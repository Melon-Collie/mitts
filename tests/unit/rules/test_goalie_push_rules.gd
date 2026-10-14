extends GutTest

# The upright goalie's lateral push (GoaliePushRules): the cruise a save push
# makes across a shot in flight, and the push that stops SET on its spot, which
# every re-square race and the live mover share.

# ── cruise_reach ─────────────────────────────────────────────────────────────
# Accelerate from rest at `accel` to `max_speed`, then hold.

func test_cruise_reach_zero_time_is_zero() -> void:
	assert_almost_eq(GoaliePushRules.cruise_reach(3.8, 14.0, 0.0), 0.0, 0.0001)

func test_cruise_reach_ramp_phase() -> void:
	# t=0.1s is inside the ramp (t_ramp = 3.8/14 ≈ 0.271): d = ½·14·0.1² = 0.07.
	assert_almost_eq(GoaliePushRules.cruise_reach(3.8, 14.0, 0.1), 0.07, 0.0001)

func test_cruise_reach_past_ramp() -> void:
	# t=0.5s: d = v·t − v²/(2a) = 1.9 − 0.5157 ≈ 1.3843.
	assert_almost_eq(GoaliePushRules.cruise_reach(3.8, 14.0, 0.5), 1.3843, 0.001)

func test_cruise_reach_zero_accel_is_instant_speed() -> void:
	assert_almost_eq(GoaliePushRules.cruise_reach(3.8, 0.0, 0.5), 1.9, 0.0001)

# ── set_reach / time_to_set / push_progress ──────────────────────────────────
# A push that ends stopped on its spot: up at 14 m/s² to 3.8 m/s, cruise, down
# at 14 × GOALIE_EDGE_STOP_DECEL_RATIO. Mirrors _move_along_arc's braking cap.

const _BRAKE: float = 14.0 * GameRules.GOALIE_EDGE_STOP_DECEL_RATIO

func test_set_reach_zero_time_is_zero() -> void:
	assert_almost_eq(GoaliePushRules.set_reach(3.8, 14.0, 0.0), 0.0, 0.0001)

func test_a_short_push_peaks_and_stops_short_of_top_speed() -> void:
	# Triangular: peak v at t/k, distance ½·v·t.
	var t: float = 0.2
	var peak: float = t / (1.0 / 14.0 + 1.0 / _BRAKE)
	assert_lt(peak, 3.8)
	assert_almost_eq(GoaliePushRules.set_reach(3.8, 14.0, t), 0.5 * peak * t, 0.0001)

func test_a_long_push_cruises_between_the_push_and_the_stop() -> void:
	var t: float = 1.0
	var t_up: float = 3.8 / 14.0
	var t_down: float = 3.8 / _BRAKE
	var expect: float = 0.5 * 3.8 * t_up + 3.8 * (t - t_up - t_down) + 0.5 * 3.8 * t_down
	assert_almost_eq(GoaliePushRules.set_reach(3.8, 14.0, t), expect, 0.0001)

func test_stopping_costs_reach_against_a_push_that_never_stops() -> void:
	var t: float = 0.5
	assert_lt(GoaliePushRules.set_reach(3.8, 14.0, t), GoaliePushRules.cruise_reach(3.8, 14.0, t))

func test_time_to_set_inverts_set_reach() -> void:
	for t: float in [0.1, 0.3, 0.6, 1.5]:
		var d: float = GoaliePushRules.set_reach(3.8, 14.0, t)
		assert_almost_eq(GoaliePushRules.time_to_set(d, 3.8, 14.0), t, 0.0001)

func test_push_progress_arrives_exactly_when_set() -> void:
	for dist: float in [0.2, 0.8, 2.5]:
		var t_set: float = GoaliePushRules.time_to_set(dist, 3.8, 14.0)
		assert_lt(GoaliePushRules.push_progress(dist, 3.8, 14.0, t_set * 0.95), dist)
		assert_almost_eq(GoaliePushRules.push_progress(dist, 3.8, 14.0, t_set), dist, 0.0001)
		assert_almost_eq(GoaliePushRules.push_progress(dist, 3.8, 14.0, t_set + 1.0), dist, 0.0001)

func test_push_progress_never_goes_backwards() -> void:
	var last: float = 0.0
	for i: int in 200:
		var p: float = GoaliePushRules.push_progress(1.2, 3.8, 14.0, float(i) * 0.005)
		assert_gte(p, last - 1e-6)
		last = p

func test_the_braking_cap_stops_him_on_the_spot() -> void:
	# At the cap he sheds exactly his speed over the remaining distance.
	var cap: float = GoaliePushRules.braking_speed_cap(0.3, 14.0)
	assert_almost_eq(cap * cap / (2.0 * _BRAKE), 0.3, 0.0001)
