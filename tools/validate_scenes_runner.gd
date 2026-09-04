extends Node

## Loaded via validate_scenes.tscn so project autoloads are active.

const SCENES := [
	"res://scenes/Main.tscn",
	"res://scenes/MenuFlow.tscn",
]

func _ready() -> void:
	for path in SCENES:
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			push_error("FAIL: scene load: %s" % path)
			get_tree().quit(1)
			return
		var inst := packed.instantiate()
		if inst == null:
			push_error("FAIL: scene instantiate: %s" % path)
			get_tree().quit(1)
			return
		inst.free()
	print("VALIDATE_SCENES_OK")
	get_tree().quit(0)
