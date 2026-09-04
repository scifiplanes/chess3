extends SceneTree

## Headless player-style playtest for Chess 3 organ rules.
## Run: godot --headless --path . --script res://tools/playtest_chess3.gd

const GameStateScript = preload("res://src/sim/GameState.gd")
const ResolverScript = preload("res://src/sim/Resolver.gd")
const RulesScript = preload("res://src/sim/Rules.gd")
const UnitDefsScript = preload("res://src/sim/UnitDefs.gd")
const UnitStateScript = preload("res://src/sim/UnitState.gd")

var _fails: Array[String] = []
var _passes: int = 0

func _init() -> void:
	print("=== Chess 3 playtest ===")
	_case_boot_and_seed()
	_case_attach_in_spawn()
	_case_attach_rejected_when_locked()
	_case_return_to_spawn_stays_locked()
	_case_move_within_spawn_no_lock()
	_case_hard_max_organs()
	_case_ability_union()
	_case_damage_pops_organs()
	_case_duplicate_organ_damage()
	_case_offer_attach_vs_spawn()
	_case_fresh_cannot_act()
	_case_elimination_win()
	_case_cp_attach_illegal()
	_case_cp_not_marked_as_ra()
	_case_duplicate_melee_uses_best_def()
	_case_multi_gene_offer()
	_case_spawn_egress_clear()
	_case_mutant_organ_hp()
	_case_mutant_bonus_ability()
	_case_full_organ_roster()
	_case_plate_two_hp()
	_case_play_card_mutant_spawn()
	_case_offer_mutants_turn1_guarantee()
	_case_opening_teaching_hand()
	_case_destroy_hero_prop()
	_case_board_spawns_gear_and_eggs()
	_case_pickup_gear_field_attach()
	_case_drop_gear_repickup()
	_case_core_brood_not_reclaimable_gear()
	_case_egg_attaches_curse()
	_case_curse_debuffs()
	print("=== results: %d pass, %d fail ===" % [_passes, _fails.size()])
	for f in _fails:
		print("FAIL: ", f)
	quit(1 if _fails.size() > 0 else 0)

func _ok(name: String) -> void:
	_passes += 1
	print("PASS: ", name)

func _fail(name: String, detail: String) -> void:
	_fails.append("%s — %s" % [name, detail])
	print("FAIL: ", name, " — ", detail)

func _offer_cards(gs, ids: Array) -> void:
	gs.offer_cards.clear()
	for id in ids:
		gs.offer_cards.append(str(id))

func _fresh_gs(p_seed: int = 42):
	var gs = GameStateScript.new()
	root.add_child(gs)
	gs.setup(GameStateScript.DEFAULT_BOARD_SIZE, p_seed)
	gs.squads.clear()
	gs._next_squad_id = 1
	gs.winner = -1
	gs.offer_pending = true
	gs.active_player = 0
	gs.turn_number = 1
	return gs

func _leave_spawn(gs, resolver, rules, sid: int) -> bool:
	var s = gs.get_squad(sid)
	if s == null:
		return false
	s.fresh_turn = -1
	s.moved_turn = -1
	gs.offer_pending = false
	# Prefer a legal move out of spawn; fall back to forced cell set.
	for y in range(0, int(gs.board.size.y)):
		for x in range(0, int(gs.board.size.x)):
			var c := Vector2i(x, y)
			if not rules.can_move(gs, sid, c):
				continue
			if rules.is_spawn_pool_cell(gs, c, int(s.owner)):
				continue
			resolver.move_squad(gs, sid, c)
			return bool(gs.get_squad(sid).organs_locked)
	resolver._set_squad_cell(gs, s, Vector2i(s.cell.x, mini(s.cell.y + 3, int(gs.board.size.y) - 1)))
	return bool(s.organs_locked)

func _case_boot_and_seed() -> void:
	var name := "boot+gene pool"
	var gs = _fresh_gs()
	var inv: Dictionary = gs.player_inventory.get(0, {})
	for id in UnitDefsScript.all_gene_ids():
		if UnitDefsScript.is_curse_organ(id):
			continue
		if int(inv.get(id, 0)) <= 0:
			_fail(name, "missing gene %s in pool" % id)
			gs.queue_free()
			return
	if UnitDefsScript.all_gene_ids().size() != 24:
		_fail(name, "expected 24 genes, got %d" % UnitDefsScript.all_gene_ids().size())
		gs.queue_free()
		return
	for bad in ["soldier", "ninja"]:
		if inv.has(bad):
			_fail(name, "legacy unit %s still in gene pool" % bad)
			gs.queue_free()
			return
	_ok(name)
	gs.queue_free()

func _case_attach_in_spawn() -> void:
	var name := "attach in Spawn Pool"
	var gs = _fresh_gs()
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var sid := gs.add_squad(0, Vector2i(2, 0), "core", 1)
	gs.player_inventory[0]["claw"] = 3
	gs.offer_pending = true
	_offer_cards(gs, ["claw", "eye", "hoof"])
	if not rules.can_play_card_reinforce(gs, "claw", sid):
		_fail(name, "can_play_card_reinforce false for unlocked spawn mutant")
		gs.queue_free()
		return
	resolver.play_card_reinforce(gs, "claw", sid)
	var s = gs.get_squad(sid)
	if int(s.unit_count_alive()) != 2:
		_fail(name, "expected 2 organs after attach, got %d" % s.unit_count_alive())
		gs.queue_free()
		return
	if gs.offer_cards.size() != 2:
		_fail(name, "expected 2 remaining offer cards, got %s" % str(gs.offer_cards))
		gs.queue_free()
		return
	_ok(name)
	gs.queue_free()

func _case_attach_rejected_when_locked() -> void:
	var name := "attach rejected after leave Spawn Pool"
	var gs = _fresh_gs()
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var sid := gs.add_squad(0, Vector2i(2, 0), "core", 1)
	if not _leave_spawn(gs, resolver, rules, sid):
		_fail(name, "failed to leave spawn / lock")
		gs.queue_free()
		return
	var s = gs.get_squad(sid)
	gs.player_inventory[0]["claw"] = 2
	gs.offer_pending = true
	_offer_cards(gs, ["claw", "eye", "hoof"])
	if rules.can_play_card_reinforce(gs, "claw", sid):
		_fail(name, "attach still legal after lock")
		gs.queue_free()
		return
	var before := int(s.unit_count_alive())
	resolver.play_card_reinforce(gs, "claw", sid)
	s = gs.get_squad(sid)
	if int(s.unit_count_alive()) != before:
		_fail(name, "attach mutated locked mutant")
		gs.queue_free()
		return
	_ok(name)
	gs.queue_free()

func _case_return_to_spawn_stays_locked() -> void:
	var name := "return to Spawn Pool stays locked"
	var gs = _fresh_gs()
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var sid := gs.add_squad(0, Vector2i(2, 0), "core", 1)
	if not _leave_spawn(gs, resolver, rules, sid):
		_fail(name, "failed to leave spawn / lock")
		gs.queue_free()
		return
	var s = gs.get_squad(sid)
	s.cell = Vector2i(2, 0) # return without clearing lock
	if not bool(s.organs_locked):
		_fail(name, "lock cleared after returning to spawn")
		gs.queue_free()
		return
	gs.player_inventory[0]["claw"] = 2
	gs.offer_pending = true
	_offer_cards(gs, ["claw", "eye", "hoof"])
	if rules.can_play_card_reinforce(gs, "claw", sid):
		_fail(name, "attach became legal after return")
		gs.queue_free()
		return
	_ok(name)
	gs.queue_free()

func _case_move_within_spawn_no_lock() -> void:
	var name := "move within Spawn Pool does not lock"
	var gs = _fresh_gs()
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var sid := gs.add_squad(0, Vector2i(2, 0), "core", 1)
	var s = gs.get_squad(sid)
	s.fresh_turn = -1
	gs.offer_pending = false
	if not rules.can_move(gs, sid, Vector2i(2, 1)):
		_fail(name, "expected can_move to (2,1)")
		gs.queue_free()
		return
	resolver.move_squad(gs, sid, Vector2i(2, 1))
	s = gs.get_squad(sid)
	if bool(s.organs_locked) or not rules.is_spawn_pool_cell(gs, s.cell, 0):
		_fail(name, "locked or left spawn unexpectedly cell=%s locked=%s" % [str(s.cell), str(s.organs_locked)])
		gs.queue_free()
		return
	_ok(name)
	gs.queue_free()

func _case_hard_max_organs() -> void:
	var name := "hard max 10 organs"
	var gs = _fresh_gs()
	var rules = RulesScript.new()
	var sid := gs.add_squad(0, Vector2i(3, 0), "core", 1)
	var s = gs.get_squad(sid)
	for i in range(9):
		s.units.append(UnitStateScript.new("claw", 1, 1))
	if int(s.unit_count_alive()) != 10:
		_fail(name, "setup expected 10 organs")
		gs.queue_free()
		return
	if rules.can_add_unit_to_squad(s, "eye"):
		_fail(name, "can_add true at hard max")
		gs.queue_free()
		return
	gs.offer_pending = true
	_offer_cards(gs, ["eye", "claw", "hoof"])
	gs.player_inventory[0]["eye"] = 2
	if rules.can_play_card_reinforce(gs, "eye", sid):
		_fail(name, "attach legal at hard max")
		gs.queue_free()
		return
	_ok(name)
	gs.queue_free()

func _case_ability_union() -> void:
	var name := "ability union from organs"
	var gs = _fresh_gs()
	var sid := gs.add_squad(0, Vector2i(4, 0), "core", 1)
	var s = gs.get_squad(sid)
	s.units.append(UnitStateScript.new("claw", 1, 1))
	s.units.append(UnitStateScript.new("eye", 1, 1))
	s.units.append(UnitStateScript.new("hoof", 1, 1))
	var ids: Array[String] = UnitDefsScript.list_action_ids_for_squad(s)
	for need in ["melee", "dash", "ranged", "run"]:
		if not ids.has(need):
			_fail(name, "missing action %s in union %s" % [need, str(ids)])
			gs.queue_free()
			return
	_ok(name)
	gs.queue_free()

func _case_damage_pops_organs() -> void:
	var name := "damage pops N organs"
	var gs = _fresh_gs()
	var resolver = ResolverScript.new()
	var sid_a := gs.add_squad(0, Vector2i(1, 0), "claw", 1)
	var sid_d := gs.add_squad(1, Vector2i(1, 1), "core", 1)
	var d = gs.get_squad(sid_d)
	for _i in range(3):
		d.units.append(UnitStateScript.new("shell", 1, 1))
	var a = gs.get_squad(sid_a)
	a.fresh_turn = -1
	d.fresh_turn = -1
	gs.offer_pending = false
	gs.active_player = 0
	a.cell = Vector2i(1, 2)
	d.cell = Vector2i(1, 1)
	var before := int(d.unit_count_alive())
	if not resolver.rules.can_attack(gs, sid_a, sid_d, "melee"):
		_fail(name, "melee not legal (setup)")
		gs.queue_free()
		return
	var pred = resolver.predict_attack_damage(gs, sid_a, sid_d, "melee")
	var loss := int(pred.get("hp_loss", 0))
	resolver.attack(gs, sid_a, sid_d, "melee")
	d = gs.get_squad(sid_d)
	var after := int(d.unit_count_alive())
	if before - after != loss and not (after == 0 and loss >= before):
		_fail(name, "expected pop %d from %d -> got %d (alive after=%d)" % [loss, before, before - after, after])
		gs.queue_free()
		return
	while d.is_alive():
		resolver._pop_organs(gs, d, 99)
	if d.is_alive():
		_fail(name, "mutant still alive with 0 organs")
		gs.queue_free()
		return
	_ok(name)
	gs.queue_free()

func _case_duplicate_organ_damage() -> void:
	var name := "duplicate organs pop front-first per damage"
	var gs = _fresh_gs()
	var resolver = ResolverScript.new()
	var sid := gs.add_squad(0, Vector2i(2, 2), "claw", 1)
	var s = gs.get_squad(sid)
	for _i in range(3):
		s.units.append(UnitStateScript.new("claw", 1, 1))
	if int(s.unit_count_alive()) != 4:
		_fail(name, "setup expected 4 claws, got %d" % int(s.unit_count_alive()))
		gs.queue_free()
		return
	resolver._apply_organ_damage(gs, s, 3)
	if int(s.unit_count_alive()) != 1:
		_fail(name, "3 damage should leave 1 claw, got %d" % int(s.unit_count_alive()))
		gs.queue_free()
		return
	var front = s.front_unit()
	if front == null or str(front.unit_def_id) != "claw" or int(front.hp) != 1:
		_fail(name, "survivor should be front claw at 1hp")
		gs.queue_free()
		return
	_ok(name)
	gs.queue_free()

func _case_offer_attach_vs_spawn() -> void:
	var name := "offer playability spawn+attach"
	var gs = _fresh_gs()
	var rules = RulesScript.new()
	var sid := gs.add_squad(0, Vector2i(5, 0), "core", 1)
	gs.player_inventory[0] = {"claw": 2, "eye": 2}
	gs.offer_pending = true
	_offer_cards(gs, ["claw", "eye", "hoof"])
	if not gs._offer_is_playable_now(0, "claw"):
		_fail(name, "claw not playable with unlocked spawn mutant")
		gs.queue_free()
		return
	var cells = rules.spawn_cells(gs, 0)
	if cells.is_empty():
		_fail(name, "no spawn cells")
		gs.queue_free()
		return
	var s = gs.get_squad(sid)
	s.organs_locked = true
	s.cell = Vector2i(5, 5)
	if rules.can_play_card_reinforce(gs, "claw", sid):
		_fail(name, "attach playable on locked/out-of-pool mutant")
		gs.queue_free()
		return
	if not rules.can_play_card_spawn(gs, "claw", cells[0]):
		_fail(name, "spawn should still be legal")
		gs.queue_free()
		return
	_ok(name)
	gs.queue_free()

func _case_fresh_cannot_act() -> void:
	var name := "fresh mutant cannot move"
	var gs = _fresh_gs()
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	gs.offer_pending = true
	gs.player_inventory[0]["core"] = 5
	_offer_cards(gs, ["core", "claw", "eye"])
	var cells = rules.spawn_cells(gs, 0)
	if cells.is_empty():
		_fail(name, "no spawn cells")
		gs.queue_free()
		return
	resolver.play_card_spawn(gs, "core", cells[0])
	var s = gs.squad_at(cells[0])
	if s == null:
		_fail(name, "spawn did not create mutant")
		gs.queue_free()
		return
	if int(s.fresh_turn) != int(gs.turn_number):
		_fail(name, "fresh_turn not set")
		gs.queue_free()
		return
	var moved := false
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var to: Vector2i = s.cell + d
		if rules.can_move(gs, s.id, to):
			moved = true
			break
	if moved:
		_fail(name, "fresh mutant can move")
		gs.queue_free()
		return
	_ok(name)
	gs.queue_free()

func _case_elimination_win() -> void:
	var name := "elimination when organs depleted"
	var gs = _fresh_gs()
	var resolver = ResolverScript.new()
	gs.add_squad(0, Vector2i(2, 0), "core", 1)
	var b := gs.add_squad(1, Vector2i(2, 1), "core", 1)
	var enemy = gs.get_squad(b)
	resolver._pop_organs(gs, enemy, 1)
	if gs.winner != 0:
		_fail(name, "expected P1 win after enemy organs gone, winner=%d" % gs.winner)
		gs.queue_free()
		return
	_ok(name)
	gs.queue_free()

func _case_cp_attach_illegal() -> void:
	var name := "CP is not attach zone"
	var gs = _fresh_gs()
	var rules = RulesScript.new()
	var cell := Vector2i(7, 7)
	if gs.board.control_points.size() > 0:
		cell = gs.board.control_points[0].cell
	var sid := gs.add_squad(0, cell, "core", 1)
	var s = gs.get_squad(sid)
	if rules.is_spawn_pool_cell(gs, s.cell, 0):
		s.cell = Vector2i(7, 7)
	s.organs_locked = false
	gs.offer_pending = true
	_offer_cards(gs, ["claw", "eye", "hoof"])
	gs.player_inventory[0]["claw"] = 2
	if rules.can_play_card_reinforce(gs, "claw", sid):
		_fail(name, "attach legal on CP/midboard cell %s" % str(s.cell))
		gs.queue_free()
		return
	_ok(name)
	gs.queue_free()

func _case_cp_not_marked_as_ra() -> void:
	var name := "CP cells not board RA markers"
	var gs = _fresh_gs()
	if gs.board.control_points.is_empty():
		_fail(name, "no CPs")
		gs.queue_free()
		return
	var cp = gs.board.control_points[0].cell
	if gs.board.is_reinforcement_area(cp):
		_fail(name, "CP %s still marked reinforcement_area (yellow ring)" % str(cp))
		gs.queue_free()
		return
	_ok(name)
	gs.queue_free()

func _case_duplicate_melee_uses_best_def() -> void:
	var name := "duplicate action uses strongest organ def"
	var gs = _fresh_gs()
	var sid := gs.add_squad(0, Vector2i(4, 0), "core", 1) # melee dmg 2
	var s = gs.get_squad(sid)
	s.units.append(UnitStateScript.new("claw", 1, 1)) # melee dmg 2
	var ad = UnitDefsScript.action_def_for_squad(s, "melee")
	if int(ad.get("damage", 0)) != 2:
		_fail(name, "expected best claw melee dmg 2, got %s" % str(ad.get("damage")))
		gs.queue_free()
		return
	# Reorder core to front — still claw stats
	var core = s.units[0]
	s.units.remove_at(0)
	s.units.append(core)
	ad = UnitDefsScript.action_def_for_squad(s, "melee")
	if int(ad.get("damage", 0)) != 2:
		_fail(name, "front reorder changed melee power unexpectedly: %s" % str(ad.get("damage")))
		gs.queue_free()
		return
	_ok(name)
	gs.queue_free()

func _case_multi_gene_offer() -> void:
	var name := "multi gene spend in one offer"
	var gs = _fresh_gs()
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	gs.player_inventory[0] = {"core": 5, "claw": 5, "eye": 5}
	gs.offer_pending = true
	gs.offer_picks_remaining = 3
	_offer_cards(gs, ["core", "claw", "eye"])
	var cells = rules.spawn_cells(gs, 0)
	if cells.is_empty():
		_fail(name, "no spawn cells")
		gs.queue_free()
		return
	resolver.play_card_spawn(gs, "core", cells[0])
	if not bool(gs.offer_pending):
		_fail(name, "offer cleared after first spawn; remaining=%s" % str(gs.offer_cards))
		gs.queue_free()
		return
	if gs.offer_cards.size() != 2:
		_fail(name, "expected 2 offer cards left, got %s" % str(gs.offer_cards))
		gs.queue_free()
		return
	var mutant = gs.squad_at(cells[0])
	if mutant == null:
		_fail(name, "spawn missing")
		gs.queue_free()
		return
	resolver.play_card_reinforce(gs, "claw", int(mutant.id))
	if int(mutant.unit_count_alive()) != 2:
		_fail(name, "attach failed in continued offer")
		gs.queue_free()
		return
	if not bool(gs.offer_pending) or gs.offer_cards.size() != 1:
		_fail(name, "offer should still have eye, pending=%s cards=%s" % [str(gs.offer_pending), str(gs.offer_cards)])
		gs.queue_free()
		return
	resolver.play_card_reinforce(gs, "eye", int(mutant.id))
	if bool(gs.offer_pending) or not gs.offer_cards.is_empty():
		_fail(name, "offer should end after last gene")
		gs.queue_free()
		return
	if int(mutant.unit_count_alive()) != 3:
		_fail(name, "expected 3 organs after full offer spend")
		gs.queue_free()
		return
	_ok(name)
	gs.queue_free()

func _case_mutant_organ_hp() -> void:
	var name := "mutant organ chips then pops"
	var gs = _fresh_gs()
	var resolver = ResolverScript.new()
	var sid := gs.add_squad(0, Vector2i(3, 0), "shell", 2, true)
	var s = gs.get_squad(sid)
	var u = s.units[0]
	if not bool(u.is_mutant) or int(u.hp) != 2:
		_fail(name, "setup expected 2hp mutant organ")
		gs.queue_free()
		return
	resolver._apply_organ_damage(gs, s, 1)
	if int(s.unit_count_alive()) != 1 or int(u.hp) != 1:
		_fail(name, "first damage should chip to 1hp, alive=%d hp=%d" % [int(s.unit_count_alive()), int(u.hp)])
		gs.queue_free()
		return
	resolver._apply_organ_damage(gs, s, 1)
	if s.is_alive():
		_fail(name, "second damage should pop mutant organ")
		gs.queue_free()
		return
	_ok(name)
	gs.queue_free()

func _case_mutant_bonus_ability() -> void:
	var name := "mutant organ grants bonus ability"
	var gs = _fresh_gs()
	var sid := gs.add_squad(0, Vector2i(3, 0), "core", 2, true)
	var s = gs.get_squad(sid)
	var ids: Array[String] = UnitDefsScript.list_action_ids_for_squad(s)
	if not ids.has("slam"):
		_fail(name, "mutant core missing bonus slam, got %s" % str(ids))
		gs.queue_free()
		return
	_ok(name)
	gs.queue_free()

func _case_full_organ_roster() -> void:
	var name := "full organ roster abilities wired"
	var gs = _fresh_gs()
	var checks := {
		"hoof": "run",
		"claw": "dash",
		"shell": "slam",
		"ram": "charge",
		"node": "powerstrike",
		"vent": "eruption",
		"spine": "railgun",
		"spring": "jump",
		"leap": "pounce",
		"synapse": "switch",
		"phase": "blink",
		"beacon": "airstrike",
		"spore": "mine",
		"pod": "big_mine",
		"gland": "snare",
	}
	for organ_id in checks.keys():
		var sid := gs.add_squad(0, Vector2i(2, 0), str(organ_id), UnitDefsScript.max_hp_for(str(organ_id), false))
		var s = gs.get_squad(sid)
		var want := str(checks[organ_id])
		if not UnitDefsScript.list_action_ids_for_squad(s).has(want):
			_fail(name, "%s missing %s, got %s" % [organ_id, want, str(UnitDefsScript.list_action_ids_for_squad(s))])
			gs.queue_free()
			return
		gs.squads.erase(sid)
	var brood_sid := gs.add_squad(0, Vector2i(2, 0), "brood", 1)
	var anchor_sid := gs.add_squad(0, Vector2i(4, 0), "anchor", 1)
	if not UnitDefsScript.unit_tags("brood").has("logistics"):
		_fail(name, "brood missing logistics tag"); gs.queue_free(); return
	if not UnitDefsScript.unit_tags("anchor").has("fob"):
		_fail(name, "anchor missing fob tag"); gs.queue_free(); return
	_ok(name)
	gs.queue_free()

func _case_plate_two_hp() -> void:
	var name := "plate organ has 4 hp"
	var gs = _fresh_gs()
	var resolver = ResolverScript.new()
	var sid := gs.add_squad(0, Vector2i(2, 0), "plate", UnitDefsScript.max_hp_for("plate", false))
	var s = gs.get_squad(sid)
	if int(s.units[0].hp) != 4:
		_fail(name, "expected plate 4hp, got %d" % int(s.units[0].hp))
		gs.queue_free()
		return
	resolver._apply_organ_damage(gs, s, 1)
	if not s.is_alive() or int(s.units[0].hp) != 3:
		_fail(name, "plate should chip to 3hp")
		gs.queue_free()
		return
	resolver._apply_organ_damage(gs, s, 1)
	if not s.is_alive() or int(s.units[0].hp) != 2:
		_fail(name, "plate should chip to 2hp")
		gs.queue_free()
		return
	resolver._apply_organ_damage(gs, s, 1)
	if not s.is_alive() or int(s.units[0].hp) != 1:
		_fail(name, "plate should chip to 1hp")
		gs.queue_free()
		return
	resolver._apply_organ_damage(gs, s, 1)
	if s.is_alive():
		_fail(name, "plate should pop on fourth chip")
		gs.queue_free()
		return
	_ok(name)
	gs.queue_free()

func _case_play_card_mutant_spawn() -> void:
	var name := "play_card_spawn creates mutant organ"
	var gs = _fresh_gs()
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	gs.offer_pending = true
	_offer_cards(gs, ["claw"])
	gs.offer_mutants.clear()
	gs.offer_mutants.append(true)
	gs.player_inventory[0]["claw"] = 1
	var cells: Array[Vector2i] = rules.spawn_cells(gs, 0)
	if cells.is_empty():
		_fail(name, "no spawn cells")
		gs.queue_free()
		return
	resolver.play_card_spawn(gs, "claw", cells[0], true, 0)
	var s = gs.squad_at(cells[0])
	if s == null:
		_fail(name, "no squad spawned")
		gs.queue_free()
		return
	var u = s.units[0]
	if not bool(u.is_mutant) or int(u.hp) != 2:
		_fail(name, "expected 2hp mutant claw, mutant=%s hp=%d" % [str(u.is_mutant), int(u.hp)])
		gs.queue_free()
		return
	_ok(name)
	gs.queue_free()

func _case_offer_mutants_turn1_guarantee() -> void:
	var name := "turn 1 offer guarantees one mutant when possible"
	var gs = _fresh_gs(99)
	gs.start_offer_phase()
	var any := false
	for i in range(gs.offer_mutants.size()):
		if bool(gs.offer_mutants[i]):
			any = true
			break
	if not any:
		_fail(name, "no mutant in turn-1 hand mut=%s cards=%s" % [str(gs.offer_mutants), str(gs.offer_cards)])
		gs.queue_free()
		return
	_ok(name)
	gs.queue_free()

func _case_opening_teaching_hand() -> void:
	var name := "opening hand teaches core + combat"
	for seed in [7, 99, 5000, 5097]:
		var gs = _fresh_gs(seed)
		gs.apply_seed_first_player()
		if gs.offer_cards.size() != 5:
			_fail(name, "seed %d turn1 need 5 got %d" % [seed, gs.offer_cards.size()])
			gs.queue_free()
			return
		if not gs.offer_cards.has("core"):
			_fail(name, "seed %d missing core in %s" % [seed, str(gs.offer_cards)])
			gs.queue_free()
			return
		var combat := false
		for c in ["claw", "eye", "hoof"]:
			if gs.offer_cards.has(c):
				combat = true
				break
		if not combat:
			_fail(name, "seed %d missing combat gene in %s" % [seed, str(gs.offer_cards)])
			gs.queue_free()
			return
		# Second seat opening (turn 2) also 5 + teaching.
		gs.clear_offer_phase()
		var resolver = ResolverScript.new()
		# Skip without playing so inventory stays full; advance via end_turn path.
		gs.offer_pending = false
		resolver.end_turn(gs)
		if int(gs.turn_number) != 2 or gs.offer_cards.size() != 5:
			_fail(name, "seed %d turn2 hand size %d (turn=%d)" % [seed, gs.offer_cards.size(), gs.turn_number])
			gs.queue_free()
			return
		if not gs.offer_cards.has("core"):
			_fail(name, "seed %d turn2 missing core in %s" % [seed, str(gs.offer_cards)])
			gs.queue_free()
			return
		gs.queue_free()
	_ok(name)

func _case_destroy_hero_prop() -> void:
	var name := "destroy hero prop leaves path + clears hero entry"
	var gs = _fresh_gs()
	var resolver = ResolverScript.new()
	var rules = RulesScript.new()
	var prop_cell := Vector2i(6, 6)
	gs.board.add_obstacle(prop_cell, 5, true, "blob")
	gs.board.hero_props.append({"cell": prop_cell, "kind": "blob", "variant": 1})
	var sid := gs.add_squad(0, Vector2i(6, 5), "claw", 1)
	var a = gs.get_squad(sid)
	a.fresh_turn = -1
	gs.offer_pending = false
	gs.active_player = 0
	if not rules.can_attack_obstacle(gs, sid, prop_cell, "melee"):
		_fail(name, "melee cannot target destructible prop")
		gs.queue_free()
		return
	while gs.board.is_blocked(prop_cell) and int(gs.board.obstacle_hp(prop_cell)) > 0:
		resolver.attack_obstacle(gs, sid, prop_cell, "melee")
		a = gs.get_squad(sid)
		if a != null:
			a.cooldowns["melee"] = 0
	if gs.board.is_blocked(prop_cell):
		_fail(name, "prop still blocked after damage")
		gs.queue_free()
		return
	for hp_any in gs.board.hero_props:
		var hp: Dictionary = hp_any
		if hp.get("cell", Vector2i(-1, -1)) == prop_cell:
			_fail(name, "hero_props still lists destroyed cell")
			gs.queue_free()
			return
	_ok(name)
	gs.queue_free()

func _case_spawn_egress_clear() -> void:
	var name := "spawn egress row obstacle-free"
	var gs = _fresh_gs(42)
	var rules = RulesScript.new()
	var egress_y := int(RulesScript.HOME_SPAWN_ROWS) # first row outside P0 pool
	for x in range(0, int(gs.board.size.x)):
		var c := Vector2i(x, egress_y)
		if gs.board.is_blocked(c):
			_fail(name, "egress cell blocked at %s (seed 42)" % str(c))
			gs.queue_free()
			return
	# From a spawn cell, at least one orthogonal step out of pool should be movable after clearing fresh.
	var sid := gs.add_squad(0, Vector2i(2, 0), "core", 1)
	var s = gs.get_squad(sid)
	s.fresh_turn = -1
	gs.offer_pending = false
	var exit_ok := false
	for d in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0)]:
		var to: Vector2i = s.cell + d
		if not rules.is_spawn_pool_cell(gs, to, 0) and rules.can_move(gs, sid, to):
			exit_ok = true
			break
	# (2,1) is still in pool; from (2,1) to (2,2) should work with egress clear
	if rules.can_move(gs, sid, Vector2i(2, 1)):
		ResolverScript.new().move_squad(gs, sid, Vector2i(2, 1))
		s = gs.get_squad(sid)
		s.moved_turn = -1
		gs.turn_number = 2
		s.fresh_turn = -1
		if rules.can_move(gs, sid, Vector2i(2, 2)):
			exit_ok = true
	if not exit_ok:
		_fail(name, "could not step out of spawn via egress")
		gs.queue_free()
		return
	_ok(name)
	gs.queue_free()

func _find_gear_cell(gs) -> Vector2i:
	for c in gs.board.gear.keys():
		return c
	return Vector2i(-1, -1)

func _find_egg_with(gs, unit_def_id: String) -> Vector2i:
	for c in gs.board.eggs.keys():
		var e = gs.board.egg_at(c)
		if e != null and str(e.get("unit_def_id", "")) == unit_def_id:
			return c
	return Vector2i(-1, -1)

func _step_squad_to(gs, resolver, sid: int, to: Vector2i) -> void:
	var s = gs.get_squad(sid)
	if s == null:
		return
	s.fresh_turn = -1
	s.moved_turn = -1
	gs.offer_pending = false
	if s.cell == to:
		resolver._try_pickups_at_cell(gs, s)
		return
	if RulesScript.new().can_move(gs, sid, to):
		resolver.move_squad(gs, sid, to)
		return
	# Path unavailable in one step — warp adjacent then step onto pickup.
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var adj: Vector2i = to + d
		if not gs.board.in_bounds(adj) or gs.board.is_blocked(adj):
			continue
		if gs.squad_at(adj) != null and gs.squad_at(adj) != s:
			continue
		resolver._set_squad_cell(gs, s, adj)
		s.organs_locked = true
		s.moved_turn = -1
		if RulesScript.new().can_move(gs, sid, to):
			resolver.move_squad(gs, sid, to)
			return
	resolver._set_squad_cell(gs, s, to)
	resolver._try_pickups_at_cell(gs, s)

func _case_board_spawns_gear_and_eggs() -> void:
	var name := "board spawns gear and eggs"
	var gs = _fresh_gs(42)
	if gs.board.gear.is_empty():
		_fail(name, "no gear spawned (seed 42)")
		gs.queue_free()
		return
	if gs.board.eggs.is_empty():
		_fail(name, "no eggs spawned (seed 42)")
		gs.queue_free()
		return
	_ok(name)
	gs.queue_free()

func _case_pickup_gear_field_attach() -> void:
	var name := "pickup gear bypasses attach lock"
	var gs = _fresh_gs(42)
	var resolver = ResolverScript.new()
	var gear_cell := _find_gear_cell(gs)
	if gear_cell.x < 0:
		_fail(name, "no gear on board")
		gs.queue_free()
		return
	var gear = gs.board.gear_at(gear_cell)
	var gid := str(gear.get("unit_def_id", ""))
	var sid := gs.add_squad(0, Vector2i(2, 0), "core", 1)
	_leave_spawn(gs, resolver, RulesScript.new(), sid)
	var before := int(gs.get_squad(sid).unit_count_alive())
	_step_squad_to(gs, resolver, sid, gear_cell)
	var s = gs.get_squad(sid)
	if gs.board.gear.has(gear_cell):
		_fail(name, "gear still on board after pickup")
		gs.queue_free()
		return
	if int(s.unit_count_alive()) != before + 1:
		_fail(name, "organ count not increased after gear pickup")
		gs.queue_free()
		return
	var has := false
	for u in s.units:
		if str(u.unit_def_id) == gid:
			has = true
			break
	if not has:
		_fail(name, "picked up organ %s not in stack" % gid)
		gs.queue_free()
		return
	_ok(name)
	gs.queue_free()

func _case_drop_gear_repickup() -> void:
	var name := "dropped organ becomes gear and re-pickups"
	var gs = _fresh_gs(42)
	var resolver = ResolverScript.new()
	var sid := gs.add_squad(0, Vector2i(2, 0), "claw", 1)
	gs.reinforce_squad(sid, "core", 1)
	_leave_spawn(gs, resolver, RulesScript.new(), sid)
	var s = gs.get_squad(sid)
	var cell: Vector2i = s.cell
	resolver._pop_organs(gs, s, 1)
	if not gs.board.gear.has(cell):
		_fail(name, "no gear dropped at mutant cell after pop")
		gs.queue_free()
		return
	var away: Vector2i = cell + Vector2i(1, 0)
	if not gs.board.in_bounds(away) or gs.board.is_blocked(away) or gs.squad_at(away) != null:
		away = cell + Vector2i(0, 1)
	s.moved_turn = -1
	resolver.move_squad(gs, sid, away)
	s.moved_turn = -1
	var n_before := int(gs.get_squad(sid).unit_count_alive())
	resolver.move_squad(gs, sid, cell)
	if gs.board.gear.has(cell):
		_fail(name, "gear not consumed on re-pickup")
		gs.queue_free()
		return
	if int(gs.get_squad(sid).unit_count_alive()) != n_before + 1:
		_fail(name, "organ count not restored after re-pickup")
		gs.queue_free()
		return
	_ok(name)
	gs.queue_free()

func _case_core_brood_not_reclaimable_gear() -> void:
	var name := "core/brood/curses do not drop as reclaimable gear"
	if UnitDefsScript.is_reclaimable_gear("claw") != true:
		_fail(name, "claw should be reclaimable")
		return
	if UnitDefsScript.is_reclaimable_gear("core"):
		_fail(name, "core must not be reclaimable")
		return
	if UnitDefsScript.is_reclaimable_gear("brood"):
		_fail(name, "brood must not be reclaimable")
		return
	if UnitDefsScript.is_reclaimable_gear("anchor"):
		_fail(name, "anchor must not be reclaimable")
		return
	if UnitDefsScript.is_reclaimable_gear("rot"):
		_fail(name, "curse must not be reclaimable")
		return
	var gs = _fresh_gs(42)
	var resolver = ResolverScript.new()
	var sid := gs.add_squad(0, Vector2i(2, 0), "core", 1)
	gs.reinforce_squad(sid, "claw", 1)
	# Stack after stabilize: [claw, core] — pop claw first (gear), then core (no gear).
	_leave_spawn(gs, resolver, RulesScript.new(), sid)
	var s = gs.get_squad(sid)
	var gear_before := int(gs.board.gear.size())
	resolver._pop_organs(gs, s, 1) # claw → gear
	if int(gs.board.gear.size()) != gear_before + 1:
		_fail(name, "claw should drop gear")
		gs.queue_free()
		return
	var gear_mid := int(gs.board.gear.size())
	resolver._pop_organs(gs, s, 1) # core → no gear
	if int(gs.board.gear.size()) != gear_mid:
		_fail(name, "core must not drop gear")
		gs.queue_free()
		return
	_ok(name)
	gs.queue_free()

func _case_egg_attaches_curse() -> void:
	var name := "egg graft attaches contained organ"
	var gs = _fresh_gs(42)
	var resolver = ResolverScript.new()
	var egg_cell := _find_egg_with(gs, "rot")
	if egg_cell.x < 0:
		for c in gs.board.eggs.keys():
			egg_cell = c
			break
	if egg_cell.x < 0:
		_fail(name, "no egg on board")
		gs.queue_free()
		return
	var egg = gs.board.egg_at(egg_cell)
	var eid := str(egg.get("unit_def_id", ""))
	var sid := gs.add_squad(0, Vector2i(2, 0), "core", 1)
	_leave_spawn(gs, resolver, RulesScript.new(), sid)
	_step_squad_to(gs, resolver, sid, egg_cell)
	if gs.board.eggs.has(egg_cell):
		_fail(name, "egg still on board after step")
		gs.queue_free()
		return
	var s = gs.get_squad(sid)
	var has := false
	for u in s.units:
		if str(u.unit_def_id) == eid:
			has = true
			break
	if not has:
		_fail(name, "egg organ %s not attached" % eid)
		gs.queue_free()
		return
	_ok(name)
	gs.queue_free()

func _case_curse_debuffs() -> void:
	var name := "curse organs apply debuffs"
	var gs = _fresh_gs()
	var rules = RulesScript.new()
	var sid := gs.add_squad(0, Vector2i(2, 0), "core", 1)
	var s = gs.get_squad(sid)
	s.fresh_turn = -1
	var base := rules.move_range_for_squad(gs, s)
	if base < 2:
		_fail(name, "expected spawn-pool move range >= 2 for leech test, got %d" % base)
		gs.queue_free()
		return
	gs.field_attach_organ(sid, "leech", 1)
	var penalized := rules.move_range_for_squad(gs, s)
	if penalized >= base:
		_fail(name, "leech did not reduce move range (%d -> %d)" % [base, penalized])
		gs.queue_free()
		return
	gs.field_attach_organ(sid, "rot", 1)
	if UnitDefsScript.extra_damage_taken(s) < 1:
		_fail(name, "rot did not add fragile damage taken")
		gs.queue_free()
		return
	_ok(name)
	gs.queue_free()
