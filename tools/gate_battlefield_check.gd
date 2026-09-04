extends SceneTree

## Headless smoke for battlefield juice systems.
## godot --headless --path . --script res://tools/gate_battlefield_check.gd

const AbilityFootprintScript = preload("res://src/presentation/vfx/AbilityFootprint.gd")
const BattlefieldForceScript = preload("res://src/presentation/vfx/BattlefieldForce.gd")
const BoardAtmosphereScript = preload("res://src/presentation/vfx/BoardAtmosphere.gd")
const ContactShadowScript = preload("res://src/presentation/vfx/ContactShadow.gd")
const ImpactDebrisScript = preload("res://src/presentation/vfx/ImpactDebris.gd")
const AbilityBurstVfxScript = preload("res://src/presentation/vfx/AbilityBurstVfx.gd")
const HitSparkVfxScript = preload("res://src/presentation/vfx/HitSparkVfx.gd")
const CombatJuiceScript = preload("res://src/presentation/vfx/CombatJuice.gd")
const LoosePropScript = preload("res://src/presentation/vfx/LooseProp.gd")
const BoardScene = preload("res://scenes/Board.tscn")
const GameStateScript = preload("res://src/sim/GameState.gd")
const UnitStateScript = preload("res://src/sim/UnitState.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok := true
	var reasons: PackedStringArray = []

	var root := Node3D.new()
	root.name = "GateRoot"
	get_root().add_child(root)

	var board: Node3D = BoardScene.instantiate()
	root.add_child(board)
	await process_frame
	await process_frame

	var gs = GameStateScript.new()
	root.add_child(gs)
	gs.setup(GameStateScript.DEFAULT_BOARD_SIZE, 7)
	gs.squads.clear()
	gs._next_squad_id = 1
	gs.offer_pending = false
	var sid: int = int(gs.add_squad(0, Vector2i(5, 5), "core", 1))
	var s = gs.get_squad(sid)
	s.units.append(UnitStateScript.new("claw", 1, 1))
	s.units.append(UnitStateScript.new("eye", 1, 1))
	s.units.append(UnitStateScript.new("shell", 1, 1))
	s.organs_locked = true
	if board.has_method("sync_from_game_state"):
		board.call("sync_from_game_state", gs)
	await process_frame
	await process_frame

	var atmo = BoardAtmosphereScript.new()
	root.add_child(atmo)
	atmo.setup(7.2, Vector3(7, 0, 7))
	if atmo.get_node_or_null("LightShaft") == null:
		ok = false
		reasons.append("missing LightShaft")
	if atmo.get_node_or_null("Dust") == null:
		ok = false
		reasons.append("missing Dust")
	if atmo.get_node_or_null("Clouds") == null:
		ok = false
		reasons.append("missing Clouds")

	var vfx := Node3D.new()
	root.add_child(vfx)
	AbilityBurstVfxScript.warmup(vfx, Vector3(5.5, 0.3, 5.5))
	HitSparkVfxScript.warmup(vfx, Vector3(5.5, 0.5, 5.5))

	var fp: Dictionary = AbilityFootprintScript.footprint_for_action("slam")
	if not bool(fp.get("heavy", false)) or int(fp.get("debris", 0)) < 1:
		ok = false
		reasons.append("slam footprint not heavy")

	var debris_host: Node3D = board.call("debris_root")
	ImpactDebrisScript.spawn_burst(debris_host, Vector3(5.5, 0.4, 5.5), 4, 0.11, Vector2(7, 7), 7.2, 5.0)
	await process_frame

	var bodies_before := BattlefieldForceScript.collect_bodies(self).size()
	if bodies_before < 1:
		ok = false
		reasons.append("no force_bodies after debris/organs")

	BattlefieldForceScript.apply(
		self,
		Vector3(5.5, 0.2, 5.5),
		Vector3(1, 0, 0),
		AbilityFootprintScript.Id.CIRCLE,
		2.0,
		9.0
	)
	atmo.apply_ability_force(Vector3(5.5, 0.2, 5.5), Vector3(1, 0, 0), AbilityFootprintScript.Id.CIRCLE, 2.0, 9.0)

	var view = null
	if board.has_method("get_squad_view"):
		view = board.call("get_squad_view", sid)
	if view == null:
		ok = false
		reasons.append("missing squad view")
	else:
		if not view.has_method("enter_ragdoll"):
			ok = false
			reasons.append("squad view missing enter_ragdoll")
		else:
			view.call("enter_ragdoll", Vector3(2, 3, 1), 0.8)
			if not bool(view.call("is_ragdolling")):
				ok = false
				reasons.append("ragdoll flag not set")
			await create_timer(1.3).timeout
			if bool(view.call("is_ragdolling")):
				ok = false
				reasons.append("ragdoll did not reseat")

	CombatJuiceScript.play(
		self, vfx, atmo, debris_host, "slam",
		Vector3(5.5, 0.3, 5.5), Vector3(5.5, 0.3, 5.5),
		1.0, 0.11, Vector2(7, 7), 7.2, view
	)
	await process_frame

	# LooseProp class loads
	var _lp = LoosePropScript.new()
	_lp.queue_free()

	if board.get_node_or_null("PhysicsFloor") == null:
		ok = false
		reasons.append("missing PhysicsFloor")

	if ok:
		print("GATE_BATTLEFIELD_PASS")
		quit(0)
	else:
		print("GATE_BATTLEFIELD_FAIL: ", ", ".join(reasons))
		quit(1)
