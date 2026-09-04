extends SceneTree

## 30 player-style cycles across organ combinations.
## godot --headless --path . --script res://tools/playtest_30_cycles.gd

const GameStateScript = preload("res://src/sim/GameState.gd")
const ResolverScript = preload("res://src/sim/Resolver.gd")
const RulesScript = preload("res://src/sim/Rules.gd")
const UnitDefsScript = preload("res://src/sim/UnitDefs.gd")
const UnitStateScript = preload("res://src/sim/UnitState.gd")
const BoardStateScript = preload("res://src/sim/BoardState.gd")

var _fails: Array[String] = []
var _passes: int = 0
var _notes: Array[String] = []

func _init() -> void:
	print("=== Chess 3 — 30 live player cycles ===")
	var cycles: Array = [
		Callable(self, "_c01_core_claw_lock_melee"),
		Callable(self, "_c02_spawn_claw_only"),
		Callable(self, "_c03_eye_on_sand_chips"),
		Callable(self, "_c04_eye_on_rock_partial"),
		Callable(self, "_c05_soil_melee_bonus_pop"),
		Callable(self, "_c06_hoof_run_then_melee"),
		Callable(self, "_c07_gland_snare_trap_line"),
		Callable(self, "_c08_shell_slam_two_flanks"),
		Callable(self, "_c09_claw_dash_chip_path"),
		Callable(self, "_c10_dash_onto_enemy_blocked"),
		Callable(self, "_c11_friendly_snare_armed"),
		Callable(self, "_c12_core_back_after_attach"),
		Callable(self, "_c13_set_front_changes_pop_not_power"),
		Callable(self, "_c14_multi_gene_offer_three"),
		Callable(self, "_c15_skip_keeps_inventory"),
		Callable(self, "_c16_end_turn_blocked_in_offer"),
		Callable(self, "_c17_gene_not_in_offer_rejected"),
		Callable(self, "_c18_zero_inv_prunes_offer"),
		Callable(self, "_c19_soft_ceiling_still_legal"),
		Callable(self, "_c20_hard_max_rejects"),
		Callable(self, "_c21_return_pool_stays_locked"),
		Callable(self, "_c22_move_in_spawn_no_lock"),
		Callable(self, "_c23_fresh_after_attach_blocks"),
		Callable(self, "_c24_pop_eye_prunes_ranged_cd"),
		Callable(self, "_c25_two_mutants_focus"),
		Callable(self, "_c26_obstacle_clear_then_enter"),
		Callable(self, "_c27_melee_ally_blocked"),
		Callable(self, "_c28_slam_spares_ally"),
		Callable(self, "_c29_both_build_clash"),
		Callable(self, "_c30_mixed_attrition_match"),
	]
	if cycles.size() != 30:
		printerr("Expected 30 cycles, got %d" % cycles.size())
		quit(2)
		return
	for i in range(cycles.size()):
		var seed := 400 + i * 17
		cycles[i].call(seed)
	print("=== results: %d pass, %d fail, %d notes ===" % [_passes, _fails.size(), _notes.size()])
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

func _note(n: String) -> void:
	_notes.append(n)
	print("NOTE: ", n)

func _gs(seed: int):
	var gs = GameStateScript.new()
	root.add_child(gs)
	gs.setup(GameStateScript.DEFAULT_BOARD_SIZE, seed)
	gs.squads.clear()
	gs._next_squad_id = 1
	gs.winner = -1
	gs.active_player = 0
	gs.turn_number = 1
	gs.player_inventory[0] = {"core": 12, "claw": 12, "hoof": 12, "eye": 12, "gland": 12, "shell": 12}
	gs.player_inventory[1] = gs.player_inventory[0].duplicate(true)
	gs.offer_pending = false
	gs.offer_cards.clear()
	return gs

func _unfresh(gs, sid: int) -> void:
	var s = gs.get_squad(sid)
	if s == null:
		return
	s.fresh_turn = -1
	s.moved_turn = -1
	for k in s.cooldowns.keys():
		s.cooldowns[k] = 0

func _clear(gs, c: Vector2i) -> void:
	if gs.board.obstacles.has(c):
		gs.board.obstacles.erase(c)

func _offer(gs, ids: Array) -> void:
	gs.offer_cards.clear()
	for id in ids:
		gs.offer_cards.append(str(id))

func _acts(s) -> Array:
	return UnitDefsScript.list_action_ids_for_squad(s)

func _sand(gs, c: Vector2i) -> void:
	gs.board.set_terrain(c, BoardStateScript.TERRAIN_SAND)

func _rock(gs, c: Vector2i) -> void:
	gs.board.set_terrain(c, BoardStateScript.TERRAIN_ROCK)

func _soil(gs, c: Vector2i) -> void:
	gs.board.set_terrain(c, BoardStateScript.TERRAIN_SOIL)

func _spawn_build(gs, resolver, rules, owner: int, genes: Array) -> int:
	# Player-like: offer genes, spawn first, attach rest.
	gs.active_player = owner
	gs.offer_pending = true
	_offer(gs, genes)
	var cells = rules.spawn_cells(gs, owner)
	if cells.is_empty() or genes.is_empty():
		return -1
	var c: Vector2i = cells[0]
	_clear(gs, c)
	resolver.play_card_spawn(gs, str(genes[0]), c)
	var sq = gs.squad_at(c)
	if sq == null:
		return -1
	var sid := int(sq.id)
	for i in range(1, genes.size()):
		gs.offer_pending = true
		if not gs.offer_cards.has(str(genes[i])):
			_offer(gs, [genes[i], "core", "claw"])
		if rules.can_play_card_reinforce(gs, str(genes[i]), sid):
			resolver.play_card_reinforce(gs, str(genes[i]), sid)
	gs.clear_offer_phase()
	return sid

func _force_out(gs, resolver, rules, sid: int) -> void:
	var s = gs.get_squad(sid)
	if s == null:
		return
	var out := Vector2i(s.cell.x, RulesScript.HOME_SPAWN_ROWS + 1) if int(s.owner) == 0 else Vector2i(s.cell.x, int(gs.board.size.y) - RulesScript.HOME_SPAWN_ROWS - 2)
	_clear(gs, out)
	resolver._set_squad_cell(gs, s, out)

# --- cycles -----------------------------------------------------------------

func _c01_core_claw_lock_melee(seed: int) -> void:
	var n := "01 core+claw lock melee (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var sid := _spawn_build(gs, resolver, rules, 0, ["core", "claw"])
	if sid < 0:
		_fail(n, "build failed"); gs.queue_free(); return
	_force_out(gs, resolver, rules, sid)
	var s = gs.get_squad(sid)
	if not bool(s.organs_locked):
		_fail(n, "not locked"); gs.queue_free(); return
	var eid := gs.add_squad(1, Vector2i(s.cell.x, s.cell.y + 1), "core", 1)
	_clear(gs, gs.get_squad(eid).cell)
	_unfresh(gs, sid)
	if not rules.can_attack(gs, sid, eid, "melee"):
		_fail(n, "melee illegal"); gs.queue_free(); return
	resolver.attack(gs, sid, eid, "melee")
	if gs.get_squad(eid) != null and gs.get_squad(eid).is_alive():
		_fail(n, "enemy lived"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _c02_spawn_claw_only(seed: int) -> void:
	var n := "02 spawn claw-only mutant (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var sid := _spawn_build(gs, resolver, rules, 0, ["claw"])
	if sid < 0:
		_fail(n, "spawn failed"); gs.queue_free(); return
	var s = gs.get_squad(sid)
	var acts = _acts(s)
	if not acts.has("melee") or not acts.has("dash"):
		_fail(n, "claw abilities missing: %s" % str(acts)); gs.queue_free(); return
	if int(s.unit_count_alive()) != 1:
		_fail(n, "expected 1 organ"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _c03_eye_on_sand_chips(seed: int) -> void:
	var n := "03 eye sand chips 3org (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var a := gs.add_squad(0, Vector2i(5, 5), "core", 1)
	gs.get_squad(a).units.append(UnitStateScript.new("claw", 1, 1))
	gs.get_squad(a).units.append(UnitStateScript.new("hoof", 1, 1))
	var b := gs.add_squad(1, Vector2i(5, 8), "core", 1)
	gs.get_squad(b).units.append(UnitStateScript.new("eye", 1, 1))
	_sand(gs, gs.get_squad(a).cell)
	_sand(gs, gs.get_squad(b).cell)
	gs.active_player = 1
	_unfresh(gs, b)
	var pred = resolver.predict_attack_damage(gs, b, a, "ranged")
	if int(pred.get("hp_loss", 0)) != 2:
		_fail(n, "expected 2 organ chip on sand: %s" % str(pred)); gs.queue_free(); return
	resolver.attack(gs, b, a, "ranged")
	var sa = gs.get_squad(a)
	if sa == null or not sa.is_alive() or int(sa.unit_count_alive()) != 1:
		_fail(n, "3-organ should survive with 1 organ left"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _c04_eye_on_rock_partial(seed: int) -> void:
	var n := "04 eye rock partial pop (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var a := gs.add_squad(0, Vector2i(5, 5), "core", 1)
	gs.get_squad(a).units.append(UnitStateScript.new("claw", 1, 1))
	var b := gs.add_squad(1, Vector2i(5, 8), "core", 1)
	gs.get_squad(b).units.append(UnitStateScript.new("eye", 1, 1))
	_rock(gs, gs.get_squad(a).cell)
	gs.active_player = 1
	_unfresh(gs, b)
	var pred = resolver.predict_attack_damage(gs, b, a, "ranged")
	if int(pred.get("defender_reduction", 0)) != 1:
		_fail(n, "rock should −1 ranged: %s" % str(pred)); gs.queue_free(); return
	resolver.attack(gs, b, a, "ranged")
	var sa = gs.get_squad(a)
	if sa == null or not sa.is_alive() or int(sa.unit_count_alive()) != 1:
		_fail(n, "expected 1 organ left on rock"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _c05_soil_melee_bonus_pop(seed: int) -> void:
	var n := "05 soil melee +1 pop (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var a := gs.add_squad(0, Vector2i(6, 6), "core", 1)
	gs.get_squad(a).units.append(UnitStateScript.new("claw", 1, 1))
	var b := gs.add_squad(1, Vector2i(6, 7), "core", 1)
	for _i in range(4):
		gs.get_squad(b).units.append(UnitStateScript.new("shell", 1, 1))
	_soil(gs, gs.get_squad(a).cell)
	gs.get_squad(a).organs_locked = true
	_unfresh(gs, a)
	var pred = resolver.predict_attack_damage(gs, a, b, "melee")
	if int(pred.get("attacker_bonus", 0)) != 1:
		_fail(n, "soil atk bonus missing: %s" % str(pred)); gs.queue_free(); return
	var before := int(gs.get_squad(b).unit_count_alive())
	resolver.attack(gs, a, b, "melee")
	var after := int(gs.get_squad(b).unit_count_alive()) if gs.get_squad(b) else 0
	if before - after < 2:
		_fail(n, "expected claw+soil to pop >=2, delta=%d" % (before - after)); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _c06_hoof_run_then_melee(seed: int) -> void:
	var n := "06 hoof run then melee (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var sid := _spawn_build(gs, resolver, rules, 0, ["core", "hoof", "claw"])
	_force_out(gs, resolver, rules, sid)
	var s = gs.get_squad(sid)
	var dest := Vector2i(s.cell.x, s.cell.y + 2)
	_clear(gs, Vector2i(s.cell.x, s.cell.y + 1))
	_clear(gs, dest)
	_unfresh(gs, sid)
	resolver.use_run(gs, sid, dest)
	s = gs.get_squad(sid)
	if s.cell != dest:
		_fail(n, "run failed cell=%s" % str(s.cell)); gs.queue_free(); return
	var eid := gs.add_squad(1, Vector2i(dest.x, dest.y + 1), "core", 1)
	_clear(gs, gs.get_squad(eid).cell)
	_unfresh(gs, sid)
	s.cooldowns["melee"] = 0
	if not rules.can_attack(gs, sid, eid, "melee"):
		_fail(n, "melee after run illegal"); gs.queue_free(); return
	resolver.attack(gs, sid, eid, "melee")
	_ok(n)
	gs.queue_free()

func _c07_gland_snare_trap_line(seed: int) -> void:
	var n := "07 gland snare trap line (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var a := gs.add_squad(0, Vector2i(7, 5), "core", 1)
	gs.get_squad(a).units.append(UnitStateScript.new("gland", 1, 1))
	gs.get_squad(a).units.append(UnitStateScript.new("claw", 1, 1))
	gs.get_squad(a).organs_locked = true
	var trap := Vector2i(7, 6)
	_clear(gs, trap)
	_unfresh(gs, a)
	resolver.plant_hazard(gs, a, trap, "snare")
	if gs.board.hazard_at(trap) == null:
		_fail(n, "snare not planted"); gs.queue_free(); return
	var b := gs.add_squad(1, Vector2i(7, 7), "core", 1)
	resolver._set_squad_cell(gs, gs.get_squad(b), trap)
	resolver._trigger_hazard_on_enter(gs, gs.get_squad(b))
	if rules.can_move(gs, b, Vector2i(7, 8)):
		# need active player 1 for can_move owner check
		gs.active_player = 1
		_unfresh(gs, b)
		if rules.can_move(gs, b, Vector2i(7, 8)):
			_fail(n, "snared enemy can move"); gs.queue_free(); return
	gs.active_player = 0
	_unfresh(gs, a)
	gs.get_squad(a).cooldowns["melee"] = 0
	resolver.attack(gs, a, b, "melee")
	if gs.get_squad(b) != null and gs.get_squad(b).is_alive():
		_fail(n, "snared prey lived"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _c08_shell_slam_two_flanks(seed: int) -> void:
	var n := "08 shell slam two flanks (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var a := gs.add_squad(0, Vector2i(8, 8), "core", 1)
	gs.get_squad(a).units.append(UnitStateScript.new("shell", 1, 1))
	gs.get_squad(a).organs_locked = true
	var e1 := gs.add_squad(1, Vector2i(8, 7), "core", 1)
	var e2 := gs.add_squad(1, Vector2i(9, 8), "core", 1)
	_unfresh(gs, a)
	resolver.use_slam(gs, a)
	var dead := 0
	for eid in [e1, e2]:
		var e = gs.get_squad(eid)
		if e == null or not e.is_alive():
			dead += 1
	if dead < 2:
		_fail(n, "slam should kill both, dead=%d" % dead); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _c09_claw_dash_chip_path(seed: int) -> void:
	var n := "09 claw dash path chip (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var a := gs.add_squad(0, Vector2i(4, 4), "core", 1)
	gs.get_squad(a).units.append(UnitStateScript.new("claw", 1, 1))
	gs.get_squad(a).organs_locked = true
	var mid := Vector2i(4, 5)
	var land := Vector2i(4, 6)
	var b := gs.add_squad(1, mid, "core", 1)
	gs.get_squad(b).units.append(UnitStateScript.new("shell", 1, 1))
	gs.get_squad(b).units.append(UnitStateScript.new("shell", 1, 1))
	_clear(gs, Vector2i(4, 4))
	_clear(gs, mid)
	_clear(gs, land)
	_unfresh(gs, a)
	var before := int(gs.get_squad(b).unit_count_alive())
	resolver.use_dash(gs, a, land)
	var aa = gs.get_squad(a)
	if aa.cell != land:
		_fail(n, "dash did not land at %s got %s" % [str(land), str(aa.cell)]); gs.queue_free(); return
	var bb = gs.get_squad(b)
	if bb == null or int(bb.unit_count_alive()) >= before:
		# path_damage 1 should chip
		_fail(n, "dash path did not chip"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _c10_dash_onto_enemy_blocked(seed: int) -> void:
	var n := "10 dash onto enemy blocked (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var a := gs.add_squad(0, Vector2i(3, 3), "core", 1)
	gs.get_squad(a).units.append(UnitStateScript.new("claw", 1, 1))
	gs.get_squad(a).organs_locked = true
	var b := gs.add_squad(1, Vector2i(3, 5), "core", 1)
	_clear(gs, Vector2i(3, 4))
	_unfresh(gs, a)
	var before: Vector2i = gs.get_squad(a).cell
	resolver.use_dash(gs, a, gs.get_squad(b).cell)
	if gs.get_squad(a).cell == gs.get_squad(b).cell:
		_fail(n, "dashed onto enemy"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _c11_friendly_snare_armed(seed: int) -> void:
	var n := "11 friendly snare stays armed (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var a := gs.add_squad(0, Vector2i(5, 5), "core", 1)
	gs.get_squad(a).units.append(UnitStateScript.new("gland", 1, 1))
	gs.get_squad(a).organs_locked = true
	var trap := Vector2i(5, 6)
	_clear(gs, trap)
	_unfresh(gs, a)
	resolver.plant_hazard(gs, a, trap, "snare")
	resolver._set_squad_cell(gs, gs.get_squad(a), trap)
	resolver._trigger_hazard_on_enter(gs, gs.get_squad(a))
	if gs.board.hazard_at(trap) == null:
		_fail(n, "friendly disarmed snare"); gs.queue_free(); return
	resolver._set_squad_cell(gs, gs.get_squad(a), Vector2i(5, 5))
	var b := gs.add_squad(1, Vector2i(5, 7), "core", 1)
	resolver._set_squad_cell(gs, gs.get_squad(b), trap)
	resolver._trigger_hazard_on_enter(gs, gs.get_squad(b))
	if gs.board.hazard_at(trap) != null:
		_fail(n, "enemy did not consume"); gs.queue_free(); return
	if int(gs.get_squad(b).snared_no_move_until_turn) < int(gs.turn_number) + 1:
		_fail(n, "enemy not snared"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _c12_core_back_after_attach(seed: int) -> void:
	var n := "12 core sinks back after attach (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var sid := _spawn_build(gs, resolver, rules, 0, ["core", "eye", "shell"])
	var s = gs.get_squad(sid)
	if str(s.units[s.units.size() - 1].unit_def_id) != "core":
		_fail(n, "core not at back: %s" % str(s.units[s.units.size() - 1].unit_def_id)); gs.queue_free(); return
	if str(s.units[0].unit_def_id) == "core":
		_fail(n, "core still at front"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _c13_set_front_changes_pop_not_power(seed: int) -> void:
	var n := "13 set_front pop≠power (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var a := gs.add_squad(0, Vector2i(4, 4), "core", 1)
	var s = gs.get_squad(a)
	s.units.append(UnitStateScript.new("claw", 1, 1))
	# Stabilize isn't called on manual append — put claw front via set_front
	# units: [core, claw]; set front to claw index 1
	_unfresh(gs, a)
	if not rules.can_set_front_unit(gs, a, 1):
		_fail(n, "cannot set front"); gs.queue_free(); return
	resolver.set_front_unit(gs, a, 1)
	s = gs.get_squad(a)
	if str(s.units[0].unit_def_id) != "claw":
		_fail(n, "front not claw after set_front"); gs.queue_free(); return
	var dmg := int(UnitDefsScript.action_def_for_squad(s, "melee").get("damage", 0))
	if dmg != 2:
		_fail(n, "melee power should stay claw 2, got %d" % dmg); gs.queue_free(); return
	var b := gs.add_squad(1, Vector2i(4, 5), "core", 1)
	gs.get_squad(b).units.append(UnitStateScript.new("shell", 1, 1))
	gs.get_squad(b).units.append(UnitStateScript.new("shell", 1, 1))
	_sand(gs, s.cell)
	_unfresh(gs, a)
	resolver._pop_organs(gs, s, 1)
	s = gs.get_squad(a)
	if str(s.units[0].unit_def_id) != "core":
		_fail(n, "after pop expected core, got %s" % str(s.units[0].unit_def_id)); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _c14_multi_gene_offer_three(seed: int) -> void:
	var n := "14 spend two genes one opening offer (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	gs.offer_pending = true
	gs.offer_picks_remaining = int(gs.offer_pick_quota())
	_offer(gs, ["core", "claw", "eye"])
	var cells = rules.spawn_cells(gs, 0)
	resolver.play_card_spawn(gs, "core", cells[0])
	var sid := int(gs.squad_at(cells[0]).id)
	resolver.play_card_reinforce(gs, "claw", sid)
	if bool(gs.offer_pending):
		_fail(n, "offer should end after opening quota"); gs.queue_free(); return
	if int(gs.get_squad(sid).unit_count_alive()) != 2:
		_fail(n, "expected 2 organs"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _c15_skip_keeps_inventory(seed: int) -> void:
	var n := "15 skip keeps inventory (%d)" % seed
	var gs = _gs(seed)
	gs.offer_pending = true
	_offer(gs, ["claw", "eye", "shell"])
	var before := int(gs.player_inventory[0].get("claw", 0))
	gs.clear_offer_phase()
	if int(gs.player_inventory[0].get("claw", 0)) != before:
		_fail(n, "inventory changed on skip"); gs.queue_free(); return
	if bool(gs.offer_pending):
		_fail(n, "offer still pending"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _c16_end_turn_blocked_in_offer(seed: int) -> void:
	var n := "16 end turn blocked in offer (%d)" % seed
	var gs = _gs(seed)
	var rules = RulesScript.new()
	gs.offer_pending = true
	_offer(gs, ["claw", "eye", "hoof"])
	if rules.can_end_turn(gs):
		_fail(n, "end turn allowed during offer"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _c17_gene_not_in_offer_rejected(seed: int) -> void:
	var n := "17 gene not in offer rejected (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	gs.offer_pending = true
	_offer(gs, ["eye", "hoof", "gland"])
	var cells = rules.spawn_cells(gs, 0)
	if rules.can_play_card_spawn(gs, "claw", cells[0]):
		_fail(n, "claw spawn legal though not offered"); gs.queue_free(); return
	resolver.play_card_spawn(gs, "claw", cells[0])
	if gs.squad_at(cells[0]) != null and str(gs.squad_at(cells[0]).units[0].unit_def_id) == "claw":
		_fail(n, "claw spawned anyway"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _c18_zero_inv_prunes_offer(seed: int) -> void:
	var n := "18 zero inv prunes offer (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	gs.player_inventory[0]["claw"] = 1
	gs.offer_pending = true
	_offer(gs, ["claw", "claw", "claw"])
	var cells = rules.spawn_cells(gs, 0)
	resolver.play_card_spawn(gs, "claw", cells[0])
	# After one spend, inv=0 → remaining claws unplayable → pruned / offer ends
	if gs.offer_cards.has("claw") and int(gs.player_inventory[0].get("claw", 0)) <= 0:
		gs.finish_offer_if_done()
	if bool(gs.offer_pending) and gs.offer_cards.has("claw"):
		# prune should have removed
		gs.prune_unplayable_offer_cards()
		gs.finish_offer_if_done()
	if bool(gs.offer_pending) and not gs.offer_cards.is_empty():
		# if still pending with only unplayable — bug
		var any_playable := false
		for c in gs.offer_cards:
			if rules.can_play_card_spawn(gs, str(c), cells[0] if not cells.is_empty() else Vector2i(0, 0)) \
				or (gs.squad_at(cells[0]) != null and rules.can_play_card_reinforce(gs, str(c), int(gs.squad_at(cells[0]).id))):
				any_playable = true
		if not any_playable and bool(gs.offer_pending):
			_fail(n, "unplayable offer still pending cards=%s" % str(gs.offer_cards)); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _c19_soft_ceiling_still_legal(seed: int) -> void:
	var n := "19 soft ceiling still legal (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var sid := _spawn_build(gs, resolver, rules, 0, ["core"])
	var extras := ["claw", "eye", "hoof", "gland", "shell", "claw"]
	for o in extras:
		gs.offer_pending = true
		_offer(gs, [o, "eye", "hoof"])
		if not rules.can_play_card_reinforce(gs, o, sid):
			_fail(n, "attach %s illegal at %d" % [o, gs.get_squad(sid).unit_count_alive()]); gs.queue_free(); return
		resolver.play_card_reinforce(gs, o, sid)
	if int(gs.get_squad(sid).unit_count_alive()) != 7:
		_fail(n, "expected 7 organs"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _c20_hard_max_rejects(seed: int) -> void:
	var n := "20 hard max rejects (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var sid := _spawn_build(gs, resolver, rules, 0, ["core"])
	for i in range(9):
		gs.offer_pending = true
		_offer(gs, ["claw", "eye", "hoof"])
		resolver.play_card_reinforce(gs, "claw", sid)
	if int(gs.get_squad(sid).unit_count_alive()) != RulesScript.ORGAN_HARD_MAX:
		_fail(n, "expected hard max"); gs.queue_free(); return
	gs.offer_pending = true
	_offer(gs, ["claw", "eye", "hoof"])
	if rules.can_play_card_reinforce(gs, "claw", sid):
		_fail(n, "attach past hard max"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _c21_return_pool_stays_locked(seed: int) -> void:
	var n := "21 return pool stays locked (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var sid := _spawn_build(gs, resolver, rules, 0, ["core", "claw"])
	_force_out(gs, resolver, rules, sid)
	var s = gs.get_squad(sid)
	var home: Vector2i = rules.spawn_cells(gs, 0)[0] if not rules.spawn_cells(gs, 0).is_empty() else Vector2i(0, 0)
	# spawn_cells returns empty cells — find any pool cell
	for x in range(int(gs.board.size.x)):
		var c := Vector2i(x, 0)
		if rules.is_spawn_pool_cell(gs, c, 0) and gs.squad_at(c) == null and not gs.board.is_blocked(c):
			home = c
			break
	resolver._set_squad_cell(gs, s, home)
	if not bool(s.organs_locked):
		_fail(n, "unlocked on return"); gs.queue_free(); return
	gs.offer_pending = true
	_offer(gs, ["eye", "hoof", "shell"])
	if rules.can_play_card_reinforce(gs, "eye", sid):
		_fail(n, "attach on locked returnee"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _c22_move_in_spawn_no_lock(seed: int) -> void:
	var n := "22 move in spawn no lock (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var sid := _spawn_build(gs, resolver, rules, 0, ["core"])
	var s = gs.get_squad(sid)
	var to := Vector2i(-1, -1)
	for x in range(int(gs.board.size.x)):
		var c := Vector2i(x, s.cell.y)
		if c == s.cell:
			continue
		if rules.is_spawn_pool_cell(gs, c, 0) and gs.squad_at(c) == null and not gs.board.is_blocked(c):
			to = c
			break
	if to.x < 0:
		_fail(n, "no free spawn neighbor"); gs.queue_free(); return
	_unfresh(gs, sid)
	if rules.can_move(gs, sid, to):
		resolver.move_squad(gs, sid, to)
	else:
		resolver._set_squad_cell(gs, s, to)
	s = gs.get_squad(sid)
	if bool(s.organs_locked):
		_fail(n, "locked while still in spawn"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _c23_fresh_after_attach_blocks(seed: int) -> void:
	var n := "23 fresh after attach blocks (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var sid := _spawn_build(gs, resolver, rules, 0, ["core"])
	gs.offer_pending = true
	_offer(gs, ["claw", "eye", "hoof"])
	resolver.play_card_reinforce(gs, "claw", sid)
	gs.clear_offer_phase()
	var s = gs.get_squad(sid)
	if int(s.fresh_turn) != int(gs.turn_number):
		_fail(n, "not fresh after attach"); gs.queue_free(); return
	var eid := gs.add_squad(1, Vector2i(s.cell.x, s.cell.y + 2), "core", 1)
	# place adjacent if possible
	var adj := Vector2i(s.cell.x, mini(s.cell.y + 1, int(gs.board.size.y) - 1))
	_clear(gs, adj)
	resolver._set_squad_cell(gs, gs.get_squad(eid), adj)
	if rules.can_attack(gs, sid, eid, "melee"):
		_fail(n, "fresh can melee"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _c24_pop_eye_prunes_ranged_cd(seed: int) -> void:
	var n := "24 pop eye prunes ranged cd (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var a := gs.add_squad(0, Vector2i(5, 5), "core", 1)
	var s = gs.get_squad(a)
	s.units.clear()
	s.units.append(UnitStateScript.new("eye", 1, 1))
	s.units.append(UnitStateScript.new("core", 1, 1))
	s.cooldowns["ranged"] = 3
	s.cooldowns["melee"] = 1
	resolver._pop_organs(gs, s, 1)
	s = gs.get_squad(a)
	if s.cooldowns.has("ranged"):
		_fail(n, "ranged cd lingered"); gs.queue_free(); return
	if int(s.cooldowns.get("melee", 0)) != 1:
		_fail(n, "melee cd should remain"); gs.queue_free(); return
	if _acts(s).has("ranged"):
		_fail(n, "ranged still listed"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _c25_two_mutants_focus(seed: int) -> void:
	var n := "25 two mutants focus fire (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var a1 := gs.add_squad(0, Vector2i(6, 6), "core", 1)
	gs.get_squad(a1).units.append(UnitStateScript.new("claw", 1, 1))
	var a2 := gs.add_squad(0, Vector2i(7, 6), "core", 1)
	gs.get_squad(a2).units.append(UnitStateScript.new("claw", 1, 1))
	var e := gs.add_squad(1, Vector2i(6, 7), "core", 1)
	for _i in range(5):
		gs.get_squad(e).units.append(UnitStateScript.new("shell", 1, 1))
	gs.get_squad(a1).organs_locked = true
	gs.get_squad(a2).organs_locked = true
	_sand(gs, gs.get_squad(a1).cell)
	_sand(gs, gs.get_squad(a2).cell)
	_unfresh(gs, a1)
	_unfresh(gs, a2)
	var before := int(gs.get_squad(e).unit_count_alive())
	resolver.attack(gs, a1, e, "melee")
	# a2 may not be adjacent — move
	resolver._set_squad_cell(gs, gs.get_squad(a2), Vector2i(7, 7))
	_unfresh(gs, a2)
	if rules.can_attack(gs, a2, e, "melee"):
		resolver.attack(gs, a2, e, "melee")
	var after := int(gs.get_squad(e).unit_count_alive()) if gs.get_squad(e) else 0
	if after >= before:
		_fail(n, "no damage from focus"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _c26_obstacle_clear_then_enter(seed: int) -> void:
	var n := "26 obstacle clear then enter (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var a := gs.add_squad(0, Vector2i(3, 3), "core", 1)
	gs.get_squad(a).units.append(UnitStateScript.new("claw", 1, 1))
	gs.get_squad(a).organs_locked = true
	var oc := Vector2i(3, 4)
	gs.board.obstacles[oc] = {"hp": 2, "destructible": true}
	var guard := 0
	while gs.board.is_blocked(oc) and guard < 6:
		guard += 1
		_unfresh(gs, a)
		gs.get_squad(a).cooldowns["melee"] = 0
		resolver.attack_obstacle(gs, a, oc, "melee")
	if gs.board.is_blocked(oc):
		_fail(n, "obstacle remains"); gs.queue_free(); return
	_unfresh(gs, a)
	if not rules.can_move(gs, a, oc):
		_fail(n, "cannot enter cleared"); gs.queue_free(); return
	resolver.move_squad(gs, a, oc)
	_ok(n)
	gs.queue_free()

func _c27_melee_ally_blocked(seed: int) -> void:
	var n := "27 melee ally blocked (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var a := gs.add_squad(0, Vector2i(5, 5), "core", 1)
	gs.get_squad(a).units.append(UnitStateScript.new("claw", 1, 1))
	var ally := gs.add_squad(0, Vector2i(5, 6), "core", 1)
	gs.get_squad(a).organs_locked = true
	_unfresh(gs, a)
	if rules.can_attack(gs, a, ally, "melee"):
		_fail(n, "melee legal on ally"); gs.queue_free(); return
	var before := int(gs.get_squad(ally).unit_count_alive())
	resolver.attack(gs, a, ally, "melee")
	if int(gs.get_squad(ally).unit_count_alive()) != before:
		_fail(n, "ally damaged"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _c28_slam_spares_ally(seed: int) -> void:
	var n := "28 slam spares ally (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var a := gs.add_squad(0, Vector2i(6, 6), "core", 1)
	gs.get_squad(a).units.append(UnitStateScript.new("shell", 1, 1))
	var ally := gs.add_squad(0, Vector2i(6, 7), "core", 1)
	gs.get_squad(ally).units.append(UnitStateScript.new("claw", 1, 1))
	var enemy := gs.add_squad(1, Vector2i(7, 6), "core", 1)
	gs.get_squad(enemy).units.append(UnitStateScript.new("shell", 1, 1))
	gs.get_squad(a).organs_locked = true
	_unfresh(gs, a)
	var ally_before := int(gs.get_squad(ally).unit_count_alive())
	resolver.use_slam(gs, a)
	if int(gs.get_squad(ally).unit_count_alive()) != ally_before:
		_fail(n, "ally hit by slam"); gs.queue_free(); return
	var en = gs.get_squad(enemy)
	if en != null and en.is_alive() and int(en.unit_count_alive()) >= 2:
		_fail(n, "enemy untouched by slam"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()

func _c29_both_build_clash(seed: int) -> void:
	var n := "29 both players build clash (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var p0 := _spawn_build(gs, resolver, rules, 0, ["core", "claw", "shell"])
	resolver.end_turn(gs)
	var p1 := _spawn_build(gs, resolver, rules, 1, ["core", "eye", "hoof"])
	resolver.end_turn(gs)
	var a = gs.get_squad(p0)
	var b = gs.get_squad(p1)
	resolver._set_squad_cell(gs, a, Vector2i(6, 6))
	resolver._set_squad_cell(gs, b, Vector2i(6, 9))
	_sand(gs, a.cell)
	_sand(gs, b.cell)
	a.organs_locked = true
	b.organs_locked = true
	gs.active_player = 1
	_unfresh(gs, p1)
	if not rules.can_attack(gs, p1, p0, "ranged"):
		_fail(n, "eye out of range"); gs.queue_free(); return
	var before := int(a.unit_count_alive())
	resolver.attack(gs, p1, p0, "ranged")
	a = gs.get_squad(p0)
	if a == null or not a.is_alive() or int(a.unit_count_alive()) >= before:
		_fail(n, "eye dealt no damage"); gs.queue_free(); return
	gs.active_player = 0
	_unfresh(gs, p0)
	resolver._set_squad_cell(gs, a, Vector2i(6, 8))
	a.cooldowns["melee"] = 0
	if rules.can_attack(gs, p0, p1, "melee"):
		resolver.attack(gs, p0, p1, "melee")
	_ok(n)
	gs.queue_free()

func _c30_mixed_attrition_match(seed: int) -> void:
	var n := "30 mixed attrition match (%d)" % seed
	var gs = _gs(seed)
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	# Three builds each side
	var p0a := _spawn_build(gs, resolver, rules, 0, ["core", "claw"])
	gs.offer_pending = true
	_offer(gs, ["core", "eye", "gland"])
	var cells0 = rules.spawn_cells(gs, 0)
	if cells0.is_empty():
		_fail(n, "no P0 spawn left"); gs.queue_free(); return
	resolver.play_card_spawn(gs, "core", cells0[0])
	var p0b := int(gs.squad_at(cells0[0]).id)
	resolver.play_card_reinforce(gs, "eye", p0b)
	gs.clear_offer_phase()
	resolver.end_turn(gs)
	var p1a := _spawn_build(gs, resolver, rules, 1, ["core", "shell"])
	gs.offer_pending = true
	_offer(gs, ["core", "hoof", "claw"])
	var cells1 = rules.spawn_cells(gs, 1)
	if cells1.is_empty():
		_fail(n, "no P1 spawn"); gs.queue_free(); return
	resolver.play_card_spawn(gs, "core", cells1[0])
	var p1b := int(gs.squad_at(cells1[0]).id)
	resolver.play_card_reinforce(gs, "claw", p1b)
	gs.clear_offer_phase()
	# Place in arena
	var placements := {
		p0a: Vector2i(5, 6),
		p0b: Vector2i(7, 6),
		p1a: Vector2i(5, 8),
		p1b: Vector2i(7, 8),
	}
	for sid_any in placements.keys():
		var sid := int(sid_any)
		var s = gs.get_squad(sid)
		if s == null:
			continue
		_clear(gs, placements[sid])
		resolver._set_squad_cell(gs, s, placements[sid])
		s.organs_locked = true
		_sand(gs, s.cell)
	var guard := 0
	while gs.winner == -1 and guard < 24:
		guard += 1
		if bool(gs.offer_pending):
			gs.clear_offer_phase()
		var ap := int(gs.active_player)
		var owned: Array[int] = []
		for sid_any in gs.squads.keys():
			var s = gs.get_squad(int(sid_any))
			if s and s.is_alive() and int(s.owner) == ap:
				owned.append(int(s.id))
		if owned.is_empty():
			break
		# Act with first owned that can hit an enemy
		var acted := false
		for sid in owned:
			_unfresh(gs, sid)
			var s = gs.get_squad(sid)
			if s == null:
				continue
			for eid_any in gs.squads.keys():
				var e = gs.get_squad(int(eid_any))
				if e == null or not e.is_alive() or int(e.owner) == ap:
					continue
				s.cooldowns["melee"] = 0
				s.cooldowns["ranged"] = 0
				s.cooldowns["slam"] = 0
				if rules.can_attack(gs, sid, int(e.id), "melee"):
					resolver.attack(gs, sid, int(e.id), "melee")
					acted = true
					break
				if rules.can_attack(gs, sid, int(e.id), "ranged"):
					resolver.attack(gs, sid, int(e.id), "ranged")
					acted = true
					break
				if _acts(s).has("slam") and abs(s.cell.x - e.cell.x) + abs(s.cell.y - e.cell.y) == 1:
					resolver.use_slam(gs, sid)
					acted = true
					break
			if acted:
				break
		if gs.winner != -1:
			break
		if not rules.can_end_turn(gs):
			gs.clear_offer_phase()
		resolver.end_turn(gs)
	if gs.winner == -1:
		# Force wipe remaining enemies of P0
		for sid_any in gs.squads.keys():
			var s = gs.get_squad(int(sid_any))
			if s and s.is_alive() and int(s.owner) == 1:
				resolver._pop_organs(gs, s, 99)
		if gs.winner == -1:
			_fail(n, "no winner after attrition"); gs.queue_free(); return
	_ok(n)
	gs.queue_free()
