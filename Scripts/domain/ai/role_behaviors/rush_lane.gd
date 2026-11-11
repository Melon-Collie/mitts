class_name AIRoleRushLane

# LANE_L / LANE_R (5v5 TRANS_OFFENSE) — fill the two of the three rush lanes the
# carrier is not in, at pace: both wings with the carrier in the middle, the
# middle and the far wing with him on a wall. A man driving the middle pushes
# their D back off the line and opens the entry. Lead the play up-ice, but hold
# NZ-side of the attacking blue line until the puck crosses, so the body-level
# offside brake never has to slam.

const LANE_INSET_M: float = 4.0     # a wing lane off the boards
const LEAD_AHEAD_M: float = 5.0     # up-ice of the play reference
const LINE_HOLD_BACK_M: float = 0.8 # NZ-side stand-off at the blue line
# How far past his lane's edge the carrier must be before he is read in the next
# lane, so a carrier skating the edge does not swap the two fillers every tick.
const CARRIER_LANE_HYSTERESIS_M: float = 1.0


# A lane's x: -1 the left wing (−x), 0 the middle, 1 the right wing.
static func lane_x(lane: int) -> float:
	return float(lane) * (GameRules.RINK_HALF_WIDTH - LANE_INSET_M)


# The lane a carrier at `x` is in, holding `prev` until he is past its edge by
# the hysteresis.
static func carrier_lane(x: float, prev: int) -> int:
	var edge: float = lane_x(1) * 0.5
	if absf(x - lane_x(prev)) <= edge + CARRIER_LANE_HYSTERESIS_M:
		return prev
	if x < -edge:
		return -1
	return 1 if x > edge else 0


# The lane LANE_L (`side` -1) or LANE_R (`side` 1) fills: of the two lanes the
# carrier leaves free, the one on that side.
static func filled_lane(carrier: int, side: float) -> int:
	if side < 0.0:
		return 0 if carrier == -1 else -1
	return 0 if carrier == 1 else 1


static func decide(ctx: RoleContext, side: float) -> RoleDecision:
	var d := RoleDecision.new()
	var own_dir: float = ctx.own_goal_dir
	var play_ref: Vector3 = AIRoleReads.resolve_offensive_play_ref(ctx)
	if not play_ref.is_finite():
		d.target_position = ctx.self_pos
		return d

	var x: float = lane_x(filled_lane(ctx.carrier_lane, side))
	var z: float = play_ref.z - own_dir * LEAD_AHEAD_M
	var attacking_blue_z: float = -own_dir * GameRules.BLUE_LINE_Z
	var puck_in_zone: bool = own_dir * play_ref.z < own_dir * attacking_blue_z
	if not puck_in_zone:
		var hold_z: float = attacking_blue_z + own_dir * LINE_HOLD_BACK_M
		if own_dir * z < own_dir * hold_z:
			z = hold_z
	d.target_position = Vector3(x, 0.0, z)
	# The lane advances with the rush.
	d.arrive_at_speed = true
	return d
