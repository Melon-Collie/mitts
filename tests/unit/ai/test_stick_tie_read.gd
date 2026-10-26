extends GutTest

# AIStickTieRead: the geometry a covering bot ties a man's stick on, and the pull
# a tied bot makes to break one.


func test_a_feed_reaches_the_man_only_along_its_path() -> void:
	var puck := Vector3(0.0, 0.0, 10.0)
	var vel := Vector3(0.0, 0.0, -12.0)
	assert_true(AIStickTieRead.path_passes_within(puck, vel, Vector3(0.3, 0.0, 2.0), 0.6))
	assert_false(AIStickTieRead.path_passes_within(puck, vel, Vector3(3.0, 0.0, 2.0), 0.6),
			"wide of the path")
	assert_false(AIStickTieRead.path_passes_within(puck, vel, Vector3(0.0, 0.0, 14.0), 0.6),
			"behind the puck")
	assert_false(AIStickTieRead.path_passes_within(puck, vel, Vector3(0.0, 0.0, -40.0), 0.6),
			"past the read horizon")


func test_a_lane_is_open_unless_a_defender_reaches_the_line() -> void:
	var carrier := Vector3(0.0, 0.0, 10.0)
	var man := Vector3(0.0, 0.0, 0.0)
	var reach: Array[float] = [GameRules.DEFAULT_STICK_LENGTH_M]
	assert_true(AIStickTieRead.lane_open(carrier, man,
			[Vector3(3.0, 0.0, 5.0)] as Array[Vector3], reach))
	assert_false(AIStickTieRead.lane_open(carrier, man,
			[Vector3(1.0, 0.0, 5.0)] as Array[Vector3], reach))


func test_the_shaft_is_in_reach_by_its_nearest_point() -> void:
	var hand := Vector3(0.0, 1.0, 0.0)
	var blade := Vector3(0.0, 0.03, -1.2)
	assert_true(AIStickTieRead.shaft_in_reach(Vector3(1.5, 0.0, -1.0), hand, blade, 2.0))
	assert_false(AIStickTieRead.shaft_in_reach(Vector3(4.0, 0.0, -1.0), hand, blade, 2.0))


func test_the_yank_pulls_straight_away_from_the_tying_stick() -> void:
	var self_pos := Vector3.ZERO
	var self_blade := Vector3(0.0, 0.03, -1.2)
	var tier_blade := Vector3(0.5, 0.03, -1.2)
	var aim: Vector3 = AIStickTieRead.yank_aim(self_pos, self_blade, tier_blade, 1.6)
	assert_lt(aim.x, self_blade.x, "away from the tier")
	assert_lte(Vector2(aim.x, aim.z).length(), 1.6 + 1e-4, "inside the stick's own reach")
