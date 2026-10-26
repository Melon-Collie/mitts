class_name AIRoleFinisher

# FINISHER (3v3 OZONE) and NET_FRONT (5v5 OZONE). Stateless, and two-mode:
# REACTIVE deflects an incoming shot and overrides everything while it is
# active; POSITIONING stages for the next one. No exposure factor: crashing the
# net is the role, and defensive recovery is SUPPORT's job.

# Speed gate: pucks slower than this are passes / rolling, not shots.
const INCOMING_SHOT_SPEED_M_S: float = 12.0

# Weak-side staging bias for the SET CYCLE, where the cross-seam feed is the
# highest-value look. Feel tunable; 0 = centered.
const WEAK_SIDE_BIAS_M: float = 4.0

# Weak-side bias at FULL rush: still opposite the carrier, but tight enough to
# drive a lane it can finish from. Blended toward WEAK_SIDE_BIAS_M as the rush
# cools.
const RUSH_WEAK_SIDE_BIAS_M: float = 2.0

# Staging depth off the opp goal at FULL rush (metres), pulled in from
# SLOT_DIST_M so the FINISHER crashes the net. is_legal_position keeps it off
# the crease and goal line.
const RUSH_NET_DRIVE_DIST_M: float = 2.5

# Carrier up-ice speed band (m/s) mapped to the rush blend: at/below LO a set
# cycle, at/above HI a full rush, lerped between.
const RUSH_SPEED_LO_M_S: float = 2.5
const RUSH_SPEED_HI_M_S: float = 6.5

# Cap on the feed flight time the goalie-motion prediction uses, so a far
# cross-ice candidate doesn't model an unrealistically settled goalie. The pass
# lead's own horizon (test_bot_mirrors.gd).
const FEED_FLIGHT_MAX_S: float = 1.0

# TIP/SCREEN STATION depth off the goal mouth along the carrier→net line: just
# outside the crease arc (GameRules.CREASE_ARC_RADIUS) plus a body, where the
# body screens and the blade reaches the point blast.
const TIP_STATION_DIST_M: float = 2.5


static func decide(ctx: RoleContext) -> RoleDecision:
	var reactive: RoleDecision = _try_reactive_decision(ctx)
	if reactive != null:
		return reactive
	return _positioning_decision(ctx)


# ── Reactive (incoming shot) ─────────────────────────────────────────────────

# A TIP decision when an incoming shot is detected, else null (positioning
# takes over).
static func _try_reactive_decision(ctx: RoleContext) -> RoleDecision:
	var puck_state: PuckNetworkState = ctx.snapshot.puck_state
	if puck_state == null:
		return null

	# Held pucks are not shots. Right after a release the puck still reads as
	# held for the carrier-reaction delay, so the tip starts a beat late — which
	# is what that difficulty knob means.
	if puck_state.carrier_peer_id != -1:
		return null

	var puck_pos: Vector3 = puck_state.position
	var puck_vel: Vector3 = puck_state.velocity
	var puck_speed: float = sqrt(puck_vel.x * puck_vel.x + puck_vel.z * puck_vel.z)

	if puck_speed < INCOMING_SHOT_SPEED_M_S:
		return null

	var opp_goal_z: float = -ctx.own_goal_dir * GameRules.GOAL_LINE_Z
	var to_goal_z: float = opp_goal_z - puck_pos.z
	if puck_vel.z * to_goal_z <= 0.0:
		return null

	# Where the puck path crosses our z plane.
	if absf(puck_vel.z) < 0.001:
		return null
	var t_to_my_z: float = (ctx.self_pos.z - puck_pos.z) / puck_vel.z
	if t_to_my_z <= 0.0 or t_to_my_z > 2.0:
		return null
	var path_x_at_my_z: float = puck_pos.x + puck_vel.x * t_to_my_z

	# TIP: step onto the puck path at our current z and aim at the goal, so the
	# blade angles the redirect on- and off-target shots alike.
	var d := RoleDecision.new()
	d.target_position = Vector3(path_x_at_my_z, 0.0, ctx.self_pos.z)
	d.aim_world_pos = Vector3(0.0, 0.0, opp_goal_z)
	d.has_aim_override = true
	# A grounded blade flies under an elevated puck, so an airborne incoming shot
	# has to be met with the blade raised.
	if _last_shooter_is_elevated(ctx):
		d.lift_blade = true
	return d


# True when the likely shooter — our skater nearest the puck — has any loft
# selected (elevation_level > 0), read off his replicated state.
static func _last_shooter_is_elevated(ctx: RoleContext) -> bool:
	if ctx.snapshot.puck_state == null:
		return false
	var puck_pos: Vector3 = ctx.snapshot.puck_state.position
	var best_pid: int = 0
	var best_d2: float = INF
	for pid: int in ctx.snapshot.skater_states:
		if ctx.team_id_by_peer.get(pid, -1) != ctx.team_id:
			continue
		var pos: Vector3 = ctx.snapshot.skater_states[pid].position
		var dx: float = pos.x - puck_pos.x
		var dz: float = pos.z - puck_pos.z
		var d2: float = dx * dx + dz * dz
		if d2 < best_d2:
			best_d2 = d2
			best_pid = pid
	if best_pid == 0:
		return false
	return ctx.snapshot.skater_states[best_pid].elevation_level > 0


# ── Positioning (no incoming shot) ──────────────────────────────────────────

# Argmax over the named staging stations, each scored as the better of its two
# payoffs — the one-timer feed or the tip of the carrier's direct rip. Holds
# when no teammate carries.
static func _positioning_decision(ctx: RoleContext) -> RoleDecision:
	var d := RoleDecision.new()

	var carrier_pos: Vector3 = AIRoleReads.resolve_teammate_carrier_pos(ctx)
	if not carrier_pos.is_finite():
		d.target_position = ctx.self_pos
		return d

	var goalie_pos: Vector3 = AIRoleReads.resolve_opp_goalie_pos(ctx)

	var opp_positions: Array[Vector3] = ctx.scratch_opp_positions
	var opp_states: Array[SkaterNetworkState] = ctx.scratch_opp_states
	AIRoleReads.collect_opponents(ctx, opp_positions, opp_states)

	var teammate_positions: Array[Vector3] = ctx.scratch_teammates
	AIRoleReads.collect_teammates_excluding_self(ctx, teammate_positions)

	# 0 = set cycle (cross-seam staging), 1 = full rush (net-crash).
	var rush: float = _rush_factor(ctx)
	var weak_bias: float = lerpf(WEAK_SIDE_BIAS_M, RUSH_WEAK_SIDE_BIAS_M, rush)
	var stage_dist: float = lerpf(GameRules.SLOT_DIST_M, RUSH_NET_DRIVE_DIST_M, rush)

	# stage_dist off the opp goal, shifted to the weak side for the cross-seam
	# one-timer.
	var search_center := Vector3(
			-ctx.strong_x * weak_bias,
			0.0,
			ctx.attacking_goal_pos.z + ctx.own_goal_dir * stage_dist)
	# Far from the station, skate at the calculated center (STATION_ARGMAX_LOD_M).
	if not AIStationSearch.station_needs_refinement(ctx.self_pos, search_center):
		d.target_position = search_center
		return d
	# Named stations rather than a polar ring: one ring cannot span the backdoor
	# and the high slot in the same read.
	var weak: float = -ctx.strong_x
	var goal_z: float = ctx.attacking_goal_pos.z
	var own_dir: float = ctx.own_goal_dir
	var candidates: Array[Vector3] = [
		search_center,
		ctx.self_pos,
		# BACKDOOR — a body-width outside the far post, just clear of the crease
		# arc and the goal-line buffer.
		Vector3(weak * (GameRules.NET_HALF_WIDTH + 1.4), 0.0,
				goal_z + own_dir * 1.5),
		# BUMPER — the mid-slot one-timer.
		Vector3(weak * 0.8, 0.0, goal_z + own_dir * GameRules.SLOT_DIST_M),
		# WEAK DOT — the end-zone faceoff dot.
		Vector3(weak * GameRules.END_ZONE_FACEOFF_DOT_X, 0.0,
				goal_z + own_dir
						* (GameRules.GOAL_LINE_Z - GameRules.ICING_FACEOFF_DOT_Z)),
		# HIGH SLOT — the trailing seam.
		Vector3(weak * 1.5, 0.0, goal_z + own_dir * 9.5),
	]
	# TIP/SCREEN STATION — on the carrier→net line at TIP_STATION_DIST_M, so it
	# tracks the carrier. Its value comes only from the tip term: as a pass target
	# a body in the goalie's chest is rightly worthless.
	var to_carrier: Vector3 = carrier_pos - ctx.attacking_goal_pos
	to_carrier.y = 0.0
	var to_carrier_len: float = to_carrier.length()
	if to_carrier_len > TIP_STATION_DIST_M + 0.5:
		candidates.append(ctx.attacking_goal_pos
				+ to_carrier * (TIP_STATION_DIST_M / to_carrier_len))
	# Switch-hysteresis (the pre-aim cursor snaps to this target).
	AIStationSearch.append_incumbent(ctx, candidates)

	# The carrier's rip, for the tip term: his real wrister pace, released a
	# handle-length toward the net.
	var carrier_caps: AISkaterCaps = null
	var carrier_pid: int = ctx.snapshot.puck_state.carrier_peer_id \
			if ctx.snapshot != null and ctx.snapshot.puck_state != null else -1
	if carrier_pid != -1:
		carrier_caps = ctx.caps_by_peer.get(carrier_pid)
	var carrier_shot_speed: float = carrier_caps.wrister_shot_speed \
			if carrier_caps != null else AIBotMechanics.WRISTER_SHOT_SPEED_M_S
	var carrier_release: Vector3 = AIPuckLane.release_point_toward(
			carrier_pos, ctx.attacking_goal_pos)
	var self_caps: AISkaterCaps = ctx.caps_by_peer.get(ctx.peer_id)
	AIRoleReads.collect_feed_defence(ctx)
	var origin: Vector3 = AIRoleReads.feed_origin(ctx, carrier_pos)

	var best_pos: Vector3 = ctx.self_pos
	var best_score: float = -INF
	# RUSH DEPTH GATE — a coaching decision, deliberately not a perception: on a
	# rush the second attacker drives the net. On the shot alone these stations
	# are indistinguishable (each hinges on whether the goalie has re-squared),
	# and nothing in the scoring prices the net's rebounds and body presence, so
	# the gate states it directly. The cap is stage_dist itself — the staging
	# decision just made.
	var depth_cap: float = stage_dist
	for c: Vector3 in candidates:
		if not AIStationSearch.is_legal_position(c):
			continue
		if AIStationSearch.too_close_to_teammate(c, teammate_positions):
			continue
		if absf(c.z - goal_z) > depth_cap:
			continue
		var pass_speed: float = AIRoleReads.feed_speed(ctx, origin, c)
		# The FINISHER fires on contact: his one-timer off the feed. Its worth is
		# linear in the lane, read only where an open one could win (exact).
		var feed: float = AIActionScoring.score_pass_value(
				origin, c, ctx.attacking_goal_pos, goalie_pos, opp_positions,
				pass_speed, ctx.scratch_opp_caps, true, 1.0)
		var tip: float = AIActionScoring.tip_ev(
				carrier_release, c, ctx.attacking_goal_pos, goalie_pos,
				opp_positions,
				carrier_shot_speed, ctx.scratch_opp_caps, self_caps)
		var bonus: float = AIStationSearch.incumbent_bonus(ctx, c)
		if feed > tip and feed + bonus > best_score:
			feed *= AIRoleReads.feed_lane(ctx, origin, c, pass_speed)
		# The better of the one-timer feed and the tip — max(), not sum: one puck,
		# one outcome.
		var score: float = maxf(feed, tip) + bonus
		if score > best_score:
			best_score = score
			best_pos = c

	d.target_position = best_pos
	# No separate quality gate: a weak spot scores low for the carrier too. Half
	# a search step — nearer the chosen station than any neighbour.
	if ctx.self_pos.distance_to(best_pos) < AIStationSearch.SEARCH_STEP_M * 0.5:
		d.is_one_timer_ready = true
	return d


# Rush blend in [0, 1] from our carrier's up-ice speed (lateral cycling is not a
# rush). 0 when no teammate carries.
static func _rush_factor(ctx: RoleContext) -> float:
	if ctx.snapshot == null or ctx.snapshot.puck_state == null:
		return 0.0
	var carrier_pid: int = ctx.snapshot.puck_state.carrier_peer_id
	if carrier_pid == -1 or not ctx.snapshot.skater_states.has(carrier_pid):
		return 0.0
	if ctx.team_id_by_peer.get(carrier_pid, -1) != ctx.team_id:
		return 0.0
	var carrier_vel: Vector3 = ctx.snapshot.skater_states[carrier_pid].velocity
	var closing_speed: float = maxf(-ctx.own_goal_dir * carrier_vel.z, 0.0)
	return clampf(
			(closing_speed - RUSH_SPEED_LO_M_S)
					/ (RUSH_SPEED_HI_M_S - RUSH_SPEED_LO_M_S),
			0.0, 1.0)
