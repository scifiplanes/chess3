extends Node

## Fullscreen ordered-Bayer dither post-process (ported from Elfenstein DitherShader).

const SHADER := preload("res://shaders/dither_post.gdshader")

var enabled: bool = true
var strength: float = 0.55
var colour_preserve: float = 0.6
var pixel_size: float = 1.0
var levels: float = 10.0
var matrix_size: float = 4.0
var palette: float = 4.0
var palette0_mix: float = 1.0
var post_levels: float = 1.0
var post_lift: float = 0.0
var post_gamma: float = 1.0

var _layer: CanvasLayer
var _rect: ColorRect
var _mat: ShaderMaterial

func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "DitherPostProcessLayer"
	_layer.layer = 100
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_layer)

	# Required for reliable hint_screen_texture sampling (see warhead SharpenFx).
	var bbc := BackBufferCopy.new()
	bbc.name = "DitherBackBuffer"
	bbc.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	_layer.add_child(bbc)

	_rect = ColorRect.new()
	_rect.name = "DitherRect"
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.color = Color(1.0, 1.0, 1.0, 1.0)
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_rect.grow_vertical = Control.GROW_DIRECTION_BOTH

	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_rect.material = _mat
	_layer.add_child(_rect)

	var vp := get_viewport()
	if vp:
		vp.size_changed.connect(_fit_rect)
	_fit_rect()
	_apply()

func _fit_rect() -> void:
	if _rect == null:
		return
	# Full-rect anchors alone; avoid size override warning with opposite anchors.
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.offset_left = 0.0
	_rect.offset_top = 0.0
	_rect.offset_right = 0.0
	_rect.offset_bottom = 0.0

func push_settings(
	p_enabled: bool,
	p_strength: float,
	p_colour_preserve: float,
	p_pixel_size: float,
	p_levels: float,
	p_matrix_size: float,
	p_palette: float,
	p_palette0_mix: float,
	p_post_levels: float,
	p_post_lift: float,
	p_post_gamma: float
) -> void:
	enabled = p_enabled
	strength = clampf(p_strength, 0.0, 1.0)
	colour_preserve = clampf(p_colour_preserve, 0.0, 1.0)
	pixel_size = clampf(p_pixel_size, 1.0, 8.0)
	levels = clampf(p_levels, 2.0, 32.0)
	var m := int(round(p_matrix_size))
	if m <= 3:
		matrix_size = 2.0
	elif m <= 6:
		matrix_size = 4.0
	else:
		matrix_size = 8.0
	palette = clampf(float(round(p_palette)), 0.0, 4.0)
	palette0_mix = clampf(p_palette0_mix, 0.0, 1.0)
	post_levels = maxf(0.0, p_post_levels)
	post_lift = clampf(p_post_lift, -0.5, 0.5)
	post_gamma = clampf(p_post_gamma, 0.2, 3.0)
	_apply()

func _apply() -> void:
	if _rect == null or _mat == null or _layer == null:
		return
	var on := enabled and strength > 0.0
	_layer.visible = on
	_rect.visible = on
	if not on:
		return
	_mat.set_shader_parameter("strength", strength)
	_mat.set_shader_parameter("colour_preserve", colour_preserve)
	_mat.set_shader_parameter("pixel_size", pixel_size)
	_mat.set_shader_parameter("levels", levels)
	_mat.set_shader_parameter("matrix_size", matrix_size)
	_mat.set_shader_parameter("palette", palette)
	_mat.set_shader_parameter("palette0_mix", palette0_mix)
	_mat.set_shader_parameter("post_levels", post_levels)
	_mat.set_shader_parameter("post_lift", post_lift)
	_mat.set_shader_parameter("post_gamma", post_gamma)
