extends Node3D

@onready var voxel_root: Node3D = $VoxelRoot
@onready var highlights_root: Node3D = $Highlights
@onready var squads_root: Node3D = $Squads
var control_points_root: Node3D
var reinforcement_areas_root: Node3D
var obstacles_root: Node3D
var float_text_root: Node3D
var pending_ghosts_root: Node3D

const BoardStateScript = preload("res://src/sim/BoardState.gd")
const GameStateScript = preload("res://src/sim/GameState.gd")

const DEFAULT_SIZE := GameStateScript.DEFAULT_BOARD_SIZE
const CELL_SIZE := 1.0

var _size: Vector2i = DEFAULT_SIZE
var _cell_mesh: BoxMesh
var _tile_nodes := {} # Vector2i -> MeshInstance3D
var _terrain_mats := {} # int -> StandardMaterial3D

func _ready() -> void:
	_cell_mesh = BoxMesh.new()
	_cell_mesh.size = Vector3(CELL_SIZE, 0.2, CELL_SIZE)

	_terrain_mats.clear()
	_terrain_mats[BoardStateScript.TERRAIN_SOIL] = _make_tile_mat(Color(0.10, 0.12, 0.10))
	_terrain_mats[BoardStateScript.TERRAIN_ROCK] = _make_tile_mat(Color(0.14, 0.14, 0.16))
	_terrain_mats[BoardStateScript.TERRAIN_SAND] = _make_tile_mat(Color(0.18, 0.16, 0.10))

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

	_build_debug_board()

func _make_tile_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.95
	return m

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
	if not is_in_bounds(cell):
		return
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(CELL_SIZE * 0.98, 0.05, CELL_SIZE * 0.98)
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.35
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.position = Vector3((cell.x + 0.5) * CELL_SIZE, 0.16, (cell.y + 0.5) * CELL_SIZE)
	highlights_root.add_child(mi)

func sync_from_game_state(gs) -> void:
	if gs == null:
		return
	if gs.board != null:
		var sz: Vector2i = gs.board.size
		if sz.x > 0 and sz.y > 0 and sz != _size:
			_size = sz
			_build_debug_board()
			call_deferred("_notify_camera_board_changed")
	_sync_terrain(gs)
	_sync_control_points(gs)
	_sync_reinforcement_areas(gs)
	_sync_obstacles(gs)
	_sync_pending_strike_ghosts(gs)
	if squads_root != null and squads_root.has_method("sync_from_game_state"):
		squads_root.call("sync_from_game_state", gs, int(gs.selected_squad_id), float(CELL_SIZE))

func play_hit_flash(squad_id: int) -> void:
	if squads_root != null and squads_root.has_method("play_hit_flash"):
		squads_root.call("play_hit_flash", int(squad_id))

func pop_text(cell: Vector2i, text: String, color: Color = Color(1, 1, 1, 1)) -> void:
	if float_text_root == null:
		return
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.01
	label.outline_size = 6
	label.outline_modulate = Color(0, 0, 0, 1)
	label.modulate = color
	label.text = text
	label.position = Vector3((cell.x + 0.5) * CELL_SIZE, 1.35, (cell.y + 0.5) * CELL_SIZE)
	float_text_root.add_child(label)

	var t := create_tween()
	t.tween_property(label, "position:y", label.position.y + 0.35, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(label, "modulate:a", 0.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_callback(func(): label.queue_free())

func _sync_reinforcement_areas(gs) -> void:
	if reinforcement_areas_root == null:
		return

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

		for child in root.get_children():
			child.queue_free()

		var ring := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.42
		mesh.bottom_radius = 0.42
		mesh.height = 0.04
		ring.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.85, 0.25)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.75, 0.10)
		mat.roughness = 0.7
		ring.material_override = mat
		ring.position = Vector3(0, 0.14, 0)
		root.add_child(ring)

	for child in reinforcement_areas_root.get_children():
		if not alive_names.has(child.name):
			child.queue_free()

func _sync_terrain(gs) -> void:
	# Update per-cell ground tile materials based on sim terrain.
	if gs.board == null:
		return
	for y in range(_size.y):
		for x in range(_size.x):
			var cell := Vector2i(x, y)
			var mi := _tile_nodes.get(cell, null) as MeshInstance3D
			if mi == null:
				continue
			var tid := int(gs.board.terrain_at(cell))
			var mat: StandardMaterial3D = _terrain_mats.get(tid, null)
			if mat == null:
				mat = _terrain_mats.get(BoardStateScript.TERRAIN_SOIL, null) as StandardMaterial3D
			mi.material_override = mat

func _sync_control_points(gs) -> void:
	if control_points_root == null:
		return

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

		# Clear children and rebuild simple marker (tiny scene graph, CP count is small).
		for c in root.get_children():
			c.queue_free()

		var owner_color := Color(0.55, 0.55, 0.55)
		if cp.owner == 0:
			owner_color = Color(0.35, 0.85, 1.0)
		elif cp.owner == 1:
			owner_color = Color(1.0, 0.45, 0.45)

		var base := MeshInstance3D.new()
		var base_mesh := CylinderMesh.new()
		base_mesh.top_radius = 0.20
		base_mesh.bottom_radius = 0.20
		base_mesh.height = 0.15
		base.mesh = base_mesh
		var base_mat := StandardMaterial3D.new()
		base_mat.albedo_color = owner_color
		base_mat.roughness = 0.8
		base.material_override = base_mat
		base.position = Vector3(0, 0.12, 0)
		root.add_child(base)

		# Flag pips (0..2 visible; on capture, flags reset).
		var p0_flags := int(cp.flags_for(0))
		var p1_flags := int(cp.flags_for(1))
		_add_flag_pips(root, Vector3(-0.22, 0.25, 0.0), p0_flags, Color(0.35, 0.85, 1.0))
		_add_flag_pips(root, Vector3(0.22, 0.25, 0.0), p1_flags, Color(1.0, 0.45, 0.45))

	for child in control_points_root.get_children():
		if not alive_names.has(child.name):
			child.queue_free()

func _add_flag_pips(parent: Node3D, origin: Vector3, count: int, color: Color) -> void:
	var n := clampi(count, 0, 3)
	for i in range(n):
		var pip := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = Vector3(0.08, 0.08, 0.08)
		pip.mesh = m
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.9
		pip.material_override = mat
		pip.position = origin + Vector3(0.0, i * 0.10, 0.0)
		parent.add_child(pip)

func _sync_pending_strike_ghosts(gs) -> void:
	if pending_ghosts_root == null:
		return
	for c in pending_ghosts_root.get_children():
		c.queue_free()
	if gs == null:
		return
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
		var cell := Vector2i(cx, cy)
		if not is_in_bounds(cell):
			continue
		var resolve_at := int(pe.get("resolve_at_turn", turn_now))
		var turns_left: int = maxi(0, resolve_at - turn_now)
		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(CELL_SIZE * 0.92, 0.04, CELL_SIZE * 0.92)
		mi.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.55, 0.1, 0.42)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mi.material_override = mat
		mi.position = Vector3((cell.x + 0.5) * CELL_SIZE, 0.18, (cell.y + 0.5) * CELL_SIZE)
		pending_ghosts_root.add_child(mi)
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.pixel_size = 0.008
		label.text = "Δ%d → T%d" % [turns_left, resolve_at]
		label.position = Vector3((cell.x + 0.5) * CELL_SIZE, 0.55, (cell.y + 0.5) * CELL_SIZE)
		label.modulate = Color(1.0, 0.85, 0.35, 1.0)
		label.font_size = 48
		label.outline_size = 8
		label.no_depth_test = true
		pending_ghosts_root.add_child(label)

func _sync_obstacles(gs) -> void:
	if obstacles_root == null:
		return

	var alive_names := {}
	var cells: Array = gs.board.obstacles.keys()
	cells.sort_custom(func(a, b): return (a.x == b.x and a.y < b.y) or (a.x < b.x))
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

		for child in root.get_children():
			child.queue_free()

		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(CELL_SIZE * 0.95, 0.9, CELL_SIZE * 0.95)
		mi.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.25, 0.25, 0.28) if not gs.board.is_destructible(c) else Color(0.45, 0.30, 0.22)
		mat.roughness = 0.95
		mi.material_override = mat
		mi.position = Vector3(0.0, 0.55, 0.0)
		root.add_child(mi)

	for child in obstacles_root.get_children():
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

