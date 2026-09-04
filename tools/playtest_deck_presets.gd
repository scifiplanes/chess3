extends SceneTree

## Validates loadout-bay presets + gene draft packs.
## godot --headless --path . --script res://tools/playtest_deck_presets.gd

const DeckRules = preload("res://src/app/DeckRules.gd")

var _failed := false

func _init() -> void:
	print("=== Deck preset + draft validation ===")
	for pname in ["default", "rush", "kite", "tank", "swarm", "clear"]:
		var inv: Dictionary = DeckRules.preset(pname)
		var v: Dictionary = DeckRules.validate(inv)
		var cost := DeckRules.point_cost(inv)
		if pname == "clear":
			if bool(v["ok"]):
				_fail("clear preset should fail (no core)")
			else:
				print("PASS: clear invalid as expected (%s)" % str(v.get("reason", "")))
			continue
		if not bool(v["ok"]):
			_fail("%s invalid: %s (cost=%d)" % [pname, str(v.get("reason", "")), cost])
			continue
		if cost > DeckRules.BUDGET:
			_fail("%s over budget %d > %d" % [pname, cost, DeckRules.BUDGET])
			continue
		print("PASS: %s cost=%d/%d" % [pname, cost, DeckRules.BUDGET])

	_test_draft_pack()
	_test_style_presets_list()
	_test_bay_flow_inventory()

	if _failed:
		print("PLAYTEST_DECK_PRESETS_FAIL")
		quit(1)
	print("PLAYTEST_DECK_PRESETS_OK")
	quit(0)

func _fail(msg: String) -> void:
	print("FAIL: ", msg)
	_failed = true

func _test_style_presets_list() -> void:
	var styles: Array[String] = DeckRules.style_presets()
	for need in ["default", "rush", "kite", "tank", "swarm"]:
		if not styles.has(need):
			_fail("style_presets missing %s" % need)
			return
	print("PASS: style_presets has bay styles")

func _test_draft_pack() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var empty: Dictionary = DeckRules.sanitized_copy({})
	var pack: Array[String] = DeckRules.draft_pack(empty, rng, 5)
	if pack.size() != 5:
		_fail("draft pack size %d != 5" % pack.size())
		return
	if not pack.has("core"):
		_fail("empty inv pack must offer core, got %s" % str(pack))
		return
	var seen := {}
	for g in pack:
		if seen.has(g):
			_fail("duplicate gene in pack: %s" % g)
			return
		seen[g] = true
		if not DeckRules.GENE_COSTS.has(g):
			_fail("unknown gene in pack: %s" % g)
			return
	# After taking core, packs should still be size 5
	var inv := empty.duplicate()
	inv["core"] = 3
	inv["claw"] = 2
	rng.seed = 99
	var pack2: Array[String] = DeckRules.draft_pack(inv, rng, 5)
	if pack2.size() != 5:
		_fail("partial inv pack size %d" % pack2.size())
		return
	# Capacitance near full — still returns up to 5 (may include unaffordable rest)
	var fat := DeckRules.preset("default")
	rng.seed = 7
	var pack3: Array[String] = DeckRules.draft_pack(fat, rng, 5)
	if pack3.is_empty():
		_fail("near-full pack empty")
		return
	print("PASS: draft_pack core-guarantee + unique genes")

func _test_bay_flow_inventory() -> void:
	# Simulate P1 lock default, P2 rush — both must validate for match start.
	var p0 := DeckRules.preset("default")
	var p1 := DeckRules.preset("rush")
	var v0 := DeckRules.validate(p0)
	var v1 := DeckRules.validate(p1)
	if not bool(v0["ok"]) or not bool(v1["ok"]):
		_fail("bay hot-seat pair invalid p0=%s p1=%s" % [str(v0), str(v1)])
		return
	# Draft start: empty then pick cores until valid
	var draft := DeckRules.sanitized_copy({})
	if bool(DeckRules.validate(draft)["ok"]):
		_fail("empty draft should be invalid")
		return
	draft["core"] = 1
	if not bool(DeckRules.validate(draft)["ok"]):
		_fail("single core should validate")
		return
	print("PASS: bay lock pair + draft min valid")
