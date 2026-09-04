extends Control

# K1 board-first HUD — wet-mud clay chrome (phase / zones / genes / MOVE/END).

const K1Widgets = preload("res://src/presentation/K1Widgets.gd")
const K1HexPipScript = preload("res://src/presentation/K1HexPip.gd")
const K1GeneCartridgeScript = preload("res://src/presentation/K1GeneCartridge.gd")
const K1ActionButtonScript = preload("res://src/presentation/K1ActionButton.gd")
const CrtMenuChrome = preload("res://src/presentation/CrtMenuChrome.gd")
const UnitDefsScript = preload("res://src/sim/UnitDefs.gd")
const RulesScript = preload("res://src/sim/Rules.gd")
const OrganEmojiPartScript = preload("res://src/presentation/OrganEmojiPart.gd")

const COL_BG := Color(0.10, 0.11, 0.12, 0.92)
const COL_BG_SOFT := Color(0.08, 0.09, 0.10, 0.78)
const COL_BORDER := Color(0.55, 0.48, 0.34, 0.85)
const COL_AMBER := Color(0.95, 0.72, 0.28, 1.0)
const COL_AMBER_DIM := Color(0.75, 0.55, 0.22, 1.0)
const COL_TEXT := Color(0.92, 0.88, 0.78, 1.0)
const COL_CP0 := Color(0.92, 0.68, 0.22, 1.0)
const COL_CP1 := Color(0.42, 0.72, 0.92, 1.0)

@onready var phase_plaque: PanelContainer = $TopBar
@onready var phase_label: Label = $TopBar/PhaseLabel
@onready var cp_cluster: HBoxContainer = $CpCluster
var cp0_pip: Control
var cp1_pip: Control
@onready var prompt_chip: PanelContainer = $PromptChip
@onready var prompt_label: Label = $PromptChip/PromptLabel
@onready var winner_label: Label = $WinnerLabel

@onready var move_button: Button = $BottomBar/MoveButton
@onready var ability_bar: HBoxContainer = $BottomBar/AbilityBar
@onready var end_turn_button: Button = $BottomBar/EndTurnButton

@onready var offer_panel: Control = $OfferPanel
@onready var offer_cards_row: HBoxContainer = $OfferPanel/VBox/Cards
@onready var offer_skip: Button = $OfferPanel/VBox/SkipButton
var offer_card0: Button
var offer_card1: Button
var offer_card2: Button
var offer_card3: Button
var offer_card4: Button

@onready var toast_label: Label = $Toast
var _toast_tween: Tween
var _end_blink_tween: Tween
var _end_blink_on: bool = false
var _move_highlight_on: bool = false

@onready var squad_inspect_panel: Control = $SquadInspectPanel
@onready var squad_cooldowns_label: Label = $SquadInspectPanel/VBox/CooldownsLabel
@onready var squad_units_list: ItemList = $SquadInspectPanel/VBox/UnitsList

@onready var debug_toggle_button: Button = $DebugDock/DebugToggleButton
@onready var debug_panel: PanelContainer = $DebugDock/DebugPanel
@onready var debug_height_slider: HSlider = $DebugDock/DebugPanel/VBox/HeightRow/HeightSlider
@onready var debug_height_value: Label = $DebugDock/DebugPanel/VBox/HeightRow/HeightValue
@onready var debug_angle_slider: HSlider = $DebugDock/DebugPanel/VBox/AngleRow/AngleSlider
@onready var debug_angle_value: Label = $DebugDock/DebugPanel/VBox/AngleRow/AngleValue
@onready var debug_energy_slider: HSlider = $DebugDock/DebugPanel/VBox/EnergyRow/EnergySlider
@onready var debug_energy_value: Label = $DebugDock/DebugPanel/VBox/EnergyRow/EnergyValue
@onready var debug_shadow_check: CheckBox = $DebugDock/DebugPanel/VBox/ShadowCheck
@onready var debug_bias_slider: HSlider = $DebugDock/DebugPanel/VBox/BiasRow/BiasSlider
@onready var debug_bias_value: Label = $DebugDock/DebugPanel/VBox/BiasRow/BiasValue
@onready var debug_normal_bias_slider: HSlider = $DebugDock/DebugPanel/VBox/NormalBiasRow/NormalBiasSlider
@onready var debug_normal_bias_value: Label = $DebugDock/DebugPanel/VBox/NormalBiasRow/NormalBiasValue
@onready var debug_max_dist_slider: HSlider = $DebugDock/DebugPanel/VBox/MaxDistRow/MaxDistSlider
@onready var debug_max_dist_value: Label = $DebugDock/DebugPanel/VBox/MaxDistRow/MaxDistValue
@onready var debug_light_color: ColorPickerButton = $DebugDock/DebugPanel/VBox/ColorRow/LightColorPicker
@onready var debug_specular_slider: HSlider = $DebugDock/DebugPanel/VBox/SpecularRow/SpecularSlider
@onready var debug_specular_value: Label = $DebugDock/DebugPanel/VBox/SpecularRow/SpecularValue
@onready var debug_spawn_mutant_button: Button = $DebugDock/DebugPanel/VBox/SpawnMutantButton
@onready var debug_dither_enabled: CheckBox = $DebugDock/DebugPanel/VBox/DitherEnabled
@onready var debug_dither_strength: HSlider = $DebugDock/DebugPanel/VBox/DitherStrengthRow/DitherStrengthSlider
@onready var debug_dither_strength_value: Label = $DebugDock/DebugPanel/VBox/DitherStrengthRow/DitherStrengthValue
@onready var debug_dither_levels: HSlider = $DebugDock/DebugPanel/VBox/DitherLevelsRow/DitherLevelsSlider
@onready var debug_dither_levels_value: Label = $DebugDock/DebugPanel/VBox/DitherLevelsRow/DitherLevelsValue
@onready var debug_post_dither_enabled: CheckBox = $DebugDock/DebugPanel/VBox/PostDitherEnabled
@onready var debug_post_dither_strength: HSlider = $DebugDock/DebugPanel/VBox/PostDitherStrengthRow/PostDitherStrengthSlider
@onready var debug_post_dither_strength_value: Label = $DebugDock/DebugPanel/VBox/PostDitherStrengthRow/PostDitherStrengthValue
@onready var debug_post_dither_colour: HSlider = $DebugDock/DebugPanel/VBox/PostDitherColourRow/PostDitherColourSlider
@onready var debug_post_dither_colour_value: Label = $DebugDock/DebugPanel/VBox/PostDitherColourRow/PostDitherColourValue
@onready var debug_post_dither_pixel: HSlider = $DebugDock/DebugPanel/VBox/PostDitherPixelRow/PostDitherPixelSlider
@onready var debug_post_dither_pixel_value: Label = $DebugDock/DebugPanel/VBox/PostDitherPixelRow/PostDitherPixelValue
@onready var debug_post_dither_levels: HSlider = $DebugDock/DebugPanel/VBox/PostDitherLevelsRow/PostDitherLevelsSlider
@onready var debug_post_dither_levels_value: Label = $DebugDock/DebugPanel/VBox/PostDitherLevelsRow/PostDitherLevelsValue
@onready var debug_post_dither_matrix: HSlider = $DebugDock/DebugPanel/VBox/PostDitherMatrixRow/PostDitherMatrixSlider
@onready var debug_post_dither_matrix_value: Label = $DebugDock/DebugPanel/VBox/PostDitherMatrixRow/PostDitherMatrixValue
@onready var debug_post_dither_palette: HSlider = $DebugDock/DebugPanel/VBox/PostDitherPaletteRow/PostDitherPaletteSlider
@onready var debug_post_dither_palette_value: Label = $DebugDock/DebugPanel/VBox/PostDitherPaletteRow/PostDitherPaletteValue
@onready var debug_post_dither_pal0_mix: HSlider = $DebugDock/DebugPanel/VBox/PostDitherPal0MixRow/PostDitherPal0MixSlider
@onready var debug_post_dither_pal0_mix_value: Label = $DebugDock/DebugPanel/VBox/PostDitherPal0MixRow/PostDitherPal0MixValue
@onready var debug_post_dither_gain: HSlider = $DebugDock/DebugPanel/VBox/PostDitherGainRow/PostDitherGainSlider
@onready var debug_post_dither_gain_value: Label = $DebugDock/DebugPanel/VBox/PostDitherGainRow/PostDitherGainValue
@onready var debug_post_dither_lift: HSlider = $DebugDock/DebugPanel/VBox/PostDitherLiftRow/PostDitherLiftSlider
@onready var debug_post_dither_lift_value: Label = $DebugDock/DebugPanel/VBox/PostDitherLiftRow/PostDitherLiftValue
@onready var debug_post_dither_gamma: HSlider = $DebugDock/DebugPanel/VBox/PostDitherGammaRow/PostDitherGammaSlider
@onready var debug_post_dither_gamma_value: Label = $DebugDock/DebugPanel/VBox/PostDitherGammaRow/PostDitherGammaValue

var _debug_sun: DirectionalLight3D

signal action_pressed(action_id: String)
signal offer_card_pressed(unit_def_id: String, offer_index: int)
signal offer_skip_pressed
signal front_unit_requested(unit_index: int)
signal menu_resume_pressed
signal menu_restart_pressed
signal menu_quit_pressed
signal debug_spawn_mutant_pressed
signal demo_pause_pressed
signal demo_skip_pressed
signal demo_exit_pressed
signal demo_tempo_pressed(tempo: String)

@onready var main_menu: Control = $MainMenu
@onready var menu_resume_button: Button = $MainMenu/Center/Panel/VBox/ResumeButton
@onready var menu_restart_button: Button = $MainMenu/Center/Panel/VBox/RestartButton
@onready var menu_quit_button: Button = $MainMenu/Center/Panel/VBox/QuitButton

var _turn_cache := ""
var _phase_cache := ""
var _selection_cache := ""
var _mode_cache := ""
var _info_cache := ""
var _prompt_cache := ""
var _hover_cache := ""
var _rules_overlay: PanelContainer
var _pass_interstitial: PanelContainer
var _pass_interstitial_lbl: Label
var _hover_chip: PanelContainer
var _hover_label: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_k1_widgets()
	_apply_k1_chrome()
	_register_ui_hover_blockers()

	move_button.pressed.connect(func(): action_pressed.emit("move"))
	end_turn_button.pressed.connect(func(): action_pressed.emit("end_turn"))

	_bind_offer_card(offer_card0)
	_bind_offer_card(offer_card1)
	_bind_offer_card(offer_card2)
	_bind_offer_card(offer_card3)
	_bind_offer_card(offer_card4)
	offer_skip.pressed.connect(func(): offer_skip_pressed.emit())

	if squad_units_list:
		squad_units_list.item_clicked.connect(_on_units_list_item_clicked)

	if debug_toggle_button:
		debug_toggle_button.pressed.connect(_on_debug_toggle_pressed)
		debug_toggle_button.modulate = Color(1, 1, 1, 0.35)
	_setup_debug_light_ui_connections()
	_setup_debug_dither_ui()
	_setup_debug_post_dither_ui()
	if debug_spawn_mutant_button:
		debug_spawn_mutant_button.pressed.connect(func(): debug_spawn_mutant_pressed.emit())
		_style_button(debug_spawn_mutant_button)
		K1Widgets.apply_body_font(debug_spawn_mutant_button, 11)

	if menu_resume_button:
		menu_resume_button.pressed.connect(func(): menu_resume_pressed.emit())
	if menu_restart_button:
		menu_restart_button.pressed.connect(func(): menu_restart_pressed.emit())
	if menu_quit_button:
		menu_quit_button.pressed.connect(func(): menu_quit_pressed.emit())
	if main_menu:
		main_menu.visible = false

	if squad_inspect_panel:
		squad_inspect_panel.visible = false
	if debug_toggle_button:
		var dev_tools := OS.is_debug_build()
		debug_toggle_button.visible = dev_tools
		if debug_panel:
			debug_panel.visible = false
		if not dev_tools:
			var dock := get_node_or_null("DebugDock") as Control
			if dock:
				dock.visible = false
		else:
			_fit_debug_dock()
	if prompt_chip:
		prompt_chip.visible = false

func _build_k1_widgets() -> void:
	# Hex CP gems
	for c in cp_cluster.get_children():
		c.free()
	cp0_pip = K1HexPipScript.new()
	cp0_pip.call("set_accent", K1Widgets.CP_GOLD)
	cp0_pip.call("set_seat", "P1")
	cp_cluster.add_child(cp0_pip)
	cp1_pip = K1HexPipScript.new()
	cp1_pip.call("set_accent", K1Widgets.CP_STEEL)
	cp1_pip.call("set_seat", "P2")
	cp_cluster.add_child(cp1_pip)

	# Gene cartridges (organ emoji = board organs)
	for c in offer_cards_row.get_children():
		c.free()
	offer_card0 = K1GeneCartridgeScript.new()
	offer_card1 = K1GeneCartridgeScript.new()
	offer_card2 = K1GeneCartridgeScript.new()
	offer_card3 = K1GeneCartridgeScript.new()
	offer_card4 = K1GeneCartridgeScript.new()
	offer_cards_row.add_child(offer_card0)
	offer_cards_row.add_child(offer_card1)
	offer_cards_row.add_child(offer_card2)
	offer_cards_row.add_child(offer_card3)
	offer_cards_row.add_child(offer_card4)
	offer_cards_row.add_theme_constant_override("separation", 6)

	# MOVE / END as vector-glyph instrument keys
	var bottom := $BottomBar as HBoxContainer
	var old_move := move_button
	var old_end := end_turn_button
	var move_i := old_move.get_index()
	var end_i := old_end.get_index()
	old_move.free()
	old_end.free()
	move_button = K1ActionButtonScript.new()
	end_turn_button = K1ActionButtonScript.new()
	bottom.add_child(move_button)
	bottom.add_child(end_turn_button)
	bottom.move_child(move_button, move_i)
	bottom.move_child(end_turn_button, end_i)
	move_button.call("setup", "move", "MOVE", Vector2(108, 70), 0)
	end_turn_button.call("setup", "end_turn", "END", Vector2(108, 70), 0)

func _bind_offer_card(btn: BaseButton) -> void:
	if btn == null:
		return
	btn.pressed.connect(func():
		var def_id := str(btn.get_meta("def_id", ""))
		if def_id == "":
			def_id = str(btn.get("def_id"))
		var idx := int(btn.get_meta("offer_index", -1))
		if def_id != "":
			offer_card_pressed.emit(def_id, idx)
	)

func _set_action_pips(btn: Button, lit_count: int) -> void:
	if btn != null and btn.has_method("set_pips"):
		btn.call("set_pips", lit_count)

func _apply_k1_chrome() -> void:
	if phase_plaque:
		var plaque := K1Widgets.mud_box(false, 14.0, K1Widgets.AMBER_DIM)
		plaque.content_margin_left = 16
		plaque.content_margin_right = 16
		plaque.content_margin_top = 10
		plaque.content_margin_bottom = 10
		phase_plaque.add_theme_stylebox_override("panel", plaque)
		K1Widgets.ensure_clay_backplate(phase_plaque, K1Widgets.CLAY_WET, 0.5, 0.28)
	_style_label(phase_label, K1Widgets.TEXT_ON_CLAY)
	K1Widgets.style_text_on_clay(phase_label, 14)

	if prompt_chip:
		var chip_box := K1Widgets.mud_box(false, 12.0, K1Widgets.AMBER_DIM)
		chip_box.content_margin_left = 12
		chip_box.content_margin_right = 12
		chip_box.content_margin_top = 8
		chip_box.content_margin_bottom = 8
		prompt_chip.add_theme_stylebox_override("panel", chip_box)
		K1Widgets.ensure_clay_backplate(prompt_chip, K1Widgets.CLAY_WET, 0.5, 0.26)
		prompt_chip.visible = false
		prompt_chip.offset_left = -280.0
		prompt_chip.offset_right = 280.0
		prompt_chip.offset_bottom = 58.0
	_style_label(prompt_label, K1Widgets.TEXT_ON_CLAY)
	K1Widgets.style_text_on_clay(prompt_label, 12)
	if prompt_label:
		prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_style_label(winner_label, K1Widgets.TEXT_ON_CLAY)
	K1Widgets.apply_readable_font(winner_label, 28)
	if winner_label:
		winner_label.modulate = Color(1.0, 0.95, 0.8, 1.0)

	_style_button(offer_skip, K1Widgets.CLAY_TERRA)
	K1Widgets.ensure_clay_backplate(offer_skip, K1Widgets.CLAY_WET, 0.55, 0.3)
	K1Widgets.style_text_on_clay(offer_skip, 13)
	offer_skip.add_theme_stylebox_override("disabled", K1Widgets.mud_box(true, 12.0, Color(0.35, 0.28, 0.22, 0.85)))
	offer_skip.add_theme_color_override("font_color", K1Widgets.TEXT_ON_CLAY)
	offer_skip.add_theme_color_override("font_disabled_color", Color(0.7, 0.64, 0.52, 0.85))
	offer_skip.modulate = Color(1, 1, 1, 1.0)
	offer_skip.custom_minimum_size = Vector2(96, 32)

	if squad_inspect_panel is PanelContainer:
		(squad_inspect_panel as PanelContainer).add_theme_stylebox_override("panel", K1Widgets.mud_box(false, 12.0))
		K1Widgets.ensure_clay_backplate(squad_inspect_panel as Control, K1Widgets.CLAY_WET, 0.5, 0.2)
	var track_title := get_node_or_null("SquadInspectPanel/VBox/Title") as Label
	if track_title:
		_style_label(track_title, K1Widgets.TEXT_ON_CLAY)
		K1Widgets.apply_readable_font(track_title, 12)
	_style_label(squad_cooldowns_label)
	K1Widgets.apply_body_font(squad_cooldowns_label, 11)
	if squad_units_list:
		K1Widgets.apply_body_font(squad_units_list, 11)
	_style_label(toast_label, K1Widgets.TEXT_ON_CLAY)
	K1Widgets.apply_body_font(toast_label, 14)

	var offer_title := get_node_or_null("OfferPanel/VBox/Title") as Label
	if offer_title:
		_style_label(offer_title, K1Widgets.TEXT_ON_CLAY)
		K1Widgets.apply_readable_font(offer_title, 13)

	# Tiny ghost affordance — never mud-plaque (SIZE_FILL was a 264px empty slab).
	if debug_toggle_button:
		debug_toggle_button.custom_minimum_size = Vector2(28, 22)
		debug_toggle_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		debug_toggle_button.flat = true
		debug_toggle_button.add_theme_stylebox_override("normal", K1Widgets.empty_box())
		debug_toggle_button.add_theme_stylebox_override("hover", K1Widgets.empty_box())
		debug_toggle_button.add_theme_stylebox_override("pressed", K1Widgets.empty_box())
		debug_toggle_button.add_theme_stylebox_override("focus", K1Widgets.empty_box())
		K1Widgets.apply_body_font(debug_toggle_button, 12)
		debug_toggle_button.add_theme_color_override("font_color", Color(0.7, 0.62, 0.5, 0.55))
	if debug_panel:
		debug_panel.add_theme_stylebox_override("panel", K1Widgets.mud_box(false, 10.0))
		K1Widgets.ensure_clay_backplate(debug_panel, K1Widgets.CLAY_WET, 0.45, 0.18)
	_apply_body_fonts_under(debug_panel)

	var menu_panel := get_node_or_null("MainMenu/Center/Panel") as PanelContainer
	if menu_panel:
		menu_panel.add_theme_stylebox_override("panel", K1Widgets.mud_box(false, 18.0))
		K1Widgets.ensure_clay_backplate(menu_panel, K1Widgets.CLAY_WET, 0.5, 0.16)
	var menu_title := get_node_or_null("MainMenu/Center/Panel/VBox/Title") as Label
	if menu_title:
		menu_title.text = "CHESS 3"
		_style_label(menu_title, K1Widgets.TEXT_ON_CLAY)
		K1Widgets.apply_readable_font(menu_title, 28)
	for b in [menu_resume_button, menu_restart_button, menu_quit_button]:
		_style_button(b)
		K1Widgets.apply_body_font(b, 13)
		if b:
			K1Widgets.ensure_clay_backplate(b, K1Widgets.CLAY_WET, 0.5, 0.22)

func _register_ui_hover_blockers() -> void:
	# These rects own the pointer: board cell/organ hover must yield.
	var paths: Array[String] = [
		"TopBar",
		"BottomBar",
		"CpCluster",
		"OfferPanel",
		"SquadInspectPanel",
		"DebugDock",
		"MainMenu",
	]
	for path in paths:
		var n := get_node_or_null(path)
		if n is Control:
			var c := n as Control
			# Chrome trays need STOP so empty gaps still own the pointer.
			if path in ["OfferPanel", "BottomBar", "DebugDock", "CpCluster", "TopBar"]:
				c.mouse_filter = Control.MOUSE_FILTER_STOP
			c.add_to_group("ui_blocks_board_hover")
	if offer_skip:
		offer_skip.add_to_group("ui_blocks_board_hover")
		offer_skip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		offer_skip.mouse_entered.connect(func() -> void:
			if not offer_skip.disabled:
				offer_skip.modulate = Color(1.2, 1.12, 0.88, 1.0)
		)
		offer_skip.mouse_exited.connect(func() -> void:
			offer_skip.modulate = Color(1, 1, 1, 0.85) if offer_skip.disabled else Color(1, 1, 1, 1.0)
		)
	if debug_toggle_button:
		debug_toggle_button.add_to_group("ui_blocks_board_hover")
	for b in [menu_resume_button, menu_restart_button, menu_quit_button]:
		if b:
			b.add_to_group("ui_blocks_board_hover")
	# Gene carts / action keys register themselves; ensure post-build membership.
	for b in [move_button, end_turn_button, offer_card0, offer_card1, offer_card2]:
		if b is Control:
			(b as Control).add_to_group("ui_blocks_board_hover")

func _apply_body_fonts_under(root: Node) -> void:
	if root == null:
		return
	for n in root.find_children("*", "Label", true, false):
		K1Widgets.apply_body_font(n as Control, -1)
	for n in root.find_children("*", "Button", true, false):
		K1Widgets.apply_body_font(n as Control, -1)
	for n in root.find_children("*", "CheckBox", true, false):
		K1Widgets.apply_body_font(n as Control, -1)

func setup_debug_light(sun: DirectionalLight3D) -> void:
	_debug_sun = sun
	if _debug_sun == null:
		return
	var euler := _debug_sun.rotation_degrees
	debug_height_slider.value = clampf(euler.x, debug_height_slider.min_value, debug_height_slider.max_value)
	debug_angle_slider.value = fposmod(euler.y, 360.0)
	debug_energy_slider.value = _debug_sun.light_energy
	debug_shadow_check.button_pressed = _debug_sun.shadow_enabled
	debug_bias_slider.value = _debug_sun.shadow_bias
	debug_normal_bias_slider.value = _debug_sun.shadow_normal_bias
	debug_max_dist_slider.value = _debug_sun.directional_shadow_max_distance
	debug_light_color.color = _debug_sun.light_color
	debug_specular_slider.value = _debug_sun.light_specular
	_refresh_debug_light_labels()

func _setup_debug_light_ui_connections() -> void:
	debug_height_slider.value_changed.connect(_on_debug_height_changed)
	debug_angle_slider.value_changed.connect(_on_debug_angle_changed)
	debug_energy_slider.value_changed.connect(_on_debug_energy_changed)
	debug_shadow_check.toggled.connect(_on_debug_shadow_toggled)
	debug_bias_slider.value_changed.connect(_on_debug_bias_changed)
	debug_normal_bias_slider.value_changed.connect(_on_debug_normal_bias_changed)
	debug_max_dist_slider.value_changed.connect(_on_debug_max_dist_changed)
	debug_light_color.color_changed.connect(_on_debug_light_color_changed)
	debug_specular_slider.value_changed.connect(_on_debug_specular_changed)

func _setup_debug_dither_ui() -> void:
	if debug_dither_enabled == null or debug_dither_strength == null or debug_dither_levels == null:
		return
	debug_dither_enabled.button_pressed = OrganEmojiPartScript.dither_enabled
	debug_dither_strength.value = OrganEmojiPartScript.dither_strength
	debug_dither_levels.value = OrganEmojiPartScript.dither_levels
	_refresh_debug_dither_labels()
	debug_dither_enabled.toggled.connect(func(_on: bool) -> void: _push_debug_dither())
	debug_dither_strength.value_changed.connect(func(_v: float) -> void: _push_debug_dither())
	debug_dither_levels.value_changed.connect(func(_v: float) -> void: _push_debug_dither())
	_push_debug_dither()

func _refresh_debug_dither_labels() -> void:
	if debug_dither_strength_value:
		debug_dither_strength_value.text = "%.2f" % debug_dither_strength.value
	if debug_dither_levels_value:
		debug_dither_levels_value.text = "%d" % int(round(debug_dither_levels.value))

func _push_debug_dither() -> void:
	_refresh_debug_dither_labels()
	OrganEmojiPartScript.push_dither_settings(
		bool(debug_dither_enabled.button_pressed),
		float(debug_dither_strength.value),
		float(debug_dither_levels.value),
		get_tree()
	)

func _setup_debug_post_dither_ui() -> void:
	if debug_post_dither_enabled == null or debug_post_dither_strength == null:
		return
	debug_post_dither_enabled.button_pressed = DitherPostProcess.enabled
	debug_post_dither_strength.value = DitherPostProcess.strength
	debug_post_dither_colour.value = DitherPostProcess.colour_preserve
	debug_post_dither_pixel.value = DitherPostProcess.pixel_size
	debug_post_dither_levels.value = DitherPostProcess.levels
	debug_post_dither_matrix.value = DitherPostProcess.matrix_size
	debug_post_dither_palette.value = DitherPostProcess.palette
	debug_post_dither_pal0_mix.value = DitherPostProcess.palette0_mix
	debug_post_dither_gain.value = DitherPostProcess.post_levels
	debug_post_dither_lift.value = DitherPostProcess.post_lift
	debug_post_dither_gamma.value = DitherPostProcess.post_gamma
	_refresh_debug_post_dither_labels()
	var push := func(_v = null) -> void: _push_debug_post_dither()
	debug_post_dither_enabled.toggled.connect(push)
	debug_post_dither_strength.value_changed.connect(push)
	debug_post_dither_colour.value_changed.connect(push)
	debug_post_dither_pixel.value_changed.connect(push)
	debug_post_dither_levels.value_changed.connect(push)
	debug_post_dither_matrix.value_changed.connect(push)
	debug_post_dither_palette.value_changed.connect(push)
	debug_post_dither_pal0_mix.value_changed.connect(push)
	debug_post_dither_gain.value_changed.connect(push)
	debug_post_dither_lift.value_changed.connect(push)
	debug_post_dither_gamma.value_changed.connect(push)
	_push_debug_post_dither()

func _refresh_debug_post_dither_labels() -> void:
	if debug_post_dither_strength_value:
		debug_post_dither_strength_value.text = "%.2f" % debug_post_dither_strength.value
	if debug_post_dither_colour_value:
		debug_post_dither_colour_value.text = "%.2f" % debug_post_dither_colour.value
	if debug_post_dither_pixel_value:
		debug_post_dither_pixel_value.text = "%d" % int(round(debug_post_dither_pixel.value))
	if debug_post_dither_levels_value:
		debug_post_dither_levels_value.text = "%d" % int(round(debug_post_dither_levels.value))
	if debug_post_dither_matrix_value:
		debug_post_dither_matrix_value.text = "%d" % int(round(debug_post_dither_matrix.value))
	if debug_post_dither_palette_value:
		debug_post_dither_palette_value.text = "%d" % int(round(debug_post_dither_palette.value))
	if debug_post_dither_pal0_mix_value:
		debug_post_dither_pal0_mix_value.text = "%.2f" % debug_post_dither_pal0_mix.value
	if debug_post_dither_gain_value:
		debug_post_dither_gain_value.text = "%.2f" % debug_post_dither_gain.value
	if debug_post_dither_lift_value:
		debug_post_dither_lift_value.text = "%.2f" % debug_post_dither_lift.value
	if debug_post_dither_gamma_value:
		debug_post_dither_gamma_value.text = "%.2f" % debug_post_dither_gamma.value

func _push_debug_post_dither() -> void:
	# Snap matrix to 2 / 4 / 8 (Elfenstein contract).
	var m := int(round(debug_post_dither_matrix.value))
	var snapped_m := 2.0 if m <= 3 else (4.0 if m <= 6 else 8.0)
	if absf(debug_post_dither_matrix.value - snapped_m) > 0.01:
		debug_post_dither_matrix.set_value_no_signal(snapped_m)
	_refresh_debug_post_dither_labels()
	DitherPostProcess.push_settings(
		bool(debug_post_dither_enabled.button_pressed),
		float(debug_post_dither_strength.value),
		float(debug_post_dither_colour.value),
		float(debug_post_dither_pixel.value),
		float(debug_post_dither_levels.value),
		snapped_m,
		float(debug_post_dither_palette.value),
		float(debug_post_dither_pal0_mix.value),
		float(debug_post_dither_gain.value),
		float(debug_post_dither_lift.value),
		float(debug_post_dither_gamma.value)
	)

func _on_debug_toggle_pressed() -> void:
	_toggle_debug_panel()

func toggle_debug_panel() -> void:
	_toggle_debug_panel()

func _toggle_debug_panel() -> void:
	if debug_panel == null:
		return
	debug_panel.visible = not debug_panel.visible
	_fit_debug_dock()

func _fit_debug_dock() -> void:
	var dock := get_node_or_null("DebugDock") as Control
	if dock == null:
		return
	# Collapsed: only the tiny … chip — don't reserve a tall empty hover slab.
	if debug_panel != null and debug_panel.visible:
		dock.offset_top = -560.0
		dock.offset_bottom = -130.0
	else:
		dock.offset_top = -158.0
		dock.offset_bottom = -130.0

func _refresh_debug_light_labels() -> void:
	debug_height_value.text = "%.0f" % debug_height_slider.value
	debug_angle_value.text = "%.0f" % debug_angle_slider.value
	debug_energy_value.text = "%.2f" % debug_energy_slider.value
	debug_bias_value.text = "%.3f" % debug_bias_slider.value
	debug_normal_bias_value.text = "%.2f" % debug_normal_bias_slider.value
	debug_max_dist_value.text = "%d" % int(round(debug_max_dist_slider.value))
	debug_specular_value.text = "%.2f" % debug_specular_slider.value

func _on_debug_height_changed(v: float) -> void:
	if _debug_sun:
		var e := _debug_sun.rotation_degrees
		e.x = v
		_debug_sun.rotation_degrees = e
	debug_height_value.text = "%.0f" % v

func _on_debug_angle_changed(v: float) -> void:
	if _debug_sun:
		var e := _debug_sun.rotation_degrees
		e.y = v
		_debug_sun.rotation_degrees = e
	debug_angle_value.text = "%.0f" % v

func _on_debug_energy_changed(v: float) -> void:
	if _debug_sun:
		_debug_sun.light_energy = v
	debug_energy_value.text = "%.2f" % v

func _on_debug_shadow_toggled(on: bool) -> void:
	if _debug_sun:
		_debug_sun.shadow_enabled = on

func _on_debug_bias_changed(v: float) -> void:
	if _debug_sun:
		_debug_sun.shadow_bias = v
	debug_bias_value.text = "%.3f" % v

func _on_debug_normal_bias_changed(v: float) -> void:
	if _debug_sun:
		_debug_sun.shadow_normal_bias = v
	debug_normal_bias_value.text = "%.2f" % v

func _on_debug_max_dist_changed(v: float) -> void:
	if _debug_sun:
		_debug_sun.directional_shadow_max_distance = v
	debug_max_dist_value.text = "%d" % int(round(v))

func _on_debug_light_color_changed(c: Color) -> void:
	if _debug_sun:
		_debug_sun.light_color = c

func _on_debug_specular_changed(v: float) -> void:
	if _debug_sun:
		_debug_sun.light_specular = v
	debug_specular_value.text = "%.2f" % v

func _style_label(lbl: Label, color: Color = K1Widgets.BONE) -> void:
	if lbl == null:
		return
	lbl.add_theme_color_override("font_color", color)

func _style_button(btn: Button, accent: Color = K1Widgets.AMBER_DIM) -> void:
	if btn == null:
		return
	btn.add_theme_stylebox_override("normal", K1Widgets.mud_box(false, 12.0, accent))
	btn.add_theme_stylebox_override("hover", K1Widgets.mud_box(false, 12.0, K1Widgets.CLAY_OCHRE))
	btn.add_theme_stylebox_override("pressed", K1Widgets.mud_box(true, 12.0, K1Widgets.AMBER))
	btn.add_theme_stylebox_override("disabled", K1Widgets.mud_box(true, 12.0, Color(0.35, 0.28, 0.22, 0.5)))
	btn.add_theme_color_override("font_color", K1Widgets.TEXT_ON_CLAY)
	btn.add_theme_color_override("font_hover_color", K1Widgets.CLAY_OCHRE)
	btn.add_theme_color_override("font_disabled_color", Color(0.45, 0.42, 0.38, 0.55))
	btn.add_theme_font_size_override("font_size", 12)

func _refresh_phase_plaque() -> void:
	# Readable phase name (not PHASE 1/2).
	var phase_name := "OFFER"
	var p := _phase_cache.to_lower()
	if "action" in p:
		phase_name = "ACTION"
	elif "offer" in p:
		phase_name = "OFFER"
	var turn_n := 0
	var idx := _turn_cache.find("(T")
	if idx >= 0:
		var end := _turn_cache.find(")", idx)
		if end > idx:
			turn_n = int(_turn_cache.substr(idx + 2, end - idx - 2))
	if phase_label:
		phase_label.text = "%s / TURN %02d" % [phase_name, turn_n]

func _refresh_prompt_chip() -> void:
	if prompt_chip == null or prompt_label == null:
		return
	var chip_text := _prompt_cache.strip_edges()
	if chip_text == "":
		chip_text = _info_cache.strip_edges()
	var show_prompt := chip_text != ""
	prompt_chip.visible = show_prompt
	if show_prompt:
		prompt_label.text = chip_text
	_refresh_hover_chip()

func _ensure_hover_chip() -> void:
	if _hover_chip != null:
		return
	_hover_chip = PanelContainer.new()
	_hover_chip.name = "HoverChip"
	_hover_chip.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hover_chip.offset_left = -200
	_hover_chip.offset_right = 200
	_hover_chip.offset_top = -120
	_hover_chip.offset_bottom = -88
	_hover_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chip_box := K1Widgets.metal_box(true, 4.0, K1Widgets.AMBER_DIM)
	chip_box.content_margin_left = 10
	chip_box.content_margin_right = 10
	chip_box.content_margin_top = 4
	chip_box.content_margin_bottom = 4
	_hover_chip.add_theme_stylebox_override("panel", chip_box)
	_hover_label = Label.new()
	_hover_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hover_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	K1Widgets.apply_body_font(_hover_label, 11)
	_hover_label.add_theme_color_override("font_color", K1Widgets.BONE)
	_hover_chip.add_child(_hover_label)
	_hover_chip.visible = false
	add_child(_hover_chip)

func _refresh_hover_chip() -> void:
	_ensure_hover_chip()
	var t := _hover_cache.strip_edges()
	# Don't cover the gene tray with a sticky mode dump during offers.
	if offer_panel != null and offer_panel.visible:
		if t.begins_with("Gene cartridges") or t.begins_with("Mode:"):
			_hover_chip.visible = false
			return
		_hover_chip.offset_top = -200
		_hover_chip.offset_bottom = -168
	else:
		_hover_chip.offset_top = -120
		_hover_chip.offset_bottom = -88
	_hover_chip.visible = t != ""
	if t != "":
		_hover_label.text = t

func set_hover_info(text: String) -> void:
	_hover_cache = text
	_refresh_hover_chip()

func set_status(turn_text: String, selection_text: String, cp_text: String = "", winner_text: String = "") -> void:
	_turn_cache = turn_text
	_selection_cache = selection_text
	_refresh_phase_plaque()
	_refresh_prompt_chip()

	var a := 0
	var b := 0
	var cleaned := cp_text.replace("CP", "").strip_edges()
	var bits := cleaned.split("-")
	if bits.size() >= 2:
		a = int(bits[0])
		b = int(bits[1])
	const CP_MAJORITY_NEED := 2 # majority of 3 control points
	if cp0_pip and cp0_pip.has_method("set_value"):
		cp0_pip.call("set_value", a, CP_MAJORITY_NEED)
	if cp1_pip and cp1_pip.has_method("set_value"):
		cp1_pip.call("set_value", b, CP_MAJORITY_NEED)

	if winner_label:
		winner_label.text = winner_text

func set_action_bar_visible(visible_on: bool) -> void:
	var bottom := get_node_or_null("BottomBar") as Control
	if bottom:
		bottom.visible = visible_on

func set_action_enabled(action_id: String, enabled: bool) -> void:
	match action_id:
		"move":
			move_button.disabled = not enabled
			_set_action_pips(move_button, 2 if enabled else 0)
		"end_turn":
			end_turn_button.disabled = not enabled
			_set_action_pips(end_turn_button, 4 if enabled else 0)
		_:
			if ability_bar:
				for c in ability_bar.get_children():
					if c is Button and str(c.get_meta("action_id", "")) == action_id:
						(c as Button).disabled = not enabled

func set_end_turn_highlighted(on: bool) -> void:
	if end_turn_button == null:
		return
	_set_end_turn_blink(on and not end_turn_button.disabled)
	var lit := Color(1.18, 1.08, 0.62, 1.0)
	var idle := Color(1, 1, 1, 1)
	if on and not end_turn_button.disabled:
		if end_turn_button.has_method("set_idle_modulate"):
			end_turn_button.call("set_idle_modulate", lit)
		else:
			end_turn_button.modulate = lit
		_set_action_pips(end_turn_button, 4)
	else:
		if end_turn_button.has_method("set_idle_modulate"):
			end_turn_button.call("set_idle_modulate", idle)
		else:
			end_turn_button.modulate = idle
		_set_action_pips(end_turn_button, 0 if end_turn_button.disabled else 4)

func _set_end_turn_blink(on: bool) -> void:
	if end_turn_button == null:
		return
	var running := _end_blink_tween != null and _end_blink_tween.is_valid()
	if on and _end_blink_on and running:
		return
	if (not on) and (not _end_blink_on) and (not running):
		return
	_end_blink_on = on
	if running:
		_end_blink_tween.kill()
	_end_blink_tween = null
	if not on:
		end_turn_button.scale = Vector2.ONE
		return
	_end_blink_tween = create_tween()
	_end_blink_tween.set_loops()
	_end_blink_tween.tween_property(end_turn_button, "modulate", Color(1.35, 1.2, 0.55, 1.0), 0.42).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_end_blink_tween.tween_property(end_turn_button, "modulate", Color(1.05, 0.95, 0.7, 1.0), 0.42).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func set_move_highlighted(on: bool) -> void:
	if move_button == null:
		return
	_move_highlight_on = on and not move_button.disabled
	var lit := Color(1.12, 1.08, 0.85, 1.0)
	var idle := Color(1, 1, 1, 1)
	if _move_highlight_on:
		if move_button.has_method("set_idle_modulate"):
			move_button.call("set_idle_modulate", lit)
		else:
			move_button.modulate = lit
		_set_action_pips(move_button, 2)
	else:
		if move_button.has_method("set_idle_modulate"):
			move_button.call("set_idle_modulate", idle)
		else:
			move_button.modulate = idle

func set_ready_abilities_highlighted(on: bool) -> void:
	if ability_bar == null:
		return
	var lit := Color(1.14, 1.1, 0.88, 1.0)
	var idle := Color(1, 1, 1, 1)
	for c in ability_bar.get_children():
		if not (c is Button):
			continue
		var btn := c as Button
		if btn.disabled:
			if btn.has_method("set_idle_modulate"):
				btn.call("set_idle_modulate", idle)
			else:
				btn.modulate = idle
			continue
		var col := lit if on else idle
		if btn.has_method("set_idle_modulate"):
			btn.call("set_idle_modulate", col)
		else:
			btn.modulate = col
		if btn.has_method("set_pips"):
			btn.call("set_pips", 2 if on else 0)

func set_offer(cards: Array, visible: bool, selected_id: String = "", playable_ids: Array = [], picks_remaining: int = 0, mutants: Array = []) -> void:
	offer_panel.visible = visible
	# One lever: any offer tray owns the chrome — hide MOVE/END/abilities (Main + validators).
	var dock := get_node_or_null("DebugDock") as Control
	if visible:
		set_action_bar_visible(false)
		clear_ability_buttons()
		# Empty "…" debug slab reads as dead left chrome during offers.
		if dock:
			dock.visible = false
	else:
		set_action_bar_visible(true)
		if dock != null and OS.is_debug_build():
			dock.visible = true
			_fit_debug_dock()
	if not visible:
		_refresh_hover_chip()
		return
	if _hover_cache.begins_with("Gene cartridges"):
		_hover_cache = ""
	_refresh_hover_chip()
	var offer_title := get_node_or_null("OfferPanel/VBox/Title") as Label
	if offer_skip:
		# Opening hand (5 cards): Skip locked until at least one gene placed.
		# Enabled = full phosphor; disabled = dim but still readable (not ghost α).
		if cards.size() >= 5:
			offer_skip.disabled = picks_remaining >= 2
			offer_skip.modulate = Color(1, 1, 1, 0.85) if offer_skip.disabled else Color(1, 1, 1, 1.0)
		else:
			offer_skip.disabled = false
			offer_skip.modulate = Color(1, 1, 1, 1.0)
	if offer_title:
		offer_title.visible = true
		if cards.size() >= 5:
			var placed := maxi(0, 2 - picks_remaining) if picks_remaining >= 0 else 0
			var left := maxi(0, picks_remaining)
			if left <= 0:
				offer_title.text = "OPENING  2/2  ·  leave home locks attach"
			else:
				offer_title.text = "OPENING  %d/2  ·  glowing home pad → Mutant" % placed
		else:
			offer_title.text = "GENE TRAY — PICK 1"
	var dup_counts: Dictionary = {}
	for c in cards:
		var cid := str(c)
		dup_counts[cid] = int(dup_counts.get(cid, 0)) + 1
	var carts: Array = [offer_card0, offer_card1, offer_card2, offer_card3, offer_card4]
	for i in range(carts.size()):
		var def_id := ""
		if i < cards.size():
			def_id = str(cards[i])
		var cart = carts[i]
		if def_id == "":
			if cart != null:
				cart.visible = false
			continue
		var is_mutant := false
		if i < mutants.size():
			is_mutant = bool(mutants[i])
		var lit := 2
		if def_id == "eye":
			lit = 1
		elif def_id == "shell":
			lit = 3
		var dups := int(dup_counts.get(def_id, 1))
		if cart != null and cart.has_method("setup"):
			cart.set_meta("offer_index", i)
			cart.call("setup", def_id, lit, is_mutant, dups)
			cart.visible = true
			if cart.has_method("set_offer_state"):
				var playable := playable_ids.has(def_id)
				cart.call("set_offer_state", true, str(selected_id) == def_id, playable)


func set_mode_and_info(mode_text: String, info_text: String) -> void:
	_mode_cache = mode_text
	# Hover/detail dump goes to hover chip — never overwrite phase prompt.
	_hover_cache = info_text
	_refresh_hover_chip()

func set_phase_and_prompt(phase_text: String, prompt_text: String) -> void:
	_phase_cache = phase_text
	_refresh_phase_plaque()
	_prompt_cache = prompt_text.strip_edges()
	_info_cache = _prompt_cache
	if prompt_label:
		prompt_label.set_meta("raw_prompt", prompt_text)
	_refresh_prompt_chip()

func set_menu_visible(on: bool) -> void:
	if main_menu:
		main_menu.visible = on

func is_menu_visible() -> bool:
	return main_menu != null and main_menu.visible

func clear_ability_buttons() -> void:
	if ability_bar == null:
		return
	for c in ability_bar.get_children():
		c.queue_free()

func rebuild_ability_buttons(unit_def_id: String, cooldowns: Dictionary, allow_actions: bool) -> void:
	if ability_bar == null:
		return
	clear_ability_buttons()
	if str(unit_def_id) == "":
		return
	var ids: Array[String] = UnitDefsScript.list_action_ids(str(unit_def_id))
	_build_ability_buttons_from_ids(ids, cooldowns, allow_actions, null)

func rebuild_ability_buttons_for_squad(squad, cooldowns: Dictionary, allow_actions: bool) -> void:
	if ability_bar == null:
		return
	clear_ability_buttons()
	if squad == null:
		return
	var ids: Array[String] = UnitDefsScript.list_action_ids_for_squad(squad)
	_build_ability_buttons_from_ids(ids, cooldowns, allow_actions, squad)

func _build_ability_buttons_from_ids(ids: Array[String], cooldowns: Dictionary, allow_actions: bool, squad) -> void:
	for aid in ids:
		var ad: Dictionary = {}
		if squad != null:
			ad = UnitDefsScript.action_def_for_squad(squad, str(aid))
		else:
			ad = {}
		if ad.is_empty() and squad == null:
			for def_id in UnitDefsScript.DEFS.keys():
				ad = UnitDefsScript.action_def(str(def_id), str(aid))
				if not ad.is_empty():
					break
		if ad.is_empty():
			continue
		var aid_local := str(aid)
		var label := UnitDefsScript.action_label(aid_local)
		var organ_hint := ""
		var organ_emoji := ""
		if squad != null:
			for u_any in squad.units:
				var u = u_any
				if u == null:
					continue
				var ad_u := UnitDefsScript.action_def_for_unit(u, aid_local)
				if not ad_u.is_empty():
					organ_hint = UnitDefsScript.organ_display_name(str(u.unit_def_id))
					organ_emoji = UnitDefsScript.emoji_for(str(u.unit_def_id))
					break
		var cd := int(cooldowns.get(aid, 0))
		var btn: Button = K1ActionButtonScript.new()
		var cd_txt := ("cd %d" % cd) if cd > 0 else ""
		var face := label if organ_emoji == "" else "%s %s" % [organ_emoji, label]
		btn.call("setup", aid_local, face, Vector2(78, 64), 0, cd_txt)
		var tip_bits: Array[String] = []
		if organ_hint != "":
			tip_bits.append(organ_hint)
		tip_bits.append(label)
		var dmg := int(ad.get("damage", 0))
		var rng := int(ad.get("range", 0))
		if dmg > 0 and rng > 0:
			tip_bits.append("r%d dmg %d" % [rng, dmg])
		elif dmg > 0:
			tip_bits.append("dmg %d" % dmg)
		elif rng > 0:
			tip_bits.append("range %d" % rng)
		var aoe := int(ad.get("aoe_radius", 0))
		if aoe > 0:
			tip_bits.append("aoe %d" % aoe)
		if cd > 0:
			tip_bits.append("cd %d" % cd)
		elif int(ad.get("cooldown", 0)) > 0:
			tip_bits.append("ready")
		btn.tooltip_text = " · ".join(tip_bits)
		btn.disabled = (not allow_actions) or cd > 0
		btn.pressed.connect(func(): action_pressed.emit(aid_local))
		ability_bar.add_child(btn)

func toast(text: String, duration_s: float = 1.6) -> void:
	if toast_label == null:
		return
	toast_label.text = text
	toast_label.visible = true
	toast_label.modulate = Color(1, 1, 1, 1)
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(maxf(0.2, duration_s * 0.55))
	_toast_tween.tween_property(toast_label, "modulate:a", 0.0, maxf(0.2, duration_s * 0.45)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_toast_tween.tween_callback(func():
		toast_label.visible = false
	)

func set_selected_squad_inspect(
	units: Array,
	cooldowns: Dictionary,
	is_fresh: bool,
	current_turn: int,
	organs_locked: bool = false,
	organ_count: int = 0,
) -> void:
	if squad_inspect_panel:
		squad_inspect_panel.visible = true

	var stack_emojis := ""
	for ud_any in units:
		if typeof(ud_any) != TYPE_DICTIONARY:
			continue
		stack_emojis += UnitDefsScript.emoji_for(str((ud_any as Dictionary).get("unit_def_id", "")))
	var track_title := get_node_or_null("SquadInspectPanel/VBox/Title") as Label
	if track_title:
		track_title.text = stack_emojis if stack_emojis != "" else "TRACK"

	var cd_parts: Array[String] = []
	var keys: Array = cooldowns.keys()
	keys.sort()
	for k in keys:
		var v := int(cooldowns.get(k, 0))
		if v > 0:
			cd_parts.append("%s:%d" % [str(k), v])
	var cd_str := ", ".join(cd_parts)
	if cd_str == "":
		cd_str = "ready"
	var fresh_text := " | FRESH" if is_fresh else ""
	var lock_text := " | LOCKED" if organs_locked else " | POOL attach"
	var curse_n := 0
	for ud_any in units:
		if typeof(ud_any) != TYPE_DICTIONARY:
			continue
		var ud: Dictionary = ud_any
		if UnitDefsScript.is_curse_organ(str(ud.get("unit_def_id", ""))):
			curse_n += 1
	var curse_text := " | CURSED x%d" % curse_n if curse_n > 0 else ""
	var cap_text := ""
	if organ_count > 0:
		cap_text = " | %d/%d organs" % [organ_count, RulesScript.ORGAN_HARD_MAX]
	squad_cooldowns_label.text = "CD %s%s%s%s%s (T%d)" % [cd_str, fresh_text, lock_text, curse_text, cap_text, int(current_turn)]

	squad_units_list.clear()
	for i in range(0, units.size()):
		var ud_any = units[i]
		if typeof(ud_any) != TYPE_DICTIONARY:
			continue
		var ud: Dictionary = ud_any
		var unit_def_id := str(ud.get("unit_def_id", "?"))
		var ready_turn := int(ud.get("ready_turn", 0))
		var prefix := "▶ " if i == 0 else "  "
		var ready_txt := "rdy" if ready_turn <= int(current_turn) else ("@T%d" % ready_turn)
		var text := "%s%s %s %s" % [prefix, UnitDefsScript.emoji_for(unit_def_id), unit_def_id, ready_txt]
		if UnitDefsScript.is_curse_organ(unit_def_id):
			text += " [curse]"
		squad_units_list.add_item(text)

func clear_selected_squad_inspect() -> void:
	if squad_inspect_panel:
		squad_inspect_panel.visible = false
	var track_title := get_node_or_null("SquadInspectPanel/VBox/Title") as Label
	if track_title:
		track_title.text = "TRACK"
	squad_cooldowns_label.text = "No selection"
	if squad_units_list:
		squad_units_list.clear()

func _on_units_list_item_clicked(index: int, _at_position: Vector2, _mouse_button_index: int) -> void:
	front_unit_requested.emit(int(index))

# --- Demo spectator overlay ---

var _demo_root: Control
var _demo_status: Label
var _demo_strip: Label
var _demo_interstitial: PanelContainer
var _demo_interstitial_label: Label
var _demo_paused: bool = false
var _demo_tempo_btns: Dictionary = {}
var _demo_log_panel: PanelContainer
var _demo_log_scroll: ScrollContainer
var _demo_log_body: VBoxContainer
var _demo_log_line_count: int = 0
const _DEMO_LOG_MAX_LINES := 48

func setup_demo_overlay() -> void:
	if _demo_root != null:
		return
	_demo_root = Control.new()
	_demo_root.name = "DemoOverlay"
	_demo_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_demo_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_demo_root)

	var top := PanelContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_STOP
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 12
	top.offset_top = 8
	top.offset_right = -12
	top.offset_bottom = 44
	top.add_theme_stylebox_override("panel", K1Widgets.metal_box(false, 14.0, COL_AMBER))
	_demo_root.add_child(top)
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 10)
	top.add_child(top_row)
	_demo_status = Label.new()
	_demo_status.text = "DEMO"
	K1Widgets.apply_body_font(_demo_status, 13)
	_demo_status.add_theme_color_override("font_color", COL_AMBER)
	_demo_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(_demo_status)
	for t in ["slow", "normal", "fast"]:
		var on: bool = GameSettings.demo_tempo == t
		var tb := CrtMenuChrome.pill_toggle(t.substr(0, 1).to_upper() + t.substr(1), on, func(_v): pass)
		tb.custom_minimum_size = Vector2(64, 28)
		tb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		# pill_toggle already wired toggled→style; emit tempo + exclusivity on press.
		var tn: String = t
		tb.pressed.connect(func():
			demo_tempo_pressed.emit(tn)
			set_demo_tempo_active(tn)
		)
		top_row.add_child(tb)
		_demo_tempo_btns[t] = tb
	var pause_btn := Button.new()
	pause_btn.text = "Pause"
	pause_btn.custom_minimum_size = Vector2(64, 28)
	pause_btn.pressed.connect(func(): demo_pause_pressed.emit())
	top_row.add_child(pause_btn)
	var skip_btn := Button.new()
	skip_btn.text = "Skip"
	skip_btn.custom_minimum_size = Vector2(56, 28)
	skip_btn.pressed.connect(func(): demo_skip_pressed.emit())
	top_row.add_child(skip_btn)
	var log_btn := Button.new()
	log_btn.text = "Log"
	log_btn.custom_minimum_size = Vector2(48, 28)
	log_btn.pressed.connect(func() -> void:
		if _demo_log_panel:
			_demo_log_panel.visible = not _demo_log_panel.visible
	)
	top_row.add_child(log_btn)
	var exit_btn := Button.new()
	exit_btn.text = "Menu"
	exit_btn.custom_minimum_size = Vector2(56, 28)
	exit_btn.pressed.connect(func(): demo_exit_pressed.emit())
	top_row.add_child(exit_btn)

	_demo_log_panel = PanelContainer.new()
	_demo_log_panel.name = "CommentaryLog"
	_demo_log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_demo_log_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_demo_log_panel.offset_left = 12
	_demo_log_panel.offset_top = 52
	_demo_log_panel.offset_right = 200
	_demo_log_panel.offset_bottom = -44
	_demo_log_panel.add_theme_stylebox_override("panel", K1Widgets.metal_box(false, 12.0, COL_AMBER_DIM))
	_demo_log_panel.visible = false
	_demo_root.add_child(_demo_log_panel)
	var log_v := VBoxContainer.new()
	log_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	log_v.offset_left = 8
	log_v.offset_top = 6
	log_v.offset_right = -8
	log_v.offset_bottom = -6
	log_v.add_theme_constant_override("separation", 4)
	_demo_log_panel.add_child(log_v)
	var log_title := Label.new()
	log_title.text = "COMMENTARY"
	K1Widgets.apply_body_font(log_title, 10)
	log_title.add_theme_color_override("font_color", COL_AMBER_DIM)
	log_v.add_child(log_title)
	_demo_log_scroll = ScrollContainer.new()
	_demo_log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_demo_log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	log_v.add_child(_demo_log_scroll)
	_demo_log_body = VBoxContainer.new()
	_demo_log_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_demo_log_body.add_theme_constant_override("separation", 2)
	_demo_log_scroll.add_child(_demo_log_body)

	var bottom := PanelContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 12
	bottom.offset_top = -36
	bottom.offset_right = -12
	bottom.offset_bottom = -8
	bottom.add_theme_stylebox_override("panel", K1Widgets.metal_box(false, 12.0, COL_AMBER_DIM))
	_demo_root.add_child(bottom)
	_demo_strip = Label.new()
	_demo_strip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	K1Widgets.apply_body_font(_demo_strip, 12)
	_demo_strip.add_theme_color_override("font_color", COL_TEXT)
	bottom.add_child(_demo_strip)

	_demo_interstitial = PanelContainer.new()
	_demo_interstitial.visible = false
	_demo_interstitial.set_anchors_preset(Control.PRESET_CENTER)
	_demo_interstitial.offset_left = -220
	_demo_interstitial.offset_top = -80
	_demo_interstitial.offset_right = 220
	_demo_interstitial.offset_bottom = 80
	_demo_interstitial.add_theme_stylebox_override("panel", K1Widgets.metal_box(false, 18.0, COL_AMBER))
	_demo_root.add_child(_demo_interstitial)
	_demo_interstitial_label = Label.new()
	_demo_interstitial_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_demo_interstitial_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_demo_interstitial_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	K1Widgets.apply_readable_font(_demo_interstitial_label, 18)
	_demo_interstitial_label.add_theme_color_override("font_color", COL_AMBER)
	_demo_interstitial.add_child(_demo_interstitial_label)

func set_demo_status(text: String) -> void:
	if _demo_status:
		_demo_status.text = text

func set_demo_match_info(index: int, seed: int, s0: String, s1: String) -> void:
	if _demo_strip:
		_demo_strip.text = "AI vs AI · seed %d · %s vs %s · Match %03d" % [seed, s0, s1, index]

func set_demo_interstitial(show: bool, data: Dictionary) -> void:
	if _demo_interstitial == null:
		return
	_demo_interstitial.visible = show
	if not show:
		return
	var winner := int(data.get("winner", -1))
	var reason := str(data.get("reason", "?"))
	var wtxt := "DRAW" if winner < 0 else "P%d WINS" % (winner + 1)
	_demo_interstitial_label.text = "%s\n(%s)\nNext match…" % [wtxt, reason]

func set_demo_tempo_active(tempo: String) -> void:
	for k in _demo_tempo_btns.keys():
		var tb: Button = _demo_tempo_btns[k]
		var on: bool = k == tempo
		tb.set_pressed_no_signal(on)
		CrtMenuChrome._style_pill_toggle(tb, on)

func clear_demo_commentary() -> void:
	if _demo_log_body == null:
		return
	for c in _demo_log_body.get_children():
		c.queue_free()
	_demo_log_line_count = 0

func append_demo_commentary(lines: Array) -> void:
	if _demo_log_body == null:
		return
	var last_line := ""
	for line_any in lines:
		var line := str(line_any).strip_edges()
		if line == "":
			continue
		last_line = line
		var lbl := Label.new()
		lbl.text = line
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		K1Widgets.apply_body_font(lbl, 11)
		var col := COL_TEXT
		if line.begins_with("P1"):
			col = COL_CP0
		elif line.begins_with("P2"):
			col = COL_CP1
		elif line.begins_with("—") or line.begins_with("▸"):
			col = COL_AMBER_DIM
		lbl.add_theme_color_override("font_color", col)
		_demo_log_body.add_child(lbl)
		_demo_log_line_count += 1
	while _demo_log_line_count > _DEMO_LOG_MAX_LINES:
		var old = _demo_log_body.get_child(0)
		_demo_log_body.remove_child(old)
		old.queue_free()
		_demo_log_line_count -= 1
	if last_line != "" and _demo_status:
		_demo_status.text = "DEMO · %s" % last_line
	call_deferred("_scroll_demo_log_to_bottom")

func _scroll_demo_log_to_bottom() -> void:
	if _demo_log_scroll == null:
		return
	var bar := _demo_log_scroll.get_v_scroll_bar()
	if bar != null:
		_demo_log_scroll.scroll_vertical = int(bar.max_value)

func demo_commentary_nonempty() -> bool:
	return _demo_log_line_count > 0

func show_first_match_rules_overlay() -> void:
	if _rules_overlay != null:
		_rules_overlay.visible = true
		return
	_rules_overlay = PanelContainer.new()
	_rules_overlay.set_anchors_preset(Control.PRESET_CENTER)
	_rules_overlay.offset_left = -220
	_rules_overlay.offset_top = -120
	_rules_overlay.offset_right = 220
	_rules_overlay.offset_bottom = 120
	_rules_overlay.add_theme_stylebox_override("panel", K1Widgets.metal_box(false, 12.0, COL_AMBER))
	add_child(_rules_overlay)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	_rules_overlay.add_child(vb)
	for line in [
		"Quick rules",
		"• First turns: pick 2 of 5 genes — place on home spawn pads",
		"• Leaving home locks organ attach — gear & eggs still graft",
		"• Later turns: pick 1 of 3 (or Skip)",
	]:
		var lbl := Label.new()
		lbl.text = line
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		K1Widgets.apply_body_font(lbl, 12 if line != "Quick rules" else 14)
		lbl.add_theme_color_override("font_color", COL_TEXT if line != "Quick rules" else COL_AMBER)
		vb.add_child(lbl)
	var dismiss := Button.new()
	dismiss.text = "Got it"
	dismiss.pressed.connect(func() -> void:
		_rules_overlay.visible = false
		GameSettings.seen_rules_overlay = true
		GameSettings.save_settings()
	)
	K1Widgets.apply_body_font(dismiss, 12)
	vb.add_child(dismiss)

func show_pass_interstitial(player: int, cp0: int, cp1: int) -> void:
	if _pass_interstitial == null:
		_pass_interstitial = PanelContainer.new()
		_pass_interstitial.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_pass_interstitial.offset_left = -280
		_pass_interstitial.offset_top = 52
		_pass_interstitial.offset_right = -12
		_pass_interstitial.offset_bottom = 108
		_pass_interstitial.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pass_interstitial.add_theme_stylebox_override("panel", K1Widgets.metal_box(false, 10.0, Color(0.04, 0.04, 0.05, 0.92)))
		add_child(_pass_interstitial)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 4)
		_pass_interstitial.add_child(vb)
		_pass_interstitial_lbl = Label.new()
		_pass_interstitial_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		K1Widgets.apply_body_font(_pass_interstitial_lbl, 16)
		_pass_interstitial_lbl.add_theme_color_override("font_color", COL_AMBER)
		vb.add_child(_pass_interstitial_lbl)
		var hint := Label.new()
		hint.text = "Tap to skip next time (Settings)"
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		K1Widgets.apply_body_font(hint, 9)
		hint.add_theme_color_override("font_color", Color(COL_TEXT.r, COL_TEXT.g, COL_TEXT.b, 0.45))
		vb.add_child(hint)
	_pass_interstitial_lbl.text = "PASS → P%d  ·  CP %d–%d" % [player + 1, cp0, cp1]
	_pass_interstitial.visible = true
	var tw := create_tween()
	tw.tween_interval(0.85)
	tw.tween_callback(func() -> void:
		if is_instance_valid(_pass_interstitial):
			_pass_interstitial.visible = false
	)
