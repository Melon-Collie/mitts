extends GutTest

const OMEGA: float = 12.0


func _run(x: float, v: float, target: float, steps: int, dt: float) -> Vector2:
	for _i: int in steps:
		var nx: float = EaseRules.critical_x(x, v, target, OMEGA, dt)
		v = EaseRules.critical_v(x, v, target, OMEGA, dt)
		x = nx
	return Vector2(x, v)


# The point of it: from rest, the first step moves almost nothing — a lag at the
# same settling time would have moved k·dt of the gap.
func test_a_step_starts_from_rest() -> void:
	var first: float = EaseRules.critical_x(0.0, 0.0, 1.0, OMEGA, 1.0 / 120.0)
	var lag_first: float = OMEGA / EaseRules.OMEGA_PER_RATE / 120.0
	assert_lt(first, lag_first * 0.1)


func test_it_arrives_without_overshoot() -> void:
	var x: float = 0.0
	var v: float = 0.0
	for _i: int in 240:
		var nx: float = EaseRules.critical_x(x, v, 1.0, OMEGA, 1.0 / 120.0)
		v = EaseRules.critical_v(x, v, 1.0, OMEGA, 1.0 / 120.0)
		x = nx
		assert_true(x <= 1.0 + 1e-9, "overshot")
	assert_almost_eq(x, 1.0, 1e-4)


# Exact, not integrated: one long step lands where many short ones do.
func test_the_result_does_not_depend_on_the_frame_rate() -> void:
	var fine: Vector2 = _run(0.2, 0.5, 1.0, 120, 1.0 / 240.0)
	var coarse: Vector2 = _run(0.2, 0.5, 1.0, 30, 1.0 / 60.0)
	assert_almost_eq(fine.x, coarse.x, 1e-5)
	assert_almost_eq(fine.y, coarse.y, 1e-4)


# Its 90% time sits near the first-order lag's at the rate it stands in for.
func test_it_settles_in_about_the_lags_time() -> void:
	var rate: float = OMEGA / EaseRules.OMEGA_PER_RATE
	var lag_t90: float = log(10.0) / rate
	var dt: float = 1.0 / 1000.0
	var x: float = 0.0
	var v: float = 0.0
	var t: float = 0.0
	while x < 0.9:
		var nx: float = EaseRules.critical_x(x, v, 1.0, OMEGA, dt)
		v = EaseRules.critical_v(x, v, 1.0, OMEGA, dt)
		x = nx
		t += dt
	assert_almost_eq(t, lag_t90, lag_t90 * 0.25)
