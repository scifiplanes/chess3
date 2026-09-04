extends MeshInstance3D
class_name ContactShadow

## Soft ellipse under a moving body (Chillout blob shadow, board AABB clip).

const _SHADER_PATH := "res://shaders/contact_shadow.gdshader"
const _NODE_NAME := "ContactShadow"
const _FOOTPRINT_SCALE := 2.45
const _GROUND_EPS := 0.005
const _FADE_HEIGHT := 2.2
const _SIZE_AT_FADE := 1.85
const _BASE_TINT := Color(0.02, 0.03, 0.05, 0.16)
const _Self = preload("res://src/presentation/vfx/ContactShadow.gd")

static var _mat_template: ShaderMaterial

var _follow: Node3D = null
var _ground_y: float = 0.11
var _mat: ShaderMaterial = null
var _body_height: float = 0.2

static func attach(
	piece: Node3D,
	footprint: Vector2,
	ground_y: float = 0.11,
	board_center: Vector2 = Vector2(7.0, 7.0),
	board_half: float = 7.2,
	body_height: float = 0.2
) -> void:
	if piece == null:
		return
	var existing := piece.get_node_or_null(_NODE_NAME)
	if existing != null:
		existing.queue_free()

	var w := maxf(footprint.x, 0.08) * _FOOTPRINT_SCALE
	var d := maxf(footprint.y, 0.08) * _FOOTPRINT_SCALE
	var plane := PlaneMesh.new()
	plane.size = Vector2(w, d)

	var blob = _Self.new()
	blob.name = _NODE_NAME
	blob.mesh = plane
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blob._mat = _make_mat(board_center, board_half)
	blob.material_override = blob._mat
	blob._follow = piece
	blob._ground_y = ground_y + _GROUND_EPS
	blob._body_height = body_height
	piece.add_child(blob)
	blob._sync_to_ground()

func _physics_process(_delta: float) -> void:
	_sync_to_ground()

func _sync_to_ground() -> void:
	if _follow == null or not is_instance_valid(_follow):
		return
	var p := _follow.global_position
	global_position = Vector3(p.x, _ground_y, p.z)
	global_basis = Basis.IDENTITY
	var platform_top := _ground_y - _GROUND_EPS
	var bottom_y := p.y - _body_height * 0.5
	var height := maxf(bottom_y - platform_top, 0.0)
	var t := clampf(height / _FADE_HEIGHT, 0.0, 1.0)
	var fade := (1.0 - t) * (1.0 - t)
	var size_k := lerpf(1.0, _SIZE_AT_FADE, t)
	visible = fade > 0.02
	scale = Vector3(size_k, 1.0, size_k)
	if _mat != null:
		var tint := _BASE_TINT
		tint.a = _BASE_TINT.a * fade
		_mat.set_shader_parameter("tint", tint)

static func _make_mat(board_center: Vector2, board_half: float) -> ShaderMaterial:
	_ensure_template()
	var mat := _mat_template.duplicate() as ShaderMaterial
	mat.set_shader_parameter("board_center", board_center)
	mat.set_shader_parameter("board_half", board_half)
	mat.set_shader_parameter("board_edge_softness", 0.35)
	mat.set_shader_parameter("tint", _BASE_TINT)
	mat.set_shader_parameter("edge_softness", 0.92)
	return mat

static func _ensure_template() -> void:
	if _mat_template != null:
		return
	_mat_template = ShaderMaterial.new()
	var shader := load(_SHADER_PATH) as Shader
	if shader != null:
		_mat_template.shader = shader
	else:
		push_warning("ContactShadow: missing shader at %s" % _SHADER_PATH)
