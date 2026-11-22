extends GutTest

# Where a station may be put (AIStationSearch.is_legal_position): on ice a body
# can stand on, rink side of both goal lines, out of both creases.

const INSET: float = AIStationSearch.RINK_INSET_M
# A body's width inside the side boards and a stride short of the goal line's
# buffer: inside the bounding box, outside the corner's arc.
const IN_THE_ARC := Vector3(GameRules.INNER_HALF_WIDTH - 2.0 * INSET, 0.0,
		GameRules.GOAL_LINE_Z - 2.0 * AIStationSearch.GOAL_LINE_BUFFER_M)


func test_the_rounded_corner_is_not_ice() -> void:
	assert_gt(IN_THE_ARC.z, GameRules.CORNER_CENTER_Z, "the point is in the corner")
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var p := Vector3(sx * IN_THE_ARC.x, 0.0, sz * IN_THE_ARC.z)
			assert_false(AIStationSearch.is_legal_position(p), "%s is outside the arc" % p)
			assert_false(AIStationSearch.is_legal_ice(p), "%s is outside the arc" % p)


func test_the_same_distance_off_the_straight_boards_is_ice() -> void:
	assert_true(AIStationSearch.is_legal_position(Vector3(IN_THE_ARC.x, 0.0, 18.0)))
	assert_true(AIStationSearch.is_legal_position(Vector3(-IN_THE_ARC.x, 0.0, 0.0)))


func test_a_legal_position_is_one_a_body_stands_on() -> void:
	# Every legal point is its own clamp to the surface a body's width in: the
	# station search and the body's wall agree on where the ice ends.
	var x: float = -GameRules.RINK_HALF_WIDTH
	while x <= GameRules.RINK_HALF_WIDTH:
		var z: float = -GameRules.GOAL_LINE_Z
		while z <= GameRules.GOAL_LINE_Z:
			var xz := Vector2(x, z)
			if AIStationSearch.is_legal_position(Vector3(x, 0.0, z)):
				assert_true(GameRules.clamp_to_rink_inner(xz, INSET).is_equal_approx(xz),
						"%s is legal and off the surface" % xz)
			z += 0.5
		x += 0.5


func test_past_a_goal_line_and_in_a_crease_are_not_stations() -> void:
	assert_false(AIStationSearch.is_legal_position(
			Vector3(3.0, 0.0, GameRules.GOAL_LINE_Z + 1.0)), "behind the net")
	assert_false(AIStationSearch.is_legal_position(
			Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z + 1.2)), "in the crease")
