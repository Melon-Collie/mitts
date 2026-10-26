class_name AIRoleDefenseman

# The off-puck defenseman (5v5 only). Design: docs/5v5-ai-plan.md §4 and its
# appendix.
#
#   OZONE points (POINT_STRONG / POINT_WEAK) — hold the offensive blue line and
#     walk it for a shooting lane; the strong point sinks down his wall as the
#     cycle goes low.
#   FORECHECK line pair (DP_STRONG / DP_WEAK) — hold the line per lane, keep
#     wall clears in, go home once their breakout is under way. The strong D
#     alone may PINCH.
#   TRANS_OFFENSE safety valve (DVALVE) — trail the rush centrally.
#   NEUTRAL back pair (DBACK_L / DBACK_R) — goal-side at our blue line inside
#     the dots, shading with the puck.
#
# Every stand goes through the shared station read
# (AILastManDiscipline.offensive_station_target / neutral_station_target).
#
# THE ROTATION. While the strong-side D is deeper than any stand his slot takes,
# the weak D slides to the middle of the line and a forward takes the vacated
# strong point — HIGH_SLOT in the O-zone, F2_WEAK on the forecheck, via
# rotate_up_to_point from his own role.

# How far inside the offensive zone the points stand: a full puck-handling
# radius, so a reception's give or a backswing never drags the puck back across
# the line.
const POINT_INSET_M: float = 2.0
# The strong point's sink rows down his wall while the puck is within
# POINT_SINK_PUCK_DEPTH_M of their goal line.
const POINT_SINK_M: float = 3.5
const POINT_SINK_ROWS: int = 2
const POINT_SINK_PUCK_DEPTH_M: float = 6.0
# Lateral walk-the-line samples (strong-signed u = s·x), wall → middle.
const POINT_STRONG_LANES_U: Array[float] = [9.5, 7.5, 5.5, 3.5, 1.5]
const POINT_WEAK_LANES_U: Array[float] = [6.0, 4.5, 3.0, 1.5, 0.0]
# Forecheck line pair lanes (world-x magnitude, inside the dots).
const DP_STRONG_LANE_X_M: float = 6.7
const DP_WEAK_LANE_X_M: float = 5.0
# Forecheck line-hold stand, this far INSIDE the offensive blue line: inside so
# it can keep pucks in, under a stick so stepping back out is one stride.
const DP_LINE_INSET_M: float = 1.0
# DVALVE: how far behind the play it trails, and its pad off our goal line.
const DVALVE_TRAIL_M: float = 10.0
const DVALVE_GOAL_LINE_PAD_M: float = 2.0
# DBACK posts: inside the dots at our blue line, with a small puck shade.
const DBACK_X_M: float = 5.0
const DBACK_PUCK_SHADE: float = 0.2
const DBACK_SHADE_MAX_M: float = 1.5

# ── Rim keep-ins (docs/breakout-plan.md, Phase C) ────────────────────────────
# The walk-the-line stands hold the line OFF the wall, so a rim up it would sail
# out untouched.
# A FIRED clear; slower loose pucks are the chase election's business.
const RIM_MIN_SPEED_M_S: float = 8.0
const RIM_KEEPIN_WALL_INSET_M: float = 1.0

# ── The pinch and its rotation (docs/5v5-ai-plan.md: "D pinches, F3 fills") ──
# One stick of slack past the deepest stand a strong-D slot ever takes: beyond
# it he has left the point, short of it he is merely sinking with the cycle.
const POINT_VACATED_SLACK_M: float = \
		GameRules.DEFAULT_STICK_LENGTH_M + GameRules.DEFAULT_BLADE_LENGTH_M
# A filler whose last target sat this close to the vacated stand is already
# covering it — generous, because the leash and numbers bound move the target.
const ROTATION_HELD_M: float = 3.0
# The weak D's lanes while his partner is down the wall (weak-signed u, so the
# negative entry is the strong side of centre): the middle of the line.
const POINT_WEAK_COVER_LANES_U: Array[float] = [1.5, 0.0, -1.5]
# How far down his wall the strong D may pinch, off their blue line: to
# F2_STRONG's post (AIRoleForecheck.F2_STRONG_DEPTH_OFF_GOAL_M), which owns the
# wall below. test_role_defenseman holds the two together.
const PINCH_MAX_DEPTH_M: float = 7.36


static func decide(ctx: RoleContext, slot: int) -> RoleDecision:
	match slot:
		AIRoleSlots.Slot.POINT_STRONG:
			return _decide_point(ctx, true)
		AIRoleSlots.Slot.POINT_WEAK:
			return _decide_point(ctx, false)
		AIRoleSlots.Slot.DP_STRONG:
			return _decide_line_hold(ctx, ctx.strong_x * DP_STRONG_LANE_X_M, true)
		AIRoleSlots.Slot.DP_WEAK:
			return _decide_line_hold(ctx, -ctx.strong_x * DP_WEAK_LANE_X_M, false)
		AIRoleSlots.Slot.DVALVE:
			return _decide_valve(ctx)
		AIRoleSlots.Slot.DBACK_L:
			return _decide_back(ctx, -1.0)
		AIRoleSlots.Slot.DBACK_R:
			return _decide_back(ctx, 1.0)
		_:
			# Unreachable from the dispatcher; hold rather than target the origin.
			var d := RoleDecision.new()
			d.target_position = ctx.self_pos
			return d


# ── OZONE point play: hold the line, walk it for a lane ─────────────────────
static func _decide_point(ctx: RoleContext, is_strong: bool) -> RoleDecision:
	var d := RoleDecision.new()
	var own_dir: float = ctx.own_goal_dir
	var opp_net: Vector3 = ctx.attacking_goal_pos
	var line_z: float = -own_dir * (GameRules.BLUE_LINE_Z + POINT_INSET_M)
	var side: float = ctx.strong_x if is_strong else -ctx.strong_x

	# A rim coming up MY wall that I can win: kill it at the boards, at pace.
	var keepin: Vector3 = wall_rim_keepin(ctx, side)
	if keepin.is_finite():
		d.target_position = keepin
		d.arrive_at_speed = true
		return d

	var opp_positions: Array[Vector3] = ctx.scratch_opp_positions
	var opp_states: Array[SkaterNetworkState] = ctx.scratch_opp_states
	AIRoleReads.collect_opponents(ctx, opp_positions, opp_states)
	var teammates: Array[Vector3] = ctx.scratch_teammates
	AIRoleReads.collect_teammates_excluding_self(ctx, teammates)
	# Puck depth off the ATTACKED goal line.
	var puck_depth: float = INF
	if ctx.snapshot != null and ctx.snapshot.puck_state != null:
		puck_depth = AIZoneCoverage.depth_of(
				opp_net.z, ctx.snapshot.puck_state.position)
	var allow_sink: bool = is_strong and puck_depth < POINT_SINK_PUCK_DEPTH_M

	var lanes: Array[float] = POINT_STRONG_LANES_U if is_strong else POINT_WEAK_LANES_U
	# The rotation's weak-D half: partner down the wall → hold the middle.
	if not is_strong and _partner_vacated(ctx, AIRoleSlots.Slot.POINT_STRONG):
		lanes = POINT_WEAK_COVER_LANES_U
	var shot_speed: float = ctx.self_wrister_shot_speed
	var base_stand := Vector3(side * lanes[0], 0.0, line_z)
	var best_pos: Vector3 = base_stand
	var best_score: float = -INF
	for u: float in lanes:
		for row: int in (POINT_SINK_ROWS + 1 if allow_sink else 1):
			var z: float = line_z - own_dir * (POINT_SINK_M * float(row))
			var c := Vector3(side * u, 0.0, z)
			if not AIStationSearch.is_legal_position(c):
				continue
			if AIStationSearch.too_close_to_teammate(c, teammates):
				continue
			# Walking the line: could I get my point shot through from here?
			var lane: float = AIPuckLane.lane_clear(
					c, opp_net, opp_positions, shot_speed,
					AIActionScoring.EMPTY_VEC3, ctx.scratch_opp_caps)
			var score: float = lane + AIStationSearch.incumbent_bonus(ctx, c)
			if score > best_score:
				best_score = score
				best_pos = c
	if best_score == -INF:
		best_pos = base_stand
	d.target_position = AILastManDiscipline.offensive_station_target(
			ctx, best_pos, ctx.prev_held_forward_stand)
	d.held_forward_stand = d.target_position.distance_to(best_pos) < 0.5
	return d


# The keep-in stand for a fired loose puck whose PREDICTED path (the chase
# election's walk, caroms included) crosses the keep-in line in `side`'s wall
# lane outside the dots — the crossing, just inside the zone — or Vector3.INF
# when there is none or I lose the race to it. Whose rim it was does not enter.
static func wall_rim_keepin(ctx: RoleContext, side: float) -> Vector3:
	if ctx.snapshot == null or ctx.snapshot.puck_state == null:
		return Vector3.INF
	var puck: PuckNetworkState = ctx.snapshot.puck_state
	if puck.carrier_peer_id != -1:
		return Vector3.INF
	if Vector2(puck.velocity.x, puck.velocity.z).length() < RIM_MIN_SPEED_M_S:
		return Vector3.INF
	var own_dir: float = ctx.own_goal_dir
	var stand := Vector3(
			side * (GameRules.INNER_HALF_WIDTH - RIM_KEEPIN_WALL_INSET_M),
			0.0, -own_dir * (GameRules.BLUE_LINE_Z + 0.5))
	# Already past the line: the TRANS flip owns it.
	if (puck.position.z - stand.z) * own_dir >= 0.0:
		return Vector3.INF
	var traj: Array[Vector3] = AILoosePuckChase.race_trajectory(
			puck.position, puck.velocity)
	var step_dt: float = AILoosePuckChase.RACE_LOOKAHEAD_S \
			/ float(AILoosePuckChase.RACE_STEPS)
	var prev: Vector3 = puck.position
	for i: int in traj.size():
		var p: Vector3 = traj[i]
		var past: float = (p.z - stand.z) * own_dir
		if past >= 0.0:
			var before: float = (stand.z - prev.z) * own_dir
			var f: float = before / maxf(before + past, 0.001)
			var cross_x: float = lerpf(prev.x, p.x, f)
			if signf(cross_x) != signf(side) \
					or absf(cross_x) < GameRules.END_ZONE_FACEOFF_DOT_X:
				return Vector3.INF
			stand.x = side * minf(absf(cross_x),
					GameRules.INNER_HALF_WIDTH - RIM_KEEPIN_WALL_INSET_M)
			var t_me: float = AIArrival.time_to_arrive(
					ctx.self_pos, stand, ctx.self_velocity,
					ctx.self_max_speed, ctx.self_max_accel, ctx.self_lateral_grip)
			return stand if t_me <= (float(i) + f) * step_dt else Vector3.INF
		prev = p
	return Vector3.INF


# ── FORECHECK: hold the line on the lane, or go home ────────────────────────
# Two things pre-empt the hold: a rim keep-in (either D — the stand is still the
# line) and the strong D's pinch. Never let both D pinch: every failed forecheck
# becomes an odd-man rush. See Scripts/domain/ai/CLAUDE.md → "A pinch is priced
# on both halves".
static func _decide_line_hold(ctx: RoleContext, lane_x: float,
		is_strong: bool) -> RoleDecision:
	var d := RoleDecision.new()
	var own_dir: float = ctx.own_goal_dir
	var line_z: float = -own_dir * (GameRules.BLUE_LINE_Z + DP_LINE_INSET_M)

	var keepin: Vector3 = wall_rim_keepin(ctx, signf(lane_x))
	if keepin.is_finite():
		d.target_position = keepin
		d.arrive_at_speed = true
		return d

	var line_stand := Vector3(lane_x, 0.0, line_z)
	if is_strong:
		var pinch: RoleDecision = _wall_pinch(ctx, signf(lane_x), line_stand)
		if pinch != null:
			return pinch
	elif _partner_vacated(ctx, AIRoleSlots.Slot.DP_STRONG):
		# The rotation's weak-D half.
		line_stand.x = 0.0
	d.target_position = AILastManDiscipline.offensive_station_target(
			ctx, line_stand, ctx.prev_held_forward_stand)
	d.held_forward_stand = d.target_position.distance_to(line_stand) < 0.5
	return d


# The situational pinch: step down my wall onto an opposing carrier bottled
# between the line and the half-wall, as a pressurer — or null to hold the line.
# Gated on WINNING it (not already on his way out; I reach him before he skates
# it to the line) and COVERING it (_pinch_is_covered). A pinch already under way
# skips the race and cover checks so it finishes rather than flickers, but still
# bails once the breakout forms.
static func _wall_pinch(ctx: RoleContext, side: float,
		line_stand: Vector3) -> RoleDecision:
	if ctx.snapshot == null or ctx.snapshot.puck_state == null:
		return null
	var carrier_pid: int = ctx.snapshot.puck_state.carrier_peer_id
	if carrier_pid == -1 or ctx.team_id_by_peer.get(carrier_pid, -1) == ctx.team_id:
		return null
	var cs: SkaterNetworkState = ctx.snapshot.skater_states.get(carrier_pid)
	if cs == null:
		return null
	if signf(cs.position.x) != side \
			or absf(cs.position.x) < GameRules.END_ZONE_FACEOFF_DOT_X:
		return null
	var depth: float = _depth_inside_attacked_zone(ctx, cs.position)
	if depth < 0.0 or depth > PINCH_MAX_DEPTH_M:
		return null
	if not AILastManDiscipline.may_hold_forward_stand(
			ctx, ctx.prev_held_forward_stand, line_stand):
		return null
	var pinching: bool = ctx.prev_role_target.is_finite() \
			and _depth_inside_attacked_zone(ctx, ctx.prev_role_target) \
					> DP_LINE_INSET_M + POINT_VACATED_SLACK_M
	if not pinching:
		var t_me: float = AIArrival.time_to_arrive(
				ctx.self_pos, cs.position, ctx.self_velocity,
				ctx.self_max_speed, ctx.self_max_accel, ctx.self_lateral_grip)
		var out_speed: float = cs.velocity.z * ctx.own_goal_dir
		if out_speed > 0.0 and t_me >= depth / out_speed:
			return null
		if not _pinch_is_covered(ctx, line_stand, t_me):
			return null
	var d: RoleDecision = AIRolePressure.decide(ctx, true)
	d.pressures_puck = true
	# Still the forward posture, so the numbers read keeps its holding hysteresis.
	d.held_forward_stand = true
	return d


# The cover half of the pinch: nobody of theirs behind my stand, my partner on
# the line, and F2_WEAK able to take my point inside `t_engage` + the late-man
# window.
static func _pinch_is_covered(ctx: RoleContext, line_stand: Vector3,
		t_engage: float) -> bool:
	var our_net: Vector3 = ctx.defending_goal_pos
	var stand_d: float = AIRoleReads.xz_distance(line_stand, our_net)
	for lead: Vector3 in ctx.rush_read.attacker_leads:
		if AIRoleReads.xz_distance(lead, our_net) \
				< stand_d - AIRushRead.cover_envelope_m():
			return false
	var partner: SkaterNetworkState = _slot_holder(ctx, AIRoleSlots.Slot.DP_WEAK)
	if partner == null or _depth_inside_attacked_zone(ctx, partner.position) \
			> DP_LINE_INSET_M + POINT_VACATED_SLACK_M:
		return false
	var filler_pid: int = _slot_holder_pid(ctx, AIRoleSlots.Slot.F2_WEAK)
	if filler_pid == -1:
		return false
	var filler: SkaterNetworkState = ctx.snapshot.skater_states[filler_pid]
	return AIArrival.time_to_arrive_caps(filler.position, line_stand, filler.velocity,
			ctx.caps_by_peer.get(filler_pid)) <= t_engage + AIRushRead.LATE_MAN_WINDOW_S


# ── The rotation ─────────────────────────────────────────────────────────────

# The forward's half of the rotation: the strong point's stand, held as a back
# layer, while the D who owns it is down the wall — or null when he is not.
static func rotate_up_to_point(ctx: RoleContext, strong_slot: int) -> RoleDecision:
	var stand: Vector3 = strong_point_stand(ctx, strong_slot)
	var covering: bool = ctx.prev_role_target.is_finite() \
			and AIRoleReads.xz_distance(ctx.prev_role_target, stand) < ROTATION_HELD_M
	if not strong_point_vacated(ctx, strong_slot, covering):
		return null
	var d := RoleDecision.new()
	d.target_position = AILastManDiscipline.offensive_station_target(
			ctx, stand, ctx.prev_held_forward_stand, true)
	d.held_forward_stand = d.target_position.distance_to(stand) < 0.5
	return d


static func strong_point_stand(ctx: RoleContext, strong_slot: int) -> Vector3:
	var own_dir: float = ctx.own_goal_dir
	if strong_slot == AIRoleSlots.Slot.DP_STRONG:
		return Vector3(ctx.strong_x * DP_STRONG_LANE_X_M, 0.0,
				-own_dir * (GameRules.BLUE_LINE_Z + DP_LINE_INSET_M))
	return Vector3(ctx.strong_x * GameRules.END_ZONE_FACEOFF_DOT_X, 0.0,
			-own_dir * (GameRules.BLUE_LINE_Z + POINT_INSET_M))


# Has the teammate holding `strong_slot` gone deeper into the zone we attack than
# any stand that slot takes, by POINT_VACATED_SLACK_M? `covering` drops the
# slack, so a rotation already made holds until he is back. False when nobody
# holds the slot or no brain is wired.
static func strong_point_vacated(ctx: RoleContext, strong_slot: int,
		covering: bool) -> bool:
	var holder: SkaterNetworkState = _slot_holder(ctx, strong_slot)
	if holder == null:
		return false
	var deepest: float = DP_LINE_INSET_M if strong_slot == AIRoleSlots.Slot.DP_STRONG \
			else POINT_INSET_M + POINT_SINK_M * float(POINT_SINK_ROWS)
	if not covering:
		deepest += POINT_VACATED_SLACK_M
	return _depth_inside_attacked_zone(ctx, holder.position) > deepest


# The weak D's read: his "already covering" is standing in the middle lanes.
static func _partner_vacated(ctx: RoleContext, strong_slot: int) -> bool:
	var covering: bool = ctx.prev_role_target.is_finite() \
			and absf(ctx.prev_role_target.x) < POINT_WEAK_COVER_LANES_U[0] + 0.5
	return strong_point_vacated(ctx, strong_slot, covering)


# The teammate (not me) the brain has in `slot`, or null.
static func _slot_holder(ctx: RoleContext, slot: int) -> SkaterNetworkState:
	var pid: int = _slot_holder_pid(ctx, slot)
	return ctx.snapshot.skater_states[pid] if pid != -1 else null


static func _slot_holder_pid(ctx: RoleContext, slot: int) -> int:
	if ctx.team_brain == null or ctx.snapshot == null:
		return -1
	for pid: int in ctx.snapshot.skater_states:
		if pid == ctx.peer_id or ctx.team_id_by_peer.get(pid, -1) != ctx.team_id:
			continue
		if ctx.team_brain.get_slot(pid) == slot:
			return pid
	return -1


# Metres inside the zone we attack, past its blue line (negative = outside it).
static func _depth_inside_attacked_zone(ctx: RoleContext, pos: Vector3) -> float:
	return -ctx.own_goal_dir * pos.z - GameRules.BLUE_LINE_Z


# ── TRANS_OFFENSE: the safety valve ───────────────────────────────────────────────
static func _decide_valve(ctx: RoleContext) -> RoleDecision:
	var d := RoleDecision.new()
	var own_dir: float = ctx.own_goal_dir
	var play_ref: Vector3 = AIRoleReads.resolve_offensive_play_ref(ctx)
	if not play_ref.is_finite():
		d.target_position = ctx.self_pos
		return d
	# Trail the play centrally, DVALVE_TRAIL_M behind, never past our goal line.
	var cap: float = GameRules.GOAL_LINE_Z - DVALVE_GOAL_LINE_PAD_M
	var trail_z: float = clampf(play_ref.z + own_dir * DVALVE_TRAIL_M, -cap, cap)
	var target := Vector3(0.0, 0.0, trail_z)
	# The valve's whole job is never to be beaten home.
	var valve_stand: Vector3 = target
	target = AILastManDiscipline.offensive_station_target(
			ctx, valve_stand, ctx.prev_held_forward_stand)
	d.held_forward_stand = target.distance_to(valve_stand) < 0.5
	d.target_position = target
	# The rush advances every tick — pace the waypoint, don't brake at it.
	d.arrive_at_speed = true
	return d


# ── NEUTRAL: the goal-side back pair ─────────────────────────────────────────
static func _decide_back(ctx: RoleContext, side: float) -> RoleDecision:
	var d := RoleDecision.new()
	var own_dir: float = ctx.own_goal_dir
	var x: float = side * DBACK_X_M
	if ctx.snapshot != null and ctx.snapshot.puck_state != null:
		# The back wall slides with the puck; it doesn't chase.
		x += clampf(ctx.snapshot.puck_state.position.x * DBACK_PUCK_SHADE,
				-DBACK_SHADE_MAX_M, DBACK_SHADE_MAX_M)
	var stand := Vector3(x, 0.0, own_dir * GameRules.BLUE_LINE_Z)
	d.target_position = AILastManDiscipline.neutral_station_target(
			ctx, stand, ctx.prev_held_forward_stand)
	d.held_forward_stand = d.target_position.distance_to(stand) < 0.5
	return d
