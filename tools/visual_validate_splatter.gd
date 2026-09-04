extends Node3D

## Visual proofs: yellow-amber organ-pop splatter + floor decals.
## godot --path . res://tools/visual_validate_splatter.tscn
## Writes tools/visual_shots/splat_*.png and prints VISUAL_SPLATTER_OK

const GameStateScript = preload("res://src/sim/GameState.gd")
const UnitStateScript = preload("res://src/sim/UnitState.gd")
const BoardScene = preload("res://scenes/Board.tscn")
const OrganSplatterVfxScript = preload("res://src/presentation/vfx/OrganSplatterVfx.gd")

var _gs
var _board: Node3D
var _vfx: Node3D
var _cam: Camera3D
var _out_dir := "res://tools/visual_shots"
var _status: Label3D

func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))

	var light := DirectionalLight3D.new()
	light.light_energy = 2.05
	light.shadow_enabled = true
	light.rotation_degrees = Vector3(-55, 40, 0)
	add_child(light)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.04, 0.04, 0.045)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.22, 0.2, 0.18)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 2.4
	_cam.near = 0.1
	_cam.far = 200.0
	_cam.position = Vector3(5.9, 4.8, 8.6)
	add_child(_cam)
	_cam.look_at(Vector3(5.5, 0.35, 5.5), Vector3.UP)
	_cam.current = true

	_board = BoardScene.instantiate()
	add_child(_board)
	_board.name = "Board"

	_vfx = Node3D.new()
	_vfx.name = "VfxRoot"
	add_child(_vfx)

	_status = Label3D.new()
	_status.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status.pixel_size = 0.009
	_status.position = Vector3(5.5, 1.85, 4.35)
	_status.modulate = Color(1.0, 0.75, 0.35)
	add_child(_status)

	_gs = GameStateScript.new()
	add_child(_gs)
	_gs.setup(GameStateScript.DEFAULT_BOARD_SIZE, 17)
	_gs.squads.clear()
	_gs._next_squad_id = 1
	_gs.offer_pending = false
	_gs.winner = -1

	var sid: int = int(_gs.add_squad(0, Vector2i(5, 5), "core", 1))
	var s = _gs.get_squad(sid)
	s.units.append(UnitStateScript.new("claw", 1, 1))
	s.units.append(UnitStateScript.new("eye", 1, 1))
	s.units.append(UnitStateScript.new("shell", 1, 1))
	s.units.append(UnitStateScript.new("hoof", 1, 1))
	s.organs_locked = true

	_board.call("sync_from_game_state", _gs)
	await _wait(0.4)
	OrganSplatterVfxScript.warmup(_vfx, Vector3(5.5, 0.5, 5.5))

	_status.text = "before pop"
	await _shot("splat_01_before")

	# Pop two organs via corpse path (same as combat destruction).
	_status.text = "orange burst"
	var p0 := Vector3(5.35, 0.55, 5.45)
	var p1 := Vector3(5.65, 0.62, 5.55)
	_board.call("spawn_organ_corpse", "claw", p0)
	await _wait(0.06)
	_board.call("spawn_organ_corpse", "eye", p1)
	await _wait(0.08)
	await _shot("splat_02_burst")

	_status.text = "floor decals"
	# Extra direct splat for a clear decal cluster
	OrganSplatterVfxScript.play(_vfx, Vector3(5.5, 0.5, 5.5), 0.11, 1.2)
	OrganSplatterVfxScript.play(_vfx, Vector3(5.25, 0.5, 5.7), 0.11, 0.9)
	await _wait(0.35)
	await _shot("splat_03_decals")

	# Wider framing to show multiple stains
	_cam.size = 4.2
	_cam.position = Vector3(6.5, 6.2, 10.0)
	_cam.look_at(Vector3(5.5, 0.2, 5.5), Vector3.UP)
	_status.text = "wide + stains"
	await _wait(0.15)
	await _shot("splat_04_wide")

	print("VISUAL_SPLATTER_OK")
	await _wait(0.05)
	get_tree().quit(0)

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _shot(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var tex := get_viewport().get_texture()
	if tex == null:
		print("shot_skip_no_tex ", name)
		return
	var img := tex.get_image()
	if img == null:
		print("shot_skip_no_img ", name)
		return
	var path := "%s/%s.png" % [_out_dir, name]
	img.save_png(path)
	print("wrote ", path)
