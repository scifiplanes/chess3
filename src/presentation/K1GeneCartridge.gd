extends Button
class_name K1GeneCartridge

const K1Widgets = preload("res://src/presentation/K1Widgets.gd")
const UnitDefsScript = preload("res://src/sim/UnitDefs.gd")
const DeckRulesScript = preload("res://src/app/DeckRules.gd")

## Wet-mud gene cartridge — soft clay tablet with organ face.

var def_id: String = ""
var lit_pips: int = 2
var is_mutant: bool = false
var _emoji_label: Label
var _code_label: Label
var _ability_label: Label
var _dup_count: int = 1
var _hovering: bool = false
var _placement_active: bool = false
var _selected: bool = false
var _playable: bool = true
var _clay_mat: ShaderMaterial

const BG_ALPHA := 0.96

func _ready() -> void:
	custom_minimum_size = Vector2(72, 114)
	focus_mode = Control.FOCUS_NONE
	flat = false
	text = ""
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_to_group("ui_blocks_board_hover")
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)
	resized.connect(_sync_pivot)
	_clay_mat = K1Widgets.ensure_clay_backplate(self, K1Widgets.CLAY_WET, 0.55, 0.2)
	_ensure_labels()
	_apply_style()
	_refresh_face()
	_sync_pivot()

func _sync_pivot() -> void:
	pivot_offset = size * 0.5

func setup(id: String, pips_on: int = 2, p_is_mutant: bool = false, dup_count: int = 1) -> void:
	def_id = id
	lit_pips = pips_on
	is_mutant = p_is_mutant
	_dup_count = maxi(1, dup_count)
	disabled = id == ""
	set_meta("def_id", id)
	_ensure_labels()
	_apply_style()
	_refresh_face()
	_refresh_hover_look()
	queue_redraw()

func set_offer_state(active: bool, selected: bool, playable: bool) -> void:
	_placement_active = active
	_selected = selected
	_playable = playable
	# Keep clickable so a press can toast why (disabled Buttons swallow input on Web).
	disabled = def_id == ""
	_refresh_hover_look()
	queue_redraw()

func _on_mouse_entered() -> void:
	_hovering = true
	_refresh_hover_look()
	if _clay_mat:
		_clay_mat.set_shader_parameter("wetness", 0.68)
	queue_redraw()

func _on_mouse_exited() -> void:
	_hovering = false
	_refresh_hover_look()
	if _clay_mat:
		_clay_mat.set_shader_parameter("wetness", 0.55)
		_clay_mat.set_shader_parameter("press", 0.0)
	queue_redraw()

func _on_button_down() -> void:
	scale = Vector2(0.96, 0.96)
	if _clay_mat:
		_clay_mat.set_shader_parameter("press", 1.0)
		_clay_mat.set_shader_parameter("extrude_px", 6.0)
		_clay_mat.set_shader_parameter("wetness", 0.72)
	queue_redraw()

func _on_button_up() -> void:
	_refresh_hover_look()
	if _clay_mat:
		_clay_mat.set_shader_parameter("press", 0.0)
		_clay_mat.set_shader_parameter("extrude_px", 10.0)
		_clay_mat.set_shader_parameter("wetness", 0.68 if _hovering else 0.55)
	queue_redraw()

func _hot() -> bool:
	return (is_hovered() or _hovering) and not disabled and def_id != ""

func _refresh_hover_look() -> void:
	if _placement_active and not _playable and def_id != "":
		modulate = Color(0.62, 0.6, 0.56, 0.9)
		scale = Vector2.ONE
		return
	if _selected:
		modulate = Color(1.12, 1.06, 0.9, 1.0)
		scale = Vector2(1.06, 1.06)
	elif _hot():
		modulate = Color(1.08, 1.04, 0.95, 1.0)
		scale = Vector2(1.04, 1.04)
	else:
		modulate = Color(1, 1, 1, 1)
		scale = Vector2.ONE

func _ensure_labels() -> void:
	if _emoji_label == null:
		_emoji_label = Label.new()
		_emoji_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_emoji_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_emoji_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		K1Widgets.apply_emoji_font(_emoji_label, 32)
		_emoji_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_emoji_label.offset_top = 24
		_emoji_label.offset_bottom = -42
		add_child(_emoji_label)
	if _code_label == null:
		_code_label = Label.new()
		_code_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_code_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_code_label.add_theme_color_override("font_color", K1Widgets.TEXT_ON_CLAY)
		K1Widgets.style_text_on_clay(_code_label, 11)
		_code_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
		_code_label.offset_top = 3
		_code_label.offset_bottom = 22
		_code_label.offset_left = 3
		_code_label.offset_right = -3
		add_child(_code_label)
	if _ability_label == null:
		_ability_label = Label.new()
		_ability_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ability_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_ability_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		_ability_label.clip_text = true
		_ability_label.add_theme_color_override("font_color", K1Widgets.TEXT_ON_CLAY)
		K1Widgets.style_text_on_clay(_ability_label, 9)
		_ability_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		# Keep above clay pips (drawn at size.y-14).
		_ability_label.offset_top = -36
		_ability_label.offset_bottom = -18
		_ability_label.offset_left = 4
		_ability_label.offset_right = -4
		add_child(_ability_label)

func _refresh_face() -> void:
	if def_id == "":
		if _emoji_label:
			_emoji_label.text = ""
		if _code_label:
			_code_label.text = ""
		if _ability_label:
			_ability_label.text = ""
		tooltip_text = ""
		return
	if _code_label:
		K1Widgets.style_text_on_clay(_code_label, 11)
	if _ability_label:
		K1Widgets.style_text_on_clay(_ability_label, 9)
	if _emoji_label:
		_emoji_label.text = UnitDefsScript.emoji_for(def_id)
	var name := UnitDefsScript.organ_display_name(def_id)
	if _code_label:
		var title := name
		if is_mutant:
			title = "M·%s" % name
		if _dup_count > 1:
			title = "%s x%d" % [title, _dup_count]
		_code_label.text = title
	var ability := str(DeckRulesScript.GENE_BLURBS.get(def_id, ""))
	if ability == "":
		ability = UnitDefsScript.ability_summary(def_id, is_mutant)
	if _ability_label:
		# Face: verb only so blurb never collides with bottom pips; full string in tooltip.
		var face := ability
		var sep := ability.find(" · ")
		if sep >= 0:
			face = ability.substr(0, sep)
		_ability_label.text = face
		_ability_label.add_theme_color_override("font_color", K1Widgets.TEXT_ON_CLAY)
	var emoji := UnitDefsScript.emoji_for(def_id)
	var kind := "Mutant organ" if is_mutant else "Organ"
	var tip := "%s %s — %s (%s)" % [emoji, name, ability, kind]
	if _dup_count > 1:
		tip += " · x%d in pool" % _dup_count
	tooltip_text = tip

func _cartridge_box(inset: bool, border: Color) -> StyleBoxFlat:
	return K1Widgets.mud_box(inset, 16.0, border)

func _apply_style() -> void:
	add_theme_stylebox_override("normal", _cartridge_box(false, K1Widgets.AMBER_DIM))
	var hover_box := _cartridge_box(false, K1Widgets.CLAY_OCHRE)
	hover_box.shadow_size = 14
	hover_box.shadow_color = Color(0.1, 0.05, 0.02, 0.55)
	add_theme_stylebox_override("hover", hover_box)
	add_theme_stylebox_override("pressed", _cartridge_box(true, K1Widgets.AMBER))
	var disabled_box := _cartridge_box(true, Color(0.35, 0.28, 0.22, 0.5))
	disabled_box.bg_color = Color(0.32, 0.24, 0.18, BG_ALPHA * 0.75)
	add_theme_stylebox_override("disabled", disabled_box)
	add_theme_stylebox_override("focus", K1Widgets.empty_box())

func _draw() -> void:
	if def_id == "":
		return
	var hot := _hot()
	# Recessed organ well behind emoji face.
	var well := Rect2(8, 26, size.x - 16, size.y - 72)
	K1Widgets.draw_stamp_well(self, well, hot or _selected)
	if _placement_active and _playable and not _selected:
		draw_rect(Rect2(Vector2.ZERO, size).grow(-3), Color(0.45, 0.85, 0.45, 0.28), false, 2.5)
	if is_mutant:
		draw_rect(Rect2(Vector2.ZERO, size).grow(-2), Color(0.95, 0.55, 0.18, 0.5), false, 2.5)
	if _selected:
		draw_rect(Rect2(Vector2.ZERO, size).grow(-3), Color(0.95, 0.78, 0.35, 0.4), false, 2.5)
	elif hot:
		draw_rect(Rect2(Vector2.ZERO, size).grow(-4), Color(0.95, 0.75, 0.35, 0.28), false, 2.0)
	var py := size.y - 14.0
	var total_w := 4.0 * 9.0 + 3.0 * 5.0
	var x0 := (size.x - total_w) * 0.5
	for i in range(4):
		K1Widgets.draw_clay_bead(self, Vector2(x0 + i * 14.0 + 4.5, py), 3.8 if hot else 3.3, i < lit_pips, hot)
