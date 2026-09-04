extends Node

## Boot-check via scene (autoloads active). Catches Main.gd parse errors.
## godot --headless --path . res://tools/playtest_main_boot.tscn

func _ready() -> void:
	call_deferred("_run")

func _fail(detail: String) -> void:
	push_error("FAIL: main boot — %s" % detail)
	print("FAIL: main boot — ", detail)
	get_tree().quit(1)

func _run() -> void:
	print("=== main boot playtest ===")
	var DeckRules = preload("res://src/app/DeckRules.gd")
	var pool: Dictionary = DeckRules.DEFAULT_POOL.duplicate(true)
	MatchSession.configure_hotseat(pool.duplicate(true), pool.duplicate(true), 99001)

	var packed: PackedScene = load("res://scenes/Main.tscn") as PackedScene
	if packed == null:
		_fail("Main.tscn load null (Main.gd likely failed to compile)")
		return
	var inst := packed.instantiate()
	if inst == null:
		_fail("Main.tscn instantiate null")
		return
	if inst.get_script() == null:
		_fail("Main instance has no script")
		return
	add_child(inst)
	for _i in range(12):
		await get_tree().process_frame
	if not is_instance_valid(inst):
		_fail("Main died during boot frames")
		return
	if inst.get_node_or_null("Board") == null:
		_fail("Main missing Board")
		return
	if inst.get_node_or_null("HUD/HUDRoot") == null and inst.get_node_or_null("HUD") == null:
		_fail("Main missing HUD")
		return
	for path in [
		"res://src/presentation/Main.gd",
		"res://src/presentation/HUD.gd",
		"res://src/presentation/SquadView.gd",
		"res://src/presentation/SquadLayer.gd",
		"res://src/presentation/MenuFlow.gd",
	]:
		if load(path) == null:
			_fail("script load null: %s" % path)
			return
	print("PLAYTEST_MAIN_BOOT_OK")
	get_tree().quit(0)
