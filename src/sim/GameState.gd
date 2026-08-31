extends Node
class_name GameState

const BoardStateScript = preload("res://src/sim/BoardState.gd")
const BoardGeneratorScript = preload("res://src/sim/BoardGenerator.gd")
const SquadStateScript = preload("res://src/sim/SquadState.gd")
const UnitStateScript = preload("res://src/sim/UnitState.gd")
const ControlPointStateScript = preload("res://src/sim/ControlPointState.gd")
const UnitDefsScript = preload("res://src/sim/UnitDefs.gd")
const RulesScript = preload("res://src/sim/Rules.gd")
const REINFORCE_HEAL_AMOUNT := 2

## Default match grid: ~1.5× former 9×9 linear span (round(9 * 1.5) == 14).
const DEFAULT_BOARD_SIZE := Vector2i(14, 14)

signal changed

var board
var squads := {} # int -> SquadState
var rules := RulesScript.new()

var active_player: int = 0
var turn_number: int = 1
var winner: int = -1 # -1 = none, 0 = P1, 1 = P2

var selected_squad_id: int = -1

var _next_squad_id: int = 1
var seed: int = 0

# Minimal per-player inventory for the match (unit_def_id -> count remaining).
var player_inventory := {
	0: {},
	1: {},
}

# Current 3-card offer for the active player.
var offer_pending: bool = true
var offer_cards: Array[String] = []

# Scheduled abilities (delayed strikes). Resolved in Resolver after turn_number increments.
var pending_effects: Array = []
var _next_pending_id: int = 1

func next_pending_id() -> int:
	var id := _next_pending_id
	_next_pending_id += 1
	return id

func setup(p_board_size: Vector2i, p_seed: int = 0) -> void:
	board = BoardStateScript.new(p_board_size)
	squads.clear()
	pending_effects.clear()
	_next_pending_id = 1
	active_player = 0
	turn_number = 1
	winner = -1
	selected_squad_id = -1
	_next_squad_id = 1
	if int(p_seed) != 0:
		seed = int(p_seed)
	else:
		seed = int(Time.get_unix_time_from_system())
	var gen = BoardGeneratorScript.new()
	gen.call("generate", board, seed)
	_seed_default_inventory()
	start_offer_phase()
	emit_signal("changed")

func add_squad(owner: int, cell: Vector2i, unit_def_id: String, unit_hp: int) -> int:
	# Back-compat: seed squads created via add_squad are not "fresh" gated.
	return _add_squad_internal(owner, cell, unit_def_id, unit_hp, false)

func spawn_fresh_squad(owner: int, cell: Vector2i, unit_def_id: String, unit_hp: int) -> int:
	return _add_squad_internal(owner, cell, unit_def_id, unit_hp, true)

func _add_squad_internal(owner: int, cell: Vector2i, unit_def_id: String, unit_hp: int, fresh: bool) -> int:
	var size_cat := UnitDefsScript.size_category(unit_def_id)

	var sid := _next_squad_id
	_next_squad_id += 1
	var squad := SquadStateScript.new(sid, owner, cell)
	squad.size_category = size_cat
	var ready_turn := turn_number + 1 if fresh else turn_number
	squad.units.append(UnitStateScript.new(unit_def_id, unit_hp, ready_turn))
	if fresh:
		squad.fresh_turn = turn_number
	squads[sid] = squad
	emit_signal("changed")
	return sid

func reinforce_squad(sid: int, unit_def_id: String, unit_hp: int) -> bool:
	var s = get_squad(sid)
	if s == null or not s.is_alive():
		return false
	# Fresh-unit gating: reinforcements added this turn make the squad fresh.
	s.fresh_turn = turn_number

	# Capacity rule: add a unit if squad composition allows, otherwise convert into a heal.
	if rules.can_add_unit_to_squad(s, str(unit_def_id)):
		s.units.append(UnitStateScript.new(unit_def_id, unit_hp, turn_number + 1))
		# Keep squad.size_category aligned with contained units (large if any large unit present).
		var any_large := false
		for u_any in s.units:
			var u = u_any
			if u != null and int(u.hp) > 0 and UnitDefsScript.size_category(str(u.unit_def_id)) == "large":
				any_large = true
				break
		s.size_category = "large" if any_large else "small"
		emit_signal("changed")
		return true

	var u = s.front_unit() if s.has_method("front_unit") else null
	if u == null:
		return false
	var max_hp := int(UnitDefsScript.DEFS.get(str(u.unit_def_id), {}).get("max_hp", 10))
	if int(u.hp) >= max_hp:
		return false
	u.hp = mini(max_hp, int(u.hp) + REINFORCE_HEAL_AMOUNT)
	emit_signal("changed")
	return true

func get_squad(sid: int):
	return squads.get(sid, null)

func squad_at(cell: Vector2i):
	for s in squads.values():
		var squad = s
		if squad.cell == cell and squad.is_alive():
			return squad
	return null

func cp_owner_counts() -> Dictionary:
	var counts := {0: 0, 1: 0}
	for cp in board.control_points:
		if cp.owner == 0:
			counts[0] = int(counts[0]) + 1
		elif cp.owner == 1:
			counts[1] = int(counts[1]) + 1
	return counts

func end_turn() -> void:
	for s in squads.values():
		var squad = s
		squad.tick_cooldowns()
	active_player = 1 - active_player
	turn_number += 1
	selected_squad_id = -1
	emit_signal("changed")

func _seed_default_inventory() -> void:
	# Minimal placeholder: enough copies for offline loop testing.
	var pool := {
		"soldier": 8,
		"ninja": 4,
		"engineer": 4,
		"buggy": 6,
		"tank": 4,
		"chunk": 2,
		"mrap": 3,
		"copter": 3,
	}
	player_inventory[0] = pool.duplicate(true)
	player_inventory[1] = pool.duplicate(true)

func start_offer_phase() -> void:
	offer_pending = true
	offer_cards = _generate_offer_cards(active_player, turn_number)

func clear_offer_phase() -> void:
	offer_pending = false
	offer_cards = []

func _generate_offer_cards(player: int, turn: int) -> Array[String]:
	# Deterministic 3-card offer based on (seed, player, turn).
	# Keep it tiny: sample from available inventory keys (fallback to known ids).
	var pool: Array[String] = []
	var inv: Dictionary = player_inventory.get(player, {})
	for k in inv.keys():
		if int(inv.get(k, 0)) > 0:
			pool.append(str(k))
	if pool.is_empty():
		pool = ["soldier", "archer"]

	var pool_all: Array[String] = pool.duplicate()
	pool_all.sort()
	# Remove inventory ids that cannot be played at all right now (neither spawn nor reinforce).
	# This prevents misleading offers like showing `soldier` when spawn is impossible and no RA reinforce exists.
	var filtered: Array[String] = []
	for id in pool_all:
		if _offer_is_playable_now(player, str(id)):
			filtered.append(str(id))
	if not filtered.is_empty():
		pool = filtered

	pool.sort()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed) ^ int(turn * 1315423911) ^ int(player * 2654435761)

	var cards: Array[String] = []
	var terrain_counts := _offer_terrain_counts_for_player(player)
	while cards.size() < 3:
		cards.append(_offer_weighted_pick(pool, terrain_counts, rng))

	# Stronger playability guarantee:
	# Ensure at least one offered card is currently playable via:
	# - Spawn: has a legal spawn cell AND inventory for that unit, OR
	# - Reinforce: selected squad is on RA and can accept a unit or heal.
	_offer_ensure_at_least_one_playable(cards, pool, player, rng)
	# If spawning is still possible for some inventory unit,
	# ensure at least one card can spawn — avoids "everything reinforces" draws when spawn is still legal.
	_offer_ensure_at_least_one_spawn_playable(cards, pool, player, rng)

	return cards

func _offer_terrain_counts_for_player(player: int) -> Dictionary:
	# Returns {terrain_id -> count} based on current board state.
	# Uses alive squads if present; otherwise uses the player's spawn band terrain distribution.
	var counts := {
		int(BoardStateScript.TERRAIN_SOIL): 0,
		int(BoardStateScript.TERRAIN_ROCK): 0,
		int(BoardStateScript.TERRAIN_SAND): 0,
	}
	if board == null:
		return counts

	var any_squads := false
	for s in squads.values():
		var squad = s
		if squad == null or not squad.is_alive():
			continue
		if int(squad.owner) != int(player):
			continue
		any_squads = true
		var t := int(board.terrain_at(squad.cell))
		counts[t] = int(counts.get(t, 0)) + 1

	if any_squads:
		return counts

	# No squads yet: bias using spawn-band terrain as a proxy for "local environment".
	var y0: int = 0
	var y1: int = int(board.size.y) - 1
	var min_y: int = y0 if player == 0 else maxi(y0, y1 - (RulesScript.HOME_SPAWN_ROWS - 1))
	var max_y: int = mini(y1, (RulesScript.HOME_SPAWN_ROWS - 1)) if player == 0 else y1
	for y in range(min_y, max_y + 1):
		for x in range(0, int(board.size.x)):
			var c := Vector2i(x, y)
			var t := int(board.terrain_at(c))
			counts[t] = int(counts.get(t, 0)) + 1
	return counts

func _offer_preferred_terrain_for_unit(unit_def_id: String) -> int:
	# MVP heuristic (can be upgraded to data-driven affinity later):
	# - Units that benefit more from melee like Soil (melee buff on Soil).
	# - Units that benefit more from ranged like Rock (ranged buff on Rock).
	# - Mobility/utility leaning units like Sand.
	#
	# With current placeholder unit defs, keep a stable mapping.
	match str(unit_def_id):
		"archer":
			return int(BoardStateScript.TERRAIN_ROCK)
		"ogre":
			return int(BoardStateScript.TERRAIN_SOIL)
		_:
			return int(BoardStateScript.TERRAIN_SOIL)

func _offer_weight_for_unit(unit_def_id: String, terrain_counts: Dictionary) -> int:
	var base := 10
	var pref := _offer_preferred_terrain_for_unit(unit_def_id)
	var pref_ct := int(terrain_counts.get(pref, 0))
	# Keep weights bounded and stable; counts are usually small.
	return maxi(1, base + (pref_ct * 5))

func _offer_weighted_pick(pool: Array[String], terrain_counts: Dictionary, rng: RandomNumberGenerator) -> String:
	if pool.is_empty():
		return "soldier"
	var total := 0
	for id in pool:
		total += _offer_weight_for_unit(str(id), terrain_counts)
	if total <= 0:
		return str(pool[rng.randi_range(0, pool.size() - 1)])

	var roll := rng.randi_range(1, total)
	var acc := 0
	for id in pool:
		acc += _offer_weight_for_unit(str(id), terrain_counts)
		if roll <= acc:
			return str(id)
	return str(pool[pool.size() - 1])

func _offer_has_any_playable(cards: Array[String], player: int) -> bool:
	for c in cards:
		if _offer_is_playable_now(player, str(c)):
			return true
	return false

func _offer_any_reinforce_possible(player: int, unit_def_id: String) -> bool:
	# Mirrors runtime reinforce targeting: any owned alive squad on an RA that can accept this card.
	if winner != -1:
		return false
	if not bool(offer_pending):
		return false

	var inv: Dictionary = player_inventory.get(player, {})
	if int(inv.get(unit_def_id, 0)) <= 0:
		return false

	var squad_ids: Array = squads.keys()
	squad_ids.sort()
	for sid_any in squad_ids:
		var sid := int(sid_any)
		if rules.can_play_card_reinforce(self, str(unit_def_id), sid):
			return true
	return false

func _offer_is_playable_now(player: int, unit_def_id: String) -> bool:
	if winner != -1:
		return false
	if not bool(offer_pending):
		# During generation we are in offer phase, but keep this safe for future callers.
		pass

	# Spawn playability: legal spawn cells exist AND inventory still has this unit id.
	var spawn_cells: Array[Vector2i] = rules.spawn_cells(self, player)
	if not spawn_cells.is_empty():
		var inv_spawn: Dictionary = player_inventory.get(player, {})
		if int(inv_spawn.get(unit_def_id, 0)) > 0:
			return true

	# Reinforce playability: any eligible squad on an RA (does not require pre-selection).
	if _offer_any_reinforce_possible(player, unit_def_id):
		return true

	return false

func _offer_playable_pool(pool: Array[String], player: int) -> Array[String]:
	var playable: Array[String] = []
	for id in pool:
		var uid := str(id)
		if _offer_is_playable_now(player, uid):
			playable.append(uid)
	return playable

func _offer_ensure_at_least_one_playable(cards: Array[String], pool: Array[String], player: int, rng: RandomNumberGenerator) -> void:
	if _offer_has_any_playable(cards, player):
		return
	var playable := _offer_playable_pool(pool, player)
	if playable.is_empty():
		# Nothing is playable right now (e.g. board locked + no RA reinforce/heal).
		# Keep deterministic behavior and return the drawn cards.
		return
	playable.sort()
	# Replace the first card deterministically with a playable option.
	cards[0] = str(playable[rng.randi_range(0, playable.size() - 1)])

func _offer_can_spawn_unit_now(player: int, unit_def_id: String) -> bool:
	if winner != -1:
		return false
	if not bool(offer_pending):
		return false

	var inv: Dictionary = player_inventory.get(player, {})
	if int(inv.get(unit_def_id, 0)) <= 0:
		return false

	var spawn_cells: Array[Vector2i] = rules.spawn_cells(self, player)
	if spawn_cells.is_empty():
		return false
	return true

func _offer_has_any_spawn_playable(cards: Array[String], player: int) -> bool:
	for c in cards:
		if _offer_can_spawn_unit_now(player, str(c)):
			return true
	return false

func _offer_spawn_playable_pool(pool: Array[String], player: int) -> Array[String]:
	var playable: Array[String] = []
	for id in pool:
		var uid := str(id)
		if _offer_can_spawn_unit_now(player, uid):
			playable.append(uid)
	return playable

func _offer_ensure_at_least_one_spawn_playable(cards: Array[String], pool: Array[String], player: int, rng: RandomNumberGenerator) -> void:
	# If no unit can spawn at all (no cells / no inventory), nothing to do.
	var any_spawn_exists := false
	for id in pool:
		if _offer_can_spawn_unit_now(player, str(id)):
			any_spawn_exists = true
			break
	if not any_spawn_exists:
		return

	if _offer_has_any_spawn_playable(cards, player):
		return

	var spawn_playable := _offer_spawn_playable_pool(pool, player)
	if spawn_playable.is_empty():
		return
	spawn_playable.sort()
	cards[0] = str(spawn_playable[rng.randi_range(0, spawn_playable.size() - 1)])

func _cell_to_arr(cell: Vector2i) -> Array:
	return [int(cell.x), int(cell.y)]

func _arr_to_cell(a) -> Vector2i:
	if a is Array and a.size() >= 2:
		return Vector2i(int(a[0]), int(a[1]))
	return Vector2i(0, 0)

func snapshot_dict() -> Dictionary:
	# Minimal deterministic snapshot for offline save/replay.
	var d := {}
	d["v"] = 1
	d["seed"] = int(seed)
	d["active_player"] = int(active_player)
	d["turn_number"] = int(turn_number)
	d["winner"] = int(winner)
	d["offer_pending"] = bool(offer_pending)
	d["offer_cards"] = offer_cards.duplicate()
	d["player_inventory"] = player_inventory.duplicate(true)

	var bd := {}
	if board != null:
		bd["size"] = _cell_to_arr(board.size)
		bd["terrain"] = Array(board.terrain)
		bd["reinforcement_areas"] = []
		for c in board.reinforcement_areas:
			bd["reinforcement_areas"].append(_cell_to_arr(c))
		bd["control_points"] = []
		for cp in board.control_points:
			bd["control_points"].append({
				"cell": _cell_to_arr(cp.cell),
				"owner": int(cp.owner),
				"flags": cp.flags.duplicate(true),
			})
		bd["obstacles"] = []
		var cells: Array = board.obstacles.keys()
		cells.sort_custom(func(a, b): return (a.x == b.x and a.y < b.y) or (a.x < b.x))
		for cell in cells:
			var c: Vector2i = cell
			var o = board.obstacles.get(c, null)
			if o == null:
				continue
			bd["obstacles"].append({
				"cell": _cell_to_arr(c),
				"hp": int(o.get("hp", 0)),
				"destructible": bool(o.get("destructible", false)),
			})
		bd["hazards"] = []
		var hz_cells: Array = board.hazards.keys()
		hz_cells.sort_custom(func(a, b): return (a.x == b.x and a.y < b.y) or (a.x < b.x))
		for cell in hz_cells:
			var c: Vector2i = cell
			var h = board.hazards.get(c, null)
			if h == null:
				continue
			bd["hazards"].append({
				"cell": _cell_to_arr(c),
				"kind": str(h.get("kind", "")),
				"owner": int(h.get("owner", 0)),
				"damage": int(h.get("damage", 0)),
				"splash": int(h.get("splash", 0)),
			})
	d["board"] = bd

	var squads_arr := []
	var ids: Array = squads.keys()
	ids.sort()
	for sid in ids:
		var s = get_squad(int(sid))
		if s == null:
			continue
		var units_arr := []
		for u in s.units:
			var unit = u
			if unit == null:
				continue
			units_arr.append({
				"unit_def_id": str(unit.unit_def_id),
				"hp": int(unit.hp),
				"ready_turn": int(unit.ready_turn),
			})
		squads_arr.append({
			"id": int(s.id),
			"owner": int(s.owner),
			"cell": _cell_to_arr(s.cell),
			"size_category": str(s.size_category),
			"fresh_turn": int(s.fresh_turn),
			"moved_turn": int(s.moved_turn),
			"cooldowns": s.cooldowns.duplicate(true),
			"snared_no_move_until_turn": int(s.snared_no_move_until_turn),
			"units": units_arr,
		})
	d["squads"] = squads_arr

	d["pending_effects"] = pending_effects.duplicate(true)
	d["next_pending_id"] = int(_next_pending_id)
	return d

func apply_snapshot_dict(d: Dictionary) -> void:
	# Overwrite current state from snapshot_dict().
	# Does not emit changed; caller can decide when to refresh UI.
	seed = int(d.get("seed", 0))
	active_player = int(d.get("active_player", 0))
	turn_number = int(d.get("turn_number", 1))
	winner = int(d.get("winner", -1))
	offer_pending = bool(d.get("offer_pending", false))
	offer_cards = []
	for c in d.get("offer_cards", []):
		offer_cards.append(str(c))
	player_inventory = d.get("player_inventory", {0: {}, 1: {}}).duplicate(true)

	var bd: Dictionary = d.get("board", {})
	var size := _arr_to_cell(bd.get("size", [DEFAULT_BOARD_SIZE.x, DEFAULT_BOARD_SIZE.y]))
	board = BoardStateScript.new(size)
	if bd.has("terrain"):
		var t = bd.get("terrain", [])
		board.terrain = PackedInt32Array(t)
		# Defensive: ensure correct size.
		if board.terrain.size() != size.x * size.y:
			board.terrain.resize(size.x * size.y)
			board.terrain.fill(int(BoardStateScript.TERRAIN_SOIL))
	if bd.has("reinforcement_areas"):
		board.reinforcement_areas.clear()
		for a in bd.get("reinforcement_areas", []):
			board.reinforcement_areas.append(_arr_to_cell(a))
	if bd.has("control_points"):
		board.control_points.clear()
		for cp_d_any in bd.get("control_points", []):
			var cp_d: Dictionary = cp_d_any
			var cp = ControlPointStateScript.new(_arr_to_cell(cp_d.get("cell", [0, 0])))
			cp.owner = int(cp_d.get("owner", -1))
			cp.flags = cp_d.get("flags", {0: 0, 1: 0}).duplicate(true)
			board.control_points.append(cp)
	if bd.has("obstacles"):
		board.obstacles.clear()
		for o_any in bd.get("obstacles", []):
			var o: Dictionary = o_any
			var c := _arr_to_cell(o.get("cell", [0, 0]))
			board.obstacles[c] = {"hp": int(o.get("hp", 0)), "destructible": bool(o.get("destructible", false))}
	board.hazards.clear()
	for h_any in bd.get("hazards", []):
		var h: Dictionary = h_any
		var c := _arr_to_cell(h.get("cell", [0, 0]))
		board.set_hazard(c, str(h.get("kind", "mine")), int(h.get("owner", 0)), int(h.get("damage", 2)), int(h.get("splash", 0)))

	pending_effects.clear()
	for pe_any in d.get("pending_effects", []):
		if typeof(pe_any) == TYPE_DICTIONARY:
			pending_effects.append((pe_any as Dictionary).duplicate(true))
	_next_pending_id = int(d.get("next_pending_id", 1))

	squads.clear()
	var max_id := 0
	for s_any in d.get("squads", []):
		var sd: Dictionary = s_any
		var sid := int(sd.get("id", 0))
		max_id = maxi(max_id, sid)
		var squad := SquadStateScript.new(sid, int(sd.get("owner", 0)), _arr_to_cell(sd.get("cell", [0, 0])))
		squad.size_category = str(sd.get("size_category", "small"))
		squad.fresh_turn = int(sd.get("fresh_turn", -1))
		squad.moved_turn = int(sd.get("moved_turn", -1))
		squad.cooldowns = sd.get("cooldowns", {}).duplicate(true)
		squad.snared_no_move_until_turn = int(sd.get("snared_no_move_until_turn", -1))
		squad.units.clear()
		for u_any in sd.get("units", []):
			var ud: Dictionary = u_any
			squad.units.append(UnitStateScript.new(str(ud.get("unit_def_id", "soldier")), int(ud.get("hp", 1)), int(ud.get("ready_turn", 1))))
		squads[sid] = squad
	_next_squad_id = max_id + 1
	selected_squad_id = -1

func _net_owner_from_squad_dict(sd: Dictionary) -> int:
	if sd.has("owner"):
		var ow = sd["owner"]
		if typeof(ow) == TYPE_STRING:
			return 0 if str(ow) == "A" else 1
		return int(ow)
	return 0

func _net_cell_from_squad_dict(sd: Dictionary) -> Vector2i:
	var cell_d: Dictionary = sd.get("cell", {"x": 0, "y": 0})
	return Vector2i(int(cell_d.get("x", 0)), int(cell_d.get("y", 0)))

func apply_authoritative_net_state(net: Dictionary) -> void:
	# Map server JSON into GameState. Merges squad cells when the server omits `units`
	# so optimistic local play (resolver + intent) keeps HP/loadouts while positions sync.
	selected_squad_id = -1

	var board_d: Dictionary = net.get("board", {})
	var w := int(board_d.get("w", DEFAULT_BOARD_SIZE.x))
	var h := int(board_d.get("h", DEFAULT_BOARD_SIZE.y))
	if board_d.has("size"):
		var sz = board_d.get("size")
		if sz is Array and (sz as Array).size() >= 2:
			w = int((sz as Array)[0])
			h = int((sz as Array)[1])

	if board == null or board.size != Vector2i(w, h):
		setup(Vector2i(w, h))

	active_player = 0 if str(net.get("active_player", "A")) == "A" else 1
	turn_number = int(net.get("turn", 1))
	if net.has("winner"):
		winner = int(net.get("winner", -1))
	else:
		winner = -1

	if net.has("offer_pending"):
		offer_pending = bool(net.get("offer_pending"))
		if net.has("offer_cards"):
			offer_cards.clear()
			for c in net.get("offer_cards", []):
				offer_cards.append(str(c))
	else:
		offer_pending = false
		offer_cards.clear()

	if board != null and board_d.has("hazards"):
		board.hazards.clear()
		for h_any in board_d.get("hazards", []):
			if typeof(h_any) != TYPE_DICTIONARY:
				continue
			var hz: Dictionary = h_any
			var c := _arr_to_cell(hz.get("cell", [0, 0]))
			board.set_hazard(c, str(hz.get("kind", "mine")), int(hz.get("owner", 0)), int(hz.get("damage", 2)), int(hz.get("splash", 0)))

	if net.has("pending_effects"):
		pending_effects.clear()
		for pe_any in net.get("pending_effects", []):
			if typeof(pe_any) == TYPE_DICTIONARY:
				pending_effects.append((pe_any as Dictionary).duplicate(true))
	if net.has("next_pending_id"):
		_next_pending_id = int(net.get("next_pending_id", 1))

	var incoming: Array = net.get("squads", [])
	var kept := {}
	var max_id := 0
	for s_any in incoming:
		if typeof(s_any) != TYPE_DICTIONARY:
			continue
		var sd: Dictionary = s_any
		var sid := int(sd.get("id", 0))
		if sid == 0:
			continue
		kept[sid] = true
		max_id = maxi(max_id, sid)
		var owner := _net_owner_from_squad_dict(sd)
		var cell := _net_cell_from_squad_dict(sd)
		var units_raw = sd.get("units", [])
		var has_units := units_raw is Array and (units_raw as Array).size() > 0
		var existing = squads.get(sid)

		if has_units:
			var squad := SquadStateScript.new(sid, owner, cell)
			squad.size_category = str(sd.get("size_category", "small"))
			squad.fresh_turn = int(sd.get("fresh_turn", -1))
			squad.cooldowns = sd.get("cooldowns", {}).duplicate(true)
			squad.snared_no_move_until_turn = int(sd.get("snared_no_move_until_turn", -1))
			squad.units.clear()
			for u_any in sd.get("units", []):
				var ud: Dictionary = u_any
				squad.units.append(UnitStateScript.new(str(ud.get("unit_def_id", "soldier")), int(ud.get("hp", 1)), int(ud.get("ready_turn", 1))))
			squads[sid] = squad
		elif existing != null:
			existing.cell = cell
			existing.owner = owner
		else:
			var squad2 := SquadStateScript.new(sid, owner, cell)
			squad2.size_category = "small"
			squad2.fresh_turn = -1
			squad2.cooldowns = {"melee": 0, "ranged": 0}
			squad2.units.clear()
			squad2.units.append(UnitStateScript.new("soldier", 10, turn_number))
			squads[sid] = squad2

	var to_remove: Array = []
	for sid_any in squads.keys():
		var sid2 := int(sid_any)
		if not kept.has(sid2):
			to_remove.append(sid2)
	for sidr in to_remove:
		squads.erase(sidr)

	_next_squad_id = max_id + 1
	emit_signal("changed")

