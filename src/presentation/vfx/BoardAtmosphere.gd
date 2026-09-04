extends Node3D
class_name BoardAtmosphere

## Dust motes + soft cloud blobs + top light shaft (Chillout EncounterAtmosphere, trimmed).

const AbilityFootprintScript = preload("res://src/presentation/vfx/AbilityFootprint.gd")

const _DUST_FORCE_SCALE := 0.22
const _FORCE_DAMP := 1.8
const _CLOUD_FORCE_MUL := 0.32
const _CLOUD_FORCE_DAMP := 1.15
const _WHIRL_SCALE := 0.62

var amount: int = 14
var lifetime: float = 28.0
var alpha: float = 0.12
var scale_min: float = 0.85
var scale_max: float = 1.7
var velocity_min: float = 0.008
var velocity_max: float = 0.032
var sphere_radius: float = 0.05
var randomness: float = 0.85

var cloud_amount: int = 5
var cloud_lifetime: float = 55.0
var cloud_alpha: float = 0.032
var cloud_scale_min: float = 0.9
var cloud_scale_max: float = 1.5
var cloud_velocity_min: float = 0.003
var cloud_velocity_max: float = 0.01
var cloud_sphere_radius: float = 2.0
var cloud_randomness: float = 0.55

var shaft_alpha: float = 0.85

var _half: float = 7.0
var _center: Vector3 = Vector3(7.0, 0.0, 7.0)
var _emitting: bool = false

var _dust: MultiMeshInstance3D
var _multimesh: MultiMesh
var _clouds: MultiMeshInstance3D
var _cloud_multimesh: MultiMesh
var _shaft: MeshInstance3D
var _shaft_mat: StandardMaterial3D

var _pos: PackedVector3Array = PackedVector3Array()
var _vel: PackedVector3Array = PackedVector3Array()
var _age: PackedFloat32Array = PackedFloat32Array()
var _life: PackedFloat32Array = PackedFloat32Array()
var _scale: PackedFloat32Array = PackedFloat32Array()

var _cloud_pos: PackedVector3Array = PackedVector3Array()
var _cloud_vel: PackedVector3Array = PackedVector3Array()
var _cloud_age: PackedFloat32Array = PackedFloat32Array()
var _cloud_life: PackedFloat32Array = PackedFloat32Array()
var _cloud_scale: PackedFloat32Array = PackedFloat32Array()

func setup(board_half: float, board_center: Vector3 = Vector3(7.0, 0.0, 7.0)) -> void:
	_half = board_half
	_center = board_center
	_build_dust()
	_build_clouds()
	_build_shaft()
	set_emitting(true)

func set_emitting(on: bool) -> void:
	_emitting = on
	if _dust:
		_dust.visible = on
	if _clouds:
		_clouds.visible = on
	if on:
		_respawn_all(true)
		_respawn_all_clouds(true)

## Cheap move-mode diet: hide dust/clouds without respawn flash.
func set_glitter_visible(on: bool) -> void:
	if _dust:
		_dust.visible = on and _emitting
	if _clouds:
		_clouds.visible = on and _emitting

func apply_ability_force(
	origin: Vector3,
	forward_in: Vector3,
	shape: AbilityFootprintScript.Id,
	radius: float,
	strength: float,
	width: float = 1.2,
	cone_degrees: float = 70.0
) -> void:
	if not _emitting:
		return
	_apply_force_layer(false, origin, forward_in, shape, radius, strength, width, cone_degrees, 1.0)
	_apply_force_layer(true, origin, forward_in, shape, radius, strength, width, cone_degrees, _CLOUD_FORCE_MUL)

func _apply_force_layer(
	clouds: bool,
	origin: Vector3,
	forward_in: Vector3,
	shape: AbilityFootprintScript.Id,
	radius: float,
	strength: float,
	width: float,
	cone_degrees: float,
	force_mul: float
) -> void:
	var forward := AbilityFootprintScript.resolve_forward(forward_in)
	var n := _cloud_pos.size() if clouds else _pos.size()
	for i in n:
		var p: Vector3 = _cloud_pos[i] if clouds else _pos[i]
		var world := p + _center
		if not AbilityFootprintScript.contains(shape, world, origin, forward, radius, width, cone_degrees):
			continue
		var falloff := AbilityFootprintScript.falloff(shape, world, origin, radius, width)
		var to_mote := world - origin
		var dist := to_mote.length()
		var dir: Vector3
		if dist < 0.05:
			dir = Vector3(randf_range(-1, 1), 0.25, randf_range(-1, 1)).normalized()
		else:
			dir = to_mote / dist
		var impulse_mag := strength * falloff * _DUST_FORCE_SCALE * force_mul
		var gust := dir * impulse_mag + Vector3.UP * (impulse_mag * 0.35)
		gust += _whirl_tangent(to_mote) * (impulse_mag * _WHIRL_SCALE)
		if clouds:
			_cloud_vel[i] = _cloud_vel[i] + gust
		else:
			_vel[i] = _vel[i] + gust

func _whirl_tangent(from_aim: Vector3) -> Vector3:
	var tx := -from_aim.z
	var tz := from_aim.x
	var len_sq := tx * tx + tz * tz
	if len_sq < 0.0001:
		return Vector3.ZERO
	var inv := 1.0 / sqrt(len_sq)
	return Vector3(tx * inv, 0.0, tz * inv)

func _process(delta: float) -> void:
	if not _emitting:
		return
	if not _pos.is_empty():
		_simulate(delta)
		_write_multimesh()
	if not _cloud_pos.is_empty():
		_simulate_clouds(delta)
		_write_cloud_multimesh()

func _soft_quad_mesh(radius: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := radius
	# Two triangles facing camera-ish; MultiMesh will billboard via scale only — keep flat XZ soft disc.
	var v0 := Vector3(-r, 0, -r)
	var v1 := Vector3(r, 0, -r)
	var v2 := Vector3(r, 0, r)
	var v3 := Vector3(-r, 0, r)
	st.set_color(Color(1, 1, 1, 1))
	st.add_vertex(v0)
	st.add_vertex(v1)
	st.add_vertex(v2)
	st.add_vertex(v0)
	st.add_vertex(v2)
	st.add_vertex(v3)
	return st.commit()

func _make_draw_mat(a: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 0.95, 0.85, a)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	# Soft radial texture.
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(1, 1, 1, 1),
		Color(1, 1, 1, 0.35),
		Color(1, 1, 1, 0),
	])
	grad.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 64
	tex.height = 64
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	mat.albedo_texture = tex
	return mat

func _build_dust() -> void:
	_dust = MultiMeshInstance3D.new()
	_dust.name = "Dust"
	_dust.position = _center + Vector3(0, 2.2, 0)
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_colors = true
	_multimesh.mesh = _soft_quad_mesh(sphere_radius)
	_multimesh.instance_count = amount
	_dust.multimesh = _multimesh
	_dust.material_override = _make_draw_mat(alpha)
	_dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_dust)
	_resize_motes(amount)

func _build_clouds() -> void:
	_clouds = MultiMeshInstance3D.new()
	_clouds.name = "Clouds"
	_clouds.position = _center + Vector3(0, 2.6, 0)
	_cloud_multimesh = MultiMesh.new()
	_cloud_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_cloud_multimesh.use_colors = true
	_cloud_multimesh.mesh = _soft_quad_mesh(cloud_sphere_radius * 0.35)
	_cloud_multimesh.instance_count = cloud_amount
	_clouds.multimesh = _cloud_multimesh
	_clouds.material_override = _make_draw_mat(cloud_alpha)
	_clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_clouds)
	_resize_clouds(cloud_amount)

func _build_shaft() -> void:
	_shaft = MeshInstance3D.new()
	_shaft.name = "LightShaft"
	var cone := CylinderMesh.new()
	cone.top_radius = _half * 0.12
	cone.bottom_radius = _half * 0.92
	cone.height = 11.0
	cone.radial_segments = 24
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(1.0, 0.96, 0.88, 0.10),
		Color(1.0, 0.94, 0.82, 0.045),
		Color(1.0, 0.92, 0.78, 0.015),
		Color(1.0, 0.92, 0.78, 0.0),
	])
	grad.offsets = PackedFloat32Array([0.0, 0.22, 0.6, 1.0])
	var grad_tex := GradientTexture2D.new()
	grad_tex.gradient = grad
	grad_tex.width = 8
	grad_tex.height = 128
	grad_tex.fill = GradientTexture2D.FILL_LINEAR
	grad_tex.fill_from = Vector2(0.5, 0.0)
	grad_tex.fill_to = Vector2(0.5, 1.0)
	_shaft_mat = StandardMaterial3D.new()
	_shaft_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shaft_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shaft_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_shaft_mat.albedo_texture = grad_tex
	_shaft_mat.albedo_color = Color(1.0, 0.96, 0.88, shaft_alpha)
	_shaft_mat.cull_mode = BaseMaterial3D.CULL_BACK
	_shaft_mat.disable_receive_shadows = true
	cone.material = _shaft_mat
	_shaft.mesh = cone
	_shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shaft.position = _center + Vector3(0.0, 4.8, 0.0)
	add_child(_shaft)

func _resize_motes(n: int) -> void:
	_pos.resize(n)
	_vel.resize(n)
	_age.resize(n)
	_life.resize(n)
	_scale.resize(n)
	if _multimesh:
		_multimesh.instance_count = n
	_respawn_all(true)

func _resize_clouds(n: int) -> void:
	_cloud_pos.resize(n)
	_cloud_vel.resize(n)
	_cloud_age.resize(n)
	_cloud_life.resize(n)
	_cloud_scale.resize(n)
	if _cloud_multimesh:
		_cloud_multimesh.instance_count = n
	_respawn_all_clouds(true)

func _respawn_all(prefill: bool) -> void:
	for i in _pos.size():
		_respawn(i, prefill)

func _respawn_all_clouds(prefill: bool) -> void:
	for i in _cloud_pos.size():
		_respawn_cloud(i, prefill)

func _respawn(i: int, prefill: bool) -> void:
	var ext := _half * 0.85
	_pos[i] = Vector3(randf_range(-ext, ext), randf_range(-1.2, 1.6), randf_range(-ext, ext))
	_vel[i] = Vector3(randf_range(-1, 1), randf_range(-0.2, 0.4), randf_range(-1, 1)).normalized() * randf_range(velocity_min, velocity_max)
	_life[i] = lifetime * randf_range(0.7, 1.3)
	_age[i] = randf_range(0.0, _life[i]) if prefill else 0.0
	_scale[i] = randf_range(scale_min, scale_max)

func _respawn_cloud(i: int, prefill: bool) -> void:
	var ext := _half * 0.75
	_cloud_pos[i] = Vector3(randf_range(-ext, ext), randf_range(-0.6, 1.2), randf_range(-ext, ext))
	_cloud_vel[i] = Vector3(0.15, 0.2, 0.1).normalized() * randf_range(cloud_velocity_min, cloud_velocity_max)
	_cloud_life[i] = cloud_lifetime * randf_range(0.75, 1.25)
	_cloud_age[i] = randf_range(0.0, _cloud_life[i]) if prefill else 0.0
	_cloud_scale[i] = randf_range(cloud_scale_min, cloud_scale_max)

func _simulate(delta: float) -> void:
	var n := _pos.size()
	var damp := exp(-_FORCE_DAMP * delta)
	var extents := Vector3(_half * 0.9, 2.0, _half * 0.9)
	for i in n:
		_age[i] = _age[i] + delta
		if _age[i] >= _life[i]:
			_respawn(i, false)
			continue
		_vel[i] = _vel[i] * damp
		var ambient := (velocity_min + velocity_max) * 0.5
		if _vel[i].length() < ambient:
			_vel[i] = _vel[i].lerp(Vector3(0.12, 0.18, 0.08).normalized() * ambient, 1.0 - exp(-0.2 * delta))
		_pos[i] = _pos[i] + _vel[i] * delta
		for axis in 3:
			var lim: float = extents[axis]
			if _pos[i][axis] > lim:
				_pos[i][axis] = lim
				_vel[i][axis] = -absf(_vel[i][axis]) * 0.3
			elif _pos[i][axis] < -lim:
				_pos[i][axis] = -lim
				_vel[i][axis] = absf(_vel[i][axis]) * 0.3

func _simulate_clouds(delta: float) -> void:
	var n := _cloud_pos.size()
	var damp := exp(-_CLOUD_FORCE_DAMP * delta)
	var extents := Vector3(_half * 0.85, 2.0, _half * 0.85)
	for i in n:
		_cloud_age[i] = _cloud_age[i] + delta
		if _cloud_age[i] >= _cloud_life[i]:
			_respawn_cloud(i, false)
			continue
		_cloud_vel[i] = _cloud_vel[i] * damp
		var ambient := (cloud_velocity_min + cloud_velocity_max) * 0.5
		if _cloud_vel[i].length() < ambient:
			_cloud_vel[i] = _cloud_vel[i].lerp(Vector3(0.18, 0.22, 0.1).normalized() * ambient, 1.0 - exp(-0.18 * delta))
		_cloud_pos[i] = _cloud_pos[i] + _cloud_vel[i] * delta
		for axis in 3:
			var lim: float = extents[axis]
			if _cloud_pos[i][axis] > lim:
				_cloud_pos[i][axis] = lim
				_cloud_vel[i][axis] = -absf(_cloud_vel[i][axis]) * 0.25
			elif _cloud_pos[i][axis] < -lim:
				_cloud_pos[i][axis] = -lim
				_cloud_vel[i][axis] = absf(_cloud_vel[i][axis]) * 0.25

func _write_multimesh() -> void:
	if _multimesh == null:
		return
	var a := clampf(alpha, 0.01, 1.0)
	for i in _pos.size():
		var life := maxf(_life[i], 0.001)
		var t := _age[i] / life
		var fade := 1.0
		if t < 0.15:
			fade = t / 0.15
		elif t > 0.7:
			fade = 1.0 - (t - 0.7) / 0.3
		var s := _scale[i]
		_multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(s, s, s)), _pos[i]))
		_multimesh.set_instance_color(i, Color(1, 1, 1, a * clampf(fade, 0.0, 1.0)))

func _write_cloud_multimesh() -> void:
	if _cloud_multimesh == null:
		return
	var a := clampf(cloud_alpha, 0.005, 1.0)
	for i in _cloud_pos.size():
		var life := maxf(_cloud_life[i], 0.001)
		var t := _cloud_age[i] / life
		var fade := 1.0
		if t < 0.2:
			fade = t / 0.2
		elif t > 0.7:
			fade = 1.0 - (t - 0.7) / 0.3
		var s := _cloud_scale[i]
		_cloud_multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(s, s, s)), _cloud_pos[i]))
		_cloud_multimesh.set_instance_color(i, Color(1, 1, 1, a * clampf(fade, 0.0, 1.0)))
