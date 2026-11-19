extends GutTest

# A passer prices the receiver's own catch: his blade curve leans both catch-ceiling
# terms (Skater.reception_ceiling_mult, carried as AISkaterCaps.reception_ceiling_mult),
# and the pass's launch solve and its reception price read that lean as the
# reception decision sites apply it.

const _CURLING_BACK := Vector3(0, 0, 9)     # straight back at the passer, past every ceiling's slack
const _PASS_DIR := Vector3(0, 0, -1)
const _DIST: float = 14.0


func _mult(curve: int) -> float:
	return PlayerAttributes.new(73, 201, 1, curve, 1, 1).reception_ceiling_mult()


func _curves() -> Array[float]:
	return [_mult(PlayerAttributes.CURVE_CLOSED), 1.0, _mult(PlayerAttributes.CURVE_OPEN)]


func _caps(mult: float) -> AISkaterCaps:
	var caps := AISkaterCaps.new()
	caps.reception_ceiling_mult = mult
	return caps


# The receiver-frame closing speed a launch reaches a receiver `_DIST` up the
# pass direction at.
func _closing(launch: float, receiver_vel: Vector3) -> float:
	return AIFeedReception.arrival_closing_speed(Vector3.ZERO, _PASS_DIR * _DIST, launch,
			receiver_vel)


func test_the_unknown_receiver_is_priced_with_the_neutral_blade() -> void:
	assert_eq(AIFeedReception.receiver_ceiling_mult(null), 1.0)
	assert_eq(AIFeedReception.receiver_ceiling_mult(_caps(0.9)), 0.9)
	var maxw: float = GameRules.DEFAULT_WRISTER_POWER_MAX_M_S
	assert_eq(AIPuckLane.pass_launch_speed(_DIST, maxw, 1.0, _CURLING_BACK, _PASS_DIR, 1.0),
			AIPuckLane.pass_launch_speed(_DIST, maxw, 1.0, _CURLING_BACK, _PASS_DIR),
			"a neutral lean is bit-identical to the league solve the threat model reads")


func test_a_feed_to_a_receiver_curling_back_lands_at_his_own_ceiling() -> void:
	var maxw: float = GameRules.DEFAULT_WRISTER_POWER_MAX_M_S
	var prev_launch: float = -INF
	for mult: float in [_mult(PlayerAttributes.CURVE_OPEN), 1.0,
			_mult(PlayerAttributes.CURVE_CLOSED)]:
		var launch: float = AIPuckLane.pass_launch_speed(_DIST, maxw, 1.0, _CURLING_BACK,
				_PASS_DIR, mult)
		assert_almost_eq(_closing(launch, _CURLING_BACK),
				AIPuckLane.PASS_RECEIVE_CEILING_M_S * mult, 0.01,
				"the crisp bound is his blade's, at lean %.2f" % mult)
		assert_gt(launch, prev_launch, "a blade that soaks more is fed harder")
		prev_launch = launch


func test_the_lean_moves_only_the_ceiling_never_the_pace() -> void:
	# A streaking receiver and a still one are fed at the target pace, which is
	# a choice about how hard to pass; only the crisp bound is what he can handle.
	var maxw: float = GameRules.DEFAULT_WRISTER_POWER_MAX_M_S
	for receiver_vel: Vector3 in [Vector3.ZERO, Vector3(0, 0, -6), Vector3(4, 0, -3)]:
		for mult: float in _curves():
			assert_eq(AIPuckLane.pass_launch_speed(_DIST, maxw, 0.85, receiver_vel, _PASS_DIR,
					mult),
					AIPuckLane.pass_launch_speed(_DIST, maxw, 0.85, receiver_vel, _PASS_DIR))


func test_the_full_pace_feed_holds_on_the_line_on_every_curve() -> void:
	for mult: float in _curves():
		assert_lt(AIPuckLane.PASS_TARGET_CLOSING_M_S,
				AIFeedReception.RECEIVE_HOLD_CEILING_M_S * mult,
				"the unleaned target pace is still a catch on lean %.2f" % mult)
		assert_lt(AIPuckLane.PASS_TARGET_CLOSING_M_S, AIPuckLane.PASS_RECEIVE_CEILING_M_S * mult,
				"the soft bound stays under the crisp one on lean %.2f" % mult)


func test_the_lean_scales_both_ceiling_terms_as_the_reception_does() -> void:
	# PuckController and PickupClaimResolver hand the reception deflect_min ×
	# lean and alignment_bonus × lean; the settle is read off that load.
	var mult: float = _mult(PlayerAttributes.CURVE_OPEN)
	var closing: float = 21.0
	var share: float = AIFeedReception.RECEIVE_OFF_LINE_SHARE
	var deflect_min: float = AIFeedReception.RECEIVE_DEFLECT_MIN_M_S * mult
	var bonus: float = AIFeedReception.RECEIVE_ALIGNMENT_BONUS_M_S * mult
	var on_line: float = PuckReceptionRules.settle_time(PuckReceptionRules.reception_load(
			Vector3(closing, 0, 0), Vector3.ZERO, 0.0, deflect_min, bonus),
			AIFeedReception.SETTLE_CLEAN_LOAD, AIFeedReception.SETTLE_MAX_S)
	var off_line: float = PuckReceptionRules.settle_time(PuckReceptionRules.reception_load(
			Vector3(closing, 0, 0), Vector3.ZERO, AIFeedReception.RECEIVE_OFF_LINE_OFFSET,
			deflect_min, bonus),
			AIFeedReception.SETTLE_CLEAN_LOAD, AIFeedReception.SETTLE_MAX_S)
	assert_almost_eq(AIFeedReception.receiver_settle_s(closing, mult),
			(1.0 - share) * on_line + share * off_line, 0.0001)


func test_a_leaned_catch_is_the_neutral_catch_at_the_closing_over_the_lean() -> void:
	# Both ceiling terms scale, so the load is a function of closing / lean.
	for mult: float in _curves():
		for closing: float in [12.0, 18.0, 20.0, 22.0, 25.0, 28.0]:
			assert_almost_eq(AIFeedReception.receiver_settle_s(closing, mult),
					AIFeedReception.receiver_settle_s(closing / mult), 0.0001)
			assert_almost_eq(AIFeedReception.receiver_bobble_prob(closing, mult),
					AIFeedReception.receiver_bobble_prob(closing / mult), 0.0001)


func test_a_blade_that_soaks_more_never_settles_or_bobbles_more() -> void:
	var curves: Array[float] = _curves()
	curves.sort()
	for closing: float in [14.0, 18.0, 20.0, 21.0, 23.0, 26.0]:
		for i: int in range(1, curves.size()):
			assert_true(AIFeedReception.receiver_settle_s(closing, curves[i])
					<= AIFeedReception.receiver_settle_s(closing, curves[i - 1]))
			assert_true(AIFeedReception.receiver_bobble_prob(closing, curves[i])
					<= AIFeedReception.receiver_bobble_prob(closing, curves[i - 1]))
			assert_true(AIFeedReception.reception_hold_s(closing, curves[i])
					<= AIFeedReception.reception_hold_s(closing, curves[i - 1]))


func test_the_regather_of_a_bobble_is_the_bounce_not_the_blade() -> void:
	# Past every bobble line the hold is the regather alone, whatever the lean.
	var closing: float = AIFeedReception.RECEIVE_ON_LINE_CEILING_M_S * 1.2
	for mult: float in _curves():
		assert_eq(AIFeedReception.receiver_bobble_prob(closing, mult), 1.0)
		assert_almost_eq(AIFeedReception.reception_hold_s(closing, mult),
				AIFeedReception.bobble_regather_s(closing), 0.0001)
