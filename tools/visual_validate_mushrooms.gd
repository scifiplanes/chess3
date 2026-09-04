extends Node

## Visual smoke for weird-mushroom obstacle sprites.
## /Applications/Godot.app/Contents/MacOS/Godot --path . res://tools/visual_validate_mushrooms.tscn

const BoardScene = preload("res://scenes/Board.tscn")
const GameStateScript = preload("res://src/sim/GameState.gd")

var _out := "res://tools/visual_shots"

func _ready() -> void:
	print("MUSHROOM_VALIDATE_START")
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
	cam.size = 10.0
	cam.position = Vector3(8.5, 11.0, 14.5)
	world.add_child(cam)
	cam.look_at(Vector3(7.0, 0.4, 7.0), Vector3.UP)
	cam.current = true

	var board = BoardScene.instantiate()
	world.add_child(board)
	await get_tree().process_frame

	var gs = GameStateScript.new()
	add_child(gs)
	gs.setup(GameStateScript.DEFAULT_BOARD_SIZE, 77)
	gs.squads.clear()
	# Showcase cluster: one of each mushroom variant + mix of destructible.
	var showcase: Array[Vector2i] = [
		Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5),
		Vector2i(5, 6), Vector2i(6, 6), Vector2i(7, 6),
		Vector2i(4, 7), Vector2i(8, 7), Vector2i(6, 8),
	]
	# Clear generated obstacles in the showcase area so variants are readable.
	for y in range(4, 10):
		for x in range(4, 10):
			var c := Vector2i(x, y)
			if gs.board.obstacles.has(c):
				gs.board.obstacles.erase(c)
	for i in range(showcase.size()):
		var cell: Vector2i = showcase[i]
		var destructible := (i % 3) == 1
		gs.board.add_obstacle(cell, 6 if destructible else 9999, destructible)

	if board.has_method("sync_from_game_state"):
		board.call("sync_from_game_state", gs)

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.35).timeout
	await _shot("mushrooms_cluster")

	# Wider board context (seeded generation mushrooms + hero props among terrain).
	cam.size = 16.0
	cam.position = Vector3(10, 16, 18)
	cam.look_at(Vector3(7, 0.2, 7), Vector3.UP)
	var gs2 = GameStateScript.new()
	add_child(gs2)
	gs2.setup(GameStateScript.DEFAULT_BOARD_SIZE, 19)
	if board.has_method("sync_from_game_state"):
		board.call("sync_from_game_state", gs2)
	print("HERO_PROPS=", gs2.board.hero_props.size())
	await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	await _shot("mushrooms_board")
	await _shot("heroes_board")

	# Force a mixed hero showcase cluster for art read.
	gs2.board.hero_props.clear()
	var hero_cells: Array[Vector2i] = [
		Vector2i(4, 5), Vector2i(6, 5), Vector2i(8, 5),
		Vector2i(5, 7), Vector2i(7, 7), Vector2i(6, 8),
	]
	var kinds := ["mushroom", "blob", "rock", "mushroom", "blob", "rock"]
	for y in range(4, 10):
		for x in range(3, 10):
			var c0 := Vector2i(x, y)
			if gs2.board.obstacles.has(c0):
				gs2.board.obstacles.erase(c0)
	for i in range(hero_cells.size()):
		var hc: Vector2i = hero_cells[i]
		gs2.board.add_obstacle(hc, 9999, false)
		gs2.board.hero_props.append({
			"cell": hc,
			"kind": kinds[i],
			"variant": ((i % 4) + 1) if kinds[i] != "mushroom" else (i % 6),
		})
	if board.has_method("sync_from_game_state"):
		board.call("sync_from_game_state", gs2)
	cam.size = 9.0
	cam.position = Vector3(8.0, 10.0, 13.0)
	cam.look_at(Vector3(6.0, 0.5, 6.5), Vector3.UP)
	await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	await _shot("heroes_cluster")

	# Close orbit — confirm alpha edges / billboards.
	cam.size = 6.5
	cam.position = Vector3(7.5, 6.5, 11.0)
	cam.look_at(Vector3(6.0, 0.6, 6.0), Vector3.UP)
	if board.has_method("sync_from_game_state"):
		board.call("sync_from_game_state", gs)
	await get_tree().process_frame
	await get_tree().create_timer(0.25).timeout
	await _shot("mushrooms_close")

	print("MUSHROOM_VALIDATE_OK")
	get_tree().quit(0)

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var tex: ViewportTexture = get_viewport().get_texture()
	var img: Image = tex.get_image()
	var path := "%s/%s.png" % [_out, name]
	var err := img.save_png(path)
	print("wrote ", path, " err=", err)
