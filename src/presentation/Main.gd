extends Node3D

const GameStateScript = preload("res://src/sim/GameState.gd")
const ResolverScript = preload("res://src/sim/Resolver.gd")
const RulesScript = preload("res://src/sim/Rules.gd")
const PathfindingScript = preload("res://src/sim/Pathfinding.gd")
const BoardStateScript = preload("res://src/sim/BoardState.gd")
const PatchApplierScript = preload("res://src/net/PatchApplier.gd")
const UnitDefsScript = preload("res://src/sim/UnitDefs.gd")

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
var switch_pick_sid: int = -1
var hovered_cell: Vector2i = Vector2i(-999, -999)
const SNAPSHOT_PATH := "user://snapshot.json"

var _prev_squad_hp := {} # int -> int
var _prev_cp_owner := {} # Vector2i -> int
var _prev_obstacle_hp := {} # Vector2i -> int

var net_mode: bool = false
var net_room_code: String = ""
var net_player: String = ""
var net_state: Dictionary = {}

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

func _offer_card_reinforce_fail_reason(unit_def_id: String, squad) -> String:
	# Mirrors `Rules.can_play_card_reinforce`, but returns a player-facing reason string.
	if gs.winner != -1:
		return "Game over"
	if not bool(gs.offer_pending):
		return "No offer active"
	if squad == null:
		return "Click your squad"
	var inv: Dictionary = gs.player_inventory.get(gs.active_player, {})
	if int(inv.get(str(unit_def_id), 0)) <= 0:
		return "No copies of that unit in inventory"
	if int(squad.owner) != int(gs.active_player):
		return "Can't reinforce enemy squads"
	if gs.board == null:
		return "Board missing"
	if not bool(gs.board.is_reinforcement_area(squad.cell)):
		return "Reinforce only in deployment / CP reinforcement zones"

	var alive := int(squad.unit_count_alive()) if squad.has_method("unit_count_alive") else int(squad.units.size())
	if alive < 3:
		return "" # should be reinforceable (capacity)

	var u = squad.front_unit() if squad.has_method("front_unit") else null
	if u == null:
		return "No front unit"
	var max_hp := int(UnitDefsScript.DEFS.get(str(u.unit_def_id), {}).get("max_hp", 10))
	if int(u.hp) >= max_hp:
		return "Squad full and front is max HP"
	return "Can't reinforce that squad"

func _ready() -> void:
	gs = GameStateScript.new()
	resolver = ResolverScript.new()
	rules = RulesScript.new()
	pathfinding = PathfindingScript.new()
	add_child(gs)
	gs.setup(GameStateScript.DEFAULT_BOARD_SIZE)

	_try_start_network_from_args()
	if not net_mode:
		_seed_test_squads()

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

	_sync_ui()

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

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return
		if k.keycode == KEY_ESCAPE:
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

func _on_menu_quit() -> void:
	get_tree().quit()

func _restart_match() -> void:
	current_action = "select"
	reachable.clear()
	pending_card_unit_def_id = ""
	switch_pick_sid = -1
	hovered_cell = Vector2i(-999, -999)
	_prev_squad_hp.clear()
	_prev_cp_owner.clear()
	_prev_obstacle_hp.clear()
	gs.setup(GameStateScript.DEFAULT_BOARD_SIZE)
	_seed_test_squads()
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
	reachable.clear()
	gs.emit_signal("changed")

func _seed_test_squads() -> void:
	# Keep most small-squad slots free for offer/spawn testing (cap is 3 small + 1 large per player).
	# Two pre-placed small squads per player consumes 2/3 slots immediately and feels like "no space".
	gs.add_squad(0, Vector2i(2, 2), "soldier", 10)
	gs.add_squad(1, Vector2i(11, 11), "soldier", 10)

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
				info_text = "%s x%d HP %d | CD %s%s | %s" % [unit_id, unit_count, hp, cd_str, fresh_text, terrain_text]

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
					hud.call("set_selected_squad_inspect", units, s.cooldowns, is_fresh, int(gs.turn_number))

		# Hover info (cell terrain + obstacle).
		if hovered_cell.x != -999 and gs.board != null:
			var h := hovered_cell
			if gs.board.in_bounds(h):
				var h_text := "Hover %s" % _terrain_name(int(gs.board.terrain_at(h)))
				if gs.board.is_blocked(h):
					var hp := int(gs.board.obstacle_hp(h))
					if gs.board.is_destructible(h):
						h_text += " | Obstacle HP %d" % hp
					else:
						h_text += " | Obstacle"
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
						h_text += " | Preview raw %d -> HP %d (b %d %+d -%d)" % [raw, hp_l, base, atk_bonus, def_red]
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
			winner_text = "Winner: P%d" % (gs.winner + 1)

		hud.call("set_status", turn_text, sel_text, cp_text, winner_text)
		if hud.has_method("set_mode_and_info"):
			var mode_text := "Mode: %s" % current_action.capitalize()
			hud.call("set_mode_and_info", mode_text, info_text)
		if hud.has_method("set_phase_and_prompt"):
			var offer_pending := bool(gs.offer_pending)
			var phase_text := "Phase: Offer" if offer_pending else "Phase: Action"
			var prompt_text := ""
			if game_over:
				prompt_text = "Game over"
			elif offer_pending:
				if current_action == "card_reinforce":
					prompt_text = "Offer: reinforce squads in your home rows or on CP markers (yellow rings)"
				elif current_action == "card_spawn":
					prompt_text = "Offer: spawn into your home rows (purple). Army slots: 3 small squads + 1 large."
				else:
					prompt_text = "Offer: pick a card (then target) or Skip"
			else:
				match current_action:
					"move":
						prompt_text = "Action: click a highlighted cell to move"
					"switch_pick":
						prompt_text = "Action: click one of your squads, then another friendly squad to swap"
					_:
						if _is_squad_target_action(current_action):
							prompt_text = "Action: click an enemy squad (or obstacle if ranged allows)"
						elif _is_cell_target_action(current_action):
							prompt_text = "Action: click a highlighted board cell"
						else:
							prompt_text = "Action: select a squad and use Move / abilities"
			hud.call("set_phase_and_prompt", phase_text, prompt_text)
		if gs.selected_squad_id == -1 and hud.has_method("clear_selected_squad_inspect"):
			hud.call("clear_selected_squad_inspect")

		var offer_pending := bool(gs.offer_pending)
		if hud.has_method("set_offer"):
			hud.call("set_offer", gs.offer_cards, offer_pending and (not game_over))

		# While offer is pending, block normal actions (but still allow selection/clicking to target card play).
		hud.call("set_action_enabled", "move", (not game_over) and (not offer_pending) and gs.selected_squad_id != -1 and rules.squad_has_available_move(gs, gs.selected_squad_id))
		hud.call("set_action_enabled", "end_turn", (not game_over) and (not offer_pending))
		if hud.has_method("set_end_turn_highlighted"):
			var highlight_end: bool = (not game_over) and (not offer_pending) and (not rules.active_player_has_available_move_or_action(gs))
			hud.call("set_end_turn_highlighted", highlight_end)
		if hud.has_method("rebuild_ability_buttons"):
			if gs.selected_squad_id != -1 and (not game_over) and (not offer_pending):
				var s0 = gs.get_squad(gs.selected_squad_id)
				var f = s0.front_unit() if s0 != null and s0.has_method("front_unit") else null
				var udef := str(f.unit_def_id) if f != null else ""
				var can_act0 := true
				if s0 != null and s0.has_method("can_act"):
					can_act0 = s0.can_act(int(gs.turn_number))
				hud.rebuild_ability_buttons(udef, s0.cooldowns if s0 != null else {}, can_act0)
			else:
				hud.clear_ability_buttons()

	if board_view and board_view.has_method("sync_from_game_state"):
		board_view.call("sync_from_game_state", gs)

	_apply_feedback_diffs()
	_render_highlights()

func _on_front_unit_requested(unit_index: int) -> void:
	if bool(gs.offer_pending):
		_toast("Offer phase: actions are locked")
		return
	if gs.selected_squad_id == -1:
		_toast("Select a squad first")
		return
	resolver.set_front_unit(gs, int(gs.selected_squad_id), int(unit_index))

func _on_action_pressed(action_id: String) -> void:
	if _is_menu_open():
		return
	if bool(gs.offer_pending):
		_toast("Offer phase: pick a card or Skip")
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
		current_action = "move"
		switch_pick_sid = -1
		_refresh_reachable()
		_render_highlights()
		return
	if gs.selected_squad_id == -1:
		_toast("Select a squad first")
		return
	var kind := _kind_for_selected(action_id)
	match kind:
		"slam":
			resolver.use_slam(gs, int(gs.selected_squad_id))
			current_action = "select"
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

func _on_cell_hovered(cell: Vector2i) -> void:
	# Hover highlight is rendered on top of other highlights.
	hovered_cell = cell
	_render_highlights(cell)

func _on_cell_clicked(cell: Vector2i) -> void:
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
				resolver.play_card_reinforce(gs, pending_card_unit_def_id, int(squad.id))
				if not bool(gs.offer_pending):
					current_action = "select"
					pending_card_unit_def_id = ""
					reachable.clear()
				return

		if not rules.can_play_card_spawn(gs, pending_card_unit_def_id, cell):
			if squad != null:
				if int(squad.owner) != int(gs.active_player):
					_toast("Can't spawn on enemy squad")
				elif not bool(rules.can_play_card_reinforce(gs, pending_card_unit_def_id, int(squad.id))):
					_toast("Can't reinforce that squad")
				else:
					_toast("Can't spawn there")
			else:
				_toast("Can't spawn there")
			return

		var inv_before_spawn: Dictionary = gs.player_inventory.get(gs.active_player, {})
		var inv_count_before := int(inv_before_spawn.get(pending_card_unit_def_id, 0))
		resolver.play_card_spawn(gs, pending_card_unit_def_id, cell)
		var inv_after_spawn: Dictionary = gs.player_inventory.get(gs.active_player, {})
		var inv_count_after := int(inv_after_spawn.get(pending_card_unit_def_id, 0))
		if inv_count_after == inv_count_before:
			_toast("Spawn failed")
		if not bool(gs.offer_pending):
			current_action = "select"
			pending_card_unit_def_id = ""
			reachable.clear()
		return

	if current_action == "card_reinforce" and pending_card_unit_def_id != "":
		if squad != null:
			if not rules.can_play_card_reinforce(gs, pending_card_unit_def_id, squad.id):
				var why := _offer_card_reinforce_fail_reason(str(pending_card_unit_def_id), squad)
				if why != "":
					_toast(why)
				else:
					_toast("Can't reinforce that squad")
				return
			var inv_before_rf: Dictionary = gs.player_inventory.get(gs.active_player, {})
			var inv_before_ct := int(inv_before_rf.get(pending_card_unit_def_id, 0))
			resolver.play_card_reinforce(gs, pending_card_unit_def_id, squad.id)
			var inv_after_rf: Dictionary = gs.player_inventory.get(gs.active_player, {})
			var inv_after_ct := int(inv_after_rf.get(pending_card_unit_def_id, 0))
			if inv_after_ct == inv_before_ct:
				_toast("Reinforce failed")
			if not bool(gs.offer_pending):
				current_action = "select"
				pending_card_unit_def_id = ""
				reachable.clear()
		else:
			_toast("Reinforce: click one of your squads")
		return

	if current_action == "switch_pick":
		if gs.selected_squad_id == -1:
			_toast("No squad with Switch")
			return
		if squad == null or int(squad.owner) != int(gs.active_player):
			_toast("Click a friendly squad")
			return
		if int(squad.id) == int(gs.selected_squad_id):
			_toast("Pick a squad other than the caster")
			return
		if switch_pick_sid < 0:
			switch_pick_sid = int(squad.id)
			_toast("Click the second squad to swap with")
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
		# Stay in move mode when re-clicking the already selected squad (mis-click / confirmation).
		if current_action == "move" and int(squad.id) == int(gs.selected_squad_id):
			return
		resolver.select_squad(gs, squad.id)
		_auto_enter_move_after_select()
		return
	if squad != null and not rules.can_select_squad(gs, squad.id) and not bool(gs.offer_pending):
		_toast("Can't select that squad")

	if current_action == "move" and gs.selected_squad_id != -1:
		if net_mode:
			if not rules.can_move_for_net_intent(gs, gs.selected_squad_id, cell):
				_toast("Invalid move")
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
				_toast("Invalid move")
		return

	for mv in ["run", "jump", "blink", "dash", "pounce"]:
		if current_action == mv and gs.selected_squad_id != -1:
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
				_toast("Can't attack that target")
				return
			if net_mode:
				var net = get_node_or_null("/root/Network")
				if net != null:
					net.send_intent("attack", {"attacker_id": int(gs.selected_squad_id), "defender_id": int(target.id), "kind": str(current_action)})
					current_action = "select"
			else:
				match _kind_for_selected(current_action):
					"railgun":
						resolver.use_railgun(gs, int(gs.selected_squad_id), int(target.id))
					"charge":
						resolver.use_charge(gs, int(gs.selected_squad_id), int(target.id))
					_:
						resolver.attack(gs, gs.selected_squad_id, target.id, current_action)
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
				resolver.attack_obstacle(gs, gs.selected_squad_id, cell, current_action)
				current_action = "select"
			return
		_toast("No valid target there")
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

func _on_offer_card_pressed(unit_def_id: String) -> void:
	if not bool(gs.offer_pending):
		return
	pending_card_unit_def_id = unit_def_id

	var spawn_possible := _offer_spawn_possible(unit_def_id)
	var reinforce_any := _offer_any_card_reinforce_possible(unit_def_id)

	var selected_on_ra := false
	var reinforce_selected := false
	if gs.selected_squad_id != -1:
		var sel = gs.get_squad(gs.selected_squad_id)
		if sel != null and gs.board != null:
			selected_on_ra = bool(gs.board.is_reinforcement_area(sel.cell))
			reinforce_selected = bool(rules.can_play_card_reinforce(gs, str(unit_def_id), int(gs.selected_squad_id)))

	# Disambiguate when both spawn + reinforce are possible:
	# default to spawn, unless the player has explicitly selected a squad that can reinforce this card.
	var use_reinforce := false
	if reinforce_any and not spawn_possible:
		use_reinforce = true
	elif reinforce_any and spawn_possible:
		use_reinforce = bool(reinforce_selected)

	current_action = "card_reinforce" if use_reinforce else "card_spawn"
	if use_reinforce and not spawn_possible and reinforce_any:
		_toast("No empty spawn cells — reinforce only")
	reachable.clear()
	gs.emit_signal("changed")

func _on_offer_skip_pressed() -> void:
	if not bool(gs.offer_pending):
		return
	gs.clear_offer_phase()
	current_action = "select"
	pending_card_unit_def_id = ""
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
		_refresh_reachable()
	else:
		current_action = "select"
		reachable.clear()
	_render_highlights()

func _render_highlights(hover_cell: Vector2i = Vector2i(-999, -999)) -> void:
	if board_view and board_view.has_method("clear_highlights"):
		board_view.call("clear_highlights")

	# Offer targeting highlights.
	if current_action == "card_spawn" and pending_card_unit_def_id != "":
		var cells: Array[Vector2i] = rules.spawn_cells(gs, gs.active_player)
		for c in cells:
			if board_view and board_view.has_method("highlight_cell"):
				board_view.call("highlight_cell", c, Color(0.75, 0.65, 1.0))

	if current_action == "card_reinforce" and pending_card_unit_def_id != "":
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
				board_view.call("highlight_cell", s.cell, Color(1.0, 0.85, 0.25))

	# Movement / ability reachability (shared cyan tint).
	if current_action == "move" or _is_cell_target_action(current_action):
		for cell in reachable.keys():
			if board_view and board_view.has_method("highlight_cell"):
				board_view.call("highlight_cell", cell, Color(0.0, 0.83, 1.0))

	# Attack overlays + enemy highlights.
	if _is_squad_target_action(current_action) and gs.selected_squad_id != -1:
		var attacker_id := int(gs.selected_squad_id)
		var a = gs.get_squad(attacker_id)
		var ad: Dictionary = {}
		if a != null:
			var fu = a.front_unit()
			if fu != null:
				ad = UnitDefsScript.action_def(str(fu.unit_def_id), current_action)
		var r := int(ad.get("range", 3))
		if a != null and gs.board != null:
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					var dist: int = abs(int(dx)) + abs(int(dy))
					if dist <= r:
						var c := Vector2i(a.cell.x + dx, a.cell.y + dy)
						if gs.board.in_bounds(c) and board_view and board_view.has_method("highlight_cell"):
							board_view.call("highlight_cell", c, Color(0.85, 0.25, 0.85))
		var squad_ids: Array = gs.squads.keys()
		squad_ids.sort()
		for sid in squad_ids:
			var defender_id := int(sid)
			if defender_id == attacker_id:
				continue
			if _can_target_squad_action(attacker_id, defender_id, current_action):
				var d = gs.get_squad(defender_id)
				if d != null and board_view and board_view.has_method("highlight_cell"):
					board_view.call("highlight_cell", d.cell, Color(1.0, 0.25, 0.25))

	# Selected squad.
	if gs.selected_squad_id != -1:
		var s = gs.get_squad(gs.selected_squad_id)
		if s != null and board_view and board_view.has_method("highlight_cell"):
			board_view.call("highlight_cell", s.cell, Color(0.2, 1.0, 0.4))

	if _is_squad_target_action(current_action) and gs.selected_squad_id != -1:
		if hover_cell.x != -999:
			var target = gs.squad_at(hover_cell)
			if target != null:
				var attacker_id := int(gs.selected_squad_id)
				if _can_target_squad_action(attacker_id, int(target.id), current_action):
					if board_view and board_view.has_method("highlight_cell"):
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
	var u = s.front_unit()
	if u == null:
		return ""
	return UnitDefsScript.action_kind(UnitDefsScript.action_def(str(u.unit_def_id), action_id))

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
	var u = s.front_unit()
	if u == null:
		return
	var ad: Dictionary = UnitDefsScript.action_def(str(u.unit_def_id), action_id)
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
					var dist2: int = abs(c6.x - s.cell.x) + abs(c6.y - s.cell.y)
					if dist2 <= pr:
						reachable[c6] = 1
		_:
			pass

func _toast(msg: String) -> void:
	if hud and hud.has_method("toast"):
		hud.call("toast", msg)

func _snapshot_feedback_state() -> void:
	_prev_squad_hp.clear()
	for sid in gs.squads.keys():
		var id := int(sid)
		var s = gs.get_squad(id)
		if s == null or not s.is_alive():
			continue
		_prev_squad_hp[id] = int(s.total_hp_alive()) if s.has_method("total_hp_alive") else 0

	_prev_cp_owner.clear()
	if gs.board != null:
		for cp in gs.board.control_points:
			_prev_cp_owner[cp.cell] = int(cp.owner)

	_prev_obstacle_hp.clear()
	if gs.board != null:
		for cell_any in gs.board.obstacles.keys():
			var c: Vector2i = cell_any
			if not gs.board.is_blocked(c):
				continue
			_prev_obstacle_hp[c] = int(gs.board.obstacle_hp(c))

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
			_toast("Obstacle destroyed")
			if board_view and board_view.has_method("pop_text"):
				board_view.call("pop_text", c, "DESTROYED", Color(1.0, 0.65, 0.25, 1.0))

	_snapshot_feedback_state()
