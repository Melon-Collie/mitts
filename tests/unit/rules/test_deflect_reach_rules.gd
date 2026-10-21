extends GutTest

# DeflectReachRules — how high a committed deflect's blade rises to meet the puck.

const REST: float = GameRules.PUCK_COLLISION_HALF_HEIGHT
const BLADE := Vector3(0.0, 0.03, 0.0)


func _lift(pos: Vector3, vel: Vector3) -> float:
	return DeflectReachRules.lift_to_meet(pos, vel, BLADE, REST)


func test_a_puck_on_the_ice_keeps_the_blade_down() -> void:
	assert_almost_eq(_lift(Vector3(0.0, REST, 5.0), Vector3(0.0, 0.0, -20.0)), 0.0, 0.0001)


func test_the_blade_meets_a_rising_shot_where_it_will_be() -> void:
	var pos := Vector3(0.0, 0.2, 6.0)
	var vel := Vector3(0.0, 2.0, -20.0)
	var t: float = 6.0 / 20.0
	var expected: float = 0.2 + 2.0 * t - 0.5 * GameRules.GRAVITY_M_S2 * t * t - REST
	assert_almost_eq(_lift(pos, vel), expected, 0.0001,
			"read at the crossing, not where the puck is now")
	assert_gt(_lift(pos, vel), 0.2 - REST, "a rising puck is met higher than it is now")


func test_closest_approach_is_measured_across_the_line() -> void:
	# Passing 0.8 m beside the blade still counts: the cursor can carry the blade there.
	var pos := Vector3(0.8, 0.6, 4.0)
	var vel := Vector3(0.0, 0.0, -20.0)
	var t: float = 4.0 / 20.0
	assert_almost_eq(_lift(pos, vel),
			0.6 - 0.5 * GameRules.GRAVITY_M_S2 * t * t - REST, 0.0001)


func test_a_line_wide_of_the_stick_is_not_tracked() -> void:
	var wide := Vector3(DeflectReachRules.TRACK_RADIUS_M + 0.1, 0.6, 4.0)
	assert_eq(_lift(wide, Vector3(0.0, 0.0, -20.0)), 0.0)


func test_a_puck_still_far_off_in_time_is_not_tracked_yet() -> void:
	var speed: float = 20.0
	var far := Vector3(0.0, 0.6, speed * (DeflectReachRules.TRACK_HORIZON_S + 0.05))
	assert_eq(_lift(far, Vector3(0.0, 5.0, -speed)), 0.0)
	var near := Vector3(0.0, 0.6, speed * (DeflectReachRules.TRACK_HORIZON_S - 0.05))
	assert_gt(_lift(near, Vector3(0.0, 5.0, -speed)), 0.0)


func test_a_puck_moving_away_is_read_where_it_is() -> void:
	var pos := Vector3(0.0, 0.4, -0.3)
	assert_almost_eq(_lift(pos, Vector3(0.0, 0.0, -10.0)), 0.4 - REST, 0.0001)


func test_a_puck_that_lands_on_the_way_is_met_on_the_ice() -> void:
	assert_eq(_lift(Vector3(0.0, 0.1, 5.0), Vector3(0.0, -1.0, -10.0)), 0.0)


func test_a_resting_puck_by_the_blade_is_read_where_it_is() -> void:
	assert_almost_eq(_lift(Vector3(0.2, 0.3, 0.0), Vector3.ZERO), 0.3 - REST, 0.0001)
