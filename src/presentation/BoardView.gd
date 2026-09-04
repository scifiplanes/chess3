extends Node3D

@onready var voxel_root: Node3D = $VoxelRoot
@onready var highlights_root: Node3D = $Highlights
@onready var squads_root: Node3D = $Squads
var control_points_root: Node3D
var reinforcement_areas_root: Node3D
var obstacles_root: Node3D
var float_text_root: Node3D
var pending_ghosts_root: Node3D
var corpses_root: Node3D
var pickups_root: Node3D
var resolve_flash_root: Node3D

const BoardStateScript = preload("res://src/sim/BoardState.gd")
const GameStateScript = preload("res://src/sim/GameState.gd")
const UnitDefsScript = preload("res://src/sim/UnitDefs.gd")
const ResolverScript = preload("res://src/sim/Resolver.gd")
const K1Widgets = preload("res://src/presentation/K1Widgets.gd")
const OrganEmojiPartScript = preload("res://src/presentation/OrganEmojiPart.gd")

const DEFAULT_SIZE := GameStateScript.DEFAULT_BOARD_SIZE
const CELL_SIZE := 1.0
## Top of voxel tiles (BoxMesh height 0.2 centered at y=0) — corpse collision / rest height.
const CORPSE_FLOOR_Y := 0.11
## Tile top face (cell BoxMesh y=0, height 0.2 → top at 0.1). Prop feet plant here.
const PROP_FLOOR_Y := 0.10
## Slight sink so PNG pad / alpha fringe doesn't read as a hover gap.
const PROP_FOOT_SINK := 0.025
const CORPSE_RADIUS := 0.12
## Mushroom obstacles: 6 species × 3 authored yaw frames (0° / 45° / 120°).
## Camera yaw picks nearest frame (+ flip). Sprites use FIXED_Y billboard so feet stay planted.
const MUSHROOM_SPECIES := 6
const MUSHROOM_YAW_DEGS: Array[float] = [0.0, 45.0, 120.0]
const MUSHROOM_PIXEL_SIZE := 0.00155
const HERO_PROP_PIXEL_SIZE := 0.00265
const TILE_SOIL_PATH := "res://assets/tiles/tile_soil.png"
const TILE_ROCK_PATH := "res://assets/tiles/tile_rock.png"
const TILE_SAND_PATH := "res://assets/tiles/tile_sand.png"
const TILE_MYCELIUM_LIGHT_PATH := "res://assets/tiles/tile_mycelium_light.png"
const TILE_MYCELIUM_DARK_PATH := "res://assets/tiles/tile_mycelium_dark.png"
const TILE_SPAWN_SLIME_PATH := "res://assets/tiles/tile_spawn_slime.png"

var _size: Vector2i = DEFAULT_SIZE
var _cell_mesh: BoxMesh
var _tile_nodes := {} # Vector2i -> MeshInstance3D
var _terrain_mats := {} # int -> StandardMaterial3D
var _bone_mat: StandardMaterial3D
var _slate_mat: StandardMaterial3D
var _checker_mats := {} # String -> StandardMaterial3D
## species_i -> Array[Texture2D] of len 3 (yaw frames)
var _mushroom_species_tex: Array = []
var _mushroom_view_yaw_q: float = -9999.0
## "blob"|"rock" -> Array[Texture2D]
var _hero_prop_tex := {}
var _tex_soil: Texture2D
var _tex_rock: Texture2D
var _tex_sand: Texture2D
var _tex_myc_light: Texture2D
var _tex_myc_dark: Texture2D
var _tex_spawn_slime: Texture2D
var _spawn_pad_mesh: BoxMesh
## Gene pending for offer attach targeting (empty = none).
var _offer_attach_def_id: String = ""
var _props_dim_moving: bool = false
var _pickup_bob_t: float = 0.0
var _spawn_teach: bool = false
var _spawn_teach_player: int = 0
var _spawn_pulse_t: float = 0.0
var _cp_demote: bool = false
var _rules_home = null

func set_offer_targeting(unit_def_id: String) -> void:
	_offer_attach_def_id = str(unit_def_id).strip_edges()

func set_move_prop_dim(active: bool) -> void:
	_props_dim_moving = active

func _ready() -> void:
	const RulesScript = preload("res://src/sim/Rules.gd")
	_rules_home = RulesScript.new()
	_cell_mesh = BoxMesh.new()
	_cell_mesh.size = Vector3(CELL_SIZE, 0.2, CELL_SIZE)
	_spawn_pad_mesh = BoxMesh.new()
	_spawn_pad_mesh.size = Vector3(CELL_SIZE * 0.96, 0.025, CELL_SIZE * 0.96)

	_load_tile_textures()
	_terrain_mats.clear()
	# Fungal terrain defaults (textured).
	_terrain_mats[BoardStateScript.TERRAIN_SOIL] = _make_tex_tile_mat(_tex_soil, Color(0.92, 0.94, 0.96))
	_terrain_mats[BoardStateScript.TERRAIN_ROCK] = _make_tex_tile_mat(_tex_rock, Color(1.0, 1.0, 1.0))
	_terrain_mats[BoardStateScript.TERRAIN_SAND] = _make_tex_tile_mat(_tex_sand, Color(1.0, 0.98, 0.94))
	_bone_mat = _make_tex_tile_mat(_tex_myc_light, Color(1.0, 1.0, 1.0))
	_slate_mat = _make_tex_tile_mat(_tex_myc_dark, Color(1.0, 1.0, 1.0))
	_bone_mat.roughness = 0.88
	_slate_mat.roughness = 0.92

	control_points_root = get_node_or_null("ControlPoints")
	if control_points_root == null:
		control_points_root = Node3D.new()
		control_points_root.name = "ControlPoints"
		add_child(control_points_root)

	reinforcement_areas_root = get_node_or_null("ReinforcementAreas")
	if reinforcement_areas_root == null:
		reinforcement_areas_root = Node3D.new()
		reinforcement_areas_root.name = "ReinforcementAreas"
		add_child(reinforcement_areas_root)

	obstacles_root = get_node_or_null("Obstacles")
	if obstacles_root == null:
		obstacles_root = Node3D.new()
		obstacles_root.name = "Obstacles"
		add_child(obstacles_root)

	float_text_root = get_node_or_null("FloatText")
	if float_text_root == null:
		float_text_root = Node3D.new()
		float_text_root.name = "FloatText"
		add_child(float_text_root)

	pending_ghosts_root = get_node_or_null("PendingGhosts")
	if pending_ghosts_root == null:
		pending_ghosts_root = Node3D.new()
		pending_ghosts_root.name = "PendingGhosts"
		add_child(pending_ghosts_root)

	corpses_root = get_node_or_null("Corpses") as Node3D
	if corpses_root == null:
		corpses_root = Node3D.new()
		corpses_root.name = "Corpses"
		add_child(corpses_root)

	pickups_root = get_node_or_null("Pickups") as Node3D
	if pickups_root == null:
		pickups_root = Node3D.new()
		pickups_root.name = "Pickups"
		add_child(pickups_root)

	resolve_flash_root = get_node_or_null("ResolveFlash") as Node3D
	if resolve_flash_root == null:
		resolve_flash_root = Node3D.new()
		resolve_flash_root.name = "ResolveFlash"
		add_child(resolve_flash_root)

	_ensure_physics_floor()

func _process(delta: float) -> void:
	if pickups_root != null:
		_pickup_bob_t += delta
		var bob := sin(_pickup_bob_t * 2.4) * 0.04
		var i := 0
		for child in pickups_root.get_children():
			if child is Node3D:
				var base_y: float = float(child.get_meta("base_y", 0.0))
				(child as Node3D).position.y = base_y + bob * (0.85 + 0.15 * float(i % 3))
			i += 1
	if _spawn_teach and reinforcement_areas_root != null:
		_spawn_pulse_t += delta
		var pulse := 0.55 + 0.45 * sin(_spawn_pulse_t * 3.6)
		for child in reinforcement_areas_root.get_children():
			if not bool(child.get_meta("spawn_teach", false)):
				continue
			var pad := child.get_node_or_null("SlimePad") as MeshInstance3D
			if pad == null:
				continue
			var mat := pad.material_override as StandardMaterial3D
			if mat == null:
				continue
			mat.albedo_color = Color(0.42, 0.78, 0.68, 0.38 + 0.28 * pulse)
			mat.emission = Color(0.28, 0.72, 0.58)
			mat.emission_energy_multiplier = 0.35 + 0.85 * pulse
			var rim_n := child.get_node_or_null("BevelRim") as MeshInstance3D
			if rim_n != null:
				var rim_mat := rim_n.material_override as StandardMaterial3D
				if rim_mat != null:
					rim_mat.albedo_color = Color(0.35, 0.85, 0.7, 0.25 + 0.35 * pulse)
					rim_mat.emission_energy_multiplier = 0.3 + 0.7 * pulse
	_update_mushroom_yaw_frames(false)

func _ensure_physics_floor() -> void:
	var existing := get_node_or_null("PhysicsFloor")
	if existing != null:
		existing.queue_free()
	var floor_body := StaticBody3D.new()
	floor_body.name = "PhysicsFloor"
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(float(_size.x) * CELL_SIZE + 2.0, 0.2, float(_size.y) * CELL_SIZE + 2.0)
	cs.shape = box
	floor_body.add_child(cs)
	floor_body.position = Vector3(
		float(_size.x) * CELL_SIZE * 0.5,
		CORPSE_FLOOR_Y - 0.1,
		float(_size.y) * CELL_SIZE * 0.5
	)
	add_child(floor_body)

	_build_debug_board()
	set_process(true)

func _load_tile_textures() -> void:
	_tex_soil = load(TILE_SOIL_PATH) as Texture2D
	_tex_rock = load(TILE_ROCK_PATH) as Texture2D
	_tex_sand = load(TILE_SAND_PATH) as Texture2D
	_tex_myc_light = load(TILE_MYCELIUM_LIGHT_PATH) as Texture2D
	_tex_myc_dark = load(TILE_MYCELIUM_DARK_PATH) as Texture2D
	_tex_spawn_slime = load(TILE_SPAWN_SLIME_PATH) as Texture2D

func _make_tile_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.95
	return m

func _make_tex_tile_mat(tex: Texture2D, modulate: Color = Color(1, 1, 1, 1)) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = modulate
	if tex != null:
		m.albedo_texture = tex
	m.roughness = 0.92
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m

func _terrain_texture_for(tid: int, parity: int) -> Texture2D:
	match tid:
		BoardStateScript.TERRAIN_ROCK:
			return _tex_rock if _tex_rock != null else _tex_myc_light
		BoardStateScript.TERRAIN_SAND:
			return _tex_sand if _tex_sand != null else _tex_myc_light
		_:
			# Soil: light bone mycelium / dark damp fungal soil checker.
			if parity == 0:
				return _tex_myc_light if _tex_myc_light != null else _tex_soil
			return _tex_soil if _tex_soil != null else _tex_myc_dark

func _terrain_modulate_for(tid: int, parity: int) -> Color:
	match tid:
		BoardStateScript.TERRAIN_ROCK:
			return Color(0.78, 0.76, 0.74) if parity == 0 else Color(0.52, 0.53, 0.55)
		BoardStateScript.TERRAIN_SAND:
			return Color(0.72, 0.66, 0.55) if parity == 0 else Color(0.50, 0.45, 0.36)
		_:
			return Color(0.82, 0.80, 0.78) if parity == 0 else Color(0.70, 0.72, 0.74)

func grid_size() -> Vector2i:
	return _size

func cell_from_world(world_pos: Vector3) -> Vector2i:
	var gx := int(floor(world_pos.x / CELL_SIZE))
	var gy := int(floor(world_pos.z / CELL_SIZE))
	return Vector2i(gx, gy)

func is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _size.x and cell.y < _size.y

func clear_highlights() -> void:
	for c in highlights_root.get_children():
		c.queue_free()

func highlight_cell(cell: Vector2i, color: Color) -> void:
	_add_highlight_pad(highlights_root, cell, color, 0.35, 0.98)

func highlight_cells(cells: Array, color: Color, alpha: float = 0.32) -> void:
	for cell_any in cells:
		var cell: Vector2i = cell_any
		_add_highlight_pad(highlights_root, cell, color, alpha, 0.96)

func highlight_line(cells: Array, color: Color) -> void:
	## Brighter spine pads for railgun / dash path telegraphs.
	for i in range(cells.size()):
		var cell: Vector2i = cells[i]
		var a := 0.42 if i == 0 or i == cells.size() - 1 else 0.55
		_add_highlight_pad(highlights_root, cell, color, a, 0.88)

func flash_cells(cells: Array, color: Color = Color(1.0, 0.85, 0.35, 1.0), duration: float = 0.28) -> void:
	if resolve_flash_root == null:
		return
	var pads: Array = []
	for cell_any in cells:
		var cell: Vector2i = cell_any
		var mi := _make_highlight_pad(cell, color, 0.55, 0.94)
		if mi == null:
			continue
		resolve_flash_root.add_child(mi)
		pads.append(mi)
	if pads.is_empty():
		return
	var tw := create_tween()
	tw.set_parallel(true)
	for pad_any in pads:
		var pad: MeshInstance3D = pad_any
		var mat := pad.material_override as StandardMaterial3D
		if mat == null:
			continue
		tw.tween_property(mat, "albedo_color:a", 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.set_parallel(false)
	tw.tween_callback(func() -> void:
		for p_any in pads:
			if is_instance_valid(p_any):
				(p_any as Node).queue_free()
	)

func _add_highlight_pad(parent: Node3D, cell: Vector2i, color: Color, alpha: float, size_frac: float) -> void:
	var mi := _make_highlight_pad(cell, color, alpha, size_frac)
	if mi != null and parent != null:
		parent.add_child(mi)

func _make_highlight_pad(cell: Vector2i, color: Color, alpha: float, size_frac: float) -> MeshInstance3D:
	if not is_in_bounds(cell):
		return null
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(CELL_SIZE * size_frac, 0.05, CELL_SIZE * size_frac)
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	var col := color
	col.a = clampf(alpha, 0.05, 1.0)
	mat.albedo_color = col
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.position = Vector3((cell.x + 0.5) * CELL_SIZE, 0.16, (cell.y + 0.5) * CELL_SIZE)
	return mi

func sync_from_game_state(gs) -> void:
	if gs == null:
		return
	if gs.board != null:
		var sz: Vector2i = gs.board.size
		if sz.x > 0 and sz.y > 0 and sz != _size:
			_size = sz
			_build_debug_board()
			_ensure_physics_floor()
			call_deferred("_notify_camera_board_changed")
	var ap := int(gs.active_player)
	var owned_ap := 0
	for s_any in gs.squads.values():
		var sq = s_any
		if sq != null and sq.is_alive() and int(sq.owner) == ap:
			owned_ap += 1
	_spawn_teach = bool(gs.offer_pending) and int(gs.turn_number) <= 2
	_spawn_teach_player = ap
	_cp_demote = owned_ap == 0
	if not _spawn_teach:
		_spawn_pulse_t = 0.0
	_sync_terrain(gs)
	_sync_control_points(gs)
	_sync_reinforcement_areas(gs)
	_sync_obstacles(gs)
	_sync_pickups(gs)
	_sync_pending_strike_ghosts(gs)
	if squads_root != null and squads_root.has_method("sync_from_game_state"):
		squads_root.call("sync_from_game_state", gs, int(gs.selected_squad_id), float(CELL_SIZE), _offer_attach_def_id)

func play_hit_flash(squad_id: int) -> void:
	if squads_root != null and squads_root.has_method("play_hit_flash"):
		squads_root.call("play_hit_flash", int(squad_id))

func play_graft_celebrate(squad_id: int) -> void:
	if squads_root != null and squads_root.has_method("play_graft_celebrate"):
		squads_root.call("play_graft_celebrate", int(squad_id))

func play_reject_pulse(squad_id: int) -> void:
	if squads_root != null and squads_root.has_method("play_reject_pulse"):
		squads_root.call("play_reject_pulse", int(squad_id))

func spawn_organ_corpse(def_id: String, global_pos: Vector3, impulse: Vector3 = Vector3.ZERO) -> void:
	if corpses_root == null:
		return
	const BattlefieldForceScript = preload("res://src/presentation/vfx/BattlefieldForce.gd")
	const ContactShadowScript = preload("res://src/presentation/vfx/ContactShadow.gd")
	const OrganSplatterVfxScript = preload("res://src/presentation/vfx/OrganSplatterVfx.gd")
	var body := RigidBody3D.new()
	body.mass = 0.4
	body.gravity_scale = 1.35
	body.continuous_cd = true
	body.linear_damp = 0.45
	body.angular_damp = 0.7
	body.add_to_group(BattlefieldForceScript.FORCE_GROUP)
	body.set_meta("force_while_frozen", true)
	body.set_meta("force_light", true)
	# Never spawn intersecting the floor plane (was y=0 through tile centers → stuck inside voxels).
	var spawn := global_pos
	spawn.y = maxf(spawn.y, CORPSE_FLOOR_Y + CORPSE_RADIUS + 0.12)
	corpses_root.add_child(body)
	body.global_position = spawn
	# Orange pop + floor splat at destruction point.
	var vfx_host: Node3D = get_parent() as Node3D
	if vfx_host == null:
		vfx_host = self
	var vfx_root := vfx_host.get_node_or_null("VfxRoot") as Node3D
	if vfx_root == null:
		vfx_root = vfx_host
	OrganSplatterVfxScript.play(vfx_root, spawn, CORPSE_FLOOR_Y, 1.0)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = CORPSE_RADIUS
	shape.shape = sphere
	body.add_child(shape)
	var visual := OrganEmojiPartScript.new()
	visual.name = "Visual"
	visual.configure(str(def_id), Vector3(0, 0.04, 0), 0.0068)
	visual.call("set_tint", OrganEmojiPartScript.corpse_tint)
	body.add_child(visual)
	ContactShadowScript.attach(
		body,
		Vector2(CORPSE_RADIUS * 2.0, CORPSE_RADIUS * 2.0),
		CORPSE_FLOOR_Y,
		board_center_xz(),
		board_half_extent(),
		CORPSE_RADIUS * 2.0
	)
	var imp := impulse
	if imp.length_squared() < 0.01:
		imp = Vector3(randf_range(-1.4, 1.4), randf_range(2.4, 3.8), randf_range(-1.4, 1.4))
	else:
		# Ensure some upward kick so we clear the floor even from low organ slots.
		imp.y = maxf(imp.y, 1.6)
	body.apply_central_impulse(imp)
	body.apply_torque_impulse(Vector3(randf_range(-1.5, 1.5), randf_range(-1.0, 1.0), randf_range(-1.5, 1.5)))
	var settle := get_tree().create_timer(3.6)
	settle.timeout.connect(func() -> void:
		if not is_instance_valid(body):
			return
		# Snap onto the walkable surface before freeze (avoids embedding mid-voxel).
		var p := body.global_position
		p.y = maxf(p.y, CORPSE_FLOOR_Y + CORPSE_RADIUS + 0.01)
		body.global_position = p
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.freeze = true
		body.sleeping = true
	)

func cell_world_center(cell: Vector2i) -> Vector3:
	return Vector3((cell.x + 0.5) * CELL_SIZE, CORPSE_FLOOR_Y + 0.35, (cell.y + 0.5) * CELL_SIZE)

func board_ground_y() -> float:
	return CORPSE_FLOOR_Y

func board_half_extent() -> float:
	return float(maxi(_size.x, _size.y)) * CELL_SIZE * 0.5 + 0.2

func board_center_xz() -> Vector2:
	return Vector2(float(_size.x) * CELL_SIZE * 0.5, float(_size.y) * CELL_SIZE * 0.5)

func debris_root() -> Node3D:
	var root := get_node_or_null("Props") as Node3D
	if root == null:
		root = Node3D.new()
		root.name = "Props"
		add_child(root)
	return root

func get_squad_view(squad_id: int) -> Node:
	if squads_root != null and squads_root.has_method("get_view"):
		return squads_root.call("get_view", int(squad_id))
	return null

func pop_text(cell: Vector2i, text: String, color: Color = Color(1, 1, 1, 1)) -> void:
	if float_text_root == null:
		return
	var label := _make_world_label(text)
	label.modulate = color
	label.position = Vector3((cell.x + 0.5) * CELL_SIZE, 1.35, (cell.y + 0.5) * CELL_SIZE)
	float_text_root.add_child(label)

	var t := create_tween()
	t.tween_property(label, "position:y", label.position.y + 0.35, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(label, "modulate:a", 0.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_callback(func(): label.queue_free())

func _sync_terrain(gs) -> void:
	# Mycelium / fungal terrain textures with light-dark checker parity.
	if gs.board == null:
		return
	for y in range(_size.y):
		for x in range(_size.x):
			var cell := Vector2i(x, y)
			var mi := _tile_nodes.get(cell, null) as MeshInstance3D
			if mi == null:
				continue
			var tid := int(gs.board.terrain_at(cell))
			var parity := (x + y) % 2
			var key := "%d_%d" % [tid, parity]
			var mat: StandardMaterial3D = _checker_mats.get(key, null) as StandardMaterial3D
			if mat == null:
				mat = _make_tex_tile_mat(_terrain_texture_for(tid, parity), _terrain_modulate_for(tid, parity))
				mat.roughness = 0.9
				_checker_mats[key] = mat
			mi.material_override = mat
			# Note: UV jitter skipped — mats are shared per (terrain, parity).

func _sync_reinforcement_areas(gs) -> void:
	if reinforcement_areas_root == null:
		return

	# Action phase: hide idle home pads — move mode keeps cyan reach + selection + amber egress only.
	var show_pads := bool(gs.offer_pending)
	reinforcement_areas_root.visible = show_pads
	if not show_pads:
		return

	var teach_cells := {}
	if _spawn_teach and _rules_home != null:
		for c in _rules_home.spawn_cells(gs, _spawn_teach_player):
			teach_cells["%d_%d" % [c.x, c.y]] = true

	var alive_names := {}
	for cell in gs.board.reinforcement_areas:
		var c: Vector2i = cell
		var n := "RA_%d_%d" % [c.x, c.y]
		alive_names[n] = true
		var root := reinforcement_areas_root.get_node_or_null(n) as Node3D
		if root == null:
			root = Node3D.new()
			root.name = n
			reinforcement_areas_root.add_child(root)

		root.position = Vector3((c.x + 0.5) * CELL_SIZE, 0.0, (c.y + 0.5) * CELL_SIZE)
		var is_teach := _spawn_teach and teach_cells.has("%d_%d" % [c.x, c.y])
		root.set_meta("spawn_teach", is_teach)

		var pad := root.get_node_or_null("SlimePad") as MeshInstance3D
		if pad == null:
			for child in root.get_children():
				child.queue_free()
			pad = MeshInstance3D.new()
			pad.name = "SlimePad"
			pad.mesh = _spawn_pad_mesh
			var mat := StandardMaterial3D.new()
			mat.albedo_texture = _tex_spawn_slime
			mat.albedo_color = Color(0.38, 0.58, 0.52, 0.42)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.emission_enabled = true
			mat.emission = Color(0.18, 0.42, 0.38)
			mat.emission_energy_multiplier = 0.18
			if _tex_spawn_slime != null:
				mat.emission_texture = _tex_spawn_slime
			mat.roughness = 0.85
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			pad.material_override = mat
			pad.position = Vector3(0, CORPSE_FLOOR_Y + 0.02, 0)
			root.add_child(pad)
			# Faint beveled square rim for pool readability (cool mint — distinct from CP gold).
			var ring := MeshInstance3D.new()
			ring.name = "BevelRim"
			ring.mesh = K1Widgets.make_bevel_square_mesh(0.40, 0.015, 0.05)
			var rim := StandardMaterial3D.new()
			rim.albedo_color = Color(0.28, 0.55, 0.48, 0.22)
			rim.emission_enabled = true
			rim.emission = Color(0.22, 0.48, 0.42)
			rim.emission_energy_multiplier = 0.18
			rim.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			rim.roughness = 0.9
			ring.material_override = rim
			ring.position = Vector3(0, CORPSE_FLOOR_Y + 0.035, 0)
			root.add_child(ring)

		# Owner-ish UV drift so adjacent pads don't look identical.
		var mat2 := pad.material_override as StandardMaterial3D
		if mat2 != null:
			var h2 := int(c.x) * 2654435761 ^ int(c.y) * 2246822519
			mat2.uv1_offset = Vector3(float(absi(h2) % 10) * 0.05, float(absi(h2 >> 4) % 10) * 0.05, 0.0)
			if not is_teach:
				mat2.albedo_color = Color(0.38, 0.58, 0.52, 0.42)
				mat2.emission = Color(0.18, 0.42, 0.38)
				mat2.emission_energy_multiplier = 0.18
				var rim_n := root.get_node_or_null("BevelRim") as MeshInstance3D
				if rim_n != null:
					var rim_mat := rim_n.material_override as StandardMaterial3D
					if rim_mat != null:
						rim_mat.albedo_color = Color(0.28, 0.55, 0.48, 0.22)
						rim_mat.emission_energy_multiplier = 0.18

	for child in reinforcement_areas_root.get_children():
		if not alive_names.has(child.name):
			child.queue_free()

func _sync_control_points(gs) -> void:
	if control_points_root == null:
		return

	var alive_by_owner := {0: 0, 1: 0}
	for s_any in gs.squads.values():
		var sq = s_any
		if sq != null and sq.is_alive():
			var ow := int(sq.owner)
			alive_by_owner[ow] = int(alive_by_owner.get(ow, 0)) + 1

	var alive_names := {}
	for cp in gs.board.control_points:
		var n := "CP_%d_%d" % [cp.cell.x, cp.cell.y]
		alive_names[n] = true
		var node := control_points_root.get_node_or_null(n)
		var root := node as Node3D
		if root == null:
			root = Node3D.new()
			root.name = n
			control_points_root.add_child(root)

		root.position = Vector3((cp.cell.x + 0.5) * CELL_SIZE, 0.0, (cp.cell.y + 0.5) * CELL_SIZE)

		# Rebuild each sync (CP count is small).
		for c in root.get_children():
			c.queue_free()

		var occupying := {0: false, 1: false}
		for sid_any in gs.squads.keys():
			var squad = gs.get_squad(int(sid_any))
			if squad == null or not squad.is_alive():
				continue
			if gs.board.is_in_cp_zone(squad.cell, cp.cell):
				occupying[int(squad.owner)] = true
		var p0_here := bool(occupying[0])
		var p1_here := bool(occupying[1])
		var contested := p0_here and p1_here
		var flagging_player := -1
		if p0_here != p1_here:
			flagging_player = 0 if p0_here else 1

		var owner_i := int(cp.owner)
		var owner_color := Color(0.62, 0.60, 0.55)
		if owner_i == 0:
			owner_color = K1Widgets.CP_GOLD
		elif owner_i == 1:
			owner_color = Color(0.92, 0.48, 0.38)

		var state_color := owner_color
		if contested:
			state_color = Color(1.0, 0.55, 0.15)
		elif flagging_player == 0:
			state_color = Color(0.98, 0.78, 0.32)
		elif flagging_player == 1:
			state_color = Color(0.95, 0.52, 0.42)

		# Telegraph full 3×3 capture zone (CP + 8 neighbors).
		# Demote gold until the active seat has at least one mutant (opening teach).
		var demote := _cp_demote
		var zone_cells: Array[Vector2i] = gs.board.cp_zone_cells(cp.cell)
		for zone_cell in zone_cells:
			var dx: int = zone_cell.x - cp.cell.x
			var dy: int = zone_cell.y - cp.cell.y
			var is_center: bool = dx == 0 and dy == 0
			if demote and not is_center:
				continue
			var zone_pad := MeshInstance3D.new()
			var zone_mesh := BoxMesh.new()
			zone_mesh.size = Vector3(CELL_SIZE * 0.96, 0.032 if is_center else 0.026, CELL_SIZE * 0.96)
			zone_pad.mesh = zone_mesh
			var zone_mat := StandardMaterial3D.new()
			var alpha := 0.22 if is_center else 0.14
			if flagging_player >= 0 or contested:
				alpha = 0.34 if is_center else 0.26
			elif owner_i >= 0:
				alpha = 0.28 if is_center else 0.18
			if demote:
				alpha *= 0.28
			zone_mat.albedo_color = Color(state_color.r, state_color.g, state_color.b, alpha)
			zone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			zone_mat.emission_enabled = true
			zone_mat.emission = state_color
			zone_mat.emission_energy_multiplier = (1.45 if is_center else 0.95) * (0.25 if demote else 1.0)
			zone_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			zone_pad.material_override = zone_mat
			zone_pad.position = Vector3(dx * CELL_SIZE, 0.122 if is_center else 0.114, dy * CELL_SIZE)
			root.add_child(zone_pad)
			if not is_center and not demote:
				var edge := MeshInstance3D.new()
				edge.mesh = K1Widgets.make_bevel_square_mesh(0.44, 0.026, 0.055)
				var edge_mat := StandardMaterial3D.new()
				edge_mat.albedo_color = Color(state_color.r, state_color.g, state_color.b, 0.78)
				edge_mat.emission_enabled = true
				edge_mat.emission = state_color
				edge_mat.emission_energy_multiplier = 1.25
				edge_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				edge_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				edge.material_override = edge_mat
				edge.position = Vector3(dx * CELL_SIZE, 0.136, dy * CELL_SIZE)
				root.add_child(edge)

		# Center beveled square (zone footprint).
		var ring := MeshInstance3D.new()
		ring.mesh = K1Widgets.make_bevel_square_mesh(0.48, 0.045, 0.06)
		var ring_mat := StandardMaterial3D.new()
		ring_mat.albedo_color = Color(state_color.r, state_color.g, state_color.b, 0.88 if not demote else 0.22)
		ring_mat.emission_enabled = true
		ring_mat.emission = state_color
		ring_mat.emission_energy_multiplier = (1.85 if flagging_player >= 0 or contested else 1.15) * (0.22 if demote else 1.0)
		ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring.material_override = ring_mat
		ring.position = Vector3(0, 0.145, 0)
		root.add_child(ring)

		# ponytail: perimeter ring removed — square zone pads are enough at default zoom.

		# Central beacon pillar (owner tint).
		var base := MeshInstance3D.new()
		var base_mesh := CylinderMesh.new()
		base_mesh.top_radius = 0.12
		base_mesh.bottom_radius = 0.18
		base_mesh.height = 0.22
		base.mesh = base_mesh
		var base_mat := StandardMaterial3D.new()
		base_mat.albedo_color = owner_color
		base_mat.emission_enabled = true
		base_mat.emission = owner_color
		base_mat.emission_energy_multiplier = 0.55 if not demote else 0.12
		base_mat.roughness = 0.75
		base.material_override = base_mat
		base.position = Vector3(0, 0.22, 0)
		root.add_child(base)

		var p0_flags := int(cp.flags_for(0))
		var p1_flags := int(cp.flags_for(1))
		var need0 := int(ResolverScript.CP_CAPTURE_FLAGS) + (1 if int(alive_by_owner.get(0, 0)) <= 1 else 0)
		var need1 := int(ResolverScript.CP_CAPTURE_FLAGS) + (1 if int(alive_by_owner.get(1, 0)) <= 1 else 0)

		# Flag meters with empty slots so progress toward capture is readable.
		_add_flag_meter(root, Vector3(-0.28, 0.28, 0.0), p0_flags, need0, Color(0.35, 0.85, 1.0))
		_add_flag_meter(root, Vector3(0.28, 0.28, 0.0), p1_flags, need1, Color(1.0, 0.45, 0.45))

		# State label: owner + live contest/flagging progress.
		var status := "CP"
		var status_col := Color(0.85, 0.82, 0.72, 0.85)
		if contested:
			status = "CONTESTED"
			status_col = Color(1.0, 0.72, 0.28, 1.0)
		elif flagging_player == 0:
			status = "P0 %d/%d" % [p0_flags, need0]
			status_col = Color(0.55, 0.92, 1.0, 1.0)
		elif flagging_player == 1:
			status = "P1 %d/%d" % [p1_flags, need1]
			status_col = Color(1.0, 0.62, 0.55, 1.0)
		elif owner_i == 0:
			status = "P0 HELD"
			status_col = Color(0.45, 0.88, 1.0, 1.0)
		elif owner_i == 1:
			status = "P1 HELD"
			status_col = Color(1.0, 0.55, 0.5, 1.0)

		var label := _make_world_label(status, 0.0075, 42)
		label.modulate = status_col
		label.position = Vector3(0.0, 0.72, 0.0)
		root.add_child(label)

	for child in control_points_root.get_children():
		if not alive_names.has(child.name):
			child.queue_free()

func _add_flag_meter(parent: Node3D, origin: Vector3, count: int, need: int, color: Color) -> void:
	var slots := clampi(need, 1, 10)
	var filled := clampi(count, 0, slots)
	for i in range(slots):
		var pip := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = Vector3(0.07, 0.07, 0.07)
		pip.mesh = m
		var mat := StandardMaterial3D.new()
		var on := i < filled
		mat.albedo_color = color if on else Color(0.18, 0.18, 0.2, 0.55)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if not on else BaseMaterial3D.TRANSPARENCY_DISABLED
		mat.emission_enabled = on
		if on:
			mat.emission = color
			mat.emission_energy_multiplier = 0.9
		mat.roughness = 0.9
		pip.material_override = mat
		pip.position = origin + Vector3(0.0, i * 0.095, 0.0)
		parent.add_child(pip)

func _sync_pending_strike_ghosts(gs) -> void:
	if pending_ghosts_root == null:
		return
	for c in pending_ghosts_root.get_children():
		c.queue_free()
	if gs == null:
		return
	const AbilityTelegraphScript = preload("res://src/presentation/AbilityTelegraph.gd")
	var turn_now := int(gs.turn_number)
	for pe_any in gs.pending_effects:
		if typeof(pe_any) != TYPE_DICTIONARY:
			continue
		var pe: Dictionary = pe_any
		var payload: Dictionary = pe.get("payload", {})
		var cx := int(payload.get("cx", -1))
		var cy := int(payload.get("cy", -1))
		if cx < 0 or cy < 0:
			continue
		var center := Vector2i(cx, cy)
		if not is_in_bounds(center):
			continue
		var resolve_at := int(pe.get("resolve_at_turn", turn_now))
		var turns_left: int = maxi(0, resolve_at - turn_now)
		var footprint: Array[Vector2i] = AbilityTelegraphScript.impact_for_pending(gs, pe)
		for i in range(footprint.size()):
			var cell: Vector2i = footprint[i]
			var is_center := cell == center
			var a := 0.48 if is_center else 0.22
			var mi := _make_highlight_pad(cell, AbilityTelegraphScript.COLOR_DELAYED, a, 0.92 if is_center else 0.86)
			if mi != null:
				# Slightly raised so it reads over terrain, under float labels.
				mi.position.y = 0.18
				pending_ghosts_root.add_child(mi)
		var label := _make_world_label("Δ%d -> T%d" % [turns_left, resolve_at], 0.008, 48)
		label.position = Vector3((center.x + 0.5) * CELL_SIZE, 0.55, (center.y + 0.5) * CELL_SIZE)
		label.modulate = Color(1.0, 0.85, 0.35, 1.0)
		label.no_depth_test = true
		pending_ghosts_root.add_child(label)

func _make_world_label(text: String, pixel_size: float = 0.01, font_size: int = 36) -> Label3D:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = pixel_size
	label.font_size = font_size
	label.outline_size = maxi(4, int(font_size * 0.22))
	label.outline_modulate = Color(0.04, 0.04, 0.05, 0.9)
	label.text = text
	K1Widgets.apply_label3d_font(label)
	return label

func _ensure_mushroom_textures() -> void:
	if not _mushroom_species_tex.is_empty():
		return
	for si in range(1, MUSHROOM_SPECIES + 1):
		var frames: Array[Texture2D] = []
		var paths: Array[String] = [
			"res://assets/mushrooms/mushroom_%02d.png" % si,
			"res://assets/mushrooms/mushroom_%02d_a45.png" % si,
			"res://assets/mushrooms/mushroom_%02d_a120.png" % si,
		]
		for path in paths:
			var tex := load(path) as Texture2D
			if tex != null:
				frames.append(tex)
		if frames.size() == 3:
			_mushroom_species_tex.append(frames)

func _mushroom_species_for_cell(c: Vector2i) -> int:
	_ensure_mushroom_textures()
	if _mushroom_species_tex.is_empty():
		return 0
	var h := int(c.x) * 73856093 ^ int(c.y) * 19349663 ^ 83492791
	return absi(h) % _mushroom_species_tex.size()

func _mushroom_facing_deg_for_cell(c: Vector2i) -> float:
	# Per-cell facing so frame pops aren't perfectly synchronized.
	var h := int(c.x) * 97 ^ int(c.y) * 193
	return float(absi(h) % 360)

func _ensure_hero_prop_textures() -> void:
	if not _hero_prop_tex.is_empty():
		return
	_hero_prop_tex["blob"] = []
	_hero_prop_tex["rock"] = []
	for i in range(1, 5):
		var bt := load("res://assets/props/heroes/blob_%02d.png" % i) as Texture2D
		if bt != null:
			_hero_prop_tex["blob"].append(bt)
		var rt := load("res://assets/props/heroes/rock_%02d.png" % i) as Texture2D
		if rt != null:
			_hero_prop_tex["rock"].append(rt)

func _hero_index_for_cell(gs, cell: Vector2i) -> Dictionary:
	if gs == null or gs.board == null:
		return {}
	for hp_any in gs.board.hero_props:
		if typeof(hp_any) != TYPE_DICTIONARY:
			continue
		var hp: Dictionary = hp_any
		var c = hp.get("cell", null)
		if c is Vector2i and c == cell:
			return hp
	return {}

func _mushroom_scale_for_cell(c: Vector2i) -> float:
	var h := int(c.x) * 2654435761 ^ int(c.y) * 2246822519
	return 0.88 + float(absi(h) % 28) * 0.01

func _hero_scale_for_cell(c: Vector2i, kind: String) -> float:
	var h := int(c.x) * 2654435761 ^ int(c.y) * 2246822519
	if kind == "mushroom":
		return 1.85 + float(absi(h) % 40) * 0.01
	return 1.35 + float(absi(h) % 35) * 0.01

func _apply_hero_sprite(spr: Sprite3D, kind: String, variant: int, species_fallback: int) -> void:
	_ensure_hero_prop_textures()
	spr.set_meta("hero_kind", kind)
	spr.set_meta("hero_variant", variant)
	if kind == "mushroom":
		spr.pixel_size = MUSHROOM_PIXEL_SIZE
		spr.set_meta("species", clampi(variant, 0, maxi(_mushroom_species_tex.size() - 1, 0)))
		return
	spr.pixel_size = HERO_PROP_PIXEL_SIZE
	spr.flip_h = false
	var arr: Array = _hero_prop_tex.get(kind, [])
	if arr.is_empty():
		# Fallback: keep a mushroom look if art missing.
		spr.pixel_size = MUSHROOM_PIXEL_SIZE
		spr.set_meta("hero_kind", "mushroom")
		spr.set_meta("species", species_fallback)
		return
	var idx := absi(variant - 1) % arr.size()
	var tex: Texture2D = arr[idx]
	spr.texture = tex
	var scale_m := spr.scale.y
	var th := float(tex.get_height()) if tex != null else 192.0
	_plant_prop_sprite(spr, th * HERO_PROP_PIXEL_SIZE, scale_m)

func _plant_prop_sprite(spr: Sprite3D, world_h_unscaled: float, scale_m: float) -> void:
	## Centered Sprite3D: place so the quad's bottom sits on the tile (FIXED_Y keeps it upright).
	if spr == null:
		return
	var world_h := world_h_unscaled * maxf(scale_m, 0.001)
	spr.position = Vector3(0.0, PROP_FLOOR_Y + world_h * 0.5 - PROP_FOOT_SINK, 0.0)

func _camera_view_yaw_deg() -> float:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return 0.0
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		return 0.0
	fwd = fwd.normalized()
	return rad_to_deg(atan2(fwd.x, fwd.z))

func _pick_mushroom_yaw_frame(view_yaw_deg: float, facing_deg: float) -> Vector2i:
	# Returns (frame_index, flip_h as 0/1). Uses authored yaws + mirrors for full circle.
	var rel := fposmod(view_yaw_deg - facing_deg, 360.0)
	var best_i := 0
	var best_flip := 0
	var best_err := 9999.0
	for i in range(MUSHROOM_YAW_DEGS.size()):
		for flip in range(2):
			var a: float = MUSHROOM_YAW_DEGS[i]
			if flip == 1:
				a = fposmod(-a, 360.0)
			var err := absf(rel - a)
			err = minf(err, 360.0 - err)
			if err < best_err:
				best_err = err
				best_i = i
				best_flip = flip
	return Vector2i(best_i, best_flip)

func _apply_mushroom_yaw_to_sprite(spr: Sprite3D, species: int, frame: int, flip: bool) -> void:
	if spr == null or species < 0 or species >= _mushroom_species_tex.size():
		return
	var frames: Array = _mushroom_species_tex[species]
	if frame < 0 or frame >= frames.size():
		return
	var tex: Texture2D = frames[frame]
	if spr.texture != tex:
		spr.texture = tex
	spr.flip_h = flip
	# Keep feet planted after texture swap (heights differ per frame).
	var scale_m := spr.scale.y
	var th := float(tex.get_height()) if tex != null else 700.0
	_plant_prop_sprite(spr, th * MUSHROOM_PIXEL_SIZE, scale_m)

func _update_mushroom_yaw_frames(force: bool) -> void:
	if obstacles_root == null or _mushroom_species_tex.is_empty():
		return
	var yaw := _camera_view_yaw_deg()
	# Quantize so we don't thrash every sub-degree jitter; force on sync.
	var q := floorf(yaw / 8.0) * 8.0
	if not force and is_equal_approx(q, _mushroom_view_yaw_q):
		return
	_mushroom_view_yaw_q = q
	for child in obstacles_root.get_children():
		var spr := child.get_node_or_null("Mush") as Sprite3D
		if spr == null:
			continue
		var hero_kind := str(spr.get_meta("hero_kind", ""))
		if hero_kind != "" and hero_kind != "mushroom":
			continue
		var species := int(spr.get_meta("species", 0))
		var facing := float(spr.get_meta("facing_deg", 0.0))
		var pick := _pick_mushroom_yaw_frame(yaw, facing)
		_apply_mushroom_yaw_to_sprite(spr, species, pick.x, pick.y == 1)

func _sync_obstacles(gs) -> void:
	if obstacles_root == null:
		return
	_ensure_mushroom_textures()
	_ensure_hero_prop_textures()

	var alive_names := {}
	var cells: Array = gs.board.obstacles.keys()
	cells.sort_custom(func(a, b): return (a.x == b.x and a.y < b.y) or (a.x < b.x))
	var view_yaw := _camera_view_yaw_deg()
	for cell in cells:
		var c: Vector2i = cell
		if not gs.board.is_blocked(c):
			continue
		var n := "O_%d_%d" % [c.x, c.y]
		alive_names[n] = true
		var root := obstacles_root.get_node_or_null(n) as Node3D
		if root == null:
			root = Node3D.new()
			root.name = n
			obstacles_root.add_child(root)

		root.position = Vector3((c.x + 0.5) * CELL_SIZE, 0.0, (c.y + 0.5) * CELL_SIZE)

		var hero := _hero_index_for_cell(gs, c)
		var hero_kind := str(hero.get("kind", "")) if not hero.is_empty() else ""
		var hero_variant := int(hero.get("variant", 0)) if not hero.is_empty() else 0
		var species := _mushroom_species_for_cell(c)
		if hero_kind == "mushroom":
			species = clampi(hero_variant, 0, maxi(_mushroom_species_tex.size() - 1, 0))
		var facing := _mushroom_facing_deg_for_cell(c)
		var spr := root.get_node_or_null("Mush") as Sprite3D
		if spr == null:
			for child in root.get_children():
				child.queue_free()
			spr = Sprite3D.new()
			spr.name = "Mush"
			# FIXED_Y: face camera in yaw only — full billboard tips toward a downward camera and floats feet.
			spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
			spr.transparent = true
			spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
			# Must stay below idle modulate.a — scissor runs after modulate, so
			# threshold ≥ mush_a discarded every pixel (mushrooms vanished at α0.25).
			spr.alpha_scissor_threshold = 0.08
			spr.shaded = false
			spr.double_sided = true
			spr.centered = true
			spr.pixel_size = MUSHROOM_PIXEL_SIZE
			spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			root.add_child(spr)

		# Keep cut below modulate α even for sprites created under the old 0.35 threshold.
		spr.alpha_scissor_threshold = 0.08
		spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		spr.set_meta("facing_deg", facing)
		var scale_m := _mushroom_scale_for_cell(c)
		if hero_kind != "":
			scale_m = _hero_scale_for_cell(c, hero_kind)
			_apply_hero_sprite(spr, hero_kind, hero_variant, species)
		else:
			spr.set_meta("hero_kind", "")
			spr.pixel_size = MUSHROOM_PIXEL_SIZE
			spr.set_meta("species", species)
		spr.scale = Vector3(scale_m, scale_m, scale_m)
		if hero_kind == "" or hero_kind == "mushroom":
			var pick := _pick_mushroom_yaw_frame(view_yaw, facing)
			_apply_mushroom_yaw_to_sprite(spr, int(spr.get_meta("species", species)), pick.x, pick.y == 1)
		elif spr.texture != null:
			var th := float(spr.texture.get_height())
			_plant_prop_sprite(spr, th * spr.pixel_size, scale_m)
		# Visible props; Mutants still win glance via 2.2× scale + floor disc + rim.
		var mush_a := 0.72
		var no_sel := int(gs.selected_squad_id) < 0
		if not no_sel:
			mush_a = 0.48 if _props_dim_moving else 0.58
		if hero_kind != "":
			mush_a *= 0.85 if no_sel else 0.70
		if gs.board.is_destructible(c):
			spr.modulate = Color(0.92, 0.82, 0.68, mush_a)
		else:
			spr.modulate = Color(0.78, 0.80, 0.82, mush_a)
		if hero_kind == "blob":
			spr.modulate = Color(0.82, 0.92, 0.78, mush_a)
		elif hero_kind == "rock":
			spr.modulate = Color(0.88, 0.84, 0.78, mush_a)

	for child in obstacles_root.get_children():
		if not alive_names.has(child.name):
			child.queue_free()
	_mushroom_view_yaw_q = -9999.0
	_update_mushroom_yaw_frames(true)

func _sync_pickups(gs) -> void:
	if pickups_root == null or gs == null or gs.board == null:
		return
	# Opening offer: hide gear/egg orbs until this seat has a Mutant (teach = home pads only).
	if _spawn_teach and _cp_demote:
		for child in pickups_root.get_children():
			child.queue_free()
		return
	var alive_names := {}
	var cells: Array = []
	for c in gs.board.gear.keys():
		cells.append(c)
	for c in gs.board.eggs.keys():
		if not cells.has(c):
			cells.append(c)
	cells.sort_custom(func(a, b): return (a.x == b.x and a.y < b.y) or (a.x < b.x))
	var can_graft := false
	var reach_pickups: Array[Vector2i] = []
	if int(gs.selected_squad_id) >= 0 and _rules_home != null:
		var sel = gs.get_squad(int(gs.selected_squad_id))
		can_graft = _rules_home.can_field_attach(sel)
		if can_graft:
			reach_pickups = _rules_home.reachable_field_pickups(gs, int(gs.selected_squad_id))
	for cell in cells:
		var c: Vector2i = cell
		var is_gear: bool = gs.board.gear.has(c)
		var is_egg: bool = gs.board.eggs.has(c)
		var n := "P_%d_%d" % [c.x, c.y]
		alive_names[n] = true
		var root := pickups_root.get_node_or_null(n) as Node3D
		if root == null:
			root = Node3D.new()
			root.name = n
			pickups_root.add_child(root)
		# Root sits on tile top; children lift so centered emoji billboards stay above the floor.
		root.position = Vector3((c.x + 0.5) * CELL_SIZE, CORPSE_FLOOR_Y, (c.y + 0.5) * CELL_SIZE)
		root.set_meta("base_y", CORPSE_FLOOR_Y)
		for child in root.get_children():
			child.queue_free()
		# CRT literacy: blue gear / green egg / red curse — larger + taller than idle Mutant clutter.
		var in_reach := reach_pickups.has(c)
		var pickup_lit := can_graft and in_reach
		if is_egg:
			# Opaque mystery ball — never reveal contained organ emoji.
			var egg = gs.board.egg_at(c)
			var eid := str(egg.get("unit_def_id", "chunk")) if egg != null else "chunk"
			var cursed := UnitDefsScript.is_curse_organ(eid)
			var shell := MeshInstance3D.new()
			var mesh := SphereMesh.new()
			mesh.radius = 0.26 if pickup_lit else 0.23
			mesh.height = mesh.radius * 2.0
			shell.mesh = mesh
			var mat := StandardMaterial3D.new()
			mat.emission_enabled = true
			if not can_graft and int(gs.selected_squad_id) >= 0:
				# Selected mutant at hard max — egg is unusable; gray it out.
				mat.albedo_color = Color(0.42, 0.42, 0.44, 1.0)
				mat.emission = Color(0.28, 0.28, 0.30)
				mat.emission_energy_multiplier = 0.12
			elif cursed:
				mat.albedo_color = Color(0.88, 0.18, 0.14, 1.0)
				mat.emission = Color(1.0, 0.18, 0.12)
				mat.emission_energy_multiplier = 0.55 if pickup_lit else 0.32
			else:
				mat.albedo_color = Color(0.22, 0.78, 0.36, 1.0)
				mat.emission = Color(0.2, 0.85, 0.32)
				mat.emission_energy_multiplier = 0.45 if pickup_lit else 0.25
			mat.roughness = 0.45
			mat.metallic = 0.05
			shell.material_override = mat
			shell.position = Vector3(0.0, 0.34, 0.0)
			root.add_child(shell)
		elif is_gear:
			# Gear: function-clear organ emoji only (no ball / no pad blob).
			var gear = gs.board.gear_at(c)
			var gid := str(gear.get("unit_def_id", "claw")) if gear != null else "claw"
			var reclaimable := UnitDefsScript.is_reclaimable_gear(gid)
			var usable := reclaimable and (int(gs.selected_squad_id) < 0 or can_graft)
			var organ := OrganEmojiPartScript.new()
			organ.name = "Gear"
			organ.configure(gid, Vector3(0.0, 0.38, 0.0), 0.0095 if pickup_lit else 0.0082)
			if not usable:
				organ.call("set_tint", OrganEmojiPartScript.unusable_gear_tint)
			elif pickup_lit:
				organ.call("set_tint", Color(1.0, 1.0, 1.0, 1.0))
			else:
				organ.call("set_tint", Color(1.0, 1.0, 1.0, 0.88))
			root.add_child(organ)
	for child in pickups_root.get_children():
		if not alive_names.has(child.name):
			child.queue_free()

func _notify_camera_board_changed() -> void:
	for n in get_tree().get_nodes_in_group("camera_controller"):
		if n.has_method("refresh_for_board"):
			n.call("refresh_for_board")

func _build_debug_board() -> void:
	for c in voxel_root.get_children():
		c.queue_free()
	_tile_nodes.clear()

	for y in range(_size.y):
		for x in range(_size.x):
			var mi := MeshInstance3D.new()
			mi.name = "T_%d_%d" % [x, y]
			mi.mesh = _cell_mesh
			mi.material_override = _terrain_mats.get(BoardStateScript.TERRAIN_SOIL, null)
			mi.position = Vector3((x + 0.5) * CELL_SIZE, 0.0, (y + 0.5) * CELL_SIZE)
			voxel_root.add_child(mi)
			_tile_nodes[Vector2i(x, y)] = mi

