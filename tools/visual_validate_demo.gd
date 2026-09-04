extends Node

## Demo spectator camera + knockout sweep smoke.
## godot --path . res://tools/visual_validate_demo.tscn

const MainScene = preload("res://scenes/Main.tscn")
const GameStateScript = preload("res://src/sim/GameState.gd")
const ResolverScript = preload("res://src/sim/Resolver.gd")

var _out := "res://tools/visual_shots"
var _main: Node
var _gs
var _resolver := ResolverScript.new()
var _fails: Array[String] = []

func _ready() -> void:
	print("DEMO_VALIDATE_START")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))

	MatchSession.configure_demo(88001, 0, 1)
	_main = MainScene.instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.8).timeout

	_gs = _main.get("gs")
	if _gs == null:
		_fail("no game state")
		get_tree().quit(1)
		return

	# Let AI spawn + leave pool so the demo camera frames mid-board action.
	await get_tree().create_timer(4.0).timeout
	await _shot("demo_01_framed_action")
	_assert_framed_squads()
	_assert_commentary_log()

	# Force a knockout sweep on a stacked mutant (partial pop — keep match alive).
	var director = _main.get_node_or_null("DemoDirector")
	if director != null:
		director.paused = true
	var sid := _pick_fat_squad()
	if sid >= 0:
		var s = _gs.get_squad(sid)
		if s != null and s.is_alive():
			var pop_n := mini(2, int(s.unit_count_alive()) - 1)
			if pop_n > 0:
				_resolver._pop_organs(_gs, s, pop_n)
				_gs.emit_signal("changed")
			await get_tree().create_timer(1.2).timeout
			await _shot("demo_02_knockout_mid")
			var rig = _main.get_node_or_null("CameraRig")
			if rig != null and rig.has_method("is_cinematic_active"):
				while bool(rig.call("is_cinematic_active")):
					await get_tree().process_frame
			await get_tree().create_timer(0.25).timeout
			await _shot("demo_03_knockout_done")
	else:
		_fail("no squad to sweep")

	Engine.time_scale = 1.0
	if _fails.is_empty():
		print("DEMO_VALIDATE_OK")
		get_tree().quit(0)
	else:
		for f in _fails:
			push_error(f)
		get_tree().quit(1)

func _pick_fat_squad() -> int:
	var best := -1
	var best_n := 0
	for sid_any in _gs.squads.keys():
		var s = _gs.get_squad(int(sid_any))
		if s == null or not s.is_alive():
			continue
		var n := int(s.unit_count_alive()) if s.has_method("unit_count_alive") else 0
		if n > best_n:
			best_n = n
			best = int(sid_any)
	return best

func _assert_framed_squads() -> void:
	if _gs.squads.is_empty():
		_fail("demo ran but no squads on board")
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		_fail("no active camera")
		return
	var board = _main.get_node_or_null("Board")
	if board == null or not board.has_method("cell_world_center"):
		_fail("no board cell_world_center")
		return
	var play_c := Vector2(640, 360)
	var hud = _main.get_node_or_null("HUD/HUDRoot")
	if hud != null and hud.has_method("ui_blocks_board_hover"):
		pass
	var on_screen := 0
	for s_any in _gs.squads.values():
		var s = s_any
		if s == null or not s.is_alive():
			continue
		var wp: Vector3 = board.call("cell_world_center", s.cell)
		var sp := cam.unproject_position(wp)
		# Include spawn-band framing (early demo often still on home rows).
		if sp.x >= 120 and sp.x <= 1160 and sp.y >= -40 and sp.y <= 760:
			on_screen += 1
	if on_screen <= 0:
		_fail("no living squads in play rect after demo framing")

func _assert_commentary_log() -> void:
	var hud = _main.get_node_or_null("HUD/HUDRoot")
	if hud == null or not hud.has_method("demo_commentary_nonempty"):
		_fail("commentary log API missing")
		return
	if not bool(hud.call("demo_commentary_nonempty")):
		_fail("commentary log empty after AI steps")

func _fail(msg: String) -> void:
	_fails.append(msg)
	printerr("DEMO_VALIDATE_FAIL: ", msg)

func _shot(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var tex := get_viewport().get_texture()
	if tex == null:
		_fail("no viewport texture for %s" % name)
		return
	var img: Image = tex.get_image()
	if img == null:
		_fail("no image for %s" % name)
		return
	var path := "%s/%s.png" % [_out, name]
	var err := img.save_png(path)
	print("SHOT ", path, " err=", err)
