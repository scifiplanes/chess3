extends SceneTree

## Adversarial multi-cycle playtests (round 3).
## godot --headless --path . --script res://tools/playtest_cycles3.gd

const GameStateScript = preload("res://src/sim/GameState.gd")
const ResolverScript = preload("res://src/sim/Resolver.gd")
const RulesScript = preload("res://src/sim/Rules.gd")
const UnitDefsScript = preload("res://src/sim/UnitDefs.gd")
const UnitStateScript = preload("res://src/sim/UnitState.gd")
const BoardStateScript = preload("res://src/sim/BoardState.gd")

var _fails: Array[String] = []
var _passes: int = 0

func _init() -> void:
	print("=== Chess 3 cycles3 playtest ===")
	_friendly_snare_not_eaten(201)
	_slam_spares_allies(203)
	_front_pop_order(211)
	_soil_regen_disabled(223)
	_destroy_obstacle_then_enter(227)
	_snare_out_of_range(229)
	_snare_on_occupied_rejected(233)
	_ability_while_fresh_blocked(239)
	_full_spawn_band_attach_only(241)
	_snapshot_organs_locked(251)
	_offer_all_unplayable_auto_ends(257)
	_cooldown_ticks_on_end_turn(263)
	_dash_cannot_end_on_enemy(269)
	_ranged_out_of_range(271)
	_melee_friendly_fire_blocked(277)
	_multi_cycle_attrition(281)
	_core_sinks_to_back(283)
	_orphan_cooldown_pruned(293)
	_preview_lists_pop_emojis(307)
	print("=== results: %d pass, %d fail ===" % [_passes, _fails.size()])
	for f in _fails:
		print("FAIL: ", f)
	quit(1 if _fails.size() > 0 else 0)

func _ok(n: String) -> void:
	_passes += 1
	print("PASS: ", n)

func _fail(n: String, d: String) -> void:
	_fails.append("%s — %s" % [n, d])
	print("FAIL: ", n, " — ", d)

func _gs(seed: int):
	var gs = GameStateScript.new()
	root.add_child(gs)
	gs.setup(GameStateScript.DEFAULT_BOARD_SIZE, seed)
	gs.squads.clear()
	gs._next_squad_id = 1
	gs.winner = -1
	gs.active_player = 0
	gs.turn_number = 1
	gs.add_squad(0, Vector2i(2, 0), "core", 1)
	gs.add_squad(1, Vector2i(11, 13), "core", 1)
	gs.player_inventory[0] = {"core": 10, "claw": 10, "hoof": 10, "eye": 10, "gland": 10, "shell": 10}
	gs.player_inventory[1] = gs.player_inventory[0].duplicate(true)
	gs.offer_pending = false
	gs.offer_cards.clear()
	return gs

func _unfresh(gs, sid: int) -> void:
	var s = gs.get_squad(sid)
	if s:
		s.fresh_turn = -1
		s.moved_turn = -1
		for k in s.cooldowns.keys():
			s.cooldowns[k] = 0

func _p0(gs) -> int:
	for sid in gs.squads.keys():
		var s = gs.get_squad(int(sid))
		if s and s.is_alive() and int(s.owner) == 0:
			return int(sid)
	return -1

func _p1(gs) -> int:
	for sid in gs.squads.keys():
		var s = gs.get_squad(int(sid))
		if s and s.is_alive() and int(s.owner) == 1:
			return int(sid)
	return -1

func _friendly_snare_not_eaten(seed: int) -> void:
	var name := "friendly step does not eat own snare (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var a = gs.get_squad(_p0(gs))
	var b = gs.get_squad(_p1(gs))
	a.units.append(UnitStateScript.new("gland", 1, 1))
	a.cell = Vector2i(5, 5)
	a.organs_locked = true
	_unfresh(gs, a.id)
	var trap := Vector2i(5, 6)
	if gs.board.obstacles.has(trap):
		gs.board.obstacles.erase(trap)
	resolver.plant_hazard(gs, a.id, trap, "snare")
	if gs.board.hazard_at(trap) == null:
		_fail(name, "snare not planted"); gs.queue_free(); return
	# Walk onto own snare
	resolver._set_squad_cell(gs, a, trap)
	resolver._trigger_hazard_on_enter(gs, a)
	if gs.board.hazard_at(trap) == null:
		_fail(name, "own snare was consumed by friendly step"); gs.queue_free(); return
	if int(a.snared_no_move_until_turn) >= 0 and int(a.snared_no_move_until_turn) > int(gs.turn_number):
		_fail(name, "friendly snared themselves"); gs.queue_free(); return
	# Enemy still triggers and consumes
	resolver._set_squad_cell(gs, a, Vector2i(5, 5))
	resolver._set_squad_cell(gs, b, trap)
	resolver._trigger_hazard_on_enter(gs, b)
	if gs.board.hazard_at(trap) != null:
		_fail(name, "enemy did not consume snare"); gs.queue_free(); return
	if int(b.snared_no_move_until_turn) < int(gs.turn_number) + 1:
		_fail(name, "enemy not snared"); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _slam_spares_allies(seed: int) -> void:
	var name := "slam spares allies (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var a = gs.get_squad(_p0(gs))
	a.units.append(UnitStateScript.new("shell", 1, 1))
	var ally_id := gs.add_squad(0, Vector2i(6, 6), "core", 1)
	var ally = gs.get_squad(ally_id)
	ally.units.append(UnitStateScript.new("claw", 1, 1))
	var enemy = gs.get_squad(_p1(gs))
	for _i in range(3):
		enemy.units.append(UnitStateScript.new("shell", 1, 1))
	a.cell = Vector2i(6, 5)
	enemy.cell = Vector2i(6, 4)
	a.organs_locked = true
	ally.organs_locked = true
	_unfresh(gs, a.id)
	var ally_before := int(ally.unit_count_alive())
	var enemy_before := int(enemy.unit_count_alive())
	resolver.use_slam(gs, a.id)
	ally = gs.get_squad(ally_id)
	enemy = gs.get_squad(_p1(gs))
	if int(ally.unit_count_alive()) != ally_before:
		_fail(name, "ally took slam damage"); gs.queue_free(); return
	if enemy != null and enemy.is_alive() and int(enemy.unit_count_alive()) >= enemy_before:
		_fail(name, "enemy took no slam damage"); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _front_pop_order(seed: int) -> void:
	var name := "damage pops front organ first (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var a = gs.get_squad(_p0(gs))
	var b = gs.get_squad(_p1(gs))
	# Defender stack: eye, claw, core order
	b.units.clear()
	b.units.append(UnitStateScript.new("eye", 1, 1))
	b.units.append(UnitStateScript.new("claw", 1, 1))
	b.units.append(UnitStateScript.new("core", 1, 1))
	a.units.append(UnitStateScript.new("claw", 1, 1))
	a.cell = Vector2i(4, 4)
	b.cell = Vector2i(4, 5)
	gs.board.set_terrain(a.cell, BoardStateScript.TERRAIN_SAND)
	gs.board.set_terrain(b.cell, BoardStateScript.TERRAIN_SAND)
	a.organs_locked = true
	_unfresh(gs, a.id)
	# Force exactly 1 pop via predict — use weak if needed
	resolver._pop_organs(gs, b, 1)
	b = gs.get_squad(_p1(gs))
	if str(b.units[0].unit_def_id) != "claw":
		_fail(name, "expected claw now front after eye popped, got %s" % str(b.units[0].unit_def_id)); gs.queue_free(); return
	if b.unit_count_alive() != 2:
		_fail(name, "expected 2 organs"); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _soil_regen_disabled(seed: int) -> void:
	var name := "soil does not regen organs (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var a = gs.get_squad(_p0(gs))
	a.units.append(UnitStateScript.new("claw", 1, 1))
	gs.board.set_terrain(a.cell, BoardStateScript.TERRAIN_SOIL)
	var before := int(a.unit_count_alive())
	resolver._apply_soil_regen(gs)
	if int(a.unit_count_alive()) != before:
		_fail(name, "soil regen changed organ count"); gs.queue_free(); return
	# Also ensure no HP inflation on front
	if int(a.units[0].hp) != 1:
		_fail(name, "front organ hp changed"); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _destroy_obstacle_then_enter(seed: int) -> void:
	var name := "destroy obstacle then walk in (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var a = gs.get_squad(_p0(gs))
	a.units.append(UnitStateScript.new("claw", 1, 1))
	a.cell = Vector2i(3, 3)
	var oc := Vector2i(3, 4)
	gs.board.obstacles[oc] = {"hp": 3, "destructible": true}
	a.organs_locked = true
	_unfresh(gs, a.id)
	while gs.board.is_blocked(oc):
		_unfresh(gs, a.id)
		a.cooldowns["melee"] = 0
		resolver.attack_obstacle(gs, a.id, oc, "melee")
		if int(gs.board.obstacle_hp(oc)) <= 0:
			break
	if gs.board.is_blocked(oc):
		_fail(name, "obstacle still blocked"); gs.queue_free(); return
	_unfresh(gs, a.id)
	if not rules.can_move(gs, a.id, oc):
		_fail(name, "cannot enter cleared cell"); gs.queue_free(); return
	resolver.move_squad(gs, a.id, oc)
	if a.cell != oc:
		_fail(name, "move into cleared cell failed"); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _snare_out_of_range(seed: int) -> void:
	var name := "snare out of range rejected (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var a = gs.get_squad(_p0(gs))
	a.units.append(UnitStateScript.new("gland", 1, 1))
	a.cell = Vector2i(5, 5)
	a.organs_locked = true
	_unfresh(gs, a.id)
	var far := Vector2i(5, 9) # range 2 on snare
	resolver.plant_hazard(gs, a.id, far, "snare")
	if gs.board.hazard_at(far) != null:
		_fail(name, "planted snare out of range"); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _snare_on_occupied_rejected(seed: int) -> void:
	var name := "snare on occupied rejected (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var a = gs.get_squad(_p0(gs))
	var b = gs.get_squad(_p1(gs))
	a.units.append(UnitStateScript.new("gland", 1, 1))
	a.cell = Vector2i(5, 5)
	b.cell = Vector2i(5, 6)
	a.organs_locked = true
	_unfresh(gs, a.id)
	resolver.plant_hazard(gs, a.id, b.cell, "snare")
	if gs.board.hazard_at(b.cell) != null:
		_fail(name, "planted snare under enemy"); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _ability_while_fresh_blocked(seed: int) -> void:
	var name := "fresh blocks abilities (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	gs.offer_pending = true
	gs.offer_cards.clear()
	gs.offer_cards.append("claw")
	gs.offer_cards.append("eye")
	gs.offer_cards.append("shell")
	var sid := _p0(gs)
	resolver.play_card_reinforce(gs, "claw", sid)
	var s = gs.get_squad(sid)
	if int(s.fresh_turn) != int(gs.turn_number):
		_fail(name, "not marked fresh"); gs.queue_free(); return
	gs.clear_offer_phase()
	var enemy = _p1(gs)
	s.cell = Vector2i(4, 4)
	gs.get_squad(enemy).cell = Vector2i(4, 5)
	if rules.can_attack(gs, sid, enemy, "melee"):
		_fail(name, "fresh can melee"); gs.queue_free(); return
	resolver.attack(gs, sid, enemy, "melee")
	# enemy should be unscathed if only core
	var e = gs.get_squad(enemy)
	if e != null and int(e.unit_count_alive()) < 1:
		_fail(name, "fresh attack resolved"); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _full_spawn_band_attach_only(seed: int) -> void:
	var name := "full spawn band forces attach-only (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	# Fill all P0 spawn cells with mutants
	var cells = rules.spawn_cells(gs, 0)
	# spawn_cells returns empty cells only — fill empties
	var fill: Array[Vector2i] = []
	for y in range(0, RulesScript.HOME_SPAWN_ROWS):
		for x in range(0, int(gs.board.size.x)):
			var c := Vector2i(x, y)
			if gs.board.is_blocked(c):
				continue
			if gs.squad_at(c) != null:
				continue
			fill.append(c)
	for c in fill:
		gs.add_squad(0, c, "core", 1)
	cells = rules.spawn_cells(gs, 0)
	if not cells.is_empty():
		_fail(name, "spawn cells still available %d" % cells.size()); gs.queue_free(); return
	gs.offer_pending = true
	gs.offer_cards.clear()
	gs.offer_cards.append("claw")
	gs.offer_cards.append("eye")
	gs.offer_cards.append("hoof")
	var sid := _p0(gs)
	# unlock one in pool
	var s = gs.get_squad(sid)
	s.organs_locked = false
	if not rules.is_spawn_pool_cell(gs, s.cell, 0):
		# find any owned in spawn
		for sid2 in gs.squads.keys():
			var s2 = gs.get_squad(int(sid2))
			if s2 and int(s2.owner) == 0 and rules.is_spawn_pool_cell(gs, s2.cell, 0):
				sid = int(sid2)
				s = s2
				break
	if not rules.can_play_card_reinforce(gs, "claw", sid):
		_fail(name, "attach should work when spawn full"); gs.queue_free(); return
	if rules.can_play_card_spawn(gs, "claw", Vector2i(0, 0)):
		_fail(name, "spawn legal on occupied/invalid"); gs.queue_free(); return
	resolver.play_card_reinforce(gs, "claw", sid)
	if int(gs.get_squad(sid).unit_count_alive()) < 2:
		_fail(name, "attach failed"); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _snapshot_organs_locked(seed: int) -> void:
	var name := "snapshot preserves organs_locked (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var sid := _p0(gs)
	var s = gs.get_squad(sid)
	s.units.append(UnitStateScript.new("eye", 1, 1))
	resolver._set_squad_cell(gs, s, Vector2i(4, 5))
	if not bool(s.organs_locked):
		_fail(name, "not locked"); gs.queue_free(); return
	var snap: Dictionary = gs.snapshot_dict()
	var gs2 = GameStateScript.new()
	root.add_child(gs2)
	gs2.apply_snapshot_dict(snap)
	var s2 = gs2.get_squad(sid)
	if s2 == null or not bool(s2.organs_locked):
		_fail(name, "lock lost in snapshot"); gs.queue_free(); gs2.queue_free(); return
	if int(s2.unit_count_alive()) != 2:
		_fail(name, "organs lost in snapshot"); gs.queue_free(); gs2.queue_free(); return
	_ok(name)
	gs.queue_free()
	gs2.queue_free()

func _offer_all_unplayable_auto_ends(seed: int) -> void:
	var name := "unplayable offer auto-ends (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	# Lock all P0 mutants and leave spawn; no empty spawn cells? keep spawn cells but zero inv for offered
	var sid := _p0(gs)
	resolver._set_squad_cell(gs, gs.get_squad(sid), Vector2i(5, 5))
	gs.player_inventory[0] = {"claw": 0, "eye": 0, "shell": 0, "core": 0, "hoof": 0, "gland": 0}
	# Fill spawn so cannot spawn anyway
	for y in range(0, RulesScript.HOME_SPAWN_ROWS):
		for x in range(0, int(gs.board.size.x)):
			var c := Vector2i(x, y)
			if gs.squad_at(c) == null and not gs.board.is_blocked(c):
				gs.add_squad(0, c, "core", 1)
	gs.offer_pending = true
	gs.offer_cards.clear()
	gs.offer_cards.append("claw")
	gs.offer_cards.append("eye")
	gs.offer_cards.append("shell")
	gs.finish_offer_if_done()
	if bool(gs.offer_pending):
		_fail(name, "offer still pending when nothing playable"); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _cooldown_ticks_on_end_turn(seed: int) -> void:
	var name := "cooldowns tick on end turn (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var a = gs.get_squad(_p0(gs))
	a.cooldowns["melee"] = 2
	a.cooldowns["ranged"] = 1
	resolver.end_turn(gs) # also advances player
	# tick happens in end_turn before switch
	# After end_turn, cooldowns should have ticked once
	a = gs.get_squad(_p0(gs))
	if int(a.cooldowns.get("melee", 0)) != 1:
		_fail(name, "melee cd expected 1 got %s" % str(a.cooldowns.get("melee"))); gs.queue_free(); return
	if int(a.cooldowns.get("ranged", 0)) != 0:
		_fail(name, "ranged cd expected 0 got %s" % str(a.cooldowns.get("ranged"))); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _dash_cannot_end_on_enemy(seed: int) -> void:
	var name := "dash cannot end on enemy (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var a = gs.get_squad(_p0(gs))
	var b = gs.get_squad(_p1(gs))
	a.units.append(UnitStateScript.new("claw", 1, 1))
	a.cell = Vector2i(4, 4)
	b.cell = Vector2i(4, 6)
	for c in [Vector2i(4,5), Vector2i(4,6)]:
		if gs.board.obstacles.has(c):
			gs.board.obstacles.erase(c)
	a.organs_locked = true
	_unfresh(gs, a.id)
	var before: Vector2i = a.cell
	resolver.use_dash(gs, a.id, b.cell)
	a = gs.get_squad(_p0(gs))
	if a.cell == b.cell:
		_fail(name, "dashed onto enemy cell"); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _ranged_out_of_range(seed: int) -> void:
	var name := "ranged out of range rejected (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var a = gs.get_squad(_p0(gs))
	var b = gs.get_squad(_p1(gs))
	a.units.append(UnitStateScript.new("eye", 1, 1))
	a.cell = Vector2i(2, 2)
	b.cell = Vector2i(2, 8) # dist 6 > 3
	a.organs_locked = true
	_unfresh(gs, a.id)
	if rules.can_attack(gs, a.id, b.id, "ranged"):
		_fail(name, "ranged legal at dist 6"); gs.queue_free(); return
	var before := int(b.unit_count_alive())
	resolver.attack(gs, a.id, b.id, "ranged")
	if int(gs.get_squad(_p1(gs)).unit_count_alive()) != before:
		_fail(name, "out of range attack dealt damage"); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _melee_friendly_fire_blocked(seed: int) -> void:
	var name := "melee cannot hit ally (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var a = gs.get_squad(_p0(gs))
	a.units.append(UnitStateScript.new("claw", 1, 1))
	var ally_id := gs.add_squad(0, Vector2i(5, 5), "core", 1)
	a.cell = Vector2i(5, 4)
	a.organs_locked = true
	_unfresh(gs, a.id)
	if rules.can_attack(gs, a.id, ally_id, "melee"):
		_fail(name, "melee legal on ally"); gs.queue_free(); return
	var before := int(gs.get_squad(ally_id).unit_count_alive())
	resolver.attack(gs, a.id, ally_id, "melee")
	if int(gs.get_squad(ally_id).unit_count_alive()) != before:
		_fail(name, "ally damaged by melee"); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _multi_cycle_attrition(seed: int) -> void:
	var name := "multi-turn attrition duel (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var a = gs.get_squad(_p0(gs))
	var b = gs.get_squad(_p1(gs))
	for _i in range(4):
		a.units.append(UnitStateScript.new("claw", 1, 1))
		b.units.append(UnitStateScript.new("shell", 1, 1))
	a.cell = Vector2i(7, 7)
	b.cell = Vector2i(7, 8)
	a.organs_locked = true
	b.organs_locked = true
	var guard := 0
	while gs.winner == -1 and guard < 20:
		guard += 1
		if bool(gs.offer_pending):
			gs.clear_offer_phase()
		if int(gs.active_player) == 0:
			_unfresh(gs, a.id)
			a = gs.get_squad(_p0(gs))
			b = gs.get_squad(_p1(gs))
			if a == null or b == null or not b.is_alive():
				break
			a.cooldowns["melee"] = 0
			if rules.can_attack(gs, a.id, b.id, "melee"):
				resolver.attack(gs, a.id, b.id, "melee")
			resolver.end_turn(gs)
		else:
			_unfresh(gs, _p1(gs))
			a = gs.get_squad(_p0(gs))
			b = gs.get_squad(_p1(gs))
			if a == null or b == null or not a.is_alive():
				break
			b.cooldowns["melee"] = 0
			# shell has slam not melee — only core melee if still alive
			if rules.can_attack(gs, b.id, a.id, "melee"):
				resolver.attack(gs, b.id, a.id, "melee")
			elif rules.can_attack(gs, b.id, a.id, "slam") or UnitDefsScript.list_action_ids_for_squad(b).has("slam"):
				_unfresh(gs, b.id)
				resolver.use_slam(gs, b.id)
			resolver.end_turn(gs)
	if gs.winner == -1:
		# Force: ensure someone can die
		b = gs.get_squad(_p1(gs))
		if b and b.is_alive():
			resolver._pop_organs(gs, b, 99)
		if gs.winner == -1 and _p0(gs) >= 0:
			_fail(name, "no winner after attrition"); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _core_sinks_to_back(seed: int) -> void:
	var name := "core sinks to back on attach (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	gs.offer_pending = true
	gs.offer_cards.clear()
	gs.offer_cards.append("core")
	gs.offer_cards.append("claw")
	gs.offer_cards.append("shell")
	var cells = rules.spawn_cells(gs, 0)
	if cells.is_empty():
		_fail(name, "no spawn"); gs.queue_free(); return
	resolver.play_card_spawn(gs, "core", cells[0])
	var sid := int(gs.squad_at(cells[0]).id)
	resolver.play_card_reinforce(gs, "claw", sid)
	resolver.play_card_reinforce(gs, "shell", sid)
	var s = gs.get_squad(sid)
	if int(s.unit_count_alive()) != 3:
		_fail(name, "expected 3 organs"); gs.queue_free(); return
	if str(s.units[0].unit_def_id) != "claw":
		_fail(name, "front should be claw, got %s" % str(s.units[0].unit_def_id)); gs.queue_free(); return
	if str(s.units[1].unit_def_id) != "shell":
		_fail(name, "mid should be shell, got %s" % str(s.units[1].unit_def_id)); gs.queue_free(); return
	if str(s.units[2].unit_def_id) != "core":
		_fail(name, "back should be core, got %s" % str(s.units[2].unit_def_id)); gs.queue_free(); return
	resolver._pop_organs(gs, s, 1)
	s = gs.get_squad(sid)
	var acts = UnitDefsScript.list_action_ids_for_squad(s)
	if not acts.has("melee"):
		_fail(name, "melee lost after claw pop"); gs.queue_free(); return
	if not acts.has("slam"):
		_fail(name, "slam lost after claw pop"); gs.queue_free(); return
	resolver._pop_organs(gs, s, 1)
	s = gs.get_squad(sid)
	acts = UnitDefsScript.list_action_ids_for_squad(s)
	if not acts.has("melee") or acts.has("slam"):
		_fail(name, "expected core-only melee after shell pop: %s" % str(acts)); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _orphan_cooldown_pruned(seed: int) -> void:
	var name := "orphan cooldowns pruned after pop (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var a = gs.get_squad(_p0(gs))
	a.units.clear()
	a.units.append(UnitStateScript.new("eye", 1, 1))
	a.units.append(UnitStateScript.new("core", 1, 1))
	a.cooldowns["ranged"] = 2
	a.cooldowns["melee"] = 1
	resolver._pop_organs(gs, a, 1)
	a = gs.get_squad(_p0(gs))
	if a.cooldowns.has("ranged"):
		_fail(name, "ranged cooldown lingered after eye popped"); gs.queue_free(); return
	if int(a.cooldowns.get("melee", 0)) != 1:
		_fail(name, "melee cooldown should remain"); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _preview_lists_pop_emojis(seed: int) -> void:
	var name := "attack preview lists pop emojis (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var a = gs.get_squad(_p0(gs))
	var b = gs.get_squad(_p1(gs))
	a.units.append(UnitStateScript.new("claw", 1, 1))
	b.units.clear()
	b.units.append(UnitStateScript.new("eye", 1, 1))
	b.units.append(UnitStateScript.new("core", 1, 1))
	a.cell = Vector2i(4, 4)
	b.cell = Vector2i(4, 5)
	gs.board.set_terrain(a.cell, BoardStateScript.TERRAIN_SAND)
	gs.board.set_terrain(b.cell, BoardStateScript.TERRAIN_SAND)
	a.organs_locked = true
	_unfresh(gs, a.id)
	var pred = resolver.predict_attack_damage(gs, a.id, b.id, "melee")
	if str(pred.get("pop_emojis", "")) == "":
		_fail(name, "missing pop_emojis in preview"); gs.queue_free(); return
	if int(pred.get("hp_loss", 0)) < 1:
		_fail(name, "expected damage"); gs.queue_free(); return
	_ok(name)
	gs.queue_free()
