extends RigidBody3D
class_name LooseProp

## Light clutter that receives ability forces (Chillout light-prop gate).

const FORCE_AFFECTED_SCALE_MAX := 0.55

var _receives_force: bool = true

func _ready() -> void:
	add_to_group("force_bodies")
	# Settled debris must still wake for ability kicks.
	if not has_meta("force_while_frozen"):
		set_meta("force_while_frozen", true)

func receives_ability_force() -> bool:
	if not _receives_force:
		return false
	# Chunk debris / marked light props always take kicks (node scale is often 1.0).
	if has_meta("force_light") and bool(get_meta("force_light")):
		return true
	var sc := maxf(scale.x, maxf(scale.y, scale.z))
	return sc <= FORCE_AFFECTED_SCALE_MAX + 0.001

func set_receives_force(on: bool) -> void:
	_receives_force = on
