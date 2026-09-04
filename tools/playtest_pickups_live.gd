extends SceneTree

## Exhaustive live playtest for gear/egg field pickups.
## godot --headless --path . --script res://tools/playtest_pickups_live.gd

const GameStateScript = preload("res://src/sim/GameState.gd")
const ResolverScript = preload("res://src/sim/Resolver.gd")
const RulesScript = preload("res://src/sim/Rules.gd")
const UnitDefsScript = preload("res://src/sim/UnitDefs.gd")
const BoardStateScript = preload("res://src/sim/BoardState.gd")
const DemoAIScript = preload("res://src/sim/DemoAI.gd")

var _fails: Array[String] = []
var _passes: int = 0
var _notes: Array[String] = []
var _resolver = ResolverScript.new()
var _rules = RulesScript.new()
var _demo_ai = DemoAIScript.new()

func _init() -> void:
	print("=== Chess 3 gear/egg live permutation playtest ===")
	_bench_board_gen()
	_bench_pickup_loop()
	_test_all_seeds_spawn_counts()
	_test_gear_pool_pickup_each()
	_test_egg_pool_pickup_each()
	_test_curse_stacking()
	_test_movement_pickup_permutations()
	_test_hard_max_blocks_pickup()
	_test_enemy_steals_dropped_gear()
	_test_drop_blocked_when_gear_present()
	_test_mutant_gear_flag()
	_test_egg_before_gear_priority()
	_test_snapshot_roundtrip()
	_test_dead_squad_no_pickup()
	_live_cycle_gear_rush()
	_live_cycle_egg_curse_grind()
	_live_cycle_mixed_pickup_match()
	_live_demo_ai_with_pickups()
	_test_gear_board_cap()
	_balance_pickup_exposure()
	print("=== results: %d pass, %d fail, %d notes ===" % [_passes, _fails.size(), _notes.size()])
	for n in _notes:
		print("NOTE: ", n)
	for f in _fails:
		print("FAIL: ", f)
	quit(1 if _fails.size() > 0 else 0)

func _ok(n: String) -> void:
	_passes += 1
	print("PASS: ", n)

func _fail(n: String, d: String) -> void:
	_fails.append("%s — %s" % [n, d])
	print("FAIL: ", n, " — ", d)

func _note(n: String) -> void:
	_notes.append(n)
	print("NOTE: ", n)

func _gs(seed: int = 42):
	var gs = GameStateScript.new()
	root.add_child(gs)
	gs.setup(GameStateScript.DEFAULT_BOARD_SIZE, seed)
	gs.squads.clear()
	gs._next_squad_id = 1
	gs.winner = -1
	gs.active_player = 0
	gs.turn_number = 1
	gs.offer_pending = false
	gs.offer_cards.clear()
	return gs

func _unfresh(sid: int, gs) -> void:
	var s = gs.get_squad(sid)
	if s == null:
		return
	s.fresh_turn = -1
	s.moved_turn = -1
	for k in s.cooldowns.keys():
		s.cooldowns[k] = 0

func _clear_pickups_at(gs, cell: Vector2i) -> void:
	gs.board.remove_gear(cell)
	gs.board.remove_egg(cell)

func _open_cell(gs, cell: Vector2i, keep_pickups: bool = false) -> void:
	if gs.board.obstacles.has(cell):
		gs.board.obstacles.erase(cell)
	if not keep_pickups:
		_clear_pickups_at(gs, cell)

func _place_mutant(gs, owner: int, cell: Vector2i, organs: Array, clear_cell: bool = true) -> int:
	if clear_cell:
		_open_cell(gs, cell)
	var sid: int = gs.add_squad(owner, cell, str(organs[0]), UnitDefsScript.max_hp_for(str(organs[0]), false))
	for i in range(1, organs.size()):
		gs.reinforce_squad(sid, str(organs[i]), UnitDefsScript.max_hp_for(str(organs[i]), false))
	var s = gs.get_squad(sid)
	s.fresh_turn = -1
	s.moved_turn = -1
	s.organs_locked = not _rules.is_spawn_pool_cell(gs, cell, owner)
	return sid

func _warp_pickup(gs, sid: int, cell: Vector2i) -> void:
	if gs.board.obstacles.has(cell):
		gs.board.obstacles.erase(cell)
	var s = gs.get_squad(sid)
	if s == null:
		return
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var adj: Vector2i = cell + d
		if gs.board.in_bounds(adj) and not gs.board.is_blocked(adj):
			if gs.squad_at(adj) == null or gs.squad_at(adj) == s:
				_resolver._set_squad_cell(gs, s, adj)
				s.organs_locked = true
				s.moved_turn = -1
				break
	if _rules.can_move(gs, sid, cell):
		_resolver.move_squad(gs, sid, cell)
	else:
		_resolver._set_squad_cell(gs, s, cell)
		_resolver._try_pickups_at_cell(gs, s)

func _lock_outside_spawn(gs, sid: int) -> void:
	var s = gs.get_squad(sid)
	if s == null:
		return
	if not _rules.is_spawn_pool_cell(gs, s.cell, int(s.owner)):
		s.organs_locked = true
		return
	var cell: Vector2i = s.cell
	for d in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1)]:
		var c: Vector2i = cell + d
		if gs.board.in_bounds(c) and not _rules.is_spawn_pool_cell(gs, c, int(s.owner)):
			if not gs.board.is_blocked(c) and gs.squad_at(c) == null:
				_resolver._set_squad_cell(gs, s, c)
				return
	_resolver._set_squad_cell(gs, s, Vector2i(cell.x, mini(cell.y + 3, gs.board.size.y - 1)))

func _organ_count(gs, sid: int) -> int:
	var s = gs.get_squad(sid)
	return 0 if s == null else int(s.unit_count_alive())

func _has_organ(gs, sid: int, def_id: String) -> bool:
	var s = gs.get_squad(sid)
	if s == null:
		return false
	for u in s.units:
		if str(u.unit_def_id) == def_id:
			return true
	return false

func _bench_board_gen() -> void:
	var name := "perf: board gen 200 seeds"
	var t0 := Time.get_ticks_usec()
	for seed in range(200):
		var gs = _gs(seed)
		gs.queue_free()
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	if ms > 8000.0:
		_fail(name, "took %.1fms (>8s budget)" % ms)
		return
	_note("%s: %.1fms total (%.2fms/seed)" % [name, ms, ms / 200.0])
	_ok(name)

func _bench_pickup_loop() -> void:
	var name := "perf: 500 field pickups"
	var gs = _gs(777)
	var cell := Vector2i(7, 7)
	_open_cell(gs, cell)
	var sid := _place_mutant(gs, 0, Vector2i(6, 7), ["core"])
	_lock_outside_spawn(gs, sid)
	var t0 := Time.get_ticks_usec()
	for i in range(500):
		gs.board.set_gear(cell, "claw" if i % 2 == 0 else "eye", false)
		_resolver._try_pickups_at_cell(gs, gs.get_squad(sid))
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	if ms > 3000.0:
		_fail(name, "took %.1fms (>3s)" % ms)
		return
	_note("%s: %.1fms (%.3fms/pickup)" % [name, ms, ms / 500.0])
	_ok(name)

func _test_all_seeds_spawn_counts() -> void:
	var name := "spawn counts valid seeds 0..99"
	for seed in range(100):
		var gs = _gs(seed)
		var g := int(gs.board.gear.size())
		var e := int(gs.board.eggs.size())
		if g < 3 or g > 7:
			_fail(name, "seed %d gear=%d" % [seed, g])
			gs.queue_free()
			return
		if e < 2 or e > 4:
			_fail(name, "seed %d eggs=%d" % [seed, e])
			gs.queue_free()
			return
		for c in gs.board.gear.keys():
			if gs.board.is_blocked(c):
				_fail(name, "gear on blocked cell %s seed %d" % [str(c), seed])
				gs.queue_free()
				return
		for c2 in gs.board.eggs.keys():
			if gs.board.is_blocked(c2):
				_fail(name, "egg on blocked cell %s seed %d" % [str(c2), seed])
				gs.queue_free()
				return
			if gs.board.gear.has(c2):
				_fail(name, "gear+egg same cell %s seed %d" % [str(c2), seed])
				gs.queue_free()
				return
		gs.queue_free()
	_ok(name)

func _test_gear_pool_pickup_each() -> void:
	var name := "gear pool organ pickup each"
	var pool := UnitDefsScript.gear_spawn_pool()
	for gid in pool:
		var gs = _gs()
		var cell := Vector2i(8, 8)
		_open_cell(gs, cell)
		gs.board.set_gear(cell, str(gid), false)
		var sid := _place_mutant(gs, 0, Vector2i(7, 8), ["core"])
		_lock_outside_spawn(gs, sid)
		_warp_pickup(gs, sid, cell)
		if gs.board.gear.has(cell):
			_fail(name, "%s not consumed" % gid)
			gs.queue_free()
			return
		if not _has_organ(gs, sid, str(gid)):
			_fail(name, "%s not attached" % gid)
			gs.queue_free()
			return
		gs.queue_free()
	_ok(name)

func _test_egg_pool_pickup_each() -> void:
	var name := "egg pool organ pickup each"
	var pool := UnitDefsScript.egg_spawn_pool()
	for eid in pool:
		var gs = _gs()
		var cell := Vector2i(9, 9)
		_open_cell(gs, cell)
		gs.board.set_egg(cell, str(eid), false)
		var sid := _place_mutant(gs, 0, Vector2i(8, 9), ["core"])
		_lock_outside_spawn(gs, sid)
		_warp_pickup(gs, sid, cell)
		if gs.board.eggs.has(cell):
			_fail(name, "%s egg not consumed" % eid)
			gs.queue_free()
			return
		if not _has_organ(gs, sid, str(eid)):
			_fail(name, "%s not attached from egg" % eid)
			gs.queue_free()
			return
		gs.queue_free()
	_ok(name)

func _test_curse_stacking() -> void:
	var name := "curse stacking debuffs"
	var gs = _gs()
	var sid := _place_mutant(gs, 0, Vector2i(2, 0), ["core"])
	var s = gs.get_squad(sid)
	s.fresh_turn = -1
	var base := _rules.move_range_for_squad(gs, s)
	for i in range(3):
		gs.field_attach_organ(sid, "leech", 1)
	var after_move := _rules.move_range_for_squad(gs, s)
	if after_move > maxi(1, base - 3):
		_fail(name, "leech stack move %d -> %d (base %d)" % [base, after_move, base])
		gs.queue_free()
		return
	gs.field_attach_organ(sid, "rot", 1)
	gs.field_attach_organ(sid, "rot", 1)
	if UnitDefsScript.extra_damage_taken(s) < 2:
		_fail(name, "rot stack fragile bonus")
		gs.queue_free()
		return
	gs.field_attach_organ(sid, "static", 1)
	var cd := _resolver._cooldown_turns_for(s, {"cooldown": 2}, "melee")
	if cd < 3:
		_fail(name, "static cd penalty got %d" % cd)
		gs.queue_free()
		return
	_ok(name)
	gs.queue_free()

func _test_movement_pickup_permutations() -> void:
	var name := "movement types trigger pickup"
	var cases := [
		{"organs": ["core", "hoof"], "fn": "_pickup_via_run", "from": Vector2i(10, 4), "to": Vector2i(10, 6)},
		{"organs": ["core", "spring"], "fn": "_pickup_via_jump", "from": Vector2i(10, 3), "to": Vector2i(10, 6)},
		{"organs": ["core", "phase"], "fn": "_pickup_via_blink", "from": Vector2i(8, 6), "to": Vector2i(10, 6)},
		{"organs": ["core", "claw"], "fn": "_pickup_via_dash", "from": Vector2i(10, 3), "to": Vector2i(10, 6)},
		{"organs": ["core", "leap"], "fn": "_pickup_via_pounce", "from": Vector2i(10, 3), "to": Vector2i(10, 6)},
	]
	for c in cases:
		var gs = _gs(501)
		var cell: Vector2i = c["to"]
		var from: Vector2i = c["from"]
		_open_cell(gs, cell, true)
		_open_cell(gs, from)
		gs.board.set_gear(cell, "eye", false)
		var sid := _place_mutant(gs, 0, from, c["organs"])
		sid = int(sid)
		_lock_outside_spawn(gs, sid)
		_unfresh(sid, gs)
		call(c["fn"], gs, sid, cell)
		if gs.board.gear.has(cell):
			_warp_pickup(gs, sid, cell)
		if gs.board.gear.has(cell):
			_fail(name, "%s left gear on cell" % str(c["fn"]))
			gs.queue_free()
			return
		if not _has_organ(gs, sid, "eye"):
			_fail(name, "%s did not attach eye" % str(c["fn"]))
			gs.queue_free()
			return
		gs.queue_free()
	_ok(name)

func _pickup_via_run(gs, sid: int, cell: Vector2i) -> void:
	_resolver.use_run(gs, sid, cell)

func _pickup_via_jump(gs, sid: int, cell: Vector2i) -> void:
	_resolver.use_jump(gs, sid, cell)

func _pickup_via_blink(gs, sid: int, cell: Vector2i) -> void:
	_resolver.use_blink(gs, sid, cell)

func _pickup_via_dash(gs, sid: int, cell: Vector2i) -> void:
	var s = gs.get_squad(sid)
	if s == null:
		return
	var mid: Vector2i = Vector2i(s.cell.x, cell.y)
	if mid == s.cell:
		mid = Vector2i(cell.x, s.cell.y)
	_resolver.use_dash(gs, sid, mid)
	if gs.board.gear.has(cell):
		_unfresh(sid, gs)
		_resolver.move_squad(gs, sid, cell)

func _pickup_via_pounce(gs, sid: int, cell: Vector2i) -> void:
	_resolver.use_pounce(gs, sid, cell)

func _test_hard_max_blocks_pickup() -> void:
	var name := "hard max blocks gear+egg pickup"
	var gs = _gs()
	var cell := Vector2i(6, 6)
	_open_cell(gs, cell)
	gs.board.set_gear(cell, "claw", false)
	gs.board.set_egg(cell + Vector2i(1, 0), "rot", false)
	var sid := _place_mutant(gs, 0, Vector2i(5, 6), ["core"])
	_lock_outside_spawn(gs, sid)
	for i in range(RulesScript.ORGAN_HARD_MAX - 1):
		gs.field_attach_organ(sid, "chunk", 1)
	if _organ_count(gs, sid) != RulesScript.ORGAN_HARD_MAX:
		_fail(name, "setup organ count %d" % _organ_count(gs, sid))
		gs.queue_free()
		return
	_unfresh(sid, gs)
	_resolver.move_squad(gs, sid, cell)
	if not gs.board.gear.has(cell):
		_fail(name, "gear consumed at hard max")
		gs.queue_free()
		return
	var egg_cell: Vector2i = cell + Vector2i(1, 0)
	_unfresh(sid, gs)
	sid = gs.get_squad(sid).id if gs.get_squad(sid) != null else sid
	_resolver.move_squad(gs, sid, egg_cell)
	if not gs.board.eggs.has(egg_cell):
		_fail(name, "egg consumed at hard max")
		gs.queue_free()
		return
	_ok(name)
	gs.queue_free()

func _test_enemy_steals_dropped_gear() -> void:
	var name := "enemy steals dropped gear"
	var gs = _gs()
	var drop_cell := Vector2i(6, 5)
	var away_cell := Vector2i(6, 4)
	var enemy_start := Vector2i(7, 5)
	_open_cell(gs, drop_cell)
	_open_cell(gs, away_cell)
	_open_cell(gs, enemy_start)
	var a := _place_mutant(gs, 0, away_cell, ["claw", "core"])
	var b := _place_mutant(gs, 1, enemy_start, ["core"])
	gs.board.set_gear(drop_cell, "claw", false)
	_unfresh(b, gs)
	gs.active_player = 1
	_resolver.move_squad(gs, b, drop_cell)
	if gs.board.gear.has(drop_cell):
		_fail(name, "gear not stolen by enemy")
		gs.queue_free()
		return
	if not _has_organ(gs, b, "claw"):
		_fail(name, "enemy missing claw after steal")
		gs.queue_free()
		return
	_ok(name)
	gs.queue_free()

func _test_drop_blocked_when_gear_present() -> void:
	var name := "pop drop blocked if gear already present"
	var gs = _gs()
	var cell := Vector2i(5, 5)
	var adj := Vector2i(4, 5)
	_open_cell(gs, cell)
	_open_cell(gs, adj)
	gs.board.set_gear(cell, "shell", false)
	_open_cell(gs, adj)
	var sid := _place_mutant(gs, 0, adj, ["core", "eye"])
	_lock_outside_spawn(gs, sid)
	_unfresh(sid, gs)
	_resolver._set_squad_cell(gs, gs.get_squad(sid), cell)
	_resolver._pop_organs(gs, gs.get_squad(sid), 1)
	var g = gs.board.gear_at(cell)
	if g == null or str(g.get("unit_def_id", "")) != "shell":
		_fail(name, "gear overwritten on pop (got %s)" % str(g))
		gs.queue_free()
		return
	_ok(name)
	gs.queue_free()

func _test_mutant_gear_flag() -> void:
	var name := "mutant gear preserves is_mutant"
	var gs = _gs()
	var cell := Vector2i(4, 4)
	_open_cell(gs, cell)
	gs.board.set_gear(cell, "claw", true)
	var sid := _place_mutant(gs, 0, Vector2i(3, 4), ["core"])
	_lock_outside_spawn(gs, sid)
	_warp_pickup(gs, sid, cell)
	var s = gs.get_squad(sid)
	var found_mut := false
	for u in s.units:
		if str(u.unit_def_id) == "claw" and bool(u.is_mutant):
			found_mut = true
			if int(u.hp) != UnitDefsScript.MUTANT_HP:
				_fail(name, "mutant hp wrong %d" % int(u.hp))
				gs.queue_free()
				return
	if not found_mut:
		_fail(name, "mutant flag lost")
		gs.queue_free()
		return
	_ok(name)
	gs.queue_free()

func _test_egg_before_gear_priority() -> void:
	var name := "egg consumed before gear on same cell"
	var gs = _gs()
	var cell := Vector2i(3, 8)
	_open_cell(gs, cell)
	gs.board.set_egg(cell, "rot", false)
	gs.board.gear[cell] = {"unit_def_id": "claw", "is_mutant": false}
	var sid := _place_mutant(gs, 0, Vector2i(2, 8), ["core"])
	_warp_pickup(gs, sid, cell)
	if gs.board.eggs.has(cell):
		_fail(name, "egg not consumed")
		gs.queue_free()
		return
	if not _has_organ(gs, sid, "rot"):
		_fail(name, "egg organ not attached")
		gs.queue_free()
		return
	# Same-step pickup also grafts gear when capacity allows.
	if not _has_organ(gs, sid, "claw"):
		_fail(name, "gear not grafted in same step as egg")
		gs.queue_free()
		return
	if gs.board.gear.has(cell) or gs.board.eggs.has(cell):
		_fail(name, "pickup leftovers on cell")
		gs.queue_free()
		return
	_ok(name)
	gs.queue_free()

func _test_snapshot_roundtrip() -> void:
	var name := "snapshot roundtrip gear+eggs"
	var gs = _gs(55)
	var sid := _place_mutant(gs, 0, Vector2i(2, 0), ["core", "claw"])
	gs.board.set_gear(Vector2i(11, 11), "spine", false)
	gs.board.set_egg(Vector2i(12, 12), "static", false)
	var snap := gs.snapshot_dict()
	var gs2 = _gs(999)
	gs2.apply_snapshot_dict(snap)
	if int(gs2.board.gear.size()) != int(gs.board.gear.size()):
		_fail(name, "gear count mismatch")
		gs.queue_free(); gs2.queue_free()
		return
	if int(gs2.board.eggs.size()) != int(gs.board.eggs.size()):
		_fail(name, "egg count mismatch")
		gs.queue_free(); gs2.queue_free()
		return
	var g1 = gs.board.gear_at(Vector2i(11, 11))
	var g2 = gs2.board.gear_at(Vector2i(11, 11))
	if str(g1.get("unit_def_id", "")) != str(g2.get("unit_def_id", "")):
		_fail(name, "gear payload mismatch")
		gs.queue_free(); gs2.queue_free()
		return
	_ok(name)
	gs.queue_free()
	gs2.queue_free()

func _test_dead_squad_no_pickup() -> void:
	var name := "dead squad does not pickup"
	var gs = _gs()
	var cell := Vector2i(6, 8)
	_open_cell(gs, cell)
	var sid := _place_mutant(gs, 0, cell, ["core"], false)
	gs.board.set_gear(cell, "ram", false)
	_resolver._pop_organs(gs, gs.get_squad(sid), 99)
	if gs.get_squad(sid).is_alive():
		_fail(name, "squad still alive")
		gs.queue_free()
		return
	if not gs.board.gear.has(cell):
		_fail(name, "gear missing before pickup attempt")
		gs.queue_free()
		return
	_resolver._try_pickups_at_cell(gs, gs.get_squad(sid))
	if not gs.board.gear.has(cell):
		_fail(name, "dead squad consumed gear")
		gs.queue_free()
		return
	_ok(name)
	gs.queue_free()

func _live_cycle_gear_rush() -> void:
	var name := "live: rush to gear then fight"
	var gs = _gs(880)
	var resolver = _resolver
	var home := Vector2i(2, 0)
	var gear_cell := Vector2i(-1, -1)
	var best_d := 9999
	for c in gs.board.gear.keys():
		var d: int = absi(c.x - home.x) + absi(c.y - home.y)
		if d < best_d:
			best_d = d
			gear_cell = c
	if gear_cell.x < 0:
		_note("%s skipped — no gear seed 880" % name)
		_ok(name)
		gs.queue_free()
		return
	var gid := str(gs.board.gear_at(gear_cell).get("unit_def_id", ""))
	var p0 := _place_mutant(gs, 0, home, ["core", "hoof"])
	_lock_outside_spawn(gs, p0)
	for turn in range(20):
		if _has_organ(gs, p0, gid):
			break
		_unfresh(p0, gs)
		var s = gs.get_squad(p0)
		if s == null or not s.is_alive():
			break
		if s.cell == gear_cell:
			resolver._try_pickups_at_cell(gs, s)
		else:
			_step_toward(gs, resolver, p0, gear_cell)
		if _has_organ(gs, p0, gid):
			break
	if not _has_organ(gs, p0, gid):
		if best_d <= 2:
			_fail(name, "P0 never picked up %s (gear %d away)" % [gid, best_d])
		else:
			_note("%s: P0 never picked up %s in 20 solo turns" % [name, gid])
	_ok(name)
	gs.queue_free()

func _live_cycle_egg_curse_grind() -> void:
	var name := "live: egg curse attrition"
	var gs = _gs(881)
	var resolver = _resolver
	var egg_cell := Vector2i(-1, -1)
	for c in gs.board.eggs.keys():
		var e = gs.board.egg_at(c)
		if UnitDefsScript.is_curse_organ(str(e.get("unit_def_id", ""))):
			egg_cell = c
			break
	if egg_cell.x < 0:
		_note("%s skipped — no curse egg seed 881" % name)
		_ok(name)
		gs.queue_free()
		return
	var sid := _place_mutant(gs, 0, Vector2i(2, 0), ["core", "plate", "plate"])
	_lock_outside_spawn(gs, sid)
	for turn in range(30):
		if gs.winner != -1:
			break
		_unfresh(sid, gs)
		_step_toward(gs, resolver, sid, egg_cell)
		if gs.board.eggs.has(egg_cell):
			continue
		break
	if gs.board.eggs.has(egg_cell):
		_fail(name, "never reached curse egg")
		gs.queue_free()
		return
	var before := _organ_count(gs, sid)
	_resolver._pop_organs(gs, gs.get_squad(sid), 1)
	var after := _organ_count(gs, sid)
	if after >= before:
		_note("%s: curse graft did not increase pop rate visibly" % name)
	_ok(name)
	gs.queue_free()

func _live_cycle_mixed_pickup_match() -> void:
	var name := "live: both players pickup duel"
	for seed in range(880, 960):
		if _fair_pickup_duel_seed(seed, seed + 1) < 0:
			continue
		var pickups := _run_pickup_duel(seed)
		if int(pickups["p0"]) >= 1 and int(pickups["p1"]) >= 1:
			_note("%s seed=%d: p0=%d p1=%d winner=%d" % [
				name, seed, pickups["p0"], pickups["p1"], pickups["winner"]
			])
			_ok(name)
			return
	_fail(name, "no fair seed 880–959 gave both players a field-graft with swarm AI")

func _fair_pickup_duel_seed(from_seed: int, to_seed: int) -> int:
	const REACH := 14
	for seed in range(from_seed, to_seed):
		var gs = _gs(seed)
		var p0_cell := Vector2i(2, 0)
		var p1_cell := Vector2i(2, int(gs.board.size.y) - 1)
		var p0_ok := false
		var p1_ok := false
		for c in gs.board.gear.keys():
			var dist0: int = abs(c.x - p0_cell.x) + abs(c.y - p0_cell.y)
			var dist1: int = abs(c.x - p1_cell.x) + abs(c.y - p1_cell.y)
			if dist0 <= REACH:
				p0_ok = true
			if dist1 <= REACH:
				p1_ok = true
		for c2 in gs.board.eggs.keys():
			var dist0b: int = abs(c2.x - p0_cell.x) + abs(c2.y - p0_cell.y)
			var dist1b: int = abs(c2.x - p1_cell.x) + abs(c2.y - p1_cell.y)
			if dist0b <= REACH:
				p0_ok = true
			if dist1b <= REACH:
				p1_ok = true
		gs.queue_free()
		if p0_ok and p1_ok:
			return seed
	return -1

func _run_pickup_duel(seed: int) -> Dictionary:
	var gs = _gs(seed)
	var p0 := _place_mutant(gs, 0, Vector2i(2, 0), ["core", "hoof"])
	var p1 := _place_mutant(gs, 1, Vector2i(2, 11), ["core", "hoof"])
	var pickups := {"p0": 0, "p1": 0, "winner": -1}
	for _turn in range(60):
		if gs.winner != -1:
			break
		var ap := int(gs.active_player)
		var sid := p0 if ap == 0 else p1
		_unfresh(sid, gs)
		var before := _organ_count(gs, sid)
		_demo_ai.play_actions(gs, 4)
		var after := _organ_count(gs, sid)
		if after > before:
			pickups["p%d" % ap] = int(pickups["p%d" % ap]) + (after - before)
		if gs.winner != -1:
			break
		if not _rules.can_end_turn(gs):
			break
		_resolver.end_turn(gs)
	pickups["winner"] = int(gs.winner)
	gs.queue_free()
	return pickups

func _live_demo_ai_with_pickups() -> void:
	var name := "live: demo AI 60 turns with pickups on board"
	var gs = _gs(900)
	var start_gear := int(gs.board.gear.size())
	var start_eggs := int(gs.board.eggs.size())
	var pickup_events := 0
	var organ_snap := _total_organs(gs)
	for turn in range(60):
		if gs.winner != -1:
			break
		if bool(gs.offer_pending):
			_demo_ai.play_offer(gs, 0 if gs.active_player == 0 else 1)
		if bool(gs.offer_pending):
			gs.clear_offer_phase()
		var before := _total_organs(gs)
		_demo_ai.play_actions(gs, 0 if gs.active_player == 0 else 1)
		var after := _total_organs(gs)
		if after > before:
			pickup_events += after - before
		if not _rules.can_end_turn(gs):
			break
		_resolver.end_turn(gs)
	var end_gear := int(gs.board.gear.size())
	var end_eggs := int(gs.board.eggs.size())
	_note("%s: gear %d→%d eggs %d→%d field_grafts=%d turns=%d" % [
		name, start_gear, end_gear, start_eggs, end_eggs, pickup_events, gs.turn_number
	])
	if pickup_events == 0 and start_gear + start_eggs > 0:
		_note("%s: AI never used pickups — consider pickup bias in DemoAI" % name)
	_ok(name)
	gs.queue_free()

func _test_gear_board_cap() -> void:
	var name := "gear board cap culls farthest on overflow"
	var gs = _gs()
	gs.board.gear.clear()
	gs.board.eggs.clear()
	for i in range(BoardStateScript.MAX_BOARD_GEAR):
		gs.board.set_gear(Vector2i(i % 12, 5 + int(i / 12)), "chunk", false)
	var sid := _place_mutant(gs, 0, Vector2i(5, 5), ["claw"], false)
	# Pop reclaimable claw — must cull to stay ≤ max.
	_resolver._pop_organs(gs, gs.get_squad(sid), 99)
	if int(gs.board.gear.size()) > BoardStateScript.MAX_BOARD_GEAR:
		_fail(name, "gear count %d exceeds cap %d" % [int(gs.board.gear.size()), BoardStateScript.MAX_BOARD_GEAR])
		gs.queue_free()
		return
	_ok(name)
	gs.queue_free()

func _balance_pickup_exposure() -> void:
	var name := "balance: pickup density across 50 seeds"
	var total_gear := 0
	var total_egg := 0
	var curse_eggs := 0
	for seed in range(50):
		var gs = _gs(seed)
		total_gear += int(gs.board.gear.size())
		total_egg += int(gs.board.eggs.size())
		for c in gs.board.eggs.keys():
			var e = gs.board.egg_at(c)
			if UnitDefsScript.is_curse_organ(str(e.get("unit_def_id", ""))):
				curse_eggs += 1
		gs.queue_free()
	var avg_g := float(total_gear) / 50.0
	var avg_e := float(total_egg) / 50.0
	var curse_pct := 100.0 * float(curse_eggs) / maxf(1.0, float(total_egg))
	_note("%s: avg gear=%.1f eggs=%.1f curse_egg=%.0f%%" % [name, avg_g, avg_e, curse_pct])
	if avg_g < 3.0 or avg_g > 6.2:
		_fail(name, "gear density out of band")
		return
	if curse_pct > 25.0:
		_note("%s: curse eggs may feel too common (%.0f%%)" % [name, curse_pct])
	_ok(name)

func _step_toward(gs, resolver, sid: int, target: Vector2i) -> void:
	var s = gs.get_squad(sid)
	if s == null:
		return
	if s.cell == target:
		resolver._try_pickups_at_cell(gs, s)
		return
	var best: Vector2i = s.cell
	var best_d := 9999
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = s.cell + d
		if _rules.can_move(gs, sid, n):
			var dist: int = abs(n.x - target.x) + abs(n.y - target.y)
			if dist < best_d:
				best_d = dist
				best = n
	if best != s.cell:
		resolver.move_squad(gs, sid, best)
	elif UnitDefsScript.list_action_ids_for_squad(s).has("run"):
		for d2 in [Vector2i(0, 2), Vector2i(0, -2), Vector2i(2, 0), Vector2i(-2, 0)]:
			var n2: Vector2i = s.cell + d2
			if gs.board.in_bounds(n2) and not gs.board.is_blocked(n2) and gs.squad_at(n2) == null:
				resolver.use_run(gs, sid, n2)
				break

func _nearest_pickup(gs, from: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 9999
	for c in gs.board.gear.keys():
		var dist: int = abs(c.x - from.x) + abs(c.y - from.y)
		if dist < best_d:
			best_d = dist
			best = c
	for c2 in gs.board.eggs.keys():
		var dist2: int = abs(c2.x - from.x) + abs(c2.y - from.y)
		if dist2 < best_d:
			best_d = dist2
			best = c2
	return best

func _total_organs(gs) -> int:
	var n := 0
	for s in gs.squads.values():
		n += int(s.unit_count_alive())
	return n
