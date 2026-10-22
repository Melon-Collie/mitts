class_name ImageDiff
extends RefCounted

# The render tools' baseline check (pose_capture_runner.gd, keeper_capture.gd).

# Byte-wise compare of two images, a pixel counting as changed past `tolerance`
# (0-255) on any channel. Returns the changed-pixel count, the worst
# single-channel delta, the bounding box of the change, and an overlay tinting
# changed pixels magenta. Bytes rather than get_pixel(): a per-pixel Variant
# round trip over 150 k pixels x 11 poses is minutes of tool runtime for the
# same answer.
static func compare(baseline: Image, current: Image, tolerance: int) -> Dictionary:
	baseline.convert(Image.FORMAT_RGBA8)
	current.convert(Image.FORMAT_RGBA8)
	var overlay: Image = current.duplicate() as Image
	if baseline.get_size() != current.get_size():
		return {"count": -1, "worst": 255, "box": Rect2i(), "overlay": overlay}
	var a: PackedByteArray = baseline.get_data()
	var b: PackedByteArray = current.get_data()
	var width: int = current.get_width()
	var count: int = 0
	var worst: int = 0
	var min_x: int = width
	var min_y: int = current.get_height()
	var max_x: int = -1
	var max_y: int = -1
	@warning_ignore("integer_division")
	var pixels: int = a.size() / 4
	for p: int in pixels:
		var o: int = p * 4
		var d: int = maxi(maxi(absi(a[o] - b[o]), absi(a[o + 1] - b[o + 1])),
				absi(a[o + 2] - b[o + 2]))
		if d <= tolerance:
			continue
		count += 1
		worst = maxi(worst, d)
		@warning_ignore("integer_division")
		var y: int = p / width
		var x: int = p % width
		min_x = mini(min_x, x)
		min_y = mini(min_y, y)
		max_x = maxi(max_x, x)
		max_y = maxi(max_y, y)
		overlay.set_pixel(x, y, Color(1.0, 0.0, 1.0, 1.0))
	var box := Rect2i()
	if max_x >= 0:
		box = Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
	return {"count": count, "worst": worst, "box": box, "overlay": overlay}
