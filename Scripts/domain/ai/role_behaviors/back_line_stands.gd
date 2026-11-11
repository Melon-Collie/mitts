class_name AIBackLineStands
extends RefCounted

# Where the back line's carrier D stands other than on the gap ladder
# (AIRoleRushD): held on our line while the carrier comes to it, and bracketed
# with his partner while the carrier has not picked a side of the pair.

# The stand on our line (AIRoleNeutralZone.line_depth_m) when `stand` would be
# up-ice of it: slid down the carrier's line to the line, inside the dots. INF
# when the stand is already at or inside it.
static func line_stand(ctx: RoleContext, ap: AICarrierApproach,
		stand: Vector3) -> Vector3:
	var line: float = AIRoleNeutralZone.line_depth_m()
	var over: float = AIRoleNeutralZone.depth_of(ctx, stand) - line
	if over <= 0.0:
		return Vector3.INF
	var toward: float = ctx.own_goal_dir * ap.dir_net.z
	var held: Vector3 = stand + ap.dir_net * (over / toward) if toward > 0.05 \
			else stand
	held.z = ctx.own_goal_dir * (GameRules.GOAL_LINE_Z - line)
	held.x = clampf(held.x, -GameRules.END_ZONE_FACEOFF_DOT_X,
			GameRules.END_ZONE_FACEOFF_DOT_X)
	return held


# Can a back man deep in his zone be SET on `held`, the line stand (there, his skate
# braked out) before the carrier eats the slack a man standing on it has — the
# ice from `standing_stand` (the stand a standing start needs) down to the line?
# Arriving with up-ice momentum in front of a carrier at speed is how he is
# walked back into his net.
static func set_on_line_in_time(ctx: RoleContext, ap: AICarrierApproach,
		held: Vector3, standing_stand: Vector3) -> bool:
	var d: float = AIRoleReads.xz_distance(ctx.self_pos, held)
	var arrive_v: float = minf(ctx.self_max_speed, sqrt(2.0 * ctx.self_max_accel * d))
	var t_set: float = AIArrival.time_to_arrive(ctx.self_pos, held, ctx.self_velocity,
			ctx.self_max_speed, ctx.self_max_accel) + arrive_v / AISteering.ARRIVAL_BRAKE_DECEL_M_S2
	var slack: float = (held - standing_stand).dot(ap.dir_net)
	return t_set <= AIRoleRushD.carrier_time_to(ctx, ap, maxf(slack, 0.0))


# How the line stand moves: across only, as the carrier's line to our net sweeps
# the line (similar triangles off the net), and not at all pinned at the dots.
static func line_ride(ctx: RoleContext, ap: AICarrierApproach,
		held: Vector3) -> Vector3:
	if absf(held.x) >= GameRules.END_ZONE_FACEOFF_DOT_X - 0.001:
		return Vector3.ZERO
	var carrier_depth: float = maxf(AIRoleNeutralZone.depth_of(ctx, ap.carrier_pos), 0.5)
	var k: float = AIRoleNeutralZone.line_depth_m() / carrier_depth
	return Vector3(k * (ap.carrier_vel.x
			+ ap.carrier_pos.x * ctx.own_goal_dir * ap.carrier_vel.z / carrier_depth),
			0.0, 0.0)


# 5v5: while the carrier's lead runs between the two back-line D, both goal-side
# of him, he has not picked a side, and the pair plays him together, each a
# stick off his line on his own side: no seam between them and no lane left by
# a man crossing to him. The side of the line this D is on (±1), else 0 — once
# the lead is outside one of them, he is that D's (AIRoleSlots.lane_owner) and
# the other goes back to his job.
static func bracket_side(ctx: RoleContext, slot: int) -> float:
	if ctx.team_size < 5 or ctx.team_brain == null or ctx.snapshot == null \
			or not AIRoleSlots.is_back_line_d(slot):
		return 0.0
	var read: AIRushRead = ctx.rush_read
	var i: int = read.attackers.find(read.carrier_peer) if read != null else -1
	if i == -1 or not ctx.snapshot.skater_states.has(read.carrier_peer):
		return 0.0
	var carrier_z: float = ctx.snapshot.skater_states[read.carrier_peer].position.z
	if ctx.own_goal_dir * (ctx.self_pos.z - carrier_z) <= 0.0:
		return 0.0
	var lead_x: float = read.attacker_leads[i].x
	var mine: float = ctx.self_pos.x - lead_x
	for pid: int in ctx.snapshot.skater_states:
		if pid == ctx.peer_id or ctx.team_id_by_peer.get(pid, -1) != ctx.team_id \
				or not AIRoleSlots.is_back_line_d(ctx.team_brain.get_slot(pid)):
			continue
		var mate: Vector3 = ctx.snapshot.skater_states[pid].position
		if ctx.own_goal_dir * (mate.z - carrier_z) > 0.0 and mine * (mate.x - lead_x) < 0.0:
			return signf(mine)
	return 0.0
