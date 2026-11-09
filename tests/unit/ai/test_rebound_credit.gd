extends GutTest

# The rebound credit (docs/possession-floor-plan.md §2.3): a shot that reaches the
# net and is saved or missed still leaves a puck in their zone, some share of it
# ours again, credited at the zone's floor.

const GOAL := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z)
var _none: Array[Vector3] = []


func test_a_shot_with_no_odds_is_worth_its_rebound_and_a_sure_one_its_goal() -> void:
	var r: float = AIActionScoring.REBOUND_RECOVER_SHARE * AIPossessionFloor.FLOOR_THEIR_GOAL_LINE
	assert_almost_eq(AIActionScoring.with_rebound(0.0), r, 1e-9)
	assert_almost_eq(AIActionScoring.with_rebound(1.0), 1.0, 1e-9)
	var prev: float = -1.0
	for p: float in [0.0, 0.02, 0.1, 0.4, 0.9]:
		var v: float = AIActionScoring.with_rebound(p)
		assert_gt(v, prev, "rises with the odds, at %.2f" % p)
		assert_gte(v, p, "never below first contact, at %.2f" % p)
		prev = v


func test_the_seam_credits_it_only_when_asked() -> void:
	for spot: Vector3 in [Vector3(0, 0, -6), Vector3(-7, 0, -16), Vector3(3, 0, -24)]:
		var first: float = AIActionScoring.score_shoot_value(spot, GOAL, Vector3.INF, _none)
		var credited: float = AIActionScoring.score_shoot_value(spot, GOAL, Vector3.INF, _none,
				0.0, AIShotOdds.Stance.UPRIGHT, AIBotMechanics.WRISTER_SHOT_SPEED_M_S, [], -1.0,
				NAN, true)
		assert_almost_eq(credited, AIActionScoring.with_rebound(first), 1e-6,
				"on empty ice the credit is the whole difference, %s" % spot)


func test_no_credit_from_behind_the_goal_line() -> void:
	var behind := Vector3(-2.0, 0.0, -27.5)
	assert_eq(AIActionScoring.score_shoot_value(behind, GOAL, Vector3.INF, _none, 0.0,
			AIShotOdds.Stance.UPRIGHT, AIBotMechanics.WRISTER_SHOT_SPEED_M_S, [], -1.0, NAN,
			true), 0.0)


func test_a_blocked_shot_never_reaches_the_net_to_rebound() -> void:
	# Bodies on the release: the lane, not the keeper, stops it, and the rebound
	# is credited only on the share that gets through.
	var spot := Vector3(0.0, 0.0, -14.0)
	var wall: Array[Vector3] = [Vector3(0.0, 0.0, -14.8), Vector3(-0.6, 0.0, -14.7),
			Vector3(0.6, 0.0, -14.7)]
	var first: float = AIActionScoring.score_shoot_value(spot, GOAL, Vector3.INF, wall)
	assert_lt(first, 0.001, "the fixture all but blocks it")
	assert_lt(AIActionScoring.score_shoot_value(spot, GOAL, Vector3.INF, wall, 0.0,
			AIShotOdds.Stance.UPRIGHT, AIBotMechanics.WRISTER_SHOT_SPEED_M_S, [], -1.0, NAN,
			true), AIActionScoring.with_rebound(0.0) * 0.1,
			"the bodies take the rebound with the shot")
