extends Node3D
class_name ImpactDebris

## Loose RigidBody debris: small billboarded cut-mushroom-matter chunks.

const ContactShadowScript = preload("res://src/presentation/vfx/ContactShadow.gd")
const LoosePropScript = preload("res://src/presentation/vfx/LooseProp.gd")

const GROUP := "force_bodies"
const MAX_LIVE := 512
const MAX_BURST := 64
const CHUNK_DIR := "res://assets/mushrooms/chunks"
const CHUNK_COUNT := 12
## World size of chunk sprites (billboard pixel_size * texture).
const CHUNK_PIXEL_SIZE := 0.00145

static var _live: int = 0
static var _chunk_tex: Array = [] ## Texture2D

static func spawn_prop_rubble(
	host: Node3D,
	origin: Vector3,
	prop_kind: String,
	ground_y: float = 0.11,
	board_center: Vector2 = Vector2(7.0, 7.0),
	board_half: float = 7.2
) -> void:
	var count := 10
	var strength := 6.5
	match prop_kind:
		"rock":
			count = 14
			strength = 8.0
		"blob":
			count = 12
			strength = 5.5
		"mushroom":
			count = 11
			strength = 6.0
	spawn_burst(host, origin, count, ground_y, board_center, board_half, strength)

static func spawn_burst(
	host: Node3D,
	origin: Vector3,
	count: int,
	ground_y: float = 0.11,
	board_center: Vector2 = Vector2(7.0, 7.0),
	board_half: float = 7.2,
	strength: float = 6.0
) -> void:
	if host == null or count <= 0:
		return
	count = mini(count, MAX_BURST)
	_ensure_chunk_textures()
	for _i in range(count):
		if _live >= MAX_LIVE:
			break
		_spawn_one(host, origin, ground_y, board_center, board_half, strength)

static func _ensure_chunk_textures() -> void:
	if not _chunk_tex.is_empty():
		return
	for i in range(1, CHUNK_COUNT + 1):
		var path := "%s/chunk_%02d.png" % [CHUNK_DIR, i]
		if ResourceLoader.exists(path):
			var tex := load(path) as Texture2D
			if tex != null:
				_chunk_tex.append(tex)
	if _chunk_tex.is_empty():
		push_warning("ImpactDebris: no chunk textures under %s" % CHUNK_DIR)

static func _spawn_one(
	host: Node3D,
	origin: Vector3,
	ground_y: float,
	board_center: Vector2,
	board_half: float,
	strength: float
) -> void:
	var body: RigidBody3D = LoosePropScript.new() as RigidBody3D
	body.mass = randf_range(0.07, 0.18)
	body.gravity_scale = 1.4
	body.linear_damp = 0.55
	body.angular_damp = 0.85
	body.continuous_cd = true
	body.add_to_group(GROUP)
	# Settled chunks must still loft when abilities hit the cell.
	body.set_meta("force_while_frozen", true)
	body.set_meta("force_light", true)
	if body.has_method("set_receives_force"):
		body.call("set_receives_force", true)

	var s := randf_range(0.05, 0.10)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = s * 0.85
	shape.shape = sphere
	body.add_child(shape)

	var spr := Sprite3D.new()
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.pixel_size = CHUNK_PIXEL_SIZE * randf_range(0.85, 1.35)
	spr.shaded = false
	spr.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	spr.transparent = true
	spr.double_sided = true
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if not _chunk_tex.is_empty():
		spr.texture = _chunk_tex[randi() % _chunk_tex.size()]
	spr.modulate = Color(
		randf_range(0.92, 1.05),
		randf_range(0.90, 1.02),
		randf_range(0.88, 1.0),
		1.0
	)
	spr.flip_h = randf() < 0.5
	body.add_child(spr)

	host.add_child(body)
	var spawn := origin + Vector3(
		randf_range(-0.15, 0.15),
		randf_range(0.12, 0.35),
		randf_range(-0.15, 0.15)
	)
	spawn.y = maxf(spawn.y, ground_y + s + 0.05)
	body.global_position = spawn

	ContactShadowScript.attach(
		body,
		Vector2(s * 1.4, s * 1.4),
		ground_y,
		board_center,
		board_half,
		s
	)

	var dir := Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1))
	if dir.length_squared() < 0.01:
		dir = Vector3(1, 0, 0)
	dir = dir.normalized()
	var mag := strength * randf_range(0.45, 1.0)
	body.apply_central_impulse(dir * mag + Vector3.UP * mag * randf_range(0.4, 0.9))
	body.apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * mag * 0.1)

	_live += 1
	var settle_t: SceneTreeTimer = body.get_tree().create_timer(randf_range(2.2, 3.4))
	settle_t.timeout.connect(func() -> void:
		if not is_instance_valid(body):
			return
		var p: Vector3 = body.global_position
		p.y = maxf(p.y, ground_y + s * 0.5)
		body.global_position = p
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.freeze = true
		body.sleeping = true
	)
	# Debris stays on the battlefield once settled (no despawn timer).
