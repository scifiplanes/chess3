extends Node3D

## Visual smoke for battlefield juice: ragdoll, debris, shaft/dust, bursts.
## godot --path . res://tools/visual_validate_battlefield.tscn
## Prints VISUAL_BATTLEFIELD_OK and writes tools/visual_shots/bf_*.png

const GameStateScript = preload("res://src/sim/GameState.gd")
const UnitStateScript = preload("res://src/sim/UnitState.gd")
const BoardScene = preload("res://scenes/Board.tscn")
const BoardAtmosphereScript = preload("res://src/presentation/vfx/BoardAtmosphere.gd")
const AbilityBurstVfxScript = preload("res://src/presentation/vfx/AbilityBurstVfx.gd")
const HitSparkVfxScript = preload("res://src/presentation/vfx/HitSparkVfx.gd")
const CombatJuiceScript = preload("res://src/presentation/vfx/CombatJuice.gd")

var _gs
var _board: Node3D
var _atmo: Node3D
var _vfx: Node3D
var _cam: Camera3D
var _out_dir := "res://tools/visual_shots"
var _status: Label3D

func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))

	var light := DirectionalLight3D.new()
	light.light_energy = 2.0
	light.shadow_enabled = true
	light.rotation_degrees = Vector3(-55, 35, 0)
	add_child(light)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.04, 0.04, 0.045)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.2, 0.19, 0.17)
	e.ambient_light_energy = 0.55
	env.environment = e
	add_child(env)

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 3.2
	_cam.near = 0.1
	_cam.far = 200.0
	_cam.position = Vector3(6.2, 5.5, 9.5)
	add_child(_cam)
	_cam.look_at(Vector3(5.5, 0.4, 5.5), Vector3.UP)
	_cam.current = true

	_board = BoardScene.instantiate()
	add_child(_board)

	_status = Label3D.new()
	_status.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status.pixel_size = 0.01
	_status.position = Vector3(5.5, 2.2, 4.2)
	_status.modulate = Color(1, 0.9, 0.6)
	add_child(_status)

	_gs = GameStateScript.new()
	add_child(_gs)
	_gs.setup(GameStateScript.DEFAULT_BOARD_SIZE, 11)
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
	_gs.add_squad(1, Vector2i(7, 5), "core", 1)

	_board.call("sync_from_game_state", _gs)
	await _wait(0.35)

	_vfx = Node3D.new()
	add_child(_vfx)
	_atmo = BoardAtmosphereScript.new()
	add_child(_atmo)
	var bc: Vector2 = _board.call("board_center_xz")
	_atmo.call("setup", float(_board.call("board_half_extent")), Vector3(bc.x, 0.0, bc.y))
	AbilityBurstVfxScript.warmup(_vfx, Vector3(5.5, 0.3, 5.5))
	HitSparkVfxScript.warmup(_vfx, Vector3(5.5, 0.5, 5.5))

	_status.text = "idle + shaft"
	await _shot("bf_01_atmosphere")

	var view = _board.call("get_squad_view", sid)
	_status.text = "ragdoll impact"
	if view != null:
		view.call("enter_ragdoll", Vector3(2.5, 3.5, 0.5), 1.2)
	CombatJuiceScript.play(
		get_tree(), _vfx, _atmo, _board.call("debris_root"), "slam",
		Vector3(5.5, 0.3, 5.5), Vector3(5.5, 0.3, 5.5),
		1.0,
		float(_board.call("board_ground_y")),
		_board.call("board_center_xz"),
		float(_board.call("board_half_extent")),
		view
	)
	await _wait(0.35)
	await _shot("bf_02_ragdoll_debris")

	await _wait(1.0)
	_status.text = "reseated"
	await _shot("bf_03_reseated")

	print("VISUAL_BATTLEFIELD_OK")
	await _wait(0.1)
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
