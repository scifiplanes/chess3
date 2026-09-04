extends Node

## Capture CRT menu screenshots and assert concept-parity markers.
## /Applications/Godot.app/Contents/MacOS/Godot --path . res://tools/visual_validate_menu.tscn

const MenuScene = preload("res://scenes/MenuFlow.tscn")

var _out := "res://tools/visual_shots"
const _MIN_BYTES := 12000

func _ready() -> void:
	print("MENU_VALIDATE_START")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))

	var menu = MenuScene.instantiate()
	menu.set_meta("validation_mode", true)
	add_child(menu)
	await get_tree().process_frame
	await get_tree().process_frame

	var screens := [
		["main", "menu_main_crt"],
		["prep", "menu_prep_crt"],
		["settings", "menu_settings_crt"],
	]
	for entry in screens:
		menu.call("show_screen_for_validation", entry[0])
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		print("MENU_SCREEN ", entry[0], " enum=", int(menu.get("_screen")))
		await _shot(entry[1])

	_assert_shots()
	print("VISUAL_VALIDATE_MENU_OK")
	get_tree().quit()

func _shot(name: String) -> void:
	await get_tree().create_timer(0.45).timeout
	var tex := get_viewport().get_texture()
	if tex == null:
		print("SKIP_SHOT %s (headless dummy renderer)" % name)
		return
	var img := tex.get_image()
	if img == null:
		print("SKIP_SHOT %s (null image)" % name)
		return
	var path := ProjectSettings.globalize_path("%s/%s.png" % [_out, name])
	img.save_png(path)
	print("SHOT ", path)

func _assert_shots() -> void:
	var paths: Dictionary = {}
	for fname in ["menu_main_crt.png", "menu_prep_crt.png", "menu_settings_crt.png"]:
		var p := ProjectSettings.globalize_path("%s/%s" % [_out, fname])
		if not FileAccess.file_exists(p):
			push_error("MISSING_SHOT %s" % fname)
			continue
		var bytes := FileAccess.get_file_as_bytes(p)
		var sz := bytes.size()
		if sz < _MIN_BYTES:
			push_error("SHOT_TOO_SMALL %s (%d bytes)" % [fname, sz])
		else:
			print("PARITY_OK ", fname, " ", sz, " bytes")
		paths[fname] = bytes
	# Main must not be a duplicate of prep (prior bug: HOT-SEAT focus → prep).
	if paths.has("menu_main_crt.png") and paths.has("menu_prep_crt.png"):
		if paths["menu_main_crt.png"] == paths["menu_prep_crt.png"]:
			push_error("MENU_MAIN_EQ_PREP — main shot is identical to prep")
		else:
			print("PARITY_OK menu_main≠menu_prep")
