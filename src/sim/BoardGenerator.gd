extends RefCounted
class_name BoardGenerator

const BoardStateScript = preload("res://src/sim/BoardState.gd")
const ControlPointStateScript = preload("res://src/sim/ControlPointState.gd")
const RulesScript = preload("res://src/sim/Rules.gd")
const UnitDefsScript = preload("res://src/sim/UnitDefs.gd")

func generate(board, seed: int) -> void:
	# Deterministic generation for a given seed.
	# Responsibilities:
	# - CPs: fixed MVP placement (kept here to centralize board generation).
	# - Terrain: simple distribution (soil/rock/sand).
	# - Obstacles: ~12% blockers, excluded near start zones and CP/center.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed)

	_seed_control_points(board, int(seed))
	_seed_terrain(board, rng)
	_seed_obstacles(board, rng)
	_ensure_playability_guarantees(board, rng)
	_seed_hero_props(board, rng)
	_seed_pickups(board, rng)

func _seed_pickups(board, rng: RandomNumberGenerator) -> void:
	board.gear.clear()
	board.eggs.clear()
	var center := Vector2i(int(floor(board.size.x / 2.0)), int(floor(board.size.y / 2.0)))
	var start_rows := int(RulesScript.HOME_SPAWN_ROWS) + int(RulesScript.SPAWN_EGRESS_ROWS)
	var candidates: Array[Vector2i] = []
	for y in range(board.size.y):
		for x in range(board.size.x):
			var cell := Vector2i(x, y)
			if _is_obstacle_excluded(board, cell, center, start_rows):
				continue
			if board.is_blocked(cell):
				continue
			candidates.append(cell)
	_shuffle_cells(candidates, rng)

	var gear_pool := UnitDefsScript.gear_spawn_pool()
	var egg_pool := UnitDefsScript.egg_spawn_pool()
	var gear_want := rng.randi_range(3, 5)
	var egg_want := rng.randi_range(2, 4)
	var placed: Array[Vector2i] = []

	for i in range(candidates.size()):
		if gear_want <= 0 and egg_want <= 0:
			break
		var cell := candidates[i]
		if _hero_too_close(cell, placed, 2):
			continue
		if gear_want > 0 and (egg_want <= 0 or rng.randf() < 0.55):
			var gid := str(gear_pool[rng.randi_range(0, gear_pool.size() - 1)])
			board.set_gear(cell, gid, false)
			gear_want -= 1
		elif egg_want > 0:
			var curse_pool: Array[String] = []
			var normal_pool: Array[String] = []
			for eid in egg_pool:
				if UnitDefsScript.is_curse_organ(str(eid)):
					curse_pool.append(str(eid))
				else:
					normal_pool.append(str(eid))
			var eid := ""
			if not normal_pool.is_empty() and (curse_pool.is_empty() or rng.randf() >= 0.12):
				eid = normal_pool[rng.randi_range(0, normal_pool.size() - 1)]
			elif not curse_pool.is_empty():
				eid = curse_pool[rng.randi_range(0, curse_pool.size() - 1)]
			elif not normal_pool.is_empty():
				eid = normal_pool[rng.randi_range(0, normal_pool.size() - 1)]
			if eid != "":
				board.set_egg(cell, eid, false)
				egg_want -= 1
		else:
			var gid2 := str(gear_pool[rng.randi_range(0, gear_pool.size() - 1)])
			board.set_gear(cell, gid2, false)
			gear_want -= 1
		placed.append(cell)

	_guarantee_near_spawn_gear(board, rng, gear_pool, placed)

func _guarantee_near_spawn_gear(board, rng: RandomNumberGenerator, gear_pool: Array, placed: Array) -> void:
	var anchors: Array[Vector2i] = [
		Vector2i(2, 1),
		Vector2i(board.size.x - 3, board.size.y - 2),
		Vector2i(int(floor(board.size.x / 2.0)), 1),
		Vector2i(int(floor(board.size.x / 2.0)), board.size.y - 2),
	]
	var added := 0
	for anchor in anchors:
		if added >= 2:
			break
		var has_near := false
		for c in placed:
			if absi(c.x - anchor.x) + absi(c.y - anchor.y) <= 5 and board.gear.has(c):
				has_near = true
				break
		if has_near:
			continue
		var candidates: Array[Vector2i] = []
		for dy in range(-5, 6):
			for dx in range(-5, 6):
				if absi(dx) + absi(dy) > 5:
					continue
				var cell := Vector2i(anchor.x + dx, anchor.y + dy)
				if not board.in_bounds(cell) or board.is_blocked(cell):
					continue
				if board.gear.has(cell) or board.eggs.has(cell):
					continue
				candidates.append(cell)
		if candidates.is_empty():
			continue
		var pick: Vector2i = candidates[rng.randi_range(0, candidates.size() - 1)]
		var gid := str(gear_pool[rng.randi_range(0, gear_pool.size() - 1)])
		board.set_gear(pick, gid, false)
		placed.append(pick)
		added += 1

func _seed_control_points(board, seed: int = 0) -> void:
	board.control_points.clear()
	board.reinforcement_areas.clear()
	var cx := int(floor(board.size.x / 2.0))
	# Even boards: no true mid-row. Nudge CP one step toward the second player
	# so seed%2 first-player tempo cancels the shorter home→CP path.
	var h := int(board.size.y)
	var cy := int(h / 2)
	if (h % 2) == 0:
		cy = cy - (absi(int(seed)) % 2)
	var cp_cells := [
		Vector2i(cx, cy),
		Vector2i(maxi(0, cx - 5), cy),
		Vector2i(mini(board.size.x - 1, cx + 5), cy),
	]
	for c in cp_cells:
		board.control_points.append(ControlPointStateScript.new(c))
		# Chess 3: CPs are win objectives, not organ-attach zones.

	# Attach / Spawn Pool markers: home deployment bands only.
	_append_home_band_reinforcement_areas(board)

func _ra_has_cell(board, cell: Vector2i) -> bool:
	for c in board.reinforcement_areas:
		if c == cell:
			return true
	return false

func _append_home_band_reinforcement_areas(board) -> void:
	# Mirrors `Rules.spawn_cells` row bands for P0/P1 home rows.
	var y0: int = 0
	var y1: int = int(board.size.y) - 1
	var min_y: int = y0
	var max_y: int = mini(y1, (RulesScript.HOME_SPAWN_ROWS - 1))
	for player in range(0, 2):
		if player == 1:
			min_y = maxi(y0, y1 - (RulesScript.HOME_SPAWN_ROWS - 1))
			max_y = y1
		else:
			min_y = y0
			max_y = mini(y1, (RulesScript.HOME_SPAWN_ROWS - 1))
		for y in range(min_y, max_y + 1):
			for x in range(0, int(board.size.x)):
				var c := Vector2i(x, y)
				if not _ra_has_cell(board, c):
					board.reinforcement_areas.append(c)

func _seed_terrain(board, rng: RandomNumberGenerator) -> void:
	# Simple per-cell independent sampling, stable for a given seed.
	# Bias: soil (most common), rock/sand sprinkled.
	for y in range(board.size.y):
		for x in range(board.size.x):
			var r: float = float(rng.randf())
			var t: int = int(BoardStateScript.TERRAIN_SOIL)
			if r < 0.20:
				t = int(BoardStateScript.TERRAIN_ROCK)
			elif r < 0.40:
				t = int(BoardStateScript.TERRAIN_SAND)
			board.set_terrain(Vector2i(x, y), t)

func _hero_prop_hp(kind: String) -> int:
	match kind:
		"rock":
			return 10
		"blob":
			return 5
		"mushroom":
			return 8
		_:
			return 6

func _seed_hero_props(board, rng: RandomNumberGenerator) -> void:
	# Handful of large landmarks per board, sampled from a bigger art pool.
	# Mushrooms upgrade existing blockers; blobs/rocks may add solid blockers.
	board.hero_props.clear()
	var pool: Array = []
	for i in range(6):
		pool.append({"kind": "mushroom", "variant": i})
	for i in range(1, 5):
		pool.append({"kind": "blob", "variant": i})
	for i in range(1, 5):
		pool.append({"kind": "rock", "variant": i})
	# Shuffle pool.
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp

	var want := rng.randi_range(4, 6)
	var placed_cells: Array[Vector2i] = []
	var center := Vector2i(int(floor(board.size.x / 2.0)), int(floor(board.size.y / 2.0)))
	var start_rows := int(RulesScript.HOME_SPAWN_ROWS) + int(RulesScript.SPAWN_EGRESS_ROWS)

	var mush_cands: Array[Vector2i] = []
	var free_cands: Array[Vector2i] = []
	for y in range(board.size.y):
		for x in range(board.size.x):
			var cell := Vector2i(x, y)
			if _is_obstacle_excluded(board, cell, center, start_rows):
				continue
			if board.obstacles.has(cell):
				if not board.is_destructible(cell):
					mush_cands.append(cell)
			else:
				free_cands.append(cell)
	_shuffle_cells(mush_cands, rng)
	_shuffle_cells(free_cands, rng)

	for entry_any in pool:
		if placed_cells.size() >= want:
			break
		var entry: Dictionary = entry_any
		var kind := str(entry.get("kind", ""))
		var variant := int(entry.get("variant", 0))
		var cell := Vector2i(-1, -1)
		if kind == "mushroom":
			while not mush_cands.is_empty():
				var c: Vector2i = mush_cands.pop_back()
				if _hero_too_close(c, placed_cells, 3):
					continue
				cell = c
				break
		else:
			while not free_cands.is_empty():
				var c2: Vector2i = free_cands.pop_back()
				if _hero_too_close(c2, placed_cells, 3):
					continue
				cell = c2
				break
			if cell.x < 0:
				# Fallback: claim a non-destructible mushroom cell as rock/blob art.
				while not mush_cands.is_empty():
					var c3: Vector2i = mush_cands.pop_back()
					if _hero_too_close(c3, placed_cells, 3):
						continue
					cell = c3
					break
		if cell.x < 0:
			continue
		var hp := _hero_prop_hp(kind)
		board.obstacles[cell] = {"hp": hp, "destructible": true, "prop_kind": kind}
		board.hero_props.append({
			"cell": cell,
			"kind": kind,
			"variant": variant,
		})
		placed_cells.append(cell)

func _hero_too_close(cell: Vector2i, placed: Array[Vector2i], min_manhattan: int) -> bool:
	for p in placed:
		if _manhattan(cell, p) < min_manhattan:
			return true
	return false

func _seed_obstacles(board, rng: RandomNumberGenerator) -> void:
	board.obstacles.clear()
	board.hero_props.clear()

	var total_cells: int = int(board.size.x) * int(board.size.y)
	var target_count: int = int(round(float(total_cells) * 0.12))

	var center := Vector2i(int(floor(board.size.x / 2.0)), int(floor(board.size.y / 2.0)))

	# Start zones + egress buffer: keep Spawn Pool and one row beyond clear for exits.
	var start_rows := int(RulesScript.HOME_SPAWN_ROWS) + int(RulesScript.SPAWN_EGRESS_ROWS)

	var candidates: Array[Vector2i] = []
	for y in range(board.size.y):
		for x in range(board.size.x):
			var cell := Vector2i(x, y)
			if _is_obstacle_excluded(board, cell, center, start_rows):
				continue
			candidates.append(cell)

	# Deterministic shuffle + take first N.
	_shuffle_cells(candidates, rng)
	target_count = mini(target_count, candidates.size())
	for i in range(target_count):
		var c := candidates[i]
		# Destructibles are applied in a later pass to guarantee caps/spacing.
		board.add_obstacle(c, 9999, false)

	_apply_destructible_obstacles(board, rng, start_rows)

func _is_obstacle_excluded(board, cell: Vector2i, center: Vector2i, start_rows: int) -> bool:
	# Start zone exclusions.
	if cell.y < start_rows:
		return true
	if cell.y >= board.size.y - start_rows:
		return true

	# Keep center open (small radius).
	if _manhattan(cell, center) <= 1:
		return true

	# Keep CP cells and immediate neighbors open.
	for cp in board.control_points:
		if _manhattan(cell, cp.cell) <= 1:
			return true

	return false

func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func _shuffle_cells(arr: Array[Vector2i], rng: RandomNumberGenerator) -> void:
	# Fisher–Yates
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

func _ensure_playability_guarantees(board, rng: RandomNumberGenerator) -> void:
	# Guarantees (deterministic for seed):
	# - At least one clear lane from each home band (top/bottom) to the CP row (center row).
	# - CPs are not fully isolated by obstacles.
	var h := int(board.size.y)
	if h <= 0:
		return

	var start_rows := int(RulesScript.HOME_SPAWN_ROWS)
	# Match lanes to the actual CP row (seed-nudged on even boards).
	var cy := int(h / 2)
	if not board.control_points.is_empty():
		cy = int(board.control_points[0].cell.y)
	var lane_cols := _pick_lane_columns(board, rng)

	# Carve two lanes so both players have a corridor toward the CP row.
	# (Top band: rows [0..start_rows-1], Bottom band: rows [h-start_rows..h-1])
	if lane_cols.size() >= 1:
		_carve_vertical_lane(board, lane_cols[0], start_rows - 1, cy)
	if lane_cols.size() >= 2:
		_carve_vertical_lane(board, lane_cols[1], h - start_rows, cy)
	else:
		# Fallback: if only one column was available, reuse it for both.
		_carve_vertical_lane(board, lane_cols[0], h - start_rows, cy)

	# Ensure CP neighborhoods have at least one open adjacent cell.
	for i in range(board.control_points.size()):
		var cp = board.control_points[i]
		_ensure_cp_not_isolated(board, cp.cell, rng, i)

func _pick_lane_columns(board, rng: RandomNumberGenerator) -> Array[int]:
	var w := int(board.size.x)
	var cols: Array[int] = []
	if w <= 0:
		return cols

	# Prefer interior columns (avoid walls/edges for readability).
	var candidates: Array[int] = []
	for x in range(w):
		if w >= 5 and (x == 0 or x == w - 1):
			continue
		# Avoid picking a column that is directly on a CP (keeps CP area less "railroaded").
		var ok := true
		for cp in board.control_points:
			if int(cp.cell.x) == x:
				ok = false
				break
		if ok:
			candidates.append(x)

	# Deterministic shuffle.
	for i in range(candidates.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp

	if candidates.is_empty():
		cols.append(int(floor(w / 2.0)))
		return cols

	cols.append(int(candidates[0]))
	# Pick a second lane column reasonably separated when possible.
	if candidates.size() >= 2:
		var second := int(candidates[1])
		if w >= 7:
			for k in range(1, candidates.size()):
				var x2 := int(candidates[k])
				if absi(x2 - cols[0]) >= 3:
					second = x2
					break
		cols.append(second)

	return cols

func _carve_vertical_lane(board, x: int, y_from: int, y_to: int) -> void:
	if int(board.size.x) <= 0 or int(board.size.y) <= 0:
		return
	var yy0 := clampi(y_from, 0, int(board.size.y) - 1)
	var yy1 := clampi(y_to, 0, int(board.size.y) - 1)
	var dir := 1 if yy1 >= yy0 else -1
	var y := yy0
	while true:
		var c := Vector2i(clampi(x, 0, int(board.size.x) - 1), y)
		if board.obstacles.has(c):
			board.obstacles.erase(c)
		if y == yy1:
			break
		y += dir

func _ensure_cp_not_isolated(board, cp_cell: Vector2i, rng: RandomNumberGenerator, salt: int) -> void:
	# "Not isolated" here means: at least one orthogonal neighbor is open.
	# CP cells + immediate neighbors are already excluded during placement, but lanes/destructible
	# reclassification can still result in corner cases (or future generator tweaks).
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	# Deterministic rotation based on RNG + salt.
	var rot := (rng.randi() + int(salt)) % 4
	var open_neighbors := 0
	for d in dirs:
		var n: Vector2i = cp_cell + (d as Vector2i)
		if not board.in_bounds(n):
			continue
		if not board.is_blocked(n):
			open_neighbors += 1
	if open_neighbors > 0:
		return

	for k in range(4):
		var d: Vector2i = dirs[(k + rot) % 4]
		var n: Vector2i = cp_cell + d
		if not board.in_bounds(n):
			continue
		if board.obstacles.has(n):
			board.obstacles.erase(n)
			return

func _apply_destructible_obstacles(board, rng: RandomNumberGenerator, start_rows: int) -> void:
	# Tune destructibles:
	# - Some obstacles are destructible, but capped and spaced to avoid spammy "rubble fields".
	# - Deterministic selection from the placed obstacle set.
	if board.obstacles.is_empty():
		return

	var total_obstacles := int(board.obstacles.size())
	var max_destructible := int(clampi(int(round(total_obstacles * 0.18)), 3, 12))

	# Candidate destructibles exclude areas already treated as "critical open space".
	var center := Vector2i(int(floor(board.size.x / 2.0)), int(floor(board.size.y / 2.0)))
	var candidates: Array[Vector2i] = []
	for c in board.obstacles.keys():
		var cell: Vector2i = c
		if _is_obstacle_excluded(board, cell, center, start_rows):
			continue
		candidates.append(cell)

	_shuffle_cells(candidates, rng)

	var chosen: Array[Vector2i] = []
	for cell in candidates:
		if chosen.size() >= max_destructible:
			break
		var ok := true
		for other in chosen:
			if _manhattan(cell, other) <= 2:
				ok = false
				break
		if not ok:
			continue
		chosen.append(cell)

	for cell in chosen:
		# Keep the same obstacle position, just make it destructible with low-ish HP.
		board.obstacles[cell] = {"hp": 6, "destructible": true}
