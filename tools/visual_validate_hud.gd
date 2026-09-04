extends Node

## Capture K1 HUD screenshots.
## /Applications/Godot.app/Contents/MacOS/Godot --path . res://tools/visual_validate_hud.tscn

const HudScene = preload("res://scenes/HUD.tscn")
const BoardScene = preload("res://scenes/Board.tscn")
const GameStateScript = preload("res://src/sim/GameState.gd")
const UnitStateScript = preload("res://src/sim/UnitState.gd")

var _out := "res://tools/visual_shots"

func _ready() -> void:
	print("HUD_VALIDATE_START")
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
	gs.setup(GameStateScript.DEFAULT_BOARD_SIZE, 7)
	var sid: int = int(gs.add_squad(0, Vector2i(5, 5), "core", 1))
	var s = gs.get_squad(sid)
	s.units.append(UnitStateScript.new("claw", 1, 1))
	s.units.append(UnitStateScript.new("eye", 1, 1))
	gs.add_squad(1, Vector2i(9, 8), "core", 1)
	gs.add_squad(0, Vector2i(3, 7), "shell", 1)
	gs.add_squad(1, Vector2i(11, 4), "hoof", 1)
	if board.has_method("sync_from_game_state"):
		board.call("sync_from_game_state", gs)

	var layer := CanvasLayer.new()
	add_child(layer)
	var hud = HudScene.instantiate()
	layer.add_child(hud)

	await get_tree().process_frame
	await get_tree().process_frame

	var cards: Array[String] = ["core", "claw", "eye", "shell", "hoof"]
	hud.call("set_status", "P1 Turn (T1)", "No selection", "CP 0-0", "")
	hud.call("set_phase_and_prompt", "Phase: Offer", "Pick 2 · place each on a glowing home pad — that becomes your Mutant.")
	hud.call("set_mode_and_info", "Mode: Select", "Hover info chip — gene tray shows abilities")
	var playable: Array[String] = ["core", "claw", "eye", "shell", "hoof"]
	hud.call("set_offer", cards, true, "claw", playable, 3)
	hud.call("set_action_enabled", "move", false)
	hud.call("set_action_enabled", "end_turn", false)

	await get_tree().create_timer(0.4).timeout
	await _shot("hud_k1_offer")

	hud.call("set_offer", [] as Array[String], false, "", [] as Array[String])
	hud.call("set_phase_and_prompt", "Phase: Action", "Action: select a Mutant and use Move / abilities")
	hud.call("set_action_enabled", "move", true)
	hud.call("set_action_enabled", "end_turn", true)
	hud.call("rebuild_ability_buttons_for_squad", s, {}, true)

	await get_tree().create_timer(0.3).timeout
	await _shot("hud_k1_action")
	await _shot("hud_wetmud_action")

	# Also copy into docs for parity review vs wet-mud concept.
	var docs := "res://docs/hud-concepts"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(docs))
	for n in ["hud_k1_offer", "hud_k1_action", "hud_wetmud_action"]:
		var src := "%s/%s.png" % [_out, n]
		var dst := "%s/%s.png" % [docs, n]
		var img2 := Image.load_from_file(ProjectSettings.globalize_path(src))
		if img2:
			img2.save_png(dst)
			print("copied ", dst)

	print("HUD_VALIDATE_OK")
	get_tree().quit(0)

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var tex: ViewportTexture = get_viewport().get_texture()
	var img: Image = tex.get_image()
	var path := "%s/%s.png" % [_out, name]
	var err := img.save_png(path)
	print("wrote ", path, " err=", err)
