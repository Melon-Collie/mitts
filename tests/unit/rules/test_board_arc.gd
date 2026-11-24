extends GutTest

# BoardArc — arc length along the boards' centerline and its inverse.

const HALF_W: float = GameRules.RINK_HALF_WIDTH
const HALF_L: float = GameRules.RINK_HALF_LENGTH
const R: float = GameRules.CORNER_RADIUS


func _perimeter() -> float:
	return BoardArc.perimeter(HALF_W, HALF_L, R)


# Signed gap between two arcs on the loop, shortest way round.
func _arc_gap(a: float, b: float) -> float:
	var p: float = _perimeter()
	return fposmod(a - b + p / 2.0, p) - p / 2.0


func test_point_and_arc_round_trip_all_the_way_round() -> void:
	var p: float = _perimeter()
	for i: int in 400:
		var s: float = p * (float(i) + 0.37) / 400.0
		var at: Vector2 = BoardArc.point_at(s, HALF_W, HALF_L, R)
		assert_almost_eq(_arc_gap(BoardArc.arc_at(at, HALF_W, HALF_L, R), s), 0.0, 1e-4,
				"arc %.3f m" % s)


# A puck touching the boards sits inside them; it must land on the stretch of
# wall it is touching, not the one across a corner's diagonal.
func test_a_point_inside_projects_onto_the_wall_it_faces() -> void:
	var p: float = _perimeter()
	for i: int in 400:
		var s: float = p * (float(i) + 0.5) / 400.0
		var on: Vector2 = BoardArc.point_at(s, HALF_W, HALF_L, R)
		var inside: Vector2 = on - _outward(s) * 0.3
		assert_almost_eq(_arc_gap(BoardArc.arc_at(inside, HALF_W, HALF_L, R), s), 0.0, 1e-3,
				"arc %.3f m, 0.3 m in" % s)


func test_arc_starts_at_the_south_end_of_the_east_wall_and_runs_north() -> void:
	assert_almost_eq(BoardArc.arc_at(Vector2(HALF_W, -(HALF_L - R)), HALF_W, HALF_L, R),
			0.0, 1e-4)
	assert_almost_eq(BoardArc.arc_at(Vector2(HALF_W, 0.0), HALF_W, HALF_L, R),
			HALF_L - R, 1e-4)


func test_perimeter_is_four_straights_and_a_circle() -> void:
	var straights: float = 2.0 * (2.0 * (HALF_L - R)) + 2.0 * (2.0 * (HALF_W - R))
	assert_almost_eq(_perimeter(), straights + TAU * R, 1e-4)


func _outward(s: float) -> Vector2:
	var a: Vector2 = BoardArc.point_at(s - 0.01, HALF_W, HALF_L, R)
	var b: Vector2 = BoardArc.point_at(s + 0.01, HALF_W, HALF_L, R)
	var along: Vector2 = (b - a).normalized()
	# Counter-clockwise travel: the outside of the loop is to the right.
	return Vector2(along.y, -along.x)
