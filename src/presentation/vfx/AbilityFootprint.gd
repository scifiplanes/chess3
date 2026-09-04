extends RefCounted
class_name AbilityFootprint

## XZ footprints for ability forces / VFX (slim Chillout AbilityShape).

enum Id { CIRCLE, LINE, CONE, SQUARE }

static func resolve_forward(forward_in: Vector3) -> Vector3:
	var f := Vector3(forward_in.x, 0.0, forward_in.z)
	if f.length_squared() < 0.0001:
		return Vector3(0.0, 0.0, -1.0)
	return f.normalized()

static func contains(
	shape: Id,
	world_pos: Vector3,
	origin: Vector3,
	forward_in: Vector3,
	radius: float,
	width: float = 1.2,
	cone_degrees: float = 70.0
) -> bool:
	var p := Vector3(world_pos.x, 0.0, world_pos.z)
	var o := Vector3(origin.x, 0.0, origin.z)
	var forward := resolve_forward(forward_in)
	var delta := p - o
	var dist := delta.length()
	match shape:
		Id.CIRCLE:
			return dist <= radius + 0.001
		Id.SQUARE:
			var right := Vector3(-forward.z, 0.0, forward.x)
			var local := Vector3(delta.dot(right), 0.0, delta.dot(forward))
			var half := radius
			return absf(local.x) <= half + 0.001 and absf(local.z) <= half + 0.001
		Id.LINE:
			var right := Vector3(-forward.z, 0.0, forward.x)
			var along := delta.dot(forward)
			var side := absf(delta.dot(right))
			return along >= -0.05 and along <= radius + 0.05 and side <= width * 0.5 + 0.05
		Id.CONE:
			if dist > radius + 0.001:
				return false
			if dist < 0.08:
				return true
			var ang := rad_to_deg(acos(clampf(delta.normalized().dot(forward), -1.0, 1.0)))
			return ang <= cone_degrees * 0.5 + 0.5
		_:
			return dist <= radius + 0.001

static func falloff(
	shape: Id,
	world_pos: Vector3,
	origin: Vector3,
	radius: float,
	width: float = 1.2
) -> float:
	var p := Vector3(world_pos.x, 0.0, world_pos.z)
	var o := Vector3(origin.x, 0.0, origin.z)
	var dist := (p - o).length()
	var r := maxf(radius, 0.05)
	match shape:
		Id.LINE:
			# Soften by distance along the lane.
			return clampf(1.0 - dist / (r + width), 0.15, 1.0)
		_:
			return clampf(1.0 - dist / r, 0.2, 1.0)

static func footprint_for_action(action_id: String, aoe_radius: float = 1.0) -> Dictionary:
	## Returns {shape, radius, width, cone_degrees, strength, heavy}.
	var id := str(action_id)
	match id:
		"slam":
			return {
				"shape": Id.CIRCLE,
				"radius": maxf(1.1, float(aoe_radius) + 0.35),
				"width": 1.2,
				"cone_degrees": 70.0,
				"strength": 11.0,
				"heavy": true,
				"debris": 12,
			}
		"charge":
			return {
				"shape": Id.LINE,
				"radius": 2.4,
				"width": 1.15,
				"cone_degrees": 70.0,
				"strength": 10.0,
				"heavy": true,
				"debris": 8,
			}
		"dash":
			return {
				"shape": Id.LINE,
				"radius": 2.2,
				"width": 1.05,
				"cone_degrees": 70.0,
				"strength": 9.0,
				"heavy": true,
				"debris": 7,
			}
		"pounce":
			return {
				"shape": Id.CIRCLE,
				"radius": maxf(1.15, float(aoe_radius) + 0.4),
				"width": 1.2,
				"cone_degrees": 70.0,
				"strength": 9.0,
				"heavy": true,
				"debris": 7,
			}
		"railgun":
			return {
				"shape": Id.LINE,
				"radius": 3.2,
				"width": 0.85,
				"cone_degrees": 70.0,
				"strength": 8.5,
				"heavy": true,
				"debris": 6,
			}
		"airstrike":
			return {
				"shape": Id.SQUARE,
				"radius": 1.35,
				"width": 1.2,
				"cone_degrees": 70.0,
				"strength": 7.5,
				"heavy": true,
				"debris": 5,
			}
		"eruption":
			return {
				"shape": Id.CIRCLE,
				"radius": maxf(1.2, float(aoe_radius) + 0.45),
				"width": 1.2,
				"cone_degrees": 70.0,
				"strength": 8.0,
				"heavy": true,
				"debris": 6,
			}
		"melee":
			return {
				"shape": Id.CIRCLE,
				"radius": 0.85,
				"width": 1.0,
				"cone_degrees": 70.0,
				"strength": 5.5,
				"heavy": false,
				"debris": 0,
			}
		"ranged":
			return {
				"shape": Id.CIRCLE,
				"radius": 0.75,
				"width": 1.0,
				"cone_degrees": 70.0,
				"strength": 4.5,
				"heavy": false,
				"debris": 0,
			}
		_:
			return {
				"shape": Id.CIRCLE,
				"radius": 0.9,
				"width": 1.0,
				"cone_degrees": 70.0,
				"strength": 5.0,
				"heavy": false,
				"debris": 0,
			}
