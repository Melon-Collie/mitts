extends GutTest

# The slapshot's stance geometry (SlapperRules): where the puck is struck and
# which way the hips face for a shot line.

const RIGHT_BLADE: float = 1.0
const LEFT_BLADE: float = -1.0
const SIDE_ON: float = PI * 0.5


# The top hand's shoulder for a blade on `side`: on the other side.
func _top_shoulder(side: float) -> Vector2:
	return Vector2(-side * 0.22, 0.0)


func test_the_puck_is_struck_in_front_of_the_body() -> void:
	for side: float in [RIGHT_BLADE, LEFT_BLADE]:
		var spot: Vector2 = SlapperRules.strike_spot_local(_top_shoulder(side), 1.0, 0.3, 0.1, side)
		assert_lt(spot.y, -1.0, "ahead of the body (%s)" % spot)
		assert_almost_eq(signf(spot.x), -side, 0.001,
				"toward the front foot, the off-stick side (%s)" % spot)


func test_a_longer_stick_strikes_further_out() -> void:
	var short: Vector2 = SlapperRules.strike_spot_local(_top_shoulder(RIGHT_BLADE), 0.9, 0.3, 0.1, RIGHT_BLADE)
	var long: Vector2 = SlapperRules.strike_spot_local(_top_shoulder(RIGHT_BLADE), 1.1, 0.3, 0.1, RIGHT_BLADE)
	assert_lt(long.y, short.y)


func test_the_spot_is_a_stick_and_half_a_blade_from_the_top_hand() -> void:
	var shoulder: Vector2 = _top_shoulder(RIGHT_BLADE)
	var spot: Vector2 = SlapperRules.strike_spot_local(shoulder, 1.0, 0.3, 0.1, RIGHT_BLADE)
	assert_almost_eq(spot.distance_to(shoulder), 1.15, 0.0001)


func test_side_on_the_top_hands_shoulder_points_down_the_line() -> void:
	var shot := Vector2(0.0, -1.0)
	for side: float in [RIGHT_BLADE, LEFT_BLADE]:
		var facing: Vector2 = SlapperRules.stance_facing(shot, side, SIDE_ON)
		assert_almost_eq(facing.dot(shot), 0.0, 0.0001, "perpendicular to the line")
		# The top hand's shoulder is off-stick: local x = −side.
		var shoulder_dir: Vector2 = SlapperRules.local_to_world(Vector2(-side, 0.0), facing)
		assert_almost_eq(shoulder_dir.dot(shot), 1.0, 0.0001,
				"blade %+.0f: the front shoulder points at the target" % side)


func test_an_unopened_stance_faces_the_line() -> void:
	var shot := Vector2(0.6, -0.8)
	assert_almost_eq(SlapperRules.stance_facing(shot, RIGHT_BLADE, 0.0).dot(shot), 1.0, 0.0001)


func test_local_to_world_matches_the_skaters_frame() -> void:
	# A skater facing world −Z has its right (+X) at world +X and its front at −Z.
	var facing := Vector2(0.0, -1.0)
	assert_almost_eq(SlapperRules.local_to_world(Vector2(1.0, 0.0), facing), Vector2(1.0, 0.0), Vector2.ONE * 0.0001)
	assert_almost_eq(SlapperRules.local_to_world(Vector2(0.0, -1.0), facing), Vector2(0.0, -1.0), Vector2.ONE * 0.0001)


func test_the_aim_runs_from_the_strike_spot_to_the_target() -> void:
	var skater := Vector2(3.0, 5.0)
	var strike := Vector2(-0.1, -1.15)
	var target := Vector2(-4.0, -12.0)
	var dir: Vector2 = SlapperRules.aim_from_strike(skater, target, strike, RIGHT_BLADE, SIDE_ON)
	var spot: Vector2 = skater + SlapperRules.strike_offset(dir, strike, RIGHT_BLADE, SIDE_ON)
	assert_almost_eq(dir.angle_to(target - spot), 0.0, deg_to_rad(0.5),
			"the line from where the puck is struck passes through the target")


func test_the_recovery_grows_with_the_wind_up() -> void:
	assert_almost_eq(SlapperRules.recover_time(0.0, 0.1, 0.45), 0.1, 0.0001)
	assert_almost_eq(SlapperRules.recover_time(1.0, 0.1, 0.45), 0.45, 0.0001)
	assert_lt(SlapperRules.recover_time(0.3, 0.1, 0.45), SlapperRules.recover_time(0.7, 0.1, 0.45))
	assert_almost_eq(SlapperRules.recover_time(2.0, 0.1, 0.45), 0.45, 0.0001, "past the top is the top")


func test_the_aim_turns_off_the_line_no_further_than_the_arc() -> void:
	var line := Vector2(0.0, -1.0)
	var arc: float = deg_to_rad(20.0)
	var inside: Vector2 = line.rotated(deg_to_rad(12.0))
	assert_almost_eq(SlapperRules.clamp_aim(inside, line, arc).angle_to(inside), 0.0, 0.0001,
			"inside the arc the aim is the aim")
	var wide: Vector2 = line.rotated(deg_to_rad(-55.0))
	assert_almost_eq(line.angle_to(SlapperRules.clamp_aim(wide, line, arc)), -arc, 0.0001,
			"outside it the aim holds at the edge, on the same side")
