extends RefCounted
class_name BoardGenerator

const BoardStateScript = preload("res://src/sim/BoardState.gd")
const ControlPointStateScript = preload("res://src/sim/ControlPointState.gd")
const RulesScript = preload("res://src/sim/Rules.gd")

func generate(board, seed: int) -> void:
	# Deterministic generation for a given seed.
	# Responsibilities:
	# - CPs: fixed MVP placement (kept here to centralize board generation).
	# - Terrain: simple distribution (soil/rock/sand).
	# - Obstacles: ~12% blockers, excluded near start zones and CP/center.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed)

	_seed_control_points(board)
	_seed_terrain(board, rng)
	_seed_obstacles(board, rng)
	_ensure_playability_guarantees(board, rng)

func _seed_control_points(board) -> void:
	board.control_points.clear()
	board.reinforcement_areas.clear()
	var cx := int(floor(board.size.x / 2.0))
	var cy := int(floor(board.size.y / 2.0))
	# Deterministic MVP CP placement: center + two symmetric points along x.
	var cp_cells := [
		Vector2i(cx, cy),
		Vector2i(maxi(0, cx - 2), cy),
		Vector2i(mini(board.size.x - 1, cx + 2), cy),
	]
	for c in cp_cells:
		board.control_points.append(ControlPointStateScript.new(c))
		# MVP reinforcement areas: CP cells.
		board.reinforcement_areas.append(c)

	# Reinforcement can also happen in each player's home/deployment bands (same rows as spawn cells).
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

func _seed_obstacles(board, rng: RandomNumberGenerator) -> void:
	board.obstacles.clear()

	var total_cells: int = int(board.size.x) * int(board.size.y)
	var target_count: int = int(round(float(total_cells) * 0.12))

	var center := Vector2i(int(floor(board.size.x / 2.0)), int(floor(board.size.y / 2.0)))

	# Start zones (MVP): top/bottom HOME_SPAWN_ROWS rows (see Rules).
	# Obstacles are excluded from these rows for initial placements.
	var start_rows := int(RulesScript.HOME_SPAWN_ROWS)

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
	var cy := int(floor(board.size.y / 2.0))
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
