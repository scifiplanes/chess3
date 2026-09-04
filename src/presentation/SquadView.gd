extends Node3D
class_name SquadView

const RulesScript = preload("res://src/sim/Rules.gd")
const UnitDefsScript = preload("res://src/sim/UnitDefs.gd")
const K1Widgets = preload("res://src/presentation/K1Widgets.gd")
const OrganEmojiPartScript = preload("res://src/presentation/OrganEmojiPart.gd")
const ContactShadowScript = preload("res://src/presentation/vfx/ContactShadow.gd")
const BattlefieldForceScript = preload("res://src/presentation/vfx/BattlefieldForce.gd")

@onready var unit_emojis: Label3D = $UnitEmojis
@onready var label: Label3D = $Label3D

var squad_id: int = -1
var _pips_root: Node3D
var _avail_root: Node3D
var _organs_root: Node3D
var _joints_root: Node3D
var _flash_tween: Tween
var _pulse_tween: Tween
var _move_tween: Tween
var _ragdoll_timer: SceneTreeTimer
var _ragdoll_gen: int = 0
var _last_has_move: bool = false
var _last_has_action: bool = false
var _last_attach_eligible: bool = false
var _last_selected: bool = false
var _avail_built: bool = false
var _placed: bool = false
var _moving: bool = false
var _ragdolling: bool = false
var _cell_size: float = 1.0
var _owner_color: Color = Color(0.28, 0.82, 1.0)
var _hovered_part_i: int = -1
var _hover_pulse: float = 0.0
var _hover_forced: bool = false
const ORGAN_RADIUS := 0.11
const RAGDOLL_SEAT_SEC := 1.05

# Connected humanoid — spaced so glyphs do not stack/z-fight at board zoom.
const SLOT_RESTS := {
	"head": Vector3(0.0, 0.62, 0.06),
	"torso": Vector3(0.0, 0.32, 0.00),
	"arm_l": Vector3(-0.30, 0.38, 0.08),
	"arm_r": Vector3(0.30, 0.38, 0.08),
	"leg_l": Vector3(-0.16, 0.12, 0.05),
	"leg_r": Vector3(0.16, 0.12, 0.05),
}

# Overflow rings behind/around silhouette with distinct depth bands.
const EXTRA_RESTS := [
	Vector3(0.0, 0.42, -0.16),
	Vector3(-0.18, 0.46, -0.10),
	Vector3(0.18, 0.46, -0.10),
	Vector3(0.0, 0.22, -0.18),
	Vector3(-0.20, 0.24, -0.08),
	Vector3(0.20, 0.24, -0.08),
	Vector3(0.0, 0.52, -0.08),
	Vector3(-0.14, 0.14, -0.14),
	Vector3(0.14, 0.14, -0.14),
	Vector3(0.0, 0.34, -0.22),
]

# Per-organ spring state: Array of {node, rest, vel, phase, def_id, stack_i}
var _organ_parts: Array = []
var _jiggle_time: float = 0.0
var _organ_pixel: float = 0.0068

func setup(p_squad_id: int) -> void:
	squad_id = p_squad_id
	_pips_root = get_node_or_null("Pips") as Node3D
	if _pips_root == null:
		_pips_root = Node3D.new()
		_pips_root.name = "Pips"
		add_child(_pips_root)
	_avail_root = get_node_or_null("Availability") as Node3D
	if _avail_root == null:
		_avail_root = Node3D.new()
		_avail_root.name = "Availability"
		add_child(_avail_root)
	_organs_root = get_node_or_null("Organs") as Node3D
	if _organs_root == null:
		_organs_root = Node3D.new()
		_organs_root.name = "Organs"
		add_child(_organs_root)
	_joints_root = get_node_or_null("Joints") as Node3D
	if _joints_root == null:
		_joints_root = Node3D.new()
		_joints_root.name = "Joints"
		add_child(_joints_root)
	if unit_emojis:
		unit_emojis.visible = false
	if label:
		K1Widgets.apply_label3d_font(label)

func _exit_tree() -> void:
	_cancel_hit_flash()
	_invalidate_ragdoll_timer()

func _process(delta: float) -> void:
	_jiggle_time += delta
	_hover_pulse += delta
	_orient_organs_to_camera()
	if _ragdolling:
		return
	_update_hovered_organ()
	var move_amp := 2.4 if _moving else 1.0
	for i in range(_organ_parts.size()):
		var part_any = _organ_parts[i]
		if typeof(part_any) != TYPE_DICTIONARY:
			continue
		var part: Dictionary = part_any
		var node: Node3D = part.get("node", null)
		if node == null or not is_instance_valid(node):
			continue
		var rest: Vector3 = part.get("rest", Vector3.ZERO)
		var vel: Vector3 = part.get("vel", Vector3.ZERO)
		var phase: float = float(part.get("phase", 0.0))
		var hover_mul := 1.0
		if i == _hovered_part_i:
			hover_mul = 4.2
			# Continuous poke while hovered.
			vel += Vector3(
				sin(_jiggle_time * 22.0 + phase) * 0.55,
				cos(_jiggle_time * 19.0 + phase * 1.1) * 0.7,
				sin(_jiggle_time * 17.0 + phase * 0.6) * 0.45
			) * delta * 18.0
		var amp := 0.005 * move_amp * hover_mul
		var idle := Vector3(
			sin(_jiggle_time * 3.1 + phase) * amp,
			sin(_jiggle_time * 4.2 + phase * 1.3) * amp * 0.55,
			# Keep depth jiggle tiny so coplanar organs do not z-fight.
			cos(_jiggle_time * 2.7 + phase * 0.7) * amp * 0.22
		)
		if _moving:
			idle.y += sin(_jiggle_time * 14.0 + phase) * 0.02
		var target := rest + idle
		var spring_k := 52.0 if i != _hovered_part_i else 70.0
		var damp := 8.5 if i != _hovered_part_i else 6.0
		var force := (target - node.position) * spring_k - vel * damp
		vel += force * delta
		node.position += vel * delta
		part["vel"] = vel
		# Subtle scale punch on hover (whole organ part).
		var base_s := 1.06 if bool(part.get("selected_scale", false)) else 1.0
		var hs := 1.14 if i == _hovered_part_i else 1.0
		node.scale = Vector3.ONE * (base_s * hs)

func _orient_organs_to_camera() -> void:
	# Keep the humanoid cluster facing the camera (yaw only). Floor rings/tags stay world-aligned.
	if _organs_root == null or _ragdolling:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var cam := vp.get_camera_3d()
	if cam == null:
		return
	var to_cam := cam.global_position - global_position
	to_cam.y = 0.0
	if to_cam.length_squared() < 0.0001:
		return
	_organs_root.rotation.y = atan2(to_cam.x, to_cam.z)
	# Keep pin joints in the same yaw space as organ rests.
	if _joints_root != null:
		_joints_root.rotation.y = _organs_root.rotation.y

func sync_from_squad(squad, selected: bool, cell_size: float, has_move: bool = false, has_action: bool = false, attach_eligible: bool = false, current_turn: int = -1) -> void:
	if squad == null:
		return
	_cell_size = cell_size
	_owner_color = Color(0.28, 0.82, 1.0) if int(squad.owner) != 1 else Color(1.0, 0.38, 0.42)

	var target := Vector3((squad.cell.x + 0.5) * cell_size, 0.20, (squad.cell.y + 0.5) * cell_size)
	_animate_move_to(target)

	_sync_organ_layout(squad, _owner_color, selected)

	var organ_count := int(squad.unit_count_alive()) if squad.has_method("unit_count_alive") else int(squad.units.size())
	# Cooldown detail is in HUD inspect; keep board tag sparse (K1).
	var locked := "·L" if bool(squad.organs_locked) else ""
	var fresh := "·F" if current_turn >= 0 and int(squad.fresh_turn) == current_turn else ""
	if label:
		label.text = "M-%02d%s%s" % [int(squad.id), locked, fresh]
		# Seat color is the default tag — amber/mint only for avail/attach cues.
		if attach_eligible:
			label.modulate = Color(0.55, 1.0, 0.62, 1.0)
		elif has_move or has_action:
			label.modulate = Color(
				lerpf(_owner_color.r, 1.0, 0.35),
				lerpf(_owner_color.g, 0.9, 0.25),
				lerpf(_owner_color.b, 0.4, 0.2),
				1.0
			)
		else:
			label.modulate = _owner_color
		label.font_size = 22
		label.outline_size = 5
		label.outline_modulate = Color(0.02, 0.02, 0.03, 0.9)
		label.position = Vector3(0.38, 0.72, 0.0)
		label.pixel_size = 0.008

	_render_pips(organ_count)
	var is_fresh := current_turn >= 0 and int(squad.fresh_turn) == current_turn
	if (not _avail_built) or has_move != _last_has_move or has_action != _last_has_action or attach_eligible != _last_attach_eligible or selected != _last_selected:
		_last_has_move = has_move
		_last_has_action = has_action
		_last_attach_eligible = attach_eligible
		_last_selected = selected
		_avail_built = true
		_render_availability(has_move, has_action, attach_eligible, is_fresh, selected)

var _move_start: Vector3 = Vector3.ZERO
var _move_target: Vector3 = Vector3.ZERO

func _animate_move_to(target: Vector3) -> void:
	if _ragdolling:
		reseat_ragdoll()
	if not _placed:
		position = target
		_placed = true
		_moving = false
		return
	if position.distance_to(target) < 0.02:
		position = target
		_moving = false
		return
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
	_moving = true
	_move_start = position
	_move_target = target
	var dist := _move_start.distance_to(_move_target)
	var dur := clampf(0.18 + dist * 0.12, 0.22, 0.45)
	_move_tween = create_tween()
	_move_tween.tween_method(_move_step, 0.0, 1.0, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_move_tween.tween_callback(_move_finished)

func _move_step(t: float) -> void:
	var p := _move_start.lerp(_move_target, t)
	p.y = 0.20 + sin(t * PI) * 0.22
	position = p
	_nudge_organs_for_stride(t)

func _move_finished() -> void:
	position = _move_target
	_moving = false

func _nudge_organs_for_stride(t: float) -> void:
	for part_any in _organ_parts:
		if typeof(part_any) != TYPE_DICTIONARY:
			continue
		var part: Dictionary = part_any
		var vel: Vector3 = part.get("vel", Vector3.ZERO)
		vel.y += sin(t * PI * 2.0 + float(part.get("phase", 0.0))) * 0.015
		part["vel"] = vel

func _sync_organ_layout(squad, owner_color: Color, selected: bool) -> void:
	if _organs_root == null:
		return
	var slots := _slots_sorted_by_stack(_assign_slots(squad))
	if _try_incremental_organ_pop(slots):
		pass
	elif _try_incremental_organ_grow(slots, owner_color, selected):
		pass
	else:
		# Never free+respawn the whole stack — rematch survivors in place (avoids fake falling duplicates).
		_rematch_organ_layout(slots, selected, true)

	var scale_mul := 1.08 if selected else 1.0
	for part_any in _organ_parts:
		var part: Dictionary = part_any
		part["selected_scale"] = selected
		var node: Node3D = part.get("node", null)
		if node == null:
			continue
		if not _ragdolling:
			node.scale = Vector3.ONE * scale_mul
		var is_front := int(part.get("stack_i", -1)) == 0 and _organ_parts.size() > 1
		var is_mutant := bool(part.get("is_mutant", false))
		# Team rim/tint — readable at board zoom without washing organs white.
		var outline_col := Color(1.0, 0.45, 0.15, 1.0) if is_front else owner_color
		var outline_mix := 0.38
		if selected:
			outline_col = Color(
				clampf(owner_color.r * 1.15 + 0.1, 0.0, 1.0),
				clampf(owner_color.g * 1.1 + 0.08, 0.0, 1.0),
				clampf(owner_color.b * 1.08 + 0.06, 0.0, 1.0),
				1.0
			)
			outline_mix = 0.62
		elif not is_front:
			outline_col = Color(
				clampf(owner_color.r * 1.08 + 0.06, 0.0, 1.0),
				clampf(owner_color.g * 1.05 + 0.05, 0.0, 1.0),
				clampf(owner_color.b * 1.04 + 0.04, 0.0, 1.0),
				1.0
			)
			outline_mix = 0.42
		var outline_key := "%s|%.2f|%s" % [outline_col, outline_mix, is_mutant]
		if str(part.get("_outline_key", "")) != outline_key:
			part["_outline_key"] = outline_key
			var visual: Node = part.get("visual", null)
			if visual == null and node != null:
				visual = node.get_node_or_null("Visual")
			if visual != null and visual.has_method("set_outline"):
				visual.call("set_outline", outline_col, outline_mix)
		var visual: Node = part.get("visual", null)
		if visual == null and node != null:
			visual = node.get_node_or_null("Visual")
		if visual != null and visual.has_method("set_tint"):
			# Near-neutral tint — keep emoji chroma (not a lightening pass).
			visual.call("set_tint", Color(
				0.94 + owner_color.r * 0.06,
				0.94 + owner_color.g * 0.05,
				0.94 + owner_color.b * 0.05,
				1.0
			))
		_apply_organ_mirror(part, _slot_mirror_x(str(part.get("slot_id", ""))))

func _free_organ_node(node: Node) -> void:
	## Immediate free — queue_free leaves RigidBodies in-tree one frame (fake falling duplicate).
	if node == null or not is_instance_valid(node):
		return
	var p := node.get_parent()
	if p != null:
		p.remove_child(node)
	node.free()

func _make_organ_part_dict(body: RigidBody3D, slot: Dictionary, selected: bool, phase: float) -> Dictionary:
	return {
		"node": body,
		"visual": body.get_node_or_null("Visual"),
		"rest": slot.get("rest", Vector3.ZERO),
		"vel": Vector3.ZERO,
		"phase": phase,
		"def_id": str(slot.get("def_id", "")),
		"slot_id": str(slot.get("slot_id", "")),
		"is_mutant": bool(slot.get("is_mutant", false)),
		"stack_i": int(slot.get("stack_i", 0)),
		"selected_scale": selected,
	}

## Rematch living organs to new slots; corpse + free only true removals; spawn only newcomers.
func _rematch_organ_layout(slots: Array, selected: bool, emit_corpses: bool) -> void:
	_invalidate_ragdoll_timer()
	_cancel_hit_flash()
	_hovered_part_i = -1
	if _ragdolling:
		reseat_ragdoll()

	var old_sorted: Array = _organ_parts.duplicate()
	old_sorted.sort_custom(_sort_parts_by_stack_i)
	var new_sorted: Array = _slots_sorted_by_stack(slots)
	var removed: Array = _diff_removed_organs_multiset(old_sorted, new_sorted)
	# Attach/grow must never shed corpses for still-living organs.
	if emit_corpses and not removed.is_empty() and new_sorted.size() < old_sorted.size():
		_apply_removed_organ_corpse_fx(removed)
	elif emit_corpses and not removed.is_empty() and new_sorted.size() >= old_sorted.size():
		# Count did not drop — treat as layout remap, not a pop (prevents fake attach corpses).
		removed.clear()

	_clear_joints()
	var removed_nodes := {}
	for part_any in removed:
		var part: Dictionary = part_any
		var node: Node = part.get("node", null)
		if node != null:
			removed_nodes[node.get_instance_id()] = true
		_organ_parts.erase(part)
		_free_organ_node(node)

	var used_old: Dictionary = {}
	var remapped: Array = []
	for ns_any in new_sorted:
		var ns: Dictionary = ns_any
		var want := _slot_signature(ns)
		var matched := false
		for oi in range(old_sorted.size()):
			if bool(used_old.get(oi, false)):
				continue
			var op: Dictionary = old_sorted[oi]
			var node_chk: Node = op.get("node", null)
			if node_chk != null and bool(removed_nodes.get(node_chk.get_instance_id(), false)):
				continue
			if not is_instance_valid(node_chk):
				continue
			if _organ_part_signature(op) != want:
				continue
			used_old[oi] = true
			op["rest"] = ns.get("rest", Vector3.ZERO)
			op["stack_i"] = int(ns.get("stack_i", 0))
			op["slot_id"] = str(ns.get("slot_id", ""))
			op["is_mutant"] = bool(ns.get("is_mutant", false))
			op["def_id"] = str(ns.get("def_id", ""))
			op["selected_scale"] = selected
			var body: RigidBody3D = node_chk as RigidBody3D
			if body != null:
				body.freeze = true
				body.top_level = false
				body.linear_velocity = Vector3.ZERO
				body.angular_velocity = Vector3.ZERO
				if not _ragdolling:
					body.position = op.get("rest", Vector3.ZERO)
					body.rotation = Vector3.ZERO
			_apply_organ_mirror(op, _slot_mirror_x(str(op.get("slot_id", ""))))
			remapped.append(op)
			matched = true
			break
		if not matched:
			var rest: Vector3 = ns.get("rest", Vector3.ZERO)
			var slot_id := str(ns.get("slot_id", ""))
			var body_new := _make_organ_body(
				str(ns.get("def_id", "")),
				rest,
				int(ns.get("stack_i", 0)) == 0,
				_slot_mirror_x(slot_id),
				bool(ns.get("is_mutant", false))
			)
			_organs_root.add_child(body_new)
			body_new.position = rest
			remapped.append(_make_organ_part_dict(body_new, ns, selected, float(remapped.size()) * 1.7))

	# Orphaned visuals that fell out of rematch (should be rare) — free immediately, no corpse.
	for oi2 in range(old_sorted.size()):
		if bool(used_old.get(oi2, false)):
			continue
		var orphan: Dictionary = old_sorted[oi2]
		var onode: Node = orphan.get("node", null)
		if onode != null and bool(removed_nodes.get(onode.get_instance_id(), false)):
			continue
		_free_organ_node(onode)

	_organ_parts = remapped
	_ragdolling = false
	_rebuild_joints()
	_attach_torso_shadow()

func _apply_organ_layout_rebuild_or_update(slots: Array, _owner_color: Color, selected: bool) -> void:
	# Kept as a thin alias for callers/tests — always rematch, never mass queue_free.
	_rematch_organ_layout(slots, selected, true)

func _slot_mirror_x(slot_id: String) -> bool:
	# Right-side limb slots mirror the emoji so arms/legs face outward symmetrically.
	return slot_id == "arm_r" or slot_id == "leg_r"

func _apply_organ_mirror(part: Dictionary, mirror_x: bool) -> void:
	var visual: Node = part.get("visual", null)
	if visual == null:
		var node: Node = part.get("node", null)
		if node != null:
			visual = node.get_node_or_null("Visual")
	if visual != null and visual.has_method("set_mirror"):
		visual.call("set_mirror", mirror_x)

func _make_organ_body(def_id: String, rest: Vector3, is_torso_hint: bool, mirror_x: bool = false, is_mutant: bool = false) -> RigidBody3D:
	var body := RigidBody3D.new()
	var organ_scale := UnitDefsScript.organ_scale_for(def_id, is_mutant)
	var near_torso := rest.distance_to(SLOT_RESTS["torso"]) < 0.08 or is_torso_hint
	body.mass = 0.85 if near_torso else 0.32
	body.gravity_scale = 1.25
	body.linear_damp = 0.55
	body.angular_damp = 0.85
	body.continuous_cd = true
	body.freeze = true
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	body.collision_layer = 2
	body.collision_mask = 1 # floor / world
	body.add_to_group(BattlefieldForceScript.FORCE_GROUP)
	body.set_meta("force_while_frozen", true)
	body.set_meta("organ_ragdoll", true)

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = ORGAN_RADIUS * organ_scale
	shape.shape = sphere
	body.add_child(shape)

	var visual = OrganEmojiPartScript.new()
	visual.name = "Visual"
	visual.configure(def_id, Vector3.ZERO, _organ_pixel * organ_scale)
	if mirror_x and visual.has_method("set_mirror"):
		visual.call("set_mirror", true)
	# Stable depth bias from rest.z so overlapping glyphs do not flicker.
	if visual.has_method("set_sort_bias"):
		visual.call("set_sort_bias", rest.z * 8.0 + rest.y * 2.0)
	body.add_child(visual)
	return body

func _clear_joints() -> void:
	if _joints_root == null:
		return
	for c in _joints_root.get_children():
		c.queue_free()

func _rebuild_joints() -> void:
	_clear_joints()
	if _organ_parts.size() < 2:
		return
	var torso: RigidBody3D = null
	var best := 999.0
	for part_any in _organ_parts:
		var part: Dictionary = part_any
		var rest: Vector3 = part.get("rest", Vector3.ZERO)
		var d := rest.distance_to(SLOT_RESTS["torso"])
		if d < best:
			var node = part.get("node")
			if node != null and is_instance_valid(node):
				best = d
				torso = node as RigidBody3D
	if torso == null or not is_instance_valid(torso):
		var first = _organ_parts[0].get("node")
		if first != null and is_instance_valid(first):
			torso = first as RigidBody3D
	if torso == null or not is_instance_valid(torso):
		return
	for part_any in _organ_parts:
		var part: Dictionary = part_any
		var body_any = part.get("node")
		if body_any == null or not is_instance_valid(body_any) or body_any == torso:
			continue
		var body := body_any as RigidBody3D
		if body == null:
			continue
		var joint := PinJoint3D.new()
		joint.node_a = _joints_root.get_path_to(torso)
		joint.node_b = _joints_root.get_path_to(body)
		_joints_root.add_child(joint)
		# Anchor near midpoint in torso local space.
		var mid: Vector3 = (torso.position + body.position) * 0.5
		joint.position = mid

func _attach_torso_shadow() -> void:
	var torso: Node3D = null
	var best := 999.0
	for part_any in _organ_parts:
		var part: Dictionary = part_any
		var rest: Vector3 = part.get("rest", Vector3.ZERO)
		var d := rest.distance_to(SLOT_RESTS["torso"])
		if d < best:
			var node = part.get("node")
			if node != null and is_instance_valid(node):
				best = d
				torso = node as Node3D
	if (torso == null or not is_instance_valid(torso)) and not _organ_parts.is_empty():
		var first = _organ_parts[0].get("node")
		if first != null and is_instance_valid(first):
			torso = first as Node3D
	if torso == null or not is_instance_valid(torso):
		return
	var board_half := 7.2
	var board_center := Vector2(7.0, 7.0)
	ContactShadowScript.attach(torso, Vector2(0.28, 0.28), 0.11, board_center, board_half, ORGAN_RADIUS * 2.0)

func enter_ragdoll(impulse: Vector3 = Vector3.ZERO, duration_scale: float = 1.0) -> void:
	if _organ_parts.is_empty():
		return
	_ragdolling = true
	_hovered_part_i = -1
	# Soften impulse so organs flop in-place instead of leaving the cell frame.
	var soft := impulse
	if soft.length() > 4.5:
		soft = soft.normalized() * 4.5
	# Joints fight top_level bodies — drop during ragdoll, rebuild on reseat.
	_clear_joints()
	for part_any in _organ_parts:
		var part: Dictionary = part_any
		var body: RigidBody3D = part.get("node") as RigidBody3D
		if body == null or not is_instance_valid(body):
			continue
		var gp := body.global_position
		var gb := body.global_basis
		body.top_level = true
		body.global_position = gp
		body.global_basis = gb
		body.freeze = false
		body.sleeping = false
		var mul := 1.0 if body.mass > 0.5 else 0.55
		var kick := soft
		if kick.length_squared() < 0.01:
			kick = Vector3(randf_range(-0.8, 0.8), randf_range(1.2, 2.2), randf_range(-0.8, 0.8))
		body.apply_central_impulse(kick * mul)
		body.apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * kick.length() * 0.05)
	_schedule_ragdoll_reseat(duration_scale)

func _cancel_hit_flash() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = null

func _invalidate_ragdoll_timer() -> void:
	_ragdoll_gen += 1
	_ragdoll_timer = null

func _schedule_ragdoll_reseat(duration_scale: float) -> void:
	_ragdoll_gen += 1
	var gen := _ragdoll_gen
	var wait := RAGDOLL_SEAT_SEC * clampf(duration_scale, 0.55, 1.6)
	_ragdoll_timer = get_tree().create_timer(wait)
	_ragdoll_timer.timeout.connect(func() -> void:
		if gen != _ragdoll_gen:
			return
		if not is_instance_valid(self):
			return
		reseat_ragdoll()
	, CONNECT_ONE_SHOT)

func reseat_ragdoll() -> void:
	_invalidate_ragdoll_timer()
	_ragdolling = false
	for part_any in _organ_parts:
		var part: Dictionary = part_any
		var body: RigidBody3D = part.get("node") as RigidBody3D
		if body == null or not is_instance_valid(body):
			continue
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.freeze = true
		body.sleeping = true
		body.top_level = false
		body.position = part.get("rest", Vector3.ZERO)
		body.rotation = Vector3.ZERO
		body.scale = Vector3.ONE
		part["vel"] = Vector3.ZERO
	_rebuild_joints()

func is_ragdolling() -> bool:
	return _ragdolling

func _organ_part_signature(part: Dictionary) -> String:
	return "%s|%s" % [str(part.get("def_id", "")), "M" if bool(part.get("is_mutant", false)) else ""]

func _slot_signature(slot: Dictionary) -> String:
	return "%s|%s" % [str(slot.get("def_id", "")), "M" if bool(slot.get("is_mutant", false)) else ""]

func _sort_parts_by_stack_i(a, b) -> bool:
	return int((a as Dictionary).get("stack_i", 0)) < int((b as Dictionary).get("stack_i", 0))

func _slots_sorted_by_stack(slots: Array) -> Array:
	var out: Array = slots.duplicate()
	out.sort_custom(_sort_parts_by_stack_i)
	return out

## Front-first diff: sim pops from stack index 0 upward; match survivors in that order.
func _diff_removed_organs_front_first(old_sorted: Array, new_sorted: Array) -> Array:
	var removed: Array = []
	var oi := 0
	var ni := 0
	while oi < old_sorted.size() and ni < new_sorted.size():
		var op: Dictionary = old_sorted[oi]
		var ns: Dictionary = new_sorted[ni]
		if _organ_part_signature(op) == _slot_signature(ns):
			oi += 1
			ni += 1
		else:
			removed.append(op)
			oi += 1
	while oi < old_sorted.size():
		removed.append(old_sorted[oi])
		oi += 1
	return removed

## Multiset diff: only organs whose signature count dropped (safe for core-sink reorder on attach).
func _diff_removed_organs_multiset(old_sorted: Array, new_sorted: Array) -> Array:
	var new_counts: Dictionary = {}
	for ns_any in new_sorted:
		var ns: Dictionary = ns_any
		var sig := _slot_signature(ns)
		new_counts[sig] = int(new_counts.get(sig, 0)) + 1
	var removed: Array = []
	for op_any in old_sorted:
		var op: Dictionary = op_any
		var sig2 := _organ_part_signature(op)
		var left := int(new_counts.get(sig2, 0))
		if left > 0:
			new_counts[sig2] = left - 1
		else:
			removed.append(op)
	return removed

func _pair_survivor_slots(old_sorted: Array, new_sorted: Array) -> Array:
	var pairs: Array = []
	var oi := 0
	var ni := 0
	while oi < old_sorted.size() and ni < new_sorted.size():
		var op: Dictionary = old_sorted[oi]
		var ns: Dictionary = new_sorted[ni]
		if _organ_part_signature(op) == _slot_signature(ns):
			pairs.append({"part": op, "slot": ns})
			oi += 1
			ni += 1
		else:
			oi += 1
	return pairs

func _apply_removed_organ_corpse_fx(removed: Array) -> void:
	if removed.is_empty():
		return
	for part_any in removed:
		var part: Dictionary = part_any
		var node: Node3D = part.get("node", null)
		_emit_organ_corpse(str(part.get("def_id", "")), _corpse_spawn_pos(node))
	var intensity := 0.72 if removed.size() == 1 else 0.9
	_request_separation_sweep(intensity)

func _try_incremental_organ_pop(slots: Array) -> bool:
	if _organ_parts.is_empty() or slots.is_empty():
		return false
	if _organ_parts.size() <= slots.size():
		return false
	var old_sorted: Array = _organ_parts.duplicate()
	old_sorted.sort_custom(_sort_parts_by_stack_i)
	var new_sorted: Array = _slots_sorted_by_stack(slots)
	var removed: Array = _diff_removed_organs_front_first(old_sorted, new_sorted)
	var expected_removed := _organ_parts.size() - slots.size()
	if removed.size() != expected_removed:
		return false
	var pairs: Array = _pair_survivor_slots(old_sorted, new_sorted)
	if pairs.size() != slots.size():
		return false

	_invalidate_ragdoll_timer()
	_cancel_hit_flash()
	_apply_removed_organ_corpse_fx(removed)
	for part_any in removed:
		var part: Dictionary = part_any
		_organ_parts.erase(part)
		var node: Node3D = part.get("node", null)
		_free_organ_node(node)

	var reordered: Array = []
	for pair_any in pairs:
		var pair: Dictionary = pair_any
		var part: Dictionary = pair.get("part", {})
		var slot: Dictionary = pair.get("slot", {})
		part["rest"] = slot.get("rest", Vector3.ZERO)
		part["stack_i"] = int(slot.get("stack_i", 0))
		part["slot_id"] = str(slot.get("slot_id", ""))
		part["is_mutant"] = bool(slot.get("is_mutant", false))
		var node: Node3D = part.get("node", null)
		if node != null and not _ragdolling:
			node.position = part.get("rest", Vector3.ZERO)
		_apply_organ_mirror(part, _slot_mirror_x(str(part.get("slot_id", ""))))
		reordered.append(part)
	_organ_parts = reordered
	_rebuild_joints()
	_attach_torso_shadow()
	return true

func _try_incremental_organ_grow(slots: Array, _owner_color: Color, selected: bool) -> bool:
	if _organ_parts.is_empty() or slots.size() <= _organ_parts.size():
		return false
	var old_sorted: Array = _organ_parts.duplicate()
	old_sorted.sort_custom(_sort_parts_by_stack_i)
	var new_sorted: Array = _slots_sorted_by_stack(slots)
	# Prefix match (no reorder) OR multiset survivors still present (core-sink attach).
	var prefix_ok := true
	for i in range(old_sorted.size()):
		var op: Dictionary = old_sorted[i]
		var ns: Dictionary = new_sorted[i]
		if _organ_part_signature(op) != _slot_signature(ns):
			prefix_ok = false
			break
		if str(op.get("slot_id", "")) != str(ns.get("slot_id", "")):
			prefix_ok = false
			break
	if not prefix_ok:
		var removed_check: Array = _diff_removed_organs_multiset(old_sorted, new_sorted)
		if not removed_check.is_empty():
			return false
		# Reorder grow: rematch old parts to new slots by signature, then append newcomers.
		var used_old: Dictionary = {}
		var remapped: Array = []
		for ns_any in new_sorted:
			var ns2: Dictionary = ns_any
			var want := _slot_signature(ns2)
			var matched := false
			for oi in range(old_sorted.size()):
				if bool(used_old.get(oi, false)):
					continue
				var op2: Dictionary = old_sorted[oi]
				if _organ_part_signature(op2) != want:
					continue
				used_old[oi] = true
				op2["rest"] = ns2.get("rest", Vector3.ZERO)
				op2["stack_i"] = int(ns2.get("stack_i", 0))
				op2["slot_id"] = str(ns2.get("slot_id", ""))
				op2["is_mutant"] = bool(ns2.get("is_mutant", false))
				var node2: Node3D = op2.get("node", null)
				if node2 != null and not _ragdolling:
					node2.position = op2.get("rest", Vector3.ZERO)
				_apply_organ_mirror(op2, _slot_mirror_x(str(op2.get("slot_id", ""))))
				remapped.append(op2)
				matched = true
				break
			if not matched:
				var rest: Vector3 = ns2.get("rest", Vector3.ZERO)
				var slot_id := str(ns2.get("slot_id", ""))
				var mirror_x := _slot_mirror_x(slot_id)
				var is_mutant := bool(ns2.get("is_mutant", false))
				var body := _make_organ_body(str(ns2.get("def_id", "")), rest, int(ns2.get("stack_i", 0)) == 0, mirror_x, is_mutant)
				_organs_root.add_child(body)
				body.position = rest
				remapped.append({
					"node": body,
					"visual": body.get_node_or_null("Visual"),
					"rest": rest,
					"vel": Vector3.ZERO,
					"phase": float(remapped.size()) * 1.7,
					"def_id": str(ns2.get("def_id", "")),
					"slot_id": slot_id,
					"is_mutant": is_mutant,
					"stack_i": int(ns2.get("stack_i", remapped.size())),
					"selected_scale": selected,
				})
		if remapped.size() != new_sorted.size():
			return false
		_organ_parts = remapped
		_rebuild_joints()
		_attach_torso_shadow()
		return true
	for i in range(old_sorted.size(), new_sorted.size()):
		var slot: Dictionary = new_sorted[i]
		var rest: Vector3 = slot.get("rest", Vector3.ZERO)
		var slot_id := str(slot.get("slot_id", ""))
		var mirror_x := _slot_mirror_x(slot_id)
		var is_mutant := bool(slot.get("is_mutant", false))
		var body := _make_organ_body(str(slot.get("def_id", "")), rest, i == 0, mirror_x, is_mutant)
		_organs_root.add_child(body)
		body.position = rest
		_organ_parts.append({
			"node": body,
			"visual": body.get_node_or_null("Visual"),
			"rest": rest,
			"vel": Vector3.ZERO,
			"phase": float(i) * 1.7,
			"def_id": str(slot.get("def_id", "")),
			"slot_id": slot_id,
			"is_mutant": is_mutant,
			"stack_i": int(slot.get("stack_i", i)),
			"selected_scale": selected,
		})
	_rebuild_joints()
	_attach_torso_shadow()
	return true

func _spawn_corpses_for_removed(new_slots: Array) -> void:
	if _organ_parts.is_empty():
		return
	var old_sorted: Array = _organ_parts.duplicate()
	old_sorted.sort_custom(_sort_parts_by_stack_i)
	var new_sorted: Array = _slots_sorted_by_stack(new_slots)
	# Rebuild can reorder (core sinks to back on attach) — never corpse still-living organs.
	var removed: Array = _diff_removed_organs_multiset(old_sorted, new_sorted)
	_apply_removed_organ_corpse_fx(removed)

func shed_all_organs_as_corpses() -> void:
	_invalidate_ragdoll_timer()
	_cancel_hit_flash()
	_ragdolling = false
	var shed_n := _organ_parts.size()
	var to_free: Array = []
	for part_any in _organ_parts:
		if typeof(part_any) != TYPE_DICTIONARY:
			continue
		var part: Dictionary = part_any
		var def_id := str(part.get("def_id", ""))
		var node: Node3D = part.get("node", null)
		_emit_organ_corpse(def_id, _corpse_spawn_pos(node))
		to_free.append(node)
	_organ_parts.clear()
	for n_any in to_free:
		_free_organ_node(n_any)
	if shed_n > 0:
		_request_separation_sweep(1.0)

func _request_separation_sweep(intensity: float) -> void:
	var focus := global_position + Vector3(0, 0.45, 0)
	var ctrl = get_tree().get_first_node_in_group("camera_controller")
	if ctrl != null and ctrl.has_method("play_separation_sweep"):
		ctrl.call("play_separation_sweep", focus, intensity, self)

func _corpse_spawn_pos(node: Node3D) -> Vector3:
	var gp := global_position + Vector3(0, 0.55, 0)
	if node != null and is_instance_valid(node):
		if node.is_inside_tree():
			gp = node.global_position
		else:
			gp = global_position + node.position
	gp.y = maxf(gp.y, 0.4)
	return gp

func _emit_organ_corpse(def_id: String, global_pos: Vector3) -> void:
	var root := _find_corpses_root()
	if root == null:
		return
	if root.has_method("spawn_organ_corpse"):
		root.call(
			"spawn_organ_corpse",
			def_id,
			global_pos,
			Vector3(randf_range(-1.6, 1.6), randf_range(2.2, 3.6), randf_range(-1.6, 1.6))
		)
		return
	# Fallback: BoardView may expose Corpses child directly via parent chain.
	var board := _find_board_view()
	if board != null and board.has_method("spawn_organ_corpse"):
		board.call(
			"spawn_organ_corpse",
			def_id,
			global_pos,
			Vector3(randf_range(-1.6, 1.6), randf_range(2.2, 3.6), randf_range(-1.6, 1.6))
		)

func _find_board_view() -> Node:
	var n: Node = get_parent()
	while n != null:
		if n.has_method("spawn_organ_corpse"):
			return n
		n = n.get_parent()
	return null

func _find_corpses_root() -> Node:
	return _find_board_view()

func _update_hovered_organ() -> void:
	if _hover_forced:
		return
	_hovered_part_i = -1
	if _organ_parts.is_empty():
		return
	if _ragdolling:
		return
	# HUD / UI hover takes priority over organ jiggle hover.
	if _pointer_over_blocking_ui():
		return
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp != null else null
	if cam == null or vp == null:
		return
	var mouse := vp.get_mouse_position()
	var from := cam.project_ray_origin(mouse)
	var dir := cam.project_ray_normal(mouse)
	if dir.length_squared() < 0.0001:
		return
	dir = dir.normalized()
	var best_d := 0.16
	for i in range(_organ_parts.size()):
		var part: Dictionary = _organ_parts[i]
		var node: Node3D = part.get("node", null)
		if node == null or not is_instance_valid(node):
			continue
		var world: Vector3 = node.global_position
		var w := world - from
		var proj := w.dot(dir)
		if proj < 0.0:
			continue
		var closest := from + dir * proj
		var dist := closest.distance_to(world)
		if dist < best_d:
			best_d = dist
			_hovered_part_i = i

func _pointer_over_blocking_ui() -> bool:
	var vp := get_viewport()
	if vp == null:
		return false
	var mouse := vp.get_mouse_position()
	var tree := get_tree()
	if tree == null:
		return false
	for n in tree.get_nodes_in_group("ui_blocks_board_hover"):
		if n is Control:
			var c := n as Control
			if not c.visible or not c.is_visible_in_tree():
				continue
			if c.mouse_filter == Control.MOUSE_FILTER_IGNORE:
				continue
			if c.get_global_rect().has_point(mouse):
				return true
	# Any STOP HUD control under the cursor (ability keys, skip, etc.).
	var hovered := vp.gui_get_hovered_control()
	if hovered == null:
		return false
	var cur: Node = hovered
	while cur != null:
		if cur is CanvasLayer and str(cur.name) == "HUD":
			return hovered.mouse_filter != Control.MOUSE_FILTER_IGNORE
		if str(cur.name) == "HUDRoot":
			return hovered.mouse_filter != Control.MOUSE_FILTER_IGNORE
		cur = cur.get_parent()
	return false

func debug_force_hover_organ(part_i: int) -> void:
	_hover_forced = true
	_hovered_part_i = part_i

func _assign_slots(squad) -> Array:
	var organ_entries: Array = []
	var stack_i := 0
	for u_any in squad.units:
		var u = u_any
		if u == null or int(u.hp) <= 0:
			continue
		organ_entries.append({
			"def_id": str(u.unit_def_id),
			"stack_i": stack_i,
			"is_mutant": bool(u.is_mutant),
		})
		stack_i += 1

	var free := {
		"head": true,
		"torso": true,
		"arm_l": true,
		"arm_r": true,
		"leg_l": true,
		"leg_r": true,
	}
	var assigned: Array = []
	var leftovers: Array = []

	for entry_any in organ_entries:
		var entry: Dictionary = entry_any
		var def_id := str(entry.get("def_id", ""))
		var si := int(entry.get("stack_i", 0))
		var hint := UnitDefsScript.body_slot(def_id)
		var placed := false
		match hint:
			"head":
				if free["head"]:
					free["head"] = false
					assigned.append(_slot_entry(def_id, SLOT_RESTS["head"], si, "head", bool(entry.get("is_mutant", false))))
					placed = true
			"torso":
				if free["torso"]:
					free["torso"] = false
					assigned.append(_slot_entry(def_id, SLOT_RESTS["torso"], si, "torso", bool(entry.get("is_mutant", false))))
					placed = true
			"arm":
				if free["arm_l"]:
					free["arm_l"] = false
					assigned.append(_slot_entry(def_id, SLOT_RESTS["arm_l"], si, "arm_l", bool(entry.get("is_mutant", false))))
					placed = true
				elif free["arm_r"]:
					free["arm_r"] = false
					assigned.append(_slot_entry(def_id, SLOT_RESTS["arm_r"], si, "arm_r", bool(entry.get("is_mutant", false))))
					placed = true
			"leg":
				if free["leg_l"]:
					free["leg_l"] = false
					assigned.append(_slot_entry(def_id, SLOT_RESTS["leg_l"], si, "leg_l", bool(entry.get("is_mutant", false))))
					placed = true
				elif free["leg_r"]:
					free["leg_r"] = false
					assigned.append(_slot_entry(def_id, SLOT_RESTS["leg_r"], si, "leg_r", bool(entry.get("is_mutant", false))))
					placed = true
			_:
				pass
		if not placed:
			leftovers.append(entry)

	var fill_order := ["torso", "head", "arm_l", "arm_r", "leg_l", "leg_r"]
	var still: Array = []
	for entry_any in leftovers:
		var entry: Dictionary = entry_any
		var def_id := str(entry.get("def_id", ""))
		var si := int(entry.get("stack_i", 0))
		var filled := false
		for sk in fill_order:
			if free[sk]:
				free[sk] = false
				assigned.append(_slot_entry(def_id, SLOT_RESTS[sk], si, sk, bool(entry.get("is_mutant", false))))
				filled = true
				break
		if not filled:
			still.append(entry)

	for i in range(still.size()):
		var entry: Dictionary = still[i]
		var ang := float(i) * 1.15
		var rest: Vector3
		if i < EXTRA_RESTS.size():
			rest = EXTRA_RESTS[i]
		else:
			rest = Vector3(cos(ang) * 0.12, 0.32 + 0.04 * float(i % 3), sin(ang) * 0.08)
		assigned.append({
			"def_id": str(entry.get("def_id", "")),
			"rest": rest,
			"stack_i": int(entry.get("stack_i", 0)),
			"slot_id": "extra_%d" % i,
			"is_mutant": bool(entry.get("is_mutant", false)),
		})
	return assigned

func _slot_entry(def_id: String, rest: Vector3, stack_i: int, slot_id: String, is_mutant: bool = false) -> Dictionary:
	return {
		"def_id": def_id,
		"rest": rest,
		"stack_i": stack_i,
		"slot_id": slot_id,
		"is_mutant": is_mutant,
	}

func play_hit_flash() -> void:
	# Tint always; ragdoll only if CombatJuice hasn't already started one.
	if not _ragdolling:
		var kick := Vector3(
			randf_range(-1.6, 1.6),
			randf_range(1.8, 3.2),
			randf_range(-1.6, 1.6)
		)
		enter_ragdoll(kick, 1.0)
	_cancel_hit_flash()
	_flash_tween = create_tween()
	var visuals: Array = []
	for part_any in _organ_parts:
		var part: Dictionary = part_any
		var visual = part.get("visual", null)
		if visual == null:
			var node = part.get("node", null)
			if node != null and is_instance_valid(node):
				visual = (node as Node).get_node_or_null("Visual")
		if visual == null or not is_instance_valid(visual):
			continue
		visuals.append(visual)
		if visual.has_method("set_tint"):
			visual.call("set_tint", Color(1.35, 1.35, 1.35, 1.0))
	_flash_tween.tween_interval(0.08)
	_flash_tween.tween_callback(func() -> void:
		if not is_instance_valid(self):
			return
		for n_any in visuals:
			if not is_instance_valid(n_any):
				continue
			if n_any.has_method("set_tint"):
				n_any.call("set_tint", Color(1, 1, 1, 1))
	)

func play_graft_celebrate() -> void:
	## Brief mint punch when gear/egg grafts onto this mutant — no ragdoll, no corpse.
	_cancel_hit_flash()
	_flash_tween = create_tween()
	var visuals: Array = []
	for part_any in _organ_parts:
		var part: Dictionary = part_any
		var node: Node3D = part.get("node", null)
		if node != null and is_instance_valid(node) and not _ragdolling:
			part["vel"] = Vector3(
				randf_range(-0.8, 0.8),
				randf_range(1.2, 2.2),
				randf_range(-0.8, 0.8)
			)
			node.scale = Vector3.ONE * 1.18
		var visual = part.get("visual", null)
		if visual == null and node != null and is_instance_valid(node):
			visual = node.get_node_or_null("Visual")
		if visual != null and is_instance_valid(visual):
			visuals.append(visual)
			if visual.has_method("set_tint"):
				visual.call("set_tint", Color(0.75, 1.2, 0.95, 1.0))
	_flash_tween.tween_interval(0.16)
	_flash_tween.tween_callback(func() -> void:
		if not is_instance_valid(self):
			return
		for part_any2 in _organ_parts:
			var p2: Dictionary = part_any2
			var n2: Node3D = p2.get("node", null)
			if n2 != null and is_instance_valid(n2) and not _ragdolling:
				n2.scale = Vector3.ONE * (1.06 if bool(p2.get("selected_scale", false)) else 1.0)
		for v_any in visuals:
			if is_instance_valid(v_any) and v_any.has_method("set_tint"):
				v_any.call("set_tint", Color(1, 1, 1, 1))
	)

func reject_pulse() -> void:
	## Brief warn flash when the player tries an ineligible act with this mutant.
	_cancel_hit_flash()
	_flash_tween = create_tween()
	var visuals: Array = []
	var base_scale := scale
	scale = base_scale * Vector3(1.08, 1.0, 1.08)
	for part_any in _organ_parts:
		var part: Dictionary = part_any
		var node: Node3D = part.get("node", null)
		var visual = part.get("visual", null)
		if visual == null and node != null and is_instance_valid(node):
			visual = node.get_node_or_null("Visual")
		if visual != null and is_instance_valid(visual):
			visuals.append(visual)
			if visual.has_method("set_tint"):
				visual.call("set_tint", Color(1.35, 0.55, 0.45, 1.0))
	if _avail_root != null:
		_avail_root.scale = Vector3(1.12, 1.0, 1.12)
	_flash_tween.tween_property(self, "scale", base_scale, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _avail_root != null:
		_flash_tween.parallel().tween_property(_avail_root, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_flash_tween.tween_callback(func() -> void:
		if not is_instance_valid(self):
			return
		for v_any in visuals:
			if is_instance_valid(v_any) and v_any.has_method("set_tint"):
				v_any.call("set_tint", Color(1, 1, 1, 1))
	)

func _render_pips(unit_count: int) -> void:
	if _pips_root == null:
		return
	for c in _pips_root.get_children():
		c.queue_free()
	var n := clampi(unit_count, 0, RulesScript.ORGAN_HARD_MAX)
	var pip_col := Color(
		clampf(_owner_color.r * 1.05 + 0.08, 0.0, 1.0),
		clampf(_owner_color.g * 1.05 + 0.08, 0.0, 1.0),
		clampf(_owner_color.b * 1.05 + 0.08, 0.0, 1.0),
		1.0
	)
	for i in range(n):
		var pip := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = Vector3(0.08, 0.08, 0.08)
		pip.mesh = m
		var mat := StandardMaterial3D.new()
		mat.albedo_color = pip_col
		mat.emission_enabled = true
		mat.emission = pip_col
		mat.emission_energy_multiplier = 0.35
		mat.roughness = 0.9
		pip.material_override = mat
		pip.position = Vector3(-0.12 + i * 0.12, 0.95, 0.0)
		_pips_root.add_child(pip)

func _render_availability(has_move: bool, has_action: bool, attach_eligible: bool = false, is_fresh: bool = false, selected: bool = false) -> void:
	if _avail_root == null:
		return
	for c in _avail_root.get_children():
		c.queue_free()
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
		_pulse_tween = null
	_avail_root.scale = Vector3.ONE
	# Board-native corner brackets (not a filled UI disc).
	var bracket_a := 0.42 if selected else 0.22
	var bracket_half := 0.40 if selected else 0.36
	var bracket_emit := 0.55 if selected else 0.22
	var bracket_col := Color(_owner_color.r, _owner_color.g, _owner_color.b, bracket_a)
	_avail_root.add_child(_make_corner_brackets(bracket_col, 0.01, bracket_half, bracket_emit))
	if is_fresh and not attach_eligible:
		_avail_root.add_child(_make_ring(Color(0.55, 0.82, 1.0, 0.5), 0.03, 0.22))
		_pulse_tween = create_tween()
		_pulse_tween.set_loops()
		_pulse_tween.tween_property(_avail_root, "scale", Vector3(1.05, 1.0, 1.05), 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_pulse_tween.tween_property(_avail_root, "scale", Vector3.ONE, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		return
	if attach_eligible:
		_avail_root.add_child(_make_ring(Color(0.45, 1.0, 0.55, 0.65), 0.02, 0.26))
		_avail_root.add_child(_make_ring(Color(1.0, 0.90, 0.35, 0.55), 0.05, 0.20))
		_pulse_tween = create_tween()
		_pulse_tween.set_loops()
		_pulse_tween.tween_property(_avail_root, "scale", Vector3(1.08, 1.0, 1.08), 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_pulse_tween.tween_property(_avail_root, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		return
	if not has_move and not has_action:
		# Spent / idle: dim brackets only (no breath pulse).
		return
	# Available turn: soft amber ring (single, not opaque slab).
	if has_move:
		_avail_root.add_child(_make_ring(Color(1.0, 0.82, 0.28, 0.5), 0.03, 0.24))
	elif has_action:
		_avail_root.add_child(_make_ring(Color(0.95, 0.72, 0.28, 0.45), 0.03, 0.22))
	_pulse_tween = create_tween()
	_pulse_tween.set_loops()
	_pulse_tween.tween_property(_avail_root, "scale", Vector3(1.05, 1.0, 1.05), 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.tween_property(_avail_root, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _make_corner_brackets(color: Color, y: float, half: float, emit: float = 0.35, thick: float = 0.028, arm: float = 0.12) -> Node3D:
	var root := Node3D.new()
	root.name = "CornerBrackets"
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = Color(color.r, color.g, color.b)
	mat.emission_energy_multiplier = emit
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var corners: Array[Vector2] = [
		Vector2(-1.0, -1.0),
		Vector2(1.0, -1.0),
		Vector2(-1.0, 1.0),
		Vector2(1.0, 1.0),
	]
	for corner in corners:
		var cx := corner.x * half
		var cz := corner.y * half
		var hx := MeshInstance3D.new()
		var hx_mesh := BoxMesh.new()
		hx_mesh.size = Vector3(arm, 0.018, thick)
		hx.mesh = hx_mesh
		hx.material_override = mat
		hx.position = Vector3(cx - corner.x * (arm * 0.5 - thick * 0.5), y, cz)
		root.add_child(hx)
		var hz := MeshInstance3D.new()
		var hz_mesh := BoxMesh.new()
		hz_mesh.size = Vector3(thick, 0.018, arm)
		hz.mesh = hz_mesh
		hz.material_override = mat
		hz.position = Vector3(cx, y, cz - corner.y * (arm * 0.5 - thick * 0.5))
		root.add_child(hz)
	return root

func _make_ring(color: Color, y: float, radius: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = K1Widgets.make_bevel_square_mesh(radius, 0.024, 0.05)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, minf(color.a, 0.55))
	mat.emission_enabled = true
	mat.emission = Color(color.r, color.g, color.b)
	mat.emission_energy_multiplier = 0.55
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.position = Vector3(0.0, y, 0.0)
	return mi