extends SceneTree

## Headless smoke: confirm DitherPostProcess overlay is live and sized.

func _initialize() -> void:
	call_deferred("_check")

func _check() -> void:
	await process_frame
	await process_frame
	var dpp := root.get_node_or_null("DitherPostProcess")
	if dpp == null:
		push_error("DitherPostProcess autoload missing")
		quit(1)
		return
	var layer: CanvasLayer = dpp.get_node_or_null("DitherPostProcessLayer")
	if layer == null:
		push_error("DitherPostProcessLayer missing")
		quit(1)
		return
	var bbc := layer.get_node_or_null("DitherBackBuffer")
	var rect: ColorRect = layer.get_node_or_null("DitherRect")
	if bbc == null:
		push_error("DitherBackBuffer missing")
		quit(1)
		return
	if rect == null:
		push_error("DitherRect missing")
		quit(1)
		return
	var sz: Vector2 = rect.size
	print("dither_ok enabled=%s layer_vis=%s rect_vis=%s size=%s strength=%.2f mat=%s" % [
		str(dpp.enabled),
		str(layer.visible),
		str(rect.visible),
		str(sz),
		dpp.strength,
		str(rect.material != null)
	])
	if sz.x < 8.0 or sz.y < 8.0:
		push_error("DitherRect size too small: %s" % str(sz))
		quit(1)
		return
	quit(0)
