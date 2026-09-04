extends Control

var _value: float = 0.5
var _min: float = 0.0
var _max: float = 1.0
var _dragging: bool = false

signal value_changed(v: float)

func setup(value: float, min_v: float, max_v: float) -> void:
	_min = min_v
	_max = max_v
	_value = clampf(value, _min, _max)
	queue_redraw()

func get_value() -> float:
	return _value

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			_set_from_x(mb.position.x)
	elif event is InputEventMouseMotion and _dragging:
		_set_from_x((event as InputEventMouseMotion).position.x)

func _set_from_x(x: float) -> void:
	var t := clampf(x / maxf(1.0, size.x), 0.0, 1.0)
	var nv := lerpf(_min, _max, t)
	if absf(nv - _value) > 0.001:
		_value = nv
		value_changed.emit(_value)
		queue_redraw()

func _draw() -> void:
	var y := size.y * 0.5
	var col := Color(0.95, 0.72, 0.28, 0.45)
	var x := 0.0
	while x < size.x:
		draw_line(Vector2(x, y), Vector2(mini(x + 4.0, size.x), y), col, 1.5, true)
		x += 8.0
	var t := 0.0 if _max <= _min else (_value - _min) / (_max - _min)
	var hx := t * size.x
	var handle := Rect2(Vector2(hx - 5, y - 5), Vector2(10, 10))
	draw_rect(handle, Color(0.95, 0.72, 0.28, 0.95))
