extends SceneTree

## Capture one frame with post-dither on vs off; print mean abs delta.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var err := change_scene_to_file("res://scenes/Main.tscn")
	if err != OK:
		push_error("Failed to load Main.tscn: %s" % str(err))
		quit(1)
		return
	for i in 12:
		await process_frame

	var dpp := root.get_node_or_null("DitherPostProcess")
	if dpp == null:
		push_error("DitherPostProcess missing")
		quit(1)
		return

	dpp.push_settings(true, 0.85, 0.4, 2.0, 6.0, 4.0, 0.0, 1.0, 1.0, 0.0, 1.0)
	for i in 4:
		await process_frame
	var img_on := _grab()
	if img_on == null:
		push_error("grab on failed")
		quit(1)
		return
	img_on.save_png("user://dither_on.png")

	dpp.push_settings(false, 0.0, 0.6, 1.0, 10.0, 4.0, 4.0, 1.0, 1.0, 0.0, 1.0)
	for i in 4:
		await process_frame
	var img_off := _grab()
	if img_off == null:
		push_error("grab off failed")
		quit(1)
		return
	img_off.save_png("user://dither_off.png")

	var w: int = mini(img_on.get_width(), img_off.get_width())
	var h: int = mini(img_on.get_height(), img_off.get_height())
	var acc := 0.0
	var n := 0
	var step := 4
	for y in range(0, h, step):
		for x in range(0, w, step):
			var a: Color = img_on.get_pixel(x, y)
			var b: Color = img_off.get_pixel(x, y)
			acc += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
			n += 1
	var mean := acc / float(maxi(n, 1))
	print("dither_delta_mean=%.6f samples=%d size=%dx%d" % [mean, n, w, h])
	print("saved user://dither_on.png user://dither_off.png")
	if mean < 0.002:
		push_error("Post dither produced negligible frame delta — effect likely not applied")
		quit(1)
		return
	quit(0)

func _grab() -> Image:
	var vp := root.get_viewport()
	if vp == null:
		return null
	var tex := vp.get_texture()
	if tex == null:
		return null
	return tex.get_image()
