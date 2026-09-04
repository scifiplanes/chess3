extends Node3D
class_name AbilityBurstVfx

## Instant footprint ring + particle burst (no Chillout charge phase).

const POOL_SIZE := 6
const RING_SEGMENTS := 40
const _Self = preload("res://src/presentation/vfx/AbilityBurstVfx.gd")

static var _free: Array = []
static var _ring_mesh: ArrayMesh

var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _burst: GPUParticles3D
var _tween: Tween
var _built: bool = false

static func play(host: Node3D, global_pos: Vector3, radius: float, color: Color = Color(1.0, 0.82, 0.35, 1.0), intensity: float = 1.0) -> void:
	if host == null or not host.is_inside_tree():
		return
	var vfx = _acquire(host)
	vfx.global_position = Vector3(global_pos.x, global_pos.y + 0.12, global_pos.z)
	vfx._fire(radius, color, intensity)

static func warmup(host: Node3D, _at: Vector3 = Vector3.ZERO) -> void:
	## Prebuild pool only — no visible burst at match start.
	if host == null or not host.is_inside_tree():
		return
	_free.clear()
	for _i in POOL_SIZE:
		var vfx = _Self.new()
		host.add_child(vfx)
		vfx._ensure_built()
		vfx.visible = false
		_free.append(vfx)

static func _acquire(host: Node3D):
	while not _free.is_empty():
		var vfx = _free.pop_back()
		if vfx != null and is_instance_valid(vfx):
			if vfx.get_parent() != host:
				if vfx.get_parent() != null:
					vfx.get_parent().remove_child(vfx)
				host.add_child(vfx)
			return vfx
	var fresh = _Self.new()
	host.add_child(fresh)
	fresh._ensure_built()
	return fresh

func _ensure_built() -> void:
	if _built:
		return
	_ensure_ring_mesh()
	_ring = MeshInstance3D.new()
	_ring.mesh = _ring_mesh
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.albedo_color = Color(1, 0.85, 0.4, 0.85)
	_ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)

	_burst = GPUParticles3D.new()
	_burst.emitting = false
	_burst.one_shot = true
	_burst.explosiveness = 0.95
	_burst.amount = 28
	_burst.lifetime = 0.35
	_burst.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 5, 6))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 1.2
	pm.initial_velocity_max = 3.4
	pm.gravity = Vector3(0, -4.5, 0)
	pm.scale_min = 0.04
	pm.scale_max = 0.09
	pm.color = Color(1.0, 0.88, 0.45, 1.0)
	_burst.process_material = pm
	var dm := SphereMesh.new()
	dm.radius = 0.04
	dm.height = 0.08
	_burst.draw_pass_1 = dm
	add_child(_burst)
	_built = true

func _fire(radius: float, color: Color, intensity: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	visible = true
	var r := maxf(radius, 0.35)
	_ring.scale = Vector3(0.15, 1.0, 0.15)
	_ring_mat.albedo_color = Color(color.r, color.g, color.b, 0.9 * clampf(intensity, 0.3, 1.0))
	if _burst.process_material is ParticleProcessMaterial:
		(_burst.process_material as ParticleProcessMaterial).color = color
	_burst.restart()
	_burst.emitting = true
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_ring, "scale", Vector3(r, 1.0, r), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_ring_mat, "albedo_color:a", 0.0, 0.28).set_delay(0.06)
	_tween.set_parallel(false)
	_tween.tween_interval(0.12)
	_tween.tween_callback(_release)

func _release() -> void:
	if _burst != null:
		_burst.emitting = false
	visible = false
	if not _free.has(self):
		_free.append(self)

static func _ensure_ring_mesh() -> void:
	if _ring_mesh != null:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inner := 0.92
	var outer := 1.0
	for i in range(RING_SEGMENTS):
		var a0 := TAU * float(i) / float(RING_SEGMENTS)
		var a1 := TAU * float(i + 1) / float(RING_SEGMENTS)
		var i0 := Vector3(cos(a0) * inner, 0.0, sin(a0) * inner)
		var i1 := Vector3(cos(a1) * inner, 0.0, sin(a1) * inner)
		var o0 := Vector3(cos(a0) * outer, 0.0, sin(a0) * outer)
		var o1 := Vector3(cos(a1) * outer, 0.0, sin(a1) * outer)
		st.add_vertex(i0)
		st.add_vertex(o0)
		st.add_vertex(o1)
		st.add_vertex(i0)
		st.add_vertex(o1)
		st.add_vertex(i1)
	_ring_mesh = st.commit()
