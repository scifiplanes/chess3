extends SceneTree

## Fresh 30 player-style cycles (wave B) — different combos/seeds.
## godot --headless --path . --script res://tools/playtest_30_wave_b.gd

const GameStateScript = preload("res://src/sim/GameState.gd")
const ResolverScript = preload("res://src/sim/Resolver.gd")
const RulesScript = preload("res://src/sim/Rules.gd")
const UnitDefsScript = preload("res://src/sim/UnitDefs.gd")
const UnitStateScript = preload("res://src/sim/UnitState.gd")
const BoardStateScript = preload("res://src/sim/BoardState.gd")

var _fails: Array[String] = []
var _passes: int = 0
var _bugs: Array[String] = []
var _notes: Array[String] = []

func _init() -> void:
	print("=== Chess 3 — 30 live cycles (wave B) ===")
	var cycles: Array = [
		Callable(self, "_b01_eye_gland_control"),
		Callable(self, "_b02_claw_shell_brawler"),
		Callable(self, "_b03_hoof_eye_kite"),
		Callable(self, "_b04_full_six_gene_stack"),
		Callable(self, "_b05_p1_build_and_exit"),
		Callable(self, "_b06_run_then_basic_move"),
		Callable(self, "_b07_dash_onto_enemy_snare"),
		Callable(self, "_b08_dash_onto_own_snare"),
		Callable(self, "_b09_run_onto_enemy_snare"),
		Callable(self, "_b10_contested_cp_no_flag"),
		Callable(self, "_b11_melee_power_drops_after_claw_pop"),
		Callable(self, "_b12_double_gland_two_snares"),
		Callable(self, "_b13_slam_diagonal_not_hit"),
		Callable(self, "_b14_offer_auto_start_on_end_turn"),
		Callable(self, "_b15_attach_enemy_mutant_rejected"),
		Callable(self, "_b16_spawn_last_cell_then_attach_only"),
		Callable(self, "_b17_ranged_obstacle_then_path"),
		Callable(self, "_b18_set_front_while_locked"),
		Callable(self, "_b19_snare_blocks_run"),
		Callable(self, "_b20_multi_mutant_cp_race"),
		Callable(self, "_b21_claw_dash_then_melee_same_turn"),
		Callable(self, "_b22_shell_core_last_stand"),
		Callable(self, "_b23_inventory_exhaust_mid_build"),
		Callable(self, "_b24_diagonal_plant_range"),
		Callable(self, "_b25_winner_blocks_end_turn"),
		Callable(self, "_b26_eye_eye_double_ranged"),
		Callable(self, "_b27_hoof_hoof_run_cd_shared"),
		Callable(self, "_b28_move_onto_cp_and_capture"),
		Callable(self, "_b29_three_way_focus_kill"),
		Callable(self, "_b30_long_skirmish_mixed"),
	]
	assert(cycles.size() == 30)
	for i in range(30):
		cycles[i].call(1100 + i * 13)
	print("=== results: %d pass, %d fail, %d bugs, %d notes ===" % [_passes, _fails.size(), _bugs.size(), _notes.size()])
	for x in _notes:
		print("NOTE: ", x)
	for x in _bugs:
		print("BUG: ", x)
	for x in _fails:
		print("FAIL: ", x)
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

func _note(msg: String) -> void:
	_notes.append(msg)
	print("NOTE: ", msg)

func _gs(seed: int):
	var gs = GameStateScript.new()
	root.add_child(gs)
	gs.setup(GameStateScript.DEFAULT_BOARD_SIZE, seed)
	gs.squads.clear()
	gs._next_squad_id = 1
	gs.winner = -1
	gs.active_player = 0
	gs.turn_number = 1
	gs.player_inventory[0] = {"core": 14, "claw": 14, "hoof": 14, "eye": 14, "gland": 14, "shell": 14}
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

func _sand(gs, c: Vector2i) -> void:
	gs.board.set_terrain(c, BoardStateScript.TERRAIN_SAND)

func _build(gs, resolver, rules, owner: int, genes: Array) -> int:
	gs.active_player = owner
	gs.offer_pending = true
	_offer(gs, genes)
	var cells = rules.spawn_cells(gs, owner)
	if cells.is_empty() or genes.is_empty():
		return -1
	var c: Vector2i = cells[0]
	_clear(gs, c)
	resolver.play_card_spawn(gs, str(genes[0]), c)
	var sq = gs.squad_at(c)
	if sq == null:
		return -1
	var sid := int(sq.id)
	for i in range(1, genes.size()):
		gs.offer_pending = true
		if not gs.offer_cards.has(str(genes[i])):
			_offer(gs, [genes[i], "core", "claw"])
		if rules.can_play_card_reinforce(gs, str(genes[i]), sid):
			resolver.play_card_reinforce(gs, str(genes[i]), sid)
	gs.clear_offer_phase()
	return sid

func _exit(gs, resolver, sid: int) -> void:
	var s = gs.get_squad(sid)
	if s == null:
		return
	var out := Vector2i(s.cell.x, RulesScript.HOME_SPAWN_ROWS + 1) if int(s.owner) == 0 \
		else Vector2i(s.cell.x, int(gs.board.size.y) - RulesScript.HOME_SPAWN_ROWS - 2)
	_clear(gs, out)
	resolver._set_squad_cell(gs, s, out)

func _acts(s) -> Array:
	return UnitDefsScript.list_action_ids_for_squad(s)

# --- cycles ---

func _b01_eye_gland_control(seed: int) -> void:
	var n := "B01 eye+gland control (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var sid := _build(gs, resolver, rules, 0, ["core", "eye", "gland"])
	_exit(gs, resolver, sid)
	var s = gs.get_squad(sid)
	var trap := Vector2i(s.cell.x, s.cell.y + 1)
	_clear(gs, trap)
	_unfresh(gs, sid)
	resolver.plant_hazard(gs, sid, trap, "snare")
	var eid := gs.add_squad(1, Vector2i(trap.x, trap.y + 1), "core", 1)
	gs.get_squad(eid).units.append(UnitStateScript.new("shell", 1, 1))
	resolver._set_squad_cell(gs, gs.get_squad(eid), trap)
	resolver._trigger_hazard_on_enter(gs, gs.get_squad(eid))
	gs.active_player = 0
	_unfresh(gs, sid)
	_sand(gs, s.cell)
	# eye from dist — move back if needed
	resolver._set_squad_cell(gs, s, Vector2i(trap.x, trap.y - 2))
	_sand(gs, s.cell)
	_unfresh(gs, sid)
	if not rules.can_attack(gs, sid, eid, "ranged"):
		_fail(n, "ranged illegal"); gs.queue_free(); return
	resolver.attack(gs, sid, eid, "ranged")
	_ok(n)
	gs.queue_free()

func _b02_claw_shell_brawler(seed: int) -> void:
	var n := "B02 claw+shell brawler (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var sid := _build(gs, resolver, rules, 0, ["core", "claw", "shell"])
	_exit(gs, resolver, sid)
	var s = gs.get_squad(sid)
	var e1 := gs.add_squad(1, Vector2i(s.cell.x, s.cell.y + 1), "core", 1)
	var e2 := gs.add_squad(1, Vector2i(s.cell.x + 1, s.cell.y), "core", 1)
	_unfresh(gs, sid)
	resolver.use_slam(gs, sid)
	_unfresh(gs, sid)
	s.cooldowns["melee"] = 0
	# finish any survivor adjacent
	for eid in [e1, e2]:
		var e = gs.get_squad(eid)
		if e and e.is_alive() and rules.can_attack(gs, sid, eid, "melee"):
			resolver.attack(gs, sid, eid, "melee")
	_ok(n)
	gs.queue_free()

func _b03_hoof_eye_kite(seed: int) -> void:
	var n := "B03 hoof+eye kite (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var sid := _build(gs, resolver, rules, 0, ["core", "hoof", "eye"])
	_exit(gs, resolver, sid)
	var s = gs.get_squad(sid)
	# Keep enemy thick enough that one ranged (1) does not wipe → winner lockout mid-kite.
	var eid := gs.add_squad(1, Vector2i(s.cell.x, s.cell.y + 3), "core", 1)
	gs.get_squad(eid).units.append(UnitStateScript.new("claw", 1, 1))
	gs.get_squad(eid).units.append(UnitStateScript.new("shell", 1, 1))
	_sand(gs, s.cell)
	_unfresh(gs, sid)
	if not rules.can_attack(gs, sid, eid, "ranged"):
		_fail(n, "kite shot illegal"); gs.queue_free(); return
	resolver.attack(gs, sid, eid, "ranged")
	if gs.winner != -1:
		_fail(n, "kite shot wiped match before retreat"); gs.queue_free(); return
	_unfresh(gs, sid)
	var retreat := Vector2i(s.cell.x, s.cell.y - 2)
	_clear(gs, Vector2i(s.cell.x, s.cell.y - 1))
	_clear(gs, retreat)
	resolver.use_run(gs, sid, retreat)
	if gs.get_squad(sid).cell != retreat:
		_fail(n, "run retreat failed"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _b04_full_six_gene_stack(seed: int) -> void:
	var n := "B04 all six genes stacked (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var genes := ["core", "claw", "hoof", "eye", "gland", "shell"]
	var sid := _build(gs, resolver, rules, 0, genes)
	var s = gs.get_squad(sid)
	if int(s.unit_count_alive()) != 6:
		_fail(n, "expected 6 organs got %d" % int(s.unit_count_alive())); gs.queue_free(); return
	if str(s.units[s.units.size() - 1].unit_def_id) != "core":
		_fail(n, "core not back"); gs.queue_free(); return
	var acts = _acts(s)
	for need in ["melee", "dash", "run", "ranged", "snare", "slam"]:
		if not acts.has(need):
			_fail(n, "missing %s in %s" % [need, str(acts)]); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _b05_p1_build_and_exit(seed: int) -> void:
	var n := "B05 P1 build+exit lock (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var sid := _build(gs, resolver, rules, 1, ["core", "claw", "eye"])
	if sid < 0:
		_fail(n, "P1 build failed"); gs.queue_free(); return
	_exit(gs, resolver, sid)
	var s = gs.get_squad(sid)
	if not bool(s.organs_locked):
		_fail(n, "P1 not locked after exit"); gs.queue_free(); return
	if not rules.is_spawn_pool_cell(gs, s.cell, 1) and bool(s.organs_locked):
		pass
	_ok(n)
	gs.queue_free()

func _b06_run_then_basic_move(seed: int) -> void:
	var n := "B06 run then basic move same turn (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var a := gs.add_squad(0, Vector2i(3, 3), "core", 1)
	gs.get_squad(a).units.append(UnitStateScript.new("hoof", 1, 1))
	gs.get_squad(a).organs_locked = true
	var r1 := Vector2i(3, 5)
	var m1 := Vector2i(3, 6)
	_clear(gs, Vector2i(3, 4))
	_clear(gs, r1)
	_clear(gs, m1)
	_unfresh(gs, a)
	resolver.use_run(gs, a, r1)
	if gs.get_squad(a).cell != r1:
		_fail(n, "run failed"); gs.queue_free(); return
	# Design: basic Move is once/turn; abilities are separate. After run, basic move should still be legal.
	if not rules.can_move(gs, a, m1):
		_bug(n, "basic move blocked after run (unexpected if abilities don't consume Move)")
		gs.queue_free()
		return
	resolver.move_squad(gs, a, m1)
	if gs.get_squad(a).cell != m1:
		_fail(n, "basic move after run failed"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _b07_dash_onto_enemy_snare(seed: int) -> void:
	var n := "B07 dash onto enemy snare (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var a := gs.add_squad(0, Vector2i(4, 4), "core", 1)
	gs.get_squad(a).units.append(UnitStateScript.new("claw", 1, 1))
	gs.get_squad(a).organs_locked = true
	var land := Vector2i(4, 6)
	_clear(gs, Vector2i(4, 5))
	_clear(gs, land)
	gs.board.set_hazard(land, "snare", 1, 0, 0)
	_unfresh(gs, a)
	resolver.use_dash(gs, a, land)
	var s = gs.get_squad(a)
	if s.cell != land:
		_fail(n, "dash did not land"); gs.queue_free(); return
	if gs.board.hazard_at(land) != null:
		_bug(n, "enemy snare not consumed on dash enter"); gs.queue_free(); return
	if int(s.snared_no_move_until_turn) < int(gs.turn_number) + 1:
		_bug(n, "dash into snare did not snare dasher"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _b08_dash_onto_own_snare(seed: int) -> void:
	var n := "B08 dash onto own snare (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var a := gs.add_squad(0, Vector2i(5, 4), "core", 1)
	gs.get_squad(a).units.append(UnitStateScript.new("claw", 1, 1))
	gs.get_squad(a).organs_locked = true
	var land := Vector2i(5, 6)
	_clear(gs, Vector2i(5, 5))
	_clear(gs, land)
	gs.board.set_hazard(land, "snare", 0, 0, 0)
	_unfresh(gs, a)
	resolver.use_dash(gs, a, land)
	var s = gs.get_squad(a)
	if s.cell != land:
		_fail(n, "dash failed"); gs.queue_free(); return
	if gs.board.hazard_at(land) == null:
		_bug(n, "own snare consumed by friendly dash"); gs.queue_free(); return
	if int(s.snared_no_move_until_turn) >= int(gs.turn_number) + 1:
		_bug(n, "friendly dash snared self"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _b09_run_onto_enemy_snare(seed: int) -> void:
	var n := "B09 run onto enemy snare (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var a := gs.add_squad(0, Vector2i(6, 4), "core", 1)
	gs.get_squad(a).units.append(UnitStateScript.new("hoof", 1, 1))
	gs.get_squad(a).organs_locked = true
	var land := Vector2i(6, 6)
	_clear(gs, Vector2i(6, 5))
	_clear(gs, land)
	gs.board.set_hazard(land, "snare", 1, 0, 0)
	_unfresh(gs, a)
	resolver.use_run(gs, a, land)
	var s = gs.get_squad(a)
	if s.cell != land:
		_fail(n, "run failed"); gs.queue_free(); return
	if int(s.snared_no_move_until_turn) < int(gs.turn_number) + 1:
		_bug(n, "run into snare did not apply"); gs.queue_free(); return
	# next move should fail
	_unfresh(gs, a) # clears moved but not snare
	s.fresh_turn = -1
	s.moved_turn = -1
	if rules.can_move(gs, a, Vector2i(6, 7)):
		_bug(n, "snared unit can basic-move"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _b10_contested_cp_no_flag(seed: int) -> void:
	var n := "B10 both players in CP zone contests (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	if gs.board.control_points.is_empty():
		_fail(n, "no CPs"); gs.queue_free(); return
	var cp = gs.board.control_points[0]
	var cell: Vector2i = cp.cell
	var adj := Vector2i(cell.x + 1, cell.y)
	if not gs.board.in_bounds(adj):
		adj = Vector2i(cell.x, cell.y + 1)
	_clear(gs, cell)
	_clear(gs, adj)
	# P0 on CP, P1 in adjacent zone cell — contested, no flags.
	gs.add_squad(0, cell, "core", 1)
	gs.add_squad(1, adj, "core", 1)
	var before0 := int(cp.flags_for(0))
	var before1 := int(cp.flags_for(1))
	resolver._apply_control_points(gs)
	if int(cp.flags_for(0)) != before0 or int(cp.flags_for(1)) != before1:
		_bug(n, "contested zone should not flag either player"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _b11_melee_power_drops_after_claw_pop(seed: int) -> void:
	var n := "B11 melee drops after claw pops (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var sid := _build(gs, resolver, rules, 0, ["core", "claw"])
	var s = gs.get_squad(sid)
	# claw front, core back
	if int(UnitDefsScript.action_def_for_squad(s, "melee").get("damage", 0)) != 2:
		_fail(n, "expected claw melee 2"); gs.queue_free(); return
	resolver._pop_organs(gs, s, 1)
	s = gs.get_squad(sid)
	var dmg := int(UnitDefsScript.action_def_for_squad(s, "melee").get("damage", 0))
	if dmg != 1:
		_bug(n, "after claw pop expected core melee 1 got %d" % dmg); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _b12_double_gland_two_snares(seed: int) -> void:
	var n := "B12 two snares from gland (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var a := gs.add_squad(0, Vector2i(7, 5), "core", 1)
	gs.get_squad(a).units.append(UnitStateScript.new("gland", 1, 1))
	gs.get_squad(a).organs_locked = true
	var t1 := Vector2i(7, 6)
	var t2 := Vector2i(6, 6)
	_clear(gs, t1)
	_clear(gs, t2)
	_unfresh(gs, a)
	resolver.plant_hazard(gs, a, t1, "snare")
	_unfresh(gs, a)
	gs.get_squad(a).cooldowns["snare"] = 0
	resolver.plant_hazard(gs, a, t2, "snare")
	if gs.board.hazard_at(t1) == null or gs.board.hazard_at(t2) == null:
		_fail(n, "expected two snares"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _b13_slam_diagonal_not_hit(seed: int) -> void:
	var n := "B13 slam manhattan AoE (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var a := gs.add_squad(0, Vector2i(8, 8), "core", 1)
	gs.get_squad(a).units.append(UnitStateScript.new("shell", 1, 1))
	gs.get_squad(a).organs_locked = true
	# diagonal dist=2 manhattan — outside radius 1
	var e := gs.add_squad(1, Vector2i(9, 9), "core", 1)
	_unfresh(gs, a)
	resolver.use_slam(gs, a)
	if gs.get_squad(e) == null or not gs.get_squad(e).is_alive():
		_bug(n, "slam hit diagonal dist2 (should be manhattan<=1 only)"); gs.queue_free(); return
	# ortho should die
	var e2 := gs.add_squad(1, Vector2i(8, 9), "core", 1)
	_unfresh(gs, a)
	gs.get_squad(a).cooldowns["slam"] = 0
	resolver.use_slam(gs, a)
	if gs.get_squad(e2) != null and gs.get_squad(e2).is_alive():
		_fail(n, "slam missed ortho adjacent"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _b14_offer_auto_start_on_end_turn(seed: int) -> void:
	var n := "B14 end turn starts offer (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	gs.add_squad(0, Vector2i(2, 0), "core", 1)
	gs.add_squad(1, Vector2i(11, 13), "core", 1)
	gs.offer_pending = false
	gs.clear_offer_phase()
	resolver.end_turn(gs)
	if not bool(gs.offer_pending):
		_bug(n, "offer_pending false after end_turn"); gs.queue_free(); return
	if gs.offer_cards.is_empty():
		_bug(n, "offer_cards empty after end_turn"); gs.queue_free(); return
	if int(gs.active_player) != 1:
		_fail(n, "active player not switched"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _b15_attach_enemy_mutant_rejected(seed: int) -> void:
	var n := "B15 cannot attach to enemy (%d)" % seed
	var gs = _gs(seed)
	var rules = RulesScript.new()
	var enemy := gs.add_squad(1, Vector2i(2, 0), "core", 1) # in P0 pool visually? P1 owner on P0 row
	# Put enemy in P0 spawn band
	gs.get_squad(enemy).organs_locked = false
	gs.offer_pending = true
	_offer(gs, ["claw", "eye", "hoof"])
	gs.active_player = 0
	if rules.can_play_card_reinforce(gs, "claw", enemy):
		_bug(n, "can attach to enemy mutant"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _b16_spawn_last_cell_then_attach_only(seed: int) -> void:
	var n := "B16 full pool forces attach (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	# Fill all P0 spawn empties
	for y in range(RulesScript.HOME_SPAWN_ROWS):
		for x in range(int(gs.board.size.x)):
			var c := Vector2i(x, y)
			if gs.board.is_blocked(c):
				continue
			if gs.squad_at(c) == null:
				gs.add_squad(0, c, "core", 1)
	if not rules.spawn_cells(gs, 0).is_empty():
		_fail(n, "spawn cells remain"); gs.queue_free(); return
	gs.offer_pending = true
	_offer(gs, ["claw", "eye", "hoof"])
	var sid := -1
	for sid_any in gs.squads.keys():
		var s = gs.get_squad(int(sid_any))
		if s and int(s.owner) == 0 and rules.is_spawn_pool_cell(gs, s.cell, 0):
			s.organs_locked = false
			sid = int(s.id)
			break
	if sid < 0:
		_fail(n, "no unlockable"); gs.queue_free(); return
	if rules.can_play_card_spawn(gs, "claw", Vector2i(0, 0)):
		_bug(n, "spawn legal with full pool"); gs.queue_free(); return
	if not rules.can_play_card_reinforce(gs, "claw", sid):
		_fail(n, "attach should work"); gs.queue_free(); return
	resolver.play_card_reinforce(gs, "claw", sid)
	_ok(n)
	gs.queue_free()

func _b17_ranged_obstacle_then_path(seed: int) -> void:
	var n := "B17 ranged hits obstacle (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var a := gs.add_squad(0, Vector2i(3, 3), "core", 1)
	gs.get_squad(a).units.append(UnitStateScript.new("eye", 1, 1))
	gs.get_squad(a).organs_locked = true
	var oc := Vector2i(3, 5)
	gs.board.obstacles[oc] = {"hp": 2, "destructible": true}
	_unfresh(gs, a)
	if not rules.can_attack_obstacle(gs, a, oc, "ranged"):
		_fail(n, "ranged obstacle illegal"); gs.queue_free(); return
	var before := int(gs.board.obstacle_hp(oc))
	resolver.attack_obstacle(gs, a, oc, "ranged")
	if int(gs.board.obstacle_hp(oc)) >= before and gs.board.is_blocked(oc):
		_fail(n, "obstacle undamaged"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _b18_set_front_while_locked(seed: int) -> void:
	var n := "B18 set_front while locked (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var sid := _build(gs, resolver, rules, 0, ["core", "claw", "eye"])
	_exit(gs, resolver, sid)
	var s = gs.get_squad(sid)
	if not bool(s.organs_locked):
		_fail(n, "not locked"); gs.queue_free(); return
	_unfresh(gs, sid)
	# find eye index
	var eye_i := -1
	for i in range(s.units.size()):
		if str(s.units[i].unit_def_id) == "eye":
			eye_i = i
			break
	if eye_i < 0:
		_fail(n, "no eye"); gs.queue_free(); return
	if not rules.can_set_front_unit(gs, sid, eye_i):
		_bug(n, "cannot reorder while locked (formation should stay allowed)"); gs.queue_free(); return
	resolver.set_front_unit(gs, sid, eye_i)
	s = gs.get_squad(sid)
	if str(s.units[0].unit_def_id) != "eye":
		_fail(n, "front not eye"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _b19_snare_blocks_run(seed: int) -> void:
	var n := "B19 snare blocks run (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var a := gs.add_squad(0, Vector2i(4, 4), "core", 1)
	gs.get_squad(a).units.append(UnitStateScript.new("hoof", 1, 1))
	gs.get_squad(a).organs_locked = true
	gs.get_squad(a).snared_no_move_until_turn = int(gs.turn_number) + 2
	_unfresh(gs, a)
	var dest := Vector2i(4, 6)
	_clear(gs, Vector2i(4, 5))
	_clear(gs, dest)
	var before: Vector2i = gs.get_squad(a).cell
	resolver.use_run(gs, a, dest)
	if gs.get_squad(a).cell != before:
		_bug(n, "run succeeded while snared"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _b20_multi_mutant_cp_race(seed: int) -> void:
	var n := "B20 multi mutant CP race (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	if gs.board.control_points.size() < 1:
		_fail(n, "no CP"); gs.queue_free(); return
	var cp = gs.board.control_points[0]
	var cell: Vector2i = cp.cell
	_clear(gs, cell)
	gs.add_squad(0, cell, "core", 1)
	# Need enough uncontested end_turns to capture
	var guard := 0
	while int(cp.owner) != 0 and guard < 10:
		guard += 1
		gs.clear_offer_phase()
		# keep P0 on CP; don't place P1 near
		resolver._apply_control_points(gs)
		if int(cp.owner) == 0:
			break
		# simulate turns without moving off
		gs.active_player = 0
	if int(cp.owner) != 0:
		# use end_turn loop
		guard = 0
		while int(cp.owner) != 0 and guard < 12:
			guard += 1
			gs.clear_offer_phase()
			if not RulesScript.new().can_end_turn(gs):
				gs.clear_offer_phase()
			resolver.end_turn(gs)
			gs.clear_offer_phase()
	if int(cp.owner) != 0:
		_fail(n, "failed to capture CP owner=%s flags=%s" % [str(cp.owner), str(cp.flags)]); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _b21_claw_dash_then_melee_same_turn(seed: int) -> void:
	var n := "B21 dash then melee same turn (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var a := gs.add_squad(0, Vector2i(4, 4), "core", 1)
	gs.get_squad(a).units.append(UnitStateScript.new("claw", 1, 1))
	gs.get_squad(a).organs_locked = true
	var land := Vector2i(4, 6)
	var enemy_cell := Vector2i(4, 7)
	_clear(gs, Vector2i(4, 5))
	_clear(gs, land)
	_clear(gs, enemy_cell)
	var e := gs.add_squad(1, enemy_cell, "core", 1)
	_unfresh(gs, a)
	resolver.use_dash(gs, a, land)
	# melee shares no CD with dash
	if not rules.can_attack(gs, a, e, "melee"):
		_bug(n, "melee illegal after dash same turn"); gs.queue_free(); return
	resolver.attack(gs, a, e, "melee")
	_ok(n)
	gs.queue_free()

func _b22_shell_core_last_stand(seed: int) -> void:
	var n := "B22 shell pops first core last-stands (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var sid := _build(gs, resolver, rules, 0, ["core", "shell"])
	var s = gs.get_squad(sid)
	# expected shell, core
	if str(s.units[0].unit_def_id) != "shell":
		_fail(n, "shell not front"); gs.queue_free(); return
	resolver._pop_organs(gs, s, 1)
	s = gs.get_squad(sid)
	if not _acts(s).has("melee") or _acts(s).has("slam"):
		_bug(n, "expected core melee only after shell pop: %s" % str(_acts(s))); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _b23_inventory_exhaust_mid_build(seed: int) -> void:
	var n := "B23 inventory exhaust mid-build (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	gs.player_inventory[0]["claw"] = 1
	gs.offer_pending = true
	_offer(gs, ["core", "claw", "claw"])
	var cells = rules.spawn_cells(gs, 0)
	resolver.play_card_spawn(gs, "core", cells[0])
	var sid := int(gs.squad_at(cells[0]).id)
	resolver.play_card_reinforce(gs, "claw", sid)
	# second claw should be unplayable (inv 0)
	if rules.can_play_card_reinforce(gs, "claw", sid):
		_bug(n, "second claw attach legal at inv 0"); gs.queue_free(); return
	gs.finish_offer_if_done()
	if bool(gs.offer_pending) and gs.offer_cards.has("claw"):
		gs.prune_unplayable_offer_cards()
		gs.finish_offer_if_done()
	if bool(gs.offer_pending) and gs.offer_cards.has("claw") and int(gs.player_inventory[0].get("claw", 0)) <= 0:
		_bug(n, "unplayable claw remained in offer"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _b24_diagonal_plant_range(seed: int) -> void:
	var n := "B24 snare uses manhattan range (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var a := gs.add_squad(0, Vector2i(5, 5), "core", 1)
	gs.get_squad(a).units.append(UnitStateScript.new("gland", 1, 1))
	gs.get_squad(a).organs_locked = true
	# chebyshev 1 diagonal — in range
	var okc := Vector2i(6, 6)
	_clear(gs, okc)
	_unfresh(gs, a)
	resolver.plant_hazard(gs, a, okc, "snare")
	if gs.board.hazard_at(okc) == null:
		_fail(n, "chebyshev-1 diagonal should be plantable"); gs.queue_free(); return
	# chebyshev 2 — out of range
	var far := Vector2i(7, 6)
	_clear(gs, far)
	_unfresh(gs, a)
	gs.get_squad(a).cooldowns["snare"] = 0
	resolver.plant_hazard(gs, a, far, "snare")
	if gs.board.hazard_at(far) != null:
		_bug(n, "planted snare at chebyshev 2"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _b25_winner_blocks_end_turn(seed: int) -> void:
	var n := "B25 winner blocks end turn (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var a := gs.add_squad(0, Vector2i(5, 5), "core", 1)
	var e := gs.add_squad(1, Vector2i(5, 6), "core", 1)
	resolver._pop_organs(gs, gs.get_squad(e), 99)
	if gs.winner == -1:
		_fail(n, "no winner"); gs.queue_free(); return
	if rules.can_end_turn(gs):
		_bug(n, "end turn allowed after winner"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _b26_eye_eye_double_ranged(seed: int) -> void:
	var n := "B26 double eye still one ranged (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var sid := _build(gs, resolver, rules, 0, ["core", "eye", "eye"])
	var s = gs.get_squad(sid)
	var ids = _acts(s)
	var ranged_count := 0
	for a in ids:
		if str(a) == "ranged":
			ranged_count += 1
	if ranged_count != 1:
		_bug(n, "expected single ranged id, got %s" % str(ids)); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _b27_hoof_hoof_run_cd_shared(seed: int) -> void:
	var n := "B27 double hoof shared run CD (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var a := gs.add_squad(0, Vector2i(3, 3), "core", 1)
	gs.get_squad(a).units.append(UnitStateScript.new("hoof", 1, 1))
	gs.get_squad(a).units.append(UnitStateScript.new("hoof", 1, 1))
	gs.get_squad(a).organs_locked = true
	var d1 := Vector2i(3, 5)
	_clear(gs, Vector2i(3, 4))
	_clear(gs, d1)
	_unfresh(gs, a)
	resolver.use_run(gs, a, d1)
	if int(gs.get_squad(a).cooldowns.get("run", 0)) <= 0:
		_fail(n, "run CD not set"); gs.queue_free(); return
	var d2 := Vector2i(3, 7)
	_clear(gs, Vector2i(3, 6))
	_clear(gs, d2)
	# second hoof should not bypass CD
	resolver.use_run(gs, a, d2)
	if gs.get_squad(a).cell == d2:
		_bug(n, "second run ignored shared CD"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _b28_move_onto_cp_and_capture(seed: int) -> void:
	var n := "B28 stand on CP capture (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	if gs.board.control_points.is_empty():
		_fail(n, "no CP"); gs.queue_free(); return
	var cp = gs.board.control_points[0]
	_clear(gs, cp.cell)
	var a := gs.add_squad(0, cp.cell, "core", 1)
	gs.get_squad(a).organs_locked = true
	# Solo army pays +1 flag tax.
	var need := int(resolver.CP_CAPTURE_FLAGS) + 1
	for _i in range(need + 2):
		resolver._apply_control_points(gs)
		if int(cp.owner) == 0:
			break
	if int(cp.owner) != 0:
		_fail(n, "CP not captured after flags"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _b29_three_way_focus_kill(seed: int) -> void:
	var n := "B29 three mutants focus (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var ids: Array[int] = []
	ids.append(gs.add_squad(0, Vector2i(5, 5), "core", 1))
	ids.append(gs.add_squad(0, Vector2i(6, 5), "core", 1))
	ids.append(gs.add_squad(0, Vector2i(7, 5), "core", 1))
	for sid in ids:
		gs.get_squad(sid).units.append(UnitStateScript.new("claw", 1, 1))
		gs.get_squad(sid).organs_locked = true
		_sand(gs, gs.get_squad(sid).cell)
	var e := gs.add_squad(1, Vector2i(6, 6), "core", 1)
	for _i in range(8):
		gs.get_squad(e).units.append(UnitStateScript.new("shell", 1, 1))
	var before := int(gs.get_squad(e).unit_count_alive())
	for sid in ids:
		_unfresh(gs, sid)
		if rules.can_attack(gs, sid, e, "melee"):
			resolver.attack(gs, sid, e, "melee")
	var after := int(gs.get_squad(e).unit_count_alive()) if gs.get_squad(e) else 0
	if before - after < 2:
		_fail(n, "focus too weak before=%d after=%d" % [before, after]); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _b30_long_skirmish_mixed(seed: int) -> void:
	var n := "B30 long mixed skirmish (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var p0 := _build(gs, resolver, rules, 0, ["core", "claw", "gland"])
	var p0b := _build(gs, resolver, rules, 0, ["core", "eye", "hoof"])
	resolver.end_turn(gs)
	gs.clear_offer_phase()
	var p1 := _build(gs, resolver, rules, 1, ["core", "shell", "claw"])
	var p1b := _build(gs, resolver, rules, 1, ["core", "eye"])
	var places := {
		p0: Vector2i(5, 5),
		p0b: Vector2i(7, 5),
		p1: Vector2i(5, 8),
		p1b: Vector2i(7, 8),
	}
	for sid_any in places.keys():
		var sid := int(sid_any)
		var s = gs.get_squad(sid)
		if s == null:
			continue
		_clear(gs, places[sid])
		resolver._set_squad_cell(gs, s, places[sid])
		s.organs_locked = true
		_sand(gs, s.cell)
	var guard := 0
	while gs.winner == -1 and guard < 30:
		guard += 1
		gs.clear_offer_phase()
		var ap := int(gs.active_player)
		var acted := false
		for sid_any in gs.squads.keys():
			var sid := int(sid_any)
			var s = gs.get_squad(sid)
			if s == null or not s.is_alive() or int(s.owner) != ap:
				continue
			_unfresh(gs, sid)
			# plant snare opportunistically
			if _acts(s).has("snare") and int(s.cooldowns.get("snare", 0)) <= 0:
				var tc := Vector2i(s.cell.x, s.cell.y + (1 if ap == 0 else -1))
				_clear(gs, tc)
				if gs.squad_at(tc) == null and gs.board.hazard_at(tc) == null:
					resolver.plant_hazard(gs, sid, tc, "snare")
					acted = true
					break
			for eid_any in gs.squads.keys():
				var e = gs.get_squad(int(eid_any))
				if e == null or not e.is_alive() or int(e.owner) == ap:
					continue
				s.cooldowns["melee"] = 0
				s.cooldowns["ranged"] = 0
				s.cooldowns["slam"] = 0
				if rules.can_attack(gs, sid, int(e.id), "ranged"):
					resolver.attack(gs, sid, int(e.id), "ranged")
					acted = true
					break
				if rules.can_attack(gs, sid, int(e.id), "melee"):
					resolver.attack(gs, sid, int(e.id), "melee")
					acted = true
					break
				if _acts(s).has("slam") and abs(s.cell.x - e.cell.x) + abs(s.cell.y - e.cell.y) <= 1:
					resolver.use_slam(gs, sid)
					acted = true
					break
			if acted:
				break
		if gs.winner != -1:
			break
		resolver.end_turn(gs)
	if gs.winner == -1:
		for sid_any in gs.squads.keys():
			var s = gs.get_squad(int(sid_any))
			if s and s.is_alive() and int(s.owner) == 1:
				resolver._pop_organs(gs, s, 99)
		if gs.winner == -1:
			_fail(n, "no winner"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()
