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
	var t1: float = AIStrideRamp.time_to_cover(VMAX, VMAX * 2.0, VMAX, ACCEL)
	assert_almost_eq(t1, 2.0, 1e-6, "already at top speed: pure cruise")


func test_speed_is_the_rate_of_the_distance() -> void:
	# speed_at and distance_in describe one ramp: the distance's finite
	# difference is the speed, through the knee and the cap, and through a
	# wrong-way start being braked out.
	var h: float = 0.0005
	for v0: float in [-4.0, -1.0, 0.0, 1.5, 2.6, 5.0, 9.0]:
		for t: float in [0.05, 0.2, 0.6, 1.2, 2.5]:
			var dd: float = (AIStrideRamp.signed_distance_in(v0, t + h, 10.0, 10.5, 9.0)
					- AIStrideRamp.signed_distance_in(v0, t - h, 10.0, 10.5, 9.0)) / (2.0 * h)
			assert_almost_eq(AIStrideRamp.signed_speed_at(v0, t, 10.0, 10.5, 9.0),
					dd, 0.02, "v0=%.1f t=%.2f" % [v0, t])


func test_head_start_matches_a_fine_sweep() -> void:
	# The crossing search against brute force: the most ground gained over a
	# 1 ms sweep of the horizon, on seeded starts — moving, standing, wrong-way,
	# a faster chaser, a faster lead, different builds.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261011
	for _i: int in 200:
		var lv: float = rng.randf_range(-3.0, 10.0)
		var cv: float = rng.randf_range(-6.0, 10.0)
		var lmax: float = rng.randf_range(8.5, 10.8)
		var cmax: float = rng.randf_range(8.5, 10.8)
		var la: float = rng.randf_range(8.0, 12.0)
		var ca: float = rng.randf_range(8.0, 12.0)
		var hz: float = rng.randf_range(0.2, 4.0)
		var brute: float = 0.0
		var t: float = 0.0
		while t <= hz:
			brute = maxf(brute, AIStrideRamp.signed_distance_in(lv, t, lmax, la, 9.0)
					- AIStrideRamp.signed_distance_in(cv, t, cmax, ca, 9.0))
			t += 0.001
		assert_almost_eq(AIStrideRamp.head_start(lv, lmax, la, cv, cmax, ca, 9.0, hz),
				brute, 0.01, "lead %.2f/%.1f chase %.2f/%.1f horizon %.2f"
						% [lv, lmax, cv, cmax, hz])
