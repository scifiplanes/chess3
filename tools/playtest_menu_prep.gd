extends Node

## Headless MenuFlow prep smoke: bay / draft / handoff.
## Godot --headless --path . res://tools/playtest_menu_prep.tscn

const MenuScene = preload("res://scenes/MenuFlow.tscn")
const DeckRules = preload("res://src/app/DeckRules.gd")

var _fails: Array[String] = []

func _ready() -> void:
	print("=== MenuFlow loadout bay / draft smoke ===")
	var menu = MenuScene.instantiate()
	add_child(menu)
	await get_tree().process_frame
	await get_tree().process_frame

	if not menu.has_method("show_screen_for_validation"):
		_fail("MenuFlow missing show_screen_for_validation")
		_finish()
		return

	menu.call("show_screen_for_validation", "prep")
	await get_tree().process_frame
	await get_tree().process_frame
	_assert_prep_bay(menu)

	if menu.has_method("_on_prep_primary"):
		menu.call("_on_prep_primary")
		await get_tree().process_frame
		await get_tree().process_frame
		_assert_handoff(menu)
		if menu.has_method("_begin_player_two_prep"):
			menu.call("_begin_player_two_prep")
			await get_tree().process_frame
			await get_tree().process_frame
			if int(menu.get("_prep_player")) != 1:
				_fail("expected prep_player=1 after handoff continue")
			else:
				print("PASS: P2 bay after handoff")

	if menu.has_method("_set_prep_mode"):
		menu.set("_prep_player", 0)
		menu.set("_p0_locked", false)
		menu.call("_set_prep_mode", 1) # PrepMode.DRAFT
		await get_tree().process_frame
		await get_tree().process_frame
		var pack: Array = menu.get("_draft_pack")
		if pack.size() != 5:
			_fail("draft pack size %d" % pack.size())
		elif not pack.has("core"):
			_fail("draft empty-inv pack missing core")
		else:
			print("PASS: draft pack offers core")
		if menu.has_method("_draft_pick"):
			menu.call("_draft_pick", "core")
			await get_tree().process_frame
			var inv: Dictionary = menu.get("_p0_inv")
			if int(inv.get("core", 0)) < 1:
				_fail("draft pick core did not attach")
			else:
				var v: Dictionary = DeckRules.validate(inv)
				if not bool(v["ok"]):
					_fail("after core pick still invalid: %s" % str(v.get("reason", "")))
				else:
					print("PASS: draft pick core validates")

	menu.call("show_screen_for_validation", "main")
	await get_tree().process_frame
	menu.call("show_screen_for_validation", "settings")
	await get_tree().process_frame
	print("PASS: main/settings screens rebuild")

	_finish()

func _assert_prep_bay(menu) -> void:
	if int(menu.get("_prep_mode")) != 0:
		_fail("prep default mode should be BAY")
		return
	if int(menu.get("_prep_player")) != 0:
		_fail("prep should start on P1")
		return
	var inv: Dictionary = menu.get("_p0_inv")
	var v: Dictionary = DeckRules.validate(inv)
	if not bool(v["ok"]):
		_fail("default bay inv invalid: %s" % str(v.get("reason", "")))
		return
	print("PASS: bay opens on P1 with valid default")

func _assert_handoff(menu) -> void:
	if not bool(menu.get("_p0_locked")):
		_fail("P1 should be locked after primary")
		return
	print("PASS: P1 locked (handoff shown)")

func _fail(msg: String) -> void:
	_fails.append(msg)
	print("FAIL: ", msg)

func _finish() -> void:
	print("=== results: %d fail ===" % _fails.size())
	if _fails.is_empty():
		print("PLAYTEST_MENU_PREP_OK")
		get_tree().quit(0)
	else:
		print("PLAYTEST_MENU_PREP_FAIL")
		get_tree().quit(1)
