extends GutTest

# AIStationSearch.drawn_open: what a man at a spot makes the defence give up
# elsewhere. The body nearest the spot is the one who comes to cover him, and
# what he leaves is the carrier's best feed to a teammate without him.

const GOAL := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z)
const CARRIER := Vector3(8.0, 0.0, -GameRules.GOAL_LINE_Z + 6.0)
# A teammate at the weak post side of the slot, a one-timer off the feed.
const MATE := Vector3(-2.0, 0.0, -GameRules.GOAL_LINE_Z + 5.0)
# One defender in the lane from the carrier to him, one far up the ice.
const IN_LANE := Vector3(3.0, 0.0, -GameRules.GOAL_LINE_Z + 5.5)
const FAR := Vector3(-6.0, 0.0, -GameRules.GOAL_LINE_Z + 14.0)


func _ctx() -> RoleContext:
	var ctx := RoleContext.new()
	ctx.attacking_goal_pos = GOAL
	ctx.scratch_opp_caps.clear()
	ctx.scratch_opp_caps.append(null)
	ctx.scratch_opp_caps.append(null)
	return ctx


func _keeper() -> Vector3:
	return GOAL + Vector3(0.0, 0.0, 0.6)


func _feed(opps: Array[Vector3]) -> float:
	return AIActionScoring.score_pass_value(CARRIER, MATE, GOAL, _keeper(), opps,
			AIPuckLane.expected_pass_speed(CARRIER, MATE), [], true)


func test_a_spot_that_draws_the_lane_defender_opens_the_feed_he_held() -> void:
	var opps: Array[Vector3] = [IN_LANE, FAR]
	var mates: Array[Vector3] = [MATE]
	AIStationSearch.fill_opened_values(_ctx(), CARRIER, _keeper(), opps, mates)
	var only_far: Array[Vector3] = [FAR]
	var only_lane: Array[Vector3] = [IN_LANE]
	assert_gt(_feed(only_far), _feed(opps), "the lane defender holds the feed shut")
	assert_almost_eq(AIStationSearch.drawn_open(IN_LANE + Vector3(0.5, 0.0, 0.0), opps),
			_feed(only_far), 1e-5, "drawing him opens it")
	assert_almost_eq(AIStationSearch.drawn_open(FAR + Vector3(0.5, 0.0, 0.0), opps),
			_feed(only_lane), 1e-5, "drawing the far man opens nothing he held")
	assert_gt(AIStationSearch.drawn_open(IN_LANE, opps), AIStationSearch.drawn_open(FAR, opps))


func test_nobody_to_come_concedes_nothing_elsewhere() -> void:
	var none: Array[Vector3] = []
	var mates: Array[Vector3] = [MATE]
	AIStationSearch.fill_opened_values(_ctx(), CARRIER, _keeper(), none, mates)
	assert_eq(AIStationSearch.drawn_open(MATE, none), INF, "with nobody to cover him, his own feed stands")
