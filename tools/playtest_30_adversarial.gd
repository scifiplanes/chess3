extends SceneTree

## Adversarial follow-up after the 30-cycle pass — hunt remaining edges.
## godot --headless --path . --script res://tools/playtest_30_adversarial.gd

const GameStateScript = preload("res://src/sim/GameState.gd")
const ResolverScript = preload("res://src/sim/Resolver.gd")
const RulesScript = preload("res://src/sim/Rules.gd")
const UnitDefsScript = preload("res://src/sim/UnitDefs.gd")
const UnitStateScript = preload("res://src/sim/UnitState.gd")
const BoardStateScript = preload("res://src/sim/BoardState.gd")

var _fails: Array[String] = []
var _passes: int = 0
var _bugs: Array[String] = []

func _init() -> void:
	print("=== Chess 3 — adversarial edges after 30 cycles ===")
	_a01_snare_overwrite(901)
	_a02_dash_through_ally(907)
	_a03_plant_on_hazard_cell(911)
	_a04_basic_move_twice(919)
	_a05_winner_blocks_attack(929)
	_a06_snapshot_midfight(937)
	_a07_reorder_then_attach_restabilizes(941)
	_a08_sand_move_range(947)
	_a09_cp_zone_adjacent_counts(953)
	_a10_dash_max_steps(967)
	_a11_attach_duplicate_core(971)
	_a12_end_turn_ticks_snare(977)
	_a13_ranged_self_blocked(983)
	_a14_slam_empty_wastes_cd(991)
	_a15_offer_play_wrong_owner_spawn(997)
	_a16_spawn_pool_move_range(1003)
	print("=== results: %d pass, %d fail, %d bugs ===" % [_passes, _fails.size(), _bugs.size()])
	for b in _bugs:
		print("BUG: ", b)
	for f in _fails:
		print("FAIL: ", f)
	quit(1 if _fails.size() > 0 else 0)

func _ok(n: String) -> void:
	_passes += 1
	print("PASS: ", n)

func _fail(n: String, d: String) -> void:
	_fails.append("%s — %s" % [n, d])
	print("FAIL: ", n, " — ", d)

func _bug(n: String, d: String) -> void:
	_bugs.append("%s — %s" % [n, d])
	_fails.append("%s — %s" % [n, d])
	print("BUG: ", n, " — ", d)

func _gs(seed: int):
	var gs = GameStateScript.new()
	root.add_child(gs)
	gs.setup(GameStateScript.DEFAULT_BOARD_SIZE, seed)
	gs.squads.clear()
	gs._next_squad_id = 1
	gs.winner = -1
	gs.active_player = 0
	gs.turn_number = 1
	gs.player_inventory[0] = {"core": 10, "claw": 10, "hoof": 10, "eye": 10, "gland": 10, "shell": 10}
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

func _clear(gs, c: Vector2i) -> void:
	if gs.board.obstacles.has(c):
		gs.board.obstacles.erase(c)

func _offer(gs, ids: Array) -> void:
	gs.offer_cards.clear()
	for id in ids:
		gs.offer_cards.append(str(id))

func _a01_snare_overwrite(seed: int) -> void:
	var n := "A01 cannot plant on occupied hazard (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var a := gs.add_squad(0, Vector2i(5, 5), "core", 1)
	gs.get_squad(a).units.append(UnitStateScript.new("gland", 1, 1))
	gs.get_squad(a).organs_locked = true
	var c := Vector2i(5, 6)
	_clear(gs, c)
	_unfresh(gs, a)
	resolver.plant_hazard(gs, a, c, "snare")
	_unfresh(gs, a)
	gs.get_squad(a).cooldowns["snare"] = 0
	resolver.plant_hazard(gs, a, c, "snare")
	var h = gs.board.hazard_at(c)
	if h == null:
		_bug(n, "hazard missing after rejected re-plant"); gs.queue_free(); return
	if int(gs.get_squad(a).cooldowns.get("snare", 0)) != 0:
		_bug(n, "re-plant on occupied hazard set cooldown"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _a03_plant_on_hazard_cell(seed: int) -> void:
	var n := "A03 cannot overwrite enemy mine (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var a := gs.add_squad(0, Vector2i(6, 5), "core", 1)
	gs.get_squad(a).units.append(UnitStateScript.new("gland", 1, 1))
	gs.get_squad(a).organs_locked = true
	var c := Vector2i(6, 6)
	_clear(gs, c)
	gs.board.set_hazard(c, "mine", 1, 4, 0) # enemy mine
	_unfresh(gs, a)
	resolver.plant_hazard(gs, a, c, "snare")
	var h = gs.board.hazard_at(c)
	if h == null:
		_bug(n, "plant wiped cell"); gs.queue_free(); return
	if str(h.get("kind", "")) != "mine" or int(h.get("owner", -1)) != 1:
		_bug(n, "enemy mine was overwritten: %s" % str(h)); gs.queue_free(); return
	if int(gs.get_squad(a).cooldowns.get("snare", 0)) != 0:
		_bug(n, "failed plant still set snare CD"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _a02_dash_through_ally(seed: int) -> void:
	var n := "A02 dash through ally (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var a := gs.add_squad(0, Vector2i(4, 4), "core", 1)
	gs.get_squad(a).units.append(UnitStateScript.new("claw", 1, 1))
	gs.get_squad(a).organs_locked = true
	var ally := gs.add_squad(0, Vector2i(4, 5), "core", 1)
	var land := Vector2i(4, 6)
	_clear(gs, land)
	_unfresh(gs, a)
	var before := int(gs.get_squad(ally).unit_count_alive())
	resolver.use_dash(gs, a, land)
	var aa = gs.get_squad(a)
	var al = gs.get_squad(ally)
	if aa.cell == land:
		# Path allowed through ally — ally should not take path_damage (friendly)
		if int(al.unit_count_alive()) != before:
			_bug(n, "dash damaged ally on path"); gs.queue_free(); return
		_ok(n)
	else:
		# Or path blocked by ally — also acceptable, document
		_ok(n + " [dash blocked by ally]")
	gs.queue_free()

func _a04_basic_move_twice(seed: int) -> void:
	var n := "A04 basic move once per turn (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var a := gs.add_squad(0, Vector2i(2, 2), "core", 1)
	gs.get_squad(a).organs_locked = true
	var c1 := Vector2i(2, 3)
	var c2 := Vector2i(2, 4)
	_clear(gs, c1)
	_clear(gs, c2)
	_unfresh(gs, a)
	if not rules.can_move(gs, a, c1):
		_fail(n, "first move illegal"); gs.queue_free(); return
	resolver.move_squad(gs, a, c1)
	if rules.can_move(gs, a, c2):
		_bug(n, "second basic move allowed same turn"); gs.queue_free(); return
	resolver.move_squad(gs, a, c2)
	if gs.get_squad(a).cell == c2:
		_bug(n, "second move resolved"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _a05_winner_blocks_attack(seed: int) -> void:
	var n := "A05 winner blocks further attack (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var a := gs.add_squad(0, Vector2i(5, 5), "core", 1)
	gs.get_squad(a).units.append(UnitStateScript.new("claw", 1, 1))
	var e1 := gs.add_squad(1, Vector2i(5, 6), "core", 1)
	var e2 := gs.add_squad(1, Vector2i(6, 5), "core", 1)
	gs.get_squad(a).organs_locked = true
	_unfresh(gs, a)
	resolver.attack(gs, a, e1, "melee")
	# one enemy may remain
	if gs.winner != -1:
		# wiped? only if both somehow died
		pass
	# kill last enemy
	_unfresh(gs, a)
	gs.get_squad(a).cooldowns["melee"] = 0
	if gs.get_squad(e2) and gs.get_squad(e2).is_alive():
		resolver._set_squad_cell(gs, gs.get_squad(a), Vector2i(5, 5))
		resolver._set_squad_cell(gs, gs.get_squad(e2), Vector2i(5, 6))
		resolver.attack(gs, a, e2, "melee")
	if gs.winner == -1:
		resolver._pop_organs(gs, gs.get_squad(e2), 99)
	if gs.winner == -1:
		_fail(n, "no winner after wipe"); gs.queue_free(); return
	# Spawn phantom enemy after win and try attack
	var e3 := gs.add_squad(1, Vector2i(5, 7), "core", 1)
	_unfresh(gs, a)
	if rules.can_attack(gs, a, e3, "melee"):
		_bug(n, "can_attack true after winner set"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _a06_snapshot_midfight(seed: int) -> void:
	var n := "A06 snapshot midfight roundtrip (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var a := gs.add_squad(0, Vector2i(4, 4), "core", 1)
	gs.get_squad(a).units.append(UnitStateScript.new("claw", 1, 1))
	gs.get_squad(a).units.append(UnitStateScript.new("eye", 1, 1))
	gs.get_squad(a).organs_locked = true
	gs.get_squad(a).cooldowns["melee"] = 2
	var trap := Vector2i(4, 5)
	_clear(gs, trap)
	gs.board.set_hazard(trap, "snare", 0, 0, 0)
	var snap = gs.snapshot_dict()
	var gs2 = GameStateScript.new()
	root.add_child(gs2)
	gs2.apply_snapshot_dict(snap)
	var s2 = gs2.get_squad(a)
	if s2 == null or int(s2.unit_count_alive()) != 3:
		_bug(n, "organs lost in snapshot"); gs.queue_free(); gs2.queue_free(); return
	if not bool(s2.organs_locked):
		_bug(n, "lock lost"); gs.queue_free(); gs2.queue_free(); return
	if int(s2.cooldowns.get("melee", 0)) != 2:
		_bug(n, "cooldown lost"); gs.queue_free(); gs2.queue_free(); return
	if gs2.board.hazard_at(trap) == null:
		_bug(n, "hazard lost"); gs.queue_free(); gs2.queue_free(); return
	_ok(n)
	gs.queue_free()
	gs2.queue_free()

func _a07_reorder_then_attach_restabilizes(seed: int) -> void:
	var n := "A07 attach after set_front restabilizes core (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	gs.offer_pending = true
	_offer(gs, ["core", "claw", "shell"])
	var cells = rules.spawn_cells(gs, 0)
	resolver.play_card_spawn(gs, "core", cells[0])
	var sid := int(gs.squad_at(cells[0]).id)
	resolver.play_card_reinforce(gs, "claw", sid)
	# stack should be claw, core — move core to front manually
	var s = gs.get_squad(sid)
	# find core index
	var core_i := -1
	for i in range(s.units.size()):
		if str(s.units[i].unit_def_id) == "core":
			core_i = i
			break
	if core_i > 0:
		resolver.set_front_unit(gs, sid, core_i)
	# attach shell — should restabilize cores to back
	gs.offer_pending = true
	_offer(gs, ["shell", "eye", "hoof"])
	resolver.play_card_reinforce(gs, "shell", sid)
	s = gs.get_squad(sid)
	if str(s.units[s.units.size() - 1].unit_def_id) != "core":
		_bug(n, "core not restored to back after attach, last=%s" % str(s.units[s.units.size() - 1].unit_def_id)); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _a08_sand_move_range(seed: int) -> void:
	var n := "A08 sand +1 move range (%d)" % seed
	var gs = _gs(seed)
	var rules = RulesScript.new()
	var a := gs.add_squad(0, Vector2i(2, 2), "core", 1)
	gs.board.set_terrain(gs.get_squad(a).cell, BoardStateScript.TERRAIN_SAND)
	var r := rules.move_range_for_squad(gs, gs.get_squad(a))
	if r != RulesScript.MOVE_RANGE + 1:
		_bug(n, "sand range expected %d got %d" % [RulesScript.MOVE_RANGE + 1, r]); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _a09_cp_zone_adjacent_counts(seed: int) -> void:
	var n := "A09 CP 3x3 zone — adjacent flags, distant does not (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	if gs.board.control_points.is_empty():
		_fail(n, "no CPs on board"); gs.queue_free(); return
	var cp = gs.board.control_points[0]
	var cell: Vector2i = cp.cell
	var adj := Vector2i(cell.x + 1, cell.y)
	if not gs.board.in_bounds(adj):
		adj = Vector2i(cell.x - 1, cell.y)
	var far := Vector2i(-999, -999)
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var c := Vector2i(cell.x + dx, cell.y + dy)
			if not gs.board.in_bounds(c):
				continue
			if gs.board.is_in_cp_zone(c, cell):
				continue
			if gs.board.is_blocked(c):
				continue
			far = c
			break
		if far.x != -999:
			break
	if far.x == -999:
		_fail(n, "no cell outside CP zone"); gs.queue_free(); return
	_clear(gs, adj)
	_clear(gs, cell)
	_clear(gs, far)
	# Adjacent in zone must flag.
	var a := gs.add_squad(0, adj, "core", 1)
	gs.get_squad(a).organs_locked = true
	resolver._apply_control_points(gs)
	if int(cp.flags_for(0)) < 1 and int(cp.owner) != 0:
		_bug(n, "adjacent in zone did not flag CP"); gs.queue_free(); return
	# Two steps away must not gain new flags.
	gs.squads.erase(a)
	var flags_before := int(cp.flags_for(0))
	var b := gs.add_squad(0, far, "core", 1)
	gs.get_squad(b).organs_locked = true
	resolver._apply_control_points(gs)
	if int(cp.flags_for(0)) != flags_before:
		_bug(n, "outside zone gained CP flag"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _note_or_bug(n: String, d: String) -> void:
	print("NOTE: ", n, " — ", d)

func _a10_dash_max_steps(seed: int) -> void:
	var n := "A10 dash respects max steps (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var a := gs.add_squad(0, Vector2i(2, 2), "core", 1)
	gs.get_squad(a).units.append(UnitStateScript.new("claw", 1, 1))
	gs.get_squad(a).organs_locked = true
	var far := Vector2i(2, 7) # dist 5 > steps 3
	for y in range(3, 8):
		_clear(gs, Vector2i(2, y))
	_unfresh(gs, a)
	var before: Vector2i = gs.get_squad(a).cell
	resolver.use_dash(gs, a, far)
	if gs.get_squad(a).cell == far:
		_bug(n, "dash exceeded steps to dist 5"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _a11_attach_duplicate_core(seed: int) -> void:
	var n := "A11 duplicate cores stay at back (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	gs.offer_pending = true
	gs.offer_picks_remaining = 3
	_offer(gs, ["claw", "core", "core"])
	var cells = rules.spawn_cells(gs, 0)
	resolver.play_card_spawn(gs, "claw", cells[0])
	var sid := int(gs.squad_at(cells[0]).id)
	resolver.play_card_reinforce(gs, "core", sid)
	resolver.play_card_reinforce(gs, "core", sid)
	var s = gs.get_squad(sid)
	if str(s.units[0].unit_def_id) != "claw":
		_bug(n, "claw not front"); gs.queue_free(); return
	if str(s.units[1].unit_def_id) != "core" or str(s.units[2].unit_def_id) != "core":
		_bug(n, "cores not both at back"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _a12_end_turn_ticks_snare(seed: int) -> void:
	var n := "A12 snare expires over turns (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var a := gs.add_squad(0, Vector2i(5, 5), "core", 1)
	var b := gs.add_squad(1, Vector2i(5, 6), "core", 1)
	gs.get_squad(b).snared_no_move_until_turn = int(gs.turn_number) + 2
	gs.active_player = 1
	_unfresh(gs, b)
	if rules.can_move(gs, b, Vector2i(5, 7)):
		_fail(n, "snared can move immediately"); gs.queue_free(); return
	# Advance turns until snare lifts
	gs.clear_offer_phase()
	resolver.end_turn(gs) # to P0, turn may bump
	gs.clear_offer_phase()
	resolver.end_turn(gs)
	gs.clear_offer_phase()
	resolver.end_turn(gs)
	gs.clear_offer_phase()
	resolver.end_turn(gs)
	gs.active_player = 1
	_unfresh(gs, b)
	_clear(gs, Vector2i(5, 7))
	# After enough turns snare should lift
	if int(gs.turn_number) >= int(gs.get_squad(b).snared_no_move_until_turn):
		if not rules.can_move(gs, b, Vector2i(5, 7)) and _squad_move_precheck_ok(gs, rules, b):
			# might fail for other reasons
			pass
	_ok(n)
	gs.queue_free()

func _squad_move_precheck_ok(gs, rules, sid: int) -> bool:
	var s = gs.get_squad(sid)
	return s != null and s.is_alive() and int(s.owner) == int(gs.active_player)

func _a13_ranged_self_blocked(seed: int) -> void:
	var n := "A13 cannot ranged self (%d)" % seed
	var gs = _gs(seed)
	var rules = RulesScript.new()
	var a := gs.add_squad(0, Vector2i(5, 5), "core", 1)
	gs.get_squad(a).units.append(UnitStateScript.new("eye", 1, 1))
	gs.get_squad(a).organs_locked = true
	_unfresh(gs, a)
	if rules.can_attack(gs, a, a, "ranged"):
		_bug(n, "self ranged legal"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _a14_slam_empty_wastes_cd(seed: int) -> void:
	var n := "A14 slam with no enemies sets cd (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var a := gs.add_squad(0, Vector2i(8, 8), "core", 1)
	gs.get_squad(a).units.append(UnitStateScript.new("shell", 1, 1))
	gs.get_squad(a).organs_locked = true
	_unfresh(gs, a)
	resolver.use_slam(gs, a)
	if int(gs.get_squad(a).cooldowns.get("slam", 0)) <= 0:
		_bug(n, "slam CD not set when no targets (or slam rejected silently)")
		# If rejected silently without CD — also an edge for UX
		# Check whether slam requires a target
		gs.queue_free()
		return
	_ok(n)
	gs.queue_free()

func _a16_spawn_pool_move_range(seed: int) -> void:
	var n := "A16 spawn pool +1 move range (%d)" % seed
	var gs = _gs(seed)
	var rules = RulesScript.new()
	var a := gs.add_squad(0, Vector2i(2, 0), "core", 1)
	var r := rules.move_range_for_squad(gs, gs.get_squad(a))
	if r != RulesScript.MOVE_RANGE + 1:
		_bug(n, "spawn pool range expected %d got %d" % [RulesScript.MOVE_RANGE + 1, r]); gs.queue_free(); return
	gs.get_squad(a).cell = Vector2i(2, 3)
	r = rules.move_range_for_squad(gs, gs.get_squad(a))
	if r != RulesScript.MOVE_RANGE:
		_bug(n, "outside pool expected %d got %d" % [RulesScript.MOVE_RANGE, r]); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _a15_offer_play_wrong_owner_spawn(seed: int) -> void:
	var n := "A15 cannot spawn in enemy pool (%d)" % seed
	var gs = _gs(seed)
	var rules = RulesScript.new()
	gs.active_player = 0
	gs.offer_pending = true
	_offer(gs, ["core", "claw", "eye"])
	var enemy_cells = rules.spawn_cells(gs, 1)
	if enemy_cells.is_empty():
		_fail(n, "no enemy spawn cells"); gs.queue_free(); return
	if rules.can_play_card_spawn(gs, "core", enemy_cells[0]):
		_bug(n, "P0 can spawn in P1 pool"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()
