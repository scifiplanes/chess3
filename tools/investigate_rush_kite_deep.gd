extends SceneTree

const GameStateScript = preload("res://src/sim/GameState.gd")
const ResolverScript = preload("res://src/sim/Resolver.gd")
const RulesScript = preload("res://src/sim/Rules.gd")
const DemoAIScript = preload("res://src/sim/DemoAI.gd")

const MAX_TURNS := 120
const BASE_SEED := 9000

var _rules = RulesScript.new()
var _resolver = ResolverScript.new()

func _init() -> void:
	print("=== rush/kite deep trace (round-robin seeds) ===\n")
	var game_i := 0
	for a in range(6):
		for b in range(a + 1, 6):
			for g in range(2):
				game_i += 1
				var swap := g % 2 == 1
				var s0 := b if swap else a
				var s1 := a if swap else b
				if s0 != 0 and s0 != 1 and s1 != 0 and s1 != 1:
					continue
				var seed := BASE_SEED + game_i * 131
				_trace(game_i, seed, s0, s1)
	quit(0)

func _trace(game_i: int, seed: int, s0: int, s1: int) -> void:
	var gs = GameStateScript.new()
	root.add_child(gs)
	gs.setup(GameStateScript.DEFAULT_BOARD_SIZE, seed)
	var ai = DemoAIScript.new()

	var stats := {
		0: _new_side(), 1: _new_side(),
	}
	var first_ranged := {0: -1, 1: -1}
	var first_cp_zone := {0: -1, 1: -1}
	var first_contact := -1

	while gs.winner == -1 and int(gs.turn_number) <= MAX_TURNS:
		var ap := int(gs.active_player)
		var style := s0 if ap == 0 else s1
		var st: Dictionary = stats[ap]

		if bool(gs.offer_pending):
			var organs_before := _max_org(ap, gs)
			ai.play_offer(gs, style)
			if not bool(gs.offer_pending):
				if _max_org(ap, gs) > organs_before:
					st.attach_turns += 1
		if bool(gs.offer_pending):
			gs.clear_offer_phase()

		for sid_any in gs.squads.keys():
			var s = gs.get_squad(int(sid_any))
			if s == null or not s.is_alive():
				continue
			var p := int(s.owner)
			var pst: Dictionary = stats[p]
			pst.max_org = maxi(pst.max_org, int(s.unit_count_alive()))
			if pst.pool_exit < 0 and not _rules.is_spawn_pool_cell(gs, s.cell, p):
				pst.pool_exit = int(gs.turn_number)
			if int(s.fresh_turn) == int(gs.turn_number) and p == ap:
				pst.fresh_skips += 1
			if first_cp_zone[p] < 0 and _in_any_cp_zone(gs, s.cell):
				first_cp_zone[p] = int(gs.turn_number)

		var dist_before := _min_dist(gs)
		var cd_before := _snapshot_cooldowns(gs, ap)

		ai.play_actions(gs, style)

		_tally_attacks(cd_before, gs, ap, st)

		var dist_after := _min_dist(gs)
		if first_contact < 0 and dist_before > 4 and dist_after >= 0 and dist_after <= 4:
			first_contact = int(gs.turn_number)
		if first_ranged[ap] < 0 and st.ranged_shots > 0:
			first_ranged[ap] = int(gs.turn_number)

		if not _rules.can_end_turn(gs):
			break
		_resolver.end_turn(gs)

	var winner := int(gs.winner)
	var reason := "timeout"
	if winner >= 0:
		reason = "elim" if _one_dead(gs) else "cp"

	var n0 := DemoAIScript.style_name(s0)
	var n1 := DemoAIScript.style_name(s1)
	print("G%03d %s vs %s seed=%d → P%d %s T=%d" % [
		game_i, n0, n1, seed, winner, reason, int(gs.turn_number)
	])
	for p in [0, 1]:
		var st: Dictionary = stats[p]
		var sn := DemoAIScript.style_name(s0 if p == 0 else s1)
		print("  P%d(%s): pool=T%s org=%d fresh=%d ranged=%d(T%s) melee=%d cp_zone=T%s cp_flags=%d" % [
			p, sn,
			str(st.pool_exit), st.max_org, st.fresh_skips,
			st.ranged_shots, str(first_ranged[p]),
			st.melee_shots,
			str(first_cp_zone[p]),
			_cp_flags_held(gs, p),
		])
	print("  contact(T<=4)=%s final_dist=%d" % [str(first_contact), _min_dist(gs)])
	gs.queue_free()

func _new_side() -> Dictionary:
	return {
		"pool_exit": -1,
		"max_org": 0,
		"fresh_skips": 0,
		"attach_turns": 0,
		"ranged_shots": 0,
		"melee_shots": 0,
	}

func _max_org(p: int, gs) -> int:
	var m := 0
	for s in gs.squads.values():
		if s != null and s.is_alive() and int(s.owner) == p:
			m = maxi(m, int(s.unit_count_alive()))
	return m

func _min_dist(gs) -> int:
	var best := 9999
	for a in gs.squads.values():
		if a == null or not a.is_alive():
			continue
		for b in gs.squads.values():
			if b == null or not b.is_alive() or int(b.owner) == int(a.owner):
				continue
			best = mini(best, absi(a.cell.x - b.cell.x) + absi(a.cell.y - b.cell.y))
	return best if best < 9999 else -1

func _in_any_cp_zone(gs, cell: Vector2i) -> bool:
	for cp in gs.board.control_points:
		if absi(cell.x - cp.cell.x) + absi(cell.y - cp.cell.y) <= 1:
			return true
	return false

func _cp_flags_held(gs, p: int) -> int:
	var n := 0
	for cp in gs.board.control_points:
		n += int(cp.flags_for(p))
	return n

func _one_dead(gs) -> bool:
	var c := {0: 0, 1: 0}
	for s in gs.squads.values():
		if s != null and s.is_alive():
			c[int(s.owner)] += 1
	return c[0] == 0 or c[1] == 0

func _snapshot_cooldowns(gs, ap: int) -> Dictionary:
	var out := {}
	for s in gs.squads.values():
		if s == null or not s.is_alive() or int(s.owner) != ap:
			continue
		out[int(s.id)] = {"ranged": int(s.cooldowns.get("ranged", 0)), "melee": int(s.cooldowns.get("melee", 0))}
	return out

func _tally_attacks(before: Dictionary, gs, ap: int, st: Dictionary) -> void:
	for s in gs.squads.values():
		if s == null or not s.is_alive() or int(s.owner) != ap:
			continue
		var sid := int(s.id)
		if not before.has(sid):
			continue
		var b: Dictionary = before[sid]
		if int(s.cooldowns.get("ranged", 0)) > int(b.get("ranged", 0)):
			st.ranged_shots += 1
		if int(s.cooldowns.get("melee", 0)) > int(b.get("melee", 0)):
			st.melee_shots += 1
