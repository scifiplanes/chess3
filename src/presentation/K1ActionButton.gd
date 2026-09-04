extends Button
class_name K1ActionButton

const K1Widgets = preload("res://src/presentation/K1Widgets.gd")

## Wet-mud action key — fake-3D extruded clay slab.

var action_id: String = ""
var caption: String = ""
var lit_pips: int = 0
var cd_label: String = ""
var _hovering: bool = false
var _idle_modulate: Color = Color(1, 1, 1, 1)
var _clay_mat: ShaderMaterial
var _pressing: bool = false

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	flat = false
	clip_text = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_to_group("ui_blocks_board_hover")
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)
	_clay_mat = K1Widgets.ensure_clay_backplate(self, K1Widgets.CLAY_TERRA, 0.58, 0.24)
	_apply_style()
	queue_redraw()

func setup(id: String, label_text: String, min_size: Vector2 = Vector2(72, 64), pips: int = 0, cd_text: String = "") -> void:
	action_id = id
	caption = label_text
	lit_pips = pips
	cd_label = cd_text
	set_meta("action_id", id)
	text = ""
	custom_minimum_size = min_size
	_apply_style()
	queue_redraw()

func set_pips(n: int) -> void:
	lit_pips = n
	queue_redraw()

func set_cd_label(text: String) -> void:
	cd_label = text
	queue_redraw()

func set_idle_modulate(c: Color) -> void:
	_idle_modulate = c
	if not _hovering:
		modulate = _idle_modulate
	queue_redraw()

func _on_mouse_entered() -> void:
	_hovering = true
	if not disabled:
		modulate = Color(
			_idle_modulate.r * 1.08,
			_idle_modulate.g * 1.05,
			_idle_modulate.b * 0.98,
			_idle_modulate.a
		)
		scale = Vector2(1.04, 1.04)
		if _clay_mat:
			_clay_mat.set_shader_parameter("wetness", 0.7)
	queue_redraw()

func _on_mouse_exited() -> void:
	_hovering = false
	modulate = _idle_modulate
	if not _pressing:
		scale = Vector2.ONE
	if _clay_mat:
		_clay_mat.set_shader_parameter("wetness", 0.58)
		_clay_mat.set_shader_parameter("press", 0.0)
	queue_redraw()

func _on_button_down() -> void:
	_pressing = true
	scale = Vector2(0.96, 0.96)
	if _clay_mat:
		_clay_mat.set_shader_parameter("press", 1.0)
		_clay_mat.set_shader_parameter("wetness", 0.75)
		_clay_mat.set_shader_parameter("extrude_px", 6.0)
	queue_redraw()

func _on_button_up() -> void:
	_pressing = false
	scale = Vector2(1.04, 1.04) if _hovering and not disabled else Vector2.ONE
	if _clay_mat:
		_clay_mat.set_shader_parameter("press", 0.0)
		_clay_mat.set_shader_parameter("wetness", 0.7 if _hovering else 0.58)
		_clay_mat.set_shader_parameter("extrude_px", 10.0)
	queue_redraw()

func _hot() -> bool:
	return (is_hovered() or _hovering) and not disabled

func _apply_style() -> void:
	add_theme_stylebox_override("normal", K1Widgets.mud_box(false, 14.0, K1Widgets.AMBER_DIM))
	var hover_box := K1Widgets.mud_box(false, 14.0, K1Widgets.CLAY_OCHRE)
	add_theme_stylebox_override("hover", hover_box)
	add_theme_stylebox_override("pressed", K1Widgets.mud_box(true, 14.0, K1Widgets.AMBER))
	add_theme_stylebox_override("disabled", K1Widgets.mud_box(true, 14.0, Color(0.35, 0.28, 0.22, 0.55)))
	add_theme_stylebox_override("focus", K1Widgets.empty_box())
	pivot_offset = custom_minimum_size * 0.5

func _draw() -> void:
	var hot := _hot()
	var glyph_h := size.y * 0.48
	var glyph_rect := Rect2(10, 8, size.x - 20, glyph_h)
	K1Widgets.draw_stamp_well(self, glyph_rect, hot)
	var stroke := Color(0.95, 0.88, 0.6, 1.0) if hot else (K1Widgets.TEXT_ON_CLAY if not disabled else Color(0.55, 0.48, 0.40, 0.65))
	K1Widgets.draw_action_glyph(self, glyph_rect.grow(-3), action_id, stroke)
	var font := K1Widgets.font_body()
	var label := caption if caption != "" else action_id.capitalize()
	var fs := 12 if label.length() <= 6 else 11
	var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var col := Color(1.0, 0.95, 0.82, 1.0) if hot else (K1Widgets.TEXT_ON_CLAY if not disabled else Color(0.62, 0.55, 0.45, 0.7))
	K1Widgets.draw_embossed_string(self, font, Vector2((size.x - tw) * 0.5, size.y - 16.0), label, fs, col)
	if cd_label != "":
		var cfs := 10
		var ctw := font.get_string_size(cd_label, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs).x
		K1Widgets.draw_embossed_string(self, font, Vector2(size.x - ctw - 6.0, 14.0), cd_label, cfs, Color(1.0, 0.55, 0.35, 1.0))
	elif lit_pips > 0:
		var py := size.y - 7.0
		var n := mini(4, lit_pips)
		var total_w := float(n) * 7.0 + float(maxi(0, n - 1)) * 4.0
		var x0 := (size.x - total_w) * 0.5
		for i in range(n):
			K1Widgets.draw_clay_bead(self, Vector2(x0 + i * 11.0 + 3.5, py), 3.2 if hot else 2.7, true, hot)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		pivot_offset = size * 0.5
