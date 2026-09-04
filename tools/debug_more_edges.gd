extends SceneTree
const GameStateScript = preload("res://src/sim/GameState.gd")
const ResolverScript = preload("res://src/sim/Resolver.gd")
const RulesScript = preload("res://src/sim/Rules.gd")
const UnitStateScript = preload("res://src/sim/UnitState.gd")
func _init() -> void:
	var gs = GameStateScript.new(); root.add_child(gs)
	gs.setup(Vector2i(14,14), 7)
	gs.squads.clear(); gs._next_squad_id=1; gs.offer_pending=false; gs.winner=-1
	var rules = RulesScript.new(); var resolver = ResolverScript.new()
	# Dash out of spawn locks
	var sid = gs.add_squad(0, Vector2i(4,0), "claw", 1)
	var s = gs.get_squad(sid); s.fresh_turn=-1; s.units.append(UnitStateScript.new("hoof",1,1))
	# Find dash landing outside spawn
	var dashed=false
	for y in range(0,14):
		for x in range(0,14):
			var c=Vector2i(x,y)
			if rules.is_spawn_pool_cell(gs,c,0): continue
			resolver.use_dash(gs, sid, c)
			s=gs.get_squad(sid)
			if s.cell==c:
				print("DASH to ",c," locked=",s.organs_locked)
				dashed=true; break
		if dashed: break
	if not dashed:
		print("DASH: no landing found / dash failed; cooldown=", s.cooldowns)
		# force
		resolver._set_squad_cell(gs,s,Vector2i(4,4)); print("forced lock=",s.organs_locked)

	# Snare plant + trigger
	gs2()
	quit()

func gs2():
	var gs = GameStateScript.new(); root.add_child(gs)
	gs.setup(Vector2i(14,14), 9)
	gs.squads.clear(); gs._next_squad_id=1; gs.offer_pending=false
	var resolver = ResolverScript.new()
	var a = gs.add_squad(0, Vector2i(3,3), "gland", 1)
	var b = gs.add_squad(1, Vector2i(5,3), "core", 1)
	var sa=gs.get_squad(a); sa.fresh_turn=-1; sa.cell=Vector2i(3,3)
	var sb=gs.get_squad(b); sb.fresh_turn=-1
	# Give gland snare - plant adjacent
	resolver.plant_hazard(gs, a, Vector2i(4,3), "snare")
	print("hazard at 4,3=", gs.board.hazard_at(Vector2i(4,3)))
	# move enemy onto snare
	sb.moved_turn=-1
	# bypass can_move: set via move if possible
	var rules=RulesScript.new()
	gs.active_player=1
	sb.fresh_turn=-1; sb.moved_turn=-1
	if rules.can_move(gs,b,Vector2i(4,3)):
		resolver.move_squad(gs,b,Vector2i(4,3))
	else:
		resolver._set_squad_cell(gs,sb,Vector2i(4,3)); resolver._trigger_hazard_on_enter(gs,sb)
	sb=gs.get_squad(b)
	print("after snare cell=",sb.cell," snared_until=",sb.snared_no_move_until_turn," hazard_gone=",gs.board.hazard_at(Vector2i(4,3))==null)

	# Overkill pop
	var c = gs.add_squad(0, Vector2i(8,8), "core", 1)
	var sc=gs.get_squad(c)
	resolver._pop_organs(gs, sc, 50)
	print("overkill alive=",sc.is_alive()," units_size=",sc.units.size())
