class_name FeatRules
## Pure detection of the Game Puck feats (GamePucks rows of kind "feat") a
## credited goal earns, from what the host knew about it (GoalFeatContext).
## Returns { "peer", "feat" } pairs; every feat it can return is in ALL.

const SNIPE := "snipe"
const BACKHAND_SHELF := "backhand_shelf"
const ONE_TIMER_FEED := "one_timer_feed"
const PICK_AND_FINISH := "pick_and_finish"
const STRIP_AND_FINISH := "strip_and_finish"
const ONE_TIMER_DOT := "one_timer_dot"
const ALL: Array[String] = [SNIPE, BACKHAND_SHELF, ONE_TIMER_FEED, PICK_AND_FINISH,
		STRIP_AND_FINISH, ONE_TIMER_DOT]

const WON_INTERCEPTION := "interception"
const WON_TAKEAWAY := "takeaway"

# "Beyond the dots": released farther from the goal line than the end-zone
# faceoff dots sit.
const SNIPE_MIN_DISTANCE_M: float = GameRules.GOAL_LINE_Z - GameRules.ICING_FACEOFF_DOT_Z


static func goal_feats(ctx: GoalFeatContext) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if ctx == null or ctx.is_own_goal or ctx.scorer == -1:
		return out
	var own_shot: bool = ctx.shooter == ctx.scorer
	if own_shot and ctx.loft_level == ShotMechanics.ELEVATION_HIGH \
			and ctx.release_distance_m >= SNIPE_MIN_DISTANCE_M:
		out.append({"peer": ctx.scorer, "feat": SNIPE})
	if own_shot and ctx.is_backhand and ctx.loft_level >= ShotMechanics.ELEVATION_MID:
		out.append({"peer": ctx.scorer, "feat": BACKHAND_SHELF})
	if own_shot and ctx.is_one_timer and ctx.primary_assist != -1:
		out.append({"peer": ctx.primary_assist, "feat": ONE_TIMER_FEED})
	if own_shot and ctx.is_one_timer and ctx.release_distance_m >= 0.0 \
			and in_offensive_circle(ctx.release_xz):
		out.append({"peer": ctx.scorer, "feat": ONE_TIMER_DOT})
	if ctx.won_by == ctx.scorer:
		match ctx.won_kind:
			WON_INTERCEPTION:
				out.append({"peer": ctx.scorer, "feat": PICK_AND_FINISH})
			WON_TAKEAWAY:
				out.append({"peer": ctx.scorer, "feat": STRIP_AND_FINISH})
	return out


# Whether a release point (GoalFeatContext.release_xz, the goal scored on at
# +z) is inside either faceoff circle in the zone of that goal.
static func in_offensive_circle(release_xz: Vector2) -> bool:
	for x: float in [-GameRules.END_ZONE_FACEOFF_DOT_X, GameRules.END_ZONE_FACEOFF_DOT_X]:
		if release_xz.distance_to(Vector2(x, GameRules.ICING_FACEOFF_DOT_Z)) \
				<= GameRules.FACEOFF_CIRCLE_RADIUS_M:
			return true
	return false
