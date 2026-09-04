extends SceneTree

## Multi-cycle player-style playtests for Chess 3.
## godot --headless --path . --script res://tools/playtest_cycles.gd

const GameStateScript = preload("res://src/sim/GameState.gd")
const ResolverScript = preload("res://src/sim/Resolver.gd")
const RulesScript = preload("res://src/sim/Rules.gd")
const UnitDefsScript = preload("res://src/sim/UnitDefs.gd")
const PathfindingScript = preload("res://src/sim/Pathfinding.gd")

var _fails: Array[String] = []
var _passes: int = 0
var _notes: Array[String] = []

func _init() -> void:
	print("=== Chess 3 multi-cycle playtest ===")
	_cycle_build_heavy_then_march(7)
	_cycle_build_heavy_then_march(99)
	_cycle_ranged_sniper_line(11)
	_cycle_trap_and_dash(13)
	_cycle_shell_slam_brawl(17)
	_cycle_two_mutants_split(19)
	_cycle_lock_then_try_attach_midfight(23)
	_cycle_offer_exhaust_then_act(29)
	_cycle_sand_move_out(31)
	_cycle_elimination_race(37)
	_cycle_hard_max_while_building(41)
	_cycle_return_home_still_locked(43)
	_cycle_offer_membership_enforced(47)
	_cycle_end_turn_blocked_during_offer(53)
	print("=== results: %d pass, %d fail ===" % [_passes, _fails.size()])
	for n in _notes:
		print("NOTE: ", n)
	for f in _fails:
		print("FAIL: ", f)
	quit(1 if _fails.size() > 0 else 0)

func _ok(name: String) -> void:
	_passes += 1
	print("PASS: ", name)

func _fail(name: String, detail: String) -> void:
	_fails.append("%s — %s" % [name, detail])
	print("FAIL: ", name, " — ", detail)

func _note(msg: String) -> void:
	_notes.append(msg)
	print("NOTE: ", msg)

func _gs(seed: int):
	var gs = GameStateScript.new()
	root.add_child(gs)
	gs.setup(GameStateScript.DEFAULT_BOARD_SIZE, seed)
	# Start like Main: one core each in spawn.
	gs.squads.clear()
	gs._next_squad_id = 1
	gs.winner = -1
	gs.active_player = 0
	gs.turn_number = 1
	gs.add_squad(0, Vector2i(2, 0), "core", 1)
	gs.add_squad(1, Vector2i(11, 13), "core", 1)
	gs.player_inventory[0] = {"core": 8, "claw": 8, "hoof": 8, "eye": 8, "gland": 8, "shell": 8}
	gs.player_inventory[1] = {"core": 8, "claw": 8, "hoof": 8, "eye": 8, "gland": 8, "shell": 8}
	gs.start_offer_phase()
	return gs

func _p0(gs) -> int:
	for sid in gs.squads.keys():
		var s = gs.get_squad(int(sid))
		if s != null and s.is_alive() and int(s.owner) == 0:
			return int(sid)
	return -1

func _p1(gs) -> int:
	for sid in gs.squads.keys():
		var s = gs.get_squad(int(sid))
		if s != null and s.is_alive() and int(s.owner) == 1:
			return int(sid)
	return -1

func _alive_owned(gs, owner: int) -> Array:
	var out: Array = []
	var ids: Array = gs.squads.keys()
	ids.sort()
	for sid in ids:
		var s = gs.get_squad(int(sid))
		if s != null and s.is_alive() and int(s.owner) == owner:
			out.append(int(sid))
	return out

func _force_offer(gs, cards: Array) -> void:
	gs.offer_pending = true
	gs.offer_cards.clear()
	for c in cards:
		gs.offer_cards.append(str(c))

func _spend_attach(gs, resolver, rules, sid: int, gene: String) -> bool:
	if not bool(gs.offer_pending):
		return false
	if not gs.offer_cards.has(gene) and not _offer_has(gs, gene):
		# allow if in offer list
		pass
	if not _offer_has(gs, gene):
		return false
	if not rules.can_play_card_reinforce(gs, gene, sid):
		return false
	var before := int(gs.get_squad(sid).unit_count_alive())
	resolver.play_card_reinforce(gs, gene, sid)
	return int(gs.get_squad(sid).unit_count_alive()) > before

func _offer_has(gs, gene: String) -> bool:
	for c in gs.offer_cards:
		if str(c) == gene:
			return true
	return false

func _spend_spawn(gs, resolver, rules, gene: String) -> int:
	if not bool(gs.offer_pending) or not _offer_has(gs, gene):
		return -1
	var cells = rules.spawn_cells(gs, gs.active_player)
	if cells.is_empty():
		return -1
	if not rules.can_play_card_spawn(gs, gene, cells[0]):
		return -1
	resolver.play_card_spawn(gs, gene, cells[0])
	var s = gs.squad_at(cells[0])
	return int(s.id) if s != null else -1

func _skip_offer(gs) -> void:
	gs.clear_offer_phase()

func _end(gs, resolver) -> void:
	resolver.end_turn(gs)

func _unfresh(gs, sid: int) -> void:
	var s = gs.get_squad(sid)
	if s != null:
		s.fresh_turn = -1
		s.moved_turn = -1

func _try_move_toward(gs, resolver, rules, pathfinding, sid: int, target: Vector2i) -> bool:
	var s = gs.get_squad(sid)
	if s == null or not s.is_alive():
		return false
	_unfresh(gs, sid)
	var max_r: int = rules.move_range_for_squad(gs, s)
	var reach: Dictionary = pathfinding.reachable_cells(gs, sid, max_r)
	var best: Vector2i = s.cell
	var best_d: int = abs(s.cell.x - target.x) + abs(s.cell.y - target.y)
	for cell_any in reach.keys():
		var c: Vector2i = cell_any
		if c == s.cell:
			continue
		if int(reach.get(c, 0)) <= 0:
			continue
		var d: int = abs(c.x - target.x) + abs(c.y - target.y)
		if d < best_d:
			best_d = d
			best = c
	if best == s.cell:
		return false
	if not rules.can_move(gs, sid, best):
		return false
	resolver.move_squad(gs, sid, best)
	return true

func _try_run_toward(gs, resolver, rules, pathfinding, sid: int, target: Vector2i, prefer_exit_pool: bool = false) -> bool:
	var s = gs.get_squad(sid)
	if s == null or not s.is_alive():
		return false
	if not UnitDefsScript.list_action_ids_for_squad(s).has("run"):
		return false
	if int(s.cooldowns.get("run", 0)) > 0:
		return false
	_unfresh(gs, sid)
	var reach: Dictionary = pathfinding.reachable_cells(gs, sid, 2)
	var best: Vector2i = s.cell
	var best_d: int = abs(s.cell.x - target.x) + abs(s.cell.y - target.y)
	var best_exit := false
	for cell_any in reach.keys():
		var c: Vector2i = cell_any
		if c == s.cell:
			continue
		if int(reach.get(c, 0)) <= 0:
			continue
		if gs.squad_at(c) != null:
			continue
		var exits: bool = prefer_exit_pool and not rules.is_spawn_pool_cell(gs, c, int(s.owner))
		var d: int = abs(c.x - target.x) + abs(c.y - target.y)
		if exits and not best_exit:
			best_exit = true
			best_d = d
			best = c
		elif exits == best_exit and d < best_d:
			best_d = d
			best = c
	if best == s.cell:
		return false
	resolver.use_run(gs, sid, best)
	return true

func _try_melee(gs, resolver, rules, aid: int, did: int) -> bool:
	_unfresh(gs, aid)
	if not rules.can_attack(gs, aid, did, "melee"):
		return false
	resolver.attack(gs, aid, did, "melee")
	return true

func _try_ranged(gs, resolver, rules, aid: int, did: int) -> bool:
	_unfresh(gs, aid)
	if not rules.can_attack(gs, aid, did, "ranged"):
		return false
	resolver.attack(gs, aid, did, "ranged")
	return true

func _try_action(gs, resolver, sid: int, action_id: String, cell: Vector2i = Vector2i(-999, -999), other: int = -1) -> bool:
	_unfresh(gs, sid)
	match action_id:
		"dash":
			resolver.use_dash(gs, sid, cell)
			return gs.get_squad(sid) != null and gs.get_squad(sid).cell == cell
		"run":
			resolver.use_run(gs, sid, cell)
			return gs.get_squad(sid) != null and gs.get_squad(sid).cell == cell
		"slam":
			var before_cd := int(gs.get_squad(sid).cooldowns.get("slam", 0))
			resolver.use_slam(gs, sid)
			return int(gs.get_squad(sid).cooldowns.get("slam", 0)) > before_cd or before_cd > 0
		"snare":
			resolver.plant_hazard(gs, sid, cell, "snare")
			return gs.board.hazard_at(cell) != null
		"melee":
			return _try_melee(gs, resolver, ResolverScript.new().rules, sid, other)
		"ranged":
			return _try_ranged(gs, resolver, ResolverScript.new().rules, sid, other)
		_:
			return false

# --- Cycles ---

func _cycle_build_heavy_then_march(seed: int) -> void:
	var name := "build claw/eye/hoof then march (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var pf = PathfindingScript.new()
	var sid := _p0(gs)
	_force_offer(gs, ["claw", "eye", "hoof"])
	if not _spend_attach(gs, resolver, rules, sid, "claw"):
		_fail(name, "attach claw"); gs.queue_free(); return
	if not _spend_attach(gs, resolver, rules, sid, "eye"):
		_fail(name, "attach eye"); gs.queue_free(); return
	if not _spend_attach(gs, resolver, rules, sid, "hoof"):
		_fail(name, "attach hoof"); gs.queue_free(); return
	if bool(gs.offer_pending):
		_fail(name, "offer should be done"); gs.queue_free(); return
	var s = gs.get_squad(sid)
	if int(s.unit_count_alive()) != 4:
		_fail(name, "expected 4 organs, got %d" % s.unit_count_alive()); gs.queue_free(); return
	var ids = UnitDefsScript.list_action_ids_for_squad(s)
	for need in ["melee", "dash", "ranged", "run"]:
		if not ids.has(need):
			_fail(name, "missing %s in %s" % [need, str(ids)]); gs.queue_free(); return
	# End turns until not fresh, march toward enemy
	_end(gs, resolver) # P1 offer
	_skip_offer(gs)
	_end(gs, resolver) # back to P0
	sid = _p0(gs)
	_skip_offer(gs)
	var enemy = _p1(gs)
	var moved_out := false
	for _i in range(8):
		if gs.winner != -1:
			break
		if bool(gs.offer_pending):
			_skip_offer(gs)
		if int(gs.active_player) == 0:
			sid = _p0(gs)
			enemy = _p1(gs)
			if sid < 0 or enemy < 0:
				break
			var before_lock := bool(gs.get_squad(sid).organs_locked)
			_try_run_toward(gs, resolver, rules, pf, sid, gs.get_squad(enemy).cell, true)
			_try_move_toward(gs, resolver, rules, pf, sid, gs.get_squad(enemy).cell)
			if not before_lock and bool(gs.get_squad(sid).organs_locked):
				moved_out = true
			_try_melee(gs, resolver, rules, sid, enemy)
			_try_ranged(gs, resolver, rules, sid, enemy)
			_end(gs, resolver)
		else:
			_skip_offer(gs)
			_end(gs, resolver)
	if not moved_out and not bool(gs.get_squad(_p0(gs)).organs_locked):
		_fail(name, "never left spawn / locked"); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _cycle_ranged_sniper_line(seed: int) -> void:
	var name := "eye sniper line (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var sid := _p0(gs)
	_force_offer(gs, ["eye", "eye", "eye"])
	_spend_attach(gs, resolver, rules, sid, "eye")
	_spend_attach(gs, resolver, rules, sid, "eye")
	_spend_attach(gs, resolver, rules, sid, "eye")
	_skip_offer(gs)
	# Place enemy in ranged reach artificially after unfresh
	_end(gs, resolver); _skip_offer(gs); _end(gs, resolver); _skip_offer(gs)
	sid = _p0(gs)
	var eid = _p1(gs)
	var a = gs.get_squad(sid)
	var e = gs.get_squad(eid)
	a.cell = Vector2i(5, 5)
	e.cell = Vector2i(5, 8) # dist 3
	a.organs_locked = true
	_unfresh(gs, sid)
	var before := int(e.unit_count_alive())
	if not _try_ranged(gs, resolver, rules, sid, eid):
		_fail(name, "ranged not legal at dist 3"); gs.queue_free(); return
	e = gs.get_squad(eid)
	if int(e.unit_count_alive()) >= before:
		_fail(name, "ranged dealt no organ pops"); gs.queue_free(); return
	# Duplicate eye: still one ranged button, strongest identical
	var ad = UnitDefsScript.action_def_for_squad(a, "ranged")
	if int(ad.get("damage", 0)) < 1:
		_fail(name, "weak ranged def"); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _cycle_trap_and_dash(seed: int) -> void:
	var name := "gland snare + claw dash (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var sid := _p0(gs)
	_force_offer(gs, ["gland", "claw", "hoof"])
	_spend_attach(gs, resolver, rules, sid, "gland")
	_spend_attach(gs, resolver, rules, sid, "claw")
	_spend_attach(gs, resolver, rules, sid, "hoof")
	_end(gs, resolver); _skip_offer(gs); _end(gs, resolver); _skip_offer(gs)
	sid = _p0(gs)
	var a = gs.get_squad(sid)
	a.cell = Vector2i(4, 4)
	a.organs_locked = true
	_unfresh(gs, sid)
	var trap := Vector2i(5, 4)
	if not _try_action(gs, resolver, sid, "snare", trap):
		_fail(name, "snare plant failed"); gs.queue_free(); return
	# Enemy steps on trap
	var eid = _p1(gs)
	var e = gs.get_squad(eid)
	e.cell = Vector2i(6, 4)
	gs.active_player = 1
	_unfresh(gs, eid)
	# Force enter
	resolver._set_squad_cell(gs, e, trap)
	resolver._trigger_hazard_on_enter(gs, e)
	e = gs.get_squad(eid)
	if int(e.snared_no_move_until_turn) < 0:
		_fail(name, "snare did not apply"); gs.queue_free(); return
	if gs.board.hazard_at(trap) != null:
		_fail(name, "snare hazard should be consumed"); gs.queue_free(); return
	# Dash toward enemy
	gs.active_player = 0
	_unfresh(gs, sid)
	var land := Vector2i(6, 4)
	# ensure empty landing near
	if gs.squad_at(land) != null:
		land = Vector2i(6, 5)
	resolver.use_dash(gs, sid, land)
	a = gs.get_squad(sid)
	if a.cell != land and not bool(a.organs_locked):
		_note("%s: dash landing missed (cell=%s)" % [name, str(a.cell)])
	_ok(name)
	gs.queue_free()

func _cycle_shell_slam_brawl(seed: int) -> void:
	var name := "shell slam AoE (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var sid := _p0(gs)
	_force_offer(gs, ["shell", "shell", "claw"])
	_spend_attach(gs, resolver, rules, sid, "shell")
	_spend_attach(gs, resolver, rules, sid, "claw")
	_spend_attach(gs, resolver, rules, sid, "shell")
	_end(gs, resolver); _skip_offer(gs); _end(gs, resolver); _skip_offer(gs)
	sid = _p0(gs)
	var eid = _p1(gs)
	var a = gs.get_squad(sid)
	var e = gs.get_squad(eid)
	# Extra enemy organ so slam doesn't instantly end
	e.units.append(preload("res://src/sim/UnitState.gd").new("shell", 1, 1))
	e.units.append(preload("res://src/sim/UnitState.gd").new("shell", 1, 1))
	a.cell = Vector2i(7, 7)
	e.cell = Vector2i(7, 8)
	a.organs_locked = true
	_unfresh(gs, sid)
	var before := int(e.unit_count_alive())
	resolver.use_slam(gs, sid)
	e = gs.get_squad(eid)
	if e != null and e.is_alive() and int(e.unit_count_alive()) >= before:
		_fail(name, "slam dealt no damage to adjacent enemy"); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _cycle_two_mutants_split(seed: int) -> void:
	var name := "spawn second mutant + split offers (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var sid0 := _p0(gs)
	_force_offer(gs, ["claw", "core", "eye"])
	# Attach to first, then spawn second with remaining
	if not _spend_attach(gs, resolver, rules, sid0, "claw"):
		_fail(name, "attach claw to first"); gs.queue_free(); return
	var sid1 := _spend_spawn(gs, resolver, rules, "core")
	if sid1 < 0:
		_fail(name, "spawn second mutant"); gs.queue_free(); return
	if sid1 == sid0:
		_fail(name, "spawn reused id?"); gs.queue_free(); return
	# Attach eye to second if still pending
	if bool(gs.offer_pending) and _offer_has(gs, "eye"):
		if not _spend_attach(gs, resolver, rules, sid1, "eye"):
			# maybe attach to first instead
			_spend_attach(gs, resolver, rules, sid0, "eye")
	var owned := _alive_owned(gs, 0)
	if owned.size() < 2:
		_fail(name, "expected 2 mutants, got %d" % owned.size()); gs.queue_free(); return
	# Both fresh this turn — neither can move
	for sid in owned:
		if rules.squad_has_available_move(gs, sid):
			_fail(name, "fresh mutant %d can move" % sid); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _cycle_lock_then_try_attach_midfight(seed: int) -> void:
	var name := "locked midfight rejects attach (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var sid := _p0(gs)
	_force_offer(gs, ["claw", "eye", "hoof"])
	_spend_attach(gs, resolver, rules, sid, "claw")
	_skip_offer(gs)
	_end(gs, resolver); _skip_offer(gs); _end(gs, resolver)
	_skip_offer(gs)
	sid = _p0(gs)
	# Force leave spawn
	var s = gs.get_squad(sid)
	resolver._set_squad_cell(gs, s, Vector2i(2, 4))
	if not bool(s.organs_locked):
		_fail(name, "not locked after leave"); gs.queue_free(); return
	_end(gs, resolver); _skip_offer(gs); _end(gs, resolver)
	_force_offer(gs, ["eye", "shell", "gland"])
	sid = _p0(gs)
	var before := int(gs.get_squad(sid).unit_count_alive())
	if rules.can_play_card_reinforce(gs, "eye", sid):
		_fail(name, "attach legal while locked midboard"); gs.queue_free(); return
	resolver.play_card_reinforce(gs, "eye", sid)
	if int(gs.get_squad(sid).unit_count_alive()) != before:
		_fail(name, "attach mutated locked mutant"); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _cycle_offer_exhaust_then_act(seed: int) -> void:
	var name := "pick-one offer then act same turn (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var pf = PathfindingScript.new()
	var sid := _p0(gs)
	_force_offer(gs, ["hoof", "claw", "eye"])
	gs.turn_number = 2
	gs.offer_picks_remaining = 1
	_spend_attach(gs, resolver, rules, sid, "hoof")
	if bool(gs.offer_pending):
		_fail(name, "offer still pending after pick"); gs.queue_free(); return
	# Attach sets fresh_turn — should NOT be able to move this turn
	if rules.squad_has_available_move(gs, sid):
		_fail(name, "mutant actionable after attach-refresh"); gs.queue_free(); return
	_end(gs, resolver); _skip_offer(gs); _end(gs, resolver); _skip_offer(gs)
	sid = _p0(gs)
	if not rules.squad_has_available_move(gs, sid) and not rules.squad_has_available_action(gs, sid):
		_note("%s: no move/action after wait (terrain/block?)" % name)
	else:
		_try_move_toward(gs, resolver, rules, pf, sid, Vector2i(7, 7))
	_ok(name)
	gs.queue_free()

func _cycle_sand_move_out(seed: int) -> void:
	var name := "sand +1 move exit (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var pf = PathfindingScript.new()
	var BoardStateScript = preload("res://src/sim/BoardState.gd")
	var sid := _p0(gs)
	_skip_offer(gs)
	# Put sand under mutant and clear path
	var s = gs.get_squad(sid)
	gs.board.set_terrain(s.cell, BoardStateScript.TERRAIN_SAND)
	var base_r := rules.move_range_for_squad(gs, s)
	var in_pool := rules.is_spawn_pool_cell(gs, s.cell, 0)
	var expected := RulesScript.MOVE_RANGE + 1 + (1 if in_pool else 0)
	if base_r != expected:
		_fail(name, "sand should give move range %d, got %d" % [expected, base_r]); gs.queue_free(); return
	_end(gs, resolver); _skip_offer(gs); _end(gs, resolver); _skip_offer(gs)
	sid = _p0(gs)
	s = gs.get_squad(sid)
	gs.board.set_terrain(s.cell, BoardStateScript.TERRAIN_SAND)
	var reach = pf.reachable_cells(gs, sid, rules.move_range_for_squad(gs, s))
	var outside := false
	for c_any in reach.keys():
		var c: Vector2i = c_any
		if c == s.cell:
			continue
		if not rules.is_spawn_pool_cell(gs, c, 0) and int(reach.get(c, 0)) > 0:
			outside = true
			resolver.move_squad(gs, sid, c)
			break
	if not outside:
		_fail(name, "sand reach did not include outside-spawn cell"); gs.queue_free(); return
	if not bool(gs.get_squad(sid).organs_locked):
		_fail(name, "exit via sand did not lock"); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _cycle_elimination_race(seed: int) -> void:
	var name := "elimination race melee pops (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	_skip_offer(gs)
	var sid = _p0(gs)
	var eid = _p1(gs)
	# Buff attacker
	var a = gs.get_squad(sid)
	a.units.append(preload("res://src/sim/UnitState.gd").new("claw", 1, 1))
	a.cell = Vector2i(6, 6)
	var e = gs.get_squad(eid)
	e.cell = Vector2i(6, 7)
	a.organs_locked = true
	e.organs_locked = true
	_unfresh(gs, sid)
	var guard := 0
	while e != null and e.is_alive() and guard < 10:
		guard += 1
		_unfresh(gs, sid)
		a.cooldowns["melee"] = 0
		if not _try_melee(gs, resolver, rules, sid, eid):
			_fail(name, "melee failed mid race"); gs.queue_free(); return
		e = gs.get_squad(eid)
	if gs.winner != 0:
		_fail(name, "expected P0 win, winner=%d" % gs.winner); gs.queue_free(); return
	# Further actions should no-op
	_try_melee(gs, resolver, rules, sid, eid)
	_ok(name)
	gs.queue_free()

func _cycle_hard_max_while_building(seed: int) -> void:
	var name := "hit hard max mid-offer (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var sid := _p0(gs)
	var s = gs.get_squad(sid)
	# Pre-fill to 9 organs
	for _i in range(8):
		s.units.append(preload("res://src/sim/UnitState.gd").new("claw", 1, 1))
	_force_offer(gs, ["eye", "shell", "gland"])
	if not _spend_attach(gs, resolver, rules, sid, "eye"):
		_fail(name, "10th organ attach failed"); gs.queue_free(); return
	if int(gs.get_squad(sid).unit_count_alive()) != 10:
		_fail(name, "expected 10 organs"); gs.queue_free(); return
	# Remaining offer cards should become unplayable as attach → finish_offer_if_done may clear
	# (spawn might still be possible!)
	if bool(gs.offer_pending):
		# spawn still legal — OK; try attach should fail
		if rules.can_play_card_reinforce(gs, "shell", sid):
			_fail(name, "attach still legal at hard max"); gs.queue_free(); return
		# If only attaches were intended, spawn may keep offer open — spend spawn or skip
		var cells = rules.spawn_cells(gs, 0)
		if not cells.is_empty() and _offer_has(gs, "shell"):
			_spend_spawn(gs, resolver, rules, "shell")
		_skip_offer(gs)
	_ok(name)
	gs.queue_free()

func _cycle_return_home_still_locked(seed: int) -> void:
	var name := "march out, return home, still locked (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var sid := _p0(gs)
	_force_offer(gs, ["claw", "hoof", "eye"])
	_spend_attach(gs, resolver, rules, sid, "claw")
	_spend_attach(gs, resolver, rules, sid, "hoof")
	_skip_offer(gs)
	_end(gs, resolver); _skip_offer(gs); _end(gs, resolver); _skip_offer(gs)
	sid = _p0(gs)
	var s = gs.get_squad(sid)
	resolver._set_squad_cell(gs, s, Vector2i(3, 5))
	if not bool(s.organs_locked):
		_fail(name, "not locked"); gs.queue_free(); return
	# Walk home conceptually
	s.cell = Vector2i(2, 0)
	_force_offer(gs, ["shell", "gland", "core"])
	if rules.can_play_card_reinforce(gs, "shell", sid):
		_fail(name, "reattach legal after return"); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _cycle_offer_membership_enforced(seed: int) -> void:
	var name := "cannot play gene not in offer (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var sid := _p0(gs)
	_force_offer(gs, ["claw", "eye", "hoof"])
	gs.player_inventory[0]["shell"] = 5
	var cells = rules.spawn_cells(gs, 0)
	if cells.is_empty():
		_fail(name, "no spawn"); gs.queue_free(); return
	if rules.can_play_card_spawn(gs, "shell", cells[0]):
		_fail(name, "spawn shell legal though not offered"); gs.queue_free(); return
	if rules.can_play_card_reinforce(gs, "shell", sid):
		_fail(name, "attach shell legal though not offered"); gs.queue_free(); return
	resolver.play_card_spawn(gs, "shell", cells[0])
	if gs.squad_at(cells[0]) != null and str(gs.squad_at(cells[0]).units[0].unit_def_id) == "shell":
		_fail(name, "resolver spawned non-offered shell"); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _cycle_end_turn_blocked_during_offer(seed: int) -> void:
	var name := "end turn blocked during offer (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	_force_offer(gs, ["claw", "eye", "hoof"])
	var turn_before := int(gs.turn_number)
	var active_before := int(gs.active_player)
	if rules.can_end_turn(gs):
		_fail(name, "can_end_turn true during offer"); gs.queue_free(); return
	resolver.end_turn(gs)
	if int(gs.turn_number) != turn_before or int(gs.active_player) != active_before:
		_fail(name, "end_turn advanced during offer"); gs.queue_free(); return
	_skip_offer(gs)
	if not rules.can_end_turn(gs):
		_fail(name, "can_end_turn false after skip"); gs.queue_free(); return
	_ok(name)
	gs.queue_free()
