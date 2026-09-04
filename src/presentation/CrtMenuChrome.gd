extends RefCounted
class_name CrtMenuChrome

## Rounded CRT-era menu shell — amber phosphor, no barrel distortion or scanlines.

const K1Widgets = preload("res://src/presentation/K1Widgets.gd")

const BG := Color(0.025, 0.022, 0.02, 1.0)
const BEZEL := Color(0.09, 0.085, 0.08, 1.0)
const SCREEN := Color(0.045, 0.04, 0.038, 0.92)
const PHOSPHOR := Color(0.95, 0.72, 0.28, 1.0)
const PHOSPHOR_DIM := Color(0.75, 0.55, 0.22, 0.85)
const P1 := Color(0.35, 0.88, 0.95, 1.0)
const P2 := Color(0.98, 0.52, 0.45, 1.0)
const BOARD_BG := "res://tools/visual_shots/tiles_board.png"

static func build_root(parent: Control) -> Dictionary:
	## Returns { "screen": inner panel, "layer": full-size overlay layer behind content }.
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(root)

	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	var vignette := ColorRect.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.color = Color(0.55, 0.5, 0.45, 1.0)
	var vig_mat := CanvasItemMaterial.new()
	vig_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	vignette.material = vig_mat
	root.add_child(vignette)

	var bezel := PanelContainer.new()
	bezel.set_anchors_preset(Control.PRESET_FULL_RECT)
	bezel.offset_left = 44
	bezel.offset_top = 32
	bezel.offset_right = -44
	bezel.offset_bottom = -32
	bezel.add_theme_stylebox_override("panel", _bezel_box())
	root.add_child(bezel)

	var outer_margin := MarginContainer.new()
	outer_margin.add_theme_constant_override("margin_left", 22)
	outer_margin.add_theme_constant_override("margin_right", 22)
	outer_margin.add_theme_constant_override("margin_top", 18)
	outer_margin.add_theme_constant_override("margin_bottom", 18)
	bezel.add_child(outer_margin)

	var screen_wrap := PanelContainer.new()
	screen_wrap.add_theme_stylebox_override("panel", _screen_box())
	outer_margin.add_child(screen_wrap)

	var stack := Control.new()
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.custom_minimum_size = Vector2(900, 520)
	screen_wrap.add_child(stack)

	var layer := Control.new()
	layer.name = "CrtLayer"
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.add_child(layer)

	var inner := MarginContainer.new()
	inner.name = "CrtContent"
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.add_theme_constant_override("margin_left", 16)
	inner.add_theme_constant_override("margin_right", 16)
	inner.add_theme_constant_override("margin_top", 12)
	inner.add_theme_constant_override("margin_bottom", 12)
	stack.add_child(inner)

	return {"screen": inner, "layer": layer}

static func add_board_backdrop(layer: Control, alpha: float = 0.14) -> void:
	if layer == null:
		return
	var tex := load(BOARD_BG) as Texture2D
	if tex == null:
		return
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.set_anchors_preset(Control.PRESET_CENTER)
	tr.custom_minimum_size = Vector2(680, 680)
	tr.pivot_offset = Vector2(340, 340)
	tr.rotation = -0.12
	tr.modulate = Color(1, 1, 1, alpha)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(tr)
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.035, 0.03, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(dim)

static func title_banner(text: String, size: int = 38) -> Control:
	var wrap := VBoxContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var left_rule := _rule_line()
	left_rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_display_font(l, size)
	l.add_theme_color_override("font_color", PHOSPHOR)
	l.add_theme_constant_override("outline_size", 2)
	l.add_theme_color_override("font_outline_color", Color(PHOSPHOR.r, PHOSPHOR.g, PHOSPHOR.b, 0.25))
	l.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var right_rule := _rule_line()
	right_rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left_rule)
	row.add_child(l)
	row.add_child(right_rule)
	wrap.add_child(row)
	return wrap

static func subtitle_label(text: String, size: int = 13) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	K1Widgets.apply_body_font(l, size)
	l.add_theme_color_override("font_color", Color(PHOSPHOR.r, PHOSPHOR.g, PHOSPHOR.b, 0.72))
	return l

static func _rule_line() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(48, 14)
	c.set_script(load("res://src/presentation/CrtRuleLine.gd"))
	return c

static func outline_menu_button(text: String, width: float = 300.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 46)
	b.focus_mode = Control.FOCUS_ALL
	K1Widgets.apply_body_font(b, 15)
	b.add_theme_color_override("font_color", PHOSPHOR)
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.88, 0.45))
	b.add_theme_stylebox_override("normal", _outline_pill(false))
	b.add_theme_stylebox_override("hover", _outline_pill(false, true))
	b.add_theme_stylebox_override("pressed", _outline_pill(true))
	b.add_theme_stylebox_override("focus", _outline_pill(false, true))
	return b

static func action_pill(text: String, filled: bool = false, accent: Color = PHOSPHOR) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(168, 40)
	K1Widgets.apply_body_font(b, 13)
	if filled:
		b.add_theme_color_override("font_color", Color(0.06, 0.05, 0.04))
		b.add_theme_stylebox_override("normal", _pill(false, accent))
		b.add_theme_stylebox_override("hover", _pill(false, accent.lightened(0.1)))
	else:
		b.add_theme_color_override("font_color", PHOSPHOR)
		b.add_theme_stylebox_override("normal", _outline_pill(false))
		b.add_theme_stylebox_override("hover", _outline_pill(false, true))
	return b

static func corner_readout(title: String, lines: PackedStringArray) -> PanelContainer:
	const W := 172.0
	const H := 92.0
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(W, H)
	p.size = Vector2(W, H)
	p.add_theme_stylebox_override("panel", _readout_box())
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	p.add_child(v)
	var hdr := Label.new()
	hdr.text = title
	K1Widgets.apply_body_font(hdr, 10)
	hdr.add_theme_color_override("font_color", PHOSPHOR)
	v.add_child(hdr)
	for line in lines:
		var ln := Label.new()
		ln.text = line
		K1Widgets.apply_body_font(ln, 9)
		ln.add_theme_color_override("font_color", Color(PHOSPHOR.r, PHOSPHOR.g, PHOSPHOR.b, 0.65))
		v.add_child(ln)
	return p

static func player_deck_panel(accent: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.048, 0.045, 0.88)
	s.border_color = Color(accent.r, accent.g, accent.b, 0.75)
	s.set_border_width_all(2)
	s.set_corner_radius_all(14)
	s.shadow_color = Color(accent.r, accent.g, accent.b, 0.18)
	s.shadow_size = 8
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", s)
	return p

static func gene_stepper(count: int, accent: Color, minus_cb: Callable, plus_cb: Callable) -> PanelContainer:
	var cap := PanelContainer.new()
	cap.custom_minimum_size = Vector2(88, 28)
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.08, 0.075, 0.07, 0.9)
	cs.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	cs.set_border_width_all(1)
	cs.set_corner_radius_all(14)
	cap.add_theme_stylebox_override("panel", cs)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	cap.add_child(row)
	var minus := Button.new()
	minus.text = "−"
	minus.flat = true
	minus.custom_minimum_size = Vector2(24, 24)
	minus.pressed.connect(minus_cb)
	var cnt := Label.new()
	cnt.text = str(count)
	cnt.custom_minimum_size = Vector2(28, 0)
	cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	K1Widgets.apply_body_font(cnt, 13)
	cnt.add_theme_color_override("font_color", PHOSPHOR)
	var plus := Button.new()
	plus.text = "+"
	plus.flat = true
	plus.custom_minimum_size = Vector2(24, 24)
	plus.pressed.connect(plus_cb)
	row.add_child(minus)
	row.add_child(cnt)
	row.add_child(plus)
	cap.set_meta("count_label", cnt)
	return cap

static func budget_bar(spent: int, cap: int) -> Dictionary:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 4)
	var lbl := Label.new()
	lbl.text = "TOTAL BUDGET  %d / %d" % [spent, cap]
	K1Widgets.apply_body_font(lbl, 10)
	lbl.add_theme_color_override("font_color", PHOSPHOR_DIM)
	wrap.add_child(lbl)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 8)
	bar.max_value = float(cap)
	bar.value = float(spent)
	bar.show_percentage = false
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.12, 0.11, 0.1, 1.0)
	bs.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bs)
	var fs := StyleBoxFlat.new()
	fs.bg_color = PHOSPHOR
	fs.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fs)
	wrap.add_child(bar)
	return {"wrap": wrap, "label": lbl, "bar": bar}

static func section_header(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	K1Widgets.apply_body_font(l, 11)
	l.add_theme_color_override("font_color", PHOSPHOR)
	return l

static func dotted_slider_row(label: String, value: float, min_v: float, max_v: float) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var lbl := Label.new()
	lbl.text = label.to_upper()
	lbl.custom_minimum_size = Vector2(148, 20)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	K1Widgets.apply_body_font(lbl, 10)
	lbl.add_theme_color_override("font_color", PHOSPHOR_DIM)
	row.add_child(lbl)
	var track_wrap := Control.new()
	track_wrap.custom_minimum_size = Vector2(320, 20)
	track_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track_wrap.set_script(load("res://src/presentation/CrtDottedSlider.gd"))
	track_wrap.call("setup", value, min_v, max_v)
	row.add_child(track_wrap)
	var pct := Label.new()
	pct.custom_minimum_size = Vector2(40, 20)
	pct.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	K1Widgets.apply_body_font(pct, 10)
	pct.add_theme_color_override("font_color", PHOSPHOR)
	var t := 0.0 if max_v <= min_v else (value - min_v) / (max_v - min_v)
	pct.text = "%d%%" % int(round(t * 100.0))
	row.add_child(pct)
	return {"row": row, "track": track_wrap, "pct": pct}

static func segmented_tempo(options: PackedStringArray, current: String, on_pick: Callable) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fs := StyleBoxFlat.new()
	fs.bg_color = Color(0.06, 0.055, 0.05, 0.9)
	fs.border_color = PHOSPHOR
	fs.set_border_width_all(1)
	fs.set_corner_radius_all(8)
	frame.add_theme_stylebox_override("panel", fs)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	frame.add_child(row)
	for i in options.size():
		if i > 0:
			var sep := ColorRect.new()
			sep.custom_minimum_size = Vector2(1, 28)
			sep.color = Color(PHOSPHOR.r, PHOSPHOR.g, PHOSPHOR.b, 0.45)
			row.add_child(sep)
		var opt := str(options[i])
		var b := Button.new()
		b.text = opt.to_upper()
		b.toggle_mode = true
		b.button_pressed = opt == current
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 34)
		b.flat = true
		K1Widgets.apply_body_font(b, 10)
		_style_tempo_segment(b, opt == current)
		var oid := opt
		b.pressed.connect(func(): on_pick.call(oid))
		row.add_child(b)
		frame.set_meta("btn_" + opt, b)
	frame.set_meta("segment_row", row)
	return frame

static func _style_tempo_segment(b: Button, on: bool) -> void:
	b.add_theme_color_override("font_color", Color(0.06, 0.05, 0.04) if on else PHOSPHOR)
	var sn := StyleBoxFlat.new()
	sn.bg_color = PHOSPHOR if on else Color(0, 0, 0, 0)
	sn.border_color = PHOSPHOR
	sn.set_border_width_all(2 if on else 0)
	sn.set_content_margin_all(6)
	b.add_theme_stylebox_override("normal", sn)
	b.add_theme_stylebox_override("hover", sn)
	b.add_theme_stylebox_override("pressed", sn)

static func pill_toggle(label: String, on: bool, toggled: Callable) -> Button:
	var b := Button.new()
	b.text = label.to_upper()
	b.toggle_mode = true
	b.button_pressed = on
	b.custom_minimum_size = Vector2(0, 32)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	K1Widgets.apply_body_font(b, 10)
	_style_pill_toggle(b, on)
	b.toggled.connect(func(v: bool):
		_style_pill_toggle(b, v)
		toggled.call(v)
	)
	return b

## Filled phosphor when ON; outline-only when OFF (settings FULLSCREEN / VSYNC).
static func _style_pill_toggle(b: Button, on: bool) -> void:
	b.add_theme_color_override("font_color", Color(0.06, 0.05, 0.04) if on else PHOSPHOR)
	var sn := StyleBoxFlat.new()
	sn.set_corner_radius_all(16)
	sn.set_content_margin_all(8)
	if on:
		sn.bg_color = PHOSPHOR
		sn.border_color = PHOSPHOR
		sn.set_border_width_all(2)
	else:
		sn.bg_color = Color(0, 0, 0, 0)
		sn.border_color = PHOSPHOR
		sn.set_border_width_all(2)
	b.add_theme_stylebox_override("normal", sn)
	b.add_theme_stylebox_override("hover", sn)
	b.add_theme_stylebox_override("pressed", sn)
	b.add_theme_stylebox_override("focus", sn)

static func toast_label() -> Label:
	var l := Label.new()
	l.visible = false
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	K1Widgets.apply_body_font(l, 13)
	l.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
	return l

static func hsep(h: float = 10.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

static func _apply_display_font(ctrl: Control, size: int) -> void:
	# Jrudge lacks 'C' glyph — use body font for CHESS title parity.
	K1Widgets.apply_body_font(ctrl, size)

static func _bezel_box() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = BEZEL
	s.border_color = Color(PHOSPHOR.r, PHOSPHOR.g, PHOSPHOR.b, 0.35)
	s.set_border_width_all(4)
	s.set_corner_radius_all(24)
	s.shadow_color = Color(0, 0, 0, 0.7)
	s.shadow_size = 16
	return s

static func _screen_box() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = SCREEN
	s.border_color = Color(PHOSPHOR.r, PHOSPHOR.g, PHOSPHOR.b, 0.22)
	s.set_border_width_all(2)
	s.set_corner_radius_all(16)
	return s

static func _readout_box() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.045, 0.04, 0.82)
	s.border_color = Color(PHOSPHOR.r, PHOSPHOR.g, PHOSPHOR.b, 0.28)
	s.set_border_width_all(1)
	s.set_corner_radius_all(8)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s

static func _outline_pill(pressed: bool, hot: bool = false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(PHOSPHOR.r, PHOSPHOR.g, PHOSPHOR.b, 0.08 if hot else 0.03)
	if pressed:
		s.bg_color = Color(PHOSPHOR.r, PHOSPHOR.g, PHOSPHOR.b, 0.18)
	s.border_color = PHOSPHOR if not hot else Color(1.0, 0.85, 0.4)
	s.set_border_width_all(2)
	s.set_corner_radius_all(23)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s

static func _pill(pressed: bool, accent: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = accent if not pressed else accent.darkened(0.12)
	s.set_corner_radius_all(20)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	s.border_color = Color(1, 0.9, 0.55, 0.35)
	s.set_border_width_all(1)
	return s
