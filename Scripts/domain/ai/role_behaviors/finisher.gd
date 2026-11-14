class_name AIRoleFinisher

# FINISHER (3v3 OZONE; 5v5 OZONE's third low forward) and NET_FRONT (5v5 OZONE).
# Stateless, and two-mode: REACTIVE deflects an incoming shot and overrides
# everything while it is active; POSITIONING stages for the next one. No
# exposure factor: crashing the net is the role, and defensive recovery is
# SUPPORT's job.

# Speed gate: pucks slower than this are passes / rolling, not shots. The tip
# pricing reads the same gate.
const INCOMING_SHOT_SPEED_M_S: float = AIActionScoring.TIP_MIN_SPEED_M_S

# The most a deliberate tip turns the puck (Puck.deflect_max_turn_deg, held by
# test_bot_mirrors.gd), with the blade square beside the body.
const TIP_MAX_TURN_RAD: float = deg_to_rad(25.0)
# How far out from the body the tipper's blade sits: the ring the agent's FACE
# cursor snaps to (AIBotMechanics.CARRY_BLADE_AIM_FORWARD_M), so standing this
# far back of the tip point along the blade's bearing puts the blade on it.
const TIP_BLADE_OUT_M: float = AIBotMechanics.CARRY_BLADE_AIM_FORWARD_M

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
	var crash: RoleDecision = _try_crash(ctx)
	if crash != null:
		return crash
	return _positioning_decision(ctx)


# ── The crash (our shot on its way) ──────────────────────────────────────────
# How far a crash point inside the crease is walked out along its bearing from
# the goal per step, to the first legal ice.
const CRASH_STEP_OUT_M: float = 0.25


# With our shot on its way to their net (a teammate's release, untouched since,
# at a shot's pace and heading at it), go to where its rebound is worth playing:
# the measured crash point for the release (AIReboundField.crash_point) — the
# contest point, where it first sits playable, for NET_FRONT, and the late one,
# half a second on in the slot, for the FINISHER. Arrived at speed. Null when no
# shot of ours is on its way, or the release's spot leaves no rebound to play.
static func _try_crash(ctx: RoleContext) -> RoleDecision:
	var puck: PuckNetworkState = ctx.snapshot.puck_state
	if puck == null or puck.carrier_peer_id != -1:
		return null
	var releaser: int = ctx.snapshot.loose_puck_released_by
	if releaser == -1 or ctx.team_id_by_peer.get(releaser, -1) != ctx.team_id \
			or not ctx.snapshot.skater_states.has(releaser):
		return null
	var vel := Vector2(puck.velocity.x, puck.velocity.z)
	var goal: Vector3 = ctx.attacking_goal_pos
	if vel.length() < INCOMING_SHOT_SPEED_M_S \
			or vel.dot(Vector2(goal.x - puck.position.x, goal.z - puck.position.z)) <= 0.0:
		return null
	var late: bool = ctx.team_brain == null \
			or ctx.team_brain.get_slot(ctx.peer_id) != AIRoleSlots.Slot.NET_FRONT
	var at: Vector3 = AIReboundField.crash_point(AIReboundField.spot_of(
			ctx.snapshot.skater_states[releaser].position, goal), late, goal)
	if not at.is_finite():
		return null
	var out := Vector3(at.x - goal.x, 0.0, at.z - goal.z).normalized()
	if out == Vector3.ZERO:
		out = Vector3(0.0, 0.0, ctx.own_goal_dir)
	while not AIStationSearch.is_legal_position(at) \
			and Vector2(at.x - goal.x, at.z - goal.z).length() < GameRules.SLOT_DIST_M:
		at += out * CRASH_STEP_OUT_M
	var d := RoleDecision.new()
	d.target_position = at
	d.arrive_at_speed = true
	return d


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
	if absf(puck_vel.z) < 0.001:
		return null

	# The tip point: where the puck's path crosses our z plane, short of the
	# goal line.
	var t_to_my_z: float = (ctx.self_pos.z - puck_pos.z) / puck_vel.z
	if t_to_my_z <= 0.0 or t_to_my_z > 2.0:
		return null
	if (opp_goal_z - ctx.self_pos.z) * puck_vel.z <= 0.0:
		return null
	var tip := Vector2(puck_pos.x + puck_vel.x * t_to_my_z, ctx.self_pos.z)
	var travel: Vector2 = Vector2(puck_vel.x, puck_vel.z) / puck_speed

	# A tip turns the puck at most TIP_MAX_TURN_RAD, so a shot is tipped when
	# that reaches the mouth from the tip point: on net already, or wide by no
	# more than that. A shot wider than a tip can bring back, or a teammate's
	# pass running at the net, is left alone.
	var mouth: float = GameRules.NET_ENTRY_HALF_WIDTH
	var x_at_goal: float = puck_pos.x + puck_vel.x * (to_goal_z / puck_vel.z)
	if absf(x_at_goal) > mouth and absf(travel.angle_to(
			Vector2(signf(x_at_goal) * mouth, opp_goal_z) - tip)) > TIP_MAX_TURN_RAD:
		return null

	# TIP: the turn toward the middle of the net, as far as a tip turns, asked
	# for by the side the blade is held on: PuckCollisionRules.tip_turn turns it
	# by TIP_MAX_TURN_RAD × the cross of the puck's travel with the body→blade
	# bearing. The blade goes on the path at the tip point, toward the puck, and
	# the body stands TIP_BLADE_OUT_M back of it along that bearing.
	var turn: float = clampf(travel.angle_to(Vector2(0.0, opp_goal_z) - tip),
			-TIP_MAX_TURN_RAD, TIP_MAX_TURN_RAD)
	var bearing: Vector2 = (-travel).rotated(-asin(turn / TIP_MAX_TURN_RAD))
	var body: Vector2 = tip - bearing * TIP_BLADE_OUT_M
	# A tip his blade cannot be on before the puck crosses his line, stick out
	# (AILoosePuckChase.reach_eta), is no tip: the crash is his play instead.
	if AILoosePuckChase.reach_eta(ctx.self_pos, Vector3(tip.x, 0.0, tip.y), ctx.self_velocity,
			ctx.self_max_speed, ctx.self_max_accel, ctx.self_blade_reach) > t_to_my_z:
		return null
	var d := RoleDecision.new()
	d.target_position = Vector3(body.x, 0.0, body.y)
	d.aim_world_pos = Vector3(tip.x, 0.0, tip.y)
	d.has_aim_override = true
	# Hold the deflect, so the blade redirects the shot rather than catching it,
	# from when the press can read the puck: it reads it once, and takes the
	# blade to its height (DeflectReachRules.lift_to_meet). The tip changes the
	# plane the keeper read: a shot on the ice goes up, a raised one down.
	if t_to_my_z <= DeflectReachRules.TRACK_HORIZON_S:
		d.deflect = true
		d.deflect_up = not _last_shooter_is_elevated(ctx)
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
	# TIP STATION — on the carrier→net line at TIP_STATION_DIST_M, so it
	# tracks the carrier. Its value comes from the tip and the screen: as a pass target
	# a body in the goalie's chest is rightly worthless.
	var to_carrier: Vector3 = carrier_pos - ctx.attacking_goal_pos
	to_carrier.y = 0.0
	var to_carrier_len: float = to_carrier.length()
	if to_carrier_len > TIP_STATION_DIST_M + 0.5:
		candidates.append(ctx.attacking_goal_pos
				+ to_carrier * (TIP_STATION_DIST_M / to_carrier_len))
	# NET-FRONT STATIONS — in front of each shot of ours, screening it or on
	# its rebound.
	AIStationSearch.fill_shot_plays(ctx, carrier_pos, goalie_pos, opp_positions,
			teammate_positions)
	AIStationSearch.append_net_front_stations(ctx, candidates)
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
	var best_battles: bool = false
	AIStationSearch.fill_feed_values(ctx, carrier_pos, goalie_pos, opp_positions,
			teammate_positions)

	var best_pos: Vector3 = ctx.self_pos
	var best_score: float = -INF
	# RUSH DEPTH GATE — a coaching decision, deliberately not a perception: on a
	# rush the second attacker drives the net. On the shot alone these stations
	# are indistinguishable (each hinges on whether the goalie has re-squared),
	# and nothing in the scoring prices the net's rebounds yet, so the gate
	# states it directly. The cap is stage_dist itself — the staging
	# decision just made.
	var depth_cap: float = stage_dist
	for c: Vector3 in candidates:
		if not AIStationSearch.is_legal_position(c):
			continue
		if AIStationSearch.too_close_to_teammate(c, teammate_positions):
			continue
		if absf(c.z - goal_z) > depth_cap:
			continue
		# The speed our carrier would actually fire at, not a flat constant —
		# the defenders' reaction time scales with it.
		var pass_speed: float = AIPuckLane.expected_pass_speed(carrier_pos, c)
		# The FINISHER fires on contact: his one-timer off the feed.
		var feed: float = AIActionScoring.score_pass_value(
				carrier_pos, c, ctx.attacking_goal_pos, goalie_pos, opp_positions,
				pass_speed, ctx.scratch_opp_caps, true)
		var tip: float = AIActionScoring.tip_ev(
				carrier_release, c, ctx.attacking_goal_pos, goalie_pos,
				opp_positions,
				carrier_shot_speed, ctx.scratch_opp_caps, self_caps)
		# What a body here adds to our shots in front of their net: the screen,
		# and the rebound.
		var front: float = AIStationSearch.net_front_value(ctx, c)
		# The best of the one-timer feed, the tip and the net front — max(), not
		# sum: one puck, one outcome — less what a teammate a defender could
		# cover with this spot already offers.
		var score: float = maxf(maxf(feed, tip), front) \
				- AIStationSearch.shared_cover(c, teammate_positions) \
				+ AIStationSearch.incumbent_bonus(ctx, c)
		if score > best_score:
			best_score = score
			best_pos = c
			best_battles = front > 0.0

	d.target_position = best_pos
	# A station worth something in front of one of our shots is ice worth
	# fighting for, whatever else it is worth: the press wins it
	# (SkaterAgentPress).
	if best_battles:
		d.battle_spot = best_pos
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
