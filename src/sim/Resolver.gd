extends RefCounted
class_name Resolver

const CP_CAPTURE_FLAGS := 7
const RulesScript = preload("res://src/sim/Rules.gd")
const UnitStateScript = preload("res://src/sim/UnitState.gd")
const UnitDefsScript = preload("res://src/sim/UnitDefs.gd")
const BoardStateScript = preload("res://src/sim/BoardState.gd")
const PathfindingScript = preload("res://src/sim/Pathfinding.gd")
var rules = RulesScript.new()
var _pathfinding = PathfindingScript.new()
## ponytail: protect fresh drops from cap cull for one turn
var _gear_drop_turn: Dictionary = {} # Vector2i -> int turn_number

func _action_def_for_squad(squad, action_id: String) -> Dictionary:
	return UnitDefsScript.action_def_for_squad(squad, action_id)

func _maybe_lock_organs(gs, squad) -> void:
	if squad == null or bool(squad.organs_locked):
		return
	if not rules.is_spawn_pool_cell(gs, squad.cell, int(squad.owner)):
		squad.organs_locked = true

func _set_squad_cell(gs, squad, to_cell: Vector2i) -> void:
	if squad == null:
		return
	squad.cell = to_cell
	_maybe_lock_organs(gs, squad)

func _apply_organ_damage(gs, squad, count: int) -> void:
	# Chess 3: N damage chips front organ HP first; pop when HP reaches 0.
	if squad == null or count <= 0:
		return
	var n := int(count)
	while n > 0 and squad.is_alive():
		var idx := int(squad.front_unit_index())
		if idx < 0:
			break
		var u = squad.units[idx]
		if int(u.hp) > 1:
			u.hp = int(u.hp) - 1
			n -= 1
		else:
			var def_id := str(u.unit_def_id)
			var is_mut := bool(u.is_mutant)
			squad.units.remove_at(idx)
			_drop_gear_from_pop(gs, squad, def_id, is_mut)
			n -= 1
	_prune_orphan_cooldowns(squad)
	_check_win(gs)

func _drop_gear_from_pop(gs, squad, unit_def_id: String, is_mutant: bool) -> void:
	if gs == null or gs.board == null or squad == null:
		return
	if str(unit_def_id) == "":
		return
	# Core / brood / anchor / curses are not reclaimable gear.
	if not UnitDefsScript.is_reclaimable_gear(str(unit_def_id)):
		return
	var cell: Vector2i = squad.cell
	if not gs.board.in_bounds(cell):
		return
	var drop_cell := _resolve_gear_drop_cell(gs, cell)
	if drop_cell.x < 0:
		return
	while gs.board.gear.size() >= BoardStateScript.MAX_BOARD_GEAR:
		_prune_farthest_gear(gs, drop_cell)
	gs.board.set_gear(drop_cell, unit_def_id, is_mutant)
	_gear_drop_turn[drop_cell] = int(gs.turn_number)

func _resolve_gear_drop_cell(gs, preferred: Vector2i) -> Vector2i:
	if gs == null or gs.board == null:
		return Vector2i(-1, -1)
	# Spiral outward so multi-pops still land when the ring is mushroom-dense.
	for radius in range(0, 5):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if radius > 0 and absi(dx) != radius and absi(dy) != radius:
					continue
				var c := preferred + Vector2i(dx, dy)
				if not gs.board.in_bounds(c) or gs.board.is_blocked(c):
					continue
				if gs.board.gear.has(c) or gs.board.eggs.has(c):
					continue
				return c
	return Vector2i(-1, -1)

func _prune_farthest_gear(gs, near_cell: Vector2i) -> void:
	if gs == null or gs.board == null or gs.board.gear.is_empty():
		return
	var worst: Vector2i = Vector2i(-1, -1)
	var worst_d := -1
	# Prefer culling older drops; if all are fresh, still cull farthest to enforce cap.
	for pass_i in range(2):
		worst = Vector2i(-1, -1)
		worst_d = -1
		for c_any in gs.board.gear.keys():
			var c: Vector2i = c_any
			if c == near_cell:
				continue
			if pass_i == 0 and int(_gear_drop_turn.get(c, -999)) >= int(gs.turn_number) - 1:
				continue
			var d: int = absi(c.x - near_cell.x) + absi(c.y - near_cell.y)
			if d > worst_d or (d == worst_d and (c.x > worst.x or (c.x == worst.x and c.y > worst.y))):
				worst_d = d
				worst = c
		if worst.x >= 0:
			gs.board.remove_gear(worst)
			_gear_drop_turn.erase(worst)
			return

func _try_pickups_at_cell(gs, squad) -> void:
	if gs == null or gs.board == null or squad == null or not squad.is_alive():
		return
	if not rules.can_field_attach(squad):
		return
	var cell: Vector2i = squad.cell
	var egg = gs.board.egg_at(cell)
	if egg != null:
		var eid := str(egg.get("unit_def_id", ""))
		if eid != "":
			var hp := UnitDefsScript.max_hp_for(eid, bool(egg.get("is_mutant", false)))
			if gs.field_attach_organ(int(squad.id), eid, hp, bool(egg.get("is_mutant", false))):
				gs.board.remove_egg(cell)
	var gear = gs.board.gear_at(cell)
	if gear != null:
		var gid := str(gear.get("unit_def_id", ""))
		# Non-reclaimable leftovers stay on the floor as grayed debris — never graft.
		if gid != "" and UnitDefsScript.is_reclaimable_gear(gid):
			var hp2 := UnitDefsScript.max_hp_for(gid, bool(gear.get("is_mutant", false)))
			if gs.field_attach_organ(int(squad.id), gid, hp2, bool(gear.get("is_mutant", false))):
				gs.board.remove_gear(cell)

func _cooldown_turns_for(squad, action_def: Dictionary, action_id: String) -> int:
	var cd := int(action_def.get("cooldown", _cooldown_for(action_id)))
	if squad != null:
		cd += UnitDefsScript.ability_cooldown_penalty(squad)
	return cd

func _pop_organs(gs, squad, count: int) -> void:
	_apply_organ_damage(gs, squad, count)

func _prune_orphan_cooldowns(squad) -> void:
	# Drop cooldown keys for actions the mutant no longer has after organ pops.
	if squad == null or squad.cooldowns.is_empty():
		return
	var alive_actions := {}
	for aid in UnitDefsScript.list_action_ids_for_squad(squad):
		alive_actions[str(aid)] = true
	var drop: Array[String] = []
	for k in squad.cooldowns.keys():
		if not alive_actions.has(str(k)):
			drop.append(str(k))
	for k in drop:
		squad.cooldowns.erase(k)

func _dash_landing_cell(gs, from_cell: Vector2i, target_cell: Vector2i) -> Vector2i:
	# Deterministic: choose an adjacent cell to the target that is closest to attacker.
	# Tie-break order is stable (x direction before y direction based on relative delta).
	if gs == null or gs.board == null:
		return Vector2i(-999, -999)
	var candidates: Array[Vector2i] = [
		target_cell + Vector2i(1, 0),
		target_cell + Vector2i(-1, 0),
		target_cell + Vector2i(0, 1),
		target_cell + Vector2i(0, -1),
	]
	# Prefer the candidate with smallest distance to attacker; tie-break by fixed order above.
	var best := Vector2i(-999, -999)
	var best_d := 999999
	for c in candidates:
		if not gs.board.in_bounds(c):
			continue
		if gs.board.is_blocked(c):
			continue
		if gs.squad_at(c) != null:
			continue
		var d: int = abs(c.x - from_cell.x) + abs(c.y - from_cell.y)
		if d < best_d:
			best_d = d
			best = c
	return best

func _base_damage_for(action_id: String) -> int:
	if action_id == "melee":
		return 1
	if action_id == "ranged":
		return 1
	return 0

func _cooldown_for(action_id: String) -> int:
	if action_id == "melee":
		return 1
	if action_id == "ranged":
		return 2
	return 0

func _terrain_damage_bonus(gs, attacker, action_type: String) -> int:
	# MVP terrain effects (combat-only, deterministic):
	# - Soil: +1 melee damage
	# - Rock: +1 ranged damage
	# - Sand: no direct bonus (reserved for mobility/utility later)
	if gs == null or attacker == null:
		return 0
	var t := int(gs.board.terrain_at(attacker.cell))
	if action_type == "melee" and t == BoardStateScript.TERRAIN_SOIL:
		return 1
	if action_type == "ranged" and t == BoardStateScript.TERRAIN_ROCK:
		return 1
	return 0

func _terrain_damage_reduction(gs, defender, action_type: String) -> int:
	# MVP terrain defense:
	# - Rock: reduce incoming ranged damage by 1 (defender standing on Rock)
	if gs == null or defender == null:
		return 0
	if action_type != "ranged":
		return 0
	var t := int(gs.board.terrain_at(defender.cell))
	if t == BoardStateScript.TERRAIN_ROCK:
		return 1
	return 0

func _hp_loss_from_raw(unit_def_id: String, raw_damage: int) -> int:
	if raw_damage <= 0:
		return 0
	var af := UnitDefsScript.armor_factor(str(unit_def_id))
	if af <= 1:
		return raw_damage
	return maxi(1, int(floor(float(raw_damage) / float(af))))

func predict_attack_damage(gs, attacker_id: int, defender_id: int, action_id: String) -> Dictionary:
	# Returns deterministic breakdown for UI previews. Assumes the attack is otherwise legal.
	var a = gs.get_squad(attacker_id) if gs != null else null
	var d = gs.get_squad(defender_id) if gs != null else null
	if a == null or d == null:
		return {"total": 0, "base": 0, "attacker_bonus": 0, "defender_reduction": 0, "hp_loss": 0, "pop_emojis": "", "remain_emojis": ""}
	var action_def := _action_def_for_squad(a, action_id)
	var action_type := str(action_def.get("type", action_id))
	var base := int(action_def.get("damage", _base_damage_for(action_id)))
	var atk_bonus := _terrain_damage_bonus(gs, a, action_type)
	var def_red := _terrain_damage_reduction(gs, d, action_type)
	var raw := base + atk_bonus
	raw = maxi(1, raw - def_red) if base > 0 else 0
	# Chess 3: hp_loss == damage points applied (mutant organs may chip before popping).
	var hp_l := raw if raw > 0 and d.is_alive() else 0
	var preview := _preview_organ_damage(d, hp_l)
	return {
		"total": raw,
		"base": base,
		"attacker_bonus": atk_bonus,
		"defender_reduction": def_red,
		"hp_loss": hp_l,
		"pop_emojis": str(preview.get("pop_emojis", "")),
		"remain_emojis": str(preview.get("remain_emojis", "")),
	}

func _preview_organ_damage(squad, damage: int) -> Dictionary:
	var pop_emojis := ""
	var remain_emojis := ""
	if squad == null or damage <= 0:
		if squad != null:
			for u_any in squad.units:
				var u = u_any
				if u != null and int(u.hp) > 0:
					remain_emojis += UnitDefsScript.emoji_for(str(u.unit_def_id))
		return {"pop_emojis": pop_emojis, "remain_emojis": remain_emojis, "organs_removed": 0}
	var sim: Array = []
	for u_any in squad.units:
		var u = u_any
		if u == null or int(u.hp) <= 0:
			continue
		sim.append({"def_id": str(u.unit_def_id), "hp": int(u.hp)})
	var n := int(damage)
	var removed := 0
	while n > 0 and not sim.is_empty():
		var front: Dictionary = sim[0]
		if int(front.get("hp", 1)) > 1:
			front["hp"] = int(front.get("hp", 1)) - 1
			n -= 1
		else:
			pop_emojis += UnitDefsScript.emoji_for(str(front.get("def_id", "")))
			sim.remove_at(0)
			removed += 1
			n -= 1
	for entry_any in sim:
		var entry: Dictionary = entry_any
		remain_emojis += UnitDefsScript.emoji_for(str(entry.get("def_id", "")))
	return {"pop_emojis": pop_emojis, "remain_emojis": remain_emojis, "organs_removed": removed}

func predict_obstacle_damage(gs, attacker_id: int, cell: Vector2i, action_id: String) -> Dictionary:
	var a = gs.get_squad(attacker_id) if gs != null else null
	if a == null:
		return {"total": 0, "base": 0, "attacker_bonus": 0}
	var action_def := _action_def_for_squad(a, action_id)
	var action_type := str(action_def.get("type", action_id))
	var base := int(action_def.get("damage", _base_damage_for(action_id)))
	var atk_bonus := _terrain_damage_bonus(gs, a, action_type)
	var obs_bonus := int(action_def.get("obstacle_bonus", 0))
	var total := base + atk_bonus + obs_bonus
	return {"total": total, "base": base, "attacker_bonus": atk_bonus, "obstacle_bonus": obs_bonus}

func _apply_soil_regen(_gs) -> void:
	# Chess 3: organs are discrete 1-HP parts; soil regen disabled.
	pass

func select_squad(gs, sid: int) -> void:
	if not rules.can_select_squad(gs, sid):
		return
	gs.selected_squad_id = sid
	gs.emit_signal("changed")

func deselect(gs) -> void:
	if gs.selected_squad_id == -1:
		return
	gs.selected_squad_id = -1
	gs.emit_signal("changed")

func set_front_unit(gs, squad_id: int, unit_index: int) -> void:
	if not rules.can_set_front_unit(gs, squad_id, unit_index):
		return
	var s = gs.get_squad(squad_id)
	if s == null:
		return
	var idx := int(unit_index)
	if idx == 0:
		return
	# Move chosen alive unit to front of units[] (stable for the rest).
	var u = s.units[idx]
	s.units.remove_at(idx)
	s.units.insert(0, u)
	gs.emit_signal("changed")

func move_squad(gs, sid: int, to_cell: Vector2i) -> void:
	if not rules.can_move(gs, sid, to_cell):
		return
	var s = gs.get_squad(sid)
	_set_squad_cell(gs, s, to_cell)
	s.moved_turn = int(gs.turn_number)
	_trigger_hazard_on_enter(gs, s)
	_try_pickups_at_cell(gs, s)
	_check_win(gs)
	gs.emit_signal("changed")

func _trigger_hazard_on_enter(gs, squad) -> void:
	if gs == null or gs.board == null or squad == null:
		return
	var h = gs.board.hazard_at(squad.cell)
	if h == null:
		return
	var kind := str(h.get("kind", ""))
	var owner := int(h.get("owner", -1))
	# Friendly step: leave the trap armed for enemies (do not disarm by walking).
	if owner == int(squad.owner):
		return
	gs.board.remove_hazard(squad.cell)
	match kind:
		"mine":
			var dmg := int(h.get("damage", 2))
			_apply_front_damage_raw(gs, squad, dmg)
		"big_mine":
			var dmg := int(h.get("damage", 3))
			var spl := int(h.get("splash", 1))
			_apply_front_damage_raw(gs, squad, dmg)
			for sid_any in gs.squads.keys():
				var s2 = gs.get_squad(int(sid_any))
				if s2 == null or not s2.is_alive():
					continue
				if int(s2.id) == int(squad.id):
					continue
				var dist: int = abs(s2.cell.x - squad.cell.x) + abs(s2.cell.y - squad.cell.y)
				if dist == 1:
					_apply_front_damage_raw(gs, s2, spl)
		"snare":
			squad.snared_no_move_until_turn = int(gs.turn_number) + 2
		_:
			pass

func _apply_front_damage_raw(gs, squad, raw_damage: int) -> void:
	var extra := UnitDefsScript.extra_damage_taken(squad) + rules.swarm_stack_damage_penalty(squad)
	_pop_organs(gs, squad, int(raw_damage) + extra)

func attack(gs, attacker_id: int, defender_id: int, action_id: String) -> void:
	if not rules.can_attack(gs, attacker_id, defender_id, action_id):
		return
	var a = gs.get_squad(attacker_id)
	var d = gs.get_squad(defender_id)

	var breakdown := predict_attack_damage(gs, attacker_id, defender_id, action_id)
	var raw_primary := int(breakdown.get("total", 0))
	var hp_loss := int(breakdown.get("hp_loss", raw_primary))
	var action_def := _action_def_for_squad(a, action_id)
	var cd := _cooldown_turns_for(a, action_def, action_id)
	var aoe_radius := int(action_def.get("aoe_radius", 0))
	var aoe_splash_raw := int(action_def.get("aoe_splash", 0))
	var self_move := str(action_def.get("self_move", ""))

	if self_move == "dash_adjacent" and gs != null and a != null and d != null:
		var dist0: int = abs(a.cell.x - d.cell.x) + abs(a.cell.y - d.cell.y)
		if dist0 > 1:
			var landing := _dash_landing_cell(gs, a.cell, d.cell)
			if landing.x != -999:
				_set_squad_cell(gs, a, landing)

	_pop_organs(gs, d, hp_loss)

	if aoe_radius > 0 and aoe_splash_raw > 0 and gs != null:
		for sid_any in gs.squads.keys():
			var sid := int(sid_any)
			if sid == defender_id:
				continue
			var s2 = gs.get_squad(sid)
			if s2 == null or not s2.is_alive():
				continue
			if int(s2.owner) == int(a.owner):
				continue
			var dist: int = abs(s2.cell.x - d.cell.x) + abs(s2.cell.y - d.cell.y)
			if dist > aoe_radius:
				continue
			_pop_organs(gs, s2, aoe_splash_raw)

	a.cooldowns[action_id] = cd
	_check_win(gs)
	gs.emit_signal("changed")

func reinforce(gs, squad_id: int, unit_def_id: String, unit_hp: int) -> void:
	if not rules.can_reinforce(gs, squad_id):
		return
	gs.reinforce_squad(squad_id, unit_def_id, unit_hp)

func play_card_spawn(gs, unit_def_id: String, cell: Vector2i, is_mutant: bool = false, offer_index: int = -1) -> void:
	if not rules.can_play_card_spawn(gs, unit_def_id, cell):
		return
	var inv: Dictionary = gs.player_inventory.get(gs.active_player, {})
	if int(inv.get(unit_def_id, 0)) <= 0:
		return

	var hp := UnitDefsScript.max_hp_for(unit_def_id, is_mutant)
	# Spawn creates a new squad and marks it fresh this turn.
	var sid: int = int(gs.spawn_fresh_squad(gs.active_player, cell, unit_def_id, hp, is_mutant))
	if sid == -1:
		return

	inv[unit_def_id] = int(inv.get(unit_def_id, 0)) - 1
	gs.player_inventory[gs.active_player] = inv
	_consume_played_offer(gs, unit_def_id, offer_index)
	gs.record_offer_pick()
	gs.emit_signal("changed")

func play_card_reinforce(gs, unit_def_id: String, squad_id: int, is_mutant: bool = false, offer_index: int = -1) -> void:
	if not rules.can_play_card_reinforce(gs, unit_def_id, squad_id):
		return
	var inv: Dictionary = gs.player_inventory.get(gs.active_player, {})
	if int(inv.get(unit_def_id, 0)) <= 0:
		return

	var hp := UnitDefsScript.max_hp_for(unit_def_id, is_mutant)
	if not gs.reinforce_squad(squad_id, unit_def_id, hp, is_mutant):
		return

	inv[unit_def_id] = int(inv.get(unit_def_id, 0)) - 1
	gs.player_inventory[gs.active_player] = inv
	_consume_played_offer(gs, unit_def_id, offer_index)
	gs.record_offer_pick()
	gs.emit_signal("changed")

func _consume_played_offer(gs, unit_def_id: String, offer_index: int) -> void:
	if offer_index >= 0:
		gs.consume_offer_card_at(offer_index)
	else:
		gs.consume_offer_card(unit_def_id)

func attack_obstacle(gs, attacker_id: int, cell: Vector2i, action_id: String) -> void:
	if not rules.can_attack_obstacle(gs, attacker_id, cell, action_id):
		return
	var a = gs.get_squad(attacker_id)
	if a == null:
		return

	var breakdown := predict_obstacle_damage(gs, attacker_id, cell, action_id)
	var dmg := int(breakdown.get("total", 0))
	var action_def := _action_def_for_squad(a, action_id)
	var cd := _cooldown_turns_for(a, action_def, action_id)

	gs.board.damage_obstacle(cell, dmg)
	a.cooldowns[action_id] = cd
	gs.emit_signal("changed")

func _resolve_pending_effects(gs) -> void:
	if gs == null:
		return
	var turn := int(gs.turn_number)
	var to_run: Array = []
	var rest: Array = []
	for pe_any in gs.pending_effects:
		if typeof(pe_any) != TYPE_DICTIONARY:
			rest.append(pe_any)
			continue
		var pe: Dictionary = pe_any
		if int(pe.get("resolve_at_turn", -1)) == turn:
			to_run.append(pe)
		else:
			rest.append(pe)
	gs.pending_effects = rest
	to_run.sort_custom(func(a, b): return int(a.get("id", 0)) < int(b.get("id", 0)))
	for pe in to_run:
		var k := str(pe.get("kind", ""))
		var payload: Dictionary = pe.get("payload", {})
		match k:
			"powerstrike":
				var cell := Vector2i(int(payload.get("cx", 0)), int(payload.get("cy", 0)))
				var dmg := int(payload.get("damage", 0))
				var sv = gs.squad_at(cell)
				if sv != null and sv.is_alive():
					_apply_front_damage_raw(gs, sv, dmg)
			"eruption":
				var cell := Vector2i(int(payload.get("cx", 0)), int(payload.get("cy", 0)))
				var rad := int(payload.get("aoe_radius", 1))
				var dmg := int(payload.get("damage", 0))
				var owner := int(payload.get("attacker_owner", 0))
				for sid_any in gs.squads.keys():
					var s2 = gs.get_squad(int(sid_any))
					if s2 == null or not s2.is_alive():
						continue
					if int(s2.owner) == owner:
						continue
					var dist: int = abs(s2.cell.x - cell.x) + abs(s2.cell.y - cell.y)
					if dist <= rad:
						_apply_front_damage_raw(gs, s2, dmg)
			"airstrike":
				var cell := Vector2i(int(payload.get("cx", 0)), int(payload.get("cy", 0)))
				var dmg := int(payload.get("damage", 0))
				var owner := int(payload.get("attacker_owner", 0))
				var cells: Array[Vector2i] = [cell, cell + Vector2i(1, 0), cell + Vector2i(-1, 0), cell + Vector2i(0, 1), cell + Vector2i(0, -1)]
				for tc in cells:
					if not gs.board.in_bounds(tc):
						continue
					var s2 = gs.squad_at(tc)
					if s2 == null or not s2.is_alive():
						continue
					if int(s2.owner) == owner:
						continue
					_apply_front_damage_raw(gs, s2, dmg)
			_:
				pass
	if to_run.size() > 0:
		gs.emit_signal("changed")

func _can_use_front_action(gs, sid: int, action_id: String) -> bool:
	if gs.winner != -1:
		return false
	var s = gs.get_squad(sid)
	if s == null or not s.is_alive():
		return false
	if not s.can_act(int(gs.turn_number)):
		return false
	if s.owner != gs.active_player:
		return false
	if int(s.fresh_turn) == int(gs.turn_number):
		return false
	if int(s.cooldowns.get(action_id, 0)) > 0:
		return false
	var u = s.front_unit()
	if u == null:
		return false
	return not UnitDefsScript.action_def_for_squad(s, action_id).is_empty()

func _can_move_action(gs, sid: int, action_id: String) -> bool:
	if not _can_use_front_action(gs, sid, action_id):
		return false
	var s = gs.get_squad(sid)
	if int(gs.turn_number) < int(s.snared_no_move_until_turn):
		return false
	return true

func use_run(gs, sid: int, to_cell: Vector2i) -> void:
	if not _can_move_action(gs, sid, "run"):
		return
	var s = gs.get_squad(sid)
	var action_def := _action_def_for_squad(s, "run")
	var steps := int(action_def.get("steps", 2))
	var reachable := _pathfinding.reachable_cells(gs, sid, steps)
	if not reachable.has(to_cell):
		return
	_set_squad_cell(gs, s, to_cell)
	_trigger_hazard_on_enter(gs, s)
	_try_pickups_at_cell(gs, s)
	s.cooldowns["run"] = _cooldown_turns_for(s, action_def, "run")
	gs.emit_signal("changed")

func use_jump(gs, sid: int, to_cell: Vector2i) -> void:
	if not _can_move_action(gs, sid, "jump"):
		return
	var s = gs.get_squad(sid)
	var action_def := _action_def_for_squad(s, "jump")
	var steps := int(action_def.get("steps", 3))
	if not _pathfinding.jump_landing_legal(gs, sid, to_cell, steps):
		return
	_set_squad_cell(gs, s, to_cell)
	_trigger_hazard_on_enter(gs, s)
	_try_pickups_at_cell(gs, s)
	s.cooldowns["jump"] = _cooldown_turns_for(s, action_def, "jump")
	gs.emit_signal("changed")

func use_blink(gs, sid: int, to_cell: Vector2i) -> void:
	if not _can_move_action(gs, sid, "blink"):
		return
	var s = gs.get_squad(sid)
	var action_def := _action_def_for_squad(s, "blink")
	var r := int(action_def.get("range", 4))
	var dist := maxi(abs(to_cell.x - s.cell.x), abs(to_cell.y - s.cell.y))
	if dist > r or dist < 1:
		return
	if not gs.board.in_bounds(to_cell) or gs.board.is_blocked(to_cell):
		return
	if gs.squad_at(to_cell) != null:
		return
	_set_squad_cell(gs, s, to_cell)
	_trigger_hazard_on_enter(gs, s)
	_try_pickups_at_cell(gs, s)
	s.cooldowns["blink"] = _cooldown_turns_for(s, action_def, "blink")
	gs.emit_signal("changed")

func use_dash(gs, sid: int, to_cell: Vector2i) -> void:
	if not _can_move_action(gs, sid, "dash"):
		return
	var s = gs.get_squad(sid)
	var action_def := _action_def_for_squad(s, "dash")
	var max_steps := int(action_def.get("steps", 3))
	var path: Array = _pathfinding.path_pass_through_to(gs, sid, to_cell, max_steps)
	if path.is_empty():
		return
	var path_dmg := int(action_def.get("path_damage", 1))
	for c_any in path:
		var c: Vector2i = c_any
		if c == to_cell:
			continue
		var occ = gs.squad_at(c)
		if occ != null and occ.is_alive() and int(occ.owner) != int(s.owner):
			_apply_front_damage_raw(gs, occ, path_dmg)
	_set_squad_cell(gs, s, to_cell)
	_trigger_hazard_on_enter(gs, s)
	_try_pickups_at_cell(gs, s)
	s.cooldowns["dash"] = _cooldown_turns_for(s, action_def, "dash")
	gs.emit_signal("changed")

func use_charge(gs, attacker_id: int, defender_id: int) -> void:
	if not _can_use_front_action(gs, attacker_id, "charge"):
		return
	var a = gs.get_squad(attacker_id)
	var d = gs.get_squad(defender_id)
	if a == null or d == null or not d.is_alive():
		return
	if int(d.owner) == int(a.owner):
		return
	var action_def := _action_def_for_squad(a, "charge")
	var steps_max := int(action_def.get("steps", 2))
	var ac: Vector2i = a.cell
	var dc: Vector2i = d.cell
	if ac.x != dc.x and ac.y != dc.y:
		return
	var dx := signi(dc.x - ac.x)
	var dy := signi(dc.y - ac.y)
	var dist_ad: int = abs(dc.x - ac.x) + abs(dc.y - ac.y)
	if dist_ad < 2:
		return
	var steps_to_take: int = mini(steps_max, dist_ad - 1)
	var cur: Vector2i = ac
	for _i in range(steps_to_take):
		var nxt := Vector2i(cur.x + dx, cur.y + dy)
		if nxt == dc:
			break
		if not gs.board.in_bounds(nxt) or gs.board.is_blocked(nxt):
			return
		var occ = gs.squad_at(nxt)
		if occ != null and int(occ.id) != int(a.id):
			return
		cur = nxt
	_set_squad_cell(gs, a, cur)
	if abs(dc.x - a.cell.x) + abs(dc.y - a.cell.y) != 1:
		_set_squad_cell(gs, a, ac)
		return
	var br := predict_attack_damage(gs, attacker_id, defender_id, "charge")
	var hp_l := int(br.get("hp_loss", int(action_def.get("damage", 2))))
	_pop_organs(gs, d, hp_l)
	var push_to := Vector2i(dc.x + dx, dc.y + dy)
	if gs.board.in_bounds(push_to) and not gs.board.is_blocked(push_to) and gs.squad_at(push_to) == null:
		_set_squad_cell(gs, d, push_to)
	a.cooldowns["charge"] = _cooldown_turns_for(a, action_def, "charge")
	_trigger_hazard_on_enter(gs, a)
	_try_pickups_at_cell(gs, a)
	_check_win(gs)
	gs.emit_signal("changed")

func use_pounce(gs, sid: int, to_cell: Vector2i) -> void:
	if not _can_move_action(gs, sid, "pounce"):
		return
	var s = gs.get_squad(sid)
	var action_def := _action_def_for_squad(s, "pounce")
	var jr := int(action_def.get("jump_range", 3))
	if not _pathfinding.jump_landing_legal(gs, sid, to_cell, jr):
		return
	_set_squad_cell(gs, s, to_cell)
	_trigger_hazard_on_enter(gs, s)
	_try_pickups_at_cell(gs, s)
	var rad := int(action_def.get("aoe_radius", 1))
	var dmg := int(action_def.get("damage", 2))
	for sid_any in gs.squads.keys():
		var s2 = gs.get_squad(int(sid_any))
		if s2 == null or not s2.is_alive():
			continue
		if int(s2.owner) == int(s.owner):
			continue
		var dist: int = abs(s2.cell.x - to_cell.x) + abs(s2.cell.y - to_cell.y)
		if dist <= rad:
			_apply_front_damage_raw(gs, s2, dmg)
	s.cooldowns["pounce"] = _cooldown_turns_for(s, action_def, "pounce")
	gs.emit_signal("changed")

func use_slam(gs, sid: int) -> void:
	if not _can_use_front_action(gs, sid, "slam"):
		return
	var s = gs.get_squad(sid)
	var action_def := _action_def_for_squad(s, "slam")
	var rad := int(action_def.get("aoe_radius", 1))
	var dmg := int(action_def.get("damage", 1))
	var origin: Vector2i = s.cell
	for sid_any in gs.squads.keys():
		var s2 = gs.get_squad(int(sid_any))
		if s2 == null or not s2.is_alive():
			continue
		if int(s2.owner) == int(s.owner):
			continue
		var dist: int = abs(s2.cell.x - origin.x) + abs(s2.cell.y - origin.y)
		if dist <= rad:
			_apply_front_damage_raw(gs, s2, dmg)
	s.cooldowns["slam"] = _cooldown_turns_for(s, action_def, "slam")
	gs.emit_signal("changed")

func use_railgun(gs, attacker_id: int, defender_id: int) -> void:
	if not _can_use_front_action(gs, attacker_id, "railgun"):
		return
	var a = gs.get_squad(attacker_id)
	var d = gs.get_squad(defender_id)
	if a == null or d == null:
		return
	if int(d.owner) == int(a.owner):
		return
	var action_def := _action_def_for_squad(a, "railgun")
	var rmax := int(action_def.get("range", 4))
	var ac: Vector2i = a.cell
	var dc: Vector2i = d.cell
	if ac.x != dc.x and ac.y != dc.y:
		return
	var dx := signi(dc.x - ac.x)
	var dy := signi(dc.y - ac.y)
	var cur: Vector2i = ac
	var total_d := 0
	while total_d < rmax:
		cur = Vector2i(cur.x + dx, cur.y + dy)
		total_d += 1
		if not gs.board.in_bounds(cur):
			break
		var occ = gs.squad_at(cur)
		if occ != null and occ.is_alive() and int(occ.owner) != int(a.owner):
			var br := predict_attack_damage(gs, attacker_id, int(occ.id), "railgun")
			var hp_l := int(br.get("hp_loss", int(action_def.get("damage", 2))))
			_pop_organs(gs, occ, hp_l)
			break
	a.cooldowns["railgun"] = _cooldown_turns_for(a, action_def, "railgun")
	_check_win(gs)
	gs.emit_signal("changed")

func schedule_delayed_strike(gs, attacker_id: int, action_id: String, target_cell: Vector2i) -> void:
	if not _can_use_front_action(gs, attacker_id, action_id):
		return
	var a = gs.get_squad(attacker_id)
	var action_def := _action_def_for_squad(a, action_id)
	var r := int(action_def.get("range", 3))
	var dist: int = abs(target_cell.x - a.cell.x) + abs(target_cell.y - a.cell.y)
	if dist > r:
		return
	var kind := UnitDefsScript.action_kind(action_def)
	var pe := {
		"id": gs.next_pending_id(),
		"resolve_at_turn": int(gs.turn_number) + 1,
		"kind": action_id,
		"payload": {},
	}
	match kind:
		"delayed_single":
			var base := int(action_def.get("damage", 4))
			pe["payload"] = {"cx": target_cell.x, "cy": target_cell.y, "damage": base * 2}
			pe["kind"] = "powerstrike"
		"delayed_radius":
			var base := int(action_def.get("damage", 4))
			pe["payload"] = {
				"cx": target_cell.x,
				"cy": target_cell.y,
				"damage": base * 2,
				"aoe_radius": int(action_def.get("aoe_radius", 1)),
				"attacker_owner": int(a.owner),
			}
			pe["kind"] = "eruption"
		"delayed_area":
			var base := int(action_def.get("damage", 3))
			pe["payload"] = {"cx": target_cell.x, "cy": target_cell.y, "damage": base * 2, "attacker_owner": int(a.owner)}
			pe["kind"] = "airstrike"
		_:
			return
	gs.pending_effects.append(pe)
	a.cooldowns[action_id] = _cooldown_turns_for(a, action_def, action_id)
	gs.emit_signal("changed")

func plant_hazard(gs, sid: int, cell: Vector2i, action_id: String) -> void:
	if not _can_use_front_action(gs, sid, action_id):
		return
	var s = gs.get_squad(sid)
	var action_def := _action_def_for_squad(s, action_id)
	var r := int(action_def.get("range", 2))
	var dist: int = maxi(abs(cell.x - s.cell.x), abs(cell.y - s.cell.y))
	if dist > r:
		return
	if not gs.board.in_bounds(cell) or gs.board.is_blocked(cell):
		return
	if gs.squad_at(cell) != null:
		return
	# Hazards do not stack / overwrite — occupied trap cells are illegal plant targets.
	if gs.board.hazard_at(cell) != null:
		return
	var kind := UnitDefsScript.action_kind(action_def)
	match kind:
		"plant_mine":
			gs.board.set_hazard(cell, "mine", int(s.owner), int(action_def.get("damage", 2)), 0)
		"plant_big_mine":
			gs.board.set_hazard(cell, "big_mine", int(s.owner), int(action_def.get("damage", 3)), int(action_def.get("splash", 1)))
		"plant_snare":
			gs.board.set_hazard(cell, "snare", int(s.owner), 0, 0)
		_:
			return
	s.cooldowns[action_id] = _cooldown_turns_for(s, action_def, action_id)
	gs.emit_signal("changed")

func switch_squads(gs, caster_sid: int, sid_a: int, sid_b: int) -> void:
	if not _can_use_front_action(gs, caster_sid, "switch"):
		return
	var caster = gs.get_squad(caster_sid)
	var a = gs.get_squad(sid_a)
	var b = gs.get_squad(sid_b)
	if caster == null or a == null or b == null:
		return
	if int(a.owner) != int(b.owner):
		return
	if int(a.owner) != int(gs.active_player):
		return
	var action_def := _action_def_for_squad(caster, "switch")
	var r := int(action_def.get("range", 3))
	if abs(caster.cell.x - a.cell.x) + abs(caster.cell.y - a.cell.y) > r:
		return
	if abs(caster.cell.x - b.cell.x) + abs(caster.cell.y - b.cell.y) > r:
		return
	var ca: Vector2i = a.cell
	_set_squad_cell(gs, a, b.cell)
	_set_squad_cell(gs, b, ca)
	caster.cooldowns["switch"] = _cooldown_turns_for(caster, action_def, "switch")
	gs.emit_signal("changed")

func end_turn(gs) -> void:
	if not rules.can_end_turn(gs):
		return
	_tick_cooldowns(gs)
	_apply_soil_regen(gs)
	_apply_control_points(gs)
	_check_win(gs)
	if gs.winner != -1:
		gs.selected_squad_id = -1
		gs.emit_signal("changed")
		return

	# Advance turn (kept here so CP resolution happens before turn switch).
	gs.active_player = 1 - gs.active_player
	gs.turn_number += 1
	_resolve_pending_effects(gs)
	_check_win(gs)
	gs.selected_squad_id = -1
	if gs.winner == -1:
		gs.start_offer_phase()
	gs.emit_signal("changed")

func _tick_cooldowns(gs) -> void:
	for s in gs.squads.values():
		var squad = s
		squad.tick_cooldowns()

func _apply_control_points(gs) -> void:
	# Solo armies (1 living mutant) need one extra flag — rewards a second body for CP races.
	var alive := {0: 0, 1: 0}
	for s_any in gs.squads.values():
		var sq = s_any
		if sq != null and sq.is_alive():
			var ow := int(sq.owner)
			alive[ow] = int(alive.get(ow, 0)) + 1

	for cp in gs.board.control_points:
		var occupying := {0: false, 1: false}
		var squad_ids: Array = gs.squads.keys()
		squad_ids.sort()
		for sid in squad_ids:
			var squad = gs.get_squad(int(sid))
			if squad == null or not squad.is_alive():
				continue
			# Capture zone = CP cell + 8 neighbors (3×3).
			if gs.board.is_in_cp_zone(squad.cell, cp.cell):
				occupying[squad.owner] = true

		var p0 := bool(occupying[0])
		var p1 := bool(occupying[1])
		if p0 == p1:
			continue # contested or empty
		var player := 0 if p0 else 1
		cp.add_flag(player)
		var need := int(CP_CAPTURE_FLAGS)
		if int(alive.get(player, 0)) <= 1:
			need += 1
		if cp.flags_for(player) >= need:
			cp.owner = player
			cp.reset_flags()

func _check_win(gs) -> void:
	if gs == null or gs.winner != -1:
		return
	# Elimination: a player loses when they had squads and now have none alive.
	# `present` (any squad object, dead or alive) guards against a false win before a
	# side has spawned (e.g. at match start / net state still populating).
	var alive := {0: 0, 1: 0}
	var present := {0: 0, 1: 0}
	for s_any in gs.squads.values():
		var squad = s_any
		if squad == null:
			continue
		var ow := int(squad.owner)
		present[ow] = int(present.get(ow, 0)) + 1
		if squad.is_alive():
			alive[ow] = int(alive.get(ow, 0)) + 1
	if int(alive.get(0, 0)) > 0 and int(alive.get(1, 0)) == 0 and int(present.get(1, 0)) > 0:
		gs.winner = 0
		return
	if int(alive.get(1, 0)) > 0 and int(alive.get(0, 0)) == 0 and int(present.get(0, 0)) > 0:
		gs.winner = 1
		return

	if gs.board == null:
		return
	var total = gs.board.control_points.size()
	if total <= 0:
		return
	var majority := int(floor(total / 2.0)) + 1
	var counts = gs.cp_owner_counts()
	if int(counts.get(0, 0)) >= majority:
		gs.winner = 0
	elif int(counts.get(1, 0)) >= majority:
		gs.winner = 1

