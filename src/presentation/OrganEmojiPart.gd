extends Node3D
class_name OrganEmojiPart

## Dithered emoji organ billboard (morphology-readable, not a soft blob).

const DITHER_SHADER = preload("res://shaders/emoji_dither.gdshader")
const VP_SIZE := 64

static var dither_enabled: bool = true
static var dither_strength: float = 0.72
static var dither_levels: float = 6.0
## Detached organ corpses / unusable drops — grayed so they don't read as loot.
static var corpse_tint := Color(0.42, 0.42, 0.44, 0.72)
## Field gear that cannot be grafted right now (hard max / non-reclaimable).
static var unusable_gear_tint := Color(0.48, 0.48, 0.50, 0.62)

var def_id: String = ""
var _sprite: Sprite3D
var _vp: SubViewport
var _label: Label
var _mat: ShaderMaterial
var _pixel_size: float = 0.0040
var _mirror: bool = false
var _sort_bias: float = 0.0

func _ready() -> void:
	_ensure()
	add_to_group("organ_emoji_parts")
	apply_dither_from_globals()
	set_process(true)

func _process(_delta: float) -> void:
	_face_camera_y()

func configure(p_def_id: String, rest: Vector3, world_pixel: float = 0.0040) -> void:
	def_id = p_def_id
	_pixel_size = world_pixel
	position = rest
	_ensure()
	add_to_group("organ_emoji_parts")
	_label.text = _emoji_for(def_id)
	_sprite.pixel_size = _pixel_size
	_mark_emoji_dirty()
	apply_dither_from_globals()
	set_process(true)

func set_emoji_def(p_def_id: String) -> void:
	if def_id == p_def_id:
		return
	def_id = p_def_id
	_ensure()
	_label.text = _emoji_for(def_id)
	_mark_emoji_dirty()

func set_outline(owner_or_front: Color, strength: Variant = true) -> void:
	_ensure()
	if _mat == null:
		return
	_mat.set_shader_parameter("outline_rgb", Vector3(owner_or_front.r, owner_or_front.g, owner_or_front.b))
	# strength: bool legacy or float mix (selected mutant ≈ 1.0).
	var mix := 1.0 if strength is bool and bool(strength) else 0.28
	if strength is float or strength is int:
		mix = clampf(float(strength), 0.0, 1.0)
	_mat.set_shader_parameter("outline_mix", mix)

func set_tint(rgb: Color) -> void:
	_ensure()
	if _mat:
		_mat.set_shader_parameter("tint_rgb", Vector3(rgb.r, rgb.g, rgb.b))
	if _sprite:
		_sprite.modulate = Color(1, 1, 1, rgb.a)

func set_sort_bias(bias: float) -> void:
	_sort_bias = bias
	_ensure()
	if _sprite:
		# Unique depth bias so stacked glyphs do not alternate winner frames.
		_sprite.sorting_offset = bias
		_sprite.render_priority = clampi(int(round(bias * 10.0)), -64, 64)

func set_mirror(on: bool) -> void:
	if _mirror == on and _sprite != null:
		return
	_mirror = on
	_ensure()
	if _sprite:
		_sprite.flip_h = on

func apply_dither_from_globals() -> void:
	_ensure()
	if _mat == null:
		return
	_mat.set_shader_parameter("strength", dither_strength if dither_enabled else 0.0)
	_mat.set_shader_parameter("levels", maxf(2.0, dither_levels))

static func push_dither_settings(enabled: bool, strength: float, levels: float, tree: SceneTree = null) -> void:
	dither_enabled = enabled
	dither_strength = clampf(strength, 0.0, 1.0)
	dither_levels = clampf(levels, 2.0, 12.0)
	if tree != null:
		tree.call_group("organ_emoji_parts", "apply_dither_from_globals")

func _emoji_for(id: String) -> String:
	const UnitDefsScript = preload("res://src/sim/UnitDefs.gd")
	return UnitDefsScript.emoji_for(id)

## Y-axis billboard in world space so the front face always faces the camera.
## (Custom ShaderMaterial ignores Sprite3D.billboard; cull_back needs a stable front.)
func _face_camera_y() -> void:
	_ensure()
	if _sprite == null or not is_inside_tree():
		return
	var vp := get_viewport()
	if vp == null:
		return
	var cam := vp.get_camera_3d()
	if cam == null:
		return
	var from := _sprite.global_position
	var to := cam.global_position
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	if flat.length_squared() < 0.000001:
		return
	# Sprite3D draws on XY facing +Z. look_at aims -Z at target, so aim opposite of camera.
	var away := from - flat.normalized()
	_sprite.look_at(away, Vector3.UP)

func _ensure() -> void:
	if _vp != null:
		return
	_vp = SubViewport.new()
	_vp.name = "EmojiVP"
	_vp.size = Vector2i(VP_SIZE, VP_SIZE)
	_vp.transparent_bg = true
	_vp.disable_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_vp)

	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Bundled Noto Color Emoji — required on Web (no OS emoji fallback).
	K1Widgets.apply_body_font(_label, 52)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp.add_child(_label)

	_mat = ShaderMaterial.new()
	_mat.shader = DITHER_SHADER
	_mat.set_shader_parameter("levels", dither_levels)
	_mat.set_shader_parameter("strength", dither_strength if dither_enabled else 0.0)

	_sprite = Sprite3D.new()
	_sprite.name = "EmojiSprite"
	# Custom ShaderMaterial ignores Sprite3D.billboard — yaw applied in _face_camera_y.
	_sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_sprite.centered = true
	_sprite.pixel_size = _pixel_size
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_sprite.texture = _vp.get_texture()
	_mat.set_shader_parameter("texture_albedo", _vp.get_texture())
	_sprite.material_override = _mat
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_sprite.alpha_scissor_threshold = 0.12
	_sprite.transparent = true
	_sprite.shaded = false
	# Back face was the "flipped" flicker when z-order swapped (shader also culls back now).
	_sprite.double_sided = false
	_sprite.flip_h = _mirror
	_sprite.sorting_offset = _sort_bias
	add_child(_sprite)

func _mark_emoji_dirty() -> void:
	if _vp != null:
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
