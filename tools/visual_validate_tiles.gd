extends Node

## Visual smoke for fungal terrain + slime-mold spawn pads.
## /Applications/Godot.app/Contents/MacOS/Godot --path . res://tools/visual_validate_tiles.tscn

const BoardScene = preload("res://scenes/Board.tscn")
const GameStateScript = preload("res://src/sim/GameState.gd")
const BoardStateScript = preload("res://src/sim/BoardState.gd")

var _out := "res://tools/visual_shots"

func _ready() -> void:
	print("TILE_VALIDATE_START")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.04, 0.04, 0.045)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.18, 0.17, 0.16)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)

	var world := Node3D.new()
	add_child(world)
	var light := DirectionalLight3D.new()
	light.light_energy = 2.05
	light.shadow_enabled = true
	light.rotation_degrees = Vector3(-61, 330, 0)
	world.add_child(light)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 16.0
	cam.position = Vector3(10, 16, 18)
	world.add_child(cam)
	cam.look_at(Vector3(7, 0.2, 7), Vector3.UP)
	cam.current = true

	var board = BoardScene.instantiate()
	world.add_child(board)
	await get_tree().process_frame

	var gs = GameStateScript.new()
	add_child(gs)
	gs.setup(GameStateScript.DEFAULT_BOARD_SIZE, 31)
	gs.squads.clear()

	# Force a readable terrain stripe sample near center.
	for y in range(5, 9):
		for x in range(4, 10):
			var c := Vector2i(x, y)
			if x < 6:
				gs.board.set_terrain(c, BoardStateScript.TERRAIN_SOIL)
			elif x < 8:
				gs.board.set_terrain(c, BoardStateScript.TERRAIN_ROCK)
			else:
				gs.board.set_terrain(c, BoardStateScript.TERRAIN_SAND)

	if board.has_method("sync_from_game_state"):
		board.call("sync_from_game_state", gs)

	await get_tree().process_frame
	await get_tree().create_timer(0.35).timeout
	await _shot("tiles_board")

	# Close on spawn pool (slime pads).
	cam.size = 7.5
	cam.position = Vector3(7.0, 8.0, 4.5)
	cam.look_at(Vector3(7.0, 0.2, 1.0), Vector3.UP)
	await get_tree().process_frame
	await get_tree().create_timer(0.25).timeout
	await _shot("tiles_spawn_pool")

	# Terrain close — soil / rock / sand stripes.
	cam.size = 6.0
	cam.position = Vector3(8.0, 7.5, 12.0)
	cam.look_at(Vector3(7.0, 0.15, 7.0), Vector3.UP)
	await get_tree().process_frame
	await get_tree().create_timer(0.25).timeout
	await _shot("tiles_terrain_close")

	print("TILE_VALIDATE_OK")
	get_tree().quit(0)

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var tex: ViewportTexture = get_viewport().get_texture()
	var img: Image = tex.get_image()
	var path := "%s/%s.png" % [_out, name]
	var err := img.save_png(path)
	print("wrote ", path, " err=", err)
