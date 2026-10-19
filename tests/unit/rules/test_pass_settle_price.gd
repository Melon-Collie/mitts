extends GutTest

# AIPuckLane's price of a hard feed: the receiver's settle at the arrival speed in
# his frame, and the arrival speed itself.


func test_a_soft_arrival_settles_nothing_and_a_hard_one_does() -> void:
	assert_eq(AIPuckLane.receiver_settle_s(11.0), 0.0, "the NHL short-pass received mean")
	var s16: float = AIPuckLane.receiver_settle_s(16.0)
	var s20: float = AIPuckLane.receiver_settle_s(20.0)
	assert_gt(s16, 0.0)
	assert_gt(s20, s16)
	assert_almost_eq(AIPuckLane.receiver_settle_s(AIPuckLane.RECEIVE_ANY_ANGLE_CEILING_M_S),
			AIPuckLane.SETTLE_MAX_S, 0.0001, "the full settle at the catch ceiling")


func test_the_paces_end_at_full_pace_and_soften_monotonically() -> void:
	var fracs: Array[float] = AIPuckLane.PASS_PACE_FRACS
	assert_eq(fracs[fracs.size() - 1], 1.0, "full pace is always priced")
	for i: int in range(1, fracs.size()):
		assert_lt(fracs[i - 1], fracs[i])


func test_arrival_closing_speed_sheds_friction_and_the_receivers_motion() -> void:
	var origin := Vector3.ZERO
	var meet := Vector3(10, 0, 0)
	var still: float = AIPuckLane.arrival_closing_speed(origin, meet, 15.0, Vector3.ZERO)
	assert_almost_eq(still, sqrt(225.0 - 2.0 * GameRules.PUCK_ICE_DECEL_M_S2 * 10.0), 0.0001)
	assert_lt(AIPuckLane.arrival_closing_speed(origin, meet, 15.0, Vector3(6, 0, 0)), still,
			"a receiver skating with the pass catches it softer")
	assert_gt(AIPuckLane.arrival_closing_speed(origin, meet, 15.0, Vector3(-6, 0, 0)), still,
			"one skating into it catches it harder")
