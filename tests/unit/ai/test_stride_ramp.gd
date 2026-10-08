extends GutTest

# AIStrideRamp — the AI's closed-form price of the stride ramp.

const ACCEL: float = GameRules.DEFAULT_SKATER_THRUST_M_S2
const VMAX: float = GameRules.DEFAULT_SKATER_MAX_SPEED_M_S


func test_time_and_distance_are_inverses() -> void:
	for v0: float in [0.0, 2.0, 5.0, 9.0]:
		for t: float in [0.1, 0.5, 1.5, 4.0]:
			var d: float = AIStrideRamp.distance_in(v0, t, VMAX, ACCEL)
			assert_almost_eq(AIStrideRamp.time_to_cover(v0, d, VMAX, ACCEL), t, 1e-4,
					"v0=%.1f t=%.1f" % [v0, t])


func test_building_to_speed_matches_the_ramp() -> void:
	# From rest, the ramp passes `speed` exactly distance_to_speed in.
	var d: float = AIStrideRamp.distance_to_speed(7.0, ACCEL)
	var t: float = AIStrideRamp.time_to_cover(0.0, d, VMAX, ACCEL)
	var just_short: float = AIStrideRamp.distance_in(0.0, t - 0.01, VMAX, ACCEL)
	assert_lt(just_short, d, "monotone")
	assert_gt(d, AIStrideRamp.distance_to_speed(3.0, ACCEL), "faster takes longer to build")


func test_power_phase_is_slower_than_constant_accel() -> void:
	# Above the knee the push fades, so reaching top speed costs more ground
	# than a constant-accel ramp at the standing-start push would.
	var a: float = ACCEL * AIStrideRamp.EFFICIENCY
	assert_gt(AIStrideRamp.distance_to_speed(VMAX, ACCEL), VMAX * VMAX / (2.0 * a))


func test_cruise_after_top_speed() -> void:
	var t1: float = AIStrideRamp.time_to_cover(VMAX, 18.0, VMAX, ACCEL)
	assert_almost_eq(t1, 2.0, 1e-6, "already at top speed: pure cruise")
