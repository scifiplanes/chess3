extends RefCounted
class_name Resolver

const CP_CAPTURE_FLAGS := 3
const RulesScript = preload("res://src/sim/Rules.gd")
const UnitStateScript = preload("res://src/sim/UnitState.gd")
const UnitDefsScript = preload("res://src/sim/UnitDefs.gd")
const BoardStateScript = preload("res://src/sim/BoardState.gd")
const PathfindingScript = preload("res://src/sim/Pathfinding.gd")
var rules = RulesScript.new()
var _pathfinding = PathfindingScript.new()

func _action_def_for_squad(squad, action_id: String) -> Dictionary:
	if squad == null:
		return {}
	var u = squad.front_unit()
	if u == null:
		return {}
	return UnitDefsScript.action_def(str(u.unit_def_id), action_id)

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
		return 3
	if action_id == "ranged":
		return 2
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
		return {"total": 0, "base": 0, "attacker_bonus": 0, "defender_reduction": 0, "hp_loss": 0}
	var action_def := _action_def_for_squad(a, action_id)
	var action_type := str(action_def.get("type", action_id))
	var base := int(action_def.get("damage", _base_damage_for(action_id)))
	var atk_bonus := _terrain_damage_bonus(gs, a, action_type)
	var def_red := _terrain_damage_reduction(gs, d, action_type)
	var raw := base + atk_bonus
	raw = maxi(1, raw - def_red) if base > 0 else 0
	var du = d.front_unit()
	var hp_l := 0
	if du != null and raw > 0:
		hp_l = _hp_loss_from_raw(str(du.unit_def_id), raw)
	return {"total": raw, "base": base, "attacker_bonus": atk_bonus, "defender_reduction": def_red, "hp_loss": hp_l}

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

func _apply_soil_regen(gs) -> void:
	# MVP sustain:
	# - Soil: heal front alive unit by +1 at end of turn, up to its max_hp.
	if gs == null or gs.board == null:
		return
	for s_any in gs.squads.values():
		var s = s_any
		if s == null or not s.is_alive():
			continue
		var t := int(gs.board.terrain_at(s.cell))
		if t != BoardStateScript.TERRAIN_SOIL:
			continue
		var u = s.front_unit()
		if u == null:
			continue
		var max_hp := int(UnitDefsScript.DEFS.get(str(u.unit_def_id), {}).get("max_hp", 10))
		u.hp = mini(max_hp, int(u.hp) + 1)

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
	s.cell = to_cell
	s.moved_turn = int(gs.turn_number)
	_trigger_hazard_on_enter(gs, s)
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
	gs.board.remove_hazard(squad.cell)
	if owner == int(squad.owner):
		return
	match kind:
		"mine":
			var dmg := int(h.get("damage", 3))
			_apply_front_damage_raw(gs, squad, dmg)
		"big_mine":
			var dmg := int(h.get("damage", 4))
			var spl := int(h.get("splash", 2))
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
	if squad == null or not squad.is_alive():
		return
	var idx := int(squad.front_unit_index())
	if idx < 0:
		return
	var u = squad.units[idx]
	var loss := _hp_loss_from_raw(str(u.unit_def_id), int(raw_damage))
	u.hp = maxi(0, int(u.hp) - loss)
	_check_win(gs)

func attack(gs, attacker_id: int, defender_id: int, action_id: String) -> void:
	if not rules.can_attack(gs, attacker_id, defender_id, action_id):
		return
	var a = gs.get_squad(attacker_id)
	var d = gs.get_squad(defender_id)

	var breakdown := predict_attack_damage(gs, attacker_id, defender_id, action_id)
	var raw_primary := int(breakdown.get("total", 0))
	var hp_loss := int(breakdown.get("hp_loss", raw_primary))
	var action_def := _action_def_for_squad(a, action_id)
	var cd := int(action_def.get("cooldown", _cooldown_for(action_id)))
	var aoe_radius := int(action_def.get("aoe_radius", 0))
	var aoe_splash_raw := int(action_def.get("aoe_splash", 0))
	var self_move := str(action_def.get("self_move", ""))

	if self_move == "dash_adjacent" and gs != null and a != null and d != null:
		var dist0: int = abs(a.cell.x - d.cell.x) + abs(a.cell.y - d.cell.y)
		if dist0 > 1:
			var landing := _dash_landing_cell(gs, a.cell, d.cell)
			if landing.x != -999:
				a.cell = landing

	var idx := int(d.front_unit_index())
	if idx < 0:
		return
	d.units[idx].hp = maxi(0, int(d.units[idx].hp) - hp_loss)

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
			var idx2 := int(s2.front_unit_index())
			if idx2 < 0:
				continue
			var u2 = s2.units[idx2]
			var spl_hp := _hp_loss_from_raw(str(u2.unit_def_id), aoe_splash_raw)
			s2.units[idx2].hp = maxi(0, int(s2.units[idx2].hp) - spl_hp)

	a.cooldowns[action_id] = cd
	if int(d.units[idx].hp) <= 0:
		# Keep the squad object but mark as dead via hp == 0.
		pass
	_check_win(gs)
	gs.emit_signal("changed")

func reinforce(gs, squad_id: int, unit_def_id: String, unit_hp: int) -> void:
	if not rules.can_reinforce(gs, squad_id):
		return
	gs.reinforce_squad(squad_id, unit_def_id, unit_hp)

func play_card_spawn(gs, unit_def_id: String, cell: Vector2i) -> void:
	if not rules.can_play_card_spawn(gs, unit_def_id, cell):
		return
	var inv: Dictionary = gs.player_inventory.get(gs.active_player, {})
	if int(inv.get(unit_def_id, 0)) <= 0:
		return

	var hp := _unit_max_hp(unit_def_id)
	# Spawn creates a new squad and marks it fresh this turn.
	var sid: int = int(gs.spawn_fresh_squad(gs.active_player, cell, unit_def_id, hp))
	if sid == -1:
		return

	inv[unit_def_id] = int(inv.get(unit_def_id, 0)) - 1
	gs.player_inventory[gs.active_player] = inv
	gs.clear_offer_phase()
	gs.emit_signal("changed")

func play_card_reinforce(gs, unit_def_id: String, squad_id: int) -> void:
	if not rules.can_play_card_reinforce(gs, unit_def_id, squad_id):
		return
	var inv: Dictionary = gs.player_inventory.get(gs.active_player, {})
	if int(inv.get(unit_def_id, 0)) <= 0:
		return

	var hp := _unit_max_hp(unit_def_id)
	if not gs.reinforce_squad(squad_id, unit_def_id, hp):
		return

	inv[unit_def_id] = int(inv.get(unit_def_id, 0)) - 1
	gs.player_inventory[gs.active_player] = inv
	gs.clear_offer_phase()
	gs.emit_signal("changed")

func _unit_max_hp(unit_def_id: String) -> int:
	var d = UnitDefsScript.DEFS.get(unit_def_id, null)
	if d == null:
		return 10
	return int(d.get("max_hp", 10))

func attack_obstacle(gs, attacker_id: int, cell: Vector2i, action_id: String) -> void:
	if not rules.can_attack_obstacle(gs, attacker_id, cell, action_id):
		return
	var a = gs.get_squad(attacker_id)
	if a == null:
		return

	var breakdown := predict_obstacle_damage(gs, attacker_id, cell, action_id)
	var dmg := int(breakdown.get("total", 0))
	var action_def := _action_def_for_squad(a, action_id)
	var cd := int(action_def.get("cooldown", _cooldown_for(action_id)))

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
	return not UnitDefsScript.action_def(str(u.unit_def_id), action_id).is_empty()

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
	s.cell = to_cell
	_trigger_hazard_on_enter(gs, s)
	s.cooldowns["run"] = int(action_def.get("cooldown", 2))
	gs.emit_signal("changed")

func use_jump(gs, sid: int, to_cell: Vector2i) -> void:
	if not _can_move_action(gs, sid, "jump"):
		return
	var s = gs.get_squad(sid)
	var action_def := _action_def_for_squad(s, "jump")
	var steps := int(action_def.get("steps", 3))
	if not _pathfinding.jump_landing_legal(gs, sid, to_cell, steps):
		return
	s.cell = to_cell
	_trigger_hazard_on_enter(gs, s)
	s.cooldowns["jump"] = int(action_def.get("cooldown", 2))
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
	s.cell = to_cell
	_trigger_hazard_on_enter(gs, s)
	s.cooldowns["blink"] = int(action_def.get("cooldown", 3))
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
	var path_dmg := int(action_def.get("path_damage", 2))
	for c_any in path:
		var c: Vector2i = c_any
		if c == to_cell:
			continue
		var occ = gs.squad_at(c)
		if occ != null and occ.is_alive() and int(occ.owner) != int(s.owner):
			_apply_front_damage_raw(gs, occ, path_dmg)
	s.cell = to_cell
	_trigger_hazard_on_enter(gs, s)
	s.cooldowns["dash"] = int(action_def.get("cooldown", 3))
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
	a.cell = cur
	if abs(dc.x - a.cell.x) + abs(dc.y - a.cell.y) != 1:
		a.cell = ac
		return
	var br := predict_attack_damage(gs, attacker_id, defender_id, "charge")
	var hp_l := int(br.get("hp_loss", int(action_def.get("damage", 3))))
	var idx := int(d.front_unit_index())
	if idx >= 0:
		d.units[idx].hp = maxi(0, int(d.units[idx].hp) - hp_l)
	var push_to := Vector2i(dc.x + dx, dc.y + dy)
	if gs.board.in_bounds(push_to) and not gs.board.is_blocked(push_to) and gs.squad_at(push_to) == null:
		d.cell = push_to
	a.cooldowns["charge"] = int(action_def.get("cooldown", 3))
	_trigger_hazard_on_enter(gs, a)
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
	s.cell = to_cell
	_trigger_hazard_on_enter(gs, s)
	var rad := int(action_def.get("aoe_radius", 1))
	var dmg := int(action_def.get("damage", 3))
	for sid_any in gs.squads.keys():
		var s2 = gs.get_squad(int(sid_any))
		if s2 == null or not s2.is_alive():
			continue
		if int(s2.owner) == int(s.owner):
			continue
		var dist: int = abs(s2.cell.x - to_cell.x) + abs(s2.cell.y - to_cell.y)
		if dist <= rad:
			_apply_front_damage_raw(gs, s2, dmg)
	s.cooldowns["pounce"] = int(action_def.get("cooldown", 3))
	gs.emit_signal("changed")

func use_slam(gs, sid: int) -> void:
	if not _can_use_front_action(gs, sid, "slam"):
		return
	var s = gs.get_squad(sid)
	var action_def := _action_def_for_squad(s, "slam")
	var rad := int(action_def.get("aoe_radius", 1))
	var dmg := int(action_def.get("damage", 2))
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
	s.cooldowns["slam"] = int(action_def.get("cooldown", 3))
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
			var hp_l := int(br.get("hp_loss", int(action_def.get("damage", 3))))
			var idx := int(occ.front_unit_index())
			if idx >= 0:
				occ.units[idx].hp = maxi(0, int(occ.units[idx].hp) - hp_l)
			break
	a.cooldowns["railgun"] = int(action_def.get("cooldown", 2))
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
	a.cooldowns[action_id] = int(action_def.get("cooldown", 4))
	gs.emit_signal("changed")

func plant_hazard(gs, sid: int, cell: Vector2i, action_id: String) -> void:
	if not _can_use_front_action(gs, sid, action_id):
		return
	var s = gs.get_squad(sid)
	var action_def := _action_def_for_squad(s, action_id)
	var r := int(action_def.get("range", 2))
	var dist: int = abs(cell.x - s.cell.x) + abs(cell.y - s.cell.y)
	if dist > r:
		return
	if not gs.board.in_bounds(cell) or gs.board.is_blocked(cell):
		return
	if gs.squad_at(cell) != null:
		return
	var kind := UnitDefsScript.action_kind(action_def)
	match kind:
		"plant_mine":
			gs.board.set_hazard(cell, "mine", int(s.owner), int(action_def.get("damage", 4)), 0)
		"plant_big_mine":
			gs.board.set_hazard(cell, "big_mine", int(s.owner), int(action_def.get("damage", 4)), int(action_def.get("splash", 2)))
		"plant_snare":
			gs.board.set_hazard(cell, "snare", int(s.owner), 0, 0)
		_:
			return
	s.cooldowns[action_id] = int(action_def.get("cooldown", 3))
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
	a.cell = b.cell
	b.cell = ca
	caster.cooldowns["switch"] = int(action_def.get("cooldown", 4))
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
	for cp in gs.board.control_points:
		var adjacent := {0: false, 1: false}
		var squad_ids: Array = gs.squads.keys()
		squad_ids.sort()
		for sid in squad_ids:
			var squad = gs.get_squad(int(sid))
			if squad == null or not squad.is_alive():
				continue
			# Occupy or orthogonally adjacent (Manhattan <= 1).
			var dist = abs(squad.cell.x - cp.cell.x) + abs(squad.cell.y - cp.cell.y)
			if dist <= 1:
				adjacent[squad.owner] = true

		var p0 := bool(adjacent[0])
		var p1 := bool(adjacent[1])
		if p0 == p1:
			continue # contested or empty
		var player := 0 if p0 else 1
		cp.add_flag(player)
		if cp.flags_for(player) >= CP_CAPTURE_FLAGS:
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

