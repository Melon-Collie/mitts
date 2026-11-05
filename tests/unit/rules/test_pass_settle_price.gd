extends GutTest

# AIFeedReception's price of a hard feed: the receiver's settle at the arrival speed in
# his frame, and the arrival speed itself.


func test_a_soft_arrival_settles_nothing_and_a_hard_one_does() -> void:
	assert_eq(AIFeedReception.receiver_settle_s(11.0), 0.0, "the NHL short-pass received mean")
	var s16: float = AIFeedReception.receiver_settle_s(16.0)
	var s20: float = AIFeedReception.receiver_settle_s(20.0)
	assert_gt(s16, 0.0, "the share off the line settles a 16 m/s feed")
	assert_gt(s20, s16)
	assert_almost_eq(AIFeedReception.receiver_settle_s(AIFeedReception.RECEIVE_ON_LINE_CEILING_M_S),
			AIFeedReception.SETTLE_MAX_S, 0.0001, "the full settle at the on-line ceiling")


func test_the_settle_is_each_contact_by_its_share() -> void:
	var closing: float = 20.0
	var share: float = AIFeedReception.RECEIVE_OFF_LINE_SHARE
	var on_line: float = PuckReceptionRules.settle_time(PuckReceptionRules.reception_load(
			Vector3(closing, 0, 0), Vector3.ZERO, 0.0, AIFeedReception.RECEIVE_DEFLECT_MIN_M_S,
			AIFeedReception.RECEIVE_ALIGNMENT_BONUS_M_S),
			AIFeedReception.SETTLE_CLEAN_LOAD, AIFeedReception.SETTLE_MAX_S)
	var off_line: float = PuckReceptionRules.settle_time(PuckReceptionRules.reception_load(
			Vector3(closing, 0, 0), Vector3.ZERO, AIFeedReception.RECEIVE_OFF_LINE_OFFSET,
			AIFeedReception.RECEIVE_DEFLECT_MIN_M_S, AIFeedReception.RECEIVE_ALIGNMENT_BONUS_M_S),
			AIFeedReception.SETTLE_CLEAN_LOAD, AIFeedReception.SETTLE_MAX_S)
	assert_gt(off_line, on_line, "off the line the same feed settles longer")
	assert_almost_eq(AIFeedReception.receiver_settle_s(closing),
			(1.0 - share) * on_line + share * off_line, 0.0001)


func test_the_paces_end_at_full_pace_and_soften_monotonically() -> void:
	var fracs: Array[float] = AIPuckLane.PASS_PACE_FRACS
	assert_eq(fracs[fracs.size() - 1], 1.0, "full pace is always priced")
	for i: int in range(1, fracs.size()):
		assert_lt(fracs[i - 1], fracs[i])


func test_arrival_closing_speed_sheds_friction_and_the_receivers_motion() -> void:
	var origin := Vector3.ZERO
	var meet := Vector3(10, 0, 0)
	var still: float = AIFeedReception.arrival_closing_speed(origin, meet, 15.0, Vector3.ZERO)
	assert_almost_eq(still, sqrt(225.0 - 2.0 * GameRules.PUCK_ICE_DECEL_M_S2 * 10.0), 0.0001)
	assert_lt(AIFeedReception.arrival_closing_speed(origin, meet, 15.0, Vector3(6, 0, 0)), still,
			"a receiver skating with the pass catches it softer")
	assert_gt(AIFeedReception.arrival_closing_speed(origin, meet, 15.0, Vector3(-6, 0, 0)), still,
			"one skating into it catches it harder")


func test_bobble_odds_rise_from_none_through_the_off_line_share_to_all() -> void:
	var hold: float = AIFeedReception.RECEIVE_HOLD_CEILING_M_S
	assert_eq(AIFeedReception.receiver_bobble_prob(16.0), 0.0, "a 16 m/s feed holds on and off the line")
	assert_almost_eq(AIFeedReception.receiver_bobble_prob(hold - 0.1),
			AIFeedReception.RECEIVE_OFF_LINE_SHARE, 0.0001,
			"just under the line's bobble pace, only the contacts off it bobble")
	assert_almost_eq(AIFeedReception.receiver_bobble_prob(hold + 0.1), 1.0, 0.0001,
			"past the line's bobble pace, every contact does")


func test_the_full_pace_feed_holds_on_the_line() -> void:
	assert_lt(AIPuckLane.PASS_TARGET_CLOSING_M_S, AIFeedReception.RECEIVE_HOLD_CEILING_M_S,
			"a bot's full-pace feed is held by a blade parked on its line")


func test_a_bobble_is_regathered_after_the_lockout_and_a_chase() -> void:
	var regather: float = AIFeedReception.bobble_regather_s(20.0)
	assert_gt(regather, AIFeedReception.SETTLE_MAX_S, "the lockout, then the blade has to get to it")
	var exit: float = AIFeedReception.bobble_exit_speed(20.0)
	assert_almost_eq(regather, AIFeedReception.SETTLE_MAX_S
			+ exit * AIFeedReception.SETTLE_MAX_S / (AISkaterCaps.LEAGUE_BLADE_SPEED_M_S - exit), 0.0001)
	assert_between(exit, 2.0, 3.2, "Puck's bobble exit for a square 20 m/s feed")


func test_the_hold_is_the_settle_or_the_regather_by_their_odds() -> void:
	assert_eq(AIFeedReception.reception_hold_s(10.0), 0.0, "a clean catch ties him up for nothing")
	var p: float = AIFeedReception.receiver_bobble_prob(22.0)
	assert_almost_eq(AIFeedReception.reception_hold_s(22.0),
			(1.0 - p) * AIFeedReception.receiver_settle_s(22.0) + p * AIFeedReception.bobble_regather_s(22.0),
			0.0001)
	assert_almost_eq(AIFeedReception.reception_hold_s(26.0), AIFeedReception.bobble_regather_s(26.0), 0.0001,
			"past the bobble pace everywhere, the hold is the regather")
