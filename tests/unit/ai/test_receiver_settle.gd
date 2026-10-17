extends GutTest

# What a feed costs its receiver in settle time, as the passer prices it
# (AIPuckLane.feed_closing_speed / receiver_settle_s). Properties only.


func test_a_stationary_receiver_meets_the_feed_at_its_arrival_pace() -> void:
	var launch: float = 20.0
	var dist: float = 10.0
	var arrival: float = sqrt(launch * launch - 2.0 * GameRules.PUCK_ICE_DECEL_M_S2 * dist)
	assert_almost_eq(AIPuckLane.feed_closing_speed(
			Vector3.ZERO, Vector3(dist, 0, 0), launch, Vector3.ZERO), arrival, 1e-4)


func test_skating_with_the_feed_softens_it() -> void:
	var with_it: float = AIPuckLane.feed_closing_speed(
			Vector3.ZERO, Vector3(10, 0, 0), 20.0, Vector3(6, 0, 0))
	var into_it: float = AIPuckLane.feed_closing_speed(
			Vector3.ZERO, Vector3(10, 0, 0), 20.0, Vector3(-6, 0, 0))
	assert_lt(with_it, into_it)
	assert_lt(AIPuckLane.receiver_settle_s(with_it, true, 1.0),
			AIPuckLane.receiver_settle_s(into_it, true, 1.0))


func test_a_squared_receiver_settles_a_bot_feed_sooner() -> void:
	var closing: float = AIPuckLane.PASS_TARGET_CLOSING_M_S
	var squared: float = AIPuckLane.receiver_settle_s(closing, true, 1.0)
	assert_gt(squared, 0.0, "a bot feed is hard enough to settle")
	assert_lt(squared, AIPuckLane.receiver_settle_s(closing, false, 1.0))
	assert_lt(squared, PuckReceptionRules.RECEPTION_SETTLE_MAX_S)


func test_a_soft_feed_costs_nothing() -> void:
	assert_eq(AIPuckLane.receiver_settle_s(
			PuckReceptionRules.LEAGUE_PICKUP_MAX_M_S, false, 1.0), 0.0)
