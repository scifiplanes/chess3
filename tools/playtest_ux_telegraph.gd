extends SceneTree

## UX telegraph pass: obstacle destroy erase + organ pop free + slam confirm wiring smoke.
## godot --headless --path . --script res://tools/playtest_ux_telegraph.gd

const GameStateScript = preload("res://src/sim/GameState.gd")
const ResolverScript = preload("res://src/sim/Resolver.gd")
const RulesScript = preload("res://src/sim/Rules.gd")
const UnitStateScript = preload("res://src/sim/UnitState.gd")
const BoardScene = preload("res://scenes/Board.tscn")

var _fails: Array[String] = []
var _passes: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _ok(n: String) -> void:
	_passes += 1
	print("PASS: ", n)

func _fail(n: String, d: String) -> void:
	_fails.append("%s — %s" % [n, d])
	print("FAIL: ", n, " — ", d)

func _run() -> void:
	print("=== ux telegraph playtest ===")
	_obstacle_destroy_erases()
	await _organ_pop_immediate_free()
	_slam_confirm_source()
	print("=== results: %d pass, %d fail ===" % [_passes, _fails.size()])
	for f in _fails:
		print("FAIL: ", f)
	if _fails.is_empty():
		print("PLAYTEST_UX_TELEGRAPH_OK")
		quit(0)
	else:
		print("PLAYTEST_UX_TELEGRAPH_FAIL")
		quit(1)

func _obstacle_destroy_erases() -> void:
	var name := "obstacle destroy erases entry"
	var gs = GameStateScript.new()
	root.add_child(gs)
	gs.setup(GameStateScript.DEFAULT_BOARD_SIZE, 77)
	gs.offer_pending = false
	gs.winner = -1
	gs.active_player = 0
	gs.squads.clear()
	gs._next_squad_id = 1
	var sid := int(gs.add_squad(0, Vector2i(4, 4), "claw", 1))
	var a = gs.get_squad(sid)
	a.units.append(UnitStateScript.new("claw", 1, 1))
	a.organs_locked = true
	a.fresh_turn = -1
	var oc := Vector2i(4, 5)
	gs.board.add_obstacle(oc, 2, true, "blob")
	gs.board.hero_props.append({"cell": oc, "kind": "blob", "variant": 1})
	var rules = RulesScript.new()
	var resolver = ResolverScript.new()
	if not rules.can_attack_obstacle(gs, sid, oc, "melee"):
		_fail(name, "cannot attack")
		gs.queue_free()
		return
	while gs.board.is_blocked(oc):
		resolver.attack_obstacle(gs, sid, oc, "melee")
		a.cooldowns["melee"] = 0
		if int(gs.board.obstacle_hp(oc)) <= 0:
			break
	if gs.board.is_blocked(oc):
		_fail(name, "still blocked")
		gs.queue_free()
		return
	if gs.board.obstacles.has(oc):
		_fail(name, "obstacle dict still has cell after hp<=0")
		gs.queue_free()
		return
	for hp_any in gs.board.hero_props:
		if (hp_any as Dictionary).get("cell", Vector2i(-1, -1)) == oc:
			_fail(name, "hero_props still lists cell")
			gs.queue_free()
			return
	_ok(name)
	gs.queue_free()

func _organ_pop_immediate_free() -> void:
	var name := "organ pop frees living node same frame"
	var root3 := Node3D.new()
	root.add_child(root3)
	var board = BoardScene.instantiate()
	root3.add_child(board)
	await process_frame
	var gs = GameStateScript.new()
	root3.add_child(gs)
	gs.setup(GameStateScript.DEFAULT_BOARD_SIZE, 88)
	gs.squads.clear()
	gs._next_squad_id = 1
	gs.offer_pending = false
	gs.winner = -1
	var sid := int(gs.add_squad(0, Vector2i(5, 5), "core", 1))
	var s = gs.get_squad(sid)
	s.units.append(UnitStateScript.new("claw", 1, 1))
	s.units.append(UnitStateScript.new("eye", 1, 1))
	s.organs_locked = true
	s.fresh_turn = -1
	board.call("sync_from_game_state", gs)
	await process_frame
	await process_frame
	var view = board.call("get_squad_view", sid)
	if view == null:
		_fail(name, "no view")
		root3.queue_free()
		return
	var parts: Array = view.get("_organ_parts")
	if parts.size() != 3:
		_fail(name, "expected 3 parts, got %d" % parts.size())
		root3.queue_free()
		return
	var ids: Array[int] = []
	for p in parts:
		var n: Node = (p as Dictionary).get("node")
		ids.append(n.get_instance_id())
	s.units.pop_front()
	board.call("sync_from_game_state", gs)
	var after: Array = view.get("_organ_parts")
	if after.size() != 2:
		_fail(name, "expected 2 parts after pop, got %d" % after.size())
		root3.queue_free()
		return
	var surv: Dictionary = {}
	for p2 in after:
		surv[(p2 as Dictionary).get("node").get_instance_id()] = true
	var zombies := 0
	for iid in ids:
		if surv.has(iid):
			continue
		if is_instance_id_valid(iid):
			zombies += 1
	if zombies > 0:
		_fail(name, "popped organ instance still valid (%d)" % zombies)
		root3.queue_free()
		return
	_ok(name)
	root3.queue_free()

func _slam_confirm_source() -> void:
	var name := "slam confirm helpers present"
	var main := FileAccess.get_file_as_string("res://src/presentation/Main.gd")
	if main.is_empty():
		_fail(name, "Main.gd unreadable")
		return
	if not main.contains("func _confirm_slam"):
		_fail(name, "missing _confirm_slam")
		return
	if not main.contains('current_action = "slam"'):
		_fail(name, "slam does not arm confirm mode")
		return
	var slam_idx := main.find('"slam":')
	if slam_idx < 0:
		_fail(name, "no slam match arm")
		return
	var slice := main.substr(slam_idx, 420)
	if slice.contains("resolver.use_slam") and not slice.contains("_confirm_slam") and not slice.contains('current_action == "slam"'):
		_fail(name, "slam still resolves immediately in match")
		return
	_ok(name)
