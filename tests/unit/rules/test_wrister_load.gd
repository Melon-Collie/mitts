extends GutTest

# WristerLoad — what the torso can put into a wrist shot. Positions are in the
# skater's local frame (forward −Z, left −X), named by the clock: 12 ahead,
# 9 on the left, 3 on the right, 6 behind.

const AT_12 := Vector3(0.0, 0.0, -0.9)
const AT_9 := Vector3(-0.9, 0.0, 0.0)
const AT_3 := Vector3(0.9, 0.0, 0.0)
const TO_12 := Vector3(0.0, 0.0, -1.0)
const TO_9 := Vector3(-1.0, 0.0, 0.0)
const TO_3 := Vector3(1.0, 0.0, 0.0)
const TO_6 := Vector3(0.0, 0.0, 1.0)
const LEFTY: bool = true
const RIGHTY: bool = false

var _cfg := WristerLoad.Config.new()
var _out := WristerLoad.Result.new()


func _solve(puck: Vector3, aim: Vector3, left_handed: bool) -> WristerLoad.Result:
	WristerLoad.solve(_out, puck, aim, left_handed, _cfg)
	return _out


func test_forehand_forward_from_the_stick_side_is_full() -> void:
	var r := _solve(AT_9, TO_12, LEFTY)
	assert_false(r.is_backhand)
	assert_almost_eq(r.load_share, 1.0, 0.001)
	assert_almost_eq(r.wound_yaw, _cfg.max_twist_rad, 0.001,
			"a lefty's forehand winds the torso round to the left")


func test_puck_behind_the_stick_hip_is_fully_loaded() -> void:
	# The coached load: the puck drawn back behind the back foot.
	var behind := Vector3(-0.9 * sin(deg_to_rad(120.0)), 0.0, -0.9 * cos(deg_to_rad(120.0)))
	var r := _solve(behind, TO_12, LEFTY)
	assert_false(r.is_backhand)
	assert_almost_eq(r.load_share, 1.0, 0.001)


func test_backhand_from_out_on_the_stick_side_is_weak() -> void:
	var r := _solve(AT_9, TO_6, LEFTY)
	assert_true(r.is_backhand, "a lefty sweeping 9 → 6 is turning the backhand way")
	assert_lt(r.load_share, 0.15, "the mirror of the crossed-arms forehand")


func test_the_two_crossed_cases_mirror_each_other() -> void:
	var forehand: float = _solve(AT_3, TO_6, LEFTY).load_share
	assert_almost_eq(_solve(AT_9, TO_6, LEFTY).load_share, forehand, 0.001)


func test_puck_in_front_shot_forward_carries_nothing() -> void:
	assert_almost_eq(_solve(AT_12, TO_12, LEFTY).load_share, 0.0, 0.001,
			"the torso turns the puck sideways, not along the shot")


func test_shot_straight_out_from_the_body_carries_nothing() -> void:
	assert_almost_eq(_solve(AT_9, TO_9, LEFTY).load_share, 0.0, 0.001)


func test_sweep_across_the_front_is_a_full_forehand() -> void:
	var r := _solve(AT_12, TO_3, LEFTY)
	assert_false(r.is_backhand)
	assert_almost_eq(r.load_share, 1.0, 0.001)


func test_crossed_arms_forehand_is_weak() -> void:
	var r := _solve(AT_3, TO_6, LEFTY)
	assert_false(r.is_backhand, "a lefty sweeping 3 → 6 is turning the forehand way")
	assert_lt(r.load_share, 0.15, "the arms are crossed and the torso can't wind up")


func test_cross_body_backhand_forward_is_full() -> void:
	var r := _solve(AT_3, TO_12, LEFTY)
	assert_true(r.is_backhand)
	assert_almost_eq(r.load_share, 1.0, 0.001)
	assert_almost_eq(r.wound_yaw, -_cfg.max_twist_rad, 0.001,
			"the backhand winds toward the off side")


func test_right_handed_mirrors_left_handed() -> void:
	var r := _solve(AT_3, TO_12, RIGHTY)
	assert_false(r.is_backhand)
	assert_almost_eq(r.load_share, 1.0, 0.001)
	assert_almost_eq(r.wound_yaw, -_cfg.max_twist_rad, 0.001)
	assert_lt(_solve(AT_9, TO_6, RIGHTY).load_share, 0.15, "the righty's crossed-arms forehand")


func test_full_arc_then_linear_taper() -> void:
	# Puck at 9, aims swung off the forward tangent toward the stick side.
	assert_almost_eq(_solve(AT_9, _aim_off_forward(45.0), LEFTY).load_share, 1.0, 0.001,
			"45° off the tangent is still inside the full arc")
	assert_almost_eq(_solve(AT_9, _aim_off_forward(67.5), LEFTY).load_share, 0.5, 0.001,
			"halfway down the taper")


func test_zero_aim_leaves_the_shot_alone() -> void:
	var r := _solve(AT_9, Vector3.ZERO, LEFTY)
	assert_almost_eq(r.load_share, 1.0, 0.001)


# ── The arms ─────────────────────────────────────────────────────────────────

func test_arms_push_a_shot_straight_out_from_the_body() -> void:
	var r := _solve(AT_9, TO_9, LEFTY)
	assert_almost_eq(r.arm_share, 1.0, 0.001)
	assert_almost_eq(WristerLoad.power_share(r.load_share, r.arm_share, r.is_backhand, 0.6, 1.0),
			0.6, 0.001, "no turn behind it, but the arms still snap it out")


func test_a_puck_in_front_cannot_be_shot_back_through_the_body() -> void:
	for left_handed: bool in [LEFTY, RIGHTY]:
		var r := _solve(AT_12, TO_6, left_handed)
		assert_almost_eq(r.arm_share, 0.0, 0.001)
		assert_almost_eq(WristerLoad.power_share(r.load_share, r.arm_share, r.is_backhand,
				0.6, 0.75), 0.0, 0.001)


func test_arms_full_past_the_tangent_then_linear_taper() -> void:
	# Puck at 9, aims swung off the forward tangent toward the off side, i.e. in
	# toward the body.
	assert_almost_eq(_solve(AT_9, _aim_off_forward(0.0), LEFTY).arm_share, 1.0, 0.001,
			"along the tangent")
	assert_almost_eq(_solve(AT_9, _aim_off_forward(-45.0), LEFTY).arm_share, 1.0, 0.001,
			"45° past the tangent is still a full push")
	assert_almost_eq(_solve(AT_9, _aim_off_forward(-67.5), LEFTY).arm_share, 0.5, 0.001,
			"halfway down the taper")


func test_a_full_load_always_has_the_arms_behind_it() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xA4A5
	for i: int in 500:
		var puck := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0))
		var aim := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0))
		var r := _solve(puck, aim, rng.randf() < 0.5)
		if r.load_share > 0.999:
			assert_almost_eq(r.arm_share, 1.0, 0.001, "case %d" % i)


# A forward aim swung `deg` toward the left.
func _aim_off_forward(deg: float) -> Vector3:
	var a: float = deg_to_rad(deg)
	return Vector3(-sin(a), 0.0, -cos(a))
