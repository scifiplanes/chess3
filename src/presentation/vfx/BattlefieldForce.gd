extends RefCounted
class_name BattlefieldForce

## Apply Chillout-style shove impulses to RigidBody3D props/organs in an XZ footprint.

const AbilityFootprintScript = preload("res://src/presentation/vfx/AbilityFootprint.gd")

const FORCE_GROUP := "force_bodies"
const LOFT_FACTOR := 0.55
const TORQUE_FACTOR := 0.12
## Extra upward kick for light debris chunks (settled mushroom matter).
const DEBRIS_LOFT_BONUS := 0.45

static func collect_bodies(tree: SceneTree) -> Array[RigidBody3D]:
	var out: Array[RigidBody3D] = []
	if tree == null:
		return out
	for n in tree.get_nodes_in_group(FORCE_GROUP):
		if n is RigidBody3D and is_instance_valid(n):
			var body := n as RigidBody3D
			# Living mutant organs are ragdolled explicitly — never shove via AOE force alone.
			if body.has_meta("organ_ragdoll") and bool(body.get_meta("organ_ragdoll")):
				continue
			if body.freeze and body.has_meta("force_while_frozen") and not bool(body.get_meta("force_while_frozen")):
				continue
			out.append(body)
	return out

static func apply(
	tree: SceneTree,
	origin: Vector3,
	forward_in: Vector3,
	shape: AbilityFootprintScript.Id,
	radius: float,
	strength: float,
	width: float = 1.2,
	cone_degrees: float = 70.0
) -> int:
	var bodies := collect_bodies(tree)
	var hit := 0
	var forward := AbilityFootprintScript.resolve_forward(forward_in)
	for body in bodies:
		if body == null or not is_instance_valid(body):
			continue
		if body.has_method("receives_ability_force") and not bool(body.call("receives_ability_force")):
			continue
		var p := body.global_position
		if not AbilityFootprintScript.contains(shape, p, origin, forward, radius, width, cone_degrees):
			continue
		var falloff := AbilityFootprintScript.falloff(shape, p, origin, radius, width)
		var to := p - origin
		to.y = 0.0
		var dir: Vector3
		if to.length_squared() < 0.0025:
			dir = Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)).normalized()
			if dir.length_squared() < 0.01:
				dir = forward
		else:
			dir = to.normalized()
		var mag := strength * falloff
		var loft := LOFT_FACTOR
		if body.has_meta("force_light") and bool(body.get_meta("force_light")):
			loft += DEBRIS_LOFT_BONUS
			mag *= 1.15
		var impulse := dir * mag + Vector3.UP * (mag * loft)
		body.freeze = false
		body.sleeping = false
		body.apply_central_impulse(impulse)
		body.apply_torque_impulse(Vector3(
			randf_range(-1, 1),
			randf_range(-1, 1),
			randf_range(-1, 1)
		) * mag * TORQUE_FACTOR)
		hit += 1
	return hit
