class_name AIRoleReads

# What a role reads off its RoleContext: the goalies and carriers it resolves,
# the play reference it anchors to and the velocity a stand rides, where a
# threat will be (lead_threat), and the collected teammates and opponents it
# scores against.


# How far ahead (seconds) defensive reads lead an opponent when scoring threats,
# so they price where the attack is GOING rather than the freeze-frame.
const DEFENSIVE_ANTICIPATION_S: float = 0.3


# Clamp on the lead, so a fast skater or a velocity spike on a curling route
# can't drag the read onto a phantom.
const DEFENSIVE_ANTICIPATION_MAX_M: float = 2.5


# XZ only; y is 0. `scale` is ctx.defensive_anticipation_scale: 1.0 = full lead,
# lower leads less.
static func lead_threat(pos: Vector3, vel: Vector3, scale: float = 1.0) -> Vector3:
	var anticipation_s: float = DEFENSIVE_ANTICIPATION_S * scale
	var lead_x: float = vel.x * anticipation_s
	var lead_z: float = vel.z * anticipation_s
	var l: float = sqrt(lead_x * lead_x + lead_z * lead_z)
	if l > DEFENSIVE_ANTICIPATION_MAX_M:
		var s: float = DEFENSIVE_ANTICIPATION_MAX_M / l
		lead_x *= s
		lead_z *= s
	return Vector3(pos.x + lead_x, 0.0, pos.z + lead_z)


# The puck-carrying teammate's position, or Vector3.INF when no teammate carries.
static func resolve_teammate_carrier_pos(ctx: RoleContext) -> Vector3:
	if ctx.snapshot == null or ctx.snapshot.puck_state == null:
		return Vector3.INF
	var carrier_pid: int = ctx.snapshot.puck_state.carrier_peer_id
	if carrier_pid == -1:
		return Vector3.INF
	if ctx.team_id_by_peer.get(carrier_pid, -1) != ctx.team_id:
		return Vector3.INF
	if not ctx.snapshot.skater_states.has(carrier_pid):
		return Vector3.INF
	return ctx.snapshot.skater_states[carrier_pid].position


# Our carrier's up-ice speed (m/s, the Z component toward the attacking goal,
# floored at 0) — the "is this a rush?" read. Lateral motion deliberately does
# not count. 0 when no teammate carries.
static func carrier_closing_speed(ctx: RoleContext) -> float:
	if ctx.snapshot == null or ctx.snapshot.puck_state == null:
		return 0.0
	var carrier_pid: int = ctx.snapshot.puck_state.carrier_peer_id
	if carrier_pid == -1 or not ctx.snapshot.skater_states.has(carrier_pid):
		return 0.0
	if ctx.team_id_by_peer.get(carrier_pid, -1) != ctx.team_id:
		return 0.0
	var vel: Vector3 = ctx.snapshot.skater_states[carrier_pid].velocity
	return maxf(-ctx.own_goal_dir * vel.z, 0.0)


# The opposing goalie's current position (the attacking goal mouth before any
# state is buffered). Callers pass it unprojected as score_pass's
# predicted_goalie_pos: differences across candidates dominate the error.
static func resolve_opp_goalie_pos(ctx: RoleContext) -> Vector3:
	var opp_team_id: int = 1 - ctx.team_id
	var goalie: GoalieNetworkState = ctx.snapshot.goalie_states.get(opp_team_id)
	if goalie == null:
		return ctx.attacking_goal_pos
	return Vector3(goalie.position_x, 0.0, goalie.position_z)


# OUR goalie's current position (our goal mouth before any state is buffered).
static func resolve_our_goalie_pos(ctx: RoleContext) -> Vector3:
	var goalie: GoalieNetworkState = ctx.snapshot.goalie_states.get(ctx.team_id)
	if goalie == null:
		return ctx.defending_goal_pos
	return Vector3(goalie.position_x, 0.0, goalie.position_z)


# Whoever carries the puck, either team, or Vector3.INF when it is loose / null.
static func resolve_any_carrier_pos(ctx: RoleContext) -> Vector3:
	if ctx.snapshot == null or ctx.snapshot.puck_state == null:
		return Vector3.INF
	var carrier_pid: int = ctx.snapshot.puck_state.carrier_peer_id
	if carrier_pid == -1:
		return Vector3.INF
	if not ctx.snapshot.skater_states.has(carrier_pid):
		return Vector3.INF
	return ctx.snapshot.skater_states[carrier_pid].position


# ── Play reference (anti-freeze) ─────────────────────────────────────────────
# There is no live carrier for most of every transition (a loose puck, a pass in
# flight), so these fall back to the PUCK and the role keeps flowing toward the
# play. INF only when there is no puck state at all.

# Offensive roles: a teammate carrier, else a LOOSE puck. An opposing carrier is
# deliberately not a fallback — the brain re-slots us to a defensive role on that
# change, so the caller holds for the transient.
static func resolve_offensive_play_ref(ctx: RoleContext) -> Vector3:
	var carrier: Vector3 = resolve_teammate_carrier_pos(ctx)
	if carrier.is_finite():
		return carrier
	if ctx.snapshot != null and ctx.snapshot.puck_state != null \
			and ctx.snapshot.puck_state.carrier_peer_id == -1:
		return ctx.snapshot.puck_state.position
	return Vector3.INF


# Defensive roles: whoever carries the puck, else the puck.
static func resolve_defensive_play_ref(ctx: RoleContext) -> Vector3:
	var carrier: Vector3 = resolve_any_carrier_pos(ctx)
	if carrier.is_finite():
		return carrier
	if ctx.snapshot != null and ctx.snapshot.puck_state != null:
		return ctx.snapshot.puck_state.position
	return Vector3.INF


# The play reference's velocity: the carrier's when one holds the puck, else
# the puck's own.
static func resolve_play_ref_velocity(ctx: RoleContext) -> Vector3:
	if ctx.snapshot == null or ctx.snapshot.puck_state == null:
		return Vector3.ZERO
	var carrier_pid: int = ctx.snapshot.puck_state.carrier_peer_id
	if carrier_pid != -1 and ctx.snapshot.skater_states.has(carrier_pid):
		return ctx.snapshot.skater_states[carrier_pid].velocity
	return ctx.snapshot.puck_state.velocity


# The velocity a defensive stand built off the play reference rides at — a role's
# RoleDecision.target_velocity. ZERO for anything but a live OPPOSING carrier:
# a loose puck is decelerating and unowned, not a frame to hold station in, so
# the stand degrades to a point seek.
static func stand_ride_velocity(ctx: RoleContext) -> Vector3:
	if ctx.snapshot == null or ctx.snapshot.puck_state == null:
		return Vector3.ZERO
	var pid: int = ctx.snapshot.puck_state.carrier_peer_id
	if pid == -1 or pid == ctx.peer_id:
		return Vector3.ZERO
	if ctx.team_id_by_peer.get(pid, -1) == ctx.team_id:
		return Vector3.ZERO   # our own carrier — not a man anyone is defending
	if not ctx.snapshot.skater_states.has(pid):
		return Vector3.ZERO
	return ctx.snapshot.skater_states[pid].velocity


# Fills `out` with the opposing carrier's potential receivers (every opponent
# but the carrier), led by lead_threat when `anticipate`.
static func collect_opp_team_excluding_carrier(ctx: RoleContext,
		out: Array[Vector3], anticipate: bool = false) -> void:
	out.clear()
	var carrier_pid: int = -1
	if ctx.snapshot != null and ctx.snapshot.puck_state != null:
		carrier_pid = ctx.snapshot.puck_state.carrier_peer_id
	for pid: int in ctx.snapshot.skater_states:
		if ctx.team_id_by_peer.get(pid, -1) == ctx.team_id:
			continue  # our team
		if pid == carrier_pid:
			continue
		var s: SkaterNetworkState = ctx.snapshot.skater_states[pid]
		out.append(lead_threat(s.position, s.velocity, ctx.defensive_anticipation_scale) \
				if anticipate else s.position)


# Fills `out` with teammates' positions excluding self, and
# ctx.scratch_teammate_caps / scratch_teammate_vels index-matched.
static func collect_teammates_excluding_self(ctx: RoleContext,
		out: Array[Vector3]) -> void:
	out.clear()
	ctx.scratch_teammate_caps.clear()
	ctx.scratch_teammate_vels.clear()
	for pid: int in ctx.snapshot.skater_states:
		if pid == ctx.peer_id:
			continue
		if ctx.team_id_by_peer.get(pid, -1) == ctx.team_id:
			out.append(ctx.snapshot.skater_states[pid].position)
			ctx.scratch_teammate_caps.append(ctx.caps_by_peer.get(pid))
			ctx.scratch_teammate_vels.append(ctx.snapshot.skater_states[pid].velocity)


# The opposing attack's possession read (AIPossessionValue) against our skaters
# other than this bot — the defence's scale for what a man threatens. Reads the
# buffers collect_teammates_excluding_self filled into `teammates`, so call it
# after that; a candidate body is priced by push_defender / pop_defender.
static func defence_possession(ctx: RoleContext,
		teammates: Array[Vector3]) -> AIPossessionValue:
	var poss: AIPossessionValue = ctx.scratch_defence_possession
	var holder: Vector3 = AIDefencePairing.collect_attack(ctx.snapshot, ctx.team_id_by_peer,
			1 - ctx.team_id, ctx.scratch_defence_pairing, ctx.scratch_defence_pairing_vels)
	poss.fill(ctx.defending_goal_pos, teammates, ctx.scratch_teammate_vels,
			ctx.scratch_teammate_caps, false, ctx.scratch_defence_pairing,
			ctx.scratch_defence_pairing_vels, holder)
	return poss


# Fills parallel arrays of opponent positions (led by lead_threat when
# `anticipate`) and raw states, plus ctx.scratch_opp_caps / scratch_opp_ids.
static func collect_opponents(ctx: RoleContext,
		out_positions: Array[Vector3],
		out_states: Array[SkaterNetworkState],
		anticipate: bool = false) -> void:
	out_positions.clear()
	out_states.clear()
	ctx.scratch_opp_caps.clear()
	ctx.scratch_opp_ids.clear()
	ctx.scratch_opp_vels.clear()
	for pid: int in ctx.snapshot.skater_states:
		if ctx.team_id_by_peer.get(pid, -1) != ctx.team_id:
			var s: SkaterNetworkState = ctx.snapshot.skater_states[pid]
			out_positions.append(lead_threat(s.position, s.velocity, ctx.defensive_anticipation_scale) \
					if anticipate else s.position)
			out_states.append(s)
			ctx.scratch_opp_caps.append(ctx.caps_by_peer.get(pid))
			ctx.scratch_opp_ids.append(pid)
			ctx.scratch_opp_vels.append(s.velocity)


# ── The feed our carrier reads ───────────────────────────────────────────────
# A station a teammate feeds is priced on the lane the carrier's own pass search
# reads (AICarrierPassSearch over AICarrierField.fill): from his release point,
# against the defence and its blades carried to the release, read on their
# velocities and builds by the accurate lane model, at his own launch. A station
# read off a frozen defence stands in lanes its passer reads closed.

# Fills the ctx.scratch_feed_* buffers. Call once per decide, before feed_lane.
static func collect_feed_defence(ctx: RoleContext) -> void:
	ctx.scratch_feed_opp_release.clear()
	ctx.scratch_feed_opp_blades.clear()
	ctx.scratch_feed_opp_vels.clear()
	ctx.scratch_feed_opp_caps.clear()
	var windup: float = AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S
	for pid: int in ctx.snapshot.skater_states:
		if ctx.team_id_by_peer.get(pid, -1) == ctx.team_id:
			continue
		var s: SkaterNetworkState = ctx.snapshot.skater_states[pid]
		ctx.scratch_feed_opp_release.append(AITrajectory.predict_at(s.position, s.velocity, windup))
		var blade := Vector3(s.blade_contact_world.x, 0.0, s.blade_contact_world.z)
		ctx.scratch_feed_opp_blades.append(AITrajectory.predict_at(blade, s.velocity, windup))
		ctx.scratch_feed_opp_vels.append(s.velocity)
		ctx.scratch_feed_opp_caps.append(ctx.caps_by_peer.get(pid))


# Where our carrier's feed leaves from (AICarrierField.pass_origin_from);
# `carrier_pos` when no teammate carries the puck.
static func feed_origin(ctx: RoleContext, carrier_pos: Vector3) -> Vector3:
	var pid: int = _our_carrier(ctx)
	if pid == -1:
		return carrier_pos
	var puck: Vector3 = ctx.snapshot.puck_state.position
	return AICarrierField.pass_origin_from(Vector3(puck.x, 0.0, puck.z),
			ctx.snapshot.skater_states[pid].velocity)


# The launch of our carrier's feed from `origin` to a receiver standing at
# `spot`, under his own wrister.
static func feed_speed(ctx: RoleContext, origin: Vector3, spot: Vector3) -> float:
	var caps: AISkaterCaps = ctx.caps_by_peer.get(_our_carrier(ctx))
	var launch_cap: float = caps.wrister_shot_speed if caps != null \
			else GameRules.DEFAULT_WRISTER_POWER_MAX_M_S
	return AIPuckLane.pass_launch_speed(origin.distance_to(spot), launch_cap)


# The lane of that feed, against the defence collect_feed_defence filled.
static func feed_lane(ctx: RoleContext, origin: Vector3, spot: Vector3,
		speed: float) -> float:
	return AIPuckLane.lane_clear(origin, spot, ctx.scratch_feed_opp_release, speed,
			ctx.scratch_feed_opp_vels, ctx.scratch_feed_opp_caps, true,
			ctx.scratch_feed_opp_blades)


# What the feed of `lane` to a receiver at `spot` is worth, as the passer prices
# it in `objective`'s currency: completed, our possession there (`held`); picked
# off, the turnover where it is picked (AIPossessionValue.turnover_cost, `ours`
# read against their skaters, `theirs` against ours).
static func feed_ev(ctx: RoleContext, origin: Vector3, spot: Vector3, speed: float,
		lane: float, held: float, objective: int, ours: AIPossessionValue,
		theirs: AIPossessionValue) -> float:
	if lane >= 1.0:
		return held
	var loss: Vector3 = AIPuckLane.lane_loss_point(origin, spot,
			ctx.scratch_feed_opp_release, speed, ctx.scratch_feed_opp_vels,
			ctx.scratch_feed_opp_caps, ctx.scratch_feed_opp_blades)
	var cost: float = AIPossessionValue.turnover_cost(objective, loss, 0.0, ours, theirs) \
			if loss.is_finite() else 0.0
	return lane * held - (1.0 - lane) * cost


# The teammate carrying the puck, or -1.
static func _our_carrier(ctx: RoleContext) -> int:
	if ctx.snapshot == null or ctx.snapshot.puck_state == null:
		return -1
	var pid: int = ctx.snapshot.puck_state.carrier_peer_id
	if pid == -1 or ctx.team_id_by_peer.get(pid, -1) != ctx.team_id \
			or not ctx.snapshot.skater_states.has(pid):
		return -1
	return pid


# Our possession read (AIPossessionValue) against the opponents collect_opponents
# filled into `opponents` — the attack's scale for what a spot is worth to us.
# Call it after collect_opponents.
static func attack_possession(ctx: RoleContext,
		opponents: Array[Vector3]) -> AIPossessionValue:
	var poss: AIPossessionValue = ctx.scratch_attack_possession
	var holder: Vector3 = AIDefencePairing.collect_attack(ctx.snapshot, ctx.team_id_by_peer,
			ctx.team_id, ctx.scratch_attack_pairing, ctx.scratch_attack_pairing_vels)
	poss.fill(ctx.attacking_goal_pos, opponents, ctx.scratch_opp_vels,
			ctx.scratch_opp_caps, false, ctx.scratch_attack_pairing,
			ctx.scratch_attack_pairing_vels, holder)
	return poss


static func xz_distance(a: Vector3, b: Vector3) -> float:
	var dx: float = b.x - a.x
	var dz: float = b.z - a.z
	return sqrt(dx * dx + dz * dz)
