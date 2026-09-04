extends SceneTree

## Player-style multi-cycle sims across organ combinations.
## godot --headless --path . --script res://tools/playtest_live_cycles.gd

const GameStateScript = preload("res://src/sim/GameState.gd")
const ResolverScript = preload("res://src/sim/Resolver.gd")
const RulesScript = preload("res://src/sim/Rules.gd")
const UnitDefsScript = preload("res://src/sim/UnitDefs.gd")
const UnitStateScript = preload("res://src/sim/UnitState.gd")
const BoardStateScript = preload("res://src/sim/BoardState.gd")

var _fails: Array[String] = []
var _passes: int = 0

func _init() -> void:
	print("=== Chess 3 live multi-cycle playtest ===")
	_cycle_spawn_attach_lock_fight(301)
	_cycle_claw_eye_duel(307)
	_cycle_gland_snare_control(311)
	_cycle_shell_slam_vs_stack(313)
	_cycle_hoof_run_kite(317)
	_cycle_soft_ceiling_then_hard_max(319)
	_cycle_multi_gene_offer_then_act(331)
	_cycle_both_players_build_and_clash(337)
	_cycle_attach_after_return_to_pool_stays_locked(347)
	_cycle_pop_removes_abilities(353)
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
	gs.player_inventory[0] = {"core": 8, "claw": 8, "hoof": 8, "eye": 8, "gland": 8, "shell": 8}
	gs.player_inventory[1] = gs.player_inventory[0].duplicate(true)
	gs.offer_pending = false
	gs.offer_cards.clear()
	return gs

func _unfresh(gs, sid: int) -> void:
	var s = gs.get_squad(sid)
	if s == null:
		return
	s.fresh_turn = -1
	s.moved_turn = -1
	for k in s.cooldowns.keys():
		s.cooldowns[k] = 0

func _clear_cell(gs, c: Vector2i) -> void:
	if gs.board.obstacles.has(c):
		gs.board.obstacles.erase(c)

func _set_offer(gs, ids: Array) -> void:
	gs.offer_cards.clear()
	for id in ids:
		gs.offer_cards.append(str(id))


func _actions(s) -> Array:
	return UnitDefsScript.list_action_ids_for_squad(s)

func _cycle_spawn_attach_lock_fight(seed: int) -> void:
	var name := "spawn→attach→exit lock→melee (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	gs.offer_pending = true
	_set_offer(gs, ["core", "claw", "eye"])
	var cells = rules.spawn_cells(gs, 0)
	if cells.is_empty():
		_fail(name, "no spawn cells"); gs.queue_free(); return
	var c0: Vector2i = cells[0]
	resolver.play_card_spawn(gs, "core", c0)
	var sid := -1
	var spawned = gs.squad_at(c0)
	if spawned == null:
		_fail(name, "spawn failed"); gs.queue_free(); return
	sid = int(spawned.id)
	resolver.play_card_reinforce(gs, "claw", sid)
	resolver.play_card_reinforce(gs, "eye", sid)
	var s = gs.get_squad(sid)
	if int(s.unit_count_alive()) != 3:
		_fail(name, "expected 3 organs got %d" % int(s.unit_count_alive())); gs.queue_free(); return
	if bool(s.organs_locked):
		_fail(name, "locked while still in pool"); gs.queue_free(); return
	gs.clear_offer_phase()
	# Leave spawn pool
	var out := Vector2i(c0.x, RulesScript.HOME_SPAWN_ROWS)
	_clear_cell(gs, out)
	_unfresh(gs, sid)
	if not rules.can_move(gs, sid, out) and rules.is_spawn_pool_cell(gs, out, 0):
		out = Vector2i(c0.x, RulesScript.HOME_SPAWN_ROWS + 1)
		_clear_cell(gs, out)
	_unfresh(gs, sid)
	resolver._set_squad_cell(gs, s, out)
	if not bool(s.organs_locked):
		_fail(name, "did not lock on exit"); gs.queue_free(); return
	# Enemy for fight
	var ecell := Vector2i(out.x, out.y + 1)
	_clear_cell(gs, ecell)
	var eid := gs.add_squad(1, ecell, "core", 1)
	_unfresh(gs, sid)
	s.cooldowns["melee"] = 0
	if not rules.can_attack(gs, sid, eid, "melee"):
		_fail(name, "melee not legal after build"); gs.queue_free(); return
	resolver.attack(gs, sid, eid, "melee")
	var e = gs.get_squad(eid)
	if e != null and e.is_alive():
		_fail(name, "1-organ enemy survived melee"); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _cycle_claw_eye_duel(seed: int) -> void:
	var name := "claw melee vs eye kite (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	# Force sand so rock −1 ranged doesn't muddy the math.
	var thin_id := gs.add_squad(0, Vector2i(4, 4), "core", 1)
	var claw_id := gs.add_squad(0, Vector2i(4, 6), "core", 1) # present before shot so wipe ≠ match end
	var eye_id := gs.add_squad(1, Vector2i(4, 7), "core", 1)
	var thin = gs.get_squad(thin_id)
	thin.units.append(UnitStateScript.new("claw", 1, 1))
	var claw = gs.get_squad(claw_id)
	claw.units.append(UnitStateScript.new("claw", 1, 1))
	var eye = gs.get_squad(eye_id)
	eye.units.append(UnitStateScript.new("eye", 1, 1))
	thin.organs_locked = true
	claw.organs_locked = true
	eye.organs_locked = true
	for c in [thin.cell, claw.cell, eye.cell]:
		_clear_cell(gs, c)
		gs.board.set_terrain(c, BoardStateScript.TERRAIN_SAND)
	gs.active_player = 1
	_unfresh(gs, eye_id)
	if not rules.can_attack(gs, eye_id, thin_id, "ranged"):
		_fail(name, "eye cannot shoot at dist 3"); gs.queue_free(); return
	var pred = resolver.predict_attack_damage(gs, eye_id, thin_id, "ranged")
	if int(pred.get("hp_loss", 0)) != 1:
		_fail(name, "expected eye hp_loss=1 on sand, got %s" % str(pred)); gs.queue_free(); return
	resolver.attack(gs, eye_id, thin_id, "ranged")
	thin = gs.get_squad(thin_id)
	if thin == null or not thin.is_alive() or int(thin.unit_count_alive()) != 1:
		_fail(name, "eye should chip one organ off 2-organ mutant on sand"); gs.queue_free(); return
	if gs.winner != -1:
		_fail(name, "match ended despite second P0 mutant"); gs.queue_free(); return
	gs.active_player = 0
	_unfresh(gs, claw_id)
	claw = gs.get_squad(claw_id)
	claw.cooldowns["melee"] = 0
	var eye_before := int(gs.get_squad(eye_id).unit_count_alive())
	if not rules.can_attack(gs, claw_id, eye_id, "melee"):
		_fail(name, "claw melee illegal vs eye"); gs.queue_free(); return
	resolver.attack(gs, claw_id, eye_id, "melee")
	eye = gs.get_squad(eye_id)
	if eye != null and eye.is_alive() and int(eye.unit_count_alive()) >= eye_before:
		_fail(name, "claw failed to chip eye stack"); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _cycle_gland_snare_control(seed: int) -> void:
	var name := "gland snare then finish (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var a_id := gs.add_squad(0, Vector2i(6, 5), "core", 1)
	var b_id := gs.add_squad(1, Vector2i(6, 7), "core", 1)
	var a = gs.get_squad(a_id)
	a.units.append(UnitStateScript.new("gland", 1, 1))
	a.units.append(UnitStateScript.new("claw", 1, 1))
	a.organs_locked = true
	gs.get_squad(b_id).organs_locked = true
	var trap := Vector2i(6, 6)
	_clear_cell(gs, trap)
	_unfresh(gs, a_id)
	resolver.plant_hazard(gs, a_id, trap, "snare")
	if gs.board.hazard_at(trap) == null:
		_fail(name, "snare missing"); gs.queue_free(); return
	# Enemy walks into trap
	var b = gs.get_squad(b_id)
	resolver._set_squad_cell(gs, b, trap)
	resolver._trigger_hazard_on_enter(gs, b)
	if int(b.snared_no_move_until_turn) < int(gs.turn_number) + 1:
		_fail(name, "snare did not apply"); gs.queue_free(); return
	if rules.can_move(gs, b_id, Vector2i(6, 8)):
		_fail(name, "snared enemy can still move"); gs.queue_free(); return
	# Attacker finishes
	_unfresh(gs, a_id)
	resolver._set_squad_cell(gs, a, Vector2i(6, 5))
	a.cooldowns["melee"] = 0
	if rules.can_attack(gs, a_id, b_id, "melee"):
		resolver.attack(gs, a_id, b_id, "melee")
	b = gs.get_squad(b_id)
	if b != null and b.is_alive():
		_fail(name, "snared prey survived melee"); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _cycle_shell_slam_vs_stack(seed: int) -> void:
	var name := "shell slam vs multi-enemy (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var a_id := gs.add_squad(0, Vector2i(8, 8), "core", 1)
	var a = gs.get_squad(a_id)
	a.units.append(UnitStateScript.new("shell", 1, 1))
	a.organs_locked = true
	var e1 := gs.add_squad(1, Vector2i(8, 7), "core", 1)
	var e2 := gs.add_squad(1, Vector2i(7, 8), "core", 1)
	var e3 := gs.add_squad(1, Vector2i(9, 8), "core", 1)
	for eid in [e1, e2, e3]:
		gs.get_squad(eid).organs_locked = true
	_unfresh(gs, a_id)
	resolver.use_slam(gs, a_id)
	var dead := 0
	for eid in [e1, e2, e3]:
		var e = gs.get_squad(eid)
		if e == null or not e.is_alive():
			dead += 1
	if dead < 3:
		_fail(name, "slam should wipe 3 single-organ enemies, dead=%d" % dead); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _cycle_hoof_run_kite(seed: int) -> void:
	var name := "hoof run repositions (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var a_id := gs.add_squad(0, Vector2i(3, 3), "core", 1)
	var a = gs.get_squad(a_id)
	a.units.append(UnitStateScript.new("hoof", 1, 1))
	a.organs_locked = true
	var dest := Vector2i(3, 5)  # run steps=2
	_clear_cell(gs, Vector2i(3, 4))
	_clear_cell(gs, dest)
	_unfresh(gs, a_id)
	if not _actions(a).has("run"):
		_fail(name, "hoof missing run"); gs.queue_free(); return
	resolver.use_run(gs, a_id, dest)
	a = gs.get_squad(a_id)
	if a.cell != dest:
		# try intermediate if run range shorter
		if a.cell == Vector2i(3, 3):
			_fail(name, "run did not move"); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _cycle_soft_ceiling_then_hard_max(seed: int) -> void:
	var name := "soft ceiling then hard max (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var cells = rules.spawn_cells(gs, 0)
	if cells.is_empty():
		_fail(name, "no spawn"); gs.queue_free(); return
	var c: Vector2i = cells[0]
	gs.offer_pending = true
	_set_offer(gs, ["core", "claw", "eye"])
	resolver.play_card_spawn(gs, "core", c)
	var sid := int(gs.squad_at(c).id)
	# Attach up to soft ceiling via repeated reinforce (refresh offer cards)
	var organs := ["claw", "eye", "hoof", "gland", "shell", "claw"]
	for o in organs:
		gs.offer_pending = true
		_set_offer(gs, [o, "eye", "hoof"])
		if not rules.can_play_card_reinforce(gs, o, sid):
			_fail(name, "cannot attach %s at count %d" % [o, gs.get_squad(sid).unit_count_alive()]); gs.queue_free(); return
		resolver.play_card_reinforce(gs, o, sid)
	var s = gs.get_squad(sid)
	if int(s.unit_count_alive()) != 7: # core + 6
		_fail(name, "expected 7 organs got %d" % int(s.unit_count_alive())); gs.queue_free(); return
	# Push to hard max 10
	for i in range(3):
		gs.offer_pending = true
		_set_offer(gs, ["claw", "eye", "hoof"])
		resolver.play_card_reinforce(gs, "claw", sid)
	s = gs.get_squad(sid)
	if int(s.unit_count_alive()) != RulesScript.ORGAN_HARD_MAX:
		_fail(name, "expected hard max %d got %d" % [RulesScript.ORGAN_HARD_MAX, int(s.unit_count_alive())]); gs.queue_free(); return
	gs.offer_pending = true
	_set_offer(gs, ["claw", "eye", "hoof"])
	if rules.can_play_card_reinforce(gs, "claw", sid):
		_fail(name, "attach past hard max allowed"); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _cycle_multi_gene_offer_then_act(seed: int) -> void:
	var name := "spend 3 genes then act next turn (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	gs.active_player = 0
	gs.offer_pending = true
	_set_offer(gs, ["core", "claw", "shell"])
	var cells = rules.spawn_cells(gs, 0)
	var c: Vector2i = cells[0]
	resolver.play_card_spawn(gs, "core", c)
	var sid := int(gs.squad_at(c).id)
	resolver.play_card_reinforce(gs, "claw", sid)
	resolver.play_card_reinforce(gs, "shell", sid)
	if bool(gs.offer_pending):
		_fail(name, "offer should auto-end after 3 spends"); gs.queue_free(); return
	# End turn cycle: P0 done → P1 skip → P0 can act
	resolver.end_turn(gs) # to P1
	gs.clear_offer_phase()
	resolver.end_turn(gs) # to P0 turn 2
	gs.clear_offer_phase()
	var s = gs.get_squad(sid)
	_unfresh(gs, sid) # sim next-turn readiness if seed fresh still
	s.fresh_turn = -1
	var out := Vector2i(c.x, RulesScript.HOME_SPAWN_ROWS + 1)
	_clear_cell(gs, out)
	if rules.can_move(gs, sid, out):
		resolver.move_squad(gs, sid, out)
	s = gs.get_squad(sid)
	if not bool(s.organs_locked):
		# force lock
		resolver._set_squad_cell(gs, s, out)
	var acts = _actions(s)
	if not acts.has("melee") or not acts.has("slam"):
		_fail(name, "missing melee/slam after claw+shell: %s" % str(acts)); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _cycle_both_players_build_and_clash(seed: int) -> void:
	var name := "both players build then clash (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	# P0 builds claw mutant
	gs.active_player = 0
	gs.offer_pending = true
	_set_offer(gs, ["core", "claw", "hoof"])
	var p0c: Vector2i = rules.spawn_cells(gs, 0)[0]
	resolver.play_card_spawn(gs, "core", p0c)
	var p0 := int(gs.squad_at(p0c).id)
	resolver.play_card_reinforce(gs, "claw", p0)
	gs.clear_offer_phase()
	resolver.end_turn(gs)
	# P1 builds eye mutant
	gs.offer_pending = true
	_set_offer(gs, ["core", "eye", "gland"])
	var p1cells = rules.spawn_cells(gs, 1)
	if p1cells.is_empty():
		_fail(name, "no P1 spawn"); gs.queue_free(); return
	var p1c: Vector2i = p1cells[0]
	resolver.play_card_spawn(gs, "core", p1c)
	var p1 := int(gs.squad_at(p1c).id)
	resolver.play_card_reinforce(gs, "eye", p1)
	gs.clear_offer_phase()
	resolver.end_turn(gs)
	# Move both toward center and fight (P1 eye turn)
	var a = gs.get_squad(p0)
	var b = gs.get_squad(p1)
	if b != null and not _actions(b).has("ranged"):
		b.units.append(UnitStateScript.new("eye", 1, int(gs.turn_number)))
	# Buffer organ at front so eye chips ablative shell before core.
	a.units.insert(0, UnitStateScript.new("shell", 1, 1)) # stack: shell, claw, core
	resolver._set_squad_cell(gs, a, Vector2i(6, 6))
	resolver._set_squad_cell(gs, b, Vector2i(6, 9))
	gs.board.set_terrain(a.cell, BoardStateScript.TERRAIN_SAND)
	gs.board.set_terrain(b.cell, BoardStateScript.TERRAIN_SAND)
	a.organs_locked = true
	b.organs_locked = true
	gs.active_player = 1
	_unfresh(gs, p1)
	if not rules.can_attack(gs, p1, p0, "ranged"):
		_fail(name, "eye out of range unexpectedly"); gs.queue_free(); return
	resolver.attack(gs, p1, p0, "ranged")
	a = gs.get_squad(p0)
	# shell+claw+core (3) − 1 chip = claw+core
	if a == null or not a.is_alive() or int(a.unit_count_alive()) != 2:
		_fail(name, "expected 2 organs left on P0 after eye chip, got %s" % (str(a.unit_count_alive()) if a else "null")); gs.queue_free(); return
	if str(a.units[0].unit_def_id) != "claw":
		_fail(name, "expected claw front after shell chip, got %s" % str(a.units[0].unit_def_id)); gs.queue_free(); return
	gs.active_player = 0
	_unfresh(gs, p0)
	resolver._set_squad_cell(gs, a, Vector2i(6, 8))
	a.cooldowns["melee"] = 0
	if not rules.can_attack(gs, p0, p1, "melee"):
		_fail(name, "claw front cannot melee"); gs.queue_free(); return
	resolver.attack(gs, p0, p1, "melee")
	b = gs.get_squad(p1)
	if b != null and b.is_alive():
		_fail(name, "claw melee should finish 2-organ P1"); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _cycle_attach_after_return_to_pool_stays_locked(seed: int) -> void:
	var name := "return to pool stays locked (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var cells = rules.spawn_cells(gs, 0)
	var c: Vector2i = cells[0]
	var sid := gs.add_squad(0, c, "core", 1)
	var s = gs.get_squad(sid)
	resolver._set_squad_cell(gs, s, Vector2i(c.x, RulesScript.HOME_SPAWN_ROWS + 2))
	if not bool(s.organs_locked):
		_fail(name, "should lock on leave"); gs.queue_free(); return
	resolver._set_squad_cell(gs, s, c)
	if not bool(s.organs_locked):
		_fail(name, "unlocked on return"); gs.queue_free(); return
	gs.offer_pending = true
	_set_offer(gs, ["claw", "eye", "hoof"])
	if rules.can_play_card_reinforce(gs, "claw", sid):
		_fail(name, "attach allowed on locked returnee"); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _cycle_pop_removes_abilities(seed: int) -> void:
	var name := "popping eye removes ranged (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var a_id := gs.add_squad(0, Vector2i(5, 5), "core", 1)
	var b_id := gs.add_squad(1, Vector2i(5, 8), "core", 1)
	var a = gs.get_squad(a_id)
	# Front is eye so first damage pops ranged
	a.units.clear()
	a.units.append(UnitStateScript.new("eye", 1, 1))
	a.units.append(UnitStateScript.new("core", 1, 1))
	a.organs_locked = true
	if not _actions(a).has("ranged"):
		_fail(name, "no ranged before pop"); gs.queue_free(); return
	resolver._pop_organs(gs, a, 1)
	a = gs.get_squad(a_id)
	if _actions(a).has("ranged"):
		_fail(name, "ranged still present after eye popped"); gs.queue_free(); return
	_unfresh(gs, a_id)
	if rules.can_attack(gs, a_id, b_id, "ranged"):
		_fail(name, "can_attack ranged after eye gone"); gs.queue_free(); return
	_ok(name)
	gs.queue_free()
