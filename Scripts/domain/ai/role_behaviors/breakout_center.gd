class_name AIRoleBreakoutCenter

# BREAKOUT_C (5v5 BREAKOUT) — the center's low swing, the SECOND outlet under
# the breakout. Researched rules (docs/5v5-ai-plan.md appendix): swing low on
# the puck side, stay below the puck until the first pass, pace the carrier
# rather than park.
#
# The swing point sits SWING_BELOW_M goal-side of the carrier, in the mid lane
# or the carrier's-side circle lane — whichever the carrier has the cleaner
# lane_clear to.

const SWING_BELOW_M: float = 3.0       # goal-side of the carrier
const GOAL_LINE_PAD_M: float = 2.0
const MID_LANE_FRACTION: float = 0.5   # mirror the puck side, keep the middle
const CIRCLE_LANE_X_M: float = 6.0     # alternate: the carrier's-side circle lane


static func decide(ctx: RoleContext) -> RoleDecision:
	var d := RoleDecision.new()
	var own_dir: float = ctx.own_goal_dir
	var carrier_pos: Vector3 = AIRoleHelpers.resolve_offensive_play_ref(ctx)
	if not carrier_pos.is_finite():
		d.target_position = ctx.self_pos
		return d

	var opp_positions: Array[Vector3] = ctx.scratch_opp_positions
	var opp_states: Array[SkaterNetworkState] = ctx.scratch_opp_states
	AIRoleHelpers.collect_opponents(ctx, opp_positions, opp_states)

	# Never behind our goal line.
	var cap: float = GameRules.GOAL_LINE_Z - GOAL_LINE_PAD_M
	var z: float = clampf(carrier_pos.z + own_dir * SWING_BELOW_M, -cap, cap)

	var mid := Vector3(carrier_pos.x * MID_LANE_FRACTION, 0.0, z)
	var circle := Vector3(signf(carrier_pos.x) * CIRCLE_LANE_X_M, 0.0, z)
	var pass_speed_mid: float = AIPuckLane.expected_pass_speed(carrier_pos, mid)
	var pass_speed_circle: float = AIPuckLane.expected_pass_speed(carrier_pos, circle)
	var lane_mid: float = AIPuckLane.lane_clear(
			carrier_pos, mid, opp_positions, pass_speed_mid,
			AIActionScoring.EMPTY_VEC3, ctx.scratch_opp_caps)
	var lane_circle: float = AIPuckLane.lane_clear(
			carrier_pos, circle, opp_positions, pass_speed_circle,
			AIActionScoring.EMPTY_VEC3, ctx.scratch_opp_caps)
	var target: Vector3 = mid if lane_mid >= lane_circle else circle
	if not AIRoleHelpers.is_legal_position(target):
		target = mid if target == circle else circle
	d.target_position = target
	# The swing paces the retrieval.
	d.arrive_at_speed = true
	return d
