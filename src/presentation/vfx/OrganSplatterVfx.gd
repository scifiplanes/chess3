extends Node3D
class_name OrganSplatterVfx

## Yellow-amber gore-ish burst at organ pop + lasting floor splat decal.

const _Self = preload("res://src/presentation/vfx/OrganSplatterVfx.gd")

const POOL_SIZE := 10
const MAX_DECALS := 28
const SPLAT_TEX_GEN := 3
const SPLAT_YELLOW := Color(1.0, 0.95, 0.35, 1.0)
const SPLAT_YELLOW_HOT := Color(1.0, 1.0, 0.72, 1.0)

static var _free: Array = []
static var _decal_host: Node3D = null
static var _decal_count: int = 0
static var _splat_tex: Texture2D = null
static var _splat_tex_gen: int = 0

var _burst: GPUParticles3D
var _tween: Tween
var _built: bool = false

static func play(
	host: Node3D,
	global_pos: Vector3,
	ground_y: float = 0.11,
	intensity: float = 1.0
) -> void:
	if host == null or not host.is_inside_tree():
		return
	_ensure_splat_tex()
	var vfx = _acquire(host)
	vfx.global_position = global_pos
	vfx._restart(intensity)
	_spawn_decal(host, global_pos, ground_y, intensity)

static func warmup(host: Node3D, _at: Vector3 = Vector3.ZERO) -> void:
	## Prebuild pool + splat texture only — never emit a visible burst/decal at boot.
	if host == null or not host.is_inside_tree():
		return
	_free.clear()
	_ensure_splat_tex()
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

static func _ensure_decal_host(host: Node3D) -> Node3D:
	if _decal_host != null and is_instance_valid(_decal_host):
		return _decal_host
	var parent: Node3D = host
	var p := host.get_parent()
	if p is Node3D:
		parent = p as Node3D
	var existing := parent.get_node_or_null("SplatDecals") as Node3D
	if existing != null:
		_decal_host = existing
		return _decal_host
	_decal_host = Node3D.new()
	_decal_host.name = "SplatDecals"
	parent.add_child(_decal_host)
	return _decal_host

static func _ensure_splat_tex() -> void:
	if _splat_tex != null and _splat_tex_gen == SPLAT_TEX_GEN:
		return
	_splat_tex_gen = SPLAT_TEX_GEN
	# Soft irregular yellow blot — radial falloff + blotchy alpha.
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var cx := 31.5
	var cy := 31.5
	for y in range(64):
		for x in range(64):
			var dx := (float(x) - cx) / 28.0
			var dy := (float(y) - cy) / 28.0
			var ang := atan2(dy, dx)
			var rad := sqrt(dx * dx + dy * dy)
			var wobble := 1.0 + 0.22 * sin(ang * 3.0) + 0.12 * sin(ang * 7.0 + 1.3)
			var d := rad / wobble
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = pow(a, 1.55)
			var pore := sin(x * 0.55 + y * 0.31) * sin(x * 0.27 - y * 0.49)
			if pore > 0.55:
				a *= 0.35
			var edge := clampf(1.0 - absf(d - 0.55) * 2.2, 0.0, 1.0)
			# Yellow → amber (avoid red channel dominance).
			var r := lerpf(0.95, 1.0, edge)
			var g := lerpf(0.78, 0.98, a)
			var b := lerpf(0.12, 0.42, a * 0.55)
			img.set_pixel(x, y, Color(r, g, b, a))
	_splat_tex = ImageTexture.create_from_image(img)

static func _spawn_decal(host: Node3D, global_pos: Vector3, ground_y: float, intensity: float) -> void:
	var root := _ensure_decal_host(host)
	if root == null:
		return
	while _decal_count >= MAX_DECALS and root.get_child_count() > 0:
		var oldest := root.get_child(0)
		oldest.queue_free()
		_decal_count = maxi(_decal_count - 1, 0)

	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	var sz := lerpf(0.72, 1.35, clampf(intensity, 0.3, 1.2)) * randf_range(0.9, 1.25)
	plane.size = Vector2(sz, sz * randf_range(0.75, 1.15))
	mi.mesh = plane
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = _splat_tex
	mat.albedo_color = Color(1.0, 0.96, 0.4, 0.85)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	mi.material_override = mat

	root.add_child(mi)
	_decal_count += 1
	mi.global_position = Vector3(
		global_pos.x + randf_range(-0.1, 0.1),
		ground_y + 0.012,
		global_pos.z + randf_range(-0.1, 0.1)
	)
	mi.rotation = Vector3(0.0, randf_range(0.0, TAU), 0.0)
	mi.scale = Vector3(0.4, 1.0, 0.4)

	var tw := root.create_tween()
	tw.tween_property(mi, "scale", Vector3(1.0, 1.0, 1.0), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(randf_range(16.0, 24.0))
	tw.tween_property(mat, "albedo_color:a", 0.0, 1.4)
	tw.tween_callback(func() -> void:
		if is_instance_valid(mi):
			mi.queue_free()
		_decal_count = maxi(_decal_count - 1, 0)
	)

func _ensure_built() -> void:
	if _built:
		return
	_burst = GPUParticles3D.new()
	_burst.emitting = false
	_burst.one_shot = true
	_burst.explosiveness = 0.96
	_burst.amount = 52
	_burst.lifetime = 0.62
	_burst.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 6, 8))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 1.8
	pm.initial_velocity_max = 4.8
	pm.gravity = Vector3(0, -9.5, 0)
	pm.damping_min = 0.4
	pm.damping_max = 1.2
	pm.scale_min = 0.07
	pm.scale_max = 0.2
	pm.color = SPLAT_YELLOW
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		SPLAT_YELLOW_HOT,
		SPLAT_YELLOW,
		Color(0.98, 0.88, 0.28, 0.92),
		Color(0.85, 0.72, 0.18, 0.0),
	])
	grad.offsets = PackedFloat32Array([0.0, 0.22, 0.62, 1.0])
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	pm.color_ramp = ramp
	_burst.process_material = pm
	var dm := SphereMesh.new()
	dm.radius = 0.075
	dm.height = 0.15
	var draw_mat := StandardMaterial3D.new()
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.vertex_color_use_as_albedo = true
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.albedo_color = Color(1, 1, 1, 1)
	draw_mat.disable_receive_shadows = true
	dm.material = draw_mat
	_burst.draw_pass_1 = dm
	add_child(_burst)
	_built = true

func _restart(intensity: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var i := clampf(intensity, 0.35, 1.4)
	if _burst.process_material is ParticleProcessMaterial:
		var pm := _burst.process_material as ParticleProcessMaterial
		pm.initial_velocity_max = 3.6 + 2.4 * i
		pm.scale_max = 0.14 + 0.1 * i
	visible = true
	_burst.restart()
	_burst.emitting = true
	_tween = create_tween()
	_tween.tween_interval(_burst.lifetime + 0.08)
	_tween.tween_callback(_release)

func _release() -> void:
	if _burst != null:
		_burst.emitting = false
	visible = false
	if not _free.has(self):
		_free.append(self)
