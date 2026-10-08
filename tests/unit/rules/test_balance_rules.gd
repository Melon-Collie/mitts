extends GutTest

# The balance model's two halves: the angle that balances an acceleration, and
# the spring that gets the body there. Pinned at the skater's tuning: a
# sustained turn arrives in about a second (the body's weight takes a beat to
# come over the edges), a steering wiggle mostly does not arrive at all.

const OMEGA: float = 4.0
const CAP: float = deg_to_rad(20.0)


func test_the_skater_is_tuned_as_pinned_here() -> void:
	var skater := Skater.new()
	assert_eq(skater.balance_omega, OMEGA, "re-pin this file when the spring is retuned")
	assert_almost_eq(deg_to_rad(skater.balance_lean_cap_deg), CAP, 1e-6)
	skater.free()


func test_a_gentle_push_leans_at_the_balancing_angle() -> void:
	# A light 0.5 m/s² push toward +x: well under the cap, so the soft cap's
	# cubic term is under a percent of the angle.
	var a: float = 0.5
	var tilt: Vector2 = BalanceRules.balance_tilt(Vector2(a, 0.0), CAP)
	assert_almost_eq(tilt.length(), atan(a / BalanceRules.GRAVITY), 0.01 * atan(a / BalanceRules.GRAVITY))
	assert_almost_eq(tilt.normalized().x, 1.0, 1e-6, "toward the acceleration")


# Soft: a hard push approaches the cap without reaching it, and a harder one
# still leans further — no ceiling every push lands on.
func test_the_tilt_eases_into_its_cap() -> void:
	var turn: float = BalanceRules.balance_tilt(Vector2(0.0, -8.0), CAP).length()
	var harder: float = BalanceRules.balance_tilt(Vector2(0.0, -16.0), CAP).length()
	assert_lt(turn, CAP, "under the cap")
	assert_lt(harder, CAP, "still under it")
	assert_gt(harder, turn + deg_to_rad(0.5), "a harder push leans further")
	assert_gt(harder, CAP * 0.9, "and nearly gets there")


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


func test_a_sustained_lean_arrives_in_about_a_second() -> void:
	var t90: float = _time_to_fraction(0.9)
	assert_between(t90, 0.85, 1.1, "90%% of a held lean took %.2f s" % t90)


# A steering wiggle at 1.5 Hz and at 3 Hz, each swinging the target across the
# whole ±cap: the body shows a fraction of the first and almost none of the
# second, rather than rocking through upright on every switch.
func test_a_steering_wiggle_is_mostly_filtered_out() -> void:
	assert_lt(_wiggle_amplitude(1.5), CAP * 0.25)
	assert_lt(_wiggle_amplitude(3.0), CAP * 0.08)


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
		var target := Vector2(CAP * sin(TAU * hz * t), 0.0)
		var s: Vector4 = BalanceRules.spring_step(x, v, target, OMEGA, dt)
		x = Vector2(s.x, s.y)
		v = Vector2(s.z, s.w)
		if t > 2.0:
			peak = maxf(peak, absf(x.x))
	return peak
