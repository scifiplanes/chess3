extends Control

@onready var turn_label: Label = $TopBar/HBox/TurnLabel
@onready var selection_label: Label = $TopBar/HBox/SelectionLabel
@onready var phase_label: Label = $TopBar/HBox/PhaseLabel
@onready var prompt_label: Label = $TopBar/HBox/PromptLabel
@onready var mode_label: Label = $TopBar/HBox/ModeLabel
@onready var info_label: Label = $TopBar/HBox/InfoLabel
@onready var cp_label: Label = $TopBar/HBox/CPLabel
@onready var winner_label: Label = $TopBar/HBox/WinnerLabel

@onready var move_button: Button = $BottomBar/Actions/MoveButton
@onready var ability_bar: HBoxContainer = $BottomBar/Actions/AbilityBar
@onready var end_turn_button: Button = $BottomBar/Actions/EndTurnButton

const UnitDefsScript = preload("res://src/sim/UnitDefs.gd")

@onready var offer_panel: Control = $OfferPanel
@onready var offer_card0: Button = $OfferPanel/VBox/Cards/Card0
@onready var offer_card1: Button = $OfferPanel/VBox/Cards/Card1
@onready var offer_card2: Button = $OfferPanel/VBox/Cards/Card2
@onready var offer_skip: Button = $OfferPanel/VBox/SkipButton

@onready var toast_label: Label = $Toast
var _toast_tween: Tween

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

var _debug_sun: DirectionalLight3D

signal action_pressed(action_id: String)
signal offer_card_pressed(unit_def_id: String)
signal offer_skip_pressed
signal front_unit_requested(unit_index: int)
signal menu_resume_pressed
signal menu_restart_pressed
signal menu_quit_pressed

@onready var main_menu: Control = $MainMenu
@onready var menu_resume_button: Button = $MainMenu/Center/Panel/VBox/ResumeButton
@onready var menu_restart_button: Button = $MainMenu/Center/Panel/VBox/RestartButton
@onready var menu_quit_button: Button = $MainMenu/Center/Panel/VBox/QuitButton

func _ready() -> void:
	# Let board raycasts “see through” empty HUD areas; children (bars, offer panel, etc.)
	# keep MOUSE_FILTER_STOP and receive clicks normally.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	move_button.pressed.connect(func(): action_pressed.emit("move"))
	end_turn_button.pressed.connect(func(): action_pressed.emit("end_turn"))

	offer_card0.pressed.connect(func(): offer_card_pressed.emit(offer_card0.text))
	offer_card1.pressed.connect(func(): offer_card_pressed.emit(offer_card1.text))
	offer_card2.pressed.connect(func(): offer_card_pressed.emit(offer_card2.text))
	offer_skip.pressed.connect(func(): offer_skip_pressed.emit())

	if squad_units_list:
		squad_units_list.item_clicked.connect(_on_units_list_item_clicked)

	if debug_toggle_button:
		debug_toggle_button.pressed.connect(_on_debug_toggle_pressed)
	_setup_debug_light_ui_connections()

	if menu_resume_button:
		menu_resume_button.pressed.connect(func(): menu_resume_pressed.emit())
	if menu_restart_button:
		menu_restart_button.pressed.connect(func(): menu_restart_pressed.emit())
	if menu_quit_button:
		menu_quit_button.pressed.connect(func(): menu_quit_pressed.emit())
	if main_menu:
		main_menu.visible = false

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

func _on_debug_toggle_pressed() -> void:
	_toggle_debug_panel()

func toggle_debug_panel() -> void:
	_toggle_debug_panel()

func _toggle_debug_panel() -> void:
	if debug_panel == null:
		return
	debug_panel.visible = not debug_panel.visible

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

func set_status(turn_text: String, selection_text: String, cp_text: String = "", winner_text: String = "") -> void:
	turn_label.text = turn_text
	selection_label.text = selection_text
	cp_label.text = cp_text
	winner_label.text = winner_text

func set_mode_and_info(mode_text: String, info_text: String) -> void:
	mode_label.text = mode_text
	info_label.text = info_text

func set_phase_and_prompt(phase_text: String, prompt_text: String) -> void:
	phase_label.text = phase_text
	prompt_label.text = prompt_text

func set_action_enabled(action_id: String, enabled: bool) -> void:
	match action_id:
		"move":
			move_button.disabled = not enabled
		"end_turn":
			end_turn_button.disabled = not enabled
		_:
			if ability_bar:
				for c in ability_bar.get_children():
					if c is Button and str(c.get_meta("action_id", "")) == action_id:
						(c as Button).disabled = not enabled

func set_end_turn_highlighted(on: bool) -> void:
	if end_turn_button == null:
		return
	if on and not end_turn_button.disabled:
		end_turn_button.modulate = Color(1.15, 0.95, 0.35, 1.0)
		end_turn_button.add_theme_font_size_override("font_size", 18)
	else:
		end_turn_button.modulate = Color(1, 1, 1, 1)
		if end_turn_button.has_theme_font_size_override("font_size"):
			end_turn_button.remove_theme_font_size_override("font_size")

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
	for aid in ids:
		var ad: Dictionary = UnitDefsScript.action_def(str(unit_def_id), aid)
		if ad.is_empty():
			continue
		var btn := Button.new()
		btn.text = UnitDefsScript.action_label(str(aid))
		btn.set_meta("action_id", str(aid))
		var cd := int(cooldowns.get(aid, 0))
		btn.disabled = (not allow_actions) or cd > 0
		if cd > 0:
			btn.text += " (%d)" % cd
		var aid_local := str(aid)
		btn.pressed.connect(func(): action_pressed.emit(aid_local))
		ability_bar.add_child(btn)

func set_offer(cards: Array[String], visible: bool) -> void:
	offer_panel.visible = visible
	if not visible:
		return
	var texts := ["", "", ""]
	for i in range(0, mini(3, cards.size())):
		texts[i] = str(cards[i])
	offer_card0.text = texts[0]
	offer_card1.text = texts[1]
	offer_card2.text = texts[2]

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

func set_selected_squad_inspect(units: Array, cooldowns: Dictionary, is_fresh: bool, current_turn: int) -> void:
	# units: Array[Dictionary] with {unit_def_id:String, hp:int, ready_turn:int}
	# cooldowns: Dictionary action_id -> turns remaining
	if squad_inspect_panel:
		squad_inspect_panel.visible = true

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
	squad_cooldowns_label.text = "CD %s%s (T%d)" % [cd_str, fresh_text, int(current_turn)]

	squad_units_list.clear()
	for i in range(0, units.size()):
		var ud_any = units[i]
		if typeof(ud_any) != TYPE_DICTIONARY:
			continue
		var ud: Dictionary = ud_any
		var unit_def_id := str(ud.get("unit_def_id", "?"))
		var hp := int(ud.get("hp", 0))
		var ready_turn := int(ud.get("ready_turn", 0))
		var prefix := "FRONT " if i == 0 else "      "
		var ready_txt := "ready" if ready_turn <= int(current_turn) else ("ready@T%d" % ready_turn)
		var text := "%s[%d] %s | HP %d | %s" % [prefix, i, unit_def_id, hp, ready_txt]
		squad_units_list.add_item(text)

func clear_selected_squad_inspect() -> void:
	if squad_inspect_panel:
		squad_inspect_panel.visible = true
	squad_cooldowns_label.text = "No selection"
	if squad_units_list:
		squad_units_list.clear()

func _on_units_list_item_clicked(index: int, _at_position: Vector2, _mouse_button_index: int) -> void:
	front_unit_requested.emit(int(index))
