extends RefCounted
class_name Rules

const MOVE_RANGE := 3
const HOME_SPAWN_ROWS := 2
# Per-squad composition (from `UnitDefs.size`):
# Up to 3 small-class units + 1 large-class unit (4 alive units max) in a single squad.
const SQUAD_MAX_SMALL_UNITS := 3
const SQUAD_MAX_LARGE_UNITS := 1
const SQUAD_MAX_TOTAL_UNITS := SQUAD_MAX_SMALL_UNITS + SQUAD_MAX_LARGE_UNITS
const BoardStateScript = preload("res://src/sim/BoardState.gd")
const UnitDefsScript = preload("res://src/sim/UnitDefs.gd")

func _unit_size_category(unit_def_id: String) -> String:
	var cat := UnitDefsScript.size_category(unit_def_id)
	return "large" if cat == "large" else "small"

func squad_alive_unit_counts(squad) -> Dictionary:
	var out := {"small": 0, "large": 0, "total": 0}
	if squad == null:
		return out
	for u_any in squad.units:
		var u = u_any
		if u == null or int(u.hp) <= 0:
			continue
		var cat := _unit_size_category(str(u.unit_def_id))
		out[cat] = int(out.get(cat, 0)) + 1
		out["total"] = int(out["total"]) + 1
	return out

func can_add_unit_to_squad(squad, unit_def_id: String) -> bool:
	if squad == null or not squad.is_alive():
		return false
	var incoming := _unit_size_category(str(unit_def_id))
	var c := squad_alive_unit_counts(squad)
	if int(c.get("total", 0)) >= SQUAD_MAX_TOTAL_UNITS:
		return false
	if incoming == "large":
		return int(c.get("large", 0)) < SQUAD_MAX_LARGE_UNITS
	return int(c.get("small", 0)) < SQUAD_MAX_SMALL_UNITS

func move_range_for_squad(gs, squad) -> int:
	# MVP terrain movement modifier:
	# - Sand: +1 move range for squads standing on Sand.
	if gs == null or squad == null or gs.board == null:
		return MOVE_RANGE
	var t := int(gs.board.terrain_at(squad.cell))
	if t == BoardStateScript.TERRAIN_SAND:
		return MOVE_RANGE + 1
	return MOVE_RANGE

func can_select_squad(gs, sid: int) -> bool:
	if gs.winner != -1:
		return false
	var s = gs.get_squad(sid)
	return s != null and s.is_alive() and s.owner == gs.active_player

func can_set_front_unit(gs, squad_id: int, unit_index: int) -> bool:
	# Purely a formation/UI action: allow any time during your turn, as long as the squad is selectable.
	if not can_select_squad(gs, squad_id):
		return false
	var s = gs.get_squad(squad_id)
	if s == null:
		return false
	if unit_index < 0 or unit_index >= int(s.units.size()):
		return false
	var u = s.units[unit_index]
	return u != null and int(u.hp) > 0

func can_end_turn(gs) -> bool:
	return gs.winner == -1

func _squad_can_attempt_basic_move(gs, s) -> bool:
	if gs == null or s == null or not s.is_alive():
		return false
	if gs.winner != -1:
		return false
	if not s.can_act(int(gs.turn_number)):
		return false
	if int(s.owner) != int(gs.active_player):
		return false
	if int(s.fresh_turn) == int(gs.turn_number):
		return false
	if int(s.moved_turn) == int(gs.turn_number):
		return false
	if int(gs.turn_number) < int(s.snared_no_move_until_turn):
		return false
	return true

func can_move(gs, sid: int, to_cell: Vector2i) -> bool:
	var s = gs.get_squad(sid)
	if not _squad_can_attempt_basic_move(gs, s):
		return false
	if not gs.board.in_bounds(to_cell):
		return false
	if gs.board.is_blocked(to_cell):
		return false
	if gs.squad_at(to_cell) != null:
		return false
	var reachable := _pathfinding.reachable_cells(gs, sid, move_range_for_squad(gs, s))
	return reachable.has(to_cell)

## Authoritative net server v0 ignores terrain pathing; match that so local validation does not reject intent.
func can_move_for_net_intent(gs, sid: int, to_cell: Vector2i) -> bool:
	var s = gs.get_squad(sid)
	if not _squad_can_attempt_basic_move(gs, s):
		return false
	if not gs.board.in_bounds(to_cell):
		return false
	if gs.squad_at(to_cell) != null:
		return false
	var budget: int = int(gs.board.size.x) + int(gs.board.size.y) + 4
	var reachable := _pathfinding.reachable_cells(gs, sid, maxi(budget, move_range_for_squad(gs, s)), true, true)
	return reachable.has(to_cell)

## True if this squad still has a legal basic Move destination this turn.
func squad_has_available_move(gs, sid: int) -> bool:
	var s = gs.get_squad(sid)
	if not _squad_can_attempt_basic_move(gs, s):
		return false
	var reachable := _pathfinding.reachable_cells(gs, sid, move_range_for_squad(gs, s))
	for cell_any in reachable.keys():
		var cell: Vector2i = cell_any
		if cell == s.cell:
			continue
		if int(reachable.get(cell, 0)) > 0:
			return true
	return false

## True if front unit has any ability off cooldown (button would be enabled).
func squad_has_available_action(gs, sid: int) -> bool:
	if gs == null or gs.winner != -1:
		return false
	var s = gs.get_squad(sid)
	if s == null or not s.is_alive():
		return false
	if not s.can_act(int(gs.turn_number)):
		return false
	if int(s.owner) != int(gs.active_player):
		return false
	if int(s.fresh_turn) == int(gs.turn_number):
		return false
	var u = s.front_unit() if s.has_method("front_unit") else null
	if u == null:
		return false
	var ids: Array[String] = UnitDefsScript.list_action_ids(str(u.unit_def_id))
	for aid in ids:
		if int(s.cooldowns.get(aid, 0)) <= 0:
			return true
	return false

func active_player_has_available_move_or_action(gs) -> bool:
	if gs == null or gs.winner != -1:
		return false
	if bool(gs.offer_pending):
		return false
	var ids: Array = gs.squads.keys()
	ids.sort()
	for sid_any in ids:
		var sid := int(sid_any)
		if squad_has_available_move(gs, sid) or squad_has_available_action(gs, sid):
			return true
	return false

func can_attack(gs, attacker_id: int, defender_id: int, action_id: String) -> bool:
	if gs.winner != -1:
		return false
	var a = gs.get_squad(attacker_id)
	var d = gs.get_squad(defender_id)
	if a == null or d == null:
		return false
	if not a.is_alive() or not d.is_alive():
		return false
	if not a.can_act(int(gs.turn_number)):
		return false
	if a.owner != gs.active_player:
		return false
	if int(a.fresh_turn) == int(gs.turn_number):
		return false
	if d.owner == gs.active_player:
		return false
	if int(a.cooldowns.get(action_id, 0)) > 0:
		return false

	var u = a.front_unit()
	if u == null:
		return false
	var action_def: Dictionary = UnitDefsScript.action_def(str(u.unit_def_id), action_id)
	if action_def.is_empty():
		return false
	var r := int(action_def.get("range", 1))
	var dist: int = abs(a.cell.x - d.cell.x) + abs(a.cell.y - d.cell.y)
	if dist > r:
		return false

	var self_move := str(action_def.get("self_move", ""))
	if self_move == "dash_adjacent" and dist > 1:
		if gs == null or gs.board == null:
			return false
		# Must have a legal landing cell adjacent to the defender.
		var target_cell: Vector2i = d.cell
		var candidates: Array[Vector2i] = [
			target_cell + Vector2i(1, 0),
			target_cell + Vector2i(-1, 0),
			target_cell + Vector2i(0, 1),
			target_cell + Vector2i(0, -1),
		]
		var best_d: int = 999999
		var found := false
		for c in candidates:
			if not gs.board.in_bounds(c):
				continue
			if gs.board.is_blocked(c):
				continue
			if gs.squad_at(c) != null:
				continue
			var dd: int = abs(c.x - a.cell.x) + abs(c.y - a.cell.y)
			if dd < best_d:
				best_d = dd
				found = true
		if not found:
			return false

	var ak := UnitDefsScript.action_kind(action_def)
	if ak == "railgun":
		if a.cell.x != d.cell.x and a.cell.y != d.cell.y:
			return false
		var dx := signi(d.cell.x - a.cell.x)
		var dy := signi(d.cell.y - a.cell.y)
		var cur: Vector2i = a.cell
		while cur != d.cell:
			cur = Vector2i(cur.x + dx, cur.y + dy)
			if not gs.board.in_bounds(cur):
				return false
			var occ = gs.squad_at(cur)
			if occ != null and int(occ.id) != int(d.id):
				return false
	if ak == "charge":
		if a.cell.x != d.cell.x and a.cell.y != d.cell.y:
			return false
		var dx2 := signi(d.cell.x - a.cell.x)
		var dy2 := signi(d.cell.y - a.cell.y)
		var cur2: Vector2i = a.cell
		while cur2 != d.cell:
			var nxt2 := Vector2i(cur2.x + dx2, cur2.y + dy2)
			if nxt2 == d.cell:
				break
			if not gs.board.in_bounds(nxt2) or gs.board.is_blocked(nxt2):
				return false
			var occ2 = gs.squad_at(nxt2)
			if occ2 != null:
				return false
			cur2 = nxt2
	return true

func can_attack_obstacle(gs, attacker_id: int, cell: Vector2i, action_id: String) -> bool:
	if gs.winner != -1:
		return false
	var a = gs.get_squad(attacker_id)
	if a == null or not a.is_alive():
		return false
	if not a.can_act(int(gs.turn_number)):
		return false
	if a.owner != gs.active_player:
		return false
	if int(a.fresh_turn) == int(gs.turn_number):
		return false
	if not gs.board.in_bounds(cell):
		return false
	if not gs.board.is_blocked(cell):
		return false
	if not gs.board.is_destructible(cell):
		return false
	if int(a.cooldowns.get(action_id, 0)) > 0:
		return false

	var u = a.front_unit()
	if u == null:
		return false
	var action_def: Dictionary = UnitDefsScript.action_def(str(u.unit_def_id), action_id)
	if action_def.is_empty():
		return false
	var r := int(action_def.get("range", 1))
	var dist: int = abs(a.cell.x - cell.x) + abs(a.cell.y - cell.y)
	return dist <= r

func spawn_cells(gs, player: int) -> Array[Vector2i]:
	var base: Array[Vector2i] = _spawn_cells_base(gs, player)
	var extra: Dictionary = {}
	for c in base:
		extra[c] = true
	for c2 in _logistics_spawn_extra_cells(gs, player):
		extra[c2] = true
	var out: Array[Vector2i] = []
	for k in extra.keys():
		out.append(k)
	out.sort_custom(func(a, b): return (a.x == b.x and a.y < b.y) or (a.x < b.x))
	return out

func _spawn_cells_base(gs, player: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var y0: int = 0
	var y1: int = int(gs.board.size.y) - 1
	var min_y: int = y0 if player == 0 else maxi(y0, y1 - (HOME_SPAWN_ROWS - 1))
	var max_y: int = mini(y1, (HOME_SPAWN_ROWS - 1)) if player == 0 else y1
	for y in range(min_y, max_y + 1):
		for x in range(0, gs.board.size.x):
			var c := Vector2i(x, y)
			if gs.board.is_blocked(c):
				continue
			if gs.squad_at(c) != null:
				continue
			cells.append(c)
	return cells

func can_reinforce(gs, squad_id: int) -> bool:
	if gs.winner != -1:
		return false
	var s = gs.get_squad(squad_id)
	if s == null or not s.is_alive():
		return false
	if int(s.owner) != int(gs.active_player):
		return false
	return gs.board.is_reinforcement_area(s.cell)

func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(abs(a.x - b.x), abs(a.y - b.y))

func _logistics_spawn_extra_cells(gs, player: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if gs == null or gs.board == null:
		return out
	var squad_ids: Array = gs.squads.keys()
	squad_ids.sort()
	for sid_any in squad_ids:
		var s = gs.get_squad(int(sid_any))
		if s == null or not s.is_alive():
			continue
		if int(s.owner) != int(player):
			continue
		var u = s.front_unit()
		if u == null:
			continue
		var tags: Array = UnitDefsScript.unit_tags(str(u.unit_def_id))
		var has_log := tags.has("logistics")
		var has_fob := tags.has("fob")
		if not has_log and not has_fob:
			continue
		var origin: Vector2i = s.cell
		for y in range(0, int(gs.board.size.y)):
			for x in range(0, int(gs.board.size.x)):
				var c := Vector2i(x, y)
				if gs.board.is_blocked(c):
					continue
				if gs.squad_at(c) != null:
					continue
				var ch := _chebyshev(origin, c)
				if has_log and ch <= 1:
					out.append(c)
				elif has_fob:
					var dx: int = abs(c.x - origin.x)
					var dy: int = abs(c.y - origin.y)
					if dx + dy <= 2 and (dx == 0 or dy == 0):
						out.append(c)
	return out

func is_reinforcement_area(gs, cell: Vector2i, player: int) -> bool:
	# Plan C RA: explicit board-marked reinforcement area cells.
	# (player arg kept for back-compat with existing call sites)
	return gs.board.is_reinforcement_area(cell)

func can_play_card_spawn(gs, unit_def_id: String, cell: Vector2i) -> bool:
	if gs.winner != -1:
		return false
	if not bool(gs.offer_pending):
		return false
	if not gs.board.in_bounds(cell):
		return false
	if gs.board.is_blocked(cell):
		return false
	if gs.squad_at(cell) != null:
		return false
	var legal := spawn_cells(gs, gs.active_player)
	return legal.has(cell)

func can_play_card_reinforce(gs, unit_def_id: String, squad_id: int) -> bool:
	if gs.winner != -1:
		return false
	if not bool(gs.offer_pending):
		return false
	var s = gs.get_squad(squad_id)
	if s == null or not s.is_alive():
		return false
	if s.owner != gs.active_player:
		return false
	if not is_reinforcement_area(gs, s.cell, gs.active_player):
		return false

	# Reinforce is explicit:
	# - If squad has capacity under the small/large composition cap: add a unit.
	# - If squad cannot accept another unit: card may be played to heal front unit (only if it isn't at max HP).
	if can_add_unit_to_squad(s, str(unit_def_id)):
		return true
	var u = s.front_unit() if s.has_method("front_unit") else null
	if u == null:
		return false
	var max_hp := int(UnitDefsScript.DEFS.get(str(u.unit_def_id), {}).get("max_hp", 10))
	return int(u.hp) < max_hp

const PathfindingScript = preload("res://src/sim/Pathfinding.gd")
var _pathfinding = PathfindingScript.new()

