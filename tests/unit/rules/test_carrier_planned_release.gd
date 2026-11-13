extends GutTest

# ── The carrier plans where he releases (#946) ───────────────────────────────
# The rolled carry is worth its best shot on the way (AICarrierArrivalShot
# .best_on_path), placed between the path's reads at the peak through them; the
# carrier keeps that release point until a re-plan finds one clearly better or
# he passes it, and commits the shot once he reaches it before the next re-plan
# (AIRoleCarrier._plan_release), the press waiting for the point. The shot he
# prices meets the keeper down in tight (AIRoleCarrier._stance_met).

const GOAL := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z)
const TICK: float = 1.0 / float(preload("res://Scripts/game/constants.gd").PHYSICS_TICK)


func _ctx(off: float, speed: float, dispatch_ticks: int = 2) -> RoleContext:
	var ctx := RoleContext.new()
	ctx.attacking_goal_pos = GOAL
	ctx.self_pos = Vector3(0.0, 0.0, GOAL.z + off)
	ctx.self_velocity = Vector3(0.0, 0.0, -speed)
	ctx.dispatch_period_ticks = dispatch_ticks
	return ctx


# A carrier on a rolled carry whose search planned a release `off` metres off
# the goal line, worth `worth`, last re-evaluated `ticks` ago.
func _planning(off: float, worth: float, ticks: int) -> AIRoleCarrier:
	var c := AIRoleCarrier.new()
	c._carry_plan = AIRoleCarrier.CarryPlan.ROLLED
	c._carry.plan_release_pos = Vector3(0.0, 0.0, GOAL.z + off)
	c._carry.plan_release_value = worth
	c._ticks_since_pick = ticks
	return c


func test_a_release_in_tight_meets_the_keeper_down() -> void:
	var up: int = AIShotOdds.Stance.UPRIGHT
	assert_eq(AIRoleCarrier._stance_met(up, Vector3(0.0, 0.0, GOAL.z + 2.0), GOAL),
			AIShotOdds.Stance.DOWN, "he goes down for a carrier in tight before it leaves")
	assert_eq(AIRoleCarrier._stance_met(up, Vector3(0.0, 0.0, GOAL.z + 6.0), GOAL), up,
			"out of tight he is read as he stands")
	assert_eq(AIRoleCarrier._stance_met(AIShotOdds.Stance.DOWN,
			Vector3(0.0, 0.0, GOAL.z + 6.0), GOAL), AIShotOdds.Stance.DOWN)


func test_the_planned_point_is_kept_against_a_re_plan_no_clearly_better() -> void:
	var c := _planning(4.0, 0.80, 9)
	assert_eq(c._plan_release(_ctx(7.0, 9.0)), 0, "two metres on at pace is not yet due")
	c._carry.plan_release_pos = Vector3(0.0, 0.0, GOAL.z + 3.0)
	c._carry.plan_release_value = 0.80 * (1.0 + AIActionScoring.ACTION_HYSTERESIS_MARGIN_FRAC)
	c._plan_release(_ctx(6.5, 9.0))
	assert_almost_eq(c._planned_release.z, GOAL.z + 4.0, 0.001,
			"a re-plan only as good as the margin keeps the planned point")
	c._carry.plan_release_value = 0.80 * (1.0 + 2.0 * AIActionScoring.ACTION_HYSTERESIS_MARGIN_FRAC)
	c._plan_release(_ctx(6.5, 9.0))
	assert_almost_eq(c._planned_release.z, GOAL.z + 3.0, 0.001,
			"one clearly better replaces it")


func test_a_planned_point_comes_due_before_the_next_re_plan_would_pass_it() -> void:
	var c := _planning(4.0, 0.8, 9)
	var period_m: float = 9.0 * 9.0 * TICK
	assert_eq(c._plan_release(_ctx(4.0 + 0.9 * period_m, 9.0)), 1,
			"within a re-eval's skate of it: due")
	var far := _planning(4.0, 0.8, 9)
	assert_eq(far._plan_release(_ctx(4.0 + 1.5 * period_m, 9.0)), 0,
			"the next re-plan still comes before it")


func test_a_point_he_has_passed_is_dropped() -> void:
	var c := _planning(5.0, 0.8, 9)
	c._plan_release(_ctx(8.0, 9.0))
	c._carry.plan_release_pos = Vector3(0.0, 0.0, GOAL.z + 2.0)
	c._carry.plan_release_value = 0.1
	c._plan_release(_ctx(4.5, 9.0))
	assert_almost_eq(c._planned_release.z, GOAL.z + 2.0, 0.001,
			"past the planned point, the re-plan's is taken whatever it is worth")


func test_no_planned_shot_clears_the_plan() -> void:
	var c := _planning(4.0, 0.8, 9)
	c._plan_release(_ctx(7.0, 9.0))
	c._carry_plan = AIRoleCarrier.CarryPlan.DRIVE_IN
	assert_eq(c._plan_release(_ctx(6.0, 9.0)), -1)
	assert_false(c._planned_release.is_finite())


func test_the_path_best_sits_at_the_peak_between_its_reads() -> void:
	var a := AICarrierArrivalShot.new()
	a.best_t = 1.0
	a.best_pos = Vector3(0.0, 0.0, 10.0)
	a._refine(0.5, 0.8, Vector3(0.0, 0.0, 15.0), 1.0, 1.5, 0.6, Vector3(0.0, 0.0, 5.0))
	assert_between(a.best_t, 0.5, 1.0, "the peak leans to the better neighbour")
	assert_almost_eq(a.best_t, 1.0 - 0.5 * 0.05 / 0.3, 0.0001)
	assert_almost_eq(a.best_pos.z, lerpf(15.0, 10.0, (a.best_t - 0.5) / 0.5), 0.0001,
			"the point is the path's at that time")
	var even := AICarrierArrivalShot.new()
	even.best_t = 1.0
	even.best_pos = Vector3(0.0, 0.0, 10.0)
	even._refine(0.5, 0.8, Vector3(0.0, 0.0, 15.0), 1.0, 1.5, 0.8, Vector3(0.0, 0.0, 5.0))
	assert_almost_eq(even.best_t, 1.0, 0.0001, "even neighbours keep the read")
