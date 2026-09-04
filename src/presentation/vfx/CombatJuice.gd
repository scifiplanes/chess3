extends RefCounted
class_name CombatJuice

## Orchestrates force shove + atmosphere gust + debris + burst/sparks after resolves.

const AbilityFootprintScript = preload("res://src/presentation/vfx/AbilityFootprint.gd")
const BattlefieldForceScript = preload("res://src/presentation/vfx/BattlefieldForce.gd")
const ImpactDebrisScript = preload("res://src/presentation/vfx/ImpactDebris.gd")
const AbilityBurstVfxScript = preload("res://src/presentation/vfx/AbilityBurstVfx.gd")
const HitSparkVfxScript = preload("res://src/presentation/vfx/HitSparkVfx.gd")

static func play(
	tree: SceneTree,
	vfx_root: Node3D,
	atmosphere: Node,
	debris_host: Node3D,
	action_id: String,
	origin: Vector3,
	target: Vector3,
	aoe_radius: float = 1.0,
	ground_y: float = 0.11,
	board_center: Vector2 = Vector2(7.0, 7.0),
	board_half: float = 7.2,
	defender_view: Node = null
) -> void:
	var fp: Dictionary = AbilityFootprintScript.footprint_for_action(action_id, aoe_radius)
	var shape: AbilityFootprintScript.Id = fp.get("shape", AbilityFootprintScript.Id.CIRCLE)
	var radius := float(fp.get("radius", 1.0))
	var width := float(fp.get("width", 1.2))
	var cone := float(fp.get("cone_degrees", 70.0))
	var strength := float(fp.get("strength", 6.0))
	var heavy := bool(fp.get("heavy", false))
	var debris_n := int(fp.get("debris", 0))

	var forward := target - origin
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3(0, 0, -1)

	BattlefieldForceScript.apply(tree, target, forward, shape, radius, strength, width, cone)

	if atmosphere != null and atmosphere.has_method("apply_ability_force"):
		atmosphere.call("apply_ability_force", target, forward, shape, radius, strength, width, cone)

	if debris_n > 0 and debris_host != null:
		ImpactDebrisScript.spawn_burst(
			debris_host, target, debris_n, ground_y, board_center, board_half, strength * 0.55
		)

	if vfx_root != null:
		var col := Color(1.0, 0.82, 0.35, 1.0) if heavy else Color(0.95, 0.9, 0.75, 1.0)
		AbilityBurstVfxScript.play(vfx_root, target, radius, col, 1.0 if heavy else 0.65)
		HitSparkVfxScript.play(vfx_root, target + Vector3(0, 0.45, 0), 1.0 if heavy else 0.7, col)

	if defender_view != null and defender_view.has_method("enter_ragdoll"):
		var shove := forward.normalized() * strength * 0.55 + Vector3.UP * strength * 0.22
		defender_view.call("enter_ragdoll", shove, 1.15 if heavy else 0.75)
