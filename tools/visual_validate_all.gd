extends SceneTree

## Run all visual validation scenes sequentially (requires display; not headless).
## godot --path . --script res://tools/visual_validate_all.gd

const SCENES := [
	"res://tools/visual_validate_menu.tscn",
	"res://tools/visual_validate_hud.tscn",
	"res://tools/visual_validate_rig.tscn",
	"res://tools/visual_validate_battlefield.tscn",
	"res://tools/visual_validate_splatter.tscn",
	"res://tools/visual_validate_tiles.tscn",
	"res://tools/visual_validate_mushrooms.tscn",
	"res://tools/visual_validate_gameplay.tscn",
	"res://tools/visual_validate_demo.tscn",
]

const OK_MARKERS := [
	"VISUAL_VALIDATE_MENU_OK",
	"HUD_VALIDATE_OK",
	"VISUAL_VALIDATE_OK",
	"VISUAL_BATTLEFIELD_OK",
	"VISUAL_SPLATTER_OK",
	"TILE_VALIDATE_OK",
	"MUSHROOM_VALIDATE_OK",
	"VISUAL_VALIDATE_GAMEPLAY_OK",
	"DEMO_VALIDATE_OK",
]

func _init() -> void:
	print("=== Visual validate all ===")
	call_deferred("_run_all")

func _run_all() -> void:
	var fails := 0
	var project := ProjectSettings.globalize_path("res://")
	for i in range(SCENES.size()):
		var scene_path: String = SCENES[i]
		var expect: String = OK_MARKERS[i]
		print("\n--- ", scene_path.get_file(), " ---")
		var output: Array = []
		var code := OS.execute(
			OS.get_executable_path(),
			["--path", project, scene_path],
			output,
			true,
			false
		)
		var out := ""
		for line in output:
			out += str(line) + "\n"
		print(out.strip_edges())
		if code != 0 or expect not in out:
			push_error("FAIL %s (exit=%d, expected %s)" % [scene_path, code, expect])
			fails += 1
		else:
			print("PASS ", scene_path.get_file())
	if fails == 0:
		print("\nVISUAL_VALIDATE_ALL_OK")
		quit(0)
	else:
		print("\nVISUAL_VALIDATE_ALL_FAIL count=", fails)
		quit(1)
