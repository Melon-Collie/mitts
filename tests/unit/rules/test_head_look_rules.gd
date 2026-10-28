extends GutTest

const T := HeadLookRules.Target
const MAX: float = PI / 3.0


func test_without_the_puck_the_head_watches_it() -> void:
	assert_eq(HeadLookRules.target(false, false, true), T.PUCK)


func test_a_carrier_looks_at_the_net() -> void:
	assert_eq(HeadLookRules.target(true, false, true), T.NET)
	assert_eq(HeadLookRules.target(true, true, true), T.NET)


# The one-timer's committed swing: the puck is not carried, the shot is aimed.
func test_an_aimed_shot_looks_at_the_net() -> void:
	assert_eq(HeadLookRules.target(false, true, true), T.NET)


func test_a_parked_puck_is_not_watched() -> void:
	assert_eq(HeadLookRules.target(false, false, false), T.NONE)
	assert_eq(HeadLookRules.target(true, false, false), T.NET)


func test_puck_in_play() -> void:
	assert_true(HeadLookRules.is_puck_in_play(Vector3.ZERO))
	assert_true(HeadLookRules.is_puck_in_play(Vector3(0.0, 0.0, GameRules.GOAL_LINE_Z)))
	assert_false(HeadLookRules.is_puck_in_play(Vector3(100.0, 0.0, 100.0)))


func test_each_team_looks_at_the_other_end() -> void:
	var net_0: Vector3 = HeadLookRules.attacking_net(0)
	var net_1: Vector3 = HeadLookRules.attacking_net(1)
	assert_almost_eq(absf(net_0.z), GameRules.GOAL_LINE_Z, 1e-6)
	assert_almost_eq(net_0.z, -net_1.z, 1e-6)


func test_yaw_turns_toward_the_side_the_target_is_on() -> void:
	assert_almost_eq(HeadLookRules.yaw(Vector3(0.0, 0.0, -5.0), 0.0, MAX), 0.0, 1e-6)
	assert_gt(HeadLookRules.yaw(Vector3(1.0, 0.0, -5.0), 0.0, MAX), 0.0)
	assert_lt(HeadLookRules.yaw(Vector3(-1.0, 0.0, -5.0), 0.0, MAX), 0.0)


func test_yaw_is_clamped() -> void:
	assert_almost_eq(HeadLookRules.yaw(Vector3(5.0, 0.0, 0.0), 0.0, MAX), MAX, 1e-6)
	assert_almost_eq(HeadLookRules.yaw(Vector3(-5.0, 0.0, 0.0), 0.0, MAX), -MAX, 1e-6)


func test_a_target_on_top_of_the_skater_is_straight_ahead() -> void:
	assert_eq(HeadLookRules.yaw(Vector3(0.001, 1.0, 0.001), 0.4, MAX), 0.0)


# Crossing straight behind must not swing the head from one limit to the other.
func test_straight_behind_holds_the_side_it_is_turned_to() -> void:
	var just_left_of_behind := Vector3(-0.2, 0.0, 5.0)
	assert_almost_eq(HeadLookRules.yaw(just_left_of_behind, MAX, MAX), MAX, 1e-6)
	assert_almost_eq(HeadLookRules.yaw(just_left_of_behind, 0.0, MAX), -MAX, 1e-6)
	# Well round to the side, the hold lets go.
	assert_almost_eq(HeadLookRules.yaw(Vector3(-5.0, 0.0, 1.0), MAX, MAX), -MAX, 1e-6)
