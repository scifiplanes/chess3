extends Node

@onready var board_view: Node3D = get_parent()

var _ray_length := 500.0

signal cell_hovered(cell: Vector2i)
signal cell_clicked(cell: Vector2i)

var _press_pos: Vector2 = Vector2.ZERO
var _pressed: bool = false
var _press_time_ms: int = 0
var _move_dist_px: float = 0.0

## Left release qualified as a short click; cleared in `_unhandled_input` when we raycast the board,
## or next idle if GUI (offer buttons, HUD) consumed the release first.
var _pending_board_click: bool = false

const CLICK_MAX_MOVE_PX := 8.0
const CLICK_MAX_TIME_MS := 260

func _ready() -> void:
	# Ensure we receive input callbacks.
	set_process_input(true)
	set_process_unhandled_input(true)

func _input(event: InputEvent) -> void:
	# Hover uses `_input` so it tracks under the cursor even when UI stops propagation.
	# Board **clicks** are finalized in `_unhandled_input` so Control GUI runs first
	# (see ProjectSettings input docs: `_input` → GUI → `_unhandled_input`).
	if event is InputEventMouseMotion:
		# Track drag distance for click-vs-drag disambiguation.
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
				_notify_camera_press(mb.position, true)
			else:
				_notify_camera_press(mb.position, false)
				var dt := Time.get_ticks_msec() - _press_time_ms
				var is_click := _pressed and dt <= CLICK_MAX_TIME_MS and _move_dist_px <= CLICK_MAX_MOVE_PX
				_pressed = false
				_pending_board_click = is_click and not _camera_is_interacting()
				if _pending_board_click:
					call_deferred("_discard_pending_click_if_gui_handled_it")

func _discard_pending_click_if_gui_handled_it() -> void:
	# If a Control consumed the release, `_unhandled_input` never ran — drop stale pending.
	if _pending_board_click:
		_pending_board_click = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			if _pending_board_click:
				_pending_board_click = false
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
			_notify_camera_press(st.position, true)
		else:
			_notify_camera_press(st.position, false)
			var dt := Time.get_ticks_msec() - _press_time_ms
			var is_click := _pressed and dt <= CLICK_MAX_TIME_MS and _move_dist_px <= CLICK_MAX_MOVE_PX
			_pressed = false
			if is_click and not _camera_is_interacting() and _update_hover(true):
				get_viewport().set_input_as_handled()

	elif event is InputEventScreenDrag:
		if _pressed:
			var sd := event as InputEventScreenDrag
			_move_dist_px = max(_move_dist_px, sd.position.distance_to(_press_pos))

func _update_hover(clicked: bool = false) -> bool:
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
	var hit := space.intersect_ray(query)

	if hit.is_empty():
		return false

	var pos: Vector3 = hit.position
	if board_view and board_view.has_method("cell_from_world"):
		var cell: Vector2i = board_view.call("cell_from_world", pos)
		cell_hovered.emit(cell)
		if clicked:
			cell_clicked.emit(cell)
			return true
	return false

func _camera_controller() -> Node:
	# Camera controller is on the parent of the active Camera3D (CameraRig).
	var vp := get_viewport()
	if vp == null:
		return null
	var cam := vp.get_camera_3d()
	if cam == null:
		return null
	var rig := cam.get_parent()
	return rig

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

func _notify_camera_press(pos: Vector2, pressed: bool) -> void:
	var rig := _camera_controller()
	if rig == null:
		return
	if pressed and rig.has_method("begin_press"):
		rig.call("begin_press", pos)
	elif (not pressed) and rig.has_method("end_press"):
		rig.call("end_press")
