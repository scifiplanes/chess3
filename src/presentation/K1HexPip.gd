extends Control
class_name K1HexPip

const K1Widgets = preload("res://src/presentation/K1Widgets.gd")

## Chunky extruded team clay zone gem.

@export var value: int = 0
@export var need: int = 2
@export var accent: Color = Color(0.82, 0.58, 0.24, 1.0)
@export var seat_label: String = "" # "P1" / "P2" — not color-only

var _hovering: bool = false

func _ready() -> void:
	custom_minimum_size = Vector2(84, 72)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	tooltip_text = "Zones held / need 2 to win"
	add_to_group("ui_blocks_board_hover")
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	queue_redraw()

func set_value(v: int, need_v: int = -1) -> void:
	value = v
	if need_v >= 0:
		need = need_v
	queue_redraw()

func set_accent(c: Color) -> void:
	accent = c
	queue_redraw()

func set_seat(label: String) -> void:
	seat_label = str(label).strip_edges()
	if seat_label != "":
		tooltip_text = "%s zones held / need 2 to win" % seat_label
	queue_redraw()

func _on_mouse_entered() -> void:
	_hovering = true
	modulate = Color(1.1, 1.06, 1.0, 1.0)
	scale = Vector2(1.04, 1.04)
	queue_redraw()

func _on_mouse_exited() -> void:
	_hovering = false
	modulate = Color(1, 1, 1, 1)
	scale = Vector2.ONE
	queue_redraw()

func _team_body() -> Color:
	return Color(
		lerpf(K1Widgets.CLAY_WET.r, accent.r, 0.72),
		lerpf(K1Widgets.CLAY_WET.g, accent.g, 0.72),
		lerpf(K1Widgets.CLAY_WET.b, accent.b, 0.72),
		0.98
	)

func _draw() -> void:
	var c := size * 0.5 - Vector2(0, 2)
	var r := mini(size.x, size.y) * 0.40
	if _hovering:
		r *= 1.04
	var body := _team_body()
	var well := Color(
		lerpf(0.1, accent.r * 0.35, 0.55),
		lerpf(0.07, accent.g * 0.35, 0.55),
		lerpf(0.05, accent.b * 0.35, 0.55),
		0.92
	)
	K1Widgets.draw_clay_extrude_hex(self, c, r, body, accent, 8.0 if not _hovering else 9.0)
	K1Widgets.draw_hex(self, c, r * 0.52, well, Color(accent.r, accent.g, accent.b, 0.75), 1.6)
	# Stamp lip on well
	K1Widgets.draw_hex(self, c, r * 0.52, Color(0, 0, 0, 0), Color(0.55, 0.45, 0.32, 0.25), 1.2)
	var title_font := K1Widgets.font_readable()
	var body_font := K1Widgets.font_readable()
	var type_col := Color(
		lerpf(1.0, accent.r, 0.35),
		lerpf(0.95, accent.g, 0.35),
		lerpf(0.85, accent.b, 0.35),
		1.0
	)
	var top := seat_label if seat_label != "" else "ZONES"
	var top_sz := 11 if seat_label != "" else 9
	var lab_w := body_font.get_string_size(top, HORIZONTAL_ALIGNMENT_LEFT, -1, top_sz).x
	K1Widgets.draw_embossed_string(self, body_font, c + Vector2(-lab_w * 0.5, -11.0), top, top_sz, type_col)
	if seat_label != "":
		const ZONES := "ZONES"
		var zw := body_font.get_string_size(ZONES, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x
		var zcol := Color(type_col.r, type_col.g, type_col.b, 0.78)
		K1Widgets.draw_embossed_string(self, body_font, c + Vector2(-zw * 0.5, 1.0), ZONES, 7, zcol)
	var num := "%d/%d" % [value, maxi(1, need)]
	var num_y := 15.0 if seat_label != "" else 12.0
	var nw := title_font.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	K1Widgets.draw_embossed_string(self, title_font, c + Vector2(-nw * 0.5, num_y), num, 18, type_col)
	for i in range(3):
		var bx := c.x + float(i - 1) * 10.0
		var on := i < value
		var bead_fill := accent if on else Color(0.14, 0.1, 0.08, 0.9)
		draw_circle(Vector2(bx, c.y + r * 0.82) + Vector2(0.5, 1.2), 2.9, Color(0.04, 0.02, 0.01, 0.5))
		draw_circle(Vector2(bx, c.y + r * 0.82), 2.7, bead_fill)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		pivot_offset = size * 0.5
