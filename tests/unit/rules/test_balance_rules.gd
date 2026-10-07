extends GutTest

# The balance model's two halves: the angle that balances an acceleration, and
# the spring that gets the body there. The spring's numbers are the plan's
# (docs/skater-animation-plan.md §4): a sustained turn arrives in about half a
# second, a steering wiggle mostly does not arrive at all.

const OMEGA: float = 7.0
const CAP: float = deg_to_rad(30.0)


func test_a_turn_banks_at_the_balancing_angle() -> void:
	# 7 m/s round a 6 m radius: centripetal 8.17 m/s² toward +x.
	var a: float = 7.0 * 7.0 / 6.0
	var tilt: Vector2 = BalanceRules.balance_tilt(Vector2(a, 0.0), deg_to_rad(80.0))
	assert_almost_eq(tilt.length(), atan(a / BalanceRules.GRAVITY), 1e-6)
	assert_almost_eq(tilt.normalized().x, 1.0, 1e-6, "toward the centre of the arc")


func test_the_tilt_is_capped() -> void:
	var tilt: Vector2 = BalanceRules.balance_tilt(Vector2(0.0, -30.0), CAP)
	assert_almost_eq(tilt.length(), CAP, 1e-6)


func test_no_acceleration_no_lean() -> void:
	assert_eq(BalanceRules.balance_tilt(Vector2.ZERO, CAP), Vector2.ZERO)


# Exact steps make the response independent of the frame rate: the same second
# rendered at 30, 60 and 144 fps lands on the same lean.
func test_the_spring_does_not_care_how_the_time_is_chopped() -> void:
	var target := Vector2(0.4, -0.1)
	var ends: Array[Vector2] = []
	for fps: int in [30, 60, 144]:
		var x := Vector2.ZERO
		var v := Vector2.ZERO
		for _i: int in fps:
			var s: Vector4 = BalanceRules.spring_step(x, v, target, OMEGA, 1.0 / fps)
			x = Vector2(s.x, s.y)
			v = Vector2(s.z, s.w)
		ends.append(x)
	assert_almost_eq(ends[0].distance_to(ends[2]), 0.0, 1e-5)
	assert_almost_eq(ends[1].distance_to(ends[2]), 0.0, 1e-5)


func test_a_sustained_lean_arrives_in_about_half_a_second() -> void:
	var t90: float = _time_to_fraction(0.9)
	assert_between(t90, 0.45, 0.65, "90%% of a held lean took %.2f s" % t90)


# A steering wiggle at 2 Hz and at 4 Hz, each swinging the target ±30°: the
# body shows a quarter of the first and almost none of the second.
func test_a_steering_wiggle_is_mostly_filtered_out() -> void:
	assert_lt(_wiggle_amplitude(2.0), deg_to_rad(30.0) * 0.3)
	assert_lt(_wiggle_amplitude(4.0), deg_to_rad(30.0) * 0.1)


func _time_to_fraction(fraction: float) -> float:
	var target := Vector2(1.0, 0.0)
	var x := Vector2.ZERO
	var v := Vector2.ZERO
	var dt: float = 1.0 / 240.0
	for i: int in 1000:
		var s: Vector4 = BalanceRules.spring_step(x, v, target, OMEGA, dt)
		x = Vector2(s.x, s.y)
		v = Vector2(s.z, s.w)
		if x.x >= fraction:
			return float(i + 1) * dt
	return INF


func _wiggle_amplitude(hz: float) -> float:
	var x := Vector2.ZERO
	var v := Vector2.ZERO
	var dt: float = 1.0 / 240.0
	var peak: float = 0.0
	for i: int in 240 * 4:
		var t: float = float(i) * dt
		var target := Vector2(deg_to_rad(30.0) * sin(TAU * hz * t), 0.0)
		var s: Vector4 = BalanceRules.spring_step(x, v, target, OMEGA, dt)
		x = Vector2(s.x, s.y)
		v = Vector2(s.z, s.w)
		if t > 2.0:
			peak = maxf(peak, absf(x.x))
	return peak
