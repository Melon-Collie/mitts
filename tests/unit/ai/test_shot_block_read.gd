extends GutTest

# AIShotBlockRead: the lane, the loft, the goalie's eyes, the shot coming
# through, and the dive's reach against standing reach.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")


func test_the_block_cylinder_is_the_skaters() -> void:
	var s: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(s)
	assert_eq(AIShotBlockRead.BLOCK_RADIUS_M, s.block_body_radius)
	assert_eq(AIShotBlockRead.BLOCK_SEAL_HEIGHT_M, s.block_seal_height)


func test_in_the_lane_is_on_the_line_between_release_and_net() -> void:
	var release := Vector3(0.0, 0.0, 10.0)
	var goal := Vector3(0.0, 0.0, 26.65)
	assert_true(AIShotBlockRead.in_lane(Vector3(0.5, 0.0, 18.0), release, goal))
	assert_false(AIShotBlockRead.in_lane(Vector3(2.0, 0.0, 18.0), release, goal), "wide")
	assert_false(AIShotBlockRead.in_lane(Vector3(0.0, 0.0, 8.0), release, goal), "behind him")
	assert_false(AIShotBlockRead.in_lane(Vector3(0.0, 0.0, 10.5), release, goal),
			"on his stick, not in his lane")


func test_a_flat_shot_stays_on_the_ice_and_a_high_one_climbs() -> void:
	assert_eq(AIShotBlockRead.shot_height_at(8.0, ShotMechanics.ELEVATION_FLAT, 30.0), 0.0)
	var low: float = AIShotBlockRead.shot_height_at(8.0, ShotMechanics.ELEVATION_LOW, 30.0)
	var high: float = AIShotBlockRead.shot_height_at(8.0, ShotMechanics.ELEVATION_HIGH, 30.0)
	assert_gt(high, low)
	assert_lt(high, 8.0 * GameRules.DEFAULT_LOFT_TAN_HIGH, "gravity takes some back")


func test_the_block_concedes_a_shot_over_its_seal() -> void:
	var release := Vector3(0.0, 0.0, 8.0)
	var near := Vector3(0.0, 0.0, 12.0)
	var far := Vector3(0.0, 0.0, 22.0)
	assert_true(AIShotBlockRead.stays_low(far, release, ShotMechanics.ELEVATION_FLAT, 33.0))
	assert_true(AIShotBlockRead.stays_low(near, release, ShotMechanics.ELEVATION_HIGH, 33.0),
			"close in, even the top rung is still low")
	assert_false(AIShotBlockRead.stays_low(far, release, ShotMechanics.ELEVATION_HIGH, 33.0),
			"from range it is over him")


func test_a_block_on_the_goalies_doorstep_screens_him() -> void:
	var cfg := GoalieScreenRules.ScreenConfig.new()
	var goalie := Vector3(0.0, 0.0, 25.5)
	assert_true(AIShotBlockRead.screens_own_goalie(Vector3(0.0, 0.0, 24.8), goalie, cfg))
	assert_false(AIShotBlockRead.screens_own_goalie(Vector3(0.0, 0.0, 22.0), goalie, cfg))


func test_a_released_shot_is_coming_through_only_at_us() -> void:
	var me := Vector3(0.0, 0.0, 20.0)
	assert_true(AIShotBlockRead.puck_coming_through(me, Vector3(0.3, 0.0, 14.0),
			Vector3(0.0, 0.0, 30.0)))
	assert_false(AIShotBlockRead.puck_coming_through(me, Vector3(0.3, 0.0, 14.0),
			Vector3(0.0, 0.0, -30.0)), "going away")
	assert_false(AIShotBlockRead.puck_coming_through(me, Vector3(3.0, 0.0, 14.0),
			Vector3(0.0, 0.0, 30.0)), "wide of us")
	assert_false(AIShotBlockRead.puck_coming_through(me, Vector3(0.3, 0.0, 14.0),
			Vector3(0.0, 0.0, 0.5)), "dead")


func test_the_dive_takes_a_lane_out_of_standing_reach_but_inside_its_own() -> void:
	var carrier := Vector3(-3.0, 0.0, 19.0)
	var receiver := Vector3(4.0, 0.0, 21.0)
	var q: Vector3 = AIShotBlockRead.dive_point(Vector3(0.5, 0.0, 17.8), Vector3.ZERO,
			carrier, receiver, 1.5, 10.0, 20.0)
	assert_true(q.is_finite(), "out of standing reach, inside the dive")
	var a := Vector2(carrier.x, carrier.z)
	var ab := Vector2(receiver.x, receiver.z) - a
	assert_almost_eq(absf(ab.cross(Vector2(q.x, q.z) - a)), 0.0, 1e-4, "on the lane")
	assert_false(AIShotBlockRead.dive_point(Vector3(-0.2, 0.0, 18.8), Vector3.ZERO,
			carrier, receiver, 1.5, 10.0, 20.0).is_finite(), "his stick already takes it")
	assert_false(AIShotBlockRead.dive_point(Vector3(0.5, 0.0, 14.0), Vector3.ZERO,
			carrier, receiver, 1.5, 10.0, 20.0).is_finite(), "past the dive")
	assert_false(AIShotBlockRead.dive_point(Vector3(0.5, 0.0, 17.8), Vector3(0.0, 0.0, 12.0),
			carrier, receiver, 1.5, 10.0, 20.0).is_finite(), "skating at it, he gets there")
