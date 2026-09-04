extends Control

func _draw() -> void:
	var y := size.y * 0.5
	var w := maxf(1.0, size.x)
	var col := Color(0.95, 0.72, 0.28, 0.55)
	draw_line(Vector2(0, y), Vector2(w, y), col, 1.0, true)
	draw_circle(Vector2(0, y), 3.0, Color(0.95, 0.72, 0.28, 0.85))
	draw_circle(Vector2(w, y), 3.0, Color(0.95, 0.72, 0.28, 0.85))
