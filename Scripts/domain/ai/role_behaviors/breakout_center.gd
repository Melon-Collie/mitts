class_name AIRoleBreakoutCenter

# BREAKOUT_C (5v5 BREAKOUT) — the center's low swing, the SECOND outlet under
# the breakout. Researched rules (docs/5v5-ai-plan.md appendix): swing low on
# the puck side, stay below the puck until the first pass, pace the carrier
# rather than park.
#
# The swing point sits SWING_BELOW_M goal-side of the carrier, in the mid lane
# or the carrier's-side circle lane — whichever the carrier reads the cleaner
# feed to (AIRoleReads.feed_lane).

const SWING_BELOW_M: float = 3.0       # goal-side of the carrier
const GOAL_LINE_PAD_M: float = 2.0
const MID_LANE_FRACTION: float = 0.5   # mirror the puck side, keep the middle
const CIRCLE_LANE_X_M: float = 6.0     # alternate: the carrier's-side circle lane


static func decide(ctx: RoleContext) -> RoleDecision:
	var d := RoleDecision.new()
	var own_dir: float = ctx.own_goal_dir
	var carrier_pos: Vector3 = AIRoleReads.resolve_offensive_play_ref(ctx)
	if not carrier_pos.is_finite():
		d.target_position = ctx.self_pos
		return d

	# Never behind our goal line.
	var cap: float = GameRules.GOAL_LINE_Z - GOAL_LINE_PAD_M
	var z: float = clampf(carrier_pos.z + own_dir * SWING_BELOW_M, -cap, cap)

	var mid := Vector3(carrier_pos.x * MID_LANE_FRACTION, 0.0, z)
	var circle := Vector3(signf(carrier_pos.x) * CIRCLE_LANE_X_M, 0.0, z)
	AIRoleReads.collect_feed_defence(ctx)
	var origin: Vector3 = AIRoleReads.feed_origin(ctx, carrier_pos)
	var lane_mid: float = AIRoleReads.feed_lane(ctx, origin, mid,
			AIRoleReads.feed_speed(ctx, origin, mid))
	var target: Vector3 = mid
	if lane_mid < 1.0 and AIRoleReads.feed_lane(ctx, origin, circle,
			AIRoleReads.feed_speed(ctx, origin, circle)) > lane_mid:
		target = circle
	if not AIStationSearch.is_legal_position(target):
		target = mid if target == circle else circle
	d.target_position = target
	# The swing paces the retrieval.
	d.arrive_at_speed = true
	return d
