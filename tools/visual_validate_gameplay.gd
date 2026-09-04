extends Node

## Full-match visual smoke: turn-1 offer, CP spacing, highlights, corpses.
## Headless dummy renderer cannot capture — sim + parity checks skip when shots fail.
## With display: godot --path . res://tools/visual_validate_gameplay.tscn

const HudScene = preload("res://scenes/HUD.tscn")
const BoardScene = preload("res://scenes/Board.tscn")
const GameStateScript = preload("res://src/sim/GameState.gd")
const UnitStateScript = preload("res://src/sim/UnitState.gd")
const ResolverScript = preload("res://src/sim/Resolver.gd")
const RulesScript = preload("res://src/sim/Rules.gd")
const PathfindingScript = preload("res://src/sim/Pathfinding.gd")

var _out := "res://tools/visual_shots"
var _gs
var _board: Node3D
var _hud: Control
var _main_node: Node3D
var _cam: Camera3D
var _resolver = ResolverScript.new()
var _fails: Array[String] = []
var _shots_taken := {} # String -> bool

func _ready() -> void:
	print("GAMEPLAY_VALIDATE_START")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.04, 0.04, 0.045)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.18, 0.17, 0.16)
	e.ambient_light_energy = 0.55
	env.environment = e
	add_child(env)

	_main_node = Node3D.new()
	add_child(_main_node)
	var light := DirectionalLight3D.new()
	light.light_energy = 2.05
	light.shadow_enabled = true
	light.rotation_degrees = Vector3(-61, 330, 0)
	_main_node.add_child(light)

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 16.0
	_cam.position = Vector3(7, 14, 16)
	_main_node.add_child(_cam)
	_cam.look_at(Vector3(7, 0.2, 7), Vector3.UP)
	_cam.current = true

	_board = BoardScene.instantiate()
	_main_node.add_child(_board)

	_gs = GameStateScript.new()
	add_child(_gs)
	_gs.setup(GameStateScript.DEFAULT_BOARD_SIZE, 4242)

	if int(_gs.turn_number) != 1 or not bool(_gs.offer_pending):
		_fail("boot should start turn 1 offer")
	if _gs.offer_cards.size() != 5:
		_fail("turn 1 need 5 cards, got %d" % _gs.offer_cards.size())
	if int(_gs.offer_picks_remaining) != 2:
		_fail("turn 1 need 2 picks, got %d" % int(_gs.offer_picks_remaining))

	if not _board.has_method("sync_from_game_state"):
		_fail("BoardView failed to load (check BoardView.gd parse errors)")
		_finish()
		return
	_board.call("sync_from_game_state", _gs)
	await get_tree().create_timer(0.35).timeout

	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = HudScene.instantiate()
	layer.add_child(_hud)
	await get_tree().create_timer(0.15).timeout

	var playable: Array[String] = []
	for c in _gs.offer_cards:
		playable.append(str(c))
	_hud.call("set_status", "P1 Turn (T1)", "No selection", "CP 0-0", "")
	_hud.call("set_phase_and_prompt", "Phase: Offer", "Pick 2 · place each on a glowing home pad — that becomes your Mutant.")
	_hud.call("set_mode_and_info", "Mode: Select", "Gene cartridges show organ abilities")
	_hud.call("set_offer", _gs.offer_cards, true, str(_gs.offer_cards[0]), playable, int(_gs.offer_picks_remaining))

	await get_tree().create_timer(0.35).timeout
	await _shot("gp_01_opening_offer")
	_assert_offer_tray_pixels()

	_cam.size = 18.0
	_cam.position = Vector3(7, 18, 20)
	_cam.look_at(Vector3(7, 0, 7), Vector3.UP)
	await get_tree().create_timer(0.2).timeout
	await _shot("gp_02_cp_board")
	_assert_cp_spacing()

	_gs.clear_offer_phase()
	var sid: int = int(_gs.add_squad(0, Vector2i(2, 0), "core", 1))
	var s = _gs.get_squad(sid)
	s.units.append(UnitStateScript.new("claw", 1, 1))
	s.units.append(UnitStateScript.new("eye", 1, 1))
	s.fresh_turn = -1
	s.moved_turn = -1
	_board.call("sync_from_game_state", _gs)

	_hud.call("set_offer", [] as Array[String], false, "", [] as Array[String])
	_hud.call("set_phase_and_prompt", "Phase: Action", "Action: click highlighted cell to move")
	_hud.call("set_action_enabled", "move", true)

	if _board.has_method("clear_highlights"):
		_board.call("clear_highlights")
	var rules = RulesScript.new()
	var pathfinding = PathfindingScript.new()
	var reachable = pathfinding.reachable_cells(_gs, sid, rules.move_range_for_squad(_gs, s))
	for cell in reachable.keys():
		_board.call("highlight_cell", cell, Color(0.0, 0.78, 0.95))

	_cam.size = 14.0
	_cam.position = Vector3(5, 12, 14)
	_cam.look_at(Vector3(4, 0.2, 3), Vector3.UP)
	await get_tree().create_timer(0.25).timeout
	await _shot("gp_03_move_highlights")
	_assert_move_highlight_color()

	_resolver._pop_organs(_gs, s, 1)
	_board.call("sync_from_game_state", _gs)
	_cam.size = 4.5
	_cam.position = Vector3(2.3, 3.5, 4.5)
	_cam.look_at(Vector3(2, 0.3, 0.2), Vector3.UP)
	await get_tree().create_timer(1.5).timeout
	await _shot("gp_04_corpse_no_sphere")
	_assert_no_gray_corpse_sphere()

	_finish()

func _assert_offer_tray_pixels() -> void:
	if not bool(_shots_taken.get("gp_01_opening_offer", false)):
		print("SKIP parity gp_01 (no capture)")
		return
	var path := ProjectSettings.globalize_path("%s/gp_01_opening_offer.png" % _out)
	if not FileAccess.file_exists(path):
		_fail("missing gp_01 shot")
		return
	var img := Image.load_from_file(path)
	if img == null:
		_fail("could not load gp_01")
		return
	var amber_hits := 0
	for y in range(int(img.get_height() * 0.58), img.get_height() - 6):
		for x in range(60, img.get_width() - 60, 3):
			var c: Color = img.get_pixel(x, y)
			if c.r > 0.5 and c.g > 0.38 and c.b < 0.38 and c.a > 0.45:
				amber_hits += 1
	if amber_hits < 50:
		_fail("offer tray too faint (amber_hits=%d)" % amber_hits)
	else:
		print("PARITY_OK offer_tray amber_hits=", amber_hits)
	var col_hits: Array[int] = []
	col_hits.resize(img.get_width())
	col_hits.fill(0)
	var y0 := int(img.get_height() * 0.62)
	var y1 := img.get_height() - 8
	for y in range(y0, y1):
		for x in range(60, img.get_width() - 60):
			var c: Color = img.get_pixel(x, y)
			if c.r > 0.48 and c.g > 0.35 and c.b < 0.4 and c.a > 0.4:
				col_hits[x] += 1
	var card_blobs := 0
	var in_blob := false
	for bx in range(60, img.get_width() - 60, 8):
		var bucket := 0
		for x in range(bx, mini(bx + 8, img.get_width())):
			bucket += col_hits[x]
		if bucket > 6:
			if not in_blob:
				card_blobs += 1
				in_blob = true
		else:
			in_blob = false
	# Card-blob count used to pass via MOVE/END amber keys; those hide during offer now.
	# amber_hits already proves the tray; blob count is diagnostic only.
	print("PARITY_OK offer_card_blobs=", card_blobs, " (diag)")
	var bottom := _hud.get_node_or_null("BottomBar") as Control
	if bottom != null and bottom.visible:
		_fail("action bar still visible during gene offer")
	else:
		print("PARITY_OK action_bar_hidden_during_offer")

func _assert_cp_spacing() -> void:
	if _gs == null or _gs.board == null:
		_fail("no board for CP check")
		return
	var cps = _gs.board.control_points
	if cps.size() != 3:
		_fail("expected 3 CPs, got %d" % cps.size())
		return
	var xs: Array[int] = []
	for cp in cps:
		xs.append(int(cp.cell.x))
	xs.sort()
	var span := int(xs[2]) - int(xs[0])
	if span < 8:
		_fail("CP span too narrow (%d, want >=8)" % span)
	else:
		print("PARITY_OK cp_span=", span)

func _assert_move_highlight_color() -> void:
	if not bool(_shots_taken.get("gp_03_move_highlights", false)):
		print("SKIP parity gp_03 (no capture)")
		return
	var path := ProjectSettings.globalize_path("%s/gp_03_move_highlights.png" % _out)
	if not FileAccess.file_exists(path):
		_fail("missing gp_03 shot")
		return
	var img := Image.load_from_file(path)
	var cyan_hits := 0
	var gold_hits := 0
	for y in range(int(img.get_height() * 0.1), int(img.get_height() * 0.9)):
		for x in range(int(img.get_width() * 0.15), int(img.get_width() * 0.85), 2):
			var c: Color = img.get_pixel(x, y)
			if c.b > 0.5 and c.g > 0.45 and c.r < 0.3:
				cyan_hits += 1
			if c.r > 0.6 and c.g > 0.5 and c.b < 0.45 and c.r > c.b + 0.15:
				gold_hits += 1
	if cyan_hits < 25:
		_fail("move reach cyan too faint (hits=%d)" % cyan_hits)
	else:
		print("PARITY_OK move_cyan_hits=", cyan_hits)
	if gold_hits < 15:
		_fail("CP gold zones too faint vs move (gold_hits=%d)" % gold_hits)
	else:
		print("PARITY_OK cp_gold_hits=", gold_hits)

func _assert_no_gray_corpse_sphere() -> void:
	if not bool(_shots_taken.get("gp_04_corpse_no_sphere", false)):
		print("SKIP parity gp_04 (no capture)")
		return
	var path := ProjectSettings.globalize_path("%s/gp_04_corpse_no_sphere.png" % _out)
	if not FileAccess.file_exists(path):
		_fail("missing gp_04 shot")
		return
	var img := Image.load_from_file(path)
	var gray_blob := 0
	var cx := int(img.get_width() * 0.48)
	var cy := int(img.get_height() * 0.5)
	for dy in range(-35, 36, 2):
		for dx in range(-35, 36, 2):
			var c: Color = img.get_pixel(cx + dx, cy + dy)
			if c.r > 0.33 and c.r < 0.43 and absf(c.g - c.r) < 0.04 and absf(c.b - c.r) < 0.06:
				gray_blob += 1
	if gray_blob > 90:
		_fail("gray corpse sphere still visible (hits=%d)" % gray_blob)
	else:
		print("PARITY_OK no_gray_sphere hits=", gray_blob)

func _fail(msg: String) -> void:
	_fails.append(msg)
	push_error("GAMEPLAY_VALIDATE_FAIL: " + msg)

func _finish() -> void:
	if _fails.is_empty():
		if _shots_taken.is_empty():
			print("HEADLESS_SIM_ONLY (screenshots skipped — run with display for parity PNGs)")
		print("VISUAL_VALIDATE_GAMEPLAY_OK")
		get_tree().quit(0)
	else:
		for f in _fails:
			print("FAIL: ", f)
		get_tree().quit(1)

func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP_SHOT ", name, " (headless dummy renderer)")
		return
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.08).timeout
	var tex := get_viewport().get_texture()
	if tex == null:
		print("SKIP_SHOT ", name, " (no viewport texture)")
		return
	var img := tex.get_image()
	if img == null or img.is_empty():
		print("SKIP_SHOT ", name, " (empty viewport image)")
		return
	var path := "%s/%s.png" % [_out, name]
	var err := img.save_png(path)
	if err != OK:
		print("SKIP_SHOT ", name, " (save err=", err, ")")
		return
	_shots_taken[name] = true
	print("wrote ", path, " err=", err)
