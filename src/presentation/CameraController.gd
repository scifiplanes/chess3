extends Node3D

const GameStateScript = preload("res://src/sim/GameState.gd")

# Camera controls for the 3D board view:
# - Zoom: mouse wheel + trackpad pinch (MagnifyGesture) + touch pinch (2-finger).
# - Rotate: press-and-hold then drag left/right; release snaps to 90°.
# - Pan: trackpad two-finger pan + right-mouse drag + two-finger touch drag.

@export var zoom_speed_wheel: float = 0.8
@export var zoom_speed_pinch: float = 10.0
@export var min_ortho_size: float = 3.0
@export var max_ortho_size: float = 28.0

@export var hold_to_rotate_ms: int = 180
@export var rotate_speed: float = 0.0105 # radians per pixel
@export var rotate_move_deadzone_px: float = 10.0
@export var snap_rotation_to_quarter_turn: bool = false

@export var pan_speed: float = 1.0 # multiplier for screen->world feel

# Clamp uses HUD-safe **play rect** corners (smaller footprint than full viewport). Outset scales
# with zoom-in so max-zoom pan keeps usable slack without clamp fighting every drag.
@export var board_clamp_outset_world: float = 1.15
@export var board_clamp_outset_full_by_zoom_end_size: float = 0.0 ## 0 = derive from min_ortho_size * 2.25
## How far past a snug board-fit the player may zoom out (1.0 = no extra zoom-out).
@export var max_zoom_out_over_fit: float = 1.18

@onready var cam: Camera3D = $Camera3D

var _rotating: bool = false
var _pressing: bool = false
var _press_time_ms: int = 0
var _press_pos: Vector2 = Vector2.ZERO
var _start_yaw: float = 0.0

var _touches := {} # int -> Vector2
var _pinch_active: bool = false
var _pinch_start_dist: float = 0.0
var _pinch_start_size: float = 0.0
var _pinch_last_centroid: Vector2 = Vector2.ZERO

var _panning: bool = false
var _mid_rotating: bool = false
var _alt_rotating: bool = false

var _board_size: Vector2i = GameStateScript.DEFAULT_BOARD_SIZE
const _CELL_SIZE := 1.0

# Orbit state: when rotating, optionally orbit the rig around a world-space pivot
# so rotation feels like it pivots around the board instead of the rig origin.
var _orbit_enabled: bool = false
var _orbit_pivot: Vector3 = Vector3.ZERO

var _cinematic_active: bool = false
var _saved_time_scale: float = 1.0
var _demo_focus_tween: Tween

# Chillout-style knockout replay (organ shed / death).
const _KNOCKOUT_HANDOFF_FRAC := 0.12
const _KNOCKOUT_YAW_SWAY := deg_to_rad(16.0)
var _knockout_running: bool = false
var _knockout_elapsed: float = 0.0
var _knockout_duration: float = 3.2
var _knockout_orbit_end: float = 2.8
var _knockout_focus: Vector3 = Vector3.ZERO
var _knockout_subject: Node3D
var _knockout_rest_pos: Vector3 = Vector3.ZERO
var _knockout_rest_yaw: float = 0.0
var _knockout_rest_size: float = 14.0
var _knockout_handoff_from_pos: Vector3 = Vector3.ZERO
var _knockout_handoff_yaw: float = 0.0
var _knockout_handoff_size: float = 14.0
var _knockout_yaw_sign: float = 1.0
var _knockout_intensity: float = 1.0
var _knockout_handoff_captured: bool = false
var _framing_override: bool = false

func is_cinematic_active() -> bool:
	return _cinematic_active

## Slow-mo orbit chase on organ separation (Chillout exceptional-replay grammar).
func play_separation_sweep(focus_world: Vector3, intensity: float = 1.0, subject: Node3D = null) -> void:
	if cam == null or _knockout_running:
		return
	intensity = clampf(intensity, 0.35, 1.0)
	if _demo_focus_tween != null and _demo_focus_tween.is_valid():
		_demo_focus_tween.kill()
	_knockout_running = true
	_cinematic_active = true
	_knockout_intensity = intensity
	_knockout_subject = subject
	_knockout_focus = focus_world
	_knockout_rest_pos = global_position
	_knockout_rest_yaw = rotation.y
	_knockout_rest_size = cam.size
	_knockout_duration = lerpf(2.8, 3.9, intensity)
	_knockout_orbit_end = _knockout_duration * (1.0 - _KNOCKOUT_HANDOFF_FRAC)
	_knockout_elapsed = 0.0
	_knockout_yaw_sign = 1.0 if randf() < 0.5 else -1.0
	_knockout_handoff_captured = false
	_saved_time_scale = Engine.time_scale
	Engine.time_scale = lerpf(0.14, 0.08, intensity)
	set_process(true)

## Demo spectator: pan + zoom so the action cell(s) sit in the play rect (not board void).
func focus_demo_action(focus_world: Vector3, tightness: float = 0.78) -> void:
	if cam == null or _cinematic_active or _knockout_running:
		return
	tightness = clampf(tightness, 0.35, 0.85)
	if _demo_focus_tween != null and _demo_focus_tween.is_valid():
		_demo_focus_tween.kill()
	var start_pos := global_position
	var start_yaw := rotation.y
	var start_size := cam.size
	var target_size := clampf(start_size * lerpf(0.82, 0.42, tightness), min_ortho_size, start_size)
	var target_yaw := start_yaw + deg_to_rad(lerpf(-4.0, 4.0, tightness)) * (1.0 if randf() < 0.5 else -1.0)
	rotation.y = target_yaw
	_pan_world_to_play_center(focus_world)
	var target_pos := global_position
	global_position = start_pos
	rotation.y = start_yaw
	_demo_focus_tween = create_tween()
	_demo_focus_tween.set_parallel(true)
	_demo_focus_tween.tween_property(self, "global_position", target_pos, 0.52)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_demo_focus_tween.tween_property(self, "rotation:y", target_yaw, 0.52)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_demo_focus_tween.tween_property(cam, "size", target_size, 0.52)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_demo_focus_tween.finished.connect(func() -> void:
		_framing_override = false
		_clamp_pivot_to_board()
	, CONNECT_ONE_SHOT)
	_framing_override = true

func _pan_world_to_play_center(world: Vector3) -> void:
	var vp := get_viewport()
	if vp == null or cam == null:
		return
	const MAX_IT := 10
	const EPS := 2.5
	for _it in MAX_IT:
		var play_rect := _safe_play_rect()
		if play_rect.size.x <= 1.0 or play_rect.size.y <= 1.0:
			return
		var screen_center := play_rect.position + play_rect.size * 0.5
		var world_screen := cam.unproject_position(world)
		var delta_px := screen_center - world_screen
		if delta_px.length() <= EPS:
			break
		_pan_by_pixels(delta_px, world_screen, false)

func _knockout_focus_now() -> Vector3:
	if _knockout_subject != null and is_instance_valid(_knockout_subject):
		return _knockout_subject.global_position + Vector3(0.0, 0.45, 0.0)
	return _knockout_focus

func _apply_knockout_pose(t: float) -> void:
	if cam == null:
		return
	var focus := _knockout_focus_now()
	if t < _knockout_orbit_end:
		var ratio := clampf(t / maxf(_knockout_orbit_end, 0.0001), 0.0, 1.0)
		ratio = smoothstep(0.0, 1.0, ratio)
		var zoom_mul := lerpf(0.72, 0.38, ratio * _knockout_intensity)
		cam.size = clampf(_knockout_rest_size * zoom_mul, min_ortho_size, _knockout_rest_size)
		rotation.y = _knockout_rest_yaw + _knockout_yaw_sign * lerpf(
			-_KNOCKOUT_YAW_SWAY, _KNOCKOUT_YAW_SWAY, ratio
		)
		_pan_world_to_play_center(focus)
		return
	if not _knockout_handoff_captured:
		_knockout_handoff_captured = true
		_knockout_handoff_from_pos = global_position
		_knockout_handoff_yaw = rotation.y
		_knockout_handoff_size = cam.size
	var handoff_span := maxf(_knockout_duration - _knockout_orbit_end, 0.0001)
	var blend := clampf((t - _knockout_orbit_end) / handoff_span, 0.0, 1.0)
	blend = smoothstep(0.0, 1.0, blend)
	global_position = _knockout_handoff_from_pos.lerp(_knockout_rest_pos, blend)
	rotation.y = lerpf(_knockout_handoff_yaw, _knockout_rest_yaw, blend)
	cam.size = lerpf(_knockout_handoff_size, _knockout_rest_size, blend)

func _finish_knockout() -> void:
	_knockout_running = false
	_cinematic_active = false
	_knockout_subject = null
	Engine.time_scale = _saved_time_scale
	global_position = _knockout_rest_pos
	rotation.y = _knockout_rest_yaw
	if cam != null:
		cam.size = _knockout_rest_size
	_clamp_pivot_to_board()

func is_rotating() -> bool:
	return _rotating

func is_interacting() -> bool:
	return _rotating or _panning

func _ready() -> void:
	var settings := get_node_or_null("/root/GameSettings")
	if settings != null:
		pan_speed *= float(settings.camera_pan_sensitivity)
		zoom_speed_wheel *= float(settings.camera_zoom_sensitivity)
		zoom_speed_pinch *= float(settings.camera_zoom_sensitivity)
	add_to_group("camera_controller")
	set_process(true)
	call_deferred("_late_init")

func _late_init() -> void:
	# Defer until the viewport + current camera are fully initialized.
	await get_tree().process_frame
	_refresh_board_bounds()
	_fit_zoom_to_board()
	_recenter_view_to_board_center()
	_clamp_pivot_to_board()

	# Fix: ensure the camera has no roll (tilt) at startup.
	# We only ever change yaw (rig rotation.y). Any non-zero camera roll makes the board look tilted.
	if cam != null and absf(cam.rotation.z) > 0.0001:
		cam.rotation.z = 0.0
	var vp := get_viewport()
	if vp != null:
		vp.size_changed.connect(func():
			_fit_zoom_to_board()
			if not is_interacting():
				_recenter_view_to_board_center()
			_clamp_pivot_to_board()
		)

func refresh_for_board() -> void:
	_refresh_board_bounds()
	_fit_zoom_to_board()
	if not is_interacting():
		_recenter_view_to_board_center()
	_clamp_pivot_to_board()

func _refresh_board_bounds() -> void:
	# Board is a sibling of CameraRig in Main.tscn.
	var board := get_node_or_null("../Board")
	if board != null and board.has_method("grid_size"):
		_board_size = board.call("grid_size") as Vector2i

func _fit_zoom_to_board() -> void:
	# Choose a starting orthographic size that fits the full board inside the
	# HUD-safe play rect, with a small margin.
	if cam == null:
		return
	var play_rect := _safe_play_rect()
	if play_rect.size.x <= 1.0 or play_rect.size.y <= 1.0:
		return

	var w := float(_board_size.x) * _CELL_SIZE
	var h := float(_board_size.y) * _CELL_SIZE
	if w <= 0.0 or h <= 0.0:
		return

	var aspect: float = float(play_rect.size.x) / float(play_rect.size.y)
	# In Godot's orthographic camera, `size` is the half-height in world units.
	var required_half_h: float = h * 0.5
	var required_half_w: float = (w * 0.5) / max(0.00001, aspect)
	var padding: float = 1.06
	var desired: float = max(required_half_h, required_half_w) * padding

	# Cap zoom-out so the board cannot shrink to a speck and be panned into the void.
	var zoom_out_cap: float = desired * maxf(1.0, max_zoom_out_over_fit)
	max_ortho_size = maxf(desired, zoom_out_cap)

	cam.size = clamp(desired, min_ortho_size, max_ortho_size)

func _recenter_view_to_board_center() -> void:
	# Robust centering:
	# - Compute the board center in world space
	# - Project it into screen space
	# - Pan the rig by the pixel delta needed to put it at the center of the
	#   currently visible playable area (excluding HUD panels)
	var vp := get_viewport()
	if vp == null or cam == null:
		return
	if not cam.is_current():
		cam.make_current()

	var play_rect := _safe_play_rect()
	if play_rect.size.x <= 1.0 or play_rect.size.y <= 1.0:
		return
	var screen_center := play_rect.position + play_rect.size * 0.5

	var board := get_node_or_null("../Board")
	var w := float(_board_size.x) * _CELL_SIZE
	var h := float(_board_size.y) * _CELL_SIZE
	var board_origin := Vector3.ZERO
	if board is Node3D:
		board_origin = (board as Node3D).global_position
	# Board tiles are centered at (x+0.5, z+0.5), so board center is still (w/2, h/2).
	var board_center := board_origin + Vector3(w * 0.5, 0.0, h * 0.5)

	var board_screen := cam.unproject_position(board_center)
	var delta_px := screen_center - board_screen
	# Pan using the board's current screen position as the anchor.
	# This makes the recenter operation move the board center to the desired screen center,
	# rather than moving whatever happens to be under the screen center.
	_pan_by_pixels(delta_px, board_screen)

func _safe_play_rect() -> Rect2:
	# Approximate "currently visible playable area" by subtracting HUD-occupied
	# screen space from the viewport rect (top bar, bottom bar, right inspect panel).
	var vp := get_viewport()
	if vp == null:
		return Rect2(Vector2.ZERO, Vector2(1, 1))
	var vr := vp.get_visible_rect()

	var hud := get_node_or_null("../HUD/HUDRoot")
	if hud == null:
		return vr

	var top_h := 0.0
	var bottom_h := 0.0
	var right_w := 0.0
	var left_w := 0.0

	var top := hud.get_node_or_null("TopBar")
	if top is Control and (top as Control).visible:
		var r := (top as Control).get_global_rect()
		top_h = max(top_h, r.end.y - vr.position.y)

	var bottom := hud.get_node_or_null("BottomBar")
	if bottom is Control and (bottom as Control).visible:
		var r2 := (bottom as Control).get_global_rect()
		bottom_h = max(bottom_h, (vr.end.y - r2.position.y))

	var right := hud.get_node_or_null("SquadInspectPanel")
	if right is Control and (right as Control).visible:
		var r3 := (right as Control).get_global_rect()
		# Inspect is a small left chip in K1 — don't carve the whole right gutter.
		if r3.position.x > vr.size.x * 0.55:
			right_w = max(right_w, (vr.end.x - r3.position.x))

	var demo := hud.get_node_or_null("DemoOverlay")
	if demo is Control and (demo as Control).visible:
		for child in (demo as Control).get_children():
			if child is Control and (child as Control).visible:
				var dr := (child as Control).get_global_rect()
				if dr.end.y <= vr.position.y + vr.size.y * 0.45:
					top_h = max(top_h, dr.end.y - vr.position.y)
				elif dr.position.y >= vr.position.y + vr.size.y * 0.55:
					bottom_h = max(bottom_h, vr.end.y - dr.position.y)
				elif child.name == "CommentaryLog":
					left_w = max(left_w, dr.end.x - vr.position.x)

	var x0 := vr.position.x + left_w
	var y0 := vr.position.y + top_h
	var x1 := vr.end.x - right_w
	var y1 := vr.end.y - bottom_h

	# Keep it sane.
	x1 = max(x1, x0 + 1.0)
	y1 = max(y1, y0 + 1.0)

	return Rect2(Vector2(x0, y0), Vector2(x1 - x0, y1 - y0))

func _default_zoom_anchor_screen() -> Vector2:
	var r := _safe_play_rect()
	return r.position + r.size * 0.5

func _process(_delta: float) -> void:
	if _knockout_running:
		var wall_delta := _delta / maxf(Engine.time_scale, 0.001)
		_knockout_elapsed += wall_delta
		_apply_knockout_pose(_knockout_elapsed)
		if _knockout_elapsed >= _knockout_duration:
			_finish_knockout()
		return
	# Start hold-rotate even if the user hasn't moved yet.
	if _pressing and (not _rotating):
		if Time.get_ticks_msec() - _press_time_ms >= hold_to_rotate_ms:
			_rotating = true
			_pressing = false
			_prepare_pivot_for_rotation()

func _input(event: InputEvent) -> void:
	# Mouse wheel zoom.
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		# Left press/release: start hold-to-rotate timer directly on the rig,
		# so it works even if other nodes don't forward press events.
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				begin_press(mb.position)
			else:
				end_press()
			# Don't mark handled: left click is also used for board interaction.
			# InputController will suppress click release if we actually rotated.
			# Still allow other handlers to see it.
			pass

		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom_by(-zoom_speed_wheel, mb.position)
				get_viewport().set_input_as_handled()
				return
			if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_by(zoom_speed_wheel, mb.position)
				get_viewport().set_input_as_handled()
				return

		# Middle mouse: direct drag rotate (fallback).
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_mid_rotating = mb.pressed
			if _mid_rotating:
				_rotating = true
				_pressing = false
				_prepare_pivot_for_rotation()
			else:
				if _rotating:
					_end_rotate(snap_rotation_to_quarter_turn)
			get_viewport().set_input_as_handled()
			return

	# Trackpad pinch zoom (macOS, etc).
	if event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		# mg.factor > 1 means zoom in; map to ortho size reduction.
		var delta := (mg.factor - 1.0) * zoom_speed_pinch
		_zoom_by(-delta, mg.position)
		get_viewport().set_input_as_handled()
		return

	# Trackpad two-finger pan.
	if event is InputEventPanGesture:
		var pg := event as InputEventPanGesture
		_pan_by_pixels(pg.delta)
		get_viewport().set_input_as_handled()
		return

	# Right-mouse drag pan.
	if event is InputEventMouseButton:
		var mb2 := event as InputEventMouseButton
		if mb2.button_index == MOUSE_BUTTON_RIGHT:
			_panning = mb2.pressed
			get_viewport().set_input_as_handled()
			return

	# Touch pinch + hold-rotate (manual multitouch).
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touches[st.index] = st.position
		else:
			_touches.erase(st.index)
			if _touches.size() < 2:
				_pinch_active = false
				# End rotation on touch release as well.
				if _rotating:
					_end_rotate(snap_rotation_to_quarter_turn)
				_panning = false
		_try_begin_pinch()
		return

	if event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		_touches[sd.index] = sd.position
		if _touches.size() >= 2 and _pinch_active:
			_update_pinch_zoom_and_pan()
			get_viewport().set_input_as_handled()
			return

		# Single-touch hold-to-rotate (long-press).
		if _touches.size() == 1:
			_update_hold_rotate(sd.position, sd.relative.x)
		return

	# Mouse hold-to-rotate.
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		# Alt/Option + left-drag rotate (trackpad-friendly fallback).
		_alt_rotating = Input.is_key_pressed(KEY_ALT) and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		if _alt_rotating:
			if not _rotating:
				_rotating = true
				_pressing = false
				_prepare_pivot_for_rotation()
			_apply_rotate_dx(mm.relative.x)
			get_viewport().set_input_as_handled()
			return

		if _mid_rotating and _rotating:
			_apply_rotate_dx(mm.relative.x)
			get_viewport().set_input_as_handled()
			return

		if _panning:
			_pan_by_pixels(mm.relative)
			get_viewport().set_input_as_handled()
			return
		if _pressing:
			_update_hold_rotate(mm.position, mm.relative.x)
		elif _rotating:
			_apply_rotate_dx(mm.relative.x)
			get_viewport().set_input_as_handled()
		return

func begin_press(pos: Vector2) -> void:
	_pressing = true
	_press_time_ms = Time.get_ticks_msec()
	_press_pos = pos
	_start_yaw = rotation.y

func end_press() -> void:
	_pressing = false
	if _rotating:
		_end_rotate(snap_rotation_to_quarter_turn)

func _update_hold_rotate(current_pos: Vector2, dx: float) -> void:
	if _rotating:
		_apply_rotate_dx(dx)
		get_viewport().set_input_as_handled()
		return

	if Time.get_ticks_msec() - _press_time_ms >= hold_to_rotate_ms:
		_rotating = true
		_pressing = false
		_start_yaw = rotation.y
		_prepare_pivot_for_rotation()
		get_viewport().set_input_as_handled()

func _apply_rotate_dx(dx: float) -> void:
	var delta_yaw := dx * rotate_speed
	# Rotate camera yaw.
	rotation.y -= delta_yaw

	# If enabled, orbit the rig around the chosen pivot by the same delta.
	if _orbit_enabled:
		var off := global_position - _orbit_pivot
		off = off.rotated(Vector3.UP, -delta_yaw)
		global_position = _orbit_pivot + off
	_clamp_pivot_to_board()

func _end_rotate(snap: bool) -> void:
	_rotating = false
	# Keep orbit pivot for snap correction below; disable active orbit after.
	var pivot := _orbit_pivot
	var had_pivot := pivot != Vector3.ZERO
	if not snap:
		_orbit_enabled = false
		return
	var step := PI / 2.0
	var yaw_snapped: float = round(rotation.y / step) * step
	var snap_delta: float = yaw_snapped - rotation.y
	rotation.y = yaw_snapped

	# If we were orbiting around a pivot during rotation, apply the same snap delta
	# to the rig position so yaw+position remain consistent (prevents post-snap "jump").
	if had_pivot:
		var off := global_position - pivot
		# Match the yaw change exactly: yaw += snap_delta, so rotate offset by +snap_delta.
		off = off.rotated(Vector3.UP, snap_delta)
		global_position = pivot + off

	_orbit_enabled = false

	# Ensure we don't end up in an out-of-bounds clamp state right after snap.
	_clamp_pivot_to_board()

func _try_begin_pinch() -> void:
	if _touches.size() < 2:
		_pinch_active = false
		return
	if _pinch_active:
		return
	var keys := _touches.keys()
	var a: Vector2 = _touches[keys[0]]
	var b: Vector2 = _touches[keys[1]]
	_pinch_active = true
	_pinch_start_dist = a.distance_to(b)
	_pinch_start_size = cam.size
	_pinch_last_centroid = (a + b) * 0.5

func _update_pinch_zoom_and_pan() -> void:
	var keys := _touches.keys()
	var a: Vector2 = _touches[keys[0]]
	var b: Vector2 = _touches[keys[1]]
	var centroid := (a + b) * 0.5
	var keep: Variant = _screen_to_ground(centroid)
	var d: float = max(1.0, a.distance_to(b))
	var ratio: float = _pinch_start_dist / d
	cam.size = clamp(_pinch_start_size * ratio, min_ortho_size, max_ortho_size)
	if keep != null:
		var g: Vector3 = keep
		var sp := cam.unproject_position(g)
		_pan_by_pixels(centroid - sp, sp)
	_pan_by_pixels(centroid - _pinch_last_centroid)
	_pinch_last_centroid = centroid

func _zoom_by(amount: float, anchor_screen: Variant = null) -> void:
	# Orthographic camera: smaller size == zoom in.
	# Keep the board point under the anchor (cursor / gesture position) stable in
	# screen space so zoom does not feel like the pivot/rig jumps, then clamp.
	if cam == null:
		return
	var anchor: Vector2
	if anchor_screen is Vector2:
		anchor = anchor_screen as Vector2
	else:
		anchor = _default_zoom_anchor_screen()
	var keep: Variant = _screen_to_ground(anchor)
	cam.size = clamp(cam.size + amount, min_ortho_size, max_ortho_size)
	if keep != null:
		var g: Vector3 = keep
		var sp := cam.unproject_position(g)
		_pan_by_pixels(anchor - sp, sp)
	else:
		_clamp_pivot_to_board()

func _screen_to_ground(screen_pos: Vector2) -> Variant:
	# Returns Vector3 hit position on y=0 plane, or null if parallel/no hit.
	if cam == null:
		return null
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var denom := dir.y
	if absf(denom) < 0.00001:
		return null
	var t := -from.y / denom
	if t < 0.0:
		return null
	return from + dir * t

func _pan_by_pixels(delta_px: Vector2, anchor_screen_pos: Vector2 = Vector2.INF, clamp_after: bool = true) -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var rect := vp.get_visible_rect()
	if rect.size.y <= 1.0:
		return

	# Convert screen-space delta into world-space movement on the ground plane (y=0)
	# by intersecting two rays (at anchor and anchor+delta).
	var anchor := anchor_screen_pos
	if anchor == Vector2.INF:
		anchor = rect.position + rect.size * 0.5
	var a = _screen_to_ground(anchor)
	var b = _screen_to_ground(anchor + delta_px)
	if a == null or b == null:
		return
	var wa: Vector3 = a
	var wb: Vector3 = b
	var d: Vector3 = (wa - wb) * pan_speed
	global_position.x += d.x
	global_position.z += d.z
	if clamp_after and not _knockout_running and not _framing_override:
		_clamp_pivot_to_board()

func _viewport_corners_screen(vr: Rect2) -> Array:
	var p := vr.position
	var s := vr.size
	return [p, p + Vector2(s.x, 0), p + Vector2(0, s.y), p + s]

func _clamp_pivot_to_board() -> void:
	# Keep the playfield on-screen:
	# - Zoomed in (view smaller than board): keep the visible ground footprint over the board.
	# - Zoomed out (view larger than board): keep the board inside the view (no void-only pans).
	var vp := get_viewport()
	if vp == null or cam == null:
		return
	var vr := vp.get_visible_rect()
	if vr.size.y <= 1.0:
		return
	var clamp_vr := _safe_play_rect()
	if clamp_vr.size.x <= 1.0 or clamp_vr.size.y <= 1.0:
		clamp_vr = vr

	var board := get_node_or_null("../Board")
	var board_origin := Vector3.ZERO
	if board is Node3D:
		board_origin = (board as Node3D).global_position

	var bw := float(_board_size.x) * _CELL_SIZE
	var bh := float(_board_size.y) * _CELL_SIZE
	var zoom_end: float = board_clamp_outset_full_by_zoom_end_size
	if zoom_end <= 0.0:
		zoom_end = min_ortho_size * 2.25
	# t=1 at min zoom (small ortho size), t=0 by zoom_end — more pan room when zoomed in hard.
	var t_zoom := clampf(1.0 - inverse_lerp(min_ortho_size, zoom_end, float(cam.size)), 0.0, 1.0)
	var pad := board_clamp_outset_world * t_zoom
	var bx0 := board_origin.x - pad
	var bx1 := board_origin.x + bw + pad
	var bz0 := board_origin.z - pad
	var bz1 := board_origin.z + bh + pad
	# Unpadded board — used when the view is wider than the board.
	var board_x0 := board_origin.x
	var board_x1 := board_origin.x + bw
	var board_z0 := board_origin.z
	var board_z1 := board_origin.z + bh

	var corners := _viewport_corners_screen(clamp_vr)

	const MAX_IT := 14
	const EPS := 0.004
	for _it in MAX_IT:
		var gmin_x: float = INF
		var gmax_x: float = -INF
		var gmin_z: float = INF
		var gmax_z: float = -INF
		var hits := 0
		for c in corners:
			var gh: Variant = _screen_to_ground(c)
			if gh == null:
				continue
			var g: Vector3 = gh
			gmin_x = minf(gmin_x, g.x)
			gmax_x = maxf(gmax_x, g.x)
			gmin_z = minf(gmin_z, g.z)
			gmax_z = maxf(gmax_z, g.z)
			hits += 1
		if hits < 2:
			return

		var span_x := gmax_x - gmin_x
		var span_z := gmax_z - gmin_z
		var wide_x := span_x > bw + 0.0001
		var wide_z := span_z > bh + 0.0001

		var dx := 0.0
		var dz := 0.0
		if wide_x:
			# Keep board inside the view (prevent panning playfield off-screen).
			if board_x0 < gmin_x:
				dx += board_x0 - gmin_x
			if board_x1 > gmax_x:
				dx += board_x1 - gmax_x
		else:
			# Keep view footprint over the board.
			if gmin_x < bx0:
				dx += bx0 - gmin_x
			if gmax_x > bx1:
				dx -= gmax_x - bx1
		if wide_z:
			if board_z0 < gmin_z:
				dz += board_z0 - gmin_z
			if board_z1 > gmax_z:
				dz += board_z1 - gmax_z
		else:
			if gmin_z < bz0:
				dz += bz0 - gmin_z
			if gmax_z > bz1:
				dz -= gmax_z - bz1

		if absf(dx) < EPS and absf(dz) < EPS:
			break
		global_position.x += dx
		global_position.z += dz

func _prepare_pivot_for_rotation() -> void:
	# Choose an orbit pivot for rotation so the rotation doesn't feel offset.
	# Important: do NOT teleport the rig here (that causes a visible jump).
	var vp := get_viewport()
	if vp == null:
		return
	var vr := vp.get_visible_rect()
	if vr.size.y <= 1.0:
		return
	var board := get_node_or_null("../Board")
	var board_origin := Vector3.ZERO
	if board is Node3D:
		board_origin = (board as Node3D).global_position
	var w := float(_board_size.x) * _CELL_SIZE
	var h := float(_board_size.y) * _CELL_SIZE
	var board_center := board_origin + Vector3(w * 0.5, 0.0, h * 0.5)
	var aspect := vr.size.x / vr.size.y
	var half_h := float(cam.size)
	var half_w := float(cam.size) * aspect
	var min_x := board_origin.x + half_w
	var max_x := board_origin.x + w - half_w
	var min_z := board_origin.z + half_h
	var max_z := board_origin.z + h - half_h
	var wide_x := min_x > max_x
	var wide_z := min_z > max_z

	# Always orbit around board center during rotation. This fixes the "offset pivot"
	# without snapping the camera into a corner.
	_orbit_enabled = true
	_orbit_pivot = board_center
