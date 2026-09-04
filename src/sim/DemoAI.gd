extends RefCounted
class_name DemoAI

## Human-style AI for demo spectator loop (from playtest_30_matches).

const GameStateScript = preload("res://src/sim/GameState.gd")
const ResolverScript = preload("res://src/sim/Resolver.gd")
const RulesScript = preload("res://src/sim/Rules.gd")
const UnitDefsScript = preload("res://src/sim/UnitDefs.gd")
const PathfindingScript = preload("res://src/sim/Pathfinding.gd")
const BoardStateScript = preload("res://src/sim/BoardState.gd")
const DemoCommentaryScript = preload("res://src/presentation/DemoCommentary.gd")

const PICKUP_DETOUR_RANGE := 8

var rules := RulesScript.new()
var resolver := ResolverScript.new()
var path := PathfindingScript.new()
var organ_pops: int = 0
var last_focus_cells: Array[Vector2i] = []
var commentary_lines: Array[String] = []

func _begin_commentary() -> void:
	commentary_lines.clear()
	last_focus_cells.clear()

func _log(text: String) -> void:
	commentary_lines.append(text)

func _player_tag(gs) -> String:
	return DemoCommentaryScript.player_tag(int(gs.active_player))

func _set_focus(cell: Vector2i) -> void:
	last_focus_cells = [cell]

func _set_focus_pair(a: Vector2i, b: Vector2i) -> void:
	last_focus_cells = [a, b]

static func style_name(s: int) -> String:
	match s:
		0: return "rush"
		1: return "kite"
		2: return "control"
		3: return "tank"
		4: return "swarm"
		_: return "balanced"

func play_offer(gs, style: int) -> void:
	_begin_commentary()
	_play_offer(gs, style)

func play_actions(gs, style: int) -> void:
	_begin_commentary()
	_play_actions(gs, style)

# --- Human-like offer ---

func _offer_index_for(gs, gene: String) -> int:
	for i in range(gs.offer_cards.size()):
		if str(gs.offer_cards[i]) == gene:
			return i
	return -1

func _offer_is_mutant_at(gs, index: int) -> bool:
	if index >= 0 and index < gs.offer_mutants.size():
		return bool(gs.offer_mutants[index])
	return false

func _play_offer_spawn(gs, gene: String, cell: Vector2i) -> void:
	var idx := _offer_index_for(gs, gene)
	var mut := _offer_is_mutant_at(gs, idx)
	_set_focus(cell)
	resolver.play_card_spawn(gs, gene, cell, mut, idx)
	_log(DemoCommentaryScript.spawn_line(int(gs.active_player), gene, mut))

func _play_offer_reinforce(gs, gene: String, squad_id: int) -> void:
	var idx := _offer_index_for(gs, gene)
	var mut := _offer_is_mutant_at(gs, idx)
	var s = gs.get_squad(squad_id)
	if s != null:
		_set_focus(s.cell)
	resolver.play_card_reinforce(gs, gene, squad_id, mut, idx)
	if s != null:
		_log(DemoCommentaryScript.attach_line(int(gs.active_player), gene, mut, int(s.id)))

func _play_offer(gs, style: int) -> void:
	# Play genes until offer closes (1 pick normally; 2 of 5 on turn 1).
	var guard := 0
	while bool(gs.offer_pending) and guard < 8:
		guard += 1
		gs.prune_unplayable_offer_cards()
		if gs.offer_cards.is_empty():
			gs.clear_offer_phase()
			return
		var played := false
		# Control: get bodies onto the board first, then stack snares/soak.
		if style == 2 and _count_owned(gs, int(gs.active_player)) < 2:
			played = _try_spawn(gs, style)
			if not played:
				played = _try_attach(gs, style)
		elif style == 3 or style == 1 or style == 0 or style == 5 or style == 2 or style == 4:
			played = _try_attach(gs, style)
		if not played:
			played = _try_spawn(gs, style)
		if not played:
			gs.clear_offer_phase()
			return

func _gene_priority(style: int) -> Array[String]:
	match style:
		0: # rush — charge tools first, then chip while closing
			return ["ram", "claw", "hoof", "spring", "leap", "eye", "core", "shell"]
		1: # kite — stack eyes first; hoof/phase for kiting
			return ["eye", "eye", "eye", "hoof", "hoof", "phase", "core", "claw"]
		3: # tank — plate soak, claw peel, shell slam, hold
			return ["plate", "plate", "plate", "claw", "shell", "chunk", "core", "ram", "hoof", "gland"]
		2: # control — dual snare + claw peel for CP pressure
			return ["gland", "gland", "claw", "plate", "shell", "core", "hoof", "eye"]
		4: # swarm — spawn many, prefer cheap cores/hoofs
			return ["core", "hoof", "claw", "eye", "gland", "shell"]
		_:
			return ["core", "claw", "eye", "hoof", "shell", "gland"]

func _try_spawn(gs, style: int) -> bool:
	var prio := _gene_priority(style)
	var cells = rules.spawn_cells(gs, int(gs.active_player))
	if cells.is_empty():
		return false
	# Prefer central-ish spawn cells for rush/control; edges for swarm.
	cells.sort_custom(func(a, b):
		var cx := int(gs.board.size.x) / 2
		var da := absi(a.x - cx)
		var db := absi(b.x - cx)
		if style == 4:
			return da > db
		return da < db
	)
	var owned := _count_owned(gs, int(gs.active_player))
	var max_squads := 3
	match style:
		0:
			max_squads = 1 # single stack — soft-cap rush ≤6 without starving floor
		1:
			max_squads = 1 # one deep eye stack — kite floor ≥4
		2:
			max_squads = 3 # multi-seat CP sit — control floor ≥4
		3:
			max_squads = 3 # tank covers multiple CP seats
		4:
			max_squads = 5
		5:
			max_squads = 2 # slight floor lift toward 4–6 without pickup greed
	if style != 4 and owned >= max_squads:
		# Prefer attach unless no unlockable mutant.
		if _has_attach_target(gs):
			return false
	for gene in prio:
		if not gs.offer_cards.has(gene):
			continue
		for c in cells:
			if rules.can_play_card_spawn(gs, gene, c):
				_play_offer_spawn(gs, gene, c)
				return true
	# Any remaining playable spawn
	for gene_any in gs.offer_cards:
		var gene := str(gene_any)
		for c in cells:
			if rules.can_play_card_spawn(gs, gene, c):
				_play_offer_spawn(gs, gene, c)
				return true
	return false

func _has_attach_target(gs) -> bool:
	for s_any in gs.squads.values():
		var s = s_any
		if s == null or not s.is_alive():
			continue
		if int(s.owner) != int(gs.active_player):
			continue
		if bool(s.organs_locked):
			continue
		if not rules.is_spawn_pool_cell(gs, s.cell, int(s.owner)):
			continue
		if int(s.unit_count_alive()) >= RulesScript.ORGAN_HARD_MAX:
			continue
		return true
	return false

func _try_attach(gs, style: int) -> bool:
	var prio := _gene_priority(style)
	var targets: Array = []
	for s_any in gs.squads.values():
		var s = s_any
		if s == null or not s.is_alive():
			continue
		if int(s.owner) != int(gs.active_player):
			continue
		if bool(s.organs_locked):
			continue
		if not rules.is_spawn_pool_cell(gs, s.cell, int(s.owner)):
			continue
		targets.append(s)
	if targets.is_empty():
		return false
	# Tank: once one body is soaked (≥2), prefer a second seat for multi-CP.
	if style == 3 and _count_owned(gs, int(gs.active_player)) < 2:
		for s0 in targets:
			if int(s0.unit_count_alive()) >= 2:
				return false
	# Prefer largest stack for tank/rush; smallest for swarm.
	targets.sort_custom(func(a, b):
		if style == 4:
			return int(a.unit_count_alive()) < int(b.unit_count_alive())
		return int(a.unit_count_alive()) > int(b.unit_count_alive())
	)
	for gene in prio:
		if not gs.offer_cards.has(gene):
			continue
		for s in targets:
			# Soft lever: tank≥4, rush≤6, kite/control≥3, swarm≤9, max≤12.
			var soft := RulesScript.ORGAN_SOFT_CEILING
			if style == 4:
				soft = 3 # thinner swarm — leave rush a path
			elif style == 0:
				soft = 2 # thinner rush — soft-cap ≤6 without tyrant
			elif style == 1:
				soft = 7 # deep eye stack on one body
			elif style == 2:
				soft = 4 # CP sit body — control floor ≥4
			elif style == 3:
				soft = 5 # deeper soak — tank floor ≥4 vs rush/control
			elif style == 5:
				soft = 4 # soft floor toward 4–6 band without greed tyrant
			if int(s.unit_count_alive()) >= soft:
				continue
			if rules.can_play_card_reinforce(gs, gene, int(s.id)):
				_play_offer_reinforce(gs, gene, int(s.id))
				return true
	return false

func _count_owned(gs, player: int) -> int:
	var n := 0
	for s_any in gs.squads.values():
		var s = s_any
		if s != null and s.is_alive() and int(s.owner) == player:
			n += 1
	return n

# --- Human-like actions ---

func _play_actions(gs, style: int) -> void:
	# Multiple passes: act with each owned mutant (humans often clear all moves).
	var passes := 0
	while passes < 6 and gs.winner == -1:
		passes += 1
		var acted := false
		var ids: Array = gs.squads.keys()
		ids.sort()
		for sid_any in ids:
			if gs.winner != -1:
				return
			var sid := int(sid_any)
			var s = gs.get_squad(sid)
			if s == null or not s.is_alive():
				continue
			if int(s.owner) != int(gs.active_player):
				continue
			if int(s.fresh_turn) == int(gs.turn_number):
				continue
			if _act_one_squad(gs, sid, style):
				acted = true
		if not acted:
			break

func _act_one_squad(gs, sid: int, style: int) -> bool:
	var s = gs.get_squad(sid)
	if s == null or not s.is_alive():
		return false
	# Control on a safe CP: don't abandon for gear greed.
	var skip_pickup := style == 2 and _in_cp_zone(gs, s.cell)
	if not skip_pickup and _try_pickup_detour(gs, sid, style):
		return true
	match style:
		1: # kite — open distance before trading
			if _kite_too_close(gs, sid) and _try_run(gs, sid, style):
				return true
			if _try_combat(gs, sid, style):
				return true
			s = gs.get_squad(sid)
			if s == null or not s.is_alive() or gs.winner != -1:
				return true
			if _try_run(gs, sid, style):
				return true
			if _try_basic_move(gs, sid, style):
				_try_combat(gs, sid, style)
				return true
			return false
		0: # rush — fight then close (gap-close after setup; delayed to soft-cap ≤6)
			if _try_combat(gs, sid, style):
				s = gs.get_squad(sid)
				if s == null or not s.is_alive() or gs.winner != -1:
					return true
			var rush_close := int(gs.turn_number) > 10
			if rush_close and _try_charge(gs, sid, style):
				return true
			if rush_close and _try_dash(gs, sid, style):
				return true
			if _try_run(gs, sid, style):
				return true
			if _try_slam(gs, sid):
				return true
			if _try_basic_move(gs, sid, style):
				s = gs.get_squad(sid)
				if s != null and s.is_alive() and gs.winner == -1:
					_try_combat(gs, sid, style)
					_try_slam(gs, sid)
				return true
			return false
		3: # tank — slam/melee clear, hold CP; don't abandon a safe zone
			var did := false
			if _try_slam(gs, sid):
				did = true
				s = gs.get_squad(sid)
				if s == null or not s.is_alive() or gs.winner != -1:
					return true
			if _try_combat(gs, sid, style):
				did = true
				s = gs.get_squad(sid)
				if s == null or not s.is_alive() or gs.winner != -1:
					return true
			s = gs.get_squad(sid)
			if s == null:
				return did
			if _in_cp_zone(gs, s.cell) and not _enemy_threat_near(gs, sid, 2):
				return did # sit until peeled at range 2
			# Charge earlier — closes on kite/control campers (tank floor ≥4).
			if int(gs.turn_number) > 3 and _try_charge(gs, sid, style):
				return true
			if _try_run(gs, sid, style):
				return true
			if _try_basic_move(gs, sid, style):
				s = gs.get_squad(sid)
				if s != null and s.is_alive() and gs.winner == -1:
					_try_combat(gs, sid, style)
					_try_slam(gs, sid)
				return true
			return did
		2: # control — snare first, move to CP, sit once there
			if _enemy_threat_near(gs, sid, 2):
				if _try_combat(gs, sid, style):
					return true
				if _try_slam(gs, sid):
					return true
			if _try_snare(gs, sid, style):
				s = gs.get_squad(sid)
				if s == null or not s.is_alive():
					return true
			s = gs.get_squad(sid)
			if s != null and _in_cp_zone(gs, s.cell) and not _enemy_threat_near(gs, sid, 2):
				if _try_combat(gs, sid, style):
					return true
				return true # sit owned/contested zone
			if _try_run(gs, sid, style):
				return true
			if _try_basic_move(gs, sid, style):
				s = gs.get_squad(sid)
				if s != null and s.is_alive() and gs.winner == -1:
					_try_snare(gs, sid, style)
					if _in_cp_zone(gs, s.cell) or _enemy_threat_near(gs, sid, 2):
						_try_combat(gs, sid, style)
				return true
			if s != null and _in_cp_zone(gs, s.cell):
				if _try_combat(gs, sid, style):
					return true
				if _try_slam(gs, sid):
					return true
			return false
		_:
			var did := false
			if _try_combat(gs, sid, style):
				did = true
				s = gs.get_squad(sid)
				if s == null or not s.is_alive() or gs.winner != -1:
					return did
			if _try_snare(gs, sid, style):
				did = true
				s = gs.get_squad(sid)
				if s == null or not s.is_alive():
					return did
			if _try_slam(gs, sid):
				did = true
				s = gs.get_squad(sid)
				if s == null or not s.is_alive() or gs.winner != -1:
					return did
			# Balanced skips dash — less map greed; keep run for board reach.
			if style != 5 and _try_dash(gs, sid, style):
				did = true
				s = gs.get_squad(sid)
				if s == null or not s.is_alive() or gs.winner != -1:
					return did
			if _try_run(gs, sid, style):
				return true
			if _try_basic_move(gs, sid, style):
				s = gs.get_squad(sid)
				if s != null and s.is_alive() and gs.winner == -1:
					_try_combat(gs, sid, style)
					if style != 5:
						_try_slam(gs, sid)
				return true
			return did

func _kite_too_close(gs, sid: int) -> bool:
	var s = gs.get_squad(sid)
	if s == null:
		return false
	var enemy = _nearest_enemy(gs, s.cell, int(s.owner))
	if enemy == null:
		return false
	var d: int = absi(enemy.cell.x - s.cell.x) + absi(enemy.cell.y - s.cell.y)
	return d <= 2 # shoot at 3–6; flee ≤2

func _kite_ideal_dist_score(from: Vector2i, enemy_cell: Vector2i) -> int:
	var d: int = absi(enemy_cell.x - from.x) + absi(enemy_cell.y - from.y)
	if d >= 3 and d <= 5:
		return 40
	if d == 6:
		return 14
	if d == 2:
		return -8
	if d <= 1:
		return -40
	return 0

func _enemy_sids(gs, me: int) -> Array:
	var out: Array = []
	for s_any in gs.squads.values():
		var s = s_any
		if s != null and s.is_alive() and int(s.owner) != me:
			out.append(int(s.id))
	return out

func _nearest_enemy(gs, from: Vector2i, me: int):
	var best = null
	var best_d := 9999
	for sid in _enemy_sids(gs, me):
		var e = gs.get_squad(sid)
		if e == null:
			continue
		var d: int = absi(e.cell.x - from.x) + absi(e.cell.y - from.y)
		if d < best_d:
			best_d = d
			best = e
	return best

func _cp_target(gs, me: int) -> Vector2i:
	# Prefer neutral or enemy-owned CP; avoid contested.
	var best := Vector2i(-1, -1)
	var best_score := -99999
	for cp in gs.board.control_points:
		var score := 0
		if int(cp.owner) == -1:
			score += 30
		elif int(cp.owner) != me:
			score += 20
		else:
			score += 5
		# Prefer closer to my side midboard
		var mid_y := int(gs.board.size.y) / 2
		score -= absi(int(cp.cell.y) - mid_y)
		if score > best_score:
			best_score = score
			best = cp.cell
	return best

func _cp_owner_at(gs, cp_cell: Vector2i) -> int:
	for cp_st in gs.board.control_points:
		if cp_st.cell == cp_cell:
			return int(cp_st.owner)
	return -1

func _in_cp_zone(gs, cell: Vector2i) -> bool:
	for cp in gs.board.control_points:
		if absi(cell.x - cp.cell.x) + absi(cell.y - cp.cell.y) <= 1:
			return true
	return false

func _enemy_threat_near(gs, sid: int, dist: int) -> bool:
	var s = gs.get_squad(sid)
	if s == null:
		return false
	var me := int(s.owner)
	for e_any in gs.squads.values():
		var e = e_any
		if e == null or not e.is_alive() or int(e.owner) == me:
			continue
		if absi(e.cell.x - s.cell.x) + absi(e.cell.y - s.cell.y) <= dist:
			return true
	return false

func _goal_cell(gs, s, style: int) -> Vector2i:
	var me := int(s.owner)
	var enemy = _nearest_enemy(gs, s.cell, me)
	var cp := _cp_target(gs, me)
	var de := 9999
	if enemy != null:
		de = absi(enemy.cell.x - s.cell.x) + absi(enemy.cell.y - s.cell.y)
	var dc := 9999
	if cp.x >= 0:
		dc = absi(cp.x - s.cell.x) + absi(cp.y - s.cell.y)
	match style:
		0: # rush — early: lean CP / don't cross-map; later: hunt (CP only with +2 margin)
			if int(gs.turn_number) <= 10:
				if enemy != null and de <= 2:
					return enemy.cell
				if cp.x >= 0:
					return cp
				return enemy.cell if enemy != null else s.cell
			if enemy != null:
				if cp.x >= 0 and dc + 2 < de:
					return cp
				return enemy.cell
			return cp if cp.x >= 0 else s.cell
		1: # kite — poke at 3–6; flee ≤2; contest CP when enemy >2 away
			if enemy != null and de <= 2:
				var away: Vector2i = s.cell + Vector2i(
					signi(s.cell.x - enemy.cell.x),
					signi(s.cell.y - enemy.cell.y)
				)
				if gs.board.in_bounds(away) and gs.squad_at(away) == null:
					return away
				var home_y := 0 if me == 0 else int(gs.board.size.y) - 1
				return Vector2i(s.cell.x, home_y)
			if enemy != null and de >= 3 and de <= 6:
				return enemy.cell # poke band; combat handles shots
			if enemy != null and de > 6:
				return enemy.cell
			if cp.x >= 0 and (enemy == null or de > 2) and dc <= 8:
				var cp_owner := _cp_owner_at(gs, cp)
				if cp_owner != me:
					return cp
			return s.cell
		2: # control — sit/contest CP; peel only if enemy already on zone
			if cp.x >= 0:
				if enemy != null and de <= 1 and _in_cp_zone(gs, enemy.cell):
					return enemy.cell
				return cp
			if enemy != null:
				return enemy.cell
			return s.cell
		3: # tank — leave immediately, peel ≤7, then hold/contest CP
			if enemy != null and de <= 7:
				return enemy.cell # peel before camping
			if cp.x >= 0:
				return cp
			if enemy != null:
				return enemy.cell
			return s.cell
		4: # swarm: nearest enemy or CP
			if enemy != null:
				return enemy.cell
			return cp
		_:
			if enemy != null and cp.x >= 0:
				return enemy.cell if de <= dc + 1 else cp
			if enemy != null:
				return enemy.cell
			return cp

func _try_combat(gs, sid: int, style: int) -> bool:
	var s = gs.get_squad(sid)
	if s == null:
		return false
	var acts: Array = UnitDefsScript.list_action_ids_for_squad(s)
	# Prefer stronger / style-fitting attacks
	var order: Array[String] = []
	if style == 1:
		order = ["ranged", "railgun", "melee"]
	elif style == 3:
		order = ["slam", "melee", "ranged"]
	elif style == 0:
		order = ["melee", "ranged"]
	elif style == 2:
		order = ["melee", "ranged"]
	else:
		order = ["ranged", "melee"]
	for aid in order:
		if not acts.has(aid):
			continue
		if int(s.cooldowns.get(aid, 0)) > 0:
			continue
		var enemies := _enemy_sids(gs, int(s.owner))
		# Prefer weakest / closest
		enemies.sort_custom(func(a, b):
			var ea = gs.get_squad(a)
			var eb = gs.get_squad(b)
			var da: int = absi(ea.cell.x - s.cell.x) + absi(ea.cell.y - s.cell.y)
			var db: int = absi(eb.cell.x - s.cell.x) + absi(eb.cell.y - s.cell.y)
			if da != db:
				return da < db
			return int(ea.unit_count_alive()) < int(eb.unit_count_alive())
		)
		for eid in enemies:
			if rules.can_attack(gs, sid, eid, aid):
				var before := 0
				var def = gs.get_squad(eid)
				if def != null:
					before = int(def.unit_count_alive())
				_set_focus_pair(s.cell, def.cell if def != null else s.cell)
				resolver.attack(gs, sid, eid, aid)
				def = gs.get_squad(eid)
				var after := 0 if def == null or not def.is_alive() else int(def.unit_count_alive())
				if after < before:
					organ_pops += before - after
					var loss := before - after
					var organ_word := "organ" if loss == 1 else "organs"
					if def == null or not def.is_alive():
						_log("%s %s kills %s at %s" % [
							_player_tag(gs),
							DemoCommentaryScript.action_label(aid),
							DemoCommentaryScript.squad_tag(eid),
							DemoCommentaryScript.cell_str(s.cell),
						])
					else:
						_log("%s %s chips %s at %s (-%d %s)" % [
							_player_tag(gs),
							DemoCommentaryScript.action_label(aid),
							DemoCommentaryScript.squad_tag(eid),
							DemoCommentaryScript.cell_str(def.cell),
							loss,
							organ_word,
						])
				else:
					_log("%s %s hits %s" % [
						_player_tag(gs),
						DemoCommentaryScript.action_label(aid),
						DemoCommentaryScript.squad_tag(eid),
					])
				# Cooldown must be set
				s = gs.get_squad(sid)
				return true
	# Obstacle chip if blocking path to goal
	return _try_break_obstacle(gs, sid)

func _try_break_obstacle(gs, sid: int) -> bool:
	var s = gs.get_squad(sid)
	if s == null:
		return false
	for aid in ["melee", "ranged"]:
		if not UnitDefsScript.list_action_ids_for_squad(s).has(aid):
			continue
		if int(s.cooldowns.get(aid, 0)) > 0:
			continue
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var c: Vector2i = s.cell + dir
			if rules.can_attack_obstacle(gs, sid, c, aid):
				_set_focus_pair(s.cell, c)
				resolver.attack_obstacle(gs, sid, c, aid)
				_log("%s %s strikes obstacle at %s" % [
					_player_tag(gs),
					DemoCommentaryScript.action_label(aid),
					DemoCommentaryScript.cell_str(c),
				])
				return true
	return false

func _try_slam(gs, sid: int) -> bool:
	var s = gs.get_squad(sid)
	if s == null:
		return false
	if not UnitDefsScript.list_action_ids_for_squad(s).has("slam"):
		return false
	if int(s.cooldowns.get("slam", 0)) > 0:
		return false
	# Only slam if an enemy is orthogonally adjacent
	var hit := false
	for eid in _enemy_sids(gs, int(s.owner)):
		var e = gs.get_squad(eid)
		if e == null:
			continue
		var d: int = absi(e.cell.x - s.cell.x) + absi(e.cell.y - s.cell.y)
		if d == 1:
			hit = true
			break
	if not hit:
		return false
	_set_focus(s.cell)
	resolver.use_slam(gs, sid)
	_log("%s slams at %s" % [
		_player_tag(gs),
		DemoCommentaryScript.cell_str(s.cell),
	])
	return true

func _try_snare(gs, sid: int, style: int) -> bool:
	if style != 2:
		return false
	var s = gs.get_squad(sid)
	if s == null:
		return false
	if not UnitDefsScript.list_action_ids_for_squad(s).has("snare"):
		return false
	if int(s.cooldowns.get("snare", 0)) > 0:
		return false
	# Plant toward enemy approach / CP adjacency
	var goal := _goal_cell(gs, s, style)
	var candidates: Array[Vector2i] = []
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if absi(dx) + absi(dy) == 0:
				continue
			if absi(dx) + absi(dy) > 2:
				continue
			candidates.append(Vector2i(s.cell.x + dx, s.cell.y + dy))
	candidates.sort_custom(func(a, b):
		var da: int = absi(a.x - goal.x) + absi(a.y - goal.y)
		var db: int = absi(b.x - goal.x) + absi(b.y - goal.y)
		return da < db
	)
	for c in candidates:
		# Use plant via resolver; it validates.
		var before = gs.board.hazard_at(c)
		resolver.plant_hazard(gs, sid, c, "snare")
		var after = gs.board.hazard_at(c)
		if before == null and after != null:
			_set_focus(c)
			_log("%s plants snare at %s" % [
				_player_tag(gs),
				DemoCommentaryScript.cell_str(c),
			])
			return true
	return false

func _try_charge(gs, sid: int, style: int) -> bool:
	if style != 0 and style != 3:
		return false
	var s = gs.get_squad(sid)
	if s == null:
		return false
	if not UnitDefsScript.list_action_ids_for_squad(s).has("charge"):
		return false
	if int(s.cooldowns.get("charge", 0)) > 0:
		return false
	var enemies := _enemy_sids(gs, int(s.owner))
	enemies.sort_custom(func(a, b):
		var ea = gs.get_squad(a)
		var eb = gs.get_squad(b)
		var da: int = absi(ea.cell.x - s.cell.x) + absi(ea.cell.y - s.cell.y)
		var db: int = absi(eb.cell.x - s.cell.x) + absi(eb.cell.y - s.cell.y)
		if da != db:
			return da < db
		return int(ea.unit_count_alive()) < int(eb.unit_count_alive())
	)
	for eid in enemies:
		if not rules.can_attack(gs, sid, eid, "charge"):
			continue
		var before: Vector2i = s.cell
		var def = gs.get_squad(eid)
		var organs_before := int(def.unit_count_alive()) if def != null else 0
		_set_focus_pair(before, def.cell if def != null else before)
		resolver.use_charge(gs, sid, eid)
		s = gs.get_squad(sid)
		if s == null:
			return true
		def = gs.get_squad(eid)
		var organs_after := 0 if def == null or not def.is_alive() else int(def.unit_count_alive())
		if s.cell != before or organs_after < organs_before:
			if organs_after < organs_before:
				organ_pops += organs_before - organs_after
			_log("%s charges %s" % [
				_player_tag(gs),
				DemoCommentaryScript.squad_tag(eid),
			])
			return true
	return false

func _try_dash(gs, sid: int, style: int) -> bool:
	if style == 1:
		return false # kite rarely dashes into melee
	var s = gs.get_squad(sid)
	if s == null:
		return false
	if not UnitDefsScript.list_action_ids_for_squad(s).has("dash"):
		return false
	if int(s.cooldowns.get("dash", 0)) > 0:
		return false
	var goal := _goal_cell(gs, s, style)
	var best: Vector2i = s.cell
	var best_score := -99999
	# Scan orthogonal rays up to 3
	for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		for steps in range(1, 4):
			var c: Vector2i = s.cell + dir * steps
			if not gs.board.in_bounds(c):
				break
			if gs.board.is_blocked(c):
				break
			if gs.squad_at(c) != null:
				# Can pass enemies for path damage — landing must be empty
				continue
			var score := 100 - (absi(c.x - goal.x) + absi(c.y - goal.y))
			# Bonus if path crosses enemy
			var crossed := false
			for step in range(1, steps):
				var mid: Vector2i = s.cell + dir * step
				var occ = gs.squad_at(mid)
				if occ != null and int(occ.owner) != int(s.owner):
					crossed = true
			if crossed:
				score += 15
			if style == 0:
				score += 12
				for eid in _enemy_sids(gs, int(s.owner)):
					var e = gs.get_squad(eid)
					if e == null:
						continue
					var land_d: int = absi(e.cell.x - c.x) + absi(e.cell.y - c.y)
					if land_d <= 1:
						score += 28
						break
			elif style == 3:
				score -= 8
			if score > best_score:
				best_score = score
				best = c
	if best == s.cell:
		return false
	var before: Vector2i = s.cell
	_set_focus_pair(before, best)
	resolver.use_dash(gs, sid, best)
	s = gs.get_squad(sid)
	if s != null and s.cell != before:
		_log("%s dashes %s -> %s" % [
			_player_tag(gs),
			DemoCommentaryScript.squad_tag(sid),
			DemoCommentaryScript.cell_str(s.cell),
		])
		return true
	return false

func _try_run(gs, sid: int, style: int) -> bool:
	var s = gs.get_squad(sid)
	if s == null:
		return false
	if not UnitDefsScript.list_action_ids_for_squad(s).has("run"):
		return false
	if int(s.cooldowns.get("run", 0)) > 0:
		return false
	var goal := _goal_cell(gs, s, style)
	var reach := path.reachable_cells(gs, sid, 2)
	var best: Vector2i = s.cell
	var best_score := -99999
	for cell_any in reach.keys():
		var c: Vector2i = cell_any
		if c == s.cell:
			continue
		if gs.squad_at(c) != null:
			continue
		var score := 50 - (absi(c.x - goal.x) + absi(c.y - goal.y))
		if style == 0:
			var enemy = _nearest_enemy(gs, s.cell, int(s.owner))
			if enemy != null:
				var d0: int = absi(enemy.cell.x - s.cell.x) + absi(enemy.cell.y - s.cell.y)
				var d1: int = absi(enemy.cell.x - c.x) + absi(enemy.cell.y - c.y)
				if d1 < d0:
					score += 12 if int(gs.turn_number) <= 7 else 35
		elif style == 3:
			var cp := _cp_target(gs, int(s.owner))
			if cp.x >= 0:
				var dcp: int = absi(cp.x - c.x) + absi(cp.y - c.y)
				if dcp == 0:
					score += 32
				elif dcp == 1:
					score += 18
		if style == 1:
			var enemy = _nearest_enemy(gs, s.cell, int(s.owner))
			if enemy != null:
				score += _kite_ideal_dist_score(c, enemy.cell)
				var d0: int = absi(enemy.cell.x - s.cell.x) + absi(enemy.cell.y - s.cell.y)
				var d1: int = absi(enemy.cell.x - c.x) + absi(enemy.cell.y - c.y)
				if d0 <= 3 and d1 > d0:
					score += 28
		if score > best_score:
			best_score = score
			best = c
	if best == s.cell:
		return false
	var before: Vector2i = s.cell
	_set_focus_pair(before, best)
	resolver.use_run(gs, sid, best)
	s = gs.get_squad(sid)
	if s != null and s.cell != before:
		_log("%s runs %s -> %s" % [
			_player_tag(gs),
			DemoCommentaryScript.squad_tag(sid),
			DemoCommentaryScript.cell_str(s.cell),
		])
		return true
	return false

func _pickup_wants(style: int, unit_def_id: String) -> bool:
	if str(unit_def_id) == "":
		return false
	if UnitDefsScript.is_curse_organ(unit_def_id):
		return style in [3, 4, 5]
	return true

func _best_pickup_cell(gs, sid: int, style: int) -> Vector2i:
	var s = gs.get_squad(sid)
	if s == null:
		return Vector2i(-1, -1)
	var reach: Array[Vector2i] = rules.reachable_field_pickups(gs, sid)
	if reach.is_empty():
		return Vector2i(-1, -1)
	var best := Vector2i(-1, -1)
	var best_score := -99999
	for cell in reach:
		var dist: int = absi(cell.x - s.cell.x) + absi(cell.y - s.cell.y)
		var max_detour := PICKUP_DETOUR_RANGE
		if style == 5:
			max_detour = 4 # balanced: shorter greed leash
		if dist > max_detour:
			continue
		var def_id := rules.pickup_unit_def_id(gs, cell)
		if not _pickup_wants(style, def_id):
			continue
		var score := 120 - dist * 14
		if style == 0 and int(s.unit_count_alive()) < 5 and not UnitDefsScript.is_curse_organ(def_id):
			score += 40
		if style == 0 and str(def_id) in ["claw", "hoof", "ram", "eye"]:
			score += 18
		if rules.pickup_is_egg(gs, cell):
			score += 6 if style == 4 else -8
		if UnitDefsScript.is_curse_organ(def_id):
			score -= 28
		if score > best_score:
			best_score = score
			best = cell
	return best

func _try_pickup_detour(gs, sid: int, style: int) -> bool:
	var s = gs.get_squad(sid)
	if s == null or not s.is_alive() or not rules.can_field_attach(s):
		return false
	if style == 4 and int(s.unit_count_alive()) >= 5:
		return false
	if style == 0 and int(s.unit_count_alive()) >= 5:
		return false
	if style == 5:
		return false # balanced: no field-graft greed
	var target := _best_pickup_cell(gs, sid, style)
	if target.x < 0:
		return false
	var before_n := int(s.unit_count_alive())
	if s.cell == target:
		resolver._try_pickups_at_cell(gs, s)
		s = gs.get_squad(sid)
		if s != null and int(s.unit_count_alive()) > before_n:
			_log(DemoCommentaryScript.graft_line(int(gs.active_player), sid))
			_set_focus(target)
			return true
		return false
	if int(s.cooldowns.get("run", 0)) <= 0 and UnitDefsScript.list_action_ids_for_squad(s).has("run"):
		var run_reach := path.reachable_cells(gs, sid, int(UnitDefsScript.action_def_for_squad(s, "run").get("steps", 3)))
		if run_reach.has(target):
			var before: Vector2i = s.cell
			_set_focus_pair(before, target)
			resolver.use_run(gs, sid, target)
			s = gs.get_squad(sid)
			if s != null and s.cell == target and int(s.unit_count_alive()) > before_n:
				_log(DemoCommentaryScript.graft_line(int(gs.active_player), sid))
				return true
	if rules.can_move(gs, sid, target):
		var before2: Vector2i = s.cell
		_set_focus_pair(before2, target)
		resolver.move_squad(gs, sid, target)
		s = gs.get_squad(sid)
		if s != null and s.cell == target and int(s.unit_count_alive()) > before_n:
			_log(DemoCommentaryScript.graft_line(int(gs.active_player), sid))
			return true
	return false

func _try_basic_move(gs, sid: int, style: int) -> bool:
	var s = gs.get_squad(sid)
	if s == null:
		return false
	if not rules.squad_has_available_move(gs, sid):
		return false
	var goal := _goal_cell(gs, s, style)
	var cp := _cp_target(gs, int(s.owner))
	var rng := rules.move_range_for_squad(gs, s)
	var reach := path.reachable_cells(gs, sid, rng)
	var best: Vector2i = s.cell
	var best_score := -99999
	for cell_any in reach.keys():
		var c: Vector2i = cell_any
		if c == s.cell:
			continue
		if not rules.can_move(gs, sid, c):
			continue
		var score := 100 - (absi(c.x - goal.x) + absi(c.y - goal.y))
		if style == 0 or style == 1 or style == 4:
			if int(gs.board.terrain_at(c)) == BoardStateScript.TERRAIN_SAND:
				score += 3
		if style == 3 and cp.x >= 0:
			var dcp: int = absi(cp.x - c.x) + absi(cp.y - c.y)
			if dcp == 0:
				score += 30
			elif dcp == 1:
				score += 16
			if _in_cp_zone(gs, c):
				score += 10
		if style == 0 and cp.x >= 0:
			var dcp: int = absi(cp.x - c.x) + absi(cp.y - c.y)
			var cp_owner := _cp_owner_at(gs, cp)
			if cp_owner >= 0 and cp_owner != int(s.owner):
				if dcp == 0:
					score += 24
				elif dcp <= 1:
					score += 14
			elif dcp == 0:
				score += 18
			elif dcp <= 1:
				score += 10
		if style == 1:
			var enemy = _nearest_enemy(gs, s.cell, int(s.owner))
			if enemy != null:
				score += _kite_ideal_dist_score(c, enemy.cell)
			if cp.x >= 0:
				var dcp: int = absi(cp.x - c.x) + absi(cp.y - c.y)
				var de := 99
				if enemy != null:
					de = absi(enemy.cell.x - s.cell.x) + absi(enemy.cell.y - s.cell.y)
				if de >= 3 and de <= 5 and dcp <= 2:
					score += 22
				elif de > 5 and dcp <= 2:
					score += 15
				elif enemy == null and dcp <= 2:
					score += 15
	# Prefer adjacency/occupation of CP for control
		if style == 2 and goal.x >= 0:
			var dcp: int = absi(c.x - goal.x) + absi(c.y - goal.y)
			if dcp == 0:
				score += 36
			elif dcp <= 1:
				score += 22
			if _in_cp_zone(gs, c):
				score += 14
		# Avoid enemy snares if known
		var h = gs.board.hazard_at(c)
		if h != null and int(h.get("owner", -1)) != int(s.owner):
			score -= 25
		if score > best_score:
			best_score = score
			best = c
	if best == s.cell:
		return false
	var before: Vector2i = s.cell
	_set_focus_pair(before, best)
	var locked_before := bool(s.organs_locked)
	resolver.move_squad(gs, sid, best)
	s = gs.get_squad(sid)
	if s == null or s.cell == before:
		return false
	_log("%s moves %s -> %s" % [
		_player_tag(gs),
		DemoCommentaryScript.cell_str(before),
		DemoCommentaryScript.cell_str(s.cell),
	])
	if not locked_before and bool(s.organs_locked):
		_log(DemoCommentaryScript.lock_line(int(gs.active_player)))
	return true