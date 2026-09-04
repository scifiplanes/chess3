extends Node

@onready var board_view: Node3D = get_parent()

var _ray_length := 500.0

signal cell_hovered(cell: Vector2i)
signal cell_clicked(cell: Vector2i)

var _press_pos: Vector2 = Vector2.ZERO
var _pressed: bool = false
var _press_time_ms: int = 0
var _move_dist_px: float = 0.0
var _ui_owns_pointer: bool = false

## Left release qualified as a short click; cleared in `_unhandled_input` when we raycast the board,
## or next idle if GUI (offer buttons, HUD) consumed the release first.
var _pending_board_click: bool = false

const CLICK_MAX_MOVE_PX := 8.0
const CLICK_MAX_TIME_MS := 260
const CLEAR_HOVER := Vector2i(-999, -999)
var _emitted_hover_cell: Vector2i = CLEAR_HOVER

func _ready() -> void:
	set_process_input(true)
	set_process_unhandled_input(true)
	set_process(true)

func _process(_delta: float) -> void:
	# Keep ownership in sync even when the mouse is still (GUI hover can change without motion).
	if _pointer_over_blocking_ui():
		_clear_board_hover()
	elif _ui_owns_pointer:
		_ui_owns_pointer = false
		_update_hover(false)

func _emit_hover(cell: Vector2i) -> void:
	if cell == _emitted_hover_cell:
		return
	_emitted_hover_cell = cell
	cell_hovered.emit(cell)

func _input(event: InputEvent) -> void:
	if _camera_cinematic_blocks_input():
		return
	# Hover uses `_input` so it tracks under the cursor even when UI stops propagation.
	# Board **clicks** are finalized in `_unhandled_input` so Control GUI runs first.
	if event is InputEventMouseMotion:
		if _pressed:
			var mm := event as InputEventMouseMotion
			_move_dist_px = max(_move_dist_px, mm.position.distance_to(_press_pos))
		_update_hover()

	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_pressed = true
				_press_time_ms = Time.get_ticks_msec()
				_press_pos = mb.position
				_move_dist_px = 0.0
				if not _pointer_over_blocking_ui():
					_notify_camera_press(mb.position, true)
			else:
				_notify_camera_press(mb.position, false)
				var dt := Time.get_ticks_msec() - _press_time_ms
				var is_click := _pressed and dt <= CLICK_MAX_TIME_MS and _move_dist_px <= CLICK_MAX_MOVE_PX
				_pressed = false
				_pending_board_click = is_click and not _camera_is_interacting() and not _pointer_over_blocking_ui()
				if _pending_board_click:
					call_deferred("_discard_pending_click_if_gui_handled_it")

func _discard_pending_click_if_gui_handled_it() -> void:
	if _pending_board_click:
		_pending_board_click = false

func _unhandled_input(event: InputEvent) -> void:
	if _camera_cinematic_blocks_input():
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			if _pending_board_click:
				_pending_board_click = false
				if _pointer_over_blocking_ui():
					_clear_board_hover()
					return
				if _update_hover(true):
					get_viewport().set_input_as_handled()
			return

	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_pressed = true
			_press_time_ms = Time.get_ticks_msec()
			_press_pos = st.position
			_move_dist_px = 0.0
			if not _pointer_over_blocking_ui():
				_notify_camera_press(st.position, true)
		else:
			_notify_camera_press(st.position, false)
			var dt := Time.get_ticks_msec() - _press_time_ms
			var is_click := _pressed and dt <= CLICK_MAX_TIME_MS and _move_dist_px <= CLICK_MAX_MOVE_PX
			_pressed = false
			if is_click and not _camera_is_interacting() and not _pointer_over_blocking_ui() and _update_hover(true):
				get_viewport().set_input_as_handled()

	elif event is InputEventScreenDrag:
		if _pressed:
			var sd := event as InputEventScreenDrag
			_move_dist_px = max(_move_dist_px, sd.position.distance_to(_press_pos))

func _pointer_over_blocking_ui() -> bool:
	var vp := get_viewport()
	if vp == null:
		return false
	var mouse := vp.get_mouse_position()
	# Live hit-test — more reliable during `_input` than stale gui_get_hovered_control().
	if vp.has_method("gui_find_control"):
		var found: Variant = vp.call("gui_find_control", mouse)
		if found is Control and _control_blocks_board(found as Control):
			return true
	var hovered := vp.gui_get_hovered_control()
	if hovered != null and _control_blocks_board(hovered):
		return true
	# Fallback: any STOP/PASS HUD control under the cursor (covers IGNORE parents with STOP kids).
	return _hud_control_under_point(mouse) != null

func _control_blocks_board(c: Control) -> bool:
	if c == null:
		return false
	# Labels/icons often IGNORE; walk up to a registered chrome rect.
	var cur: Node = c
	while cur != null:
		if cur is Control and (cur as Control).is_in_group("ui_blocks_board_hover"):
			var blocker := cur as Control
			if blocker.mouse_filter != Control.MOUSE_FILTER_IGNORE:
				return true
		if cur is CanvasLayer and str(cur.name) == "HUD":
			break
		if str(cur.name) == "HUDRoot":
			# Keep walking; HUDRoot itself is IGNORE by design.
			pass
		cur = cur.get_parent()
	return _is_under_hud(c) and c.mouse_filter != Control.MOUSE_FILTER_IGNORE

func _is_under_hud(n: Node) -> bool:
	var cur: Node = n
	while cur != null:
		if cur is CanvasLayer and str(cur.name) == "HUD":
			return true
		if str(cur.name) == "HUDRoot":
			return true
		cur = cur.get_parent()
	return false

func _hud_control_under_point(screen_pos: Vector2) -> Control:
	var tree := get_tree()
	if tree == null:
		return null
	# Prefer explicit blockers (buttons, trays, panels).
	for n in tree.get_nodes_in_group("ui_blocks_board_hover"):
		if n is Control:
			var c := n as Control
			if not c.visible or not c.is_visible_in_tree():
				continue
			if c.mouse_filter == Control.MOUSE_FILTER_IGNORE:
				continue
			if c.get_global_rect().has_point(screen_pos):
				return c
	return null

func _clear_board_hover() -> void:
	if not _ui_owns_pointer:
		_ui_owns_pointer = true
		_emit_hover(CLEAR_HOVER)

func _update_hover(clicked: bool = false) -> bool:
	if _pointer_over_blocking_ui():
		_clear_board_hover()
		return false
	_ui_owns_pointer = false

	var vp := get_viewport()
	if vp == null:
		return false
	var cam := vp.get_camera_3d()
	if cam == null:
		return false

	var mouse := vp.get_mouse_position()
	var from := cam.project_ray_origin(mouse)
	var dir := cam.project_ray_normal(mouse)
	var to := from + dir * _ray_length

	var space := cam.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	# Floor tiles only (layer 1). Organs are layer 2 — hitting them mapped clicks to
	# neighboring cells and caused occupied-slot attach to reject-then-accept.
	query.collision_mask = 1
	var hit := space.intersect_ray(query)

	if hit.is_empty():
		_emit_hover(CLEAR_HOVER)
		return false

	var pos: Vector3 = hit.position
	if board_view and board_view.has_method("cell_from_world"):
		var cell: Vector2i = board_view.call("cell_from_world", pos)
		_emit_hover(cell)
		if clicked:
			cell_clicked.emit(cell)
			return true
	return false

func _camera_controller() -> Node:
	var vp := get_viewport()
	if vp == null:
		return null
	var cam := vp.get_camera_3d()
	if cam == null:
		return null
	return cam.get_parent()

func _camera_is_rotating() -> bool:
	var rig := _camera_controller()
	if rig != null and rig.has_method("is_rotating"):
		return bool(rig.call("is_rotating"))
	return false

func _camera_is_interacting() -> bool:
	var rig := _camera_controller()
	if rig != null and rig.has_method("is_interacting"):
		return bool(rig.call("is_interacting"))
	return _camera_is_rotating()

func _camera_cinematic_blocks_input() -> bool:
	var rig := _camera_controller()
	if rig != null and rig.has_method("is_cinematic_active"):
		return bool(rig.call("is_cinematic_active"))
	return false

func _notify_camera_press(pos: Vector2, pressed: bool) -> void:
	var rig := _camera_controller()
	if rig == null:
		return
	if pressed and rig.has_method("begin_press"):
		rig.call("begin_press", pos)
	elif (not pressed) and rig.has_method("end_press"):
		rig.call("end_press")
