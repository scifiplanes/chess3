extends Node

## Async AI spectator loop for Demo mode.

const DemoAIScript = preload("res://src/sim/DemoAI.gd")
const GameStateScript = preload("res://src/sim/GameState.gd")
const ResolverScript = preload("res://src/sim/Resolver.gd")
const RulesScript = preload("res://src/sim/Rules.gd")
const MenuScene = preload("res://scenes/MenuFlow.tscn")
const DemoCommentaryScript = preload("res://src/presentation/DemoCommentary.gd")

const MAX_TURNS := 120

signal status_changed(text: String)
signal interstitial(show: bool, data: Dictionary)
signal match_started(index: int, seed: int, s0: String, s1: String)
signal commentary_appended(lines: Array)

var main: Node
var gs
var resolver := ResolverScript.new()
var rules := RulesScript.new()
var ai := DemoAIScript.new()

var paused: bool = false
var tempo: String = "normal"
var skip_turn_requested: bool = false
var exit_requested: bool = false
var _running: bool = false
var _interstitial_active: bool = false

func setup(p_main: Node, p_gs) -> void:
	main = p_main
	gs = p_gs
	tempo = GameSettings.demo_tempo
	if not _running:
		_running = true
		_loop()

func set_tempo(t: String) -> void:
	tempo = t
	GameSettings.demo_tempo = t

func request_skip_turn() -> void:
	skip_turn_requested = true

func request_pause(on: bool) -> void:
	paused = on

func request_exit_menu() -> void:
	exit_requested = true
	_running = false

func _delays() -> Dictionary:
	return GameSettings.tempo_delays(tempo)

func _loop() -> void:
	while _running and is_instance_valid(main):
		if exit_requested:
			# Main owns the scene change when Menu is pressed; bail if still here.
			_running = false
			return
		await _run_one_match()
		if exit_requested or not _running:
			_running = false
			return
		await _show_between_matches()
		if exit_requested or not _running:
			_running = false
			return

func _run_one_match() -> void:
	if gs == null:
		return
	var idx := MatchSession.demo_match_index + 1
	var s0 := DemoAIScript.style_name(MatchSession.style0)
	var s1 := DemoAIScript.style_name(MatchSession.style1)
	match_started.emit(idx, MatchSession.match_seed, s0, s1)
	status_changed.emit("DEMO · MATCH %03d · %s vs %s" % [idx, s0, s1])
	commentary_appended.emit([
		"> Match %03d · %s vs %s · seed %d" % [idx, s0, s1, MatchSession.match_seed]
	])

	var turns := 0
	while is_instance_valid(gs) and gs.winner == -1 and int(gs.turn_number) <= MAX_TURNS:
		if exit_requested:
			return
		while paused and not exit_requested:
			await get_tree().process_frame
		if exit_requested:
			return

		var ap := int(gs.active_player)
		var style := MatchSession.style0 if ap == 0 else MatchSession.style1
		var ptag := DemoCommentaryScript.player_tag(ap)
		var st := DemoAIScript.style_name(style)

		if bool(gs.offer_pending):
			_flush_commentary([
				"— T%d · %s (%s) · offer —" % [int(gs.turn_number), ptag, st]
			])
			ai.play_offer(gs, style)
			if bool(gs.offer_pending):
				gs.clear_offer_phase()
			if ai.commentary_lines.is_empty():
				_flush_commentary(["%s skips gene offer" % ptag])
			else:
				_flush_commentary([])
			_demo_frame_camera()
			await _wait_step("offer")
			if exit_requested:
				return

		if gs.winner != -1:
			break

		if skip_turn_requested:
			skip_turn_requested = false
			_flush_commentary(["%s turn skipped (spectator)" % ptag])
		else:
			_flush_commentary([
				"— T%d · %s (%s) · action —" % [int(gs.turn_number), ptag, st]
			])
			ai.play_actions(gs, style)
			if ai.commentary_lines.is_empty():
				_flush_commentary(["%s holds position" % ptag])
			else:
				_flush_commentary([])
			_demo_frame_camera()
			await _wait_step("action")
			if exit_requested:
				return

		if gs.winner != -1:
			break
		if not rules.can_end_turn(gs):
			break
		resolver.end_turn(gs)
		_flush_commentary(["%s ends turn" % ptag])
		await _wait_step("end_turn")
		turns += 1

func _show_between_matches() -> void:
	if gs == null:
		return
	_interstitial_active = true
	var reason := _win_reason()
	var winner := int(gs.winner)
	var data := {
		"winner": winner,
		"reason": reason,
		"match_index": MatchSession.demo_match_index + 1,
		"seed": MatchSession.match_seed,
		"s0": DemoAIScript.style_name(MatchSession.style0),
		"s1": DemoAIScript.style_name(MatchSession.style1),
	}
	interstitial.emit(true, data)
	var wtxt := "DRAW" if winner < 0 else "P%d" % (winner + 1)
	commentary_appended.emit(["> %s wins (%s)" % [wtxt, reason]])
	var d: Dictionary = _delays()
	var wait_s: float = float(d.get("between", 1.5))
	var t := 0.0
	while t < wait_s and not exit_requested:
		if paused:
			await get_tree().process_frame
			continue
		await get_tree().create_timer(0.1).timeout
		t += 0.1
	interstitial.emit(false, {})
	_interstitial_active = false
	if exit_requested:
		return
	MatchSession.next_demo_match()
	if main.has_method("restart_demo_match"):
		main.call("restart_demo_match")

func _flush_commentary(prefix_lines: Array = []) -> void:
	var out: Array[String] = []
	for line_any in prefix_lines:
		out.append(str(line_any))
	if ai.commentary_lines.size() > 0:
		out.append(str(ai.commentary_lines[ai.commentary_lines.size() - 1]))
	if out.is_empty():
		return
	commentary_appended.emit(out)

func _demo_frame_camera() -> void:
	if main == null or not is_instance_valid(main):
		return
	if main.has_method("demo_frame_camera"):
		main.call("demo_frame_camera", ai.last_focus_cells)

func _win_reason() -> String:
	if gs.winner == -1:
		return "timeout"
	var alive := {0: 0, 1: 0}
	for s_any in gs.squads.values():
		var s = s_any
		if s != null and s.is_alive():
			alive[int(s.owner)] = int(alive.get(int(s.owner), 0)) + 1
	if int(alive[0]) == 0 or int(alive[1]) == 0:
		return "elim"
	return "cp"

func _wait_step(kind: String) -> void:
	var d: Dictionary = _delays()
	var wait_s: float = float(d.get(kind, 0.5))
	var t := 0.0
	while t < wait_s:
		if exit_requested:
			return
		if skip_turn_requested and kind == "action":
			return
		if paused:
			await get_tree().process_frame
			continue
		await get_tree().create_timer(0.05).timeout
		t += 0.05
