extends Control

func _draw() -> void:
	var y := size.y * 0.5
	var col := Color(0.95, 0.72, 0.28, 0.45)
	for side in [-1, 1]:
		var x := size.x * 0.5 if side > 0 else size.x * 0.5
		var start_x := size.x * 0.5
		var end_x := size.x if side > 0 else 0.0
		var step := 6.0 * float(side)
		var px := start_x
		while (side > 0 and px < end_x) or (side < 0 and px > end_x):
			draw_line(Vector2(px, y), Vector2(px + step * 0.55, y), col, 1.5, true)
			px += step
	draw_circle(Vector2(size.x * 0.5, y), 4.0, Color(0.95, 0.72, 0.28, 0.9))
