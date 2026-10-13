extends GutTest

# The mask's face opening is baked as dark facet tint and the cage is a separate
# mesh laid over it, so nothing but this keeps the cage's frame on the edge of
# the dark: move one and the cage stops short of it or hangs over the paint.
# The tint is decided per facet at its centroid, so the opening's edge is the
# outline of whole facet rows and columns.



func _tinted(deg: float, y: float) -> bool:
	var sec: Vector2 = GoalieMeshBuilder._mask_section(y)
	var th: float = deg_to_rad(deg)
	return GoalieMeshBuilder._mask_tint(Vector3(sin(th) * sec.x, y, -cos(th) * sec.y), Vector3.ZERO) \
			== GoalieMeshBuilder._CAGE_TINT


func test_the_frame_sits_on_the_edge_of_the_opening() -> void:
	var column: float = 360.0 / float(GoalieMeshBuilder._MASK_SEGS)
	var top: float = NAN
	var bottom: float = NAN
	for i: int in GoalieMeshBuilder._MASK_STATIONS.size() - 1:
		var hi: float = GoalieMeshBuilder._MASK_STATIONS[i].x
		var lo: float = GoalieMeshBuilder._MASK_STATIONS[i + 1].x
		if _tinted(column * 0.5, (hi + lo) * 0.5):
			if is_nan(top):
				top = hi
			bottom = lo
	assert_almost_eq(GoalieMeshBuilder._CAGE_EDGE_TOP_Y, top, 1e-6, "the top bar is the opening's top")
	assert_almost_eq(GoalieMeshBuilder._CAGE_EDGE_BOT_Y, bottom, 1e-6, "the bottom bar is its bottom")
	var mid: float = (top + bottom) * 0.5
	var columns: int = 0
	while _tinted(column * (columns + 0.5), mid):
		columns += 1
	assert_almost_eq(GoalieMeshBuilder._CAGE_EDGE_DEG, column * columns, 1e-4,
			"the side bars are on the opening's last tinted column")
