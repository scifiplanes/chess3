extends Node3D

## Visual smoke for mutant rig: move hop, hover jiggle, organ corpses.
## godot --path . res://tools/visual_validate_rig.tscn
## Saves PNGs under res://tools/visual_shots/

const GameStateScript = preload("res://src/sim/GameState.gd")
const ResolverScript = preload("res://src/sim/Resolver.gd")
const UnitStateScript = preload("res://src/sim/UnitState.gd")
const BoardScene = preload("res://scenes/Board.tscn")
const CameraControllerScript = preload("res://src/presentation/CameraController.gd")

var _gs
var _board: Node3D
var _resolver = ResolverScript.new()
var _out_dir := "res://tools/visual_shots"
var _shot_i := 0
var _cam: Camera3D
var _cam_rig: Node3D
var _status: Label3D

func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))

	var light := DirectionalLight3D.new()
	light.light_energy = 2.0
	light.shadow_enabled = true
	light.rotation_degrees = Vector3(-50, 40, 0)
	add_child(light)

	var cam_rig := Node3D.new()
	cam_rig.name = "CameraRig"
	_cam = Camera3D.new()
	_cam.name = "Camera3D"
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 11.0
	_cam.near = 0.1
	_cam.far = 200.0
	cam_rig.add_child(_cam)
	cam_rig.set_script(CameraControllerScript)
	add_child(cam_rig)
	_cam_rig = cam_rig
	cam_rig.global_position = Vector3.ZERO
	_cam.position = Vector3(7.0, 12.0, 15.0)
	_cam.look_at(Vector3(7.0, 0.2, 6.0), Vector3.UP)
	_cam.current = true

	_board = BoardScene.instantiate()
	add_child(_board)

	_status = Label3D.new()
	_status.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status.pixel_size = 0.012
	_status.position = Vector3(6.5, 2.4, 4.0)
	_status.modulate = Color(1, 1, 0.75)
	_status.text = "visual validate"
	add_child(_status)

	_gs = GameStateScript.new()
	add_child(_gs)
	_gs.setup(GameStateScript.DEFAULT_BOARD_SIZE, 42)
	_gs.squads.clear()
	_gs._next_squad_id = 1
	_gs.winner = -1
	_gs.active_player = 0
	_gs.offer_pending = false
	_gs.offer_cards.clear()

	var sid: int = int(_gs.add_squad(0, Vector2i(5, 5), "core", 1))
	var s = _gs.get_squad(sid)
	s.units.append(UnitStateScript.new("claw", 1, 1))
	s.units.append(UnitStateScript.new("eye", 1, 1))
	s.units.append(UnitStateScript.new("shell", 1, 1))
	s.units.append(UnitStateScript.new("hoof", 1, 1))
	s.organs_locked = true
	# Enemy for spacing
	_gs.add_squad(1, Vector2i(9, 9), "core", 1)

	# Close framing on the multi-organ mutant (connectivity check).
	_cam.size = 2.15
	_cam.position = Vector3(5.5, 3.2, 7.0)
	_cam.look_at(Vector3(5.5, 0.35, 5.5), Vector3.UP)

	_sync("01_idle_stack")
	await _wait(0.45)
	await _shot("01_idle_stack")
	await _shot("organs_connected_close")

	# Wider framing for move / corpse shots.
	_cam.size = 11.0
	_cam.position = Vector3(7.0, 12.0, 15.0)
	_cam.look_at(Vector3(7.0, 0.2, 6.0), Vector3.UP)

	# Move hop
	_status.text = "MOVE hop"
	_unfresh(sid)
	s = _gs.get_squad(sid)
	_resolver._set_squad_cell(_gs, s, Vector2i(7, 5))
	_sync("02_move_start")
	await _wait(0.12)
	await _shot("02_move_mid")
	await _wait(0.35)
	await _shot("03_move_landed")

	# Hover jiggle — force-hover first organ via SquadView API if present
	_status.text = "HOVER organ"
	var view = _find_squad_view(sid)
	if view != null and view.has_method("debug_force_hover_organ"):
		view.call("debug_force_hover_organ", 0)
	elif view != null:
		view.set("_hovered_part_i", 0)
	await _wait(0.55)
	await _shot("04_hover_jiggle")

	# Pop organs → corpses
	_status.text = "POP organs → corpses"
	s = _gs.get_squad(sid)
	_resolver._pop_organs(_gs, s, 2)
	_sync("05_after_pop")
	await _wait(0.15)
	await _shot("05_corpses_airborne")
	await _wait(0.85)
	await _shot("06_corpses_settling")
	await _wait(1.2)
	await _shot("07_corpses_on_floor")

	# Kill rest → full shed
	_status.text = "KILL mutant shed all"
	s = _gs.get_squad(sid)
	if s != null and s.is_alive():
		_resolver._pop_organs(_gs, s, 99)
	_sync("08_dead")
	await _wait(0.12)
	await _shot("08_full_shed")
	await get_tree().create_timer(1.35).timeout
	await _shot("09_shed_sweep_mid")
	if _cam_rig != null and _cam_rig.has_method("is_cinematic_active"):
		while bool(_cam_rig.call("is_cinematic_active")):
			await get_tree().process_frame
	await get_tree().create_timer(0.35, true, false, true).timeout
	await _shot("09_shed_sweep")
	Engine.time_scale = 1.0

	_status.text = "DONE — see tools/visual_shots"
	await _wait(0.4)
	print("VISUAL_VALIDATE_OK shots=", _shot_i)
	get_tree().quit(0)

func _unfresh(sid: int) -> void:
	var s = _gs.get_squad(sid)
	if s == null:
		return
	s.fresh_turn = -1
	s.moved_turn = -1

func _sync(_tag: String) -> void:
	if _board and _board.has_method("sync_from_game_state"):
		_board.call("sync_from_game_state", _gs)

func _find_squad_view(sid: int) -> Node:
	var squads = _board.get_node_or_null("Squads")
	if squads == null:
		return null
	for c in squads.get_children():
		if int(c.get("squad_id")) == sid:
			return c
	return null

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _shot(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var tex := get_viewport().get_texture()
	if tex == null:
		printerr("No viewport texture for ", name)
		return
	var img: Image = tex.get_image()
	if img == null:
		printerr("No image for ", name)
		return
	# Godot 4 viewport grab is already upright on Metal in this project.
	_shot_i += 1
	var path := "%s/%02d_%s.png" % [_out_dir, _shot_i, name]
	var err := img.save_png(path)
	print("SHOT ", path, " err=", err)
