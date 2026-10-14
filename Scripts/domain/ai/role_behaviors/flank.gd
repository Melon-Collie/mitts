class_name AIRoleFlank

# FLANK_L / FLANK_R (NEUTRAL, both team sizes) — stand off either side of a
# loose puck, slightly defensive, ready to support whoever gets it.
#
# A rigid offset off the puck alone is puckwatching, so the stand goes through
# AILastManDiscipline.neutral_station_target, which also demands somebody home behind
# me: exactly one body draws the layer. See Scripts/domain/ai/CLAUDE.md →
# "Last-man discipline".

# Lateral offset off the puck.
const FLANK_LATERAL_M: float = 3.0

# Depth back from the puck toward our net, so the flanks are already placed if
# the CHASE loses the race.
const FLANK_DEPTH_M: float = 2.0


# `lateral_sign` is -1 for FLANK_L, +1 for FLANK_R.
static func decide(ctx: RoleContext, lateral_sign: float) -> RoleDecision:
	var d := RoleDecision.new()
	if ctx.snapshot == null or ctx.snapshot.puck_state == null:
		d.target_position = ctx.self_pos
		return d
	var puck_pos: Vector3 = ctx.snapshot.puck_state.position
	var stand := Vector3(
			puck_pos.x + lateral_sign * FLANK_LATERAL_M,
			0.0,
			puck_pos.z + ctx.own_goal_dir * FLANK_DEPTH_M)
	# The LAYER's stand is the D post at our blue line — the stand 5v5's back pair
	# holds here. Never a puck-relative floor: it would be skated through the
	# moment anybody picks the puck up.
	d.target_position = AILastManDiscipline.neutral_station_target(
			ctx, stand, ctx.prev_held_forward_stand,
			AIZoneCoverage.defensive_anchor(
					true, ctx.self_home_side, ctx.defending_goal_pos.z))
	d.held_forward_stand = d.target_position.distance_to(stand) < 0.5
	return d
