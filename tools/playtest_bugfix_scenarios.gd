extends SceneTree

## Multi-scenario playtest for board UX bugfix features.
## godot --headless --path . --script res://tools/playtest_bugfix_scenarios.gd

const GameStateScript = preload("res://src/sim/GameState.gd")
const ResolverScript = preload("res://src/sim/Resolver.gd")
const RulesScript = preload("res://src/sim/Rules.gd")
const UnitDefsScript = preload("res://src/sim/UnitDefs.gd")
const UnitStateScript = preload("res://src/sim/UnitState.gd")

var _fails: Array[String] = []
var _passes: int = 0
var _resolver = ResolverScript.new()
var _rules = RulesScript.new()

func _init() -> void:
	print("=== Bugfix multi-scenario playtest ===")
	_s01_occupied_attach_vs_spawn()
	_s02_core_sink_multi_attach()
	_s03_reclaimable_vs_structural_drops()
	_s04_field_graft_reclaimable_only()
	_s05_egg_graft_all_types()
	_s06_offer_attach_occupied_first_click()
	_s07_gear_pool_all_reclaimable()
	_s08_curse_never_reclaimable()
	_s09_hard_max_still_blocks()
	_s10_enemy_occupied_rejects()
	print("=== results: %d pass, %d fail ===" % [_passes, _fails.size()])
	for f in _fails:
		print("FAIL: ", f)
	if _fails.is_empty():
		print("BUGFIX_SCENARIOS_OK")
	quit(1 if _fails.size() > 0 else 0)

func _ok(n: String) -> void:
	_passes += 1
	print("PASS: ", n)

func _fail(n: String, d: String) -> void:
	_fails.append("%s — %s" % [n, d])
	print("FAIL: ", n, " — ", d)

func _fresh(seed: int = 42):
	var gs = GameStateScript.new()
	root.add_child(gs)
	gs.setup(GameStateScript.DEFAULT_BOARD_SIZE, seed)
	gs.squads.clear()
	gs._next_squad_id = 1
	gs.winner = -1
	gs.active_player = 0
	gs.turn_number = 3
	gs.offer_pending = false
	gs.offer_cards.clear()
	gs.offer_mutants.clear()
	return gs

func _spawn_pool_cell(gs, player: int) -> Vector2i:
	var cells: Array[Vector2i] = _rules.spawn_cells(gs, player)
	if cells.is_empty():
		return Vector2i(2, 0 if player == 0 else 13)
	return cells[0]

func _leave_pool(gs, sid: int) -> void:
	var s = gs.get_squad(sid)
	if s == null:
		return
	var cell: Vector2i = s.cell
	var mid := Vector2i(int(gs.board.size.x / 2), int(gs.board.size.y / 2))
	# Walk toward mid until locked / outside pool.
	for _i in range(8):
		var step := Vector2i(
			clampi(mid.x - cell.x, -1, 1),
			clampi(mid.y - cell.y, -1, 1)
		)
		if step == Vector2i.ZERO:
			break
		var nxt := cell + step
		if not gs.board.in_bounds(nxt) or gs.board.is_blocked(nxt) or gs.squad_at(nxt) != null:
			break
		s.moved_turn = -1
		_resolver.move_squad(gs, sid, nxt)
		cell = s.cell
		if bool(s.organs_locked):
			return

func _s01_occupied_attach_vs_spawn() -> void:
	var n := "S01 occupied cell: spawn illegal, reinforce legal"
	var gs = _fresh(101)
	gs.offer_pending = true
	gs.offer_cards = ["eye", "claw", "hoof"] as Array[String]
	gs.player_inventory[0] = {"eye": 3, "claw": 3, "hoof": 3, "core": 3}
	var cell := _spawn_pool_cell(gs, 0)
	var sid := gs.add_squad(0, cell, "core", 1)
	gs.get_squad(sid).organs_locked = false
	if _rules.can_play_card_spawn(gs, "eye", cell):
		_fail(n, "spawn should be illegal on occupied"); gs.queue_free(); return
	if not _rules.can_play_card_reinforce(gs, "eye", sid):
		_fail(n, "reinforce should be legal"); gs.queue_free(); return
	var before := int(gs.get_squad(sid).unit_count_alive())
	_resolver.play_card_reinforce(gs, "eye", sid, false, 0)
	if int(gs.get_squad(sid).unit_count_alive()) != before + 1:
		_fail(n, "attach did not add organ"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _s02_core_sink_multi_attach() -> void:
	var n := "S02 multi-attach with core sink keeps all organs"
	var gs = _fresh(102)
	var cell := _spawn_pool_cell(gs, 0)
	var sid := gs.add_squad(0, cell, "core", 1)
	var s = gs.get_squad(sid)
	s.organs_locked = false
	for gene in ["claw", "eye", "shell", "hoof"]:
		if not gs.reinforce_squad(sid, gene, 1):
			_fail(n, "failed attach %s" % gene); gs.queue_free(); return
	if int(s.unit_count_alive()) != 5:
		_fail(n, "expected 5 organs got %d" % int(s.unit_count_alive())); gs.queue_free(); return
	# Core must be last.
	var last = s.units[s.units.size() - 1]
	if str(last.unit_def_id) != "core":
		_fail(n, "core not at back after sink"); gs.queue_free(); return
	# All specialty still present (no kick-off).
	var ids: Array[String] = []
	for u in s.units:
		ids.append(str(u.unit_def_id))
	for need in ["claw", "eye", "shell", "hoof", "core"]:
		if not ids.has(need):
			_fail(n, "missing %s after attaches" % need); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _s03_reclaimable_vs_structural_drops() -> void:
	var n := "S03 structural organs do not drop gear; weapons do"
	var gs = _fresh(103)
	gs.board.gear.clear()
	gs.board.eggs.clear()
	var cell := Vector2i(4, 4)
	# Prefer an open mid-board cell so drops have room.
	var found := false
	for y in range(3, 11):
		for x in range(3, 11):
			var c := Vector2i(x, y)
			if gs.board.is_blocked(c) or gs.squad_at(c) != null:
				continue
			cell = c
			found = true
			break
		if found:
			break
	var sid := gs.add_squad(0, cell, "claw", 1)
	var s = gs.get_squad(sid)
	s.units.append(UnitStateScript.new("core", 1, 1))
	s.units.append(UnitStateScript.new("brood", 1, 1))
	s.units.append(UnitStateScript.new("anchor", 1, 1))
	s.units.append(UnitStateScript.new("eye", 1, 1))
	gs._stabilize_core_at_back(s)
	s.organs_locked = true
	gs.board.gear.clear()
	# Pop everything; only claw+eye should drop.
	var expected_drops := 0
	while s.is_alive():
		var front = s.units[s.front_unit_index()]
		var id := str(front.unit_def_id)
		if UnitDefsScript.is_reclaimable_gear(id):
			expected_drops += 1
		_resolver._pop_organs(gs, s, 1)
	if int(gs.board.gear.size()) != expected_drops:
		_fail(n, "gear drops %d expected %d (cell=%s)" % [int(gs.board.gear.size()), expected_drops, str(cell)])
		gs.queue_free()
		return
	for c_any in gs.board.gear.keys():
		var g = gs.board.gear_at(c_any)
		var gid := str(g.get("unit_def_id", ""))
		if not UnitDefsScript.is_reclaimable_gear(gid):
			_fail(n, "non-reclaimable on board: %s" % gid); gs.queue_free(); return
		if gid in ["core", "brood", "anchor"]:
			_fail(n, "structural gear present: %s" % gid); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _s04_field_graft_reclaimable_only() -> void:
	var n := "S04 field graft reclaimable gear / ignore structural if forced"
	var gs = _fresh(104)
	var cell := Vector2i(6, 6)
	if gs.board.is_blocked(cell):
		cell = Vector2i(7, 7)
	var sid := gs.add_squad(0, cell, "claw", 1)
	var s = gs.get_squad(sid)
	s.organs_locked = true
	s.fresh_turn = -1
	gs.board.gear.clear()
	gs.board.eggs.clear()
	var gear_cell := cell + Vector2i(1, 0)
	if gs.board.is_blocked(gear_cell) or gs.squad_at(gear_cell) != null:
		gear_cell = cell + Vector2i(0, 1)
	gs.board.set_gear(gear_cell, "shell", false)
	s.moved_turn = -1
	_resolver.move_squad(gs, sid, gear_cell)
	if int(s.unit_count_alive()) < 2:
		_fail(n, "shell gear not grafted"); gs.queue_free(); return
	if gs.board.gear.has(gear_cell):
		_fail(n, "gear not consumed"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _s05_egg_graft_all_types() -> void:
	var n := "S05 egg graft attaches content (incl curse)"
	var gs = _fresh(105)
	var cell := Vector2i(5, 5)
	if gs.board.is_blocked(cell):
		cell = Vector2i(4, 6)
	var sid := gs.add_squad(0, cell, "claw", 1)
	var s = gs.get_squad(sid)
	s.organs_locked = true
	s.fresh_turn = -1
	gs.board.gear.clear()
	gs.board.eggs.clear()
	var egg_cell := cell + Vector2i(1, 0)
	if gs.board.is_blocked(egg_cell) or gs.squad_at(egg_cell) != null:
		egg_cell = cell + Vector2i(0, 1)
	gs.board.set_egg(egg_cell, "rot", false)
	var before := int(s.unit_count_alive())
	s.moved_turn = -1
	_resolver.move_squad(gs, sid, egg_cell)
	if int(s.unit_count_alive()) != before + 1:
		_fail(n, "egg not grafted"); gs.queue_free(); return
	if gs.board.eggs.has(egg_cell):
		_fail(n, "egg not consumed"); gs.queue_free(); return
	var has_rot := false
	for u in s.units:
		if str(u.unit_def_id) == "rot":
			has_rot = true
	if not has_rot:
		_fail(n, "rot not on mutant"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _s06_offer_attach_occupied_first_click() -> void:
	var n := "S06 offer: click occupied friendly attaches immediately"
	var gs = _fresh(106)
	gs.offer_pending = true
	gs.offer_cards = ["plate", "claw", "eye"] as Array[String]
	gs.player_inventory[0] = {"plate": 2, "claw": 2, "eye": 2, "core": 2}
	var cell := _spawn_pool_cell(gs, 0)
	var sid := gs.add_squad(0, cell, "core", 1)
	gs.get_squad(sid).organs_locked = false
	# Mimic Main._on_cell_clicked card_spawn path: reinforce if possible.
	var can_reinf := bool(_rules.can_play_card_reinforce(gs, "plate", sid))
	var can_spawn := bool(_rules.can_play_card_spawn(gs, "plate", cell))
	if can_spawn:
		_fail(n, "occupied should block spawn"); gs.queue_free(); return
	if not can_reinf:
		_fail(n, "reinforce should succeed first click"); gs.queue_free(); return
	_resolver.play_card_reinforce(gs, "plate", sid, false, 0)
	if int(gs.get_squad(sid).unit_count_alive()) != 2:
		_fail(n, "attach failed"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _s07_gear_pool_all_reclaimable() -> void:
	var n := "S07 every gear_spawn_pool id is reclaimable"
	for id in UnitDefsScript.gear_spawn_pool():
		if not UnitDefsScript.is_reclaimable_gear(str(id)):
			_fail(n, "%s in pool but not reclaimable" % id)
			return
	_ok(n)

func _s08_curse_never_reclaimable() -> void:
	var n := "S08 curses never reclaimable"
	for id in ["rot", "leech", "static"]:
		if UnitDefsScript.is_reclaimable_gear(id):
			_fail(n, "%s reclaimable" % id)
			return
		if not UnitDefsScript.is_curse_organ(id):
			_fail(n, "%s not marked curse" % id)
			return
	_ok(n)

func _s09_hard_max_still_blocks() -> void:
	var n := "S09 hard max blocks attach and field graft"
	var gs = _fresh(109)
	var cell := _spawn_pool_cell(gs, 0)
	var sid := gs.add_squad(0, cell, "core", 1)
	var s = gs.get_squad(sid)
	s.organs_locked = false
	while int(s.unit_count_alive()) < RulesScript.ORGAN_HARD_MAX:
		if not gs.reinforce_squad(sid, "chunk", 1):
			break
	if int(s.unit_count_alive()) != RulesScript.ORGAN_HARD_MAX:
		_fail(n, "could not fill to hard max"); gs.queue_free(); return
	if _rules.can_add_unit_to_squad(s, "eye"):
		_fail(n, "can_add should fail at hard max"); gs.queue_free(); return
	if _rules.can_field_attach(s):
		_fail(n, "field attach should fail at hard max"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _s10_enemy_occupied_rejects() -> void:
	var n := "S10 cannot attach to enemy occupied cell"
	var gs = _fresh(110)
	gs.offer_pending = true
	gs.offer_cards = ["claw"] as Array[String]
	gs.player_inventory[0] = {"claw": 2}
	var ecell := _spawn_pool_cell(gs, 1)
	var esid := gs.add_squad(1, ecell, "core", 1)
	if _rules.can_play_card_reinforce(gs, "claw", esid):
		_fail(n, "reinforce enemy should fail"); gs.queue_free(); return
	if _rules.can_play_card_spawn(gs, "claw", ecell):
		_fail(n, "spawn on enemy cell should fail"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()
