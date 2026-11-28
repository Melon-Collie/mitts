extends GutTest

# BoardPuckMarks — where a puck mark lands on the boards, and that every peer
# paints the same one.

var _rink: HockeyRink = null
var _stations: Array = []
var _cumulative: PackedFloat32Array = PackedFloat32Array()


func before_all() -> void:
	_rink = HockeyRink.new()
	_stations = _rink._build_perimeter_stations(_rink.corner_segments)
	_cumulative = BoardAdBandBuilder.cumulative_arcs(_stations)


func after_all() -> void:
	_rink.free()


func _board_top() -> float:
	return _rink.wall_height - HockeyRink.CAP_RAIL_HEIGHT


func _ribbon() -> ArrayMesh:
	var board_face: float = _rink.wall_thickness / 2.0
	return BoardPuckMarks.build_ribbon(_stations, board_face,
			board_face + HockeyRink.KICKPLATE_PROTRUSION, _rink.kickplate_height, _board_top())


func _marks() -> BoardPuckMarks:
	var marks := BoardPuckMarks.new()
	add_child_autofree(marks)
	marks.setup(_ribbon(), _rink.rink_width / 2.0, _rink.rink_length / 2.0,
			_rink.corner_radius, _board_top())
	return marks


func _arc(xz: Vector2) -> float:
	return BoardArc.arc_at(xz, _rink.rink_width / 2.0, _rink.rink_length / 2.0,
			_rink.corner_radius)


# A mark is placed by BoardArc and the ribbon is laid by the arc over the rink's
# own stations; the two must name the same spot on the wall.
func test_board_arc_walks_the_rink_stations() -> void:
	var perimeter: float = BoardAdBandBuilder.perimeter_of(_cumulative)
	assert_almost_eq(BoardArc.perimeter(_rink.rink_width / 2.0, _rink.rink_length / 2.0,
			_rink.corner_radius), perimeter, 0.005)
	for i: int in 300:
		var s: float = perimeter * (float(i) + 0.5) / 300.0
		var at: Vector2 = BoardAdBandBuilder.sample_pos(_stations, _cumulative, s)
		assert_almost_eq(_arc(at), s, 0.005, "arc %.2f m" % s)


func test_the_ribbon_reads_the_canvas_where_marks_are_painted() -> void:
	var marks: BoardPuckMarks = _marks()
	var ribbon: ArrayMesh = _ribbon()
	var canvas := Vector2(marks._viewport.size)
	var checked: int = 0
	for surface: int in ribbon.get_surface_count():
		var arrays: Array = ribbon.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		for i: int in range(0, verts.size(), 7):
			# A row's two ends are the same place on the wall in two rows.
			if uvs[i].x < 0.01 or uvs[i].x > 0.99:
				continue
			var painted: Vector2 = marks._canvas_point(
					_arc(Vector2(verts[i].x, verts[i].z)), verts[i].y)
			assert_almost_eq(uvs[i] * canvas, painted, Vector2.ONE,
					"ribbon vertex %s" % verts[i])
			checked += 1
	assert_gt(checked, 100)


func test_every_peer_paints_the_same_mark() -> void:
	var host: BoardPuckMarks = _marks()
	var client: BoardPuckMarks = _marks()
	assert_eq(host._pending, client._pending, "the worn boards a match starts on")
	var hit := Vector3(12.9, 0.0127, -21.4)
	host.add_mark(hit, 14.0)
	client.add_mark(hit, 14.0)
	assert_eq(host._pending, client._pending)


func test_a_soft_touch_leaves_no_mark() -> void:
	var marks: BoardPuckMarks = _marks()
	var before: int = marks._pending.size()
	marks.add_mark(Vector3(12.9, 0.0127, 0.0), BoardPuckMarks.MARK_MIN_SPEED * 0.5)
	assert_eq(marks._pending.size(), before)
	marks.add_mark(Vector3(12.9, 0.0127, 0.0), BoardPuckMarks.MARK_MIN_SPEED * 2.0)
	assert_gt(marks._pending.size(), before)
