extends Control

## Main menu stack: Hot-seat prep, Demo, Settings, Exit.

const CrtMenuChrome = preload("res://src/presentation/CrtMenuChrome.gd")
const DeckRulesScript = preload("res://src/app/DeckRules.gd")
const K1Widgets = preload("res://src/presentation/K1Widgets.gd")
const UnitDefsScript = preload("res://src/sim/UnitDefs.gd")
const MainScene = preload("res://scenes/Main.tscn")

enum Screen { MAIN, PREP, SETTINGS }
enum PrepMode { BAY, DRAFT }

var _screen: Screen = Screen.MAIN
var _crt_screen: MarginContainer
var _crt_layer: Control
var _content: Control
var _toast: Label
var _menu_buttons: Array[Button] = []
var _focus_idx: int = 0

# Prep state — loadout bay (default) + optional draft ritual
var _p0_inv: Dictionary = {}
var _p1_inv: Dictionary = {}
var _prep_mode: PrepMode = PrepMode.BAY
var _prep_player: int = 0
var _p0_locked: bool = false
var _p1_locked: bool = false
var _catalog_open: bool = false
var _draft_rng := RandomNumberGenerator.new()
var _draft_pack: Array[String] = []
var _cap_lbl: Label
var _cap_bar: ProgressBar
var _start_btn: Button
var _start_reason_lbl: Label
var _prep_hint: Label

# Settings refs
var _tempo_row: PanelContainer
var _master_track: Control
var _sfx_track: Control
var _ui_track: Control
var _pan_track: Control
var _master_pct: Label
var _sfx_pct: Label
var _ui_pct: Label
var _pan_pct: Label
var _fullscreen_toggle: Button
var _vsync_toggle: Button
var _skip_pass_toggle: Button
var _corner_panels: Array[PanelContainer] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	K1Widgets.install_ui_theme(self)
	var built: Dictionary = CrtMenuChrome.build_root(self)
	_crt_screen = built["screen"] as MarginContainer
	_crt_layer = built["layer"] as Control
	_content = Control.new()
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_crt_screen.add_child(_content)
	_toast = CrtMenuChrome.toast_label()
	add_child(_toast)
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.offset_top = -48
	_toast.offset_bottom = -24
	_toast.offset_left = -200
	_toast.offset_right = 200
	_p0_inv = DeckRulesScript.preset("default")
	_p1_inv = DeckRulesScript.preset("default")
	_show_main()
	if MatchSession.skip_menu_boot():
		_launch_match_direct()

func _add_main_mutant_ghost() -> void:
	# Faint phosphor ghost behind the menu — color-emoji metrics are huge, keep small + dim.
	var ghost := Label.new()
	ghost.text = "%s\n%s%s" % [
		UnitDefsScript.emoji_for("eye"),
		UnitDefsScript.emoji_for("claw"),
		UnitDefsScript.emoji_for("hoof"),
	]
	ghost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ghost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	K1Widgets.apply_emoji_font(ghost, 36)
	ghost.modulate = Color(CrtMenuChrome.PHOSPHOR.r, CrtMenuChrome.PHOSPHOR.g, CrtMenuChrome.PHOSPHOR.b, 0.22)
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.z_index = -1
	ghost.set_anchors_preset(Control.PRESET_CENTER)
	ghost.offset_left = -70.0
	ghost.offset_right = 70.0
	ghost.offset_top = -160.0
	ghost.offset_bottom = -40.0
	_crt_layer.add_child(ghost)

func _launch_match_direct() -> void:
	MatchSession.configure_hotseat(_p0_inv, _p1_inv, 0)
	get_tree().change_scene_to_packed(MainScene)

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	if _screen == Screen.MAIN and key.keycode == KEY_ESCAPE:
		get_tree().quit()
		return
	if _menu_buttons.is_empty():
		return
	if key.keycode == KEY_UP or key.keycode == KEY_W:
		_focus_idx = posmod(_focus_idx - 1, _menu_buttons.size())
		_menu_buttons[_focus_idx].grab_focus()
	elif key.keycode == KEY_DOWN or key.keycode == KEY_S:
		_focus_idx = posmod(_focus_idx + 1, _menu_buttons.size())
		_menu_buttons[_focus_idx].grab_focus()

func _clear_content() -> void:
	for c in _content.get_children():
		c.queue_free()
	for c in _crt_layer.get_children():
		c.queue_free()
	_menu_buttons.clear()
	_focus_idx = 0
	_corner_panels.clear()
	_prep_hint = null
	_cap_lbl = null
	_cap_bar = null
	_start_btn = null
	_start_reason_lbl = null

func _show_main() -> void:
	_screen = Screen.MAIN
	_clear_content()
	CrtMenuChrome.add_board_backdrop(_crt_layer, 0.16)
	_add_main_mutant_ghost()

	_corner_panels.clear()
	# No hollow MATCH/THREAT telemetry — one teaching line under the title instead.

	var center_wrap := CenterContainer.new()
	center_wrap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.add_child(center_wrap)

	var center := VBoxContainer.new()
	center.custom_minimum_size = Vector2(300, 0)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 10)
	center_wrap.add_child(center)

	center.add_child(CrtMenuChrome.title_banner("CHESS 3", 40))
	center.add_child(CrtMenuChrome.subtitle_label("BIOTIC WARFARE • ADAPT OR DOMINATE", 12))
	# One short line only — rules teaching lives on opening prompt / first egress.
	var teach := Label.new()
	teach.text = "Hot-seat tactics — pass the device."
	teach.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	K1Widgets.apply_readable_font(teach, 13)
	teach.add_theme_color_override("font_color", Color(CrtMenuChrome.PHOSPHOR.r, CrtMenuChrome.PHOSPHOR.g, CrtMenuChrome.PHOSPHOR.b, 0.88))
	center.add_child(teach)
	center.add_child(CrtMenuChrome.hsep(16))

	for pair in [["HOT-SEAT", _on_hotseat], ["DEMO", _on_demo], ["SETTINGS", _on_settings], ["EXIT", _on_exit]]:
		var b := CrtMenuChrome.outline_menu_button(str(pair[0]), 280)
		b.pressed.connect(pair[1])
		center.add_child(b)
		_menu_buttons.append(b)
	# Skip grab_focus during visual validation — focused HOT-SEAT + ui_accept opens prep.
	if _menu_buttons.size() > 0 and not bool(get_meta("validation_mode", false)):
		_menu_buttons[0].grab_focus()

func _show_prep() -> void:
	_screen = Screen.PREP
	_prep_mode = PrepMode.BAY
	_prep_player = 0
	_p0_locked = false
	_p1_locked = false
	_catalog_open = false
	_draft_pack.clear()
	_draft_rng.randomize()
	_p0_inv = DeckRulesScript.preset("default")
	_p1_inv = DeckRulesScript.preset("default")
	_rebuild_prep()

func _rebuild_prep() -> void:
	_clear_content()
	CrtMenuChrome.add_board_backdrop(_crt_layer, 0.10)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	_content.add_child(root)

	var accent := CrtMenuChrome.P1 if _prep_player == 0 else CrtMenuChrome.P2
	var mode_title := "LOADOUT BAY" if _prep_mode == PrepMode.BAY else "GENE DRAFT"
	root.add_child(CrtMenuChrome.title_banner("%s · P%d" % [mode_title, _prep_player + 1], 26))

	var mode_row := HBoxContainer.new()
	mode_row.alignment = BoxContainer.ALIGNMENT_CENTER
	mode_row.add_theme_constant_override("separation", 8)
	var bay_btn := CrtMenuChrome.action_pill("LOADOUT", _prep_mode == PrepMode.BAY)
	bay_btn.pressed.connect(func(): _set_prep_mode(PrepMode.BAY))
	var draft_btn := CrtMenuChrome.action_pill("DRAFT", _prep_mode == PrepMode.DRAFT)
	draft_btn.pressed.connect(func(): _set_prep_mode(PrepMode.DRAFT))
	mode_row.add_child(bay_btn)
	mode_row.add_child(draft_btn)
	root.add_child(mode_row)

	_prep_hint = Label.new()
	_prep_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prep_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# System sans + ASCII — Savage turns "Lock" into "Luck"; Jrudge C→`<`.
	K1Widgets.apply_readable_font(_prep_hint, 16)
	_prep_hint.add_theme_color_override("font_color", Color(accent.r, accent.g, accent.b, 0.9))
	root.add_child(_prep_hint)

	var bud := CrtMenuChrome.budget_bar(0, DeckRulesScript.BUDGET)
	bud["label"].text = "DECK  0 / %d" % DeckRulesScript.BUDGET
	root.add_child(bud["wrap"])
	_cap_lbl = bud["label"]
	_cap_bar = bud["bar"]
	if _cap_bar:
		var fs := StyleBoxFlat.new()
		fs.bg_color = accent
		fs.set_corner_radius_all(4)
		_cap_bar.add_theme_stylebox_override("fill", fs)

	var body := MarginContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("margin_left", 8)
	body.add_theme_constant_override("margin_right", 8)
	root.add_child(body)
	var body_inner := VBoxContainer.new()
	body_inner.add_theme_constant_override("separation", 8)
	body.add_child(body_inner)

	if _prep_mode == PrepMode.BAY:
		_build_bay_body(body_inner, accent)
	else:
		_build_draft_body(body_inner, accent)

	var foot_wrap := VBoxContainer.new()
	foot_wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	foot_wrap.add_theme_constant_override("separation", 6)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_theme_constant_override("separation", 12)
	var back := CrtMenuChrome.action_pill("<- BACK", false)
	back.pressed.connect(_on_prep_back)
	foot.add_child(back)
	if _prep_mode == PrepMode.DRAFT:
		var skip := CrtMenuChrome.action_pill("REROLL PACK", false)
		skip.pressed.connect(_reroll_draft_pack)
		foot.add_child(skip)
	var lock_lbl := "LOCK · PASS TO P2 ->" if _prep_player == 0 else "LOCK · READY"
	if _prep_player == 1 and _p0_locked:
		lock_lbl = "START MATCH ->"
	_start_btn = CrtMenuChrome.action_pill(lock_lbl, true)
	_start_btn.pressed.connect(_on_prep_primary)
	foot.add_child(_start_btn)
	foot_wrap.add_child(foot)
	_start_reason_lbl = Label.new()
	_start_reason_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	K1Widgets.apply_body_font(_start_reason_lbl, 10)
	_start_reason_lbl.add_theme_color_override("font_color", Color(0.95, 0.45, 0.35, 0.9))
	_start_reason_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_start_reason_lbl.custom_minimum_size = Vector2(360, 0)
	foot_wrap.add_child(_start_reason_lbl)
	root.add_child(foot_wrap)
	_refresh_prep_chrome()

func _set_prep_mode(mode: PrepMode) -> void:
	if _prep_mode == mode:
		return
	_prep_mode = mode
	_catalog_open = false
	if mode == PrepMode.DRAFT:
		_inv_set(_prep_player, DeckRulesScript.sanitized_copy({}))
		_roll_draft_pack()
	_rebuild_prep()

func _build_bay_body(parent: VBoxContainer, accent: Color) -> void:
	_prep_hint.text = "Pick a style -> LOCK · rack shows your genes · Customize for catalog"

	var active_style := _active_style_name(_inv_for(_prep_player))
	var styles := HFlowContainer.new()
	styles.alignment = FlowContainer.ALIGNMENT_CENTER
	styles.add_theme_constant_override("h_separation", 6)
	styles.add_theme_constant_override("v_separation", 6)
	for pname in DeckRulesScript.style_presets():
		var label := "BALANCED" if pname == "default" else pname.to_upper()
		var selected := pname == active_style
		var pb := CrtMenuChrome.action_pill(label, selected)
		pb.custom_minimum_size = Vector2(96, 44)
		var pn: String = pname
		pb.pressed.connect(func(): _apply_preset(_prep_player, pn))
		styles.add_child(pb)
	parent.add_child(styles)

	var style_blurb := Label.new()
	style_blurb.text = _style_blurb(active_style)
	style_blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	style_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	K1Widgets.apply_readable_font(style_blurb, 12)
	style_blurb.add_theme_color_override("font_color", Color(0.96, 0.86, 0.52, 0.95))
	parent.add_child(style_blurb)

	var util_row := HBoxContainer.new()
	util_row.alignment = BoxContainer.ALIGNMENT_CENTER
	util_row.add_theme_constant_override("separation", 16)
	var clear_b := Button.new()
	clear_b.text = "Clear rack"
	clear_b.flat = true
	clear_b.focus_mode = Control.FOCUS_NONE
	K1Widgets.apply_readable_font(clear_b, 12)
	clear_b.add_theme_color_override("font_color", CrtMenuChrome.PHOSPHOR_DIM)
	clear_b.pressed.connect(func(): _apply_preset(_prep_player, "clear"))
	util_row.add_child(clear_b)
	var custom := CrtMenuChrome.action_pill("CUSTOMIZE" if not _catalog_open else "CLOSE CATALOG", _catalog_open)
	custom.custom_minimum_size = Vector2(140, 32)
	custom.pressed.connect(func():
		_catalog_open = not _catalog_open
		_rebuild_prep()
	)
	util_row.add_child(custom)
	parent.add_child(util_row)

	var rack_hdr := HBoxContainer.new()
	rack_hdr.add_child(CrtMenuChrome.section_header("Specimen rack"))
	rack_hdr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(rack_hdr)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var scroll_inner := VBoxContainer.new()
	scroll_inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_inner.add_theme_constant_override("separation", 8)
	scroll.add_child(scroll_inner)

	var rack := HFlowContainer.new()
	rack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rack.add_theme_constant_override("h_separation", 10)
	rack.add_theme_constant_override("v_separation", 10)
	scroll_inner.add_child(rack)
	var inv := _inv_for(_prep_player)
	var ordered: Array[String] = []
	for gid in DeckRulesScript.draftable_genes():
		if int(inv.get(gid, 0)) > 0:
			ordered.append(gid)
	ordered.sort_custom(func(a, b): return int(inv.get(a, 0)) > int(inv.get(b, 0)))
	if ordered.is_empty():
		var empty := Label.new()
		empty.text = "Rack empty — pick a style above or Customize to add genes"
		K1Widgets.apply_readable_font(empty, 13)
		empty.add_theme_color_override("font_color", CrtMenuChrome.PHOSPHOR_DIM)
		rack.add_child(empty)
	else:
		for gid in ordered:
			rack.add_child(_rack_cartridge(gid, int(inv.get(gid, 0)), accent, true))

	if not _catalog_open:
		return

	scroll_inner.add_child(CrtMenuChrome.section_header("Gene catalog — tap to add"))
	var catalog := HFlowContainer.new()
	catalog.add_theme_constant_override("h_separation", 6)
	catalog.add_theme_constant_override("v_separation", 6)
	scroll_inner.add_child(catalog)
	for gid2 in DeckRulesScript.draftable_genes():
		catalog.add_child(_catalog_tile(gid2, accent))

func _active_style_name(inv: Dictionary) -> String:
	for pname in DeckRulesScript.style_presets():
		var preset: Dictionary = DeckRulesScript.preset(pname)
		var same := true
		for gid in DeckRulesScript.draftable_genes():
			if int(inv.get(gid, 0)) != int(preset.get(gid, 0)):
				same = false
				break
		if same:
			return pname
	return ""

func _style_blurb(style_name: String) -> String:
	match style_name:
		"rush":
			return "Rush — close fast, ram and claw."
		"kite":
			return "Kite — poke at range, keep your distance."
		"tank":
			return "Tank — thick stacks, slam, hold the points."
		"swarm":
			return "Swarm — many small mutants, overwhelm."
		"default":
			return "Balanced — flexible toolkit for fight or contest."
		_:
			return "Pick a style — rack below shows your genes."

func _build_draft_body(parent: VBoxContainer, accent: Color) -> void:
	_prep_hint.text = "Pick 1 gene from the pack · fills your rack · Reroll skips · -> LOCK when ready"
	if _draft_pack.is_empty():
		_roll_draft_pack()

	parent.add_child(CrtMenuChrome.section_header("Offer pack"))
	var pack_row := HFlowContainer.new()
	pack_row.add_theme_constant_override("h_separation", 10)
	pack_row.add_theme_constant_override("v_separation", 8)
	parent.add_child(pack_row)
	for gid in _draft_pack:
		pack_row.add_child(_draft_pick_card(gid, accent))

	parent.add_child(CrtMenuChrome.section_header("Your rack so far"))
	var rack := HFlowContainer.new()
	rack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rack.add_theme_constant_override("h_separation", 10)
	rack.add_theme_constant_override("v_separation", 10)
	parent.add_child(rack)
	var inv := _inv_for(_prep_player)
	var any := false
	for gid2 in DeckRulesScript.draftable_genes():
		var n := int(inv.get(gid2, 0))
		if n <= 0:
			continue
		any = true
		rack.add_child(_rack_cartridge(gid2, n, accent, false))
	if not any:
		var empty := Label.new()
		empty.text = "No genes yet — pick from the pack"
		K1Widgets.apply_body_font(empty, 12)
		empty.add_theme_color_override("font_color", CrtMenuChrome.PHOSPHOR_DIM)
		rack.add_child(empty)

func _rack_cartridge(gid: String, count: int, accent: Color, can_remove: bool) -> PanelContainer:
	var card := CrtMenuChrome.player_deck_panel(accent)
	# Pack left in HFlow (~4/row) — no expand stretch that leaves holes.
	card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	card.custom_minimum_size = Vector2(148, 118)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	card.add_child(v)
	var emoji := Label.new()
	emoji.text = UnitDefsScript.emoji_for(gid)
	emoji.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	K1Widgets.apply_emoji_font(emoji, 22)
	v.add_child(emoji)
	var name_l := Label.new()
	name_l.text = str(DeckRulesScript.GENE_NAMES.get(gid, gid))
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	K1Widgets.apply_readable_font(name_l, 15)
	name_l.add_theme_color_override("font_color", Color(0.98, 0.94, 0.86, 1.0))
	v.add_child(name_l)
	var blurb := Label.new()
	blurb.text = str(DeckRulesScript.GENE_BLURBS.get(gid, ""))
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	K1Widgets.apply_readable_font(blurb, 10)
	blurb.add_theme_color_override("font_color", Color(0.78, 0.74, 0.66, 0.95))
	v.add_child(blurb)
	var meta := Label.new()
	meta.text = "×%d · %dpt ea" % [count, int(DeckRulesScript.GENE_COSTS.get(gid, 0))]
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	K1Widgets.apply_readable_font(meta, 12)
	meta.add_theme_color_override("font_color", Color(1.0, 0.86, 0.42, 1.0))
	v.add_child(meta)
	if can_remove:
		var rm := Button.new()
		rm.text = "−"
		rm.tooltip_text = "Remove one"
		rm.flat = true
		rm.custom_minimum_size = Vector2(32, 24)
		K1Widgets.apply_readable_font(rm, 16)
		rm.add_theme_color_override("font_color", Color(0.95, 0.55, 0.4, 0.95))
		var g := gid
		rm.pressed.connect(func(): _adjust_gene(_prep_player, g, -1))
		v.add_child(rm)
	return card

func _catalog_tile(gid: String, accent: Color) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(96, 64)
	b.tooltip_text = "%s — %s (%dpt)" % [
		DeckRulesScript.GENE_NAMES.get(gid, gid),
		DeckRulesScript.GENE_BLURBS.get(gid, ""),
		int(DeckRulesScript.GENE_COSTS.get(gid, 0)),
	]
	var n := int(_inv_for(_prep_player).get(gid, 0))
	b.text = "%s\n%s\n%dpt%s" % [
		UnitDefsScript.emoji_for(gid),
		str(DeckRulesScript.GENE_NAMES.get(gid, gid)),
		int(DeckRulesScript.GENE_COSTS.get(gid, 0)),
		(" ·×%d" % n) if n > 0 else "",
	]
	K1Widgets.apply_mixed_emoji_font(b, 9)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.065, 0.06, 0.92)
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	b.add_theme_stylebox_override("normal", sb)
	var g := gid
	b.pressed.connect(func(): _adjust_gene(_prep_player, g, 1))
	return b

func _draft_pick_card(gid: String, accent: Color) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(132, 110)
	b.tooltip_text = str(DeckRulesScript.GENE_BLURBS.get(gid, ""))
	b.text = "%s\n%s\n%dpt" % [
		UnitDefsScript.emoji_for(gid),
		str(DeckRulesScript.GENE_NAMES.get(gid, gid)),
		int(DeckRulesScript.GENE_COSTS.get(gid, 0)),
	]
	K1Widgets.apply_mixed_emoji_font(b, 11)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.07, 0.06, 0.95)
	sb.border_color = accent
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	b.add_theme_stylebox_override("normal", sb)
	var g := gid
	b.pressed.connect(func(): _draft_pick(g))
	return b

func _inv_for(player: int) -> Dictionary:
	return _p0_inv if player == 0 else _p1_inv

func _inv_set(player: int, inv: Dictionary) -> void:
	if player == 0:
		_p0_inv = inv
	else:
		_p1_inv = inv

func _apply_preset(player: int, name: String) -> void:
	_inv_set(player, DeckRulesScript.preset(name))
	_catalog_open = false
	_rebuild_prep()

func _adjust_gene(player: int, gid: String, delta: int) -> void:
	var inv := _inv_for(player)
	var n := clampi(int(inv.get(gid, 0)) + delta, 0, DeckRulesScript.MAX_PER_GENE)
	if delta > 0:
		var trial := inv.duplicate()
		trial[gid] = n
		if DeckRulesScript.point_cost(trial) > DeckRulesScript.BUDGET:
			_toast_msg("Over capacitance")
			return
	inv[gid] = n
	_rebuild_prep()

func _roll_draft_pack() -> void:
	_draft_pack = DeckRulesScript.draft_pack(_inv_for(_prep_player), _draft_rng, 5)

func _reroll_draft_pack() -> void:
	_roll_draft_pack()
	_rebuild_prep()

func _draft_pick(gid: String) -> void:
	var inv := _inv_for(_prep_player)
	var n := clampi(int(inv.get(gid, 0)) + 1, 0, DeckRulesScript.MAX_PER_GENE)
	var trial := inv.duplicate()
	trial[gid] = n
	if DeckRulesScript.point_cost(trial) > DeckRulesScript.BUDGET:
		_toast_msg("Over capacitance")
		return
	inv[gid] = n
	_roll_draft_pack()
	_rebuild_prep()

func _refresh_prep_chrome() -> void:
	var inv := _inv_for(_prep_player)
	var spent := DeckRulesScript.point_cost(inv)
	if _cap_lbl:
		_cap_lbl.text = "DECK  %d / %d" % [spent, DeckRulesScript.BUDGET]
	if _cap_bar:
		_cap_bar.value = float(spent)
	var v := DeckRulesScript.validate(inv)
	if _start_btn:
		_start_btn.disabled = not bool(v["ok"])
	if _start_reason_lbl:
		_start_reason_lbl.text = "" if bool(v["ok"]) else str(v.get("reason", "invalid"))

func _on_prep_back() -> void:
	if _prep_player == 1 and not _p1_locked:
		_prep_player = 0
		_catalog_open = false
		_draft_pack.clear()
		_rebuild_prep()
		return
	_show_main()

func _on_prep_primary() -> void:
	var v := DeckRulesScript.validate(_inv_for(_prep_player))
	if not bool(v["ok"]):
		_toast_msg(str(v.get("reason", "invalid")))
		return
	if _prep_player == 0:
		_p0_locked = true
		_show_pass_handoff()
		return
	_p1_locked = true
	_on_start_match()

func _show_pass_handoff() -> void:
	_clear_content()
	CrtMenuChrome.add_board_backdrop(_crt_layer, 0.08)
	var spent := DeckRulesScript.point_cost(_p0_inv)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.add_child(center)
	var card := CrtMenuChrome.player_deck_panel(CrtMenuChrome.P2)
	card.custom_minimum_size = Vector2(420, 220)
	center.add_child(card)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 12)
	card.add_child(v)
	var title := Label.new()
	title.text = "PASS DEVICE TO PLAYER 2"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	K1Widgets.apply_body_font(title, 20)
	title.add_theme_color_override("font_color", CrtMenuChrome.PHOSPHOR)
	v.add_child(title)
	var sub := Label.new()
	sub.text = "P1 loadout locked · capacitance %d / %d" % [spent, DeckRulesScript.BUDGET]
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	K1Widgets.apply_body_font(sub, 12)
	sub.add_theme_color_override("font_color", CrtMenuChrome.P1)
	v.add_child(sub)
	var go := CrtMenuChrome.action_pill("CONTINUE ->", true)
	go.pressed.connect(_begin_player_two_prep)
	v.add_child(go)

func _begin_player_two_prep() -> void:
	_prep_player = 1
	_catalog_open = false
	_draft_pack.clear()
	if _prep_mode == PrepMode.DRAFT:
		_inv_set(1, DeckRulesScript.sanitized_copy({}))
		_roll_draft_pack()
	_rebuild_prep()

func _show_settings() -> void:
	_screen = Screen.SETTINGS
	_clear_content()

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 10)
	_content.add_child(root)

	var body := MarginContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("margin_left", 48)
	body.add_theme_constant_override("margin_right", 48)
	body.add_theme_constant_override("margin_top", 4)
	root.add_child(body)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 10)
	body.add_child(inner)

	inner.add_child(CrtMenuChrome.title_banner("SETTINGS", 28))
	inner.add_child(CrtMenuChrome.section_header("Audio"))
	var m := CrtMenuChrome.dotted_slider_row("Master Volume", GameSettings.master_volume, 0.0, 1.0)
	_master_track = m["track"]
	_master_pct = m["pct"]
	_master_track.connect("value_changed", func(v: float): _master_pct.text = "%d%%" % int(round(v * 100.0)))
	inner.add_child(m["row"])
	var s := CrtMenuChrome.dotted_slider_row("SFX Volume", GameSettings.sfx_volume, 0.0, 1.0)
	_sfx_track = s["track"]
	_sfx_pct = s["pct"]
	_sfx_track.connect("value_changed", func(v: float): _sfx_pct.text = "%d%%" % int(round(v * 100.0)))
	inner.add_child(s["row"])
	var u := CrtMenuChrome.dotted_slider_row("Music Volume", GameSettings.ui_volume, 0.0, 1.0)
	_ui_track = u["track"]
	_ui_pct = u["pct"]
	_ui_track.connect("value_changed", func(v: float): _ui_pct.text = "%d%%" % int(round(v * 100.0)))
	inner.add_child(u["row"])

	inner.add_child(CrtMenuChrome.section_header("Demo Tempo"))
	_tempo_row = CrtMenuChrome.segmented_tempo(
		PackedStringArray(["slow", "normal", "fast", "turbo"]),
		GameSettings.demo_tempo,
		_pick_tempo
	)
	inner.add_child(_tempo_row)

	inner.add_child(CrtMenuChrome.section_header("Display"))
	var disp := HBoxContainer.new()
	disp.add_theme_constant_override("separation", 8)
	_fullscreen_toggle = CrtMenuChrome.pill_toggle("Fullscreen", GameSettings.fullscreen, func(_v): pass)
	_vsync_toggle = CrtMenuChrome.pill_toggle("VSync", GameSettings.vsync, func(_v): pass)
	disp.add_child(_fullscreen_toggle)
	disp.add_child(_vsync_toggle)
	inner.add_child(disp)

	inner.add_child(CrtMenuChrome.section_header("Hot-seat"))
	_skip_pass_toggle = CrtMenuChrome.pill_toggle("Skip pass banner", GameSettings.skip_pass_interstitial, func(_v): pass)
	inner.add_child(_skip_pass_toggle)

	inner.add_child(CrtMenuChrome.section_header("Controls"))
	var p := CrtMenuChrome.dotted_slider_row("Sensitivity", GameSettings.camera_pan_sensitivity, 0.25, 2.0)
	_pan_track = p["track"]
	_pan_pct = p["pct"]
	_pan_track.connect("value_changed", func(v: float):
		var t := (v - 0.25) / 1.75
		_pan_pct.text = "%d%%" % int(round(t * 100.0))
	)
	inner.add_child(p["row"])

	var foot_wrap := CenterContainer.new()
	foot_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var back := CrtMenuChrome.outline_menu_button("BACK", 160)
	back.pressed.connect(_save_settings_and_main)
	foot_wrap.add_child(back)
	root.add_child(foot_wrap)

func _pick_tempo(t: String) -> void:
	GameSettings.demo_tempo = t
	if _tempo_row:
		for opt in ["slow", "normal", "fast", "turbo"]:
			var b: Button = _tempo_row.get_meta("btn_" + opt, null)
			if b:
				var on: bool = opt == t
				b.button_pressed = on
				CrtMenuChrome._style_tempo_segment(b, on)

func _save_settings_and_main() -> void:
	if _master_track and _master_track.has_method("get_value"):
		GameSettings.master_volume = _master_track.call("get_value")
	if _sfx_track and _sfx_track.has_method("get_value"):
		GameSettings.sfx_volume = _sfx_track.call("get_value")
	if _ui_track and _ui_track.has_method("get_value"):
		GameSettings.ui_volume = _ui_track.call("get_value")
	if _pan_track and _pan_track.has_method("get_value"):
		GameSettings.camera_pan_sensitivity = _pan_track.call("get_value")
		GameSettings.camera_zoom_sensitivity = _pan_track.call("get_value")
	if _fullscreen_toggle:
		GameSettings.fullscreen = _fullscreen_toggle.button_pressed
	if _vsync_toggle:
		GameSettings.vsync = _vsync_toggle.button_pressed
	if _skip_pass_toggle:
		GameSettings.skip_pass_interstitial = _skip_pass_toggle.button_pressed
	GameSettings.save_settings()
	GameSettings.apply_display()
	_show_main()

func _toast_msg(msg: String) -> void:
	_toast.text = msg
	_toast.visible = true
	await get_tree().create_timer(2.0).timeout
	_toast.visible = false

func _on_hotseat() -> void:
	_show_prep()

func _on_demo() -> void:
	MatchSession.configure_demo()
	get_tree().change_scene_to_packed(MainScene)

func _on_settings() -> void:
	_show_settings()

func _on_exit() -> void:
	get_tree().quit()

func _on_start_match() -> void:
	var v0 := DeckRulesScript.validate(_p0_inv)
	var v1 := DeckRulesScript.validate(_p1_inv)
	if not bool(v0["ok"]):
		_toast_msg(str(v0["reason"]))
		return
	if not bool(v1["ok"]):
		_toast_msg(str(v1["reason"]))
		return
	MatchSession.configure_hotseat(_p0_inv, _p1_inv, int(Time.get_unix_time_from_system()) % 100000)
	get_tree().change_scene_to_packed(MainScene)

func show_screen_for_validation(name: String) -> void:
	set_meta("validation_mode", true)
	match name:
		"main":
			_show_main()
		"prep":
			_show_prep()
		"settings":
			_show_settings()
		_:
			_show_main()
	# Drop focus so ui_accept cannot fire HOT-SEAT mid-capture.
	for b in _menu_buttons:
		if b:
			b.release_focus()
	if get_viewport():
		get_viewport().gui_release_focus()
