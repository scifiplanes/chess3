extends SceneTree

## 30 full 1v1 matches played like two humans (offer → act → end turn).
## godot --headless --path . --script res://tools/playtest_30_matches.gd
## Prints PLAYTEST_30_MATCHES_OK on clean pass.

const GameStateScript = preload("res://src/sim/GameState.gd")
const ResolverScript = preload("res://src/sim/Resolver.gd")
const RulesScript = preload("res://src/sim/Rules.gd")
const UnitDefsScript = preload("res://src/sim/UnitDefs.gd")
const DemoAIScript = preload("res://src/sim/DemoAI.gd")

const MAX_TURNS := 120
const MATCH_COUNT := 30

var _rules = RulesScript.new()
var _resolver = ResolverScript.new()
var _demo_ai := DemoAIScript.new()

var _bugs: Array[String] = []
var _fails: Array[String] = []
var _notes: Array[String] = []
var _wins := {0: 0, 1: 0, "draw": 0}
var _win_by := {"elim": 0, "cp": 0, "timeout": 0}
var _organ_pops: int = 0
var _actions_used := {}
var _style_wins := {}

func _init() -> void:
	print("=== Chess 3 — 30 human-style 1v1 matches ===")
	# Full pair coverage (15 unordered pairs × 2 seats) — mirrors style RR so
	# floors aren't locked to one opponent (old i%6 schedule only tested 3 pairs).
	var pairs: Array = []
	for a in range(6):
		for b in range(a + 1, 6):
			pairs.append([a, b])
	var match_i := 0
	var pair_i := 0
	for pair_any in pairs:
		var pair: Array = pair_any
		for side in range(2):
			match_i += 1
			# Fair opener×style: old match_i*131 flipped seed parity on seat-swap, so the
			# higher-index style always opened. Keep parity fixed per pair; side*2 rotates
			# who sits in the opening seat. Alternate pair parity so P0/P1 both open ~half.
			# Same schedule as style RR.
			var seed := 9000 + pair_i * 262 + side * 2
			if (pair_i % 2) == 1:
				seed += 1
			var swap := side == 1
			var style0 := int(pair[1] if swap else pair[0])
			var style1 := int(pair[0] if swap else pair[1])
			_play_match(match_i, seed, style0, style1)
		pair_i += 1
	_report()
	if _fails.size() > 0 or _bugs.size() > 0:
		quit(1)
	else:
		print("PLAYTEST_30_MATCHES_OK")
		quit(0)

func _report() -> void:
	print("--- summary ---")
	print("wins P0=%d P1=%d draw/timeout=%d" % [int(_wins[0]), int(_wins[1]), int(_wins["draw"])])
	print("win_by elim=%d cp=%d timeout=%d" % [int(_win_by["elim"]), int(_win_by["cp"]), int(_win_by["timeout"])])
	print("organ_pops≈%d actions=%s" % [_organ_pops, str(_actions_used)])
	print("style_wins=%s" % str(_style_wins))
	print("notes=%d bugs=%d fails=%d" % [_notes.size(), _bugs.size(), _fails.size()])
	for n in _notes:
		print("NOTE: ", n)
	for b in _bugs:
		print("BUG: ", b)
	for f in _fails:
		print("FAIL: ", f)

func _bug(msg: String) -> void:
	_bugs.append(msg)
	print("BUG: ", msg)

func _fail(msg: String) -> void:
	_fails.append(msg)
	print("FAIL: ", msg)

func _note(msg: String) -> void:
	_notes.append(msg)
	print("NOTE: ", msg)

func _style_name(s: int) -> String:
	return DemoAIScript.style_name(s)

func _play_match(match_i: int, seed: int, style0: int, style1: int) -> void:
	var gs = GameStateScript.new()
	root.add_child(gs)
	gs.setup(GameStateScript.DEFAULT_BOARD_SIZE, seed)
	gs.apply_seed_first_player()
	# Snapshot start invariants
	if not bool(gs.offer_pending):
		_bug("M%d: match start without offer" % match_i)
	var expect_start := absi(int(seed)) % 2
	if int(gs.active_player) != expect_start:
		_bug("M%d: starter should be P%d (seed%%2), got P%d" % [match_i, expect_start, int(gs.active_player)])
	if gs.board == null or gs.board.control_points.is_empty():
		_bug("M%d: no CPs" % match_i)
		gs.queue_free()
		return

	var prev_alive := {0: 0, 1: 0}
	var stall := 0
	var last_hash := ""
	var turns_played := 0

	while gs.winner == -1 and int(gs.turn_number) <= MAX_TURNS:
		turns_played = int(gs.turn_number)
		var ap := int(gs.active_player)
		var style := style0 if ap == 0 else style1
		_assert_invariants(gs, match_i, "pre_offer")

		# Offer phase (human: spend playable genes, then skip).
		if bool(gs.offer_pending):
			_play_offer(gs, style, match_i)
		if bool(gs.offer_pending):
			gs.clear_offer_phase()

		_assert_invariants(gs, match_i, "pre_act")
		_play_actions(gs, style, match_i)
		_assert_invariants(gs, match_i, "pre_end")

		if gs.winner != -1:
			break
		if not _rules.can_end_turn(gs):
			_bug("M%d T%d: cannot end turn (offer_pending=%s)" % [match_i, gs.turn_number, str(gs.offer_pending)])
			break

		var before_player := int(gs.active_player)
		var before_turn := int(gs.turn_number)
		_resolver.end_turn(gs)
		if gs.winner == -1:
			if int(gs.active_player) == before_player:
				_bug("M%d T%d: end_turn did not switch player" % [match_i, before_turn])
				break
			if int(gs.turn_number) != before_turn + 1:
				_bug("M%d: turn did not increment (%d→%d)" % [match_i, before_turn, gs.turn_number])
				break
			if not bool(gs.offer_pending):
				_bug("M%d T%d: no offer after end_turn" % [match_i, gs.turn_number])
				break

		# Stall detection (same board occupancy hash).
		var h := _board_hash(gs)
		if h == last_hash:
			stall += 1
		else:
			stall = 0
			last_hash = h
		if stall >= 24:
			_note("M%d: stall detected at T%d — forcing timeout" % [match_i, gs.turn_number])
			break

		# Soft progress track
		var alive := _alive_counts(gs)
		prev_alive = alive

	# Resolve outcome
	var reason := "timeout"
	if gs.winner != -1:
		reason = _win_reason(gs)
		_wins[int(gs.winner)] = int(_wins.get(int(gs.winner), 0)) + 1
		_win_by[reason] = int(_win_by.get(reason, 0)) + 1
		var wstyle := style0 if int(gs.winner) == 0 else style1
		var sn := _style_name(wstyle)
		_style_wins[sn] = int(_style_wins.get(sn, 0)) + 1
		print("MATCH %02d seed=%d styles=%s vs %s → P%d by %s T=%d" % [
			match_i, seed, _style_name(style0), _style_name(style1), int(gs.winner), reason, turns_played
		])
	else:
		_wins["draw"] = int(_wins["draw"]) + 1
		_win_by["timeout"] = int(_win_by["timeout"]) + 1
		print("MATCH %02d seed=%d styles=%s vs %s → DRAW/TIMEOUT T=%d" % [
			match_i, seed, _style_name(style0), _style_name(style1), turns_played
		])

	# Final invariants + snapshot roundtrip
	_assert_invariants(gs, match_i, "final")
	_check_snapshot(gs, match_i)
	gs.queue_free()

func _win_reason(gs) -> String:
	var alive := _alive_counts(gs)
	if int(alive[0]) == 0 or int(alive[1]) == 0:
		return "elim"
	return "cp"

func _alive_counts(gs) -> Dictionary:
	var a := {0: 0, 1: 0}
	for s_any in gs.squads.values():
		var s = s_any
		if s != null and s.is_alive():
			a[int(s.owner)] = int(a.get(int(s.owner), 0)) + 1
	return a

func _board_hash(gs) -> String:
	var parts: Array[String] = []
	var ids: Array = gs.squads.keys()
	ids.sort()
	for sid in ids:
		var s = gs.get_squad(int(sid))
		if s == null or not s.is_alive():
			continue
		parts.append("%d:%d,%d:%d" % [int(s.id), int(s.cell.x), int(s.cell.y), int(s.unit_count_alive())])
	for cp in gs.board.control_points:
		parts.append("cp%d:%d" % [int(cp.cell.x) * 100 + int(cp.cell.y), int(cp.owner)])
	return "|".join(parts)

func _assert_invariants(gs, match_i: int, tag: String) -> void:
	# One mutant per cell
	var occ := {}
	for s_any in gs.squads.values():
		var s = s_any
		if s == null or not s.is_alive():
			continue
		var k := "%d,%d" % [s.cell.x, s.cell.y]
		if occ.has(k):
			_bug("M%d %s: two mutants on %s" % [match_i, tag, k])
		occ[k] = true
		# Organs locked outside pool
		if not _rules.is_spawn_pool_cell(gs, s.cell, int(s.owner)):
			if not bool(s.organs_locked):
				_bug("M%d %s: unlocked organs outside pool sid=%d cell=%s" % [match_i, tag, s.id, str(s.cell)])
		# Hard max
		if int(s.unit_count_alive()) > RulesScript.ORGAN_HARD_MAX:
			_bug("M%d %s: organ hard max exceeded sid=%d n=%d" % [match_i, tag, s.id, s.unit_count_alive()])
		# Cooldown non-negative
		for ck in s.cooldowns.keys():
			if int(s.cooldowns[ck]) < 0:
				_bug("M%d %s: negative cooldown %s" % [match_i, tag, str(ck)])
		# Core-at-back soft preference after attach is not enforced mid-fight; skip.
	# Inventory non-negative
	for p in [0, 1]:
		var inv: Dictionary = gs.player_inventory.get(p, {})
		for k in inv.keys():
			if int(inv[k]) < 0:
				_bug("M%d %s: negative inventory P%d %s" % [match_i, tag, p, str(k)])
	# Offer cards subset of known defs when pending
	if bool(gs.offer_pending):
		for c in gs.offer_cards:
			if not UnitDefsScript.DEFS.has(str(c)):
				_bug("M%d %s: unknown offer card %s" % [match_i, tag, str(c)])

func _check_snapshot(gs, match_i: int) -> void:
	var snap = gs.snapshot_dict()
	var gs2 = GameStateScript.new()
	root.add_child(gs2)
	gs2.apply_snapshot_dict(snap)
	if int(gs2.winner) != int(gs.winner):
		_bug("M%d: snapshot winner mismatch" % match_i)
	if int(gs2.turn_number) != int(gs.turn_number):
		_bug("M%d: snapshot turn mismatch" % match_i)
	if int(gs2.active_player) != int(gs.active_player):
		_bug("M%d: snapshot active_player mismatch" % match_i)
	if bool(gs2.offer_pending) != bool(gs.offer_pending):
		_bug("M%d: snapshot offer_pending mismatch" % match_i)
	# hero_props preserved
	if gs.board.hero_props.size() != gs2.board.hero_props.size():
		_bug("M%d: snapshot hero_props size %d→%d" % [match_i, gs.board.hero_props.size(), gs2.board.hero_props.size()])
	var a0 := _alive_counts(gs)
	var a1 := _alive_counts(gs2)
	if int(a0[0]) != int(a1[0]) or int(a0[1]) != int(a1[1]):
		_bug("M%d: snapshot alive counts mismatch %s vs %s" % [match_i, str(a0), str(a1)])
	gs2.queue_free()

# --- Demo AI (shared with spectator demo) ---

func _play_offer(gs, style: int, _match_i: int) -> void:
	_demo_ai.play_offer(gs, style)

func _play_actions(gs, style: int, _match_i: int) -> void:
	var pops_before := _demo_ai.organ_pops
	_demo_ai.play_actions(gs, style)
	_organ_pops += _demo_ai.organ_pops - pops_before
