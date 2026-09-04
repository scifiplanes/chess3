extends SceneTree

const GameStateScript = preload("res://src/sim/GameState.gd")
const ResolverScript = preload("res://src/sim/Resolver.gd")
const RulesScript = preload("res://src/sim/Rules.gd")
const DemoAIScript = preload("res://src/sim/DemoAI.gd")

const MAX_TURNS := 120

var _rules = RulesScript.new()
var _resolver = ResolverScript.new()
var _gs = null

func _init() -> void:
	var cases := [
		[9393, 0, 2, "rush(P0) vs control — rush loses"],
		[10441, 1, 2, "kite(P0) vs control — kite loses"],
		[11227, 1, 5, "kite(P0) vs balanced — kite wins"],
		[10048, 4, 0, "swarm(P0) vs rush — swarm wins"],
		[9655, 0, 3, "rush(P0) vs tank — rush wins fast"],
	]
	for c in cases:
		_analyze(int(c[0]), int(c[1]), int(c[2]), str(c[3]))
	quit(0)

func _analyze(seed: int, s0: int, s1: int, label: String) -> void:
	print("\n=== %s seed=%d ===" % [label, seed])
	_gs = GameStateScript.new()
	root.add_child(_gs)
	_gs.setup(GameStateScript.DEFAULT_BOARD_SIZE, seed)
	var ai = DemoAIScript.new()

	var exit_pool := {-1: -1, 0: -1, 1: -1}
	var fresh_skips := {0: 0, 1: 0}
	var max_org := {0: 0, 1: 0}
	var first_ranged := {0: -1, 1: -1}
	var first_contact := -1
	var cp_own := {0: 0, 1: 0}

	while _gs.winner == -1 and int(_gs.turn_number) <= MAX_TURNS:
		var ap := int(_gs.active_player)
		var style := s0 if ap == 0 else s1

		for p in [0, 1]:
			max_org[p] = maxi(max_org[p], _max_organs(p))

		if bool(_gs.offer_pending):
			ai.play_offer(_gs, style)
		if bool(_gs.offer_pending):
			_gs.clear_offer_phase()

		for sid_any in _gs.squads.keys():
			var s = _gs.get_squad(int(sid_any))
			if s == null or not s.is_alive():
				continue
			var p := int(s.owner)
			if exit_pool[p] < 0 and not _rules.is_spawn_pool_cell(_gs, s.cell, p):
				exit_pool[p] = int(_gs.turn_number)
			if int(s.fresh_turn) == int(_gs.turn_number) and int(s.owner) == ap:
				fresh_skips[ap] += 1

		var dist_before := _min_enemy_dist()
		ai.play_actions(_gs, style)
		var dist_after := _min_enemy_dist()
		if first_contact < 0 and dist_before > 0 and dist_after >= 0 and dist_after <= 4:
			first_contact = int(_gs.turn_number)
		for p in [0, 1]:
			if first_ranged[p] < 0 and _had_ranged_cd_tick(p):
				pass

		if not _rules.can_end_turn(_gs):
			break
		_resolver.end_turn(_gs)
		for cp in _gs.board.control_points:
			if int(cp.owner) == 0:
				cp_own[0] += 1
			elif int(cp.owner) == 1:
				cp_own[1] += 1

	var reason := "timeout"
	if _gs.winner != -1:
		reason = "elim" if _one_side_dead() else "cp"

	print("  → P%d by %s T=%d" % [int(_gs.winner), reason, int(_gs.turn_number)])
	print("  pool_exit turn P0=%s P1=%s" % [str(exit_pool[0]), str(exit_pool[1])])
	print("  max_organs P0=%d P1=%d" % [max_org[0], max_org[1]])
	print("  fresh_action_skips P0=%d P1=%d" % [fresh_skips[0], fresh_skips[1]])
	print("  first_contact_dist<=4 turn=%s" % str(first_contact))
	print("  final CP ownership score P0=%d P1=%d (higher=more captures)" % [cp_own[0], cp_own[1]])
	print("  final dist=%d locked=%s/%s" % [
		_min_enemy_dist(),
		str(_any_locked(0)), str(_any_locked(1))
	])
	_gs.queue_free()
	_gs = null

func _max_organs(p: int) -> int:
	var m := 0
	for s in _gs.squads.values():
		if s != null and s.is_alive() and int(s.owner) == p:
			m = maxi(m, int(s.unit_count_alive()))
	return m

func _min_enemy_dist() -> int:
	var best := 9999
	for a in _gs.squads.values():
		if a == null or not a.is_alive():
			continue
		for b in _gs.squads.values():
			if b == null or not b.is_alive() or int(b.owner) == int(a.owner):
				continue
			var d: int = absi(a.cell.x - b.cell.x) + absi(a.cell.y - b.cell.y)
			best = mini(best, d)
	return best if best < 9999 else -1

func _one_side_dead() -> bool:
	var a := {0: 0, 1: 0}
	for s in _gs.squads.values():
		if s != null and s.is_alive():
			a[int(s.owner)] += 1
	return a[0] == 0 or a[1] == 0

func _any_locked(p: int) -> bool:
	for s in _gs.squads.values():
		if s != null and s.is_alive() and int(s.owner) == p:
			return bool(s.organs_locked)
	return false

func _had_ranged_cd_tick(_p: int) -> bool:
	return false
