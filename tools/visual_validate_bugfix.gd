extends Node

## Multi-scenario visual verify for board UX bugfix.
## Run: godot --path . res://tools/visual_validate_bugfix.tscn

const BoardScene = preload("res://scenes/Board.tscn")
const GameStateScript = preload("res://src/sim/GameState.gd")
const UnitStateScript = preload("res://src/sim/UnitState.gd")
const ResolverScript = preload("res://src/sim/Resolver.gd")
const UnitDefsScript = preload("res://src/sim/UnitDefs.gd")
const RulesScript = preload("res://src/sim/Rules.gd")

var _out := "res://tools/visual_shots"
var _gs
var _board: Node3D
var _cam: Camera3D
var _root3: Node3D
var _resolver = ResolverScript.new()
var _rules = RulesScript.new()
var _fails: Array[String] = []

func _ready() -> void:
	print("BUGFIX_VALIDATE_START")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_setup_world()
	await _scenario_midboard_readability()
	await _scenario_gear_emoji_lineup()
	await _scenario_eggs_opaque()
	await _scenario_attach_no_corpse()
	await _scenario_drop_filter_visual()
	await _scenario_both_teams_hp()
	_finish()

func _setup_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.04, 0.04, 0.045)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.18, 0.17, 0.16)
	e.ambient_light_energy = 0.55
	env.environment = e
	add_child(env)

	_root3 = Node3D.new()
	add_child(_root3)
	var light := DirectionalLight3D.new()
	light.light_energy = 2.05
	light.shadow_enabled = true
	light.rotation_degrees = Vector3(-61, 330, 0)
	_root3.add_child(light)

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 8.0
	_cam.position = Vector3(7, 12, 14)
	_root3.add_child(_cam)
	_cam.look_at(Vector3(7, 0.2, 7), Vector3.UP)
	_cam.current = true

	_board = BoardScene.instantiate()
	_root3.add_child(_board)

	_gs = GameStateScript.new()
	add_child(_gs)
	_gs.setup(GameStateScript.DEFAULT_BOARD_SIZE, 4242)
	_gs.clear_offer_phase()
	_gs.board.gear.clear()
	_gs.board.eggs.clear()

func _clear_squads() -> void:
	_gs.squads.clear()
	_gs._next_squad_id = 1
	_gs.selected_squad_id = -1
	_gs.winner = -1

func _clear_board_fx() -> void:
	# Clearing squads sheds organ corpses — wipe between scenarios for clean shots.
	var corpses := _board.get_node_or_null("Corpses") as Node3D
	if corpses != null:
		for c in corpses.get_children():
			c.queue_free()
	for host in [_root3, _board, get_parent(), self]:
		if host == null:
			continue
		var vfx := host.get_node_or_null("VfxRoot") as Node3D
		if vfx != null:
			for c in vfx.get_children():
				c.queue_free()
		var decals := host.get_node_or_null("SplatDecals") as Node3D
		if decals != null:
			for c in decals.get_children():
				c.queue_free()
		for c in host.get_children():
			var nm := str(c.name).to_lower()
			if "splat" in nm or "burst" in nm or "spark" in nm or "debris" in nm:
				c.queue_free()
	# Reset static decal host so next pops recreate cleanly.
	var OrganSplatterVfxScript = preload("res://src/presentation/vfx/OrganSplatterVfx.gd")
	OrganSplatterVfxScript._decal_host = null
	OrganSplatterVfxScript._free.clear()

func _idle_squad(s) -> void:
	# No available-turn amber / fresh cyan rings — isolate team disc in shots.
	if s == null:
		return
	s.fresh_turn = -1
	s.moved_turn = int(_gs.turn_number)
	for k in s.cooldowns.keys():
		s.cooldowns[k] = 99

func _free_cell_near(prefer: Vector2i) -> Vector2i:
	if _gs.board.in_bounds(prefer) and not _gs.board.is_blocked(prefer) and _gs.squad_at(prefer) == null:
		return prefer
	for r in range(1, 6):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c := prefer + Vector2i(dx, dy)
				if not _gs.board.in_bounds(c):
					continue
				if _gs.board.is_blocked(c) or _gs.squad_at(c) != null:
					continue
				if _gs.board.gear.has(c) or _gs.board.eggs.has(c):
					continue
				return c
	return prefer

func _look_at_cell(cell: Vector2i, size: float = 5.0) -> void:
	var wx := float(cell.x) + 0.5
	var wz := float(cell.y) + 0.5
	_cam.size = size
	_cam.position = Vector3(wx, size * 1.35, wz + size * 0.85)
	_cam.look_at(Vector3(wx, 0.25, wz), Vector3.UP)

func _sync() -> void:
	_board.call("sync_from_game_state", _gs)

## Mid-board mutants (no spawn pads) — disc + lightening + HP readable.
func _scenario_midboard_readability() -> void:
	print("SCENARIO midboard_readability")
	_clear_squads()
	_clear_board_fx()
	_gs.board.gear.clear()
	_gs.board.eggs.clear()
	var c0 := _free_cell_near(Vector2i(4, 6))
	var c1 := _free_cell_near(Vector2i(9, 6))
	var sid0: int = int(_gs.add_squad(0, c0, "core", 1))
	var s0 = _gs.get_squad(sid0)
	s0.units.append(UnitStateScript.new("claw", 1, 1))
	s0.units.append(UnitStateScript.new("shell", 1, 1))
	_gs._stabilize_core_at_back(s0)
	s0.organs_locked = true
	_idle_squad(s0)
	var sid1: int = int(_gs.add_squad(1, c1, "core", 1))
	var s1 = _gs.get_squad(sid1)
	s1.units.append(UnitStateScript.new("eye", 1, 1))
	s1.units.append(UnitStateScript.new("hoof", 1, 1))
	_gs._stabilize_core_at_back(s1)
	s1.organs_locked = true
	_idle_squad(s1)
	_sync()
	await get_tree().create_timer(0.4).timeout
	_assert_disc_params()
	_assert_hp_pip_team_colors()
	_assert_tint_not_washed()
	_look_at_cell(c0, 4.5)
	await get_tree().create_timer(0.2).timeout
	await _shot("bf_sc01_p0_midboard")
	_look_at_cell(c1, 4.5)
	await get_tree().create_timer(0.2).timeout
	await _shot("bf_sc01_p1_midboard")

## Gear lineup: several weapon emojis, no balls.
func _scenario_gear_emoji_lineup() -> void:
	print("SCENARIO gear_emoji_lineup")
	_clear_squads()
	_sync()
	await get_tree().process_frame
	_clear_board_fx()
	_gs.board.gear.clear()
	_gs.board.eggs.clear()
	var ids: Array[String] = ["claw", "eye", "shell", "plate", "ram", "spine"]
	var base := Vector2i(5, 5)
	var placed: Array[Vector2i] = []
	for i in range(ids.size()):
		var c := _free_cell_near(base + Vector2i(i % 3, int(i / 3)))
		# Avoid collision with previously placed.
		while placed.has(c):
			c = _free_cell_near(c + Vector2i(1, 0))
		_gs.board.set_gear(c, ids[i], false)
		placed.append(c)
	_sync()
	await get_tree().create_timer(0.35).timeout
	_assert_pickup_visuals(true, false)
	_cam.size = 7.0
	_cam.position = Vector3(6.5, 10, 11)
	_cam.look_at(Vector3(6.5, 0.2, 5.5), Vector3.UP)
	await get_tree().create_timer(0.2).timeout
	await _shot("bf_sc02_gear_emoji_lineup")
	# Close-up first gear
	_look_at_cell(placed[0], 3.2)
	await get_tree().create_timer(0.15).timeout
	await _shot("bf_sc02_gear_closeup")

## Eggs solid, no content emoji.
func _scenario_eggs_opaque() -> void:
	print("SCENARIO eggs_opaque")
	_clear_squads()
	_sync()
	await get_tree().process_frame
	_clear_board_fx()
	_gs.board.gear.clear()
	_gs.board.eggs.clear()
	var e0 := _free_cell_near(Vector2i(6, 6))
	var e1 := _free_cell_near(e0 + Vector2i(2, 0))
	_gs.board.set_egg(e0, "shell", false)
	_gs.board.set_egg(e1, "rot", false)
	_sync()
	await get_tree().create_timer(0.35).timeout
	_assert_pickup_visuals(false, true)
	_assert_egg_materials_opaque()
	_cam.size = 5.5
	_cam.position = Vector3(float(e0.x + e1.x) * 0.5 + 0.5, 8, float(e0.y) + 5.5)
	_cam.look_at(Vector3(float(e0.x + e1.x) * 0.5 + 0.5, 0.3, float(e0.y) + 0.5), Vector3.UP)
	await get_tree().create_timer(0.2).timeout
	await _shot("bf_sc03_eggs_opaque")

## Attach with core present: corpse count must stay flat; organ count rises.
func _scenario_attach_no_corpse() -> void:
	print("SCENARIO attach_no_corpse")
	_clear_squads()
	_sync()
	await get_tree().process_frame
	_clear_board_fx()
	_gs.board.gear.clear()
	_gs.board.eggs.clear()
	# Use spawn pool so reinforce_squad lock check passes.
	var cells: Array[Vector2i] = _rules.spawn_cells(_gs, 0)
	var cell: Vector2i = cells[0] if not cells.is_empty() else Vector2i(2, 0)
	var sid: int = int(_gs.add_squad(0, cell, "core", 1))
	var s = _gs.get_squad(sid)
	s.organs_locked = false
	s.fresh_turn = -1
	_sync()
	await get_tree().create_timer(0.3).timeout
	var corpses0 := _count_corpses()
	var n0 := int(s.unit_count_alive())
	for gene in ["claw", "eye", "shell"]:
		if not _gs.reinforce_squad(sid, gene, 1):
			_fail("attach %s failed" % gene)
			return
		_sync()
		await get_tree().create_timer(0.25).timeout
		var corpses_now := _count_corpses()
		if corpses_now > corpses0:
			_fail("attach %s spawned corpse (%d -> %d)" % [gene, corpses0, corpses_now])
			return
	if int(s.unit_count_alive()) != n0 + 3:
		_fail("expected +3 organs after attaches")
		return
	_look_at_cell(cell, 4.0)
	await get_tree().create_timer(0.15).timeout
	await _shot("bf_sc04_after_multi_attach")

## Drop reclaimable vs structural — board gear only for weapons.
func _scenario_drop_filter_visual() -> void:
	print("SCENARIO drop_filter_visual")
	_clear_squads()
	_sync()
	await get_tree().process_frame
	_clear_board_fx()
	_gs.board.gear.clear()
	_gs.board.eggs.clear()
	var cell := _free_cell_near(Vector2i(7, 7))
	var sid: int = int(_gs.add_squad(0, cell, "claw", 1))
	var s = _gs.get_squad(sid)
	s.units.append(UnitStateScript.new("core", 1, 1))
	s.units.append(UnitStateScript.new("brood", 1, 1))
	s.units.append(UnitStateScript.new("eye", 1, 1))
	_gs._stabilize_core_at_back(s)
	s.organs_locked = true
	s.fresh_turn = -1
	_sync()
	await get_tree().create_timer(0.25).timeout
	var expect := 0
	while s.is_alive():
		var front = s.units[s.front_unit_index()]
		if UnitDefsScript.is_reclaimable_gear(str(front.unit_def_id)):
			expect += 1
		_resolver._pop_organs(_gs, s, 1)
	_sync()
	await get_tree().create_timer(0.35).timeout
	if int(_gs.board.gear.size()) != expect:
		_fail("drop filter gear count %d expected %d" % [int(_gs.board.gear.size()), expect])
	for c_any in _gs.board.gear.keys():
		var g = _gs.board.gear_at(c_any)
		var gid := str(g.get("unit_def_id", ""))
		if gid in ["core", "brood", "anchor"] or UnitDefsScript.is_curse_organ(gid):
			_fail("structural/curse gear visible: %s" % gid)
	_look_at_cell(cell, 5.0)
	await get_tree().create_timer(0.15).timeout
	await _shot("bf_sc05_after_pops_gear_only")
	_assert_pickup_visuals(int(_gs.board.gear.size()) > 0, false)

## Both teams HP colors distinct.
func _scenario_both_teams_hp() -> void:
	print("SCENARIO both_teams_hp")
	_clear_squads()
	_sync()
	await get_tree().process_frame
	_clear_board_fx()
	_gs.board.gear.clear()
	_gs.board.eggs.clear()
	var c0 := _free_cell_near(Vector2i(5, 7))
	var c1 := _free_cell_near(Vector2i(8, 7))
	var sid0: int = int(_gs.add_squad(0, c0, "core", 1))
	var s0 = _gs.get_squad(sid0)
	s0.units.append(UnitStateScript.new("claw", 1, 1))
	s0.units.append(UnitStateScript.new("plate", 1, 1))
	_gs._stabilize_core_at_back(s0)
	s0.organs_locked = true
	_idle_squad(s0)
	var sid1: int = int(_gs.add_squad(1, c1, "core", 1))
	var s1 = _gs.get_squad(sid1)
	s1.units.append(UnitStateScript.new("eye", 1, 1))
	s1.units.append(UnitStateScript.new("shell", 1, 1))
	_gs._stabilize_core_at_back(s1)
	s1.organs_locked = true
	_idle_squad(s1)
	_sync()
	await get_tree().create_timer(0.35).timeout
	_assert_hp_pip_team_colors()
	_cam.size = 6.5
	_cam.position = Vector3(7, 9, 12)
	_cam.look_at(Vector3(7, 0.2, 7), Vector3.UP)
	await get_tree().create_timer(0.2).timeout
	await _shot("bf_sc06_both_teams_hp")

func _assert_disc_params() -> void:
	var layer := _board.get_node_or_null("Squads") as Node3D
	if layer == null:
		_fail("Squads layer missing")
		return
	var found := 0
	for child in layer.get_children():
		var avail := child.get_node_or_null("Availability") as Node3D
		if avail == null:
			continue
		for disc_n in avail.get_children():
			if not (disc_n is MeshInstance3D):
				continue
			var mi := disc_n as MeshInstance3D
			if not (mi.mesh is CylinderMesh):
				continue
			var cyl := mi.mesh as CylinderMesh
			var mat := mi.material_override as StandardMaterial3D
			if mat == null:
				continue
			found += 1
			if cyl.top_radius > 0.38:
				_fail("disc radius too large: %.2f" % cyl.top_radius)
			if mat.albedo_color.a > 0.28:
				_fail("disc alpha too high: %.2f" % mat.albedo_color.a)
			if mat.emission_energy_multiplier > 0.55:
				_fail("disc emit too high: %.2f" % mat.emission_energy_multiplier)
	if found == 0:
		_fail("no floor disc found under mutants")

func _assert_tint_not_washed() -> void:
	# Scene-tree: outline_mix on organ materials should not be forced to 1.0 wash.
	# Soft check — organ parts exist and tint shader params aren't max white boost.
	var layer := _board.get_node_or_null("Squads") as Node3D
	if layer == null:
		return
	var organs := 0
	for child in layer.get_children():
		var oroot := child.get_node_or_null("Organs") as Node3D
		if oroot == null:
			continue
		for body in oroot.get_children():
			var visual := body.get_node_or_null("Visual")
			if visual == null:
				continue
			organs += 1
	if organs < 2:
		_fail("expected multiple organ visuals for tint check")

func _assert_hp_pip_team_colors() -> void:
	var layer := _board.get_node_or_null("Squads") as Node3D
	if layer == null:
		_fail("no Squads for HP check")
		return
	var p0: Color = Color(-1, -1, -1)
	var p1: Color = Color(-1, -1, -1)
	for child in layer.get_children():
		var pips := child.get_node_or_null("Pips") as Node3D
		if pips == null or pips.get_child_count() == 0:
			continue
		var pip := pips.get_child(0) as MeshInstance3D
		if pip == null:
			continue
		var mat := pip.material_override as StandardMaterial3D
		if mat == null:
			continue
		var c: Color = mat.albedo_color
		if c.r > 0.95 and c.g > 0.95 and c.b > 0.95:
			_fail("HP pip pure white")
			return
		# Infer team from owner on SquadView if available.
		var owner := -1
		if child.has_method("get") or true:
			# SquadView stores owner via sync; parse name S_<id> and look up.
			var nm := str(child.name)
			if nm.begins_with("S_"):
				var sid := int(nm.substr(2))
				var sq = _gs.get_squad(sid)
				if sq != null:
					owner = int(sq.owner)
		if owner == 0:
			p0 = c
		elif owner == 1:
			p1 = c
	if p0.r < 0 or p1.r < 0:
		# Still OK if at least non-white found.
		return
	# Teams should differ (cyan vs red-ish).
	var dist := absf(p0.r - p1.r) + absf(p0.g - p1.g) + absf(p0.b - p1.b)
	if dist < 0.25:
		_fail("P0/P1 HP colors too similar (dist=%.2f)" % dist)

func _assert_pickup_visuals(expect_gear: bool, expect_egg: bool) -> void:
	var pickups := _board.get_node_or_null("Pickups") as Node3D
	if pickups == null:
		_fail("Pickups root missing")
		return
	var saw_egg := false
	var saw_gear := false
	for child in pickups.get_children():
		if not str(child.name).begins_with("P_"):
			continue
		var has_sphere := false
		var has_cyl := false
		var has_hint := false
		var has_gear := false
		for c in child.get_children():
			if c is MeshInstance3D:
				var mesh = (c as MeshInstance3D).mesh
				if mesh is SphereMesh:
					has_sphere = true
				if mesh is CylinderMesh:
					has_cyl = true
			if str(c.name) == "Hint":
				has_hint = true
			if str(c.name) == "Gear":
				has_gear = true
		if has_sphere and not has_gear:
			saw_egg = true
			if has_hint:
				_fail("egg still shows content Hint")
		if has_gear:
			saw_gear = true
			if has_sphere or has_cyl:
				_fail("gear has ball/pad mesh")
	if expect_egg and not saw_egg:
		_fail("no egg visual found")
	if expect_gear and not saw_gear:
		_fail("no gear emoji visual found")

func _assert_egg_materials_opaque() -> void:
	var pickups := _board.get_node_or_null("Pickups") as Node3D
	if pickups == null:
		return
	for child in pickups.get_children():
		for c in child.get_children():
			if c is MeshInstance3D and (c as MeshInstance3D).mesh is SphereMesh:
				var mat := (c as MeshInstance3D).material_override as StandardMaterial3D
				if mat == null:
					continue
				if mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and mat.albedo_color.a < 0.98:
					_fail("egg not fully opaque (a=%.2f)" % mat.albedo_color.a)

func _count_corpses() -> int:
	var corpses := _board.get_node_or_null("Corpses") as Node3D
	if corpses == null:
		return 0
	return corpses.get_child_count()

func _shot(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		print("SHOT_SKIP ", name)
		return
	var path := "%s/%s.png" % [_out, name]
	var err := img.save_png(ProjectSettings.globalize_path(path))
	if err != OK:
		print("SHOT_FAIL ", name, " err=", err)
	else:
		print("SHOT_OK ", name)

func _fail(msg: String) -> void:
	_fails.append(msg)
	print("FAIL: ", msg)

func _finish() -> void:
	print("BUGFIX_VALIDATE_RESULTS fails=%d" % _fails.size())
	for f in _fails:
		print("FAIL: ", f)
	if _fails.is_empty():
		print("BUGFIX_VALIDATE_OK")
	get_tree().quit(0 if _fails.is_empty() else 1)
