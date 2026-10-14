extends GutTest

# XGBaseline — the public-style (location + angle + type) xG model. Its
# head-to-head against the goalie-aware geometric model is the instrument
# tests/instruments/rules/test_xg_head_to_head.gd.
#
# The anchors below are the NHL aggregates the coefficients were solved to
# reproduce; they're what makes this a usable BASELINE rather than another
# hand-shaped curve.

const GOAL_Z: float = -GameRules.GOAL_LINE_Z   # team 0 attacks -Z


# Distance straight out from the goal mouth, centred.
func _centred(dist: float) -> float:
	return XGBaseline.for_shot(0.0, GOAL_Z + dist, 0, ShotEvent.ShotType.SHOT)


func test_in_tight_anchor() -> void:
	assert_almost_eq(_centred(3.0), 0.40, 0.06,
			"3 m centred ≈ 0.40 (NHL in-tight aggregate)")


func test_mid_slot_anchor() -> void:
	assert_almost_eq(_centred(8.0), 0.12, 0.05,
			"8 m centred ≈ 0.12 (mid-slot)")


func test_point_shot_anchor() -> void:
	assert_almost_eq(_centred(20.0), 0.03, 0.02,
			"20 m centred ≈ 0.03 (point shot)")


func test_value_falls_with_distance() -> void:
	var prev: float = 1.0
	for d: float in [1.0, 3.0, 6.0, 10.0, 15.0, 22.0]:
		var v: float = _centred(d)
		assert_lt(v, prev, "xG falls monotonically with distance (at %.0f m)" % d)
		prev = v


func test_angle_costs_value() -> void:
	# Same distance, straight on vs a sharp angle off the post.
	var straight: float = XGBaseline.for_shot(0.0, GOAL_Z + 8.0, 0, ShotEvent.ShotType.SHOT)
	var sharp: float = XGBaseline.for_shot(8.0, GOAL_Z + 2.0, 0, ShotEvent.ShotType.SHOT)
	assert_lt(sharp, straight, "a sharp-angle look is worth less than straight on")


func test_sixty_degrees_roughly_halves() -> void:
	# 60° off-centre at ~8 m: along = 4, across = 6.93.
	var straight: float = _centred(8.0)
	var angled: float = XGBaseline.for_shot(6.93, GOAL_Z + 4.0, 0, ShotEvent.ShotType.SHOT)
	assert_almost_eq(angled / straight, 0.5, 0.22,
			"60° off-centre is roughly half value")


func test_shot_type_bumps_value() -> void:
	var plain: float = XGBaseline.for_shot(0.0, GOAL_Z + 6.0, 0, ShotEvent.ShotType.SHOT)
	var one_t: float = XGBaseline.for_shot(0.0, GOAL_Z + 6.0, 0, ShotEvent.ShotType.ONE_TIMER)
	var tip: float = XGBaseline.for_shot(0.0, GOAL_Z + 6.0, 0, ShotEvent.ShotType.TIP)
	assert_gt(one_t, plain, "a one-timer is worth more than a plain shot")
	assert_gt(tip, one_t, "a tip is worth more still")


func test_team_one_attacks_the_other_end() -> void:
	# The mirrored shot for team 1 must value identically.
	var t0: float = XGBaseline.for_shot(1.0, GOAL_Z + 6.0, 0, ShotEvent.ShotType.SHOT)
	var t1: float = XGBaseline.for_shot(1.0, -GOAL_Z - 6.0, 1, ShotEvent.ShotType.SHOT)
	assert_almost_eq(t0, t1, 0.0001, "the model is end-agnostic")


func test_bounded() -> void:
	for d: float in [0.1, 0.5, 2.0, 30.0, 55.0]:
		var v: float = _centred(d)
		assert_between(v, 0.0, 1.0, "bounded at %.1f m" % d)
