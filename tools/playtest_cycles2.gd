extends SceneTree

## Extended multi-cycle player playtests.
## godot --headless --path . --script res://tools/playtest_cycles2.gd

const GameStateScript = preload("res://src/sim/GameState.gd")
const ResolverScript = preload("res://src/sim/Resolver.gd")
const RulesScript = preload("res://src/sim/Rules.gd")
const UnitDefsScript = preload("res://src/sim/UnitDefs.gd")
const UnitStateScript = preload("res://src/sim/UnitState.gd")
const PathfindingScript = preload("res://src/sim/Pathfinding.gd")
const BoardStateScript = preload("res://src/sim/BoardState.gd")

var _fails: Array[String] = []
var _passes: int = 0
var _notes: Array[String] = []

func _init() -> void:
	print("=== Chess 3 cycles2 playtest ===")
	_both_players_skirmish(101)
	_duplicate_offer_genes(103)
	_soft_ceiling_then_hard_max(107)
	_terrain_melee_bonus_pops(109)
	_rock_ranged_reduction(113)
	_dash_path_damage(127)
	_run_then_melee(131)
	_inventory_zero_mid_offer(137)
	_attach_to_just_spawned(139)
	_p1_spawn_pool_attach(149)
	_obstacle_melee(151)
	_cp_majority_win(157)
	_cooldown_shared_after_union(163)
	_snare_blocks_move(167)
	_offer_skip_preserves_inventory(173)
	_multi_mutant_focus_fire(179)
	_winner_stops_turns(181)
	_dash_onto_blocked_rejected(191)
	print("=== results: %d pass, %d fail ===" % [_passes, _fails.size()])
	for n in _notes:
		print("NOTE: ", n)
	for f in _fails:
		print("FAIL: ", f)
	quit(1 if _fails.size() > 0 else 0)

func _ok(n: String) -> void:
	_passes += 1
	print("PASS: ", n)

func _fail(n: String, d: String) -> void:
	_fails.append("%s — %s" % [n, d])
	print("FAIL: ", n, " — ", d)

func _note(m: String) -> void:
	_notes.append(m)
	print("NOTE: ", m)

func _gs(seed: int):
	var gs = GameStateScript.new()
	root.add_child(gs)
	gs.setup(GameStateScript.DEFAULT_BOARD_SIZE, seed)
	gs.squads.clear()
	gs._next_squad_id = 1
	gs.winner = -1
	gs.active_player = 0
	gs.turn_number = 1
	gs.add_squad(0, Vector2i(2, 0), "core", 1)
	gs.add_squad(1, Vector2i(11, 13), "core", 1)
	gs.player_inventory[0] = {"core": 10, "claw": 10, "hoof": 10, "eye": 10, "gland": 10, "shell": 10}
	gs.player_inventory[1] = {"core": 10, "claw": 10, "hoof": 10, "eye": 10, "gland": 10, "shell": 10}
	gs.start_offer_phase()
	return gs

func _force_offer(gs, cards: Array) -> void:
	gs.offer_pending = true
	gs.offer_cards.clear()
	for c in cards:
		gs.offer_cards.append(str(c))

func _offer_has(gs, gene: String) -> bool:
	for c in gs.offer_cards:
		if str(c) == gene:
			return true
	return false

func _p0(gs) -> int:
	for sid in gs.squads.keys():
		var s = gs.get_squad(int(sid))
		if s and s.is_alive() and int(s.owner) == 0:
			return int(sid)
	return -1

func _p1(gs) -> int:
	for sid in gs.squads.keys():
		var s = gs.get_squad(int(sid))
		if s and s.is_alive() and int(s.owner) == 1:
			return int(sid)
	return -1

func _owned(gs, owner: int) -> Array:
	var out: Array = []
	var ids: Array = gs.squads.keys()
	ids.sort()
	for sid in ids:
		var s = gs.get_squad(int(sid))
		if s and s.is_alive() and int(s.owner) == owner:
			out.append(int(sid))
	return out

func _attach(gs, resolver, rules, sid: int, gene: String) -> bool:
	if not _offer_has(gs, gene):
		return false
	if not rules.can_play_card_reinforce(gs, gene, sid):
		return false
	var before := int(gs.get_squad(sid).unit_count_alive())
	resolver.play_card_reinforce(gs, gene, sid)
	return int(gs.get_squad(sid).unit_count_alive()) > before

func _spawn(gs, resolver, rules, gene: String) -> int:
	if not _offer_has(gs, gene):
		return -1
	var cells = rules.spawn_cells(gs, gs.active_player)
	for c in cells:
		if rules.can_play_card_spawn(gs, gene, c):
			resolver.play_card_spawn(gs, gene, c)
			var s = gs.squad_at(c)
			return int(s.id) if s else -1
	return -1

func _skip(gs) -> void:
	gs.clear_offer_phase()

func _end(gs, resolver) -> void:
	resolver.end_turn(gs)

func _unfresh(gs, sid: int) -> void:
	var s = gs.get_squad(sid)
	if s:
		s.fresh_turn = -1
		s.moved_turn = -1
		for k in s.cooldowns.keys():
			s.cooldowns[k] = 0

func _pass_turns(gs, resolver, n: int) -> void:
	for _i in range(n):
		if gs.winner != -1:
			return
		if bool(gs.offer_pending):
			_skip(gs)
		_end(gs, resolver)

func _both_players_skirmish(seed: int) -> void:
	var name := "both players build+clash (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	# P0 build
	_force_offer(gs, ["claw", "eye", "hoof"])
	_attach(gs, resolver, rules, _p0(gs), "claw")
	_attach(gs, resolver, rules, _p0(gs), "eye")
	_attach(gs, resolver, rules, _p0(gs), "hoof")
	_end(gs, resolver)
	# P1 build
	_force_offer(gs, ["claw", "shell", "gland"])
	_attach(gs, resolver, rules, _p1(gs), "claw")
	_attach(gs, resolver, rules, _p1(gs), "shell")
	_attach(gs, resolver, rules, _p1(gs), "gland")
	_end(gs, resolver)
	# Meet in middle
	_skip(gs)
	var a = gs.get_squad(_p0(gs))
	var b = gs.get_squad(_p1(gs))
	a.cell = Vector2i(6, 6)
	b.cell = Vector2i(6, 7)
	a.organs_locked = true
	b.organs_locked = true
	_unfresh(gs, a.id)
	var before_b := int(b.unit_count_alive())
	if not rules.can_attack(gs, a.id, b.id, "melee"):
		_fail(name, "P0 melee illegal"); gs.queue_free(); return
	resolver.attack(gs, a.id, b.id, "melee")
	b = gs.get_squad(_p1(gs))
	if b == null or not b.is_alive():
		_ok(name); gs.queue_free(); return
	if int(b.unit_count_alive()) >= before_b:
		_fail(name, "no organ pops on clash"); gs.queue_free(); return
	# P1 responds
	_end(gs, resolver)
	_skip(gs)
	b = gs.get_squad(_p1(gs))
	a = gs.get_squad(_p0(gs))
	if a == null or b == null:
		_ok(name); gs.queue_free(); return
	_unfresh(gs, b.id)
	resolver.attack(gs, b.id, a.id, "melee")
	_ok(name)
	gs.queue_free()

func _duplicate_offer_genes(seed: int) -> void:
	var name := "duplicate genes in offer (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var sid := _p0(gs)
	_force_offer(gs, ["claw", "claw", "claw"])
	if not _attach(gs, resolver, rules, sid, "claw"):
		_fail(name, "first claw attach"); gs.queue_free(); return
	if gs.offer_cards.size() != 2:
		_fail(name, "expected 2 claws left, got %s" % str(gs.offer_cards)); gs.queue_free(); return
	if not _attach(gs, resolver, rules, sid, "claw"):
		_fail(name, "second claw attach"); gs.queue_free(); return
	if not _attach(gs, resolver, rules, sid, "claw"):
		_fail(name, "third claw attach"); gs.queue_free(); return
	if bool(gs.offer_pending):
		_fail(name, "offer should end"); gs.queue_free(); return
	if int(gs.get_squad(sid).unit_count_alive()) != 4: # core+3claw
		_fail(name, "organ count %d" % gs.get_squad(sid).unit_count_alive()); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _soft_ceiling_then_hard_max(seed: int) -> void:
	var name := "soft ceiling through hard max (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var sid := _p0(gs)
	var s = gs.get_squad(sid)
	# Grow to 6 (soft), then to 10
	for _i in range(5):
		s.units.append(UnitStateScript.new("claw", 1, 1))
	if int(s.unit_count_alive()) != 6:
		_fail(name, "setup soft 6"); gs.queue_free(); return
	_force_offer(gs, ["eye", "shell", "gland"])
	# Still legal past soft ceiling
	if not rules.can_play_card_reinforce(gs, "eye", sid):
		_fail(name, "attach illegal at soft ceiling"); gs.queue_free(); return
	_attach(gs, resolver, rules, sid, "eye")
	_attach(gs, resolver, rules, sid, "shell")
	_attach(gs, resolver, rules, sid, "gland")
	s = gs.get_squad(sid)
	# 6+3=9; force to 10
	_force_offer(gs, ["hoof", "hoof", "hoof"])
	_attach(gs, resolver, rules, sid, "hoof")
	s = gs.get_squad(sid)
	if int(s.unit_count_alive()) != 10:
		_fail(name, "expected 10 got %d" % s.unit_count_alive()); gs.queue_free(); return
	if rules.can_add_unit_to_squad(s, "claw"):
		_fail(name, "hard max not enforced"); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _terrain_melee_bonus_pops(seed: int) -> void:
	var name := "soil melee +1 organ pop (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	_skip(gs)
	var a = gs.get_squad(_p0(gs))
	var b = gs.get_squad(_p1(gs))
	a.units.append(UnitStateScript.new("claw", 1, 1))
	# Stack defender
	for _i in range(5):
		b.units.append(UnitStateScript.new("shell", 1, 1))
	a.cell = Vector2i(5, 5)
	b.cell = Vector2i(5, 6)
	gs.board.set_terrain(a.cell, BoardStateScript.TERRAIN_SOIL)
	gs.board.set_terrain(b.cell, BoardStateScript.TERRAIN_SAND) # no rock reduction
	a.organs_locked = true
	_unfresh(gs, a.id)
	var pred = resolver.predict_attack_damage(gs, a.id, b.id, "melee")
	# claw melee base 2 + soil 1 = 3
	if int(pred.get("attacker_bonus", 0)) != 1:
		_fail(name, "expected soil +1, got %s" % str(pred)); gs.queue_free(); return
	var before := int(b.unit_count_alive())
	resolver.attack(gs, a.id, b.id, "melee")
	b = gs.get_squad(_p1(gs))
	var lost := before - int(b.unit_count_alive())
	if lost != int(pred.get("hp_loss", 0)):
		_fail(name, "pop mismatch lost=%d pred=%s" % [lost, str(pred.get("hp_loss"))]); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _rock_ranged_reduction(seed: int) -> void:
	var name := "rock reduces ranged pops (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	_skip(gs)
	var a = gs.get_squad(_p0(gs))
	var b = gs.get_squad(_p1(gs))
	a.units.append(UnitStateScript.new("eye", 1, 1))
	for _i in range(4):
		b.units.append(UnitStateScript.new("shell", 1, 1))
	a.cell = Vector2i(4, 4)
	b.cell = Vector2i(4, 7) # dist 3
	gs.board.set_terrain(a.cell, BoardStateScript.TERRAIN_SAND)
	gs.board.set_terrain(b.cell, BoardStateScript.TERRAIN_ROCK)
	a.organs_locked = true
	_unfresh(gs, a.id)
	var pred = resolver.predict_attack_damage(gs, a.id, b.id, "ranged")
	# eye ranged 1, rock def -1 => min 1 chip
	if int(pred.get("defender_reduction", 0)) != 1:
		_fail(name, "expected rock reduction %s" % str(pred)); gs.queue_free(); return
	if int(pred.get("hp_loss", 0)) != 1:
		_fail(name, "expected 1 organ pop after reduction, got %s" % str(pred.get("hp_loss"))); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _dash_path_damage(seed: int) -> void:
	var name := "dash damages along path (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	_skip(gs)
	var a = gs.get_squad(_p0(gs))
	var b = gs.get_squad(_p1(gs))
	a.units.append(UnitStateScript.new("claw", 1, 1))
	for _i in range(3):
		b.units.append(UnitStateScript.new("shell", 1, 1))
	a.cell = Vector2i(3, 3)
	b.cell = Vector2i(4, 3) # on path
	var land := Vector2i(5, 3)
	# clear obstacles on path
	for c in [Vector2i(3,3), Vector2i(4,3), Vector2i(5,3)]:
		if gs.board.obstacles.has(c):
			gs.board.obstacles.erase(c)
	a.organs_locked = true
	_unfresh(gs, a.id)
	var before := int(b.unit_count_alive())
	resolver.use_dash(gs, a.id, land)
	a = gs.get_squad(_p0(gs))
	b = gs.get_squad(_p1(gs))
	if a.cell != land:
		_fail(name, "dash did not land at %s (at %s)" % [str(land), str(a.cell)]); gs.queue_free(); return
	if b == null or not b.is_alive():
		_ok(name); gs.queue_free(); return
	if int(b.unit_count_alive()) >= before:
		_fail(name, "dash path dealt no damage"); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _run_then_melee(seed: int) -> void:
	var name := "hoof run into melee (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	_skip(gs)
	var a = gs.get_squad(_p0(gs))
	var b = gs.get_squad(_p1(gs))
	a.units.append(UnitStateScript.new("hoof", 1, 1))
	a.units.append(UnitStateScript.new("claw", 1, 1))
	a.cell = Vector2i(5, 5)
	b.cell = Vector2i(5, 8)
	for c in [Vector2i(5,6), Vector2i(5,7), Vector2i(5,8)]:
		if gs.board.obstacles.has(c):
			gs.board.obstacles.erase(c)
	a.organs_locked = true
	_unfresh(gs, a.id)
	resolver.use_run(gs, a.id, Vector2i(5, 7)) # steps 2
	a = gs.get_squad(_p0(gs))
	if a.cell != Vector2i(5, 7):
		_fail(name, "run failed cell=%s" % str(a.cell)); gs.queue_free(); return
	# melee now adjacent
	_unfresh(gs, a.id)
	if not rules.can_attack(gs, a.id, b.id, "melee"):
		_fail(name, "melee after run illegal"); gs.queue_free(); return
	resolver.attack(gs, a.id, b.id, "melee")
	_ok(name)
	gs.queue_free()

func _inventory_zero_mid_offer(seed: int) -> void:
	var name := "inventory depletes mid-offer (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var sid := _p0(gs)
	gs.player_inventory[0] = {"claw": 1, "eye": 5, "core": 5}
	_force_offer(gs, ["claw", "claw", "eye"]) # second claw not in inv after first
	if not _attach(gs, resolver, rules, sid, "claw"):
		_fail(name, "first claw"); gs.queue_free(); return
	# Second claw still listed until prune; inventory 0 → cannot play, then pruned
	if int(gs.player_inventory[0].get("claw", 0)) != 0:
		_fail(name, "inv claw not 0"); gs.queue_free(); return
	if rules.can_play_card_reinforce(gs, "claw", sid):
		_fail(name, "can_play claw with zero inv"); gs.queue_free(); return
	var before := int(gs.get_squad(sid).unit_count_alive())
	resolver.play_card_reinforce(gs, "claw", sid)
	if int(gs.get_squad(sid).unit_count_alive()) != before:
		_fail(name, "attached with zero inventory"); gs.queue_free(); return
	# After first attach, finish_offer_if_done pruned dead claw copies
	if _offer_has(gs, "claw"):
		_fail(name, "zero-inv claw should be pruned from offer, cards=%s" % str(gs.offer_cards)); gs.queue_free(); return
	if not bool(gs.offer_pending):
		_fail(name, "offer cleared too early"); gs.queue_free(); return
	if not _attach(gs, resolver, rules, sid, "eye"):
		_fail(name, "eye should still attach"); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _attach_to_just_spawned(seed: int) -> void:
	var name := "spawn then attach same offer (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	# Clear preseed to free spawn space clarity — keep P1
	var sid0 := _p0(gs)
	gs.squads.erase(sid0)
	_force_offer(gs, ["core", "claw", "eye"])
	var nid := _spawn(gs, resolver, rules, "core")
	if nid < 0:
		_fail(name, "spawn core"); gs.queue_free(); return
	var s = gs.get_squad(nid)
	if not bool(gs.offer_pending):
		_fail(name, "offer ended after spawn"); gs.queue_free(); return
	if not _attach(gs, resolver, rules, nid, "claw"):
		_fail(name, "attach to newborn"); gs.queue_free(); return
	if int(s.unit_count_alive()) != 2:
		_fail(name, "expected 2 organs"); gs.queue_free(); return
	# newborn is fresh — cannot move
	if rules.squad_has_available_move(gs, nid):
		_fail(name, "fresh newborn can move"); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _p1_spawn_pool_attach(seed: int) -> void:
	var name := "P1 spawn pool attach (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	_skip(gs)
	_end(gs, resolver) # P1 active
	var sid := _p1(gs)
	if not rules.is_spawn_pool_cell(gs, gs.get_squad(sid).cell, 1):
		_fail(name, "P1 seed not in spawn pool"); gs.queue_free(); return
	_force_offer(gs, ["eye", "claw", "hoof"])
	if not _attach(gs, resolver, rules, sid, "eye"):
		_fail(name, "P1 attach eye"); gs.queue_free(); return
	# P0 mutant in P1 pool should not accept P1 attach... place enemy in P1 band
	var enemy = _p0(gs)
	var e = gs.get_squad(enemy)
	e.cell = Vector2i(10, 13)
	e.organs_locked = false
	if rules.can_play_card_reinforce(gs, "claw", enemy):
		_fail(name, "P1 can attach to P0 mutant"); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _obstacle_melee(seed: int) -> void:
	var name := "melee damages obstacle (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	_skip(gs)
	var a = gs.get_squad(_p0(gs))
	a.units.append(UnitStateScript.new("claw", 1, 1))
	a.cell = Vector2i(4, 4)
	var oc := Vector2i(4, 5)
	gs.board.obstacles[oc] = {"hp": 5, "destructible": true}
	a.organs_locked = true
	_unfresh(gs, a.id)
	if not rules.can_attack_obstacle(gs, a.id, oc, "melee"):
		_fail(name, "cannot melee obstacle"); gs.queue_free(); return
	var before := int(gs.board.obstacle_hp(oc))
	resolver.attack_obstacle(gs, a.id, oc, "melee")
	var after := int(gs.board.obstacle_hp(oc))
	if after >= before:
		_fail(name, "obstacle hp unchanged %d->%d" % [before, after]); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _cp_majority_win(seed: int) -> void:
	var name := "CP majority win (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	_skip(gs)
	# Force capture all CPs for P0 via flags
	if gs.board.control_points.is_empty():
		_fail(name, "no CPs"); gs.queue_free(); return
	for cp in gs.board.control_points:
		cp.owner = 0
		cp.reset_flags()
	resolver._check_win(gs)
	if gs.winner != 0:
		_fail(name, "expected P0 CP win, winner=%d" % gs.winner); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _cooldown_shared_after_union(seed: int) -> void:
	var name := "shared melee cooldown (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	_skip(gs)
	var a = gs.get_squad(_p0(gs))
	var b = gs.get_squad(_p1(gs))
	a.units.append(UnitStateScript.new("claw", 1, 1)) # also melee
	a.cell = Vector2i(6, 6)
	b.cell = Vector2i(6, 7)
	for _i in range(3):
		b.units.append(UnitStateScript.new("shell", 1, 1))
	a.organs_locked = true
	_unfresh(gs, a.id)
	resolver.attack(gs, a.id, b.id, "melee")
	if int(a.cooldowns.get("melee", 0)) <= 0:
		_fail(name, "melee cd not set"); gs.queue_free(); return
	if rules.can_attack(gs, a.id, b.id, "melee"):
		_fail(name, "melee usable on cooldown"); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _snare_blocks_move(seed: int) -> void:
	var name := "snare blocks basic move (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	_skip(gs)
	var a = gs.get_squad(_p0(gs))
	var b = gs.get_squad(_p1(gs))
	a.units.append(UnitStateScript.new("gland", 1, 1))
	a.cell = Vector2i(5, 5)
	b.cell = Vector2i(7, 5)
	a.organs_locked = true
	_unfresh(gs, a.id)
	var trap := Vector2i(6, 5)
	if gs.board.obstacles.has(trap):
		gs.board.obstacles.erase(trap)
	resolver.plant_hazard(gs, a.id, trap, "snare")
	gs.active_player = 1
	_unfresh(gs, b.id)
	resolver._set_squad_cell(gs, b, trap)
	resolver._trigger_hazard_on_enter(gs, b)
	b = gs.get_squad(_p1(gs))
	var dest := Vector2i(6, 6)
	if gs.board.obstacles.has(dest):
		gs.board.obstacles.erase(dest)
	if rules.can_move(gs, b.id, dest):
		_fail(name, "snared mutant can move"); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _offer_skip_preserves_inventory(seed: int) -> void:
	var name := "skip preserves inventory (seed %d)" % seed
	var gs = _gs(seed)
	var before: Dictionary = gs.player_inventory[0].duplicate(true)
	_force_offer(gs, ["claw", "eye", "shell"])
	_skip(gs)
	for k in before.keys():
		if int(gs.player_inventory[0].get(k, 0)) != int(before.get(k, 0)):
			_fail(name, "inv changed on skip for %s" % k); gs.queue_free(); return
	if bool(gs.offer_pending):
		_fail(name, "offer still pending"); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _multi_mutant_focus_fire(seed: int) -> void:
	var name := "two mutants focus fire (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	_force_offer(gs, ["core", "claw", "claw"])
	var m2 := _spawn(gs, resolver, rules, "core")
	_attach(gs, resolver, rules, m2, "claw")
	_skip(gs)
	_pass_turns(gs, resolver, 2)
	_skip(gs)
	var m1 := _p0(gs)
	# Ensure both P0 mutants
	var owned := _owned(gs, 0)
	if owned.size() < 2:
		# m1 might be first remaining
		_fail(name, "need 2 mutants got %d" % owned.size()); gs.queue_free(); return
	var e = gs.get_squad(_p1(gs))
	for _i in range(6):
		e.units.append(UnitStateScript.new("shell", 1, 1))
	e.cell = Vector2i(8, 8)
	for sid in owned:
		var s = gs.get_squad(sid)
		s.cell = Vector2i(8, 7) if sid == owned[0] else Vector2i(7, 8)
		s.organs_locked = true
		s.units.append(UnitStateScript.new("claw", 1, 1))
		_unfresh(gs, sid)
	var before := int(e.unit_count_alive())
	for sid in owned:
		_unfresh(gs, sid)
		if rules.can_attack(gs, sid, e.id, "melee"):
			resolver.attack(gs, sid, e.id, "melee")
	e = gs.get_squad(_p1(gs))
	if e != null and e.is_alive() and int(e.unit_count_alive()) >= before:
		_fail(name, "focus fire no pops"); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _winner_stops_turns(seed: int) -> void:
	var name := "winner blocks end turn (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	_skip(gs)
	gs.winner = 0
	var t0 := int(gs.turn_number)
	if rules.can_end_turn(gs):
		_fail(name, "can_end_turn after winner"); gs.queue_free(); return
	resolver.end_turn(gs)
	if int(gs.turn_number) != t0:
		_fail(name, "turn advanced after winner"); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _dash_onto_blocked_rejected(seed: int) -> void:
	var name := "dash onto blocked rejected (seed %d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	_skip(gs)
	var a = gs.get_squad(_p0(gs))
	a.units.append(UnitStateScript.new("claw", 1, 1))
	a.cell = Vector2i(2, 4)
	var blocked := Vector2i(2, 6)
	gs.board.obstacles[blocked] = {"hp": 9, "destructible": true}
	a.organs_locked = true
	_unfresh(gs, a.id)
	var before: Vector2i = a.cell
	resolver.use_dash(gs, a.id, blocked)
	a = gs.get_squad(_p0(gs))
	if a.cell == blocked:
		_fail(name, "dashed onto blocked cell"); gs.queue_free(); return
	if a.cell != before and a.cell == blocked:
		_fail(name, "unexpected"); gs.queue_free(); return
	_ok(name)
	gs.queue_free()
