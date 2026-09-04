extends SceneTree
const GameStateScript = preload("res://src/sim/GameState.gd")
const ResolverScript = preload("res://src/sim/Resolver.gd")
const RulesScript = preload("res://src/sim/Rules.gd")
func _init() -> void:
	var gs = GameStateScript.new()
	root.add_child(gs)
	gs.setup(Vector2i(14,14), 42)
	gs.squads.clear()
	gs._next_squad_id = 1
	gs.offer_pending = false
	var sid = gs.add_squad(0, Vector2i(2,0), "core", 1)
	var s = gs.get_squad(sid)
	s.fresh_turn = -1
	s.moved_turn = -1
	var rules = RulesScript.new()
	var resolver = ResolverScript.new()
	# Step to (2,1) still in pool
	resolver.move_squad(gs, sid, Vector2i(2,1))
	s = gs.get_squad(sid)
	print("step1 cell=", s.cell, " locked=", s.organs_locked)
	# Next turn leave spawn
	gs.turn_number = 2
	s.moved_turn = -1
	s.fresh_turn = -1
	# Find any reachable cell outside spawn
	var found = false
	for y in range(0,14):
		for x in range(0,14):
			var c = Vector2i(x,y)
			if not rules.can_move(gs, sid, c):
				continue
			if rules.is_spawn_pool_cell(gs, c, 0):
				continue
			resolver.move_squad(gs, sid, c)
			s = gs.get_squad(sid)
			print("left to ", s.cell, " locked=", s.organs_locked, " in_spawn=", rules.is_spawn_pool_cell(gs, s.cell, 0))
			found = true
			break
		if found: break
	if not found:
		print("NO exit found from ", s.cell)
		# Force via dash-like set
		resolver._set_squad_cell(gs, s, Vector2i(2,4))
		print("forced cell=", s.cell, " locked=", s.organs_locked)
	# CP attach check
	var cp = gs.board.control_points[0].cell if gs.board.control_points.size()>0 else Vector2i(7,7)
	var sid2 = gs.add_squad(0, cp, "core", 1)
	var s2 = gs.get_squad(sid2)
	s2.organs_locked = false
	gs.offer_pending = true
	gs.offer_cards.clear()
	gs.offer_cards.append("claw")
	gs.player_inventory[0]["claw"] = 3
	print("CP cell", cp, " is_board_RA=", gs.board.is_reinforcement_area(cp), " can_attach=", rules.can_play_card_reinforce(gs, "claw", sid2), " in_spawn=", rules.is_spawn_pool_cell(gs, cp, 0))
	print("board RA count", gs.board.reinforcement_areas.size())
	quit()
