extends SceneTree

## Multi-scenario playtest for battlefield juice / ragdoll / debris.
## godot --path . --script res://tools/playtest_battlefield_juice.gd
## Prints PLAYTEST_BATTLEFIELD_JUICE_OK or FAIL lines.

const GameStateScript = preload("res://src/sim/GameState.gd")
const ResolverScript = preload("res://src/sim/Resolver.gd")
const UnitStateScript = preload("res://src/sim/UnitState.gd")
const BoardScene = preload("res://scenes/Board.tscn")
const BoardAtmosphereScript = preload("res://src/presentation/vfx/BoardAtmosphere.gd")
const CombatJuiceScript = preload("res://src/presentation/vfx/CombatJuice.gd")
const BattlefieldForceScript = preload("res://src/presentation/vfx/BattlefieldForce.gd")
const AbilityFootprintScript = preload("res://src/presentation/vfx/AbilityFootprint.gd")
const ImpactDebrisScript = preload("res://src/presentation/vfx/ImpactDebris.gd")
const AbilityBurstVfxScript = preload("res://src/presentation/vfx/AbilityBurstVfx.gd")
const HitSparkVfxScript = preload("res://src/presentation/vfx/HitSparkVfx.gd")

var _fails: Array[String] = []
var _passes: int = 0
var _board: Node3D
var _gs
var _resolver = ResolverScript.new()
var _atmo: Node3D
var _vfx: Node3D
var _root3: Node3D

func _initialize() -> void:
	call_deferred("_run")

func _ok(n: String) -> void:
	_passes += 1
	print("PASS: ", n)

func _fail(n: String, d: String) -> void:
	_fails.append("%s — %s" % [n, d])
	print("FAIL: ", n, " — ", d)

func _wait(sec: float) -> void:
	await create_timer(sec).timeout

func _run() -> void:
	print("=== battlefield juice playtest ===")
	_root3 = Node3D.new()
	root.add_child(_root3)

	var light := DirectionalLight3D.new()
	light.light_energy = 1.6
	light.rotation_degrees = Vector3(-50, 30, 0)
	_root3.add_child(light)

	_board = BoardScene.instantiate()
	_root3.add_child(_board)
	await process_frame

	_gs = GameStateScript.new()
	_root3.add_child(_gs)
	_gs.setup(GameStateScript.DEFAULT_BOARD_SIZE, 20260901)
	_gs.squads.clear()
	_gs._next_squad_id = 1
	_gs.offer_pending = false
	_gs.winner = -1
	_gs.active_player = 0

	var sid_a: int = int(_gs.add_squad(0, Vector2i(5, 5), "core", 1))
	var a = _gs.get_squad(sid_a)
	a.units.append(UnitStateScript.new("claw", 1, 1))
	a.units.append(UnitStateScript.new("eye", 1, 1))
	a.units.append(UnitStateScript.new("shell", 1, 1))
	a.organs_locked = true
	a.fresh_turn = -1
	a.moved_turn = -1

	var sid_b: int = int(_gs.add_squad(1, Vector2i(6, 5), "core", 1))
	var b = _gs.get_squad(sid_b)
	b.units.append(UnitStateScript.new("claw", 1, 1))
	b.units.append(UnitStateScript.new("hoof", 1, 1))
	b.organs_locked = true
	b.fresh_turn = -1

	var sid_solo: int = int(_gs.add_squad(0, Vector2i(8, 8), "core", 1))
	_gs.get_squad(sid_solo).organs_locked = true
	_gs.get_squad(sid_solo).fresh_turn = -1

	_board.call("sync_from_game_state", _gs)
	await process_frame
	await process_frame

	_vfx = Node3D.new()
	_root3.add_child(_vfx)
	_atmo = BoardAtmosphereScript.new()
	_root3.add_child(_atmo)
	var bc: Vector2 = _board.call("board_center_xz")
	_atmo.call("setup", float(_board.call("board_half_extent")), Vector3(bc.x, 0.0, bc.y))
	AbilityBurstVfxScript.warmup(_vfx, Vector3(5.5, 0.3, 5.5))
	HitSparkVfxScript.warmup(_vfx, Vector3(5.5, 0.5, 5.5))

	await _s01_ragdoll_reseats(sid_a)
	await _s02_double_enter_single_reseat(sid_a)
	await _s03_force_skips_living_organs(sid_a, sid_b)
	await _s04_debris_are_sprites_not_cubes()
	await _s05_melee_juice_and_hit_flash(sid_a, sid_b)
	await _s06_organ_pop_during_ragdoll(sid_b)
	await _s07_move_while_ragdolling(sid_a)
	await _s08_solo_organ_ragdoll(sid_solo)
	await _s09_heavy_debris_cap()
	await _s10_corpse_still_forceable()
	await _s11_settled_debris_forceable()
	await _s12_organ_pop_no_living_duplicate(sid_b)

	print("=== results: %d pass, %d fail ===" % [_passes, _fails.size()])
	for f in _fails:
		print("FAIL: ", f)
	if _fails.is_empty():
		print("PLAYTEST_BATTLEFIELD_JUICE_OK")
		quit(0)
	else:
		print("PLAYTEST_BATTLEFIELD_JUICE_FAIL")
		quit(1)

func _view(sid: int):
	return _board.call("get_squad_view", sid)

func _s01_ragdoll_reseats(sid: int) -> void:
	var v = _view(sid)
	if v == null:
		_fail("S01", "no view")
		return
	v.call("enter_ragdoll", Vector3(2, 2.5, 0), 0.7)
	if not bool(v.call("is_ragdolling")):
		_fail("S01", "not ragdolling after enter")
		return
	await _wait(1.25)
	if bool(v.call("is_ragdolling")):
		_fail("S01", "still ragdolling after reseat window")
		return
	# organs should be frozen at rests
	var parts: Array = v.get("_organ_parts")
	for p_any in parts:
		var body: RigidBody3D = (p_any as Dictionary).get("node") as RigidBody3D
		if body == null:
			continue
		if not body.freeze:
			_fail("S01", "body not frozen after reseat")
			return
		if body.top_level:
			_fail("S01", "body still top_level after reseat")
			return
	_ok("S01 ragdoll reseats frozen local")

func _s02_double_enter_single_reseat(sid: int) -> void:
	var v = _view(sid)
	v.call("enter_ragdoll", Vector3(1, 2, 0), 0.8)
	await _wait(0.15)
	v.call("enter_ragdoll", Vector3(-1, 2, 0), 0.8)
	await _wait(1.4)
	if bool(v.call("is_ragdolling")):
		_fail("S02", "double enter left mutant ragdolling")
		return
	_ok("S02 double enter still reseats once")

func _s03_force_skips_living_organs(sid_a: int, sid_b: int) -> void:
	var va = _view(sid_a)
	var vb = _view(sid_b)
	# ensure seated
	if bool(va.call("is_ragdolling")):
		va.call("reseat_ragdoll")
	if bool(vb.call("is_ragdolling")):
		vb.call("reseat_ragdoll")
	await process_frame
	var frozen_before := 0
	var organs := 0
	for body in BattlefieldForceScript.collect_bodies(self):
		if body.has_meta("organ_ragdoll") and bool(body.get_meta("organ_ragdoll")):
			organs += 1
			if body.freeze:
				frozen_before += 1
	# Living organs must not be force targets
	var hit := BattlefieldForceScript.apply(
		self,
		Vector3(5.5, 0.2, 5.5),
		Vector3(1, 0, 0),
		AbilityFootprintScript.Id.CIRCLE,
		3.0,
		12.0
	)
	await process_frame
	var unfrozen_organs := 0
	for n in get_nodes_in_group(BattlefieldForceScript.FORCE_GROUP):
		if n is RigidBody3D and (n as RigidBody3D).has_meta("organ_ragdoll") and bool((n as RigidBody3D).get_meta("organ_ragdoll")):
			if not (n as RigidBody3D).freeze and not bool(va.call("is_ragdolling")) and not bool(vb.call("is_ragdolling")):
				unfrozen_organs += 1
	if unfrozen_organs > 0:
		_fail("S03", "force unfroze %d living organs without ragdoll mode" % unfrozen_organs)
		return
	_ok("S03 force skips living organs (hit=%d organs_seen=%d)" % [hit, organs])

func _s04_debris_are_sprites_not_cubes() -> void:
	var host: Node3D = _board.call("debris_root")
	# clear previous
	for c in host.get_children():
		c.queue_free()
	await process_frame
	ImpactDebrisScript.spawn_burst(host, Vector3(5.5, 0.4, 5.5), 5, 0.11, Vector2(7, 7), 7.2, 5.0)
	await process_frame
	var sprites := 0
	var cubes := 0
	for c in host.get_children():
		if c is RigidBody3D:
			for ch in c.get_children():
				if ch is Sprite3D:
					sprites += 1
					var spr := ch as Sprite3D
					if spr.texture == null:
						_fail("S04", "sprite missing texture")
						return
				if ch is MeshInstance3D:
					var mi := ch as MeshInstance3D
					if mi.mesh is BoxMesh:
						cubes += 1
	if sprites < 5:
		_fail("S04", "expected >=5 chunk sprites, got %d" % sprites)
		return
	if cubes > 0:
		_fail("S04", "found %d cube meshes in debris" % cubes)
		return
	_ok("S04 debris are textured sprites")

func _s05_melee_juice_and_hit_flash(sid_a: int, sid_b: int) -> void:
	var vb = _view(sid_b)
	vb.call("reseat_ragdoll")
	await process_frame
	# Simulate juice + hit flash like Main does
	CombatJuiceScript.play(
		self, _vfx, _atmo, _board.call("debris_root"), "melee",
		Vector3(5.5, 0.3, 5.5), Vector3(6.5, 0.3, 5.5),
		1.0, 0.11, Vector2(7, 7), 7.2, vb
	)
	vb.call("play_hit_flash")
	if not bool(vb.call("is_ragdolling")):
		_fail("S05", "defender not ragdolling after juice+flash")
		return
	await _wait(1.5)
	if bool(vb.call("is_ragdolling")):
		_fail("S05", "defender stuck ragdolling after juice+flash")
		return
	_ok("S05 melee juice+flash reseats")

func _s06_organ_pop_during_ragdoll(sid_b: int) -> void:
	var vb = _view(sid_b)
	vb.call("enter_ragdoll", Vector3(1, 2, 0), 1.2)
	await _wait(0.1)
	# Pop an organ via sync (damage)
	var s = _gs.get_squad(sid_b)
	if s.units.size() > 1:
		s.units.pop_front()
	_board.call("sync_from_game_state", _gs)
	await process_frame
	# rebuild clears ragdoll flag; old timer must not crash / re-ragdoll wrongly
	await _wait(1.5)
	# still alive and not exploding
	if _view(sid_b) == null:
		_fail("S06", "view lost after pop mid-ragdoll")
		return
	if bool(_view(sid_b).call("is_ragdolling")):
		# may or may not be; if timer from old gen was invalidated should be false
		_fail("S06", "stale ragdoll timer re-entered ragdoll after rebuild")
		return
	_ok("S06 organ pop mid-ragdoll safe")

func _s07_move_while_ragdolling(sid_a: int) -> void:
	var va = _view(sid_a)
	va.call("enter_ragdoll", Vector3(0.5, 2, 0), 1.0)
	await process_frame
	# move squad cell + sync (triggers move tween)
	var s = _gs.get_squad(sid_a)
	s.cell = Vector2i(5, 6)
	_board.call("sync_from_game_state", _gs)
	await _wait(0.3)
	# should have forced reseat or stayed coherent
	await _wait(1.2)
	var parts: Array = va.get("_organ_parts")
	for p_any in parts:
		var body: RigidBody3D = (p_any as Dictionary).get("node") as RigidBody3D
		if body == null:
			continue
		if body.top_level and not bool(va.call("is_ragdolling")):
			_fail("S07", "top_level organ after move/ragdoll settle")
			return
	_ok("S07 move during ragdoll coherent")

func _s08_solo_organ_ragdoll(sid: int) -> void:
	var v = _view(sid)
	if v == null:
		_fail("S08", "no solo view")
		return
	v.call("enter_ragdoll", Vector3(1, 2, 0), 0.7)
	await _wait(1.2)
	if bool(v.call("is_ragdolling")):
		_fail("S08", "solo organ stuck ragdolling")
		return
	_ok("S08 solo organ ragdoll")

func _s09_heavy_debris_cap() -> void:
	var host: Node3D = _board.call("debris_root")
	var before := host.get_child_count()
	ImpactDebrisScript.spawn_burst(host, Vector3(7, 0.4, 7), 80, 0.11, Vector2(7, 7), 7.2, 8.0)
	await process_frame
	var after := host.get_child_count()
	var spawned := after - before
	if spawned > 64:
		_fail("S09", "debris cap broken, spawned %d" % spawned)
		return
	_ok("S09 debris cap respected (%d)" % spawned)

func _s10_corpse_still_forceable() -> void:
	_board.call("spawn_organ_corpse", "claw", Vector3(4.5, 0.5, 4.5), Vector3(0, 2, 0))
	await process_frame
	var corpses := 0
	for n in get_nodes_in_group(BattlefieldForceScript.FORCE_GROUP):
		if n is RigidBody3D and not (n as RigidBody3D).has_meta("organ_ragdoll"):
			# debris or corpse
			corpses += 1
	var hit := BattlefieldForceScript.apply(
		self, Vector3(4.5, 0.2, 4.5), Vector3(1, 0, 0),
		AbilityFootprintScript.Id.CIRCLE, 2.0, 8.0
	)
	if hit < 1:
		_fail("S10", "expected force to hit corpse/debris, hit=%d group_non_organ=%d" % [hit, corpses])
		return
	_ok("S10 corpses/debris still forceable (hit=%d)" % hit)

func _s11_settled_debris_forceable() -> void:
	var host: Node3D = _board.call("debris_root")
	ImpactDebrisScript.spawn_burst(host, Vector3(6.5, 0.4, 6.5), 6, 0.11, Vector2(7, 7), 7.2, 5.0)
	await process_frame
	var targets: Array[RigidBody3D] = []
	for n in host.get_children():
		if n is RigidBody3D:
			var b := n as RigidBody3D
			# Only sample near the burst origin (ignore leftovers from earlier tests).
			if b.global_position.distance_to(Vector3(6.5, 0.2, 6.5)) > 2.5:
				continue
			b.freeze = true
			b.sleeping = true
			b.linear_velocity = Vector3.ZERO
			targets.append(b)
	if targets.is_empty():
		_fail("S11", "no debris to freeze near origin")
		return
	var hit := BattlefieldForceScript.apply(
		self, Vector3(6.5, 0.2, 6.5), Vector3(0, 0, 1),
		AbilityFootprintScript.Id.CIRCLE, 2.5, 9.0
	)
	await process_frame
	await physics_frame
	await physics_frame
	var lofted := 0
	var unfrozen := 0
	for b2 in targets:
		if not is_instance_valid(b2):
			continue
		if not b2.freeze:
			unfrozen += 1
		# Impulse may sit pending until integrate — unfreeze + any upward/vel counts.
		if (not b2.freeze) and (b2.linear_velocity.length() > 0.2 or b2.global_position.y > 0.28):
			lofted += 1
	if hit < 1 or unfrozen < 1:
		_fail("S11", "settled debris not kicked (hit=%d unfrozen=%d lofted=%d targets=%d)" % [hit, unfrozen, lofted, targets.size()])
		return
	_ok("S11 settled debris forceable (hit=%d unfrozen=%d lofted=%d)" % [hit, unfrozen, lofted])

func _s12_organ_pop_no_living_duplicate(sid_b: int) -> void:
	## Hit-pop must free living organ immediately after corpse spawn (no 1-frame zombie glyph).
	var s = _gs.get_squad(sid_b)
	if s == null:
		_fail("S12", "no squad")
		return
	s.units.clear()
	s.units.append(UnitStateScript.new("core", 1, 1))
	s.units.append(UnitStateScript.new("claw", 1, 1))
	s.units.append(UnitStateScript.new("eye", 1, 1))
	s.fresh_turn = -1
	_board.call("sync_from_game_state", _gs)
	await process_frame
	await process_frame
	var vb = _view(sid_b)
	if vb == null:
		_fail("S12", "no view")
		return
	var parts_before: Array = vb.get("_organ_parts")
	if parts_before.size() != 3:
		_fail("S12", "expected 3 living organs before pop, got %d" % parts_before.size())
		return
	var corpses_root: Node3D = _board.get("corpses_root")
	var corpses_before := 0
	if corpses_root != null:
		corpses_before = corpses_root.get_child_count()
	# Capture node ids of living organs before pop.
	var living_ids: Dictionary = {}
	for p_any in parts_before:
		var n: Node = (p_any as Dictionary).get("node")
		if n != null:
			living_ids[n.get_instance_id()] = true
	# Pop front organ (hit path → incremental pop).
	var popped_def := str(s.units[0].unit_def_id)
	s.units.pop_front()
	_board.call("sync_from_game_state", _gs)
	# Same frame check — queue_free would still leave the node valid/in-tree here.
	var parts_after: Array = vb.get("_organ_parts")
	if parts_after.size() != 2:
		_fail("S12", "living parts != 2 after pop (got %d)" % parts_after.size())
		return
	if int(s.units.size()) != parts_after.size():
		_fail("S12", "parts %d != units %d" % [parts_after.size(), s.units.size()])
		return
	var survivors: Dictionary = {}
	for p2 in parts_after:
		var n2: Node = (p2 as Dictionary).get("node")
		if n2 == null or not is_instance_valid(n2):
			_fail("S12", "survivor organ node invalid")
			return
		survivors[n2.get_instance_id()] = true
	var zombie := 0
	for id_any in living_ids.keys():
		var iid := int(id_any)
		if survivors.has(iid):
			continue
		# Popped node's instance must be gone (immediate free), not merely queue_freed.
		if is_instance_id_valid(iid):
			zombie += 1
	if zombie > 0:
		_fail("S12", "popped organ still valid after sync (queue_free zombie x%d)" % zombie)
		return
	await process_frame
	var corpses_after := 0
	if corpses_root != null:
		corpses_after = corpses_root.get_child_count()
	if corpses_after <= corpses_before:
		_fail("S12", "expected corpse spawn (%d -> %d) for %s" % [corpses_before, corpses_after, popped_def])
		return
	_ok("S12 organ pop no living duplicate (corpses %d→%d)" % [corpses_before, corpses_after])
