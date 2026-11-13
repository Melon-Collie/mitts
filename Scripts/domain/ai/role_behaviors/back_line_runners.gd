class_name AIBackLineRunners
extends RefCounted

# The men still at speed beside a carrier the back line's D is playing. His
# stand and its ride are sized from the carrier alone (AIRoleRushD's ladder), so
# a carrier who slows brakes the D to his pace while a winger comes down the ice
# at his own, and the pass goes behind a man standing still. This bounds what
# the route may COMMAND; the stand keeps its place (Scripts/domain/ai/CLAUDE.md
# → "A defensive stand is a moving frame").


# Holds `d`'s route to at least the pace toward our net that the fastest runner
# nobody holds asks of this body (floor_pace), down to the house gate and no
# further. A stand with no ride (the puck in flight to nobody yet) is a point
# the bound cannot reach, so it rides back at that pace instead; the gate ends
# the ride.
static func hold_depth(ctx: RoleContext, d: RoleDecision) -> void:
	if ctx.rush_read == null or ctx.snapshot == null:
		return
	var our_net: Vector3 = ctx.defending_goal_pos
	var from_net: float = AIRoleReads.xz_distance(ctx.self_pos, our_net)
	if from_net <= AIZoneCoverage.HOUSE_TOP_DEPTH_M:
		return
	var pace: float = floor_pace(ctx, d.target_velocity, from_net,
			AIRoleRushD.retreat_max_speed(ctx, d.face_travel))
	if pace <= 0.0:
		return
	if d.retreat_floor_radius_m <= 0.0:
		d.retreat_floor_center = our_net
		d.retreat_floor_radius_m = AIZoneCoverage.HOUSE_TOP_DEPTH_M
	d.advance_cap_m_s = minf(d.advance_cap_m_s, -pace)
	if d.target_velocity == Vector3.ZERO:
		d.target_velocity = (our_net - ctx.self_pos) * (pace / from_net)
		d.target_velocity.y = 0.0


# The pace toward our net the fastest unheld runner asks of this body, `from_net`
# off it, whose route would otherwise settle him to `ride`; 0 when none binds.
#
# A runner is an attacker other than the carrier coming at our net at pace
# (AIRoleRushD.GAP_UP_CLOSING_M_S). He binds when the ground he gains on me
# while I build to his pace from the one I would settle to, on the better of my
# two retreats (AIRoleRushD.retreat_gains), is all the depth I hold on him past
# a stick. Then I keep his pace, or my retreat's top speed.
static func floor_pace(ctx: RoleContext, ride: Vector3, from_net: float,
		v_retreat: float) -> float:
	var runners: Array[int] = ctx.scratch_runners
	_collect_runners(ctx, runners)
	if runners.is_empty():
		return 0.0
	var held: Array[int] = ctx.scratch_held_runners
	_collect_held(ctx, runners, held)
	var our_net: Vector3 = ctx.defending_goal_pos
	var pace: float = 0.0
	for pid: int in runners:
		if held.has(pid):
			continue
		var s: SkaterNetworkState = ctx.snapshot.skater_states[pid]
		var dist: float = AIRoleReads.xz_distance(s.position, our_net)
		var depth: float = dist - from_net
		if depth <= 0.0:
			continue
		var dir: Vector3 = _dir_to(s.position, our_net, dist)
		var settle: float = minf(ride.x * dir.x + ride.z * dir.z,
				ctx.self_velocity.x * dir.x + ctx.self_velocity.z * dir.z)
		var gains: Vector2 = AIRoleRushD.retreat_gains(ctx, dir, s.velocity, dist, pid,
				AIRoleRushD.RETREAT_FINISH_M, settle)
		if depth - AIRoleRushD.stick_m(ctx) <= minf(gains.x, gains.y):
			pace = maxf(pace, minf(_closing(s, our_net), v_retreat))
	return pace


static func _collect_runners(ctx: RoleContext, out: Array[int]) -> void:
	out.clear()
	var read: AIRushRead = ctx.rush_read
	for pid: int in read.attackers:
		if pid == read.carrier_peer or not ctx.snapshot.skater_states.has(pid):
			continue
		if _closing(ctx.snapshot.skater_states[pid], ctx.defending_goal_pos) \
				>= AIRoleRushD.GAP_UP_CLOSING_M_S:
			out.append(pid)


# The runners a teammate holds, one each: a teammate holds the runner nearest
# him across the ice of those he is goal-side of on the race clock
# (AIRoleRushD.race_depth_on), a dead heat to the lower peer id.
static func _collect_held(ctx: RoleContext, runners: Array[int], out: Array[int]) -> void:
	out.clear()
	var our_net: Vector3 = ctx.defending_goal_pos
	for mate: int in ctx.snapshot.skater_states:
		if mate == ctx.peer_id or ctx.team_id_by_peer.get(mate, -1) != ctx.team_id:
			continue
		var ms: SkaterNetworkState = ctx.snapshot.skater_states[mate]
		if ms.is_ghost:
			continue
		var caps: AISkaterCaps = ctx.caps_by_peer.get(mate)
		var vmax: float = caps.max_speed if caps != null \
				else GameRules.DEFAULT_SKATER_MAX_SPEED_M_S
		var accel: float = caps.max_accel if caps != null \
				else GameRules.DEFAULT_SKATER_THRUST_M_S2
		var mate_net: float = AIRoleReads.xz_distance(ms.position, our_net)
		var pick: int = -1
		var pick_dx: float = INF
		for pid: int in runners:
			if mate_net > AIRoleRushD.race_depth_on(ctx, pid, ms.velocity, vmax, accel,
					AIRoleRushD.RETREAT_FINISH_M):
				continue
			var dx: float = absf(ms.position.x - ctx.snapshot.skater_states[pid].position.x)
			if dx < pick_dx or (dx == pick_dx and pid < pick):
				pick_dx = dx
				pick = pid
		if pick != -1 and not out.has(pick):
			out.append(pick)


static func _dir_to(from: Vector3, to: Vector3, dist: float) -> Vector3:
	if dist < 0.001:
		return Vector3.ZERO
	return Vector3((to.x - from.x) / dist, 0.0, (to.z - from.z) / dist)


# His speed toward our net, down his own line to it.
static func _closing(s: SkaterNetworkState, our_net: Vector3) -> float:
	var dist: float = AIRoleReads.xz_distance(s.position, our_net)
	var dir: Vector3 = _dir_to(s.position, our_net, dist)
	return s.velocity.x * dir.x + s.velocity.z * dir.z
