extends Node3D
class_name HitSparkVfx

## Pooled one-shot sparks at organ/impact points.

const POOL_SIZE := 8
const _Self = preload("res://src/presentation/vfx/HitSparkVfx.gd")

static var _free: Array = []

var _burst: GPUParticles3D
var _tween: Tween
var _built: bool = false

static func play(host: Node3D, global_pos: Vector3, intensity: float = 1.0, color: Color = Color(1.0, 0.78, 0.35, 1.0)) -> void:
	if host == null or not host.is_inside_tree():
		return
	var vfx = _acquire(host)
	vfx.global_position = global_pos
	vfx._restart(intensity, color)

static func warmup(host: Node3D, _at: Vector3 = Vector3.ZERO) -> void:
	## Prebuild pool only — no visible spark at match start.
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
	_burst = GPUParticles3D.new()
	_burst.emitting = false
	_burst.one_shot = true
	_burst.explosiveness = 0.92
	_burst.amount = 24
	_burst.lifetime = 0.32
	_burst.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 4, 4))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 160.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 2.8
	pm.gravity = Vector3(0, -6.0, 0)
	pm.scale_min = 0.03
	pm.scale_max = 0.07
	pm.color = Color(1.0, 0.8, 0.4, 1.0)
	_burst.process_material = pm
	var dm := SphereMesh.new()
	dm.radius = 0.035
	dm.height = 0.07
	_burst.draw_pass_1 = dm
	add_child(_burst)
	_built = true

func _restart(intensity: float, color: Color) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var i := clampf(intensity, 0.25, 1.0)
	if _burst.process_material is ParticleProcessMaterial:
		(_burst.process_material as ParticleProcessMaterial).color = color
		(_burst.process_material as ParticleProcessMaterial).initial_velocity_max = 2.0 + 2.0 * i
	visible = true
	_burst.restart()
	_burst.emitting = true
	_tween = create_tween()
	_tween.tween_interval(_burst.lifetime + 0.05)
	_tween.tween_callback(_release)

func _release() -> void:
	if _burst != null:
		_burst.emitting = false
	visible = false
	if not _free.has(self):
		_free.append(self)
