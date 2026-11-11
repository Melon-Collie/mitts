extends GutTest

# StickHoldRules: where the top hand holds a stick whose blade is placed. A
# 6'1" skater's numbers; the top hand's side is +x, ahead is −z.

const STICK: float = 1.40
const OWN: float = 1.0
const SHOULDER := Vector3(0.22, 1.3, -0.25)
const ICE: float = 0.03

var _cfg := StickHoldRules.Config.new()


func _hand(blade_x: float, blade_ahead: float) -> Vector3:
	return StickHoldRules.top_hand(SHOULDER, Vector3(blade_x, ICE, -blade_ahead), STICK, OWN, _cfg)


func _lie_deg(hand: Vector3, blade_x: float, blade_ahead: float) -> float:
	var shaft: Vector3 = hand - Vector3(blade_x, ICE, -blade_ahead)
	return rad_to_deg(asin(shaft.y / shaft.length()))


func test_the_stick_keeps_its_length_wherever_the_blade_is() -> void:
	for ahead: float in [0.5, 0.8, 1.1, 1.4, 1.7]:
		for x: float in [-1.2, -0.6, 0.0, 0.6, 1.2]:
			var hand: Vector3 = _hand(x, ahead)
			assert_almost_eq(hand.distance_to(Vector3(x, ICE, -ahead)), STICK, 0.0005,
					"blade %.1f across, %.1f ahead" % [x, ahead])


func test_a_blade_a_sticks_span_off_the_pocket_is_held_on_the_lie() -> void:
	var span: float = STICK * cos(_cfg.lie)
	var pivot := Vector2(SHOULDER.x + _cfg.home_out, -SHOULDER.z + _cfg.home_ahead)
	var hand: Vector3 = _hand(pivot.x, pivot.y + span)
	assert_almost_eq(_lie_deg(hand, pivot.x, pivot.y + span), rad_to_deg(_cfg.lie), 0.01,
			"the shaft at its lie")
	assert_almost_eq(hand.x, pivot.x, 0.001, "the hand in the pocket's middle")
	assert_almost_eq(-hand.z, pivot.y, 0.001, "the hand in the pocket's middle")


func test_a_far_blade_draws_the_hand_out_toward_it_and_keeps_the_lie() -> void:
	var near: Vector3 = _hand(-0.2, 1.45)
	var far: Vector3 = _hand(-0.2, 1.6)
	assert_gt(-far.z, -near.z + 0.1, "the hand follows the blade out")
	assert_almost_eq(_lie_deg(far, -0.2, 1.6), rad_to_deg(_cfg.lie), 0.5, "on the lie still")


func test_past_the_pockets_reach_the_shaft_lies_down() -> void:
	var hand: Vector3 = _hand(-0.2, 1.95)
	assert_lt(_lie_deg(hand, -0.2, 1.95), rad_to_deg(_cfg.lie) - 3.0, "the shaft flatter than its lie")
	assert_gt(hand.y, ICE + 0.3, "the hand still well over the ice")


func test_a_blade_in_close_draws_the_hand_out_to_its_own_side() -> void:
	var rest: Vector3 = _hand(-0.2, 1.45)
	var close: Vector3 = _hand(-0.2, 1.1)
	assert_gt(close.x, rest.x + 0.05, "out to its own side")
	assert_lt(-close.z, -rest.z, "and back toward the hip")
	assert_lt(_lie_deg(close, -0.2, 1.1), 52.0, "which keeps the shaft near its lie")


func test_only_what_the_pocket_cannot_take_stands_the_shaft_up() -> void:
	var lie: float = rad_to_deg(_cfg.lie)
	var last: float = lie
	for ahead: float in [1.3, 1.1, 0.9, 0.7]:
		var here: float = _lie_deg(_hand(-0.1, ahead), -0.1, ahead)
		assert_gte(here, last - 0.01, "steeper the nearer the blade comes (%.1f m ahead)" % ahead)
		last = here
	assert_gt(last, lie + 10.0, "a blade at his skates stands the stick up")


func test_the_hand_moves_without_a_step_as_the_blade_does() -> void:
	var worst: float = 0.0
	var prev: Vector3 = _hand(-1.5, 0.4)
	for i: int in range(1, 601):
		var t: float = float(i) / 600.0
		# A sweep from tight on the forehand, out past the pocket's reach, and
		# back in round the hand's own side: every branch of the rule.
		var blade := Vector2(lerpf(-1.5, 1.5, t), 0.4 + 1.6 * sin(PI * t))
		var hand: Vector3 = _hand(blade.x, blade.y)
		worst = maxf(worst, hand.distance_to(prev))
		prev = hand
	assert_lt(worst, 0.015, "the hand never jumps (worst step %.3f m for a ~1 cm blade step)" % worst)


func test_a_left_shot_is_the_right_shots_mirror() -> void:
	var right: Vector3 = _hand(-0.3, 1.0)
	var left: Vector3 = StickHoldRules.top_hand(Vector3(-SHOULDER.x, SHOULDER.y, SHOULDER.z),
			Vector3(0.3, ICE, -1.0), STICK, -OWN, _cfg)
	assert_almost_eq(left, Vector3(-right.x, right.y, right.z), Vector3.ONE * 0.0001)


func test_soft_cap_is_the_value_below_and_the_cap_beyond() -> void:
	assert_almost_eq(StickHoldRules.soft_cap(0.0, 0.5, 0.05), 0.0, 0.000001)
	assert_almost_eq(StickHoldRules.soft_cap(0.2, 0.5, 0.05), 0.2, 0.000001)
	assert_almost_eq(StickHoldRules.soft_cap(0.9, 0.5, 0.05), 0.5, 0.000001)
	assert_between(StickHoldRules.soft_cap(0.47, 0.5, 0.05), 0.45, 0.5, "rounded into the cap")
	assert_almost_eq(StickHoldRules.soft_cap(0.3, 0.0, 0.05), 0.0, 0.000001, "no room, no travel")
