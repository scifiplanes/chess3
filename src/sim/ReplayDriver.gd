extends RefCounted
class_name ReplayDriver

const GameStateScript = preload("res://src/sim/GameState.gd")
const ResolverScript = preload("res://src/sim/Resolver.gd")

func load_snapshot_from_json_text(json_text: String):
	var parsed = JSON.parse_string(json_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	var gs = GameStateScript.new()
	gs.apply_snapshot_dict(parsed as Dictionary)
	return gs

func apply_intents(gs, intents: Array) -> void:
	if gs == null:
		return
	var resolver = ResolverScript.new()
	for intent_any in intents:
		if typeof(intent_any) != TYPE_DICTIONARY:
			continue
		_apply_intent(gs, resolver, intent_any as Dictionary)

func _arr_to_cell(a) -> Vector2i:
	if a is Array and a.size() >= 2:
		return Vector2i(int(a[0]), int(a[1]))
	return Vector2i(0, 0)

func _apply_intent(gs, resolver, intent: Dictionary) -> void:
	var t := str(intent.get("type", ""))
	match t:
		"move":
			resolver.move_squad(gs, int(intent.get("squad_id", -1)), _arr_to_cell(intent.get("to", [0, 0])))
		"attack":
			resolver.attack(gs, int(intent.get("attacker_id", -1)), int(intent.get("defender_id", -1)), str(intent.get("action_id", "")))
		"attack_obstacle":
			resolver.attack_obstacle(gs, int(intent.get("attacker_id", -1)), _arr_to_cell(intent.get("cell", [0, 0])), str(intent.get("action_id", "")))
		"end_turn":
			resolver.end_turn(gs)
		"play_card":
			var mode := str(intent.get("mode", "spawn"))
			var unit_def_id := str(intent.get("unit_def_id", ""))
			if mode == "reinforce":
				resolver.play_card_reinforce(gs, unit_def_id, int(intent.get("squad_id", -1)))
			else:
				resolver.play_card_spawn(gs, unit_def_id, _arr_to_cell(intent.get("cell", [0, 0])))
		"run":
			resolver.use_run(gs, int(intent.get("squad_id", -1)), _arr_to_cell(intent.get("to", [0, 0])))
		"jump":
			resolver.use_jump(gs, int(intent.get("squad_id", -1)), _arr_to_cell(intent.get("to", [0, 0])))
		"blink":
			resolver.use_blink(gs, int(intent.get("squad_id", -1)), _arr_to_cell(intent.get("to", [0, 0])))
		"dash":
			resolver.use_dash(gs, int(intent.get("squad_id", -1)), _arr_to_cell(intent.get("to", [0, 0])))
		"pounce":
			resolver.use_pounce(gs, int(intent.get("squad_id", -1)), _arr_to_cell(intent.get("to", [0, 0])))
		"charge":
			resolver.use_charge(gs, int(intent.get("attacker_id", -1)), int(intent.get("defender_id", -1)))
		"railgun":
			resolver.use_railgun(gs, int(intent.get("attacker_id", -1)), int(intent.get("defender_id", -1)))
		"slam":
			resolver.use_slam(gs, int(intent.get("squad_id", -1)))
		"delayed":
			resolver.schedule_delayed_strike(gs, int(intent.get("squad_id", -1)), str(intent.get("action_id", "")), _arr_to_cell(intent.get("cell", [0, 0])))
		"plant":
			resolver.plant_hazard(gs, int(intent.get("squad_id", -1)), _arr_to_cell(intent.get("cell", [0, 0])), str(intent.get("action_id", "mine")))
		"switch":
			resolver.switch_squads(gs, int(intent.get("caster_id", -1)), int(intent.get("squad_a", -1)), int(intent.get("squad_b", -1)))
		_:
			pass

