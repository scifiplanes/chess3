extends Node3D

const GameStateScript = preload("res://src/sim/GameState.gd")
const ResolverScript = preload("res://src/sim/Resolver.gd")
const RulesScript = preload("res://src/sim/Rules.gd")
const PathfindingScript = preload("res://src/sim/Pathfinding.gd")
const BoardStateScript = preload("res://src/sim/BoardState.gd")
const PatchApplierScript = preload("res://src/net/PatchApplier.gd")
const UnitDefsScript = preload("res://src/sim/UnitDefs.gd")
const UnitStateScript = preload("res://src/sim/UnitState.gd")
const BoardAtmosphereScript = preload("res://src/presentation/vfx/BoardAtmosphere.gd")
const AbilityBurstVfxScript = preload("res://src/presentation/vfx/AbilityBurstVfx.gd")
const HitSparkVfxScript = preload("res://src/presentation/vfx/HitSparkVfx.gd")
const CombatJuiceScript = preload("res://src/presentation/vfx/CombatJuice.gd")
const ImpactDebrisScript = preload("res://src/presentation/vfx/ImpactDebris.gd")
const OrganSplatterVfxScript = preload("res://src/presentation/vfx/OrganSplatterVfx.gd")
const AbilityTelegraphScript = preload("res://src/presentation/AbilityTelegraph.gd")
const DemoDirectorScript = preload("res://src/presentation/DemoDirector.gd")
const MenuFlowScene = preload("res://scenes/MenuFlow.tscn")

@onready var board_view: Node = $Board
@onready var input_controller: Node = $Board/InputController
@onready var hud: Control = $HUD/HUDRoot

var gs
var resolver
var rules
var pathfinding
var current_action: String = "select"
var reachable := {} # Vector2i -> steps
var pending_card_unit_def_id: String = ""
var pending_card_offer_index: int = -1
var pending_card_is_mutant: bool = false
var switch_pick_sid: int = -1
var hovered_cell: Vector2i = Vector2i(-999, -999)
var _lock_pop_cell: Vector2i = Vector2i(-999, -999)
var _lock_popped_cells := {} # Vector2i -> true (once per move-mode session)
const SNAPSHOT_PATH := "user://snapshot.json"

var _prev_squad_hp := {} # int -> int
var _prev_organs_locked := {} # int -> bool
var _prev_pickups := {} # Vector2i -> {kind, def_id}
var _prev_cp_owner := {} # Vector2i -> int
var _prev_obstacle_hp := {} # Vector2i -> int
var _prev_obstacle_kind := {} # Vector2i -> String (hero prop kind, if any)
var _match_over_announced_for: int = -2

var net_mode: bool = false
var demo_mode: bool = false
var _last_active_player: int = -1
var _last_pass_cp: Vector2i = Vector2i(-1, -1)
var _demo_director: Node
var net_room_code: String = ""
var net_player: String = ""
var net_state: Dictionary = {}

var _vfx_root: Node3D
var _atmosphere: Node3D

func _terrain_name(tid: int) -> String:
	match tid:
		BoardStateScript.TERRAIN_SOIL:
			return "Soil"
		BoardStateScript.TERRAIN_ROCK:
			return "Rock"
		BoardStateScript.TERRAIN_SAND:
			return "Sand"
		_:
			return "?"

func _setup_battlefield_juice() -> void:
	_vfx_root = Node3D.new()
	_vfx_root.name = "VfxRoot"
	add_child(_vfx_root)
	_atmosphere = BoardAtmosphereScript.new()
	_atmosphere.name = "Atmosphere"
	add_child(_atmosphere)
	var half := 7.2
	var center := Vector3(7.0, 0.0, 7.0)
	if board_view != null:
		if board_view.has_method("board_half_extent"):
			half = float(board_view.call("board_half_extent"))
		if board_view.has_method("board_center_xz"):
			var c: Vector2 = board_view.call("board_center_xz")
			center = Vector3(c.x, 0.0, c.y)
	_atmosphere.call("setup", half, center)
	AbilityBurstVfxScript.warmup(_vfx_root, center + Vector3(0, 0.2, 0))
	HitSparkVfxScript.warmup(_vfx_root, center + Vector3(0, 0.4, 0))
	OrganSplatterVfxScript.warmup(_vfx_root, center + Vector3(0, 0.5, 0))

func _play_combat_juice(action_id: String, from_cell: Vector2i, to_cell: Vector2i, defender_id: int = -1, aoe_radius: float = 1.0, impact_override: Array = []) -> void:
	if board_view == null or _vfx_root == null:
		return
	var origin: Vector3 = board_view.call("cell_world_center", from_cell)
	var target: Vector3 = board_view.call("cell_world_center", to_cell)
	var ground_y: float = float(board_view.call("board_ground_y"))
	var board_c: Vector2 = board_view.call("board_center_xz")
	var board_h: float = float(board_view.call("board_half_extent"))
	var debris_host: Node3D = board_view.call("debris_root")
	var defender_view = null
	if defender_id >= 0 and board_view.has_method("get_squad_view"):
		defender_view = board_view.call("get_squad_view", defender_id)
	# Board-first resolve flash (primary telegraph); particles secondary.
	var ad: Dictionary = {}
	if gs != null and gs.selected_squad_id != -1:
		var s = gs.get_squad(gs.selected_squad_id)
		if s != null:
			ad = UnitDefsScript.action_def_for_squad(s, action_id)
	if ad.is_empty() and aoe_radius > 0.0:
		ad = {"aoe_radius": int(round(aoe_radius))}
	var prev: Dictionary = AbilityTelegraphScript.preview(gs, action_id, from_cell, to_cell, ad)
	var impact: Array = impact_override if not impact_override.is_empty() else prev.get("impact_cells", [])
	if impact.is_empty() and board_view.has_method("is_in_bounds") and board_view.call("is_in_bounds", to_cell):
		impact = [to_cell]
	if board_view.has_method("flash_cells") and not impact.is_empty():
		var flash_col := AbilityTelegraphScript.COLOR_IMPACT
		if bool(prev.get("is_line", false)) or str(action_id) in ["dash", "railgun", "charge"]:
			flash_col = Color(1.0, 0.78, 0.35, 1.0)
		board_view.call("flash_cells", impact, flash_col, 0.28)
	CombatJuiceScript.play(
		get_tree(),
		_vfx_root,
		_atmosphere,
		debris_host,
		str(action_id),
		origin,
		target,
		aoe_radius,
		ground_y,
		board_c,
		board_h,
		defender_view
	)



func _after_gene_play() -> void:
	pending_card_unit_def_id = ""
	pending_card_offer_index = -1
	pending_card_is_mutant = false
	reachable.clear()
	if bool(gs.offer_pending):
		current_action = "select"
	else:
		current_action = "select"

func _offer_card_playable(unit_def_id: String) -> bool:
	return _offer_spawn_possible(unit_def_id) or _offer_any_card_reinforce_possible(unit_def_id)

func _maybe_toast_soft_ceiling(squad) -> void:
	if squad == null:
		return
	var n := int(squad.unit_count_alive()) if squad.has_method("unit_count_alive") else 0
	if n > RulesScript.ORGAN_SOFT_CEILING:
		_toast("Soft ceiling: %d organs (hard max %d)" % [n, RulesScript.ORGAN_HARD_MAX])

func _opening_tutorial_active() -> bool:
	return int(gs.turn_number) == 1 and bool(gs.offer_pending) and not bool(GameSettings.seen_opening_tutorial)

func _active_squads_all_fresh() -> bool:
	if gs == null:
		return false
	var any := false
	for sid_any in gs.squads.keys():
		var s = gs.get_squad(int(sid_any))
		if s == null or not s.is_alive():
			continue
		if int(s.owner) != int(gs.active_player):
			continue
		any = true
		if not s.has_method("can_act") or s.can_act(int(gs.turn_number)):
			return false
	return any

func _mark_opening_tutorial_seen() -> void:
	if bool(GameSettings.seen_opening_tutorial):
		return
	GameSettings.seen_opening_tutorial = true
	GameSettings.save_settings()
	_maybe_field_graft_tip()

func _maybe_field_graft_tip() -> void:
	if bool(GameSettings.seen_field_graft_tip):
		return
	GameSettings.seen_field_graft_tip = true
	GameSettings.save_settings()
	_toast("Place on home spawn pads. Leaving home locks organ attach — gear & eggs still graft.")

func _maybe_toast_cp_zone_tip() -> void:
	if demo_mode or bool(GameSettings.seen_cp_zone_tip):
		return
	if gs == null or gs.board == null:
		return
	for s_any in gs.squads.values():
		var s = s_any
		if s == null or not s.is_alive():
			continue
		for cp in gs.board.control_points:
			if gs.board.is_in_cp_zone(s.cell, cp.cell):
				GameSettings.seen_cp_zone_tip = true
				GameSettings.save_settings()
				_toast("Hold 2 of 3 zones (flags add up).")
				return

func _maybe_toast_specialty_offer_tip() -> void:
	if demo_mode or bool(GameSettings.seen_specialty_offer_tip):
		return
	if gs == null or not bool(gs.offer_pending):
		return
	# First post-opening 1-of-3 (hand size 3) — specialty unlocked after teach openers.
	if int(gs.offer_hand_size()) >= 5:
		return
	GameSettings.seen_specialty_offer_tip = true
	GameSettings.save_settings()
	_toast("Later offers: pick 1 gene — specialty unlocked.", 2.4)

func _organ_label(def_id: String) -> String:
	return "%s %s" % [UnitDefsScript.emoji_for(def_id), UnitDefsScript.organ_display_name(def_id)]

func _selected_top_ability_label() -> String:
	if gs == null or int(gs.selected_squad_id) < 0:
		return ""
	var s = gs.get_squad(int(gs.selected_squad_id))
	if s == null:
		return ""
	var ids: Array[String] = UnitDefsScript.list_action_ids_for_squad(s)
	if ids.is_empty():
		return ""
	return UnitDefsScript.action_label(str(ids[0]))

func _selected_stack_emoji_line() -> String:
	if gs == null or int(gs.selected_squad_id) < 0:
		return ""
	var s = gs.get_squad(int(gs.selected_squad_id))
	if s == null:
		return ""
	var bits: Array[String] = []
	for u_any in s.units:
		var u = u_any
		if u == null or int(u.hp) <= 0:
			continue
		bits.append(UnitDefsScript.emoji_for(str(u.unit_def_id)))
	if bits.is_empty():
		return ""
	return "Stack: %s" % "".join(bits)

func _match_over_line(gs_ref) -> String:
	var w := int(gs_ref.winner)
	if w < 0:
		return "MATCH OVER"
	var loser := 1 - w
	var loser_alive := 0
	for s_any in gs_ref.squads.values():
		var s = s_any
		if s != null and s.is_alive() and int(s.owner) == loser:
			loser_alive += 1
	if loser_alive == 0:
		return "MATCH OVER — P%d by elimination" % (w + 1)
	return "MATCH OVER — P%d by control" % (w + 1)

func _pickup_hover_line(cell: Vector2i) -> String:
	if gs == null or gs.board == null or not gs.board.in_bounds(cell):
		return ""
	var egg = gs.board.egg_at(cell)
	if egg != null:
		var eid := str(egg.get("unit_def_id", ""))
		var line := "Egg: %s" % _organ_label(eid)
		if UnitDefsScript.is_curse_organ(eid):
			line += " (cursed)"
		return line
	var gear = gs.board.gear_at(cell)
	if gear != null:
		var gid := str(gear.get("unit_def_id", ""))
		return "Gear: %s" % _organ_label(gid)
	return ""

func _pickup_reachable_hint(sid: int) -> String:
	if sid == -1:
		return ""
	var s = gs.get_squad(sid)
	if s == null or not rules.can_field_attach(s):
		return ""
	var cells: Array[Vector2i] = rules.reachable_field_pickups(gs, sid)
	if cells.is_empty():
		return ""
	var gear_n := 0
	var egg_n := 0
	var curse_n := 0
	for pc in cells:
		var def_id: String = rules.pickup_unit_def_id(gs, pc)
		if def_id == "":
			continue
		if rules.pickup_is_egg(gs, pc):
			if UnitDefsScript.is_curse_organ(def_id):
				curse_n += 1
			else:
				egg_n += 1
		else:
			gear_n += 1
	var bits: Array[String] = []
	if gear_n > 0:
		bits.append("%d gear" % gear_n)
	if egg_n > 0:
		bits.append("%d egg" % egg_n)
	if curse_n > 0:
		bits.append("%d cursed" % curse_n)
	if bits.is_empty():
		return ""
	return "Field graft: " + ", ".join(bits)

func _offer_card_reinforce_fail_reason(unit_def_id: String, squad) -> String:
	# Mirrors `Rules.can_play_card_reinforce` (attach organ).
	if gs.winner != -1:
		return "Game over"
	if not bool(gs.offer_pending):
		return "No gene offer active"
	if squad == null:
		return "Click your Mutant"
	var inv: Dictionary = gs.player_inventory.get(gs.active_player, {})
	if int(inv.get(str(unit_def_id), 0)) <= 0:
		return "No copies of that gene left"
	# Must be one of the offered genes.
	var in_offer := false
	for c in gs.offer_cards:
		if str(c) == str(unit_def_id):
			in_offer = true
			break
	if not in_offer:
		return "That gene is not in the current offer"
	if int(squad.owner) != int(gs.active_player):
		return "Can't attach to enemy Mutants"
	if bool(squad.organs_locked):
		return "Organs locked — step on gear/eggs to field-graft"
	if not rules.is_spawn_pool_cell(gs, squad.cell, int(squad.owner)):
		return "Attach only in your Spawn Pool"
	if not rules.can_add_unit_to_squad(squad, str(unit_def_id)):
		return "Mutant at organ hard max (%d)" % RulesScript.ORGAN_HARD_MAX
	return ""

func _ready() -> void:
	gs = GameStateScript.new()
	resolver = ResolverScript.new()
	rules = RulesScript.new()
	pathfinding = PathfindingScript.new()
	add_child(gs)
	_boot_match_from_session()

	_try_start_network_from_args()

	_setup_battlefield_juice()

	gs.changed.connect(_sync_ui)
	if hud and hud.has_signal("action_pressed"):
		hud.action_pressed.connect(_on_action_pressed)
	if hud and hud.has_signal("offer_card_pressed"):
		hud.offer_card_pressed.connect(_on_offer_card_pressed)
	if hud and hud.has_signal("offer_skip_pressed"):
		hud.offer_skip_pressed.connect(_on_offer_skip_pressed)
	if hud and hud.has_signal("front_unit_requested"):
		hud.front_unit_requested.connect(_on_front_unit_requested)
	if input_controller:
		if input_controller.has_signal("cell_hovered"):
			input_controller.cell_hovered.connect(_on_cell_hovered)
		if input_controller.has_signal("cell_clicked"):
			input_controller.cell_clicked.connect(_on_cell_clicked)

	_apply_default_sun()
	if hud and hud.has_method("setup_debug_light"):
		hud.setup_debug_light($Sun as DirectionalLight3D)
	if hud and hud.has_signal("menu_resume_pressed"):
		hud.menu_resume_pressed.connect(_on_menu_resume)
	if hud and hud.has_signal("menu_restart_pressed"):
		hud.menu_restart_pressed.connect(_on_menu_restart)
	if hud and hud.has_signal("menu_quit_pressed"):
		hud.menu_quit_pressed.connect(_on_menu_quit)
	if hud and hud.has_signal("debug_spawn_mutant_pressed"):
		hud.debug_spawn_mutant_pressed.connect(_on_debug_spawn_mutant)
	if hud and hud.has_signal("demo_pause_pressed"):
		hud.demo_pause_pressed.connect(_on_demo_pause)
	if hud and hud.has_signal("demo_skip_pressed"):
		hud.demo_skip_pressed.connect(_on_demo_skip)
	if hud and hud.has_signal("demo_exit_pressed"):
		hud.demo_exit_pressed.connect(_on_demo_exit)
	if hud and hud.has_signal("demo_tempo_pressed"):
		hud.demo_tempo_pressed.connect(_on_demo_tempo)

	_sync_ui()
	if (not demo_mode) and (not GameSettings.seen_rules_overlay) and hud and hud.has_method("show_first_match_rules_overlay"):
		hud.call("show_first_match_rules_overlay")

func _boot_match_from_session() -> void:
	if MatchSession.mode == MatchSession.Mode.DEMO:
		demo_mode = true
		gs.setup(GameStateScript.DEFAULT_BOARD_SIZE, MatchSession.match_seed, MatchSession.inventories)
		gs.apply_seed_first_player()
		_start_demo_mode()
	elif MatchSession.mode == MatchSession.Mode.HOTSEAT:
		gs.setup(GameStateScript.DEFAULT_BOARD_SIZE, MatchSession.match_seed, MatchSession.inventories)
		gs.apply_seed_first_player()
	else:
		gs.setup(GameStateScript.DEFAULT_BOARD_SIZE)
		gs.apply_seed_first_player()

func _start_demo_mode() -> void:
	if input_controller:
		input_controller.set_process_input(false)
		input_controller.set_process_unhandled_input(false)
	if hud and hud.has_method("setup_demo_overlay"):
		hud.setup_demo_overlay()
	_demo_director = DemoDirectorScript.new()
	_demo_director.name = "DemoDirector"
	add_child(_demo_director)
	_demo_director.setup(self, gs)
	_demo_director.status_changed.connect(_on_demo_status)
	_demo_director.interstitial.connect(_on_demo_interstitial)
	_demo_director.match_started.connect(_on_demo_match_started)
	_demo_director.commentary_appended.connect(_on_demo_commentary)

func restart_demo_match() -> void:
	current_action = "select"
	reachable.clear()
	pending_card_unit_def_id = ""
	pending_card_offer_index = -1
	pending_card_is_mutant = false
	switch_pick_sid = -1
	hovered_cell = Vector2i(-999, -999)
	_prev_squad_hp.clear()
	_prev_cp_owner.clear()
	_prev_obstacle_hp.clear()
	_prev_obstacle_kind.clear()
	_match_over_announced_for = -2
	gs.setup(GameStateScript.DEFAULT_BOARD_SIZE, MatchSession.match_seed, MatchSession.inventories)
	gs.apply_seed_first_player()
	gs.emit_signal("changed")
	call_deferred("demo_frame_all_squads")

func _on_demo_status(text: String) -> void:
	if hud and hud.has_method("set_demo_status"):
		hud.set_demo_status(text)

func _on_demo_interstitial(show: bool, data: Dictionary) -> void:
	if hud and hud.has_method("set_demo_interstitial"):
		hud.set_demo_interstitial(show, data)

func _on_demo_match_started(index: int, seed: int, s0: String, s1: String) -> void:
	if hud and hud.has_method("clear_demo_commentary"):
		hud.call("clear_demo_commentary")
	if hud and hud.has_method("set_demo_match_info"):
		hud.set_demo_match_info(index, seed, s0, s1)
	call_deferred("demo_frame_all_squads")

func _on_demo_commentary(lines: Array) -> void:
	if hud and hud.has_method("append_demo_commentary"):
		hud.call("append_demo_commentary", lines)

func demo_frame_camera(cells: Array) -> void:
	if not demo_mode or cells.is_empty():
		return
	var rig = get_node_or_null("CameraRig")
	if rig == null or not rig.has_method("focus_demo_action"):
		return
	var sum := Vector3.ZERO
	var n := 0
	for c_any in cells:
		var c: Vector2i = c_any
		if board_view and board_view.has_method("cell_world_center"):
			sum += board_view.call("cell_world_center", c)
			n += 1
	if n <= 0:
		return
	rig.call("focus_demo_action", sum / float(n), 0.52)

func demo_frame_all_squads() -> void:
	if gs == null:
		return
	var cells: Array[Vector2i] = []
	for s_any in gs.squads.values():
		var s = s_any
		if s != null and s.is_alive():
			cells.append(s.cell)
	demo_frame_camera(cells)

func _on_demo_pause() -> void:
	if _demo_director:
		_demo_director.request_pause(not bool(_demo_director.paused))

func _on_demo_skip() -> void:
	if _demo_director:
		_demo_director.request_skip_turn()

func _on_demo_exit() -> void:
	_leave_demo_to_menu()

func _leave_demo_to_menu() -> void:
	## Immediate scene change — don't wait on DemoDirector awaits (felt like a dead button).
	if _demo_director != null and is_instance_valid(_demo_director):
		_demo_director.request_exit_menu()
	demo_mode = false
	MatchSession.reset()
	# Deferred: HTML5 can drop sync change_scene from a Button.pressed mid-frame.
	get_tree().change_scene_to_packed.call_deferred(MenuFlowScene)

func _on_menu_quit() -> void:
	if demo_mode:
		_leave_demo_to_menu()
		return
	# Web: quit() is a no-op / blank tab — return to menu instead.
	if OS.has_feature("web"):
		get_tree().change_scene_to_packed.call_deferred(MenuFlowScene)
		return
	get_tree().quit()

func _on_demo_tempo(tempo: String) -> void:
	if _demo_director:
		_demo_director.set_tempo(tempo)
	if hud and hud.has_method("set_demo_tempo_active"):
		hud.set_demo_tempo_active(tempo)

func _apply_default_sun() -> void:
	var sun := $Sun as DirectionalLight3D
	if sun == null:
		return
	sun.rotation_degrees = Vector3(-61, 330, 0)
	sun.light_energy = 2.05
	sun.light_specular = 0.45
	sun.light_color = Color(1, 1, 1, 1)
	sun.shadow_enabled = true
	sun.shadow_bias = 0.068
	sun.shadow_normal_bias = 1.75
	sun.directional_shadow_max_distance = 100.0

func _try_start_network_from_args() -> void:
	var args := OS.get_cmdline_args()
	var net_arg := ""
	var server_arg := ""
	for a in args:
		var s := str(a)
		if s.begins_with("--net="):
			net_arg = s.substr(6)
		elif s.begins_with("--server="):
			server_arg = s.substr(9)

	if net_arg == "":
		return

	var net = get_node_or_null("/root/Network")
	if net == null:
		return

	net_mode = true
	if server_arg != "":
		net.http_base_url = server_arg

	net.connected.connect(func(room_code: String, player: String):
		net_room_code = room_code
		net_player = player
		_sync_ui()
	)
	net.state_received.connect(func(state: Dictionary):
		net_state = state.duplicate(true)
		gs.apply_authoritative_net_state(net_state)
	)
	net.patch_received.connect(func(ops: Array):
		net_state = PatchApplierScript.apply_ops(net_state, ops) as Dictionary
		gs.apply_authoritative_net_state(net_state)
	)
	net.error_received.connect(func(e: Dictionary):
		net_state["_last_error"] = e
		_sync_ui()
	)

	if net_arg == "create":
		net.create_room()
	elif net_arg.begins_with("join:"):
		var rc := net_arg.substr(5).strip_edges().to_upper()
		net.join_room(rc)

func _input(event: InputEvent) -> void:
	# Before GUI: Esc dismisses first-match rules even if Got it has focus.
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
			if hud and hud.has_method("is_rules_overlay_visible") and bool(hud.is_rules_overlay_visible()):
				if hud.has_method("dismiss_rules_overlay"):
					hud.dismiss_rules_overlay()
				get_viewport().set_input_as_handled()
				return

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return
		if k.keycode == KEY_ESCAPE:
			if current_action == "switch_pick":
				switch_pick_sid = -1
				current_action = "select"
				_toast("Switch cancelled")
				_sync_ui()
				get_viewport().set_input_as_handled()
				return
			if current_action == "slam":
				current_action = "select"
				reachable.clear()
				_toast("Slam cancelled")
				_render_highlights()
				get_viewport().set_input_as_handled()
				return
			_toggle_main_menu()
			get_viewport().set_input_as_handled()
			return
		if _is_menu_open():
			return
		if k.keycode == KEY_F3:
			if hud and hud.has_method("toggle_debug_panel"):
				hud.toggle_debug_panel()
				get_viewport().set_input_as_handled()
		elif k.keycode == KEY_S:
			_save_snapshot()
		elif k.keycode == KEY_L:
			_load_snapshot()

func _is_menu_open() -> bool:
	return hud != null and hud.has_method("is_menu_visible") and bool(hud.is_menu_visible())

func _toggle_main_menu() -> void:
	if hud == null or not hud.has_method("set_menu_visible"):
		return
	hud.set_menu_visible(not _is_menu_open())

func _on_menu_resume() -> void:
	if hud and hud.has_method("set_menu_visible"):
		hud.set_menu_visible(false)

func _on_menu_restart() -> void:
	if net_mode:
		_toast("Restart is offline-only")
		return
	_restart_match()
	_on_menu_resume()

func _on_debug_spawn_mutant() -> void:
	if gs == null or gs.board == null:
		return
	if net_mode:
		_toast("Debug spawn is offline-only")
		return
	var cell := _find_debug_spawn_cell()
	if cell.x < 0:
		_toast("No empty cell for debug mutant")
		return
	var pool: Array = UnitDefsScript.DEFS.keys()
	if pool.is_empty():
		return
	# 3–6 organs; always include a core so the stack has a heart.
	var organ_n := mini(RulesScript.ORGAN_SOFT_CEILING, randi_range(3, 6))
	var organs: Array[String] = ["core"]
	while organs.size() < organ_n:
		organs.append(str(pool[randi() % pool.size()]))
	# Shuffle so core is not always front (stabilize will sink it to back).
	for i in range(organs.size() - 1, 0, -1):
		var j := randi() % (i + 1)
		var tmp := organs[i]
		organs[i] = organs[j]
		organs[j] = tmp

	var owner := int(gs.active_player)
	var sid: int = int(gs.add_squad(owner, cell, organs[0], 1))
	var s = gs.get_squad(sid)
	if s == null:
		return
	for i in range(1, organs.size()):
		var oid := str(organs[i])
		var hp := UnitDefsScript.max_hp_for(oid, false)
		s.units.append(UnitStateScript.new(oid, hp, int(gs.turn_number)))
	if gs.has_method("_stabilize_core_at_back"):
		gs.call("_stabilize_core_at_back", s)
	s.organs_locked = false
	s.fresh_turn = -1
	s.moved_turn = -1
	gs.selected_squad_id = sid
	gs.emit_signal("changed")
	_toast("Debug mutant M-%02d @ %s (%d organs)" % [sid, str(cell), s.units.size()])

func _find_debug_spawn_cell() -> Vector2i:
	var sz: Vector2i = gs.board.size
	var cx := int(sz.x / 2)
	var cy := int(sz.y / 2)
	# Spiral from board center for a free, unblocked cell.
	for radius in range(0, maxi(sz.x, sz.y)):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if radius > 0 and absi(dx) != radius and absi(dy) != radius:
					continue
				var c := Vector2i(cx + dx, cy + dy)
				if not gs.board.in_bounds(c):
					continue
				if gs.board.is_blocked(c):
					continue
				if gs.squad_at(c) != null:
					continue
				return c
	return Vector2i(-1, -1)

func _restart_match() -> void:
	current_action = "select"
	reachable.clear()
	pending_card_unit_def_id = ""
	pending_card_offer_index = -1
	pending_card_is_mutant = false
	switch_pick_sid = -1
	hovered_cell = Vector2i(-999, -999)
	_prev_squad_hp.clear()
	_prev_cp_owner.clear()
	_prev_obstacle_hp.clear()
	if MatchSession.mode != MatchSession.Mode.NONE:
		gs.setup(GameStateScript.DEFAULT_BOARD_SIZE, MatchSession.match_seed, MatchSession.inventories)
	else:
		gs.setup(GameStateScript.DEFAULT_BOARD_SIZE)
	gs.apply_seed_first_player()
	gs.emit_signal("changed")

func _save_snapshot() -> void:
	if gs == null:
		return
	var json_text := JSON.stringify(gs.snapshot_dict(), "\t")
	var f := FileAccess.open(SNAPSHOT_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(json_text)
	f.flush()
	f.close()
	gs.emit_signal("changed")

func _load_snapshot() -> void:
	if not FileAccess.file_exists(SNAPSHOT_PATH):
		return
	var f := FileAccess.open(SNAPSHOT_PATH, FileAccess.READ)
	if f == null:
		return
	var json_text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(json_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	gs.apply_snapshot_dict(parsed as Dictionary)
	current_action = "select"
	pending_card_unit_def_id = ""
	pending_card_offer_index = -1
	pending_card_is_mutant = false
	reachable.clear()
	gs.emit_signal("changed")

func _sync_ui() -> void:
	if hud and hud.has_method("set_status"):
		var turn_text := "P%d Turn (T%d)" % [gs.active_player + 1, gs.turn_number]
		if net_mode and net_room_code != "":
			turn_text = "%s | Room %s | You %s" % [turn_text, net_room_code, net_player]
		var sel_text := "No selection"
		var info_text := ""
		if gs.selected_squad_id != -1:
			var s = gs.get_squad(gs.selected_squad_id)
			if s != null:
				sel_text = "S%d @ %s" % [s.id, str(s.cell)]
				var unit_id := ""
				var hp := int(s.total_hp_alive()) if s.has_method("total_hp_alive") else 0
				var unit_count := int(s.unit_count_alive()) if s.has_method("unit_count_alive") else int(s.units.size())
				var front = s.front_unit() if s.has_method("front_unit") else null
				if front != null:
					unit_id = str(front.unit_def_id)
				var fresh_text := ""
				if s.has_method("can_act") and not s.can_act(int(gs.turn_number)):
					fresh_text = " | FRESH"
				var terrain_text := ""
				if gs.board != null:
					terrain_text = " " + _terrain_name(int(gs.board.terrain_at(s.cell)))
				var cd_bits: Array[String] = []
				var cdk: Array = s.cooldowns.keys()
				cdk.sort()
				for ck in cdk:
					if int(s.cooldowns.get(ck, 0)) > 0:
						cd_bits.append("%s:%d" % [str(ck), int(s.cooldowns.get(ck, 0))])
				var cd_str := ", ".join(cd_bits) if not cd_bits.is_empty() else "—"
				var lock_text := " | ORGANS LOCKED (field graft OK)" if bool(s.organs_locked) else " | spawn attach open"
				info_text = "%s x%d organs %d | CD %s%s | %s%s" % [unit_id, unit_count, hp, cd_str, fresh_text, terrain_text, lock_text]

				# Squad inspection panel (units + cooldowns).
				if hud.has_method("set_selected_squad_inspect"):
					var units: Array = []
					for u_any in s.units:
						var u = u_any
						if u == null:
							continue
						units.append({
							"unit_def_id": str(u.unit_def_id),
							"hp": int(u.hp),
							"ready_turn": int(u.ready_turn),
						})
					var is_fresh := int(s.fresh_turn) == int(gs.turn_number)
					hud.call(
						"set_selected_squad_inspect",
						units,
						s.cooldowns,
						is_fresh,
						int(gs.turn_number),
						bool(s.organs_locked),
						int(unit_count),
					)
				var graft_hint := _pickup_reachable_hint(int(gs.selected_squad_id))
				if graft_hint != "":
					info_text += " || " + graft_hint

		# Hover info (cell terrain + obstacle).
		if hovered_cell.x != -999 and gs.board != null:
			var h := hovered_cell
			if gs.board.in_bounds(h):
				var h_text := "Hover %s" % _terrain_name(int(gs.board.terrain_at(h)))
				if gs.board.is_blocked(h):
					var hp := int(gs.board.obstacle_hp(h))
					if gs.board.is_destructible(h):
						var pk: String = str(gs.board.obstacle_prop_kind(h))
						if pk != "":
							h_text += " | Prop (%s) HP %d" % [pk, hp]
						else:
							h_text += " | Obstacle HP %d" % hp
					else:
						h_text += " | Obstacle"
				if current_action in ["melee", "ranged"] and gs.selected_squad_id != -1:
					if gs.board.is_destructible(h) and rules.can_attack_obstacle(gs, gs.selected_squad_id, h, current_action):
						var ob_pred: Dictionary = resolver.predict_obstacle_damage(gs, gs.selected_squad_id, h, current_action)
						h_text += " | Prop dmg %d" % int(ob_pred.get("total", 0))
				# Combat preview (hovering a target in melee/ranged mode).
				if _is_squad_target_action(current_action) and gs.selected_squad_id != -1:
					var target = gs.squad_at(h)
					if target != null and _can_target_squad_action(int(gs.selected_squad_id), int(target.id), current_action):
						var breakdown: Dictionary = resolver.predict_attack_damage(gs, int(gs.selected_squad_id), int(target.id), current_action)
						var raw := int(breakdown.get("total", 0))
						var hp_l := int(breakdown.get("hp_loss", raw))
						var base := int(breakdown.get("base", 0))
						var atk_bonus := int(breakdown.get("attacker_bonus", 0))
						var def_red := int(breakdown.get("defender_reduction", 0))
						var pop_e := str(breakdown.get("pop_emojis", ""))
						var left_e := str(breakdown.get("remain_emojis", ""))
						h_text += " | Preview raw %d -> organs %d (b %d %+d -%d)" % [raw, hp_l, base, atk_bonus, def_red]
						if pop_e != "":
							h_text += " pops %s" % pop_e
							if left_e != "":
								h_text += " left %s" % left_e
							else:
								h_text += " (dead)"
				var pickup_line := _pickup_hover_line(h)
				if pickup_line != "":
					h_text += " | " + pickup_line
					if gs.selected_squad_id != -1:
						var reach_pickups: Array[Vector2i] = rules.reachable_field_pickups(gs, int(gs.selected_squad_id))
						if reach_pickups.has(h):
							h_text += " — STEP TO GRAFT"
						elif rules.can_field_attach(gs.get_squad(int(gs.selected_squad_id))):
							h_text += " — out of move range"
				if _is_lock_egress_cell(h):
					h_text += " | LOCK — leave home locks organ attach"
				if info_text == "":
					info_text = h_text
				else:
					info_text += " || " + h_text

		# Snapshot hint (minimal feedback without new UI).
		if info_text == "":
			if net_mode:
				info_text = "Esc=Menu | Net: --net=create OR --net=join:CODE"
			else:
				info_text = "Keys: Esc=Menu, S=Save snapshot, L=Load snapshot"
		else:
			if net_mode:
				info_text += " || Esc=Menu"
			else:
				info_text += " || Keys: Esc=Menu, S=Save, L=Load"

		var counts = gs.cp_owner_counts()
		var cp_text := "CP %d-%d" % [int(counts.get(0, 0)), int(counts.get(1, 0))]
		var winner_text := ""
		var game_over = gs.winner != -1
		if game_over:
			winner_text = _match_over_line(gs)
			if int(gs.winner) != int(_match_over_announced_for):
				_match_over_announced_for = int(gs.winner)
				if hud.has_method("toast"):
					hud.call("toast", winner_text, 3.2)
		else:
			_match_over_announced_for = -2

		hud.call("set_status", turn_text, sel_text, cp_text, winner_text)
		if hud.has_method("set_mode_and_info"):
			var mode_text := "Mode: %s" % current_action.capitalize()
			hud.call("set_mode_and_info", mode_text, info_text)
		if hud.has_method("set_phase_and_prompt"):
			var offer_pending := bool(gs.offer_pending)
			if int(gs.turn_number) == 1 and not offer_pending:
				_mark_opening_tutorial_seen()
			var phase_text := "Phase: Offer" if offer_pending else "Phase: Action"
			var prompt_text := ""
			if game_over:
				prompt_text = winner_text
			elif offer_pending:
				var picks_left := int(gs.offer_picks_remaining)
				var opening_hand := int(gs.offer_hand_size()) >= 5
				if opening_hand:
					var placed := 2 - picks_left
					var gene_label := _organ_label(pending_card_unit_def_id) if pending_card_unit_def_id != "" else ""
					# Leave-lock teaching lives on first-egress toast only (not opening banner).
					if pending_card_unit_def_id != "":
						if current_action == "card_reinforce":
							prompt_text = "Opening %d/2: attach %s (green)" % [placed + 1, gene_label]
						else:
							prompt_text = "Opening %d/2: place %s on a glowing home pad — that becomes your Mutant." % [placed + 1, gene_label]
					else:
						prompt_text = "Pick 2 · place each on a glowing home pad — that becomes your Mutant."
				elif current_action == "card_reinforce":
					prompt_text = "Gene offer: pick 1 — attach to a highlighted Mutant"
				elif current_action == "card_spawn":
					prompt_text = "Gene offer: pick 1 — spawn or attach"
				else:
					prompt_text = "Gene offer: pick 1 of 3 genes (or Skip)"
				_maybe_toast_specialty_offer_tip()
			else:
				var graft_prompt := _pickup_reachable_hint(int(gs.selected_squad_id))
				var all_fresh := _active_squads_all_fresh()
				match current_action:
					"move":
						if graft_prompt != "":
							prompt_text = "Move: cyan cells — blue gear / green egg graft on step"
						else:
							prompt_text = "Action: click a highlighted cell to move"
					"select":
						if all_fresh:
							prompt_text = "Fresh mutants act next turn — press END"
						elif graft_prompt != "":
							prompt_text = "Move onto blue gear or green egg to field-graft"
						elif int(gs.selected_squad_id) >= 0:
							var top_verb := _selected_top_ability_label()
							var stack_line := _selected_stack_emoji_line()
							if top_verb != "":
								prompt_text = "Select: Move or %s" % top_verb
							else:
								prompt_text = "Select: Move or ability"
							if stack_line != "":
								prompt_text = "%s\n%s" % [prompt_text, stack_line]
						else:
							prompt_text = "Action: select a Mutant — then Move or ability"
					"switch_pick":
						prompt_text = "Switch: pick swap target — click caster to cancel"
					_:
						if _is_squad_target_action(current_action):
							prompt_text = "Action: click an enemy Mutant (or obstacle if ranged allows)"
						elif _is_cell_target_action(current_action):
							prompt_text = "Action: click a highlighted board cell"
						else:
							prompt_text = "Select: Move or ability"
			hud.call("set_phase_and_prompt", phase_text, prompt_text)
		if gs.selected_squad_id == -1 and hud.has_method("clear_selected_squad_inspect"):
			hud.call("clear_selected_squad_inspect")

		var offer_pending := bool(gs.offer_pending) and not demo_mode
		var allow_actions: bool = (not game_over) and (not demo_mode)
		if hud.has_method("set_action_bar_visible"):
			hud.call("set_action_bar_visible", allow_actions and (not offer_pending))
		if hud.has_method("set_offer"):
			var playable: Array[String] = []
			if offer_pending and not game_over:
				for c in gs.offer_cards:
					if _offer_card_playable(str(c)):
						playable.append(str(c))
			hud.call(
				"set_offer",
				gs.offer_cards if not demo_mode else [] as Array[String],
				offer_pending and (not game_over),
				pending_card_unit_def_id,
				playable,
				int(gs.offer_picks_remaining),
				gs.offer_mutants if not demo_mode else [] as Array[bool]
			)

		# While offer is pending, block normal actions (but still allow selection/clicking to target card play).
		hud.call("set_action_enabled", "move", allow_actions and (not offer_pending) and gs.selected_squad_id != -1 and rules.squad_has_available_move(gs, gs.selected_squad_id))
		if offer_pending:
			hud.call("set_action_enabled", "move", false)
		hud.call("set_action_enabled", "end_turn", allow_actions and (not offer_pending))
		var no_acts_left: bool = allow_actions and (not offer_pending) and (
			(not rules.active_player_has_available_move_or_action(gs)) or _active_squads_all_fresh()
		)
		if hud.has_method("set_end_turn_highlighted"):
			hud.call("set_end_turn_highlighted", no_acts_left)
		var move_ready: bool = allow_actions and (not offer_pending) and gs.selected_squad_id != -1 and rules.squad_has_available_move(gs, gs.selected_squad_id)
		if hud.has_method("set_move_highlighted"):
			hud.call("set_move_highlighted", move_ready and not no_acts_left)
		if hud.has_method("rebuild_ability_buttons_for_squad"):
			if allow_actions and gs.selected_squad_id != -1 and (not offer_pending):
				var s0 = gs.get_squad(gs.selected_squad_id)
				var can_act0 := true
				if s0 != null and s0.has_method("can_act"):
					can_act0 = s0.can_act(int(gs.turn_number))
				hud.rebuild_ability_buttons_for_squad(s0, s0.cooldowns if s0 != null else {}, can_act0)
			else:
				hud.clear_ability_buttons()
		elif hud.has_method("rebuild_ability_buttons"):
			if allow_actions and gs.selected_squad_id != -1 and (not offer_pending):
				var s1 = gs.get_squad(gs.selected_squad_id)
				var f = s1.front_unit() if s1 != null and s1.has_method("front_unit") else null
				var udef := str(f.unit_def_id) if f != null else ""
				var can_act1 := true
				if s1 != null and s1.has_method("can_act"):
					can_act1 = s1.can_act(int(gs.turn_number))
				hud.rebuild_ability_buttons(udef, s1.cooldowns if s1 != null else {}, can_act1)
			else:
				hud.clear_ability_buttons()
		if hud.has_method("set_ready_abilities_highlighted"):
			var abl_ready: bool = allow_actions and (not offer_pending) and gs.selected_squad_id != -1 and (not no_acts_left)
			if abl_ready:
				var s_abl = gs.get_squad(gs.selected_squad_id)
				abl_ready = s_abl != null and bool(rules.squad_has_available_action(gs, int(gs.selected_squad_id)))
			hud.call("set_ready_abilities_highlighted", abl_ready)
	if board_view and board_view.has_method("set_offer_targeting"):
		var attach_target := ""
		if pending_card_unit_def_id != "" and (current_action == "card_spawn" or current_action == "card_reinforce"):
			attach_target = str(pending_card_unit_def_id)
		board_view.call("set_offer_targeting", attach_target)
	if board_view and board_view.has_method("set_move_prop_dim"):
		board_view.call("set_move_prop_dim", current_action == "move" and int(gs.selected_squad_id) >= 0)
	if board_view and board_view.has_method("sync_from_game_state"):
		board_view.call("sync_from_game_state", gs)

	var cp_counts = gs.cp_owner_counts()
	if (not demo_mode) and MatchSession.mode == MatchSession.Mode.HOTSEAT:
		if _last_active_player >= 0 and int(gs.active_player) != _last_active_player and (not bool(gs.offer_pending)):
			var cp0 := int(cp_counts.get(0, 0))
			var cp1 := int(cp_counts.get(1, 0))
			var cp_changed := _last_pass_cp.x >= 0 and (_last_pass_cp.x != cp0 or _last_pass_cp.y != cp1)
			if (not bool(GameSettings.skip_pass_interstitial)) and cp_changed:
				if hud.has_method("show_pass_interstitial"):
					hud.call("show_pass_interstitial", int(gs.active_player), cp0, cp1)
			_last_pass_cp = Vector2i(cp0, cp1)
	_last_active_player = int(gs.active_player)

	_apply_feedback_diffs()
	_render_highlights()

func _on_front_unit_requested(unit_index: int) -> void:
	if bool(gs.offer_pending):
		_reject_act("Gene offer: actions locked")
		return
	if gs.selected_squad_id == -1:
		_reject_act("Select a Mutant first")
		return
	resolver.set_front_unit(gs, int(gs.selected_squad_id), int(unit_index))

func _on_action_pressed(action_id: String) -> void:
	if demo_mode:
		return
	if _is_menu_open():
		return
	if bool(gs.offer_pending):
		_reject_act("Gene offer: pick a gene or Skip")
		return
	if action_id == "end_turn":
		if net_mode:
			resolver.end_turn(gs)
			var net_et = get_node_or_null("/root/Network")
			if net_et != null:
				net_et.send_intent("end_turn")
		else:
			resolver.end_turn(gs)
		current_action = "select"
		reachable.clear()
		switch_pick_sid = -1
		return
	if action_id == "move":
		if gs.selected_squad_id == -1:
			_reject_act("Select a Mutant first")
			return
		var move_s = gs.get_squad(int(gs.selected_squad_id))
		var move_block: Dictionary = _squad_reject_info(move_s, true)
		if str(move_block.get("reason", "")) != "":
			_reject_act(str(move_block.get("reason", "")), str(move_block.get("tag", "")), Vector2i(-999, -999), int(gs.selected_squad_id))
			return
		if not rules.squad_has_available_move(gs, int(gs.selected_squad_id)):
			_reject_act("NO MOVES — nowhere to step", "BLOCKED", Vector2i(-999, -999), int(gs.selected_squad_id))
			return
		current_action = "move"
		switch_pick_sid = -1
		_lock_popped_cells.clear()
		_lock_pop_cell = Vector2i(-999, -999)
		_refresh_reachable()
		_toast_leave_lock_warning()
		_render_highlights()
		return
	if gs.selected_squad_id == -1:
		_reject_act("Select a Mutant first")
		return
	var act_s = gs.get_squad(int(gs.selected_squad_id))
	var act_block: Dictionary = _squad_reject_info(act_s, false, action_id)
	if str(act_block.get("reason", "")) != "":
		_reject_act(str(act_block.get("reason", "")), str(act_block.get("tag", "")), Vector2i(-999, -999), int(gs.selected_squad_id))
		return
	var kind := _kind_for_selected(action_id)
	match kind:
		"slam":
			# Confirmation stage: first press arms slam + AoE telegraph; second confirms.
			if current_action == "slam":
				_confirm_slam()
			else:
				current_action = "slam"
				switch_pick_sid = -1
				reachable.clear()
				_toast("SLAM — click self or press again to confirm")
				if hud and hud.has_method("set_hover_info"):
					hud.call("set_hover_info", "SLAM — confirm to resolve")
			_render_highlights()
			return
		"delayed_single", "delayed_radius", "delayed_area":
			current_action = action_id
			switch_pick_sid = -1
			_refresh_reachable_for_action(action_id)
		"plant_mine", "plant_big_mine", "plant_snare":
			current_action = action_id
			switch_pick_sid = -1
			_refresh_reachable_for_action(action_id)
		"switch":
			current_action = "switch_pick"
			switch_pick_sid = -1
			_toast("Switch: click your squad, then another friendly squad")
		"run", "jump", "blink", "dash", "pounce":
			current_action = action_id
			_refresh_reachable_for_action(action_id)
		_:
			current_action = action_id
			switch_pick_sid = -1
	_render_highlights()

func _confirm_slam() -> void:
	if gs == null or int(gs.selected_squad_id) < 0:
		_reject_act("Select a Mutant first")
		current_action = "select"
		return
	var slam_s = gs.get_squad(int(gs.selected_squad_id))
	var block: Dictionary = _squad_reject_info(slam_s, false, "slam")
	if str(block.get("reason", "")) != "":
		_reject_act(str(block.get("reason", "")), str(block.get("tag", "")), Vector2i(-999, -999), int(gs.selected_squad_id))
		current_action = "select"
		return
	resolver.use_slam(gs, int(gs.selected_squad_id))
	if slam_s != null:
		_play_combat_juice("slam", slam_s.cell, slam_s.cell, -1, 1.0)
	current_action = "select"
	reachable.clear()
	_render_highlights()

func _on_cell_hovered(cell: Vector2i) -> void:
	# Hover highlight is rendered on top of other highlights.
	hovered_cell = cell
	_render_highlights(cell)
	_maybe_lock_egress_hover(cell)

func _is_lock_egress_cell(cell: Vector2i) -> bool:
	if current_action != "move" or cell.x == -999 or gs == null or int(gs.selected_squad_id) < 0:
		return false
	if not reachable.has(cell):
		return false
	var ms = gs.get_squad(int(gs.selected_squad_id))
	if ms == null or not ms.is_alive() or bool(ms.organs_locked):
		return false
	if not rules.is_spawn_pool_cell(gs, ms.cell, int(ms.owner)):
		return false
	return not rules.is_spawn_pool_cell(gs, cell, int(ms.owner))

func _maybe_lock_egress_hover(cell: Vector2i) -> void:
	if not _is_lock_egress_cell(cell):
		_lock_pop_cell = Vector2i(-999, -999)
		return
	if hud and hud.has_method("set_hover_info"):
		hud.call("set_hover_info", "LOCK — leave home locks organ attach (gear & eggs still graft)")
	# One LOCKED pop per egress cell per move session (hover re-entry used to spam).
	if _lock_popped_cells.has(cell) or cell == _lock_pop_cell:
		return
	_lock_pop_cell = cell
	_lock_popped_cells[cell] = true
	if board_view and board_view.has_method("pop_text"):
		board_view.call("pop_text", cell, "LOCKED", Color(1.0, 0.72, 0.25, 1.0))

func _on_cell_clicked(cell: Vector2i) -> void:
	if demo_mode:
		return
	if _is_menu_open():
		return
	var squad = gs.squad_at(cell)

	# Card targeting modes.
	if current_action == "card_spawn" and pending_card_unit_def_id != "":
		# Allow "add unit to existing squad" even if the mode was set to spawn.
		# This matches the intended UX: pick card, then click target (squad or cell).
		if squad != null:
			var _can_reinf := bool(rules.can_play_card_reinforce(gs, pending_card_unit_def_id, int(squad.id)))
			if _can_reinf:
				resolver.play_card_reinforce(
					gs,
					pending_card_unit_def_id,
					int(squad.id),
					pending_card_is_mutant,
					pending_card_offer_index
				)
				_maybe_toast_soft_ceiling(squad)
				_after_gene_play()
				return

		if not rules.can_play_card_spawn(gs, pending_card_unit_def_id, cell):
			if squad != null:
				if int(squad.owner) != int(gs.active_player):
					_toast("Can't spawn on enemy squad")
				elif not bool(rules.can_play_card_reinforce(gs, pending_card_unit_def_id, int(squad.id))):
					_toast("Can't attach to that Mutant")
				else:
					_toast("Can't spawn there")
			else:
				_toast("Can't spawn there")
			return

		var inv_before_spawn: Dictionary = gs.player_inventory.get(gs.active_player, {})
		var inv_count_before := int(inv_before_spawn.get(pending_card_unit_def_id, 0))
		var played_id := str(pending_card_unit_def_id)
		resolver.play_card_spawn(
			gs,
			pending_card_unit_def_id,
			cell,
			pending_card_is_mutant,
			pending_card_offer_index
		)
		var inv_after_spawn: Dictionary = gs.player_inventory.get(gs.active_player, {})
		var inv_count_after := int(inv_after_spawn.get(played_id, 0))
		if inv_count_after == inv_count_before:
			_toast("Spawn failed")
			return
		_after_gene_play()
		return

	if current_action == "card_reinforce" and pending_card_unit_def_id != "":
		if squad != null:
			if not rules.can_play_card_reinforce(gs, pending_card_unit_def_id, squad.id):
				var why := _offer_card_reinforce_fail_reason(str(pending_card_unit_def_id), squad)
				if why != "":
					_toast(why)
				else:
					_toast("Can't attach to that Mutant")
				return
			var inv_before_rf: Dictionary = gs.player_inventory.get(gs.active_player, {})
			var inv_before_ct := int(inv_before_rf.get(pending_card_unit_def_id, 0))
			var played_id2 := str(pending_card_unit_def_id)
			resolver.play_card_reinforce(
				gs,
				pending_card_unit_def_id,
				squad.id,
				pending_card_is_mutant,
				pending_card_offer_index
			)
			var inv_after_rf: Dictionary = gs.player_inventory.get(gs.active_player, {})
			var inv_after_ct := int(inv_after_rf.get(played_id2, 0))
			if inv_after_ct == inv_before_ct:
				_toast("Attach failed")
			else:
				_maybe_toast_soft_ceiling(squad)
				_after_gene_play()
		else:
			_toast("Attach: click one of your Mutants")
		return

	if current_action == "switch_pick":
		if gs.selected_squad_id == -1:
			_toast("No squad with Switch")
			return
		if squad == null or int(squad.owner) != int(gs.active_player):
			_toast("Click a friendly squad")
			return
		if int(squad.id) == int(gs.selected_squad_id):
			current_action = "select"
			switch_pick_sid = -1
			_toast("Switch cancelled")
			_render_highlights()
			return
		if switch_pick_sid >= 0 and int(squad.id) == int(switch_pick_sid):
			switch_pick_sid = -1
			_toast("Pick cancelled — click first swap target again")
			_render_highlights()
			return
		if switch_pick_sid < 0:
			switch_pick_sid = int(squad.id)
			_toast("Swap ghost: click second squad (Esc / caster cancels)")
			_render_highlights()
			return
		resolver.switch_squads(gs, int(gs.selected_squad_id), int(switch_pick_sid), int(squad.id))
		if net_mode:
			var net_sw = get_node_or_null("/root/Network")
			if net_sw != null:
				net_sw.send_intent(
					"switch",
					{
						"caster_id": int(gs.selected_squad_id),
						"squad_a": int(switch_pick_sid),
						"squad_b": int(squad.id),
					}
				)
		current_action = "select"
		switch_pick_sid = -1
		reachable.clear()
		_render_highlights()
		return

	if current_action in ["powerstrike", "eruption", "airstrike"] and gs.selected_squad_id != -1 and gs.board != null and gs.board.in_bounds(cell):
		var _pe_before: int = gs.pending_effects.size()
		resolver.schedule_delayed_strike(gs, int(gs.selected_squad_id), current_action, cell)
		if net_mode and gs.pending_effects.size() > _pe_before:
			var net_dly = get_node_or_null("/root/Network")
			if net_dly != null:
				var pe: Dictionary = gs.pending_effects[gs.pending_effects.size() - 1]
				net_dly.send_intent("delayed", {"effect": pe.duplicate(true)})
		current_action = "select"
		reachable.clear()
		_render_highlights()
		return
	if current_action in ["mine", "big_mine", "snare"] and gs.selected_squad_id != -1 and gs.board != null and gs.board.in_bounds(cell):
		resolver.plant_hazard(gs, int(gs.selected_squad_id), cell, current_action)
		if net_mode and gs.board != null:
			var hz = gs.board.hazard_at(cell)
			if hz != null:
				var net_pl = get_node_or_null("/root/Network")
				if net_pl != null:
					net_pl.send_intent(
						"plant",
						{
							"hazard": {
								"cell": {"x": int(cell.x), "y": int(cell.y)},
								"kind": str(hz.get("kind", "")),
								"owner": int(hz.get("owner", 0)),
								"damage": int(hz.get("damage", 0)),
								"splash": int(hz.get("splash", 0)),
							}
						}
					)
		current_action = "select"
		reachable.clear()
		_render_highlights()
		return

	if squad != null and rules.can_select_squad(gs, squad.id):
		# Slam confirmation: re-click self to resolve.
		if current_action == "slam" and int(squad.id) == int(gs.selected_squad_id):
			_confirm_slam()
			return
		# Stay in move mode when re-clicking the already selected squad (mis-click / confirmation).
		if current_action == "move" and int(squad.id) == int(gs.selected_squad_id):
			return
		resolver.select_squad(gs, squad.id)
		_auto_enter_move_after_select()
		return
	if squad != null and not rules.can_select_squad(gs, squad.id) and not bool(gs.offer_pending):
		# Only telegraph select rejects in select/move — targeting modes must fall through.
		if current_action in ["select", "move"]:
			var sel_info: Dictionary = _squad_reject_info(squad, false)
			var sel_reason := str(sel_info.get("reason", ""))
			var sel_tag := str(sel_info.get("tag", ""))
			if sel_reason == "" or sel_tag == "":
				sel_reason = "Can't select that Mutant"
				sel_tag = "ENEMY" if int(squad.owner) != int(gs.active_player) else "NO"
			_reject_act(sel_reason, sel_tag, squad.cell, int(squad.id))
			return

	if current_action == "move" and gs.selected_squad_id != -1:
		if net_mode:
			if not rules.can_move_for_net_intent(gs, gs.selected_squad_id, cell):
				var net_info: Dictionary = _move_reject_info(int(gs.selected_squad_id), cell)
				_reject_act(str(net_info.get("reason", "Invalid move")), str(net_info.get("tag", "BLOCKED")), cell, int(gs.selected_squad_id))
				return
			var net = get_node_or_null("/root/Network")
			if net != null:
				net.send_intent("move", {"squad_id": int(gs.selected_squad_id), "to": {"x": int(cell.x), "y": int(cell.y)}})
				current_action = "select"
				reachable.clear()
		else:
			if rules.can_move(gs, gs.selected_squad_id, cell):
				resolver.move_squad(gs, gs.selected_squad_id, cell)
				current_action = "select"
				reachable.clear()
			else:
				var mv_info: Dictionary = _move_reject_info(int(gs.selected_squad_id), cell)
				_reject_act(str(mv_info.get("reason", "Invalid move")), str(mv_info.get("tag", "BLOCKED")), cell, int(gs.selected_squad_id))
		return

	for mv in ["run", "jump", "blink", "dash", "pounce"]:
		if current_action == mv and gs.selected_squad_id != -1:
			var mv_s = gs.get_squad(int(gs.selected_squad_id))
			var from_cell: Vector2i = cell
			if mv_s != null:
				from_cell = mv_s.cell
			var dash_path: Array = []
			if mv == "dash" and pathfinding != null and mv_s != null:
				var dash_ad: Dictionary = UnitDefsScript.action_def_for_squad(mv_s, "dash")
				dash_path = pathfinding.path_pass_through_to(gs, int(gs.selected_squad_id), cell, int(dash_ad.get("steps", 3)))
			match mv:
				"run":
					resolver.use_run(gs, int(gs.selected_squad_id), cell)
				"jump":
					resolver.use_jump(gs, int(gs.selected_squad_id), cell)
				"blink":
					resolver.use_blink(gs, int(gs.selected_squad_id), cell)
				"dash":
					resolver.use_dash(gs, int(gs.selected_squad_id), cell)
				"pounce":
					resolver.use_pounce(gs, int(gs.selected_squad_id), cell)
			if mv in ["dash", "pounce"] and mv_s != null:
				if mv == "dash":
					_play_combat_juice(mv, from_cell, cell, -1, 1.0, dash_path)
				else:
					_play_combat_juice(mv, from_cell, cell, -1)
			if net_mode:
				var net_mv = get_node_or_null("/root/Network")
				if net_mv != null:
					net_mv.send_intent(
						mv,
						{"squad_id": int(gs.selected_squad_id), "to": {"x": int(cell.x), "y": int(cell.y)}}
					)
			current_action = "select"
			reachable.clear()
			return

	if _is_squad_target_action(current_action) and gs.selected_squad_id != -1:
		var target = gs.squad_at(cell)
		if target != null:
			if not _can_target_squad_action(int(gs.selected_squad_id), int(target.id), current_action):
				_reject_act("CAN'T HIT that target", "NO HIT", target.cell, int(gs.selected_squad_id))
				return
			if net_mode:
				var net = get_node_or_null("/root/Network")
				if net != null:
					net.send_intent("attack", {"attacker_id": int(gs.selected_squad_id), "defender_id": int(target.id), "kind": str(current_action)})
					current_action = "select"
			else:
				var atk = gs.get_squad(int(gs.selected_squad_id))
				var from_cell: Vector2i = atk.cell if atk != null else cell
				var act := str(current_action)
				match _kind_for_selected(current_action):
					"railgun":
						resolver.use_railgun(gs, int(gs.selected_squad_id), int(target.id))
					"charge":
						resolver.use_charge(gs, int(gs.selected_squad_id), int(target.id))
					_:
						resolver.attack(gs, gs.selected_squad_id, target.id, current_action)
				if atk != null:
					_play_combat_juice(act, from_cell, target.cell, int(target.id))
				current_action = "select"
			return
		var atk_k := _kind_for_selected(current_action)
		if atk_k in ["melee", "ranged"] and rules.can_attack_obstacle(gs, gs.selected_squad_id, cell, current_action):
			if net_mode:
				var net2 = get_node_or_null("/root/Network")
				if net2 != null:
					net2.send_intent("attack_obstacle", {"attacker_id": int(gs.selected_squad_id), "cell": {"x": int(cell.x), "y": int(cell.y)}, "kind": str(current_action)})
					current_action = "select"
			else:
				var atk2 = gs.get_squad(int(gs.selected_squad_id))
				var act2 := str(current_action)
				var hp_before := int(gs.board.obstacle_hp(cell))
				resolver.attack_obstacle(gs, gs.selected_squad_id, cell, current_action)
				var hp_after := int(gs.board.obstacle_hp(cell))
				if atk2 != null:
					_play_combat_juice(act2, atk2.cell, cell, -1)
				if board_view and board_view.has_method("flash_cells"):
					board_view.call("flash_cells", [cell], Color(1.0, 0.55, 0.2, 0.9), 0.28)
				if board_view and board_view.has_method("pop_text"):
					if hp_after <= 0:
						board_view.call("pop_text", cell, "DESTROYED", Color(1.0, 0.7, 0.3, 1.0))
						_toast("Obstacle destroyed")
					else:
						board_view.call("pop_text", cell, "-%d" % maxi(0, hp_before - hp_after), Color(1.0, 0.75, 0.35, 1.0))
				current_action = "select"
			return
		_reject_act("No valid target there", "NO HIT", cell, int(gs.selected_squad_id))
		return

	# Empty click behavior: back out of modes or clear selection.
	if current_action != "select":
		current_action = "select"
		switch_pick_sid = -1
		reachable.clear()
		_render_highlights()
		return
	resolver.deselect(gs)

func _offer_any_card_reinforce_possible(unit_def_id: String) -> bool:
	if gs == null:
		return false
	var squad_ids: Array = gs.squads.keys()
	squad_ids.sort()
	for sid_any in squad_ids:
		var sid := int(sid_any)
		if rules.can_play_card_reinforce(gs, str(unit_def_id), sid):
			return true
	return false

func _offer_spawn_possible(unit_def_id: String) -> bool:
	if gs == null:
		return false
	if gs.winner != -1:
		return false
	if not bool(gs.offer_pending):
		return false

	var inv: Dictionary = gs.player_inventory.get(gs.active_player, {})
	if int(inv.get(unit_def_id, 0)) <= 0:
		return false

	var cells: Array[Vector2i] = rules.spawn_cells(gs, gs.active_player)
	if cells.is_empty():
		return false

	return true

func _on_offer_card_pressed(unit_def_id: String, offer_index: int) -> void:
	if demo_mode:
		return
	if not bool(gs.offer_pending):
		return
	if str(unit_def_id).strip_edges() == "":
		return
	if not _offer_card_playable(unit_def_id):
		if int(gs.player_inventory.get(gs.active_player, {}).get(unit_def_id, 0)) <= 0:
			_toast("Not in your gene pool")
		elif rules.spawn_cells(gs, gs.active_player).is_empty():
			_toast("No empty home pads")
		else:
			_toast("Can't place that gene now")
		return
	pending_card_unit_def_id = unit_def_id
	pending_card_offer_index = int(offer_index)
	pending_card_is_mutant = false
	if offer_index >= 0 and offer_index < gs.offer_mutants.size():
		pending_card_is_mutant = bool(gs.offer_mutants[offer_index])

	var spawn_possible := _offer_spawn_possible(unit_def_id)
	var reinforce_any := _offer_any_card_reinforce_possible(unit_def_id)

	var selected_on_ra := false
	var reinforce_selected := false
	if gs.selected_squad_id != -1:
		var sel = gs.get_squad(gs.selected_squad_id)
		if sel != null and gs.board != null:
			selected_on_ra = bool(rules.is_spawn_pool_cell(gs, sel.cell, int(sel.owner)))
			reinforce_selected = bool(rules.can_play_card_reinforce(gs, str(unit_def_id), int(gs.selected_squad_id)))

	# Disambiguate when both spawn + attach are possible:
	# default to spawn, unless the player has explicitly selected a Mutant that can attach this gene.
	var use_reinforce := false
	if reinforce_any and not spawn_possible:
		use_reinforce = true
	elif reinforce_any and spawn_possible:
		use_reinforce = bool(reinforce_selected) and selected_on_ra

	current_action = "card_reinforce" if use_reinforce else "card_spawn"
	if use_reinforce and not spawn_possible and reinforce_any:
		_toast("No empty Spawn Pool cells — attach only")
	reachable.clear()
	gs.emit_signal("changed")

func _on_offer_skip_pressed() -> void:
	if demo_mode:
		return
	if not bool(gs.offer_pending):
		return
	_mark_opening_tutorial_seen()
	gs.clear_offer_phase()
	current_action = "select"
	pending_card_unit_def_id = ""
	pending_card_offer_index = -1
	pending_card_is_mutant = false
	reachable.clear()
	gs.emit_signal("changed")

func _refresh_reachable() -> void:
	reachable.clear()
	if gs.selected_squad_id == -1:
		return
	var sel = gs.get_squad(gs.selected_squad_id)
	if sel == null:
		return
	var max_r: int = rules.move_range_for_squad(gs, sel)
	if net_mode:
		var budget: int = int(gs.board.size.x) + int(gs.board.size.y) + 4
		reachable = pathfinding.reachable_cells(gs, gs.selected_squad_id, maxi(budget, max_r), true, true)
	else:
		reachable = pathfinding.reachable_cells(gs, gs.selected_squad_id, max_r)

func _auto_enter_move_after_select() -> void:
	# Prefer Move as the default mode when the selected squad can still move.
	switch_pick_sid = -1
	if bool(gs.offer_pending) or int(gs.winner) != -1:
		current_action = "select"
		reachable.clear()
		_render_highlights()
		return
	if gs.selected_squad_id != -1 and rules.squad_has_available_move(gs, int(gs.selected_squad_id)):
		current_action = "move"
		_lock_popped_cells.clear()
		_lock_pop_cell = Vector2i(-999, -999)
		_refresh_reachable()
		_toast_leave_lock_warning()
	else:
		current_action = "select"
		reachable.clear()
	_render_highlights()

func _toast_leave_lock_warning() -> void:
	# One tip while unlocked in spawn — not every hover / re-select spam.
	if bool(GameSettings.seen_spawn_lock_tip):
		return
	if gs == null or int(gs.selected_squad_id) < 0:
		return
	var s = gs.get_squad(int(gs.selected_squad_id))
	if s == null or not s.is_alive() or bool(s.organs_locked):
		return
	if not rules.is_spawn_pool_cell(gs, s.cell, int(s.owner)):
		return
	_toast("Leaving home locks organ attach — gear & eggs still graft.", 2.6)

func _render_highlights(hover_cell: Vector2i = Vector2i(-999, -999)) -> void:
	if board_view and board_view.has_method("clear_highlights"):
		board_view.call("clear_highlights")
	if _atmosphere != null and _atmosphere.has_method("set_glitter_visible"):
		_atmosphere.call("set_glitter_visible", current_action != "move")

	# Units that still have a move/action this turn (underlays; selection/reach paint over).
	var game_over := int(gs.winner) != -1
	var offer_on := bool(gs.offer_pending)
	var show_avail_turn := (not game_over) and (not offer_on) and not _opening_tutorial_active() and current_action != "move"
	if show_avail_turn:
		var only_selected: bool = gs.selected_squad_id != -1 and current_action in ["select", "move"]
		var avail_ids: Array = gs.squads.keys()
		avail_ids.sort()
		for sid_any in avail_ids:
			var sid := int(sid_any)
			var sq = gs.get_squad(sid)
			if sq == null or not sq.is_alive():
				continue
			if int(sq.owner) != int(gs.active_player):
				continue
			if only_selected and sid != int(gs.selected_squad_id):
				continue
			if rules.squad_has_available_move(gs, sid) or rules.squad_has_available_action(gs, sid):
				var alpha := 0.55 if sid == int(gs.selected_squad_id) else 0.10
				if board_view and board_view.has_method("highlight_cell"):
					board_view.call("highlight_cell", sq.cell, Color(0.72, 0.54, 0.16, alpha))

	# Switch targets: highlight friendly non-caster (and first pick brighter).
	if current_action == "switch_pick" and gs.selected_squad_id != -1:
		for sid_any in gs.squads.keys():
			var sw = gs.get_squad(int(sid_any))
			if sw == null or not sw.is_alive():
				continue
			if int(sw.owner) != int(gs.active_player):
				continue
			if int(sw.id) == int(gs.selected_squad_id):
				continue
			var sw_col := Color(0.95, 0.82, 0.35, 0.85) if int(sw.id) == int(switch_pick_sid) else Color(0.75, 0.65, 1.0, 0.55)
			if board_view and board_view.has_method("highlight_cell"):
				board_view.call("highlight_cell", sw.cell, sw_col)

	# Offer targeting highlights.
	if current_action == "card_spawn" and pending_card_unit_def_id != "":
		var cells: Array[Vector2i] = rules.spawn_cells(gs, gs.active_player)
		var opening_spawn := int(gs.turn_number) <= 2 and bool(gs.offer_pending)
		var spawn_col := Color(0.42, 1.0, 0.78, 0.92) if opening_spawn else Color(0.75, 0.65, 1.0)
		for c in cells:
			if board_view and board_view.has_method("highlight_cell"):
				board_view.call("highlight_cell", c, spawn_col)

	# Attach-eligible mutants whenever a gene is pending (spawn or reinforce mode).
	if pending_card_unit_def_id != "" and (current_action == "card_spawn" or current_action == "card_reinforce"):
		var squad_ids: Array = gs.squads.keys()
		squad_ids.sort()
		for sid in squad_ids:
			var s = gs.get_squad(int(sid))
			if s == null or not s.is_alive():
				continue
			if s.owner != gs.active_player:
				continue
			if not rules.can_play_card_reinforce(gs, pending_card_unit_def_id, s.id):
				continue
			if board_view and board_view.has_method("highlight_cell"):
				board_view.call("highlight_cell", s.cell, Color(0.45, 1.0, 0.55))

	# Movement / ability landing reachability (cyan — distinct from CP gold zones).
	# Ability hover: keep soft reach only when not previewing impact on a legal cell.
	# Leave-lock: brighter amber + higher alpha on egress (outside spawn) = LOCK preview.
	if current_action == "move":
		var lock_preview := false
		var leave_owner := -1
		if gs.selected_squad_id != -1:
			var ms = gs.get_squad(int(gs.selected_squad_id))
			if ms != null and ms.is_alive() and not bool(ms.organs_locked) and rules.is_spawn_pool_cell(gs, ms.cell, int(ms.owner)):
				lock_preview = true
				leave_owner = int(ms.owner)
		var lock_cells: Array = []
		for cell in reachable.keys():
			if lock_preview and not rules.is_spawn_pool_cell(gs, cell, leave_owner):
				lock_cells.append(cell)
			elif board_view and board_view.has_method("highlight_cell"):
				board_view.call("highlight_cell", cell, AbilityTelegraphScript.COLOR_MOVE)
		if not lock_cells.is_empty() and board_view and board_view.has_method("highlight_cells"):
			board_view.call("highlight_cells", lock_cells, Color(1.0, 0.58, 0.08, 1.0), 0.58)
	elif _is_cell_target_action(current_action):
		var is_trap := current_action in ["mine", "big_mine", "snare"]
		var reach_col := AbilityTelegraphScript.COLOR_TRAP if is_trap else AbilityTelegraphScript.COLOR_MOVE
		var suppress := hover_cell.x != -999 and (reachable.is_empty() or reachable.has(hover_cell))
		if not suppress:
			for cell in reachable.keys():
				if board_view and board_view.has_method("highlight_cell"):
					board_view.call("highlight_cell", cell, reach_col)

	# Field pickups (gear/eggs) reachable this turn by selected mutant.
	if (not bool(gs.offer_pending)) and gs.selected_squad_id != -1 and current_action in ["move", "select"]:
		var pickup_s = gs.get_squad(gs.selected_squad_id)
		if pickup_s != null and rules.can_field_attach(pickup_s):
			var pickup_cells: Array[Vector2i] = rules.reachable_field_pickups(gs, gs.selected_squad_id)
			var gear_cells: Array = []
			var egg_cells: Array = []
			var curse_cells: Array = []
			for pc in pickup_cells:
				var def_id: String = rules.pickup_unit_def_id(gs, pc)
				if def_id == "":
					continue
				if rules.pickup_is_egg(gs, pc):
					if UnitDefsScript.is_curse_organ(def_id):
						curse_cells.append(pc)
					else:
						egg_cells.append(pc)
				else:
					gear_cells.append(pc)
			if board_view and board_view.has_method("highlight_cells"):
				# Stronger destination rings than idle move cyan — graft is the prize.
				if not gear_cells.is_empty():
					board_view.call("highlight_cells", gear_cells, Color(0.45, 0.85, 1.0), 0.62)
				if not egg_cells.is_empty():
					board_view.call("highlight_cells", egg_cells, Color(0.45, 1.0, 0.58), 0.62)
				if not curse_cells.is_empty():
					board_view.call("highlight_cells", curse_cells, Color(1.0, 0.32, 0.28), 0.68)
			# Hovering a reachable pickup: crisp GRAFT destination preview.
			if hover_cell.x != -999 and pickup_cells.has(hover_cell) and board_view and board_view.has_method("highlight_cell"):
				var hover_col := Color(0.55, 0.95, 1.0)
				if rules.pickup_is_egg(gs, hover_cell):
					var hid: String = rules.pickup_unit_def_id(gs, hover_cell)
					hover_col = Color(1.0, 0.4, 0.35) if UnitDefsScript.is_curse_organ(hid) else Color(0.55, 1.0, 0.7)
				board_view.call("highlight_cell", hover_cell, hover_col)
				if hud and hud.has_method("set_hover_info"):
					var pl := _pickup_hover_line(hover_cell)
					hud.call("set_hover_info", "GRAFT — %s" % pl if pl != "" else "GRAFT — step here")

	# Destructible props / obstacles in attack range (melee/ranged).
	if current_action in ["melee", "ranged"] and gs.selected_squad_id != -1 and gs.board != null:
		var attacker = gs.get_squad(gs.selected_squad_id)
		if attacker != null:
			var ad: Dictionary = UnitDefsScript.action_def_for_squad(attacker, current_action)
			var r := int(ad.get("range", 1))
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if abs(dx) + abs(dy) > r:
						continue
					var c := Vector2i(attacker.cell.x + dx, attacker.cell.y + dy)
					if not rules.can_attack_obstacle(gs, gs.selected_squad_id, c, current_action):
						continue
					if board_view and board_view.has_method("highlight_cell"):
						var pk: String = str(gs.board.obstacle_prop_kind(c))
						var col := Color(1.0, 0.55, 0.18) if pk != "" else Color(0.95, 0.45, 0.25)
						board_view.call("highlight_cell", c, col)
					if hover_cell == c and hud and hud.has_method("set_hover_info"):
						var hp_left := int(gs.board.obstacle_hp(c))
						hud.call("set_hover_info", "BREAK — obstacle %d HP" % hp_left)

	# Slam confirmation: show AoE impact around caster (must confirm before resolve).
	if current_action == "slam" and gs.selected_squad_id != -1:
		var slam_caster = gs.get_squad(gs.selected_squad_id)
		if slam_caster != null:
			var slam_ad: Dictionary = UnitDefsScript.action_def_for_squad(slam_caster, "slam")
			var slam_prev: Dictionary = AbilityTelegraphScript.preview(gs, "slam", slam_caster.cell, slam_caster.cell, slam_ad)
			var slam_impact: Array = slam_prev.get("impact_cells", [])
			if slam_impact.is_empty():
				slam_impact = slam_prev.get("reach_cells", [])
			if board_view and board_view.has_method("highlight_cells") and not slam_impact.is_empty():
				board_view.call("highlight_cells", slam_impact, AbilityTelegraphScript.COLOR_IMPACT, 0.55)
			if board_view and board_view.has_method("highlight_cell"):
				board_view.call("highlight_cell", slam_caster.cell, Color(1.0, 0.85, 0.35))
			if hud and hud.has_method("set_hover_info"):
				hud.call("set_hover_info", "SLAM — click self or press again to confirm")

	# Squad-target actions: soft reach wash + legal enemies (no full magenta disk).
	if _is_squad_target_action(current_action) and gs.selected_squad_id != -1:
		var attacker_id := int(gs.selected_squad_id)
		var a = gs.get_squad(attacker_id)
		var ad: Dictionary = {}
		if a != null:
			ad = UnitDefsScript.action_def_for_squad(a, current_action)
		if a != null and gs.board != null:
			var soft: Dictionary = AbilityTelegraphScript.preview(gs, current_action, a.cell, a.cell, ad)
			var reach_cells: Array = soft.get("reach_cells", [])
			if board_view and board_view.has_method("highlight_cells") and not reach_cells.is_empty():
				board_view.call("highlight_cells", reach_cells, AbilityTelegraphScript.COLOR_REACH, 0.18)
		var squad_ids2: Array = gs.squads.keys()
		squad_ids2.sort()
		for sid in squad_ids2:
			var defender_id := int(sid)
			if defender_id == attacker_id:
				continue
			if _can_target_squad_action(attacker_id, defender_id, current_action):
				var d = gs.get_squad(defender_id)
				if d != null and board_view and board_view.has_method("highlight_cell"):
					board_view.call("highlight_cell", d.cell, AbilityTelegraphScript.COLOR_ENEMY)

	# Selected squad.
	if gs.selected_squad_id != -1:
		var s = gs.get_squad(gs.selected_squad_id)
		if s != null and board_view and board_view.has_method("highlight_cell"):
			board_view.call("highlight_cell", s.cell, Color(0.2, 1.0, 0.4))

	# Hover impact preview (AoE / line / path / trap splash).
	if hover_cell.x != -999 and gs.selected_squad_id != -1:
		var caster = gs.get_squad(gs.selected_squad_id)
		if caster != null and (_is_squad_target_action(current_action) or _is_cell_target_action(current_action)):
			var ad2: Dictionary = UnitDefsScript.action_def_for_squad(caster, current_action)
			var show_impact := false
			if _is_squad_target_action(current_action):
				var tgt = gs.squad_at(hover_cell)
				if tgt != null and _can_target_squad_action(int(gs.selected_squad_id), int(tgt.id), current_action):
					show_impact = true
				elif current_action == "railgun" and (hover_cell.x == caster.cell.x or hover_cell.y == caster.cell.y):
					# Soft line preview along hovered ray even without a unit.
					show_impact = true
			elif _is_cell_target_action(current_action):
				if reachable.has(hover_cell) or current_action in ["powerstrike", "eruption", "airstrike", "mine", "big_mine", "snare"]:
					if reachable.is_empty() or reachable.has(hover_cell):
						show_impact = true
			if show_impact:
				var prev: Dictionary = AbilityTelegraphScript.preview(gs, current_action, caster.cell, hover_cell, ad2)
				var impact: Array = prev.get("impact_cells", [])
				# Prefer real dash path when available.
				if current_action == "dash" and pathfinding != null:
					var ad_dash: Dictionary = ad2
					var ms := int(ad_dash.get("steps", 3))
					var path: Array = pathfinding.path_pass_through_to(gs, int(gs.selected_squad_id), hover_cell, ms)
					if not path.is_empty():
						impact = path
						prev["is_line"] = true
				if not impact.is_empty() and board_view:
					if bool(prev.get("is_line", false)) and board_view.has_method("highlight_line"):
						board_view.call("highlight_line", impact, AbilityTelegraphScript.COLOR_IMPACT)
					elif board_view.has_method("highlight_cells"):
						var impact_col := AbilityTelegraphScript.COLOR_TRAP if bool(prev.get("is_trap", false)) else AbilityTelegraphScript.COLOR_IMPACT
						board_view.call("highlight_cells", impact, impact_col, 0.38)
				if _is_squad_target_action(current_action) and board_view and board_view.has_method("highlight_cell"):
					var t2 = gs.squad_at(hover_cell)
					if t2 != null and _can_target_squad_action(int(gs.selected_squad_id), int(t2.id), current_action):
						board_view.call("highlight_cell", hover_cell, Color(1.0, 0.55, 0.15))

	# Hover highlight on top.
	if hover_cell.x != -999 and board_view and board_view.has_method("highlight_cell"):
		board_view.call("highlight_cell", hover_cell, Color(1.0, 1.0, 1.0))

func _kind_for_selected(action_id: String) -> String:
	if gs == null or gs.selected_squad_id == -1:
		return ""
	var s = gs.get_squad(gs.selected_squad_id)
	if s == null:
		return ""
	return UnitDefsScript.action_kind(UnitDefsScript.action_def_for_squad(s, action_id))

func _is_squad_target_action(action_id: String) -> bool:
	var k := _kind_for_selected(action_id)
	return k in ["melee", "ranged", "railgun", "charge"]

func _is_cell_target_action(action_id: String) -> bool:
	if action_id in ["powerstrike", "eruption", "airstrike", "mine", "big_mine", "snare"]:
		return true
	var k := _kind_for_selected(action_id)
	return k in ["run", "jump", "blink", "dash", "pounce"]

func _can_target_squad_action(attacker_id: int, defender_id: int, action_id: String) -> bool:
	return rules.can_attack(gs, attacker_id, defender_id, action_id)

func _refresh_reachable_for_action(action_id: String) -> void:
	reachable.clear()
	if gs == null or gs.selected_squad_id == -1 or gs.board == null:
		return
	var s = gs.get_squad(gs.selected_squad_id)
	if s == null:
		return
	var ad: Dictionary = UnitDefsScript.action_def_for_squad(s, action_id)
	if ad.is_empty():
		return
	match action_id:
		"run":
			reachable = pathfinding.reachable_cells(gs, gs.selected_squad_id, int(ad.get("steps", 2)))
		"jump":
			var jst := int(ad.get("steps", 3))
			for y in range(int(gs.board.size.y)):
				for x in range(int(gs.board.size.x)):
					var c := Vector2i(x, y)
					if pathfinding.jump_landing_legal(gs, gs.selected_squad_id, c, jst):
						reachable[c] = 1
		"pounce":
			var jr := int(ad.get("jump_range", 3))
			for y in range(int(gs.board.size.y)):
				for x in range(int(gs.board.size.x)):
					var c2 := Vector2i(x, y)
					if pathfinding.jump_landing_legal(gs, gs.selected_squad_id, c2, jr):
						reachable[c2] = 1
		"blink":
			var br := int(ad.get("range", 4))
			for c3 in pathfinding.chebyshev_disk(s.cell, br, gs):
				if maxi(abs(c3.x - s.cell.x), abs(c3.y - s.cell.y)) < 1:
					continue
				if gs.board.in_bounds(c3) and not gs.board.is_blocked(c3) and gs.squad_at(c3) == null:
					reachable[c3] = 1
		"dash":
			var ms := int(ad.get("steps", 3))
			for y in range(int(gs.board.size.y)):
				for x in range(int(gs.board.size.x)):
					var c4 := Vector2i(x, y)
					if not pathfinding.path_pass_through_to(gs, gs.selected_squad_id, c4, ms).is_empty():
						reachable[c4] = 1
		"powerstrike", "eruption", "airstrike":
			var rng := int(ad.get("range", 3))
			for y in range(int(gs.board.size.y)):
				for x in range(int(gs.board.size.x)):
					var c5 := Vector2i(x, y)
					var dist: int = abs(c5.x - s.cell.x) + abs(c5.y - s.cell.y)
					if dist <= rng:
						reachable[c5] = 1
		"mine", "big_mine", "snare":
			var pr := int(ad.get("range", 2))
			for y in range(int(gs.board.size.y)):
				for x in range(int(gs.board.size.x)):
					var c6 := Vector2i(x, y)
					var dist2: int = maxi(absi(c6.x - s.cell.x), absi(c6.y - s.cell.y))
					if dist2 <= pr:
						reachable[c6] = 1
		_:
			pass

func _toast(msg: String, duration_s: float = 1.6) -> void:
	if hud and hud.has_method("toast"):
		hud.call("toast", msg, duration_s)

func _reject_act(reason: String, tag: String = "", cell: Vector2i = Vector2i(-999, -999), squad_id: int = -1) -> void:
	## Unified reject telegraph: toast + chip + board pop/flash + mutant warn pulse.
	_toast(reason)
	if hud and hud.has_method("set_hover_info"):
		hud.call("set_hover_info", reason)
	var sid := int(squad_id)
	var c := cell
	if sid < 0 and gs != null and int(gs.selected_squad_id) >= 0:
		sid = int(gs.selected_squad_id)
	if c.x == -999 and sid >= 0 and gs != null:
		var s = gs.get_squad(sid)
		if s != null:
			c = s.cell
	var warn := Color(1.0, 0.45, 0.35, 1.0)
	if c.x != -999:
		if tag != "" and board_view and board_view.has_method("pop_text"):
			board_view.call("pop_text", c, tag, warn)
		if board_view and board_view.has_method("flash_cells"):
			board_view.call("flash_cells", [c], Color(1.0, 0.4, 0.3, 0.85), 0.22)
	if sid >= 0 and board_view and board_view.has_method("play_reject_pulse"):
		board_view.call("play_reject_pulse", sid)

func _squad_reject_info(s, for_move: bool = false, action_id: String = "") -> Dictionary:
	## Returns {reason, tag} when the squad cannot take the requested act; empty reason if OK.
	if s == null or not s.is_alive():
		return {"reason": "No Mutant there", "tag": ""}
	if int(s.owner) != int(gs.active_player):
		return {"reason": "ENEMY — not your Mutant", "tag": "ENEMY"}
	if int(s.fresh_turn) == int(gs.turn_number):
		return {"reason": "FRESH — acts next turn", "tag": "FRESH"}
	if not s.can_act(int(gs.turn_number)):
		return {"reason": "SPENT — already acted", "tag": "SPENT"}
	if for_move:
		if int(s.moved_turn) == int(gs.turn_number):
			return {"reason": "ALREADY MOVED this turn", "tag": "SPENT"}
		if int(gs.turn_number) < int(s.snared_no_move_until_turn):
			return {"reason": "SNARED — can't move", "tag": "SNARED"}
	if action_id != "" and int(s.cooldowns.get(action_id, 0)) > 0:
		return {"reason": "ON COOLDOWN — %s" % action_id, "tag": "CD"}
	return {"reason": "", "tag": ""}

func _move_reject_info(sid: int, to_cell: Vector2i) -> Dictionary:
	var s = gs.get_squad(sid) if gs != null else null
	var block: Dictionary = _squad_reject_info(s, true)
	if str(block.get("reason", "")) != "":
		return block
	if gs == null or gs.board == null:
		return {"reason": "Invalid move", "tag": "BLOCKED"}
	if not gs.board.in_bounds(to_cell):
		return {"reason": "OUT OF BOUNDS", "tag": "BLOCKED"}
	if gs.board.is_blocked(to_cell):
		return {"reason": "BLOCKED — terrain", "tag": "BLOCKED"}
	if gs.squad_at(to_cell) != null:
		return {"reason": "BLOCKED — occupied", "tag": "BLOCKED"}
	if not reachable.has(to_cell):
		return {"reason": "OUT OF RANGE", "tag": "RANGE"}
	return {"reason": "Invalid move", "tag": "BLOCKED"}

func _snapshot_feedback_state() -> void:
	_prev_squad_hp.clear()
	_prev_organs_locked.clear()
	for sid in gs.squads.keys():
		var id := int(sid)
		var s = gs.get_squad(id)
		if s == null or not s.is_alive():
			continue
		_prev_squad_hp[id] = int(s.total_hp_alive()) if s.has_method("total_hp_alive") else 0
		_prev_organs_locked[id] = bool(s.organs_locked)

	_prev_pickups.clear()
	if gs.board != null:
		for cell_any in gs.board.gear.keys():
			var c: Vector2i = cell_any
			var gear = gs.board.gear_at(c)
			if gear != null:
				_prev_pickups[c] = {"kind": "gear", "def_id": str(gear.get("unit_def_id", ""))}
		for cell_any in gs.board.eggs.keys():
			var c2: Vector2i = cell_any
			var egg = gs.board.egg_at(c2)
			if egg != null:
				_prev_pickups[c2] = {"kind": "egg", "def_id": str(egg.get("unit_def_id", ""))}

	_prev_cp_owner.clear()
	if gs.board != null:
		for cp in gs.board.control_points:
			_prev_cp_owner[cp.cell] = int(cp.owner)

	_prev_obstacle_hp.clear()
	_prev_obstacle_kind.clear()
	if gs.board != null:
		for cell_any in gs.board.obstacles.keys():
			var c: Vector2i = cell_any
			if not gs.board.is_blocked(c):
				continue
			_prev_obstacle_hp[c] = int(gs.board.obstacle_hp(c))
			var pk: String = str(gs.board.obstacle_prop_kind(c))
			if pk != "":
				_prev_obstacle_kind[c] = pk

func _apply_feedback_diffs() -> void:
	# First sync after load: establish baseline.
	if _prev_squad_hp.is_empty() and _prev_cp_owner.is_empty() and _prev_obstacle_hp.is_empty():
		_snapshot_feedback_state()
		return

	# Hit flash + damage popups.
	for sid in gs.squads.keys():
		var id := int(sid)
		var s = gs.get_squad(id)
		if s == null or not s.is_alive():
			continue
		var new_hp := int(s.total_hp_alive()) if s.has_method("total_hp_alive") else 0
		var old_hp := int(_prev_squad_hp.get(id, new_hp))
		if new_hp < old_hp:
			if board_view and board_view.has_method("play_hit_flash"):
				board_view.call("play_hit_flash", id)
			if board_view and board_view.has_method("pop_text"):
				board_view.call("pop_text", s.cell, "-%d" % (old_hp - new_hp), Color(1.0, 0.85, 0.35, 1.0))
			if gs.board != null and not _prev_pickups.has(s.cell) and gs.board.gear.has(s.cell):
				_toast("Organ dropped — step on gear to reclaim")
		var was_locked := bool(_prev_organs_locked.get(id, bool(s.organs_locked)))
		if bool(s.organs_locked) and not was_locked:
			_toast("M-%02d left home — organ attach locked (gear & eggs still graft)" % id)
			if not bool(GameSettings.seen_spawn_lock_tip):
				GameSettings.seen_spawn_lock_tip = true
				GameSettings.save_settings()
				_toast("Tip: gene attach closed — field gear & eggs still work")
			if board_view and board_view.has_method("pop_text"):
				board_view.call("pop_text", s.cell, "LOCKED", Color(0.95, 0.72, 0.35, 1.0))

	# Field pickup graft feedback — telegraph payoff: burst + sparks + GRAFT pop.
	for cell_any in _prev_pickups.keys():
		var cell: Vector2i = cell_any
		if gs.board != null and (gs.board.gear.has(cell) or gs.board.eggs.has(cell)):
			continue
		var meta: Dictionary = _prev_pickups.get(cell, {})
		var def_id := str(meta.get("def_id", ""))
		if def_id == "":
			continue
		var sq = gs.squad_at(cell)
		if sq == null:
			continue
		var label := _organ_label(def_id)
		var emoji := UnitDefsScript.emoji_for(def_id)
		var kind := str(meta.get("kind", "gear"))
		var pop_col := Color(0.58, 0.92, 0.62, 1.0)
		var burst_col := Color(0.55, 1.0, 0.7, 1.0)
		var toast_msg := "Grafted %s %s" % [emoji, label]
		if kind == "egg":
			if UnitDefsScript.is_curse_organ(def_id):
				pop_col = Color(0.95, 0.52, 0.42, 1.0)
				burst_col = Color(1.0, 0.4, 0.32, 1.0)
				toast_msg = "Cursed graft %s %s" % [emoji, label]
			else:
				toast_msg = "Egg graft %s %s" % [emoji, label]
		else:
			pop_col = Color(0.52, 0.88, 1.0, 1.0)
			burst_col = Color(0.5, 0.88, 1.0, 1.0)
			toast_msg = "Gear graft %s %s" % [emoji, label]
		_toast(toast_msg, 2.2)
		_maybe_toast_soft_ceiling(sq)
		if board_view and board_view.has_method("pop_text"):
			board_view.call("pop_text", cell, "GRAFT %s" % emoji, pop_col)
		if board_view and board_view.has_method("flash_cells"):
			board_view.call("flash_cells", [cell], burst_col, 0.42)
		if board_view != null and _vfx_root != null:
			var pos: Vector3 = board_view.call("cell_world_center", cell)
			pos.y += 0.35
			AbilityBurstVfxScript.play(_vfx_root, pos, 0.85, burst_col, 1.05)
			HitSparkVfxScript.play(_vfx_root, pos + Vector3(0, 0.2, 0), 1.15, pop_col)
		if board_view != null and board_view.has_method("play_graft_celebrate"):
			board_view.call("play_graft_celebrate", int(sq.id))
		var rig := get_node_or_null("CameraRig")
		if rig != null and rig.has_method("focus_demo_action") and not demo_mode:
			var focus: Vector3 = board_view.call("cell_world_center", cell) if board_view else Vector3.ZERO
			rig.call("focus_demo_action", focus, 0.38)

	# CP capture notifications.
	if gs.board != null:
		for cp in gs.board.control_points:
			var cell: Vector2i = cp.cell
			var new_owner := int(cp.owner)
			var old_owner := int(_prev_cp_owner.get(cell, new_owner))
			if new_owner != old_owner and new_owner != -1:
				_toast("CP captured by P%d" % (new_owner + 1))
				if board_view and board_view.has_method("pop_text"):
					board_view.call("pop_text", cell, "CAPTURE", Color(0.85, 1.0, 0.45, 1.0))

	# Obstacle destroyed pop.
	var prev_cells: Array = _prev_obstacle_hp.keys()
	for cell_any in prev_cells:
		var c: Vector2i = cell_any
		var was_hp := int(_prev_obstacle_hp.get(c, 0))
		var is_blocked := bool(gs.board.is_blocked(c)) if gs.board != null else false
		if was_hp > 0 and not is_blocked:
			var prop_kind := str(_prev_obstacle_kind.get(c, ""))
			var label := "Prop destroyed" if prop_kind != "" else "Obstacle destroyed"
			_toast(label)
			if board_view and board_view.has_method("pop_text"):
				board_view.call("pop_text", c, "DESTROYED", Color(1.0, 0.65, 0.25, 1.0))
			if board_view != null:
				var pos: Vector3 = board_view.call("cell_world_center", c)
				var debris_host = board_view.call("debris_root")
				if prop_kind != "":
					ImpactDebrisScript.spawn_prop_rubble(
						debris_host,
						pos,
						prop_kind,
						float(board_view.call("board_ground_y")),
						board_view.call("board_center_xz"),
						float(board_view.call("board_half_extent")),
					)
				else:
					ImpactDebrisScript.spawn_burst(
						debris_host,
						pos,
						5,
						float(board_view.call("board_ground_y")),
						board_view.call("board_center_xz"),
						float(board_view.call("board_half_extent")),
						6.0
					)
				if _vfx_root != null:
					AbilityBurstVfxScript.play(_vfx_root, pos, 0.9, Color(1.0, 0.7, 0.3, 1.0), 0.9)

	_maybe_toast_cp_zone_tip()
	_snapshot_feedback_state()
