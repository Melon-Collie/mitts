extends GutTest

# FeatRules — the plays a credited goal earns, read from the host's
# GoalFeatContext. Each feat goes to the player who made the play.

const SCORER: int = 10
const FEEDER: int = 11


func _goal() -> GoalFeatContext:
	var ctx := GoalFeatContext.new()
	ctx.scorer = SCORER
	ctx.shooter = SCORER
	return ctx


func _feats(ctx: GoalFeatContext) -> Array[Dictionary]:
	return FeatRules.goal_feats(ctx)


func test_a_plain_goal_earns_nothing() -> void:
	assert_eq(_feats(_goal()).size(), 0)


func test_a_high_shot_from_beyond_the_dots_is_a_snipe() -> void:
	var ctx := _goal()
	ctx.loft_level = ShotMechanics.ELEVATION_HIGH
	ctx.release_distance_m = FeatRules.SNIPE_MIN_DISTANCE_M + 0.5
	assert_has(_feats(ctx), {"peer": SCORER, "feat": FeatRules.SNIPE})


func test_a_snipe_needs_both_the_loft_and_the_range() -> void:
	var close := _goal()
	close.loft_level = ShotMechanics.ELEVATION_HIGH
	close.release_distance_m = FeatRules.SNIPE_MIN_DISTANCE_M - 0.5
	assert_eq(_feats(close).size(), 0, "inside the dots")
	var low := _goal()
	low.loft_level = ShotMechanics.ELEVATION_MID
	low.release_distance_m = FeatRules.SNIPE_MIN_DISTANCE_M + 5.0
	assert_eq(_feats(low).size(), 0, "not the top rung")
	var unknown := _goal()
	unknown.loft_level = ShotMechanics.ELEVATION_HIGH
	assert_eq(_feats(unknown).size(), 0, "no tracked release, no distance")


func test_the_snipe_distance_is_the_dots_off_the_goal_line() -> void:
	assert_almost_eq(FeatRules.SNIPE_MIN_DISTANCE_M, 6.096, 0.001)


func test_a_lofted_backhand_is_a_shelf() -> void:
	var ctx := _goal()
	ctx.is_backhand = true
	ctx.loft_level = ShotMechanics.ELEVATION_MID
	assert_has(_feats(ctx), {"peer": SCORER, "feat": FeatRules.BACKHAND_SHELF})
	ctx.loft_level = ShotMechanics.ELEVATION_LOW
	assert_eq(_feats(ctx).size(), 0, "a low backhand is not")


func test_the_feed_for_a_one_timer_goal_earns_the_passer_the_feat() -> void:
	var ctx := _goal()
	ctx.is_one_timer = true
	ctx.primary_assist = FEEDER
	assert_eq(_feats(ctx), [{"peer": FEEDER, "feat": FeatRules.ONE_TIMER_FEED}] as Array[Dictionary])
	ctx.primary_assist = -1
	assert_eq(_feats(ctx).size(), 0, "an unassisted one-timer feeds nobody")


func test_a_tip_does_not_credit_the_shooter_s_shot_style() -> void:
	# The scorer tipped a teammate's high one-timer from distance: the shot was
	# not theirs, so no snipe and no feed.
	var ctx := _goal()
	ctx.shooter = FEEDER
	ctx.is_one_timer = true
	ctx.primary_assist = FEEDER
	ctx.loft_level = ShotMechanics.ELEVATION_HIGH
	ctx.release_distance_m = 20.0
	assert_eq(_feats(ctx).size(), 0)


func _one_timer_from(x: float, z: float) -> GoalFeatContext:
	var ctx := _goal()
	ctx.is_one_timer = true
	ctx.release_xz = Vector2(x, z)
	ctx.release_distance_m = GameRules.GOAL_LINE_Z - z
	return ctx


func test_a_one_timer_from_either_offensive_circle_is_from_the_dot() -> void:
	var dot_x: float = GameRules.END_ZONE_FACEOFF_DOT_X
	var dot_z: float = GameRules.ICING_FACEOFF_DOT_Z
	var rim: float = RinkMarkings.FACEOFF_CIRCLE_RADIUS_M - 0.05
	for x: float in [-dot_x, dot_x, dot_x + rim, -dot_x - rim]:
		assert_has(_feats(_one_timer_from(x, dot_z)),
				{"peer": SCORER, "feat": FeatRules.ONE_TIMER_DOT}, "x = %.2f" % x)
	assert_has(_feats(_one_timer_from(dot_x, dot_z + rim)),
			{"peer": SCORER, "feat": FeatRules.ONE_TIMER_DOT}, "the circle's goal side")


func test_from_the_dot_needs_a_one_timer_inside_a_circle() -> void:
	var dot_x: float = GameRules.END_ZONE_FACEOFF_DOT_X
	var dot_z: float = GameRules.ICING_FACEOFF_DOT_Z
	var outside: float = RinkMarkings.FACEOFF_CIRCLE_RADIUS_M + 0.05
	for at: Vector2 in [Vector2(0.0, dot_z), Vector2(dot_x, dot_z - outside),
			Vector2(dot_x, -dot_z)]:
		assert_does_not_have(_feats(_one_timer_from(at.x, at.y)),
				{"peer": SCORER, "feat": FeatRules.ONE_TIMER_DOT}, "from %s" % at)
	var wrister := _one_timer_from(dot_x, dot_z)
	wrister.is_one_timer = false
	assert_eq(_feats(wrister).size(), 0, "a shot that is not a one-timer")
	var unknown := _one_timer_from(dot_x, dot_z)
	unknown.release_distance_m = -1.0
	assert_eq(_feats(unknown).size(), 0, "a release nobody tracked")
	var tipped := _one_timer_from(dot_x, dot_z)
	tipped.shooter = FEEDER
	assert_eq(_feats(tipped).size(), 0, "a tip of someone else's one-timer")


func test_scoring_on_your_own_won_possession() -> void:
	var picked := _goal()
	picked.won_by = SCORER
	picked.won_kind = FeatRules.WON_INTERCEPTION
	assert_eq(_feats(picked), [{"peer": SCORER, "feat": FeatRules.PICK_AND_FINISH}] as Array[Dictionary])
	var stripped := _goal()
	stripped.won_by = SCORER
	stripped.won_kind = FeatRules.WON_TAKEAWAY
	assert_eq(_feats(stripped), [{"peer": SCORER, "feat": FeatRules.STRIP_AND_FINISH}] as Array[Dictionary])
	var teammate_won := _goal()
	teammate_won.won_by = FEEDER
	teammate_won.won_kind = FeatRules.WON_TAKEAWAY
	assert_eq(_feats(teammate_won).size(), 0, "a teammate's takeaway is not yours")


func test_an_own_goal_earns_nothing() -> void:
	var ctx := _goal()
	ctx.is_own_goal = true
	ctx.won_by = SCORER
	ctx.won_kind = FeatRules.WON_TAKEAWAY
	assert_eq(_feats(ctx).size(), 0)
