extends SceneTree

## Round-robin style tournament: every AI style vs every other (both sides).
## godot --headless --path . --script res://tools/playtest_style_roundrobin.gd

const GameStateScript = preload("res://src/sim/GameState.gd")
const ResolverScript = preload("res://src/sim/Resolver.gd")
const RulesScript = preload("res://src/sim/Rules.gd")
const DemoAIScript = preload("res://src/sim/DemoAI.gd")

const STYLE_COUNT := 6
const GAMES_PER_PAIR := 2 # swap sides
const MAX_TURNS := 120
const BASE_SEED := 9000

var _rules = RulesScript.new()
var _resolver = ResolverScript.new()
var _demo_ai = DemoAIScript.new()

var _matrix: Dictionary = {} # "a|b" -> {a: wins, b: wins, draw: n}
var _style_wins: Dictionary = {}
var _win_by := {"elim": 0, "cp": 0, "timeout": 0}
var _bugs: Array[String] = []

func _init() -> void:
	print("=== Chess 3 — style round-robin (%d styles, %d games/pair) ===" % [
		STYLE_COUNT, GAMES_PER_PAIR
	])
	for s in range(STYLE_COUNT):
		_style_wins[_style_name(s)] = 0

	var game_i := 0
	var pair_i := 0
	for a in range(STYLE_COUNT):
		for b in range(a + 1, STYLE_COUNT):
			for g in range(GAMES_PER_PAIR):
				game_i += 1
				var swap := g % 2 == 1
				var p0 := b if swap else a
				var p1 := a if swap else b
				# Match playtest_30_matches: fixed parity per pair so seat-swap rotates
				# opener across styles (old game_i*131 made higher-index style always open).
				var seed := BASE_SEED + pair_i * 262 + g * 2
				if (pair_i % 2) == 1:
					seed += 1
				_run_game(game_i, seed, p0, p1)
			pair_i += 1

	_print_matrix()
	_print_totals()
	_check_meta_gates()
	if _bugs.size() > 0:
		for b in _bugs:
			print("BUG: ", b)
		print("PLAYTEST_STYLE_ROUNDROBIN_FAIL")
		quit(1)
	else:
		print("PLAYTEST_STYLE_ROUNDROBIN_OK")
		quit(0)

func _style_name(s: int) -> String:
	return DemoAIScript.style_name(s)

func _matrix_key(a: int, b: int) -> String:
	var lo := mini(a, b)
	var hi := maxi(a, b)
	return "%d|%d" % [lo, hi]

func _run_game(game_i: int, seed: int, style0: int, style1: int) -> void:
	var gs = GameStateScript.new()
	root.add_child(gs)
	gs.setup(GameStateScript.DEFAULT_BOARD_SIZE, seed)
	gs.apply_seed_first_player()

	var stall := 0
	var last_hash := ""
	var turns := 0

	while gs.winner == -1 and int(gs.turn_number) <= MAX_TURNS:
		turns = int(gs.turn_number)
		var ap := int(gs.active_player)
		var style := style0 if ap == 0 else style1
		if bool(gs.offer_pending):
			_demo_ai.play_offer(gs, style)
		if bool(gs.offer_pending):
			gs.clear_offer_phase()
		_demo_ai.play_actions(gs, style)
		if gs.winner != -1:
			break
		if not _rules.can_end_turn(gs):
			_bug("G%d: cannot end turn T%d" % [game_i, gs.turn_number])
			break
		var before_p := int(gs.active_player)
		var before_t := int(gs.turn_number)
		_resolver.end_turn(gs)
		if gs.winner == -1:
			if int(gs.active_player) == before_p:
				_bug("G%d: end_turn stuck on P%d" % [game_i, before_p])
				break
			if int(gs.turn_number) != before_t + 1:
				_bug("G%d: turn skip %d→%d" % [game_i, before_t, gs.turn_number])
				break
		var h := _board_hash(gs)
		if h == last_hash:
			stall += 1
		else:
			stall = 0
			last_hash = h
		if stall >= 24:
			break

	var reason := "timeout"
	if gs.winner != -1:
		reason = _win_reason(gs)
		_win_by[reason] = int(_win_by.get(reason, 0)) + 1
		var wstyle := style0 if int(gs.winner) == 0 else style1
		var wname := _style_name(wstyle)
		_style_wins[wname] = int(_style_wins.get(wname, 0)) + 1
		_record_pair(style0, style1, int(gs.winner))
		print("G%03d %s vs %s seed=%d → %s by %s T=%d" % [
			game_i, _style_name(style0), _style_name(style1), seed,
			_style_name(wstyle), reason, turns
		])
	else:
		_win_by["timeout"] = int(_win_by.get("timeout", 0)) + 1
		_record_pair(style0, style1, -1)
		print("G%03d %s vs %s seed=%d → DRAW T=%d" % [
			game_i, _style_name(style0), _style_name(style1), seed, turns
		])
	gs.queue_free()

func _win_reason(gs) -> String:
	var alive := {0: 0, 1: 0}
	for s_any in gs.squads.values():
		var s = s_any
		if s != null and s.is_alive():
			alive[int(s.owner)] = int(alive.get(int(s.owner), 0)) + 1
	if int(alive[0]) == 0 or int(alive[1]) == 0:
		return "elim"
	return "cp"

func _record_pair(p0_style: int, p1_style: int, winner: int) -> void:
	var k := _matrix_key(p0_style, p1_style)
	if not _matrix.has(k):
		_matrix[k] = {"draw": 0}
		for sid in [p0_style, p1_style]:
			_matrix[k][str(sid)] = int(_matrix[k].get(str(sid), 0))
	var rec: Dictionary = _matrix[k]
	if winner == -1:
		rec["draw"] = int(rec.get("draw", 0)) + 1
	elif winner == 0:
		var key := str(p0_style)
		rec[key] = int(rec.get(key, 0)) + 1
	else:
		var key2 := str(p1_style)
		rec[key2] = int(rec.get(key2, 0)) + 1
	_matrix[k] = rec

func _board_hash(gs) -> String:
	var parts: Array[String] = []
	var ids: Array = gs.squads.keys()
	ids.sort()
	for sid in ids:
		var s = gs.get_squad(int(sid))
		if s == null or not s.is_alive():
			continue
		parts.append("%d:%d,%d" % [int(s.id), int(s.cell.x), int(s.cell.y)])
	return "|".join(parts)

func _print_matrix() -> void:
	print("--- head-to-head (wins for row style vs col style) ---")
	var names: Array[String] = []
	for i in range(STYLE_COUNT):
		names.append(_style_name(i))
	# Header
	var hdr := "          "
	for n in names:
		hdr += "%8s" % n.substr(0, 7)
	print(hdr)
	for row in range(STYLE_COUNT):
		var line := "%8s" % names[row].substr(0, 7)
		for col in range(STYLE_COUNT):
			if row == col:
				line += "%8s" % "—"
				continue
			var k := _matrix_key(row, col)
			var rec: Dictionary = _matrix.get(k, {})
			var wins := int(rec.get(str(row), 0))
			line += "%8d" % wins
		print(line)

func _print_totals() -> void:
	print("--- totals ---")
	print("style_wins=%s" % str(_style_wins))
	print("win_by elim=%d cp=%d timeout=%d" % [
		int(_win_by.get("elim", 0)), int(_win_by.get("cp", 0)), int(_win_by.get("timeout", 0))
	])
	var total_games := STYLE_COUNT * (STYLE_COUNT - 1) / 2 * GAMES_PER_PAIR
	print("games=%d (expect %d)" % [int(_win_by["elim"]) + int(_win_by["cp"]) + int(_win_by["timeout"]), total_games])

func _bug(msg: String) -> void:
	_bugs.append(msg)
	print("BUG: ", msg)

func _check_meta_gates() -> void:
	var max_wins := 0
	for k in _style_wins.keys():
		max_wins = maxi(max_wins, int(_style_wins.get(k, 0)))
	if max_wins > 12:
		_bug("meta: top style wins %d > 12 (40%% cap)" % max_wins)
	var kite := int(_style_wins.get("kite", 0))
	if kite < 3:
		_bug("meta: kite wins %d < 3" % kite)
	var control := int(_style_wins.get("control", 0))
	if control < 4:
		_bug("meta: control wins %d < 4" % control)
	var balanced := int(_style_wins.get("balanced", 0))
	if balanced > 6:
		_bug("meta: balanced wins %d > 6" % balanced)
	var cp := int(_win_by.get("cp", 0))
	if cp > 18:
		_bug("meta: cp wins %d > 18" % cp)
	if cp < 8:
		_bug("meta: cp wins %d < 8 (elim bloodbath)" % cp)
	var swarm := int(_style_wins.get("swarm", 0))
	if swarm > 9:
		_bug("meta: swarm wins %d > 9" % swarm)
	var rush := int(_style_wins.get("rush", 0))
	if rush < 3:
		_bug("meta: rush wins %d < 3" % rush)
	if rush > 6:
		_bug("meta: rush wins %d > 6 (soft-cap)" % rush)
	var tank := int(_style_wins.get("tank", 0))
	if tank < 3:
		_bug("meta: tank wins %d < 3" % tank)
