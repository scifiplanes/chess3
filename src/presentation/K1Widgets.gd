extends RefCounted
class_name K1Widgets

## Shared HUD visual helpers — wet-mud clay chrome (prehistoric skeuomorph).

const AMBER := Color(0.86, 0.58, 0.22, 1.0)
const AMBER_DIM := Color(0.62, 0.42, 0.20, 1.0)
## Legacy aliases → mud surfaces (call sites still say METAL).
const METAL := Color(0.48, 0.32, 0.22, 0.96)
const METAL_LIGHT := Color(0.58, 0.40, 0.28, 0.97)
const BONE := Color(0.90, 0.82, 0.68, 1.0)
const INK := Color(0.18, 0.10, 0.06, 1.0)
const CP_GOLD := Color(0.92, 0.68, 0.22, 1.0)
const CP_STEEL := Color(0.42, 0.72, 0.92, 1.0)

const MUD_UMBRA := Color(0.14, 0.09, 0.06, 1.0)
const CLAY_TERRA := Color(0.28, 0.18, 0.12, 1.0)
const CLAY_WET := Color(0.22, 0.14, 0.09, 1.0)
const CLAY_OCHRE := Color(0.86, 0.68, 0.38, 1.0)
const ASH_BLUE := Color(0.40, 0.48, 0.52, 1.0)
const STAMP_INK := Color(0.92, 0.86, 0.72, 1.0)
const WET_SHEEN := Color(0.75, 0.68, 0.55, 1.0)
const MOSS_FLECK := Color(0.32, 0.40, 0.22, 1.0)
const TEXT_ON_CLAY := Color(0.96, 0.92, 0.82, 1.0)

const CLAY_SHADER_PATH := "res://shaders/wet_clay_canvas.gdshader"

static var _font_readable: Font
static var _clay_shader: Shader

static func font_title() -> Font:
	return font_readable()

static func font_body() -> Font:
	return font_readable()

static func font_readable() -> Font:
	if _font_readable == null:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["Helvetica Neue", "Helvetica", "Arial", "sans-serif"])
		_font_readable = sf
	return _font_readable if _font_readable != null else ThemeDB.fallback_font

static func font_display() -> Font:
	return font_readable()

static func apply_title_font(ctrl: Control, size: int = -1) -> void:
	apply_readable_font(ctrl, size)

static func apply_body_font(ctrl: Control, size: int = -1) -> void:
	if ctrl == null:
		return
	ctrl.add_theme_font_override("font", font_body())
	if size > 0:
		ctrl.add_theme_font_size_override("font_size", size)

static func apply_readable_font(ctrl: Control, size: int = -1) -> void:
	if ctrl == null:
		return
	ctrl.add_theme_font_override("font", font_readable())
	if size > 0:
		ctrl.add_theme_font_size_override("font_size", size)

static func apply_label3d_font(label: Label3D) -> void:
	if label == null:
		return
	label.font = font_readable()

static func _clay_sh() -> Shader:
	if _clay_shader == null:
		_clay_shader = load(CLAY_SHADER_PATH) as Shader
	return _clay_shader

static func make_clay_material(tint: Color = CLAY_TERRA, wetness: float = 0.55, corner: float = 0.22, press: float = 0.0, sdf_clip: bool = true) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _clay_sh()
	mat.set_shader_parameter("clay_tint", tint)
	mat.set_shader_parameter("wetness", wetness)
	mat.set_shader_parameter("corner_px", maxf(8.0, corner * 64.0))
	mat.set_shader_parameter("rect_px", Vector2(128, 64))
	mat.set_shader_parameter("thickness", 1.35)
	mat.set_shader_parameter("extrude_px", 10.0)
	mat.set_shader_parameter("fingerprint", 0.12)
	mat.set_shader_parameter("tex_scale", 0.09)
	mat.set_shader_parameter("light_dir", Vector2(-0.35, -0.7))
	mat.set_shader_parameter("press", press)
	mat.set_shader_parameter("use_sdf_clip", 1.0 if sdf_clip else 0.0)
	return mat

static func apply_clay_material(ctrl: CanvasItem, tint: Color = CLAY_TERRA, wetness: float = 0.55, corner: float = 0.22, sdf_clip: bool = true) -> ShaderMaterial:
	if ctrl == null:
		return null
	var mat := make_clay_material(tint, wetness, corner, 0.0, sdf_clip)
	ctrl.material = mat
	_sync_clay_rect(ctrl, mat)
	return mat

static func _sync_clay_rect(ctrl: CanvasItem, mat: ShaderMaterial) -> void:
	if mat == null:
		return
	var sz := Vector2(128, 64)
	if ctrl is Control:
		var c := ctrl as Control
		sz = c.size
		if sz.x < 2.0 or sz.y < 2.0:
			sz = c.get_rect().size
		if sz.x < 2.0 or sz.y < 2.0:
			sz = c.custom_minimum_size
		# Prefer host size when syncing a full-rect backplate child.
		var p := c.get_parent()
		if c.name == "ClayBackplate" and p is Control:
			var hs := (p as Control).size
			if hs.x >= 2.0 and hs.y >= 2.0:
				sz = hs
	mat.set_shader_parameter("rect_px", Vector2(maxf(8.0, sz.x), maxf(8.0, sz.y)))

static func ensure_clay_backplate(host: Control, tint: Color = CLAY_TERRA, wetness: float = 0.55, corner: float = 0.22, sdf_clip: bool = true) -> ShaderMaterial:
	## Shader lives on a ColorRect so labels/glyphs are NOT clay-tinted.
	## PanelContainers must use a sibling backplate — container layout would flatten/clip pads.
	if host == null:
		return null
	host.material = null
	host.clip_contents = false
	var sibling := host is Container and not (host is BaseButton)
	var bp := _find_clay_backplate(host, sibling)
	if bp == null:
		bp = ColorRect.new()
		bp.name = "ClayBackplate"
		bp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bp.color = Color(1, 1, 1, 1)
		if sibling:
			var p := host.get_parent()
			if p == null:
				return null
			bp.name = "ClayBackplate_%s" % host.name
			bp.set_meta("clay_host_path", host.get_path())
			p.add_child(bp)
			p.move_child(bp, maxi(0, host.get_index()))
			# Sibling plates outlive host.visible — orphan mud slabs read as abandoned HUD.
			bp.visible = host.is_visible_in_tree()
			if not host.has_meta("clay_vis_hooked"):
				host.set_meta("clay_vis_hooked", true)
				host.visibility_changed.connect(func(): _sync_clay_backplate_visibility(host))
			if not host.has_meta("clay_resize_hooked"):
				host.set_meta("clay_resize_hooked", true)
				host.resized.connect(func(): _on_clay_host_resized(host))
				host.item_rect_changed.connect(func(): _on_clay_host_resized(host))
		else:
			bp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			bp.offset_left = -3.0
			bp.offset_top = -2.0
			bp.offset_right = 8.0
			bp.offset_bottom = 14.0
			bp.show_behind_parent = true
			host.add_child(bp)
			host.move_child(bp, 0)
			if not host.has_meta("clay_resize_hooked"):
				host.set_meta("clay_resize_hooked", true)
				host.resized.connect(func(): _on_clay_host_resized(host))
	elif not sibling:
		bp.offset_left = -3.0
		bp.offset_top = -2.0
		bp.offset_right = 8.0
		bp.offset_bottom = 14.0
	host.set_meta("clay_backplate", bp.get_path())
	if sibling:
		bp.visible = host.is_visible_in_tree()
		if not host.has_meta("clay_vis_hooked"):
			host.set_meta("clay_vis_hooked", true)
			host.visibility_changed.connect(func(): _sync_clay_backplate_visibility(host))
	var mat := apply_clay_material(bp, tint, wetness, corner, sdf_clip)
	mat.set_shader_parameter("extrude_px", 10.0)
	mat.set_shader_parameter("thickness", 1.35)
	_sync_clay_backplate_geom(host, bp, mat)
	_schedule_clay_rect_sync(host)
	return mat

static func _sync_clay_backplate_visibility(host: Control) -> void:
	if host == null:
		return
	var bp: ColorRect = null
	if host.has_meta("clay_backplate"):
		bp = host.get_node_or_null(host.get_meta("clay_backplate")) as ColorRect
	if bp == null:
		bp = _find_clay_backplate(host, host is Container and not (host is BaseButton))
	if bp != null and bp.get_parent() != host:
		bp.visible = host.is_visible_in_tree()

static func _find_clay_backplate(host: Control, sibling: bool) -> ColorRect:
	if sibling:
		var p := host.get_parent()
		if p:
			for c in p.get_children():
				if c is ColorRect and str(c.name).begins_with("ClayBackplate"):
					if c.get_meta("clay_host_path", NodePath()) == host.get_path():
						return c as ColorRect
		var old := host.get_node_or_null("ClayBackplate") as ColorRect
		if old:
			old.queue_free()
		return null
	return host.get_node_or_null("ClayBackplate") as ColorRect

static func _sync_clay_backplate_geom(host: Control, bp: ColorRect, mat: ShaderMaterial) -> void:
	if host == null or bp == null:
		return
	var hs := host.size
	if hs.x < 2.0:
		hs = host.custom_minimum_size
	if bp.get_parent() != host:
		# Sibling plate: match host rect in parent space + extrude pads.
		var parent := bp.get_parent() as Control
		if parent != null:
			var top_left := host.global_position - parent.global_position
			bp.set_anchors_preset(Control.PRESET_TOP_LEFT)
			bp.position = top_left + Vector2(-3.0, -2.0)
			bp.size = hs + Vector2(11.0, 16.0)
			bp.z_index = host.z_index - 1
	if mat:
		mat.set_shader_parameter("rect_px", Vector2(maxf(8.0, hs.x + 11.0), maxf(8.0, hs.y + 16.0)))

static func _schedule_clay_rect_sync(host: Control) -> void:
	if host == null or not host.is_inside_tree():
		return
	var tree := host.get_tree()
	if tree == null:
		return
	tree.create_timer(0.0).timeout.connect(func():
		if is_instance_valid(host):
			_on_clay_host_resized(host)
	)

static func _on_clay_host_resized(host: Control) -> void:
	if host == null:
		return
	var sibling := host is Container and not (host is BaseButton)
	var bp := _find_clay_backplate(host, sibling)
	if bp == null:
		# Resolve via meta path (sibling plate).
		if host.has_meta("clay_backplate"):
			bp = host.get_node_or_null(host.get_meta("clay_backplate")) as ColorRect
	if bp == null or bp.material == null:
		return
	_sync_clay_backplate_geom(host, bp, bp.material as ShaderMaterial)

static func draw_stamp_well(canvas: CanvasItem, rect: Rect2, hot: bool = false) -> void:
	## Deep recessed clay well for glyphs (inner AO + top lip).
	var well := Color(0.12, 0.07, 0.04, 0.96) if hot else Color(0.1, 0.06, 0.035, 0.94)
	canvas.draw_rect(rect, well, true)
	# Inner wall (bottom/right darker)
	canvas.draw_line(rect.position + Vector2(0, rect.size.y), rect.position + rect.size, Color(0.02, 0.01, 0.0, 0.55), 2.5)
	canvas.draw_line(rect.position + Vector2(rect.size.x, 0), rect.position + rect.size, Color(0.02, 0.01, 0.0, 0.4), 2.0)
	# Top/left lip catch-light
	canvas.draw_line(rect.position, rect.position + Vector2(rect.size.x, 0), Color(0.55, 0.45, 0.32, 0.35), 2.0)
	canvas.draw_line(rect.position, rect.position + Vector2(0, rect.size.y), Color(0.45, 0.36, 0.26, 0.28), 1.8)
	canvas.draw_rect(rect.grow(1.0), Color(0.04, 0.02, 0.01, 0.5), false, 2.0)
	if hot:
		canvas.draw_rect(rect, Color(0.95, 0.75, 0.35, 0.2), false, 2.0)

static func draw_embossed_string(canvas: CanvasItem, font: Font, pos: Vector2, text: String, font_size: int, face: Color) -> void:
	## Sculpted stamp: dark lower edge + light upper edge + face.
	canvas.draw_string(font, pos + Vector2(0.0, 1.2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.02, 0.01, 0.0, 0.75))
	canvas.draw_string(font, pos + Vector2(0.0, -0.8), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.75, 0.65, 0.5, 0.35))
	canvas.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, face)

static func draw_clay_extrude_hex(canvas: CanvasItem, center: Vector2, radius: float, body: Color, accent: Color, extrude: float = 7.0) -> void:
	## Stacked hex silhouette = chunky token.
	var side := Color(body.r * 0.55, body.g * 0.5, body.b * 0.45, 0.95)
	draw_hex(canvas, center + Vector2(extrude * 0.35, extrude), radius, Color(0.02, 0.01, 0.0, 0.4), Color(0, 0, 0, 0), 0.0)
	draw_hex(canvas, center + Vector2(extrude * 0.25, extrude * 0.85), radius, side, Color(accent.r, accent.g, accent.b, 0.35), 1.2)
	draw_hex(canvas, center + Vector2(extrude * 0.12, extrude * 0.45), radius, Color(side.r * 1.08, side.g * 1.05, side.b * 1.02, 0.95), Color(0, 0, 0, 0), 0.0)
	draw_hex(canvas, center, radius, body, Color(accent.r, accent.g, accent.b, 0.95), 2.8)
	draw_hex(canvas, center, radius * 0.86, Color(body.r * 1.1, body.g * 1.08, body.b * 1.05, 0.96), Color(accent.r, accent.g, accent.b, 0.7), 1.8)

static func style_text_on_clay(lbl: Control, size: int = -1) -> void:
	if lbl == null:
		return
	apply_readable_font(lbl, size)
	if lbl is Label:
		var l := lbl as Label
		l.add_theme_color_override("font_color", TEXT_ON_CLAY)
		l.add_theme_constant_override("outline_size", 3)
		l.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.02, 0.75))
	elif lbl is Button:
		var b := lbl as Button
		b.add_theme_color_override("font_color", TEXT_ON_CLAY)
		b.add_theme_constant_override("outline_size", 2)
		b.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.02, 0.7))

static func mud_box(inset: bool = false, radius: float = 12.0, _border: Color = AMBER_DIM) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	# Transparent fill — clay ColorRect backplate owns the face; box only casts shadow.
	s.bg_color = Color(0, 0, 0, 0)
	s.border_color = Color(0, 0, 0, 0)
	s.set_border_width_all(0)
	s.set_corner_radius_all(int(radius))
	s.shadow_color = Color(0.02, 0.01, 0.0, 0.72 if not inset else 0.35)
	s.shadow_size = 18 if not inset else 5
	s.shadow_offset = Vector2(1, 8) if not inset else Vector2(0, 2)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 9
	s.content_margin_bottom = 11
	s.anti_aliasing = true
	return s

static func metal_box(inset: bool = false, radius: float = 5.0, border: Color = AMBER_DIM) -> StyleBoxFlat:
	# Alias → wet mud (keeps call sites working).
	return mud_box(inset, maxf(radius, 10.0), border)

static func empty_box() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()

static func gene_code(def_id: String) -> String:
	var h := 0
	for i in def_id.length():
		h = (h * 31 + def_id.unicode_at(i)) % 100
	return "G-%02d" % h

static func hex_points(center: Vector2, radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(6):
		var a := TAU * float(i) / 6.0 - PI * 0.5
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	return pts

static func draw_hex(canvas: CanvasItem, center: Vector2, radius: float, fill: Color, stroke: Color, stroke_w: float = 2.0) -> void:
	var pts := hex_points(center, radius)
	canvas.draw_colored_polygon(pts, fill)
	for i in range(6):
		canvas.draw_line(pts[i], pts[(i + 1) % 6], stroke, stroke_w, true)

static func draw_clay_bead(canvas: CanvasItem, pos: Vector2, radius: float, on: bool, hot: bool = false) -> void:
	var rim := Color(0.12, 0.07, 0.04, 0.85)
	var fill := CLAY_OCHRE if on else Color(0.28, 0.18, 0.12, 0.85)
	if hot and on:
		fill = Color(0.95, 0.72, 0.32, 1.0)
	canvas.draw_circle(pos + Vector2(0.6, 1.0), radius * 1.05, Color(0.05, 0.02, 0.01, 0.35))
	canvas.draw_circle(pos, radius, fill)
	canvas.draw_arc(pos, radius, 0.0, TAU, 16, rim, 1.4, true)
	if on:
		canvas.draw_circle(pos + Vector2(-radius * 0.28, -radius * 0.32), radius * 0.28, Color(1.0, 0.92, 0.75, 0.55))

static func draw_gene_glyph(canvas: CanvasItem, rect: Rect2, def_id: String) -> void:
	draw_action_glyph(canvas, rect, def_id)

static func draw_action_glyph(canvas: CanvasItem, rect: Rect2, action_id: String, stroke: Color = AMBER) -> void:
	var c := rect.get_center()
	var r := mini(rect.size.x, rect.size.y) * 0.36
	var fill := Color(0.28, 0.18, 0.12, 1.0)
	var dim := Color(stroke.r, stroke.g, stroke.b, 0.55)
	match action_id:
		"move", "run":
			canvas.draw_line(c + Vector2(-r * 0.7, r * 0.35), c + Vector2(0, -r * 0.55), stroke, 2.8, true)
			canvas.draw_line(c + Vector2(0, -r * 0.55), c + Vector2(r * 0.7, r * 0.35), stroke, 2.8, true)
			canvas.draw_line(c + Vector2(-r * 0.7, r * 0.7), c + Vector2(0, -r * 0.15), dim, 2.1, true)
			canvas.draw_line(c + Vector2(0, -r * 0.15), c + Vector2(r * 0.7, r * 0.7), dim, 2.1, true)
		"end_turn", "end":
			var s := r * 0.7
			canvas.draw_rect(Rect2(c - Vector2(s, s), Vector2(s * 2, s * 2)), stroke, false, 2.6)
			canvas.draw_line(c + Vector2(-s * 0.4, 0), c + Vector2(s * 0.4, 0), stroke, 2.6, true)
		"melee", "powerstrike", "claw":
			canvas.draw_arc(c + Vector2(-r * 0.15, r * 0.1), r * 0.85, -2.2, 0.6, 18, stroke, 3.2, true)
			canvas.draw_arc(c + Vector2(r * 0.05, r * 0.15), r * 0.55, -2.0, 0.4, 14, dim, 2.1, true)
		"ranged", "railgun", "airstrike", "eye":
			for i in range(8):
				var a := TAU * float(i) / 8.0
				canvas.draw_line(c, c + Vector2(cos(a), sin(a)) * r, stroke, 2.1, true)
			canvas.draw_circle(c, r * 0.28, fill)
			canvas.draw_arc(c, r * 0.28, 0, TAU, 20, stroke, 2.1, true)
		"dash", "charge", "pounce", "blink", "jump":
			var pts := PackedVector2Array([
				c + Vector2(-r * 0.2, -r * 0.85),
				c + Vector2(r * 0.35, -r * 0.1),
				c + Vector2(r * 0.05, -r * 0.1),
				c + Vector2(r * 0.45, r * 0.85),
				c + Vector2(-r * 0.15, r * 0.15),
				c + Vector2(r * 0.1, r * 0.15),
			])
			for i in range(pts.size()):
				canvas.draw_line(pts[i], pts[(i + 1) % pts.size()], stroke, 2.3, true)
		"slam", "eruption", "shell":
			canvas.draw_arc(c, r * 0.9, 0, TAU, 28, stroke, 2.3, true)
			canvas.draw_arc(c, r * 0.55, 0, TAU, 20, dim, 1.7, true)
			for i in range(6):
				var a2 := TAU * float(i) / 6.0
				canvas.draw_circle(c + Vector2(cos(a2), sin(a2)) * r * 0.55, 2.2, stroke)
		"snare", "mine", "big_mine", "gland":
			canvas.draw_arc(c + Vector2(0, r * 0.15), r * 0.55, PI, TAU, 16, stroke, 2.3, true)
			canvas.draw_line(c + Vector2(0, -r * 0.7), c + Vector2(0, -r * 0.15), stroke, 2.6, true)
			canvas.draw_line(c + Vector2(-r * 0.25, -r * 0.55), c + Vector2(r * 0.25, -r * 0.55), stroke, 2.1, true)
		"switch":
			canvas.draw_arc(c, r * 0.7, -0.4, PI - 0.4, 16, stroke, 2.3, true)
			canvas.draw_arc(c, r * 0.7, PI - 0.4, TAU - 0.4, 16, dim, 2.3, true)
			canvas.draw_line(c + Vector2(r * 0.55, -r * 0.35), c + Vector2(r * 0.85, -r * 0.05), stroke, 2.1, true)
			canvas.draw_line(c + Vector2(-r * 0.55, r * 0.35), c + Vector2(-r * 0.85, r * 0.05), dim, 2.1, true)
		"hoof", "core":
			canvas.draw_arc(c, r * 0.75, 0, TAU, 24, stroke, 2.5, true)
			canvas.draw_circle(c, r * 0.22, stroke)
		_:
			canvas.draw_arc(c, r * 0.7, 0, TAU, 20, stroke, 2.1, true)
			canvas.draw_line(c + Vector2(0, -r * 0.35), c + Vector2(0, r * 0.35), stroke, 2.1, true)
			canvas.draw_line(c + Vector2(-r * 0.35, 0), c + Vector2(r * 0.35, 0), stroke, 2.1, true)

## Solid square plaque with chamfered top edge — matches the square grid (not hex).
static func make_bevel_square_mesh(half: float = 0.38, height: float = 0.03, bevel: float = 0.05) -> ArrayMesh:
	var h := height * 0.5
	var b := clampf(bevel, 0.0, half * 0.45)
	var top := half - b
	var bot := PackedVector3Array([
		Vector3(-half, -h, -half), Vector3(half, -h, -half), Vector3(half, -h, half), Vector3(-half, -h, half),
	])
	var topv := PackedVector3Array([
		Vector3(-top, h, -top), Vector3(top, h, -top), Vector3(top, h, top), Vector3(-top, h, top),
	])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Bottom (down).
	st.add_vertex(bot[0]); st.add_vertex(bot[2]); st.add_vertex(bot[1])
	st.add_vertex(bot[0]); st.add_vertex(bot[3]); st.add_vertex(bot[2])
	# Top (up).
	st.add_vertex(topv[0]); st.add_vertex(topv[1]); st.add_vertex(topv[2])
	st.add_vertex(topv[0]); st.add_vertex(topv[2]); st.add_vertex(topv[3])
	# Beveled sides.
	for i in range(4):
		var j := (i + 1) % 4
		st.add_vertex(bot[i]); st.add_vertex(bot[j]); st.add_vertex(topv[j])
		st.add_vertex(bot[i]); st.add_vertex(topv[j]); st.add_vertex(topv[i])
	st.generate_normals()
	return st.commit()
