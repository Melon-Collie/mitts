extends GutTest

# The value seam (AIShotValue): every shot the carrier ranks is priced through it,
# so these hold its contract whatever the measured field says. The levels are
# the field's, held against the live goalie by test_shot_odds_vs_truth.gd.

const GOAL_Z: float = -GameRules.GOAL_LINE_Z


func _goal() -> Vector3:
	return Vector3(0.0, 0.0, GOAL_Z)


func test_a_set_keeper_is_a_still_upright_keeper_on_his_square() -> void:
	var goal: Vector3 = _goal()
	for release: Vector3 in [Vector3(0.0, 0.0, GOAL_Z + 6.0),
			Vector3(-4.0, 0.0, GOAL_Z + 3.0), Vector3(5.0, 0.0, GOAL_Z + 10.0)]:
		var square := Vector3(0.0, 0.0, GOAL_Z + 1.2)
		for i: int in 4:
			square.x = AIGoalieModel.goalie_arc_match_x(square, goal, release)
		assert_almost_eq(AIShotValue.set_keeper(release, goal),
				AIShotOdds.shot_now(release, goal, square, 0.0, AIShotOdds.Stance.UPRIGHT),
				1e-3, "square, still and upright is the set keeper at %s" % release)


func test_a_keeper_out_of_his_home_range_leaves_an_empty_net() -> void:
	var goal: Vector3 = _goal()
	var release := Vector3(2.0, 0.0, GOAL_Z + 12.0)
	var pulled := Vector3(0.0, 0.0, 0.0)
	assert_almost_eq(AIShotValue.now(release, goal, pulled, 0.0,
			AIShotOdds.Stance.UPRIGHT),
			AIShotOdds.empty_net(release, goal), 1e-6)
	assert_gt(AIShotOdds.empty_net(release, goal), AIShotValue.set_keeper(release, goal),
			"an empty net is worth more than one with a set keeper in it")


func test_an_empty_net_is_easier_the_closer_you_are() -> void:
	var goal: Vector3 = _goal()
	var prev: float = 1.0
	for d: float in [2.0, 6.0, 15.0, 30.0, 50.0]:
		var p: float = AIShotOdds.empty_net(Vector3(0.0, 0.0, GOAL_Z + d), goal)
		assert_lte(p, prev, "%.0f m is no easier than closer in" % d)
		prev = p


func test_bounded_and_nothing_from_behind_the_goal_line() -> void:
	var goal: Vector3 = _goal()
	var keeper := Vector3(0.3, 0.0, GOAL_Z + 1.3)
	for x: float in [-8.0, -2.0, 0.0, 3.0, 9.0]:
		for fwd: float in [-2.0, 0.0, 1.0, 4.0, 9.0, 16.0, 30.0]:
			var r := Vector3(x, 0.0, GOAL_Z + fwd)
			for v: float in [AIShotValue.now(r, goal, keeper, 1.5,
					AIShotOdds.Stance.UPRIGHT),
					AIShotValue.set_keeper(r, goal), AIShotOdds.empty_net(r, goal),
					AIShotValue.feed(r + Vector3(3.0, 0.0, 0.0), r, 15.0, goal, keeper, true)]:
				assert_between(v, 0.0, 1.0)
				if fwd <= 0.0:
					assert_eq(v, 0.0, "no shot from on or behind the goal line")
