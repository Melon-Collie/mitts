class_name AIRoleHelpers

# Shared helpers for the role behaviors: candidate generation, legality and
# anti-crowd filters, context resolution, the defensive verbs, and the station
# reads. A role's own differentiator is its scoring function.

# Polar candidate ring radius. A sampling parameter, not a behavioral knob; the
# same scale as AICarrierCarrySearch.CARRY_SEARCH_STEP_M.
const SEARCH_STEP_M: float = 3.0

# Candidates this close to a teammate are filtered out: the physical-overlap
# distance, at blade-reach scale.
const ANTI_CROWD_RADIUS_M: float = 1.8

# Beyond this distance from a role's analytic station center, sampled roles skate
# at the calculated station instead of running the argmax: the ring spans
# ±SEARCH_STEP_M, so from three ring-radii out the heading to "center" vs
# "refined spot" differs by under ~20°, and the role re-refines from closer.
const STATION_ARGMAX_LOD_M: float = SEARCH_STEP_M * 3.0


# True when the bot is close enough to its station center that the
# candidate argmax's refinement affects the path it actually skates.
static func station_needs_refinement(self_pos: Vector3, center: Vector3) -> bool:
	return self_pos.distance_squared_to(center) \
			< STATION_ARGMAX_LOD_M * STATION_ARGMAX_LOD_M

# Margins inside the boards / goal lines that a legal candidate keeps.
const RINK_INSET_M: float = 0.5
const GOAL_LINE_BUFFER_M: float = 1.0

# Pre-baked rotations for the 8 polar cardinal candidates.
const POLAR_ANGLES: Array[float] = [
		0.0, PI * 0.25, PI * 0.5, PI * 0.75,
		PI, -PI * 0.75, -PI * 0.5, -PI * 0.25,
]


# ── Candidate generation ─────────────────────────────────────────────────────

# The standard 10-candidate set: `center`, `self_pos` (stand still), and 8 polar
# samples around `center` at SEARCH_STEP_M.
#
# `with_inner_ring` adds 8 more at half step, so an argmax whose pick is steered
# on directly every dispatch (PRESSURE) can make small corrections instead of
# jumping in SEARCH_STEP_M quanta.
static func generate_candidates_around(self_pos: Vector3,
		center: Vector3, with_inner_ring: bool = false) -> Array[Vector3]:
	var result: Array[Vector3] = []
	result.append(center)
	result.append(self_pos)
	for angle: float in POLAR_ANGLES:
		result.append(Vector3(
				center.x + SEARCH_STEP_M * cos(angle),
				0.0,
				center.z + SEARCH_STEP_M * sin(angle)))
	if with_inner_ring:
		var inner: float = SEARCH_STEP_M * 0.5
		for angle: float in POLAR_ANGLES:
			result.append(Vector3(
					center.x + inner * cos(angle),
					0.0,
					center.z + inner * sin(angle)))
	return result


# Rejects candidates outside the playable rink, in either crease, or past either
# goal line.
static func is_legal_position(c: Vector3) -> bool:
	if absf(c.x) > GameRules.RINK_HALF_WIDTH - RINK_INSET_M:
		return false
	if absf(c.z) > GameRules.GOAL_LINE_Z - GOAL_LINE_BUFFER_M:
		return false
	if CreaseRules.is_in_crease(Vector2(c.x, c.z)):
		return false
	return true


# `teammate_positions` must exclude self (collect_teammates_excluding_self).
static func too_close_to_teammate(c: Vector3,
		teammate_positions: Array[Vector3]) -> bool:
	var r2: float = ANTI_CROWD_RADIUS_M * ANTI_CROWD_RADIUS_M
	for tp: Vector3 in teammate_positions:
		var dx: float = c.x - tp.x
		var dz: float = c.z - tp.z
		if dx * dx + dz * dz < r2:
			return true
	return false


# ── Target switch-hysteresis ─────────────────────────────────────────────────
#
# Along an argmax's tie ridge two spots trade the lead on noise, and the off-puck
# cursor SNAPS to the role target, so a per-dispatch hop whips the blade. The
# incumbent (ctx.prev_role_target) is injected as one extra candidate and scored
# by the role's own scoring and filters — so an illegal or crowded incumbent is
# dropped rather than camped — plus this bonus.
#
# In threat-surface units (the 0..1 currency of score_shoot / score_pass). Feel
# tunable: raise toward 0.08 if a role wobbles between spots, lower toward 0.02
# if it camps a stale one.
const TARGET_SWITCH_MARGIN: float = 0.04


# No-op when there is no incumbent. Pair with incumbent_bonus in the scoring loop.
static func append_incumbent(ctx: RoleContext, candidates: Array[Vector3]) -> void:
	if ctx.prev_role_target.is_finite():
		candidates.append(ctx.prev_role_target)


# Add to the role's own score inside its argmax. Exact equality is safe: the
# incumbent is the same Vector3 append_incumbent injected.
static func incumbent_bonus(ctx: RoleContext, c: Vector3) -> float:
	if ctx.prev_role_target.is_finite() and c == ctx.prev_role_target:
		return TARGET_SWITCH_MARGIN
	return 0.0


# ── Defensive anticipation ───────────────────────────────────────────────────

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


# ── Man-on-threat coverage ───────────────────────────────────────────────────

# Slack on cover_man_target's goal-side filter: candidates may sit up to this far
# toward the play from the man (roughly even with him) but no further — a
# defender ahead of his man is one burst from being beaten to the net.
#
# Goal-side is measured along the man→our-net LINE, never the Z axis: for a man
# wide of the net, "behind him in Z" admits a spot BESIDE him, off the lane.
const COVER_GOAL_SIDE_TOLERANCE_M: float = 0.5

# The spot that most deflates the carrier→`man_pos` pass-threat surface (lane
# interception × the man's resulting shot), searched around the threat
# partition's cover anchor (AIThreatAssignment.cover_anchor).
#
# The search center must track the man 1:1: one that moves slower than he does (a
# man/net midpoint, say) lets a cutting man walk away from his check. It is also
# the anchor the partition scored reachability against, so pairing and coverage
# agree. Scoring the ASSIGNED man rather than the max over all opponents is what
# stops two defenders collapsing onto the same one.
static func cover_man_target(ctx: RoleContext, man_pos: Vector3,
		carrier_pos: Vector3) -> Vector3:
	var our_net: Vector3 = ctx.defending_goal_pos
	var our_goalie_pos: Vector3 = resolve_our_goalie_pos(ctx)
	var teammates: Array[Vector3] = ctx.scratch_teammates
	collect_teammates_excluding_self(ctx, teammates)

	var search_center: Vector3 = AIThreatAssignment.cover_anchor(man_pos, our_net)
	var candidates: Array[Vector3] = generate_candidates_around(ctx.self_pos, search_center)
	# Switch-hysteresis: hold the covering spot unless a fresh one deflates the
	# feed clearly more (see TARGET_SWITCH_MARGIN).
	append_incumbent(ctx, candidates)

	# Goal-side axis: the man→our-net direction (see COVER_GOAL_SIDE_TOLERANCE_M).
	var to_net_x: float = our_net.x - man_pos.x
	var to_net_z: float = our_net.z - man_pos.z
	var to_net_len: float = sqrt(to_net_x * to_net_x + to_net_z * to_net_z)
	var has_lane: bool = to_net_len > 0.001
	if has_lane:
		to_net_x /= to_net_len
		to_net_z /= to_net_len

	var best_pos: Vector3 = ctx.self_pos
	var best_score: float = -INF
	# Best of the candidates that failed ONLY the goal-side filter — for a man on
	# our goal line, where the buffer and crease leave no legal goal-side spot.
	var fallback_pos: Vector3 = ctx.self_pos
	var fallback_score: float = -INF
	for c: Vector3 in candidates:
		if not is_legal_position(c):
			continue
		if too_close_to_teammate(c, teammates):
			continue
		# Defenders = our team + us at c, push/popped into the shared scratch in
		# place; the hypothetical body carries our own caps.
		teammates.push_back(c)
		ctx.scratch_teammate_caps.push_back(ctx.caps_by_peer.get(ctx.peer_id))
		var threat: float = AIActionScoring.threat_surface_pass(
				carrier_pos, man_pos, our_net, our_goalie_pos,
				GameRules.NET_HALF_WIDTH, teammates, ctx.scratch_teammate_caps)
		teammates.pop_back()
		ctx.scratch_teammate_caps.pop_back()
		var score: float = -threat + incumbent_bonus(ctx, c)
		# A man on the net (no lane) disables the goal-side filter.
		var proj: float = (c.x - man_pos.x) * to_net_x + (c.z - man_pos.z) * to_net_z \
				if has_lane else 0.0
		if not has_lane or proj >= -COVER_GOAL_SIDE_TOLERANCE_M:
			if score > best_score:
				best_score = score
				best_pos = c
		elif score > fallback_score:
			fallback_score = score
			fallback_pos = c
	if best_score == -INF and fallback_score > -INF:
		return fallback_pos
	return best_pos


# The stand for a defender given somebody to cover: on the man, in the feed
# lane, riding him. False when there is no man or no play — the caller's cue to
# fall back to its own post rather than publish a ride it did not earn.
#
# Do not lead the man's position: the stand rides his velocity, so a lead
# double-counts his motion and covers from further off the faster he skates.
static func cover_threat(ctx: RoleContext, d: RoleDecision, man_pid: int,
		play_ref: Vector3) -> bool:
	if man_pid == -1 or ctx.snapshot == null \
			or not ctx.snapshot.skater_states.has(man_pid):
		return false
	if not play_ref.is_finite():
		return false
	var man: SkaterNetworkState = ctx.snapshot.skater_states[man_pid]
	d.target_position = cover_man_target(ctx, man.position, play_ref)
	d.target_velocity = man.velocity
	return true


# ── Closing the carrier: the angle ───────────────────────────────────────────

# How far to the INSIDE of the carrier→our-net line a defender who owns the
# carrier stands: take away the middle, give the outside. Dead on the line he
# offers both lanes equally.
const ANGLE_INSIDE_M: float = 1.5
# Lateral offset at which the shade reaches full depth — the end-zone dot lane;
# inside the dots there is no outside to concede yet.
const ANGLE_INSIDE_FULL_X_M: float = GameRules.END_ZONE_FACEOFF_DOT_X


# The shade's depth: nil at centre ice, full at the dot lane and beyond. The zero
# at centre is load-bearing: a fixed shade there must pick a side and flips
# 2 x ANGLE_INSIDE_M as he crosses x = 0, right on the mid-lane drive.
static func inside_shade_m(carrier_pos: Vector3) -> float:
	return ANGLE_INSIDE_M * minf(
			absf(carrier_pos.x) / ANGLE_INSIDE_FULL_X_M, 1.0)


# Unit vector perpendicular to the carrier's retreat line, pointing toward the
# middle of the ice. ZERO when the carrier is dead centre — there is no inside
# to take, and no side to pick.
static func inside_dir(carrier_pos: Vector3, dir_net: Vector3) -> Vector3:
	var side: float = -signf(carrier_pos.x)
	if side == 0.0:
		return Vector3.ZERO
	var perp := Vector3(-dir_net.z, 0.0, dir_net.x)
	return perp if perp.x * side > 0.0 else -perp


# The stand for a defender who owns the carrier: `gap` metres along the
# carrier→our-net line, shaded to the inside; unshaded when the shade is illegal.
static func carrier_stand(ap: AICarrierApproach, gap: float) -> Vector3:
	# Never past the net: beyond his own route there is no ice to hold.
	var stand: Vector3 = ap.carrier_pos + ap.dir_net * minf(gap, ap.net_dist)
	var depth: float = inside_shade_m(ap.carrier_pos)
	if depth < 0.001:
		return stand
	var shaded: Vector3 = stand + inside_dir(ap.carrier_pos, ap.dir_net) * depth
	return shaded if is_legal_position(shaded) else stand


# Fills `out` with the carrier a defender owns; false only when there is no puck
# at all. A loose puck is a live read (resolve_defensive_play_ref falls back to
# it). `out.dir_net` is ZERO when the carrier is on our net — no retreat line,
# and each role handles that case itself.
static func read_carrier_approach(ctx: RoleContext,
		out: AICarrierApproach) -> bool:
	var carrier_pos: Vector3 = resolve_defensive_play_ref(ctx)
	if not carrier_pos.is_finite():
		return false
	fill_approach(ctx, carrier_pos, resolve_play_ref_velocity(ctx), out)
	return true


# The same read against an explicit subject — the puck for chase_puck, since
# resolve_defensive_play_ref answers with the carrier whenever one exists.
static func fill_approach(ctx: RoleContext, subject_pos: Vector3,
		subject_vel: Vector3, out: AICarrierApproach) -> void:
	out.carrier_pos = subject_pos
	out.carrier_vel = subject_vel
	var to_net: Vector3 = ctx.defending_goal_pos - subject_pos
	var dist: float = sqrt(to_net.x * to_net.x + to_net.z * to_net.z)
	out.net_dist = dist
	if dist < 0.001:
		out.dir_net = Vector3.ZERO
		out.closing = 0.0
		return
	out.dir_net = Vector3(to_net.x / dist, 0.0, to_net.z / dist)
	out.closing = maxf(
			subject_vel.x * out.dir_net.x + subject_vel.z * out.dir_net.z, 0.0)


# ── Going to get the puck ────────────────────────────────────────────────────

# Do I go get it? TRUE: we are running the race, and `d` gets the puck — a hint
# CHASE_PUCK steers on until it takes over the real retrieval.
#
# FALSE: an opponent has already won it, and `d` gets the PRE-CONTAIN stand — the
# closing verb applied to the puck (ladder gap, ramp cushion at the puck's pace,
# angled off the middle), so it is exactly the stand RUSH_D1 wants when
# possession flips.
static func chase_puck(ctx: RoleContext, d: RoleDecision) -> bool:
	if ctx.snapshot == null or ctx.snapshot.puck_state == null:
		d.target_position = ctx.self_pos
		return false
	var puck_pos: Vector3 = ctx.snapshot.puck_state.position
	if not loose_puck_race_lost(
			ctx.snapshot, ctx.self_pos, ctx.self_velocity, ctx.self_max_speed,
			ctx.team_id, ctx.team_id_by_peer, ctx.caps_by_peer, ctx.peer_id,
			ctx.own_goal_dir):
		d.target_position = puck_pos
		return true
	var ap: AICarrierApproach = ctx.scratch_carrier_approach
	fill_approach(ctx, puck_pos, ctx.snapshot.puck_state.velocity, ap)
	if ap.dir_net == Vector3.ZERO:
		d.target_position = puck_pos   # on our own goal line — just go
		return true
	d.target_position = carrier_stand(ap, AIRoleRushD.ladder_gap_m(
			puck_pos, ctx.own_goal_dir, ctx.self_blade_reach,
			AIRoleRushD.ramp_cushion_m(ctx, ap, -1)))
	return false


# ── Carrier-best-option (inverse scoring) ────────────────────────────────────

# Per-decide upper bounds for carrier_best_option's early-out
# (out_bases[0] = shoot, [1..] = opp_teammates in order). Every threat surface is
# monotone NON-INCREASING in the defender set, so the values with the current
# defenders bound every candidate-adjusted value from above.
static func carrier_option_bases(
		carrier_pos: Vector3,
		our_net: Vector3,
		our_goalie_pos: Vector3,
		our_team_excluding_self: Array[Vector3],
		opp_teammates: Array[Vector3],
		out_bases: Array[float],
		our_team_caps: Array = []) -> void:
	out_bases.clear()
	out_bases.append(AIActionScoring.threat_surface_shoot(
			carrier_pos, our_net, our_goalie_pos,
			GameRules.NET_HALF_WIDTH, our_team_excluding_self, our_team_caps))
	for opp_pos: Vector3 in opp_teammates:
		out_bases.append(AIActionScoring.threat_surface_pass(
				carrier_pos, opp_pos, our_net, our_goalie_pos,
				GameRules.NET_HALF_WIDTH, our_team_excluding_self, our_team_caps))


# The opposing carrier's best option — shoot at our net, or pass to any of
# `opp_teammates` — with our hypothetical defender at `candidate` added to his
# view of the defenders. PRESSURE argmaxes its negation.
#
# Scored on the threat SURFACES so the gradient survives where score_shoot /
# score_pass collapse to 0 far from the net; their position_potential floor is
# what pulls a defender tight to a carrier with no immediate scoring threat.
# Coverage is continuous: a teammate already on a receiver suppresses that pass
# threat, with no separate "who is open" boolean.
static func carrier_best_option(
		candidate: Vector3,
		carrier_pos: Vector3,
		our_net: Vector3,
		our_goalie_pos: Vector3,
		our_team_excluding_self: Array[Vector3],
		opp_teammates: Array[Vector3],
		bases: Array[float] = [],
		our_team_caps: Array = [],
		self_caps: AISkaterCaps = null) -> float:
	# Defenders = our team + me at the candidate, push/popped into the caller's
	# array in place. Caps ride alongside only when the caller supplied a matched
	# array; otherwise the surfaces fall back to league.
	var caps_matched: bool = our_team_caps.size() == our_team_excluding_self.size()
	our_team_excluding_self.push_back(candidate)
	if caps_matched:
		our_team_caps.push_back(self_caps)
	var best: float = 0.0

	if bases.size() == opp_teammates.size() + 1:
		# Pruned path: evaluate in descending-bound order, stop when no remaining
		# bound can beat the running max. Exact — a skipped value ≤ its bound ≤ best.
		var used: int = 0
		while true:
			var bi: int = -1
			var bound: float = -1.0
			for i: int in bases.size():
				if used & (1 << i) == 0 and bases[i] > bound:
					bound = bases[i]
					bi = i
			if bi == -1 or bound <= best:
				break
			used |= 1 << bi
			var v: float
			if bi == 0:
				v = AIActionScoring.threat_surface_shoot(
						carrier_pos, our_net, our_goalie_pos,
						GameRules.NET_HALF_WIDTH, our_team_excluding_self,
						our_team_caps)
			else:
				v = AIActionScoring.threat_surface_pass(
						carrier_pos, opp_teammates[bi - 1], our_net, our_goalie_pos,
						GameRules.NET_HALF_WIDTH, our_team_excluding_self,
						our_team_caps)
			if v > best:
				best = v
		our_team_excluding_self.pop_back()
		if caps_matched:
			our_team_caps.pop_back()
		return best

	# Unpruned path (no bases supplied).
	var shoot_value: float = AIActionScoring.threat_surface_shoot(
			carrier_pos, our_net, our_goalie_pos,
			GameRules.NET_HALF_WIDTH, our_team_excluding_self, our_team_caps)

	var pass_value: float = 0.0
	for opp_pos: Vector3 in opp_teammates:
		var pass_score: float = AIActionScoring.threat_surface_pass(
				carrier_pos, opp_pos, our_net, our_goalie_pos,
				GameRules.NET_HALF_WIDTH, our_team_excluding_self, our_team_caps)
		if pass_score > pass_value:
			pass_value = pass_score

	our_team_excluding_self.pop_back()
	if caps_matched:
		our_team_caps.pop_back()
	return maxf(shoot_value, pass_value)


# Rush variant of carrier_best_option, for RUSH_D1's lane fan: RAW xG (no
# position_potential floor), each pass priced as a ONE-TIMER feed the goalie must
# traverse for, the direct shot against the goalie where he is — "the goalie takes
# the shooter, I take the pass".
#
# Not the surfaced variant: its floor is flat across the fan's gap distances, and
# a set-goalie pass read scores the one-timer feed near zero — hiding the threat
# the fan exists to take away.
#
# `abort_above` is exact pruning for a caller that MINIMIZES: once the running
# best exceeds it, the remaining receivers cannot matter. INF evaluates all.
static func carrier_live_option(
		candidate: Vector3,
		carrier_pos: Vector3,
		our_net: Vector3,
		our_goalie_pos: Vector3,
		our_team_excluding_self: Array[Vector3],
		opp_teammates: Array[Vector3],
		abort_above: float = INF,
		our_team_caps: Array = [],
		self_caps: AISkaterCaps = null) -> float:
	# Same in-place defender push/pop and caps contract as carrier_best_option.
	var caps_matched: bool = our_team_caps.size() == our_team_excluding_self.size()
	our_team_excluding_self.push_back(candidate)
	if caps_matched:
		our_team_caps.push_back(self_caps)
	var best: float = AIActionScoring.score_shoot(
			carrier_pos, our_net, our_goalie_pos,
			GameRules.NET_HALF_WIDTH, our_team_excluding_self,
			AIBotMechanics.WRISTER_SHOT_SPEED_M_S, 0.0, our_team_caps)
	for receiver: Vector3 in opp_teammates:
		if best >= abort_above:
			break
		var pass_speed: float = AIPuckLane.expected_pass_speed(carrier_pos, receiver)
		var flight_s: float = carrier_pos.distance_to(receiver) / maxf(pass_speed, 1.0)
		var pred_goalie: Vector3 = AIGoalieModel.predict_goalie_pos(
				our_goalie_pos, our_net, flight_s, receiver)
		var unsettled: float = AIGoalieModel.goalie_unsettled(
				our_goalie_pos, our_net, flight_s, receiver)
		var pass_value: float = AIActionScoring.score_pass(
				carrier_pos, receiver, our_net, pred_goalie,
				GameRules.NET_HALF_WIDTH, our_team_excluding_self, pass_speed,
				unsettled, -1.0, Vector4.INF, Vector4.INF, our_team_caps)
		if pass_value > best:
			best = pass_value
	our_team_excluding_self.pop_back()
	if caps_matched:
		our_team_caps.pop_back()
	return best


# ── Body check ───────────────────────────────────────────────────────────────

# Whether to commit to a body check on the live OPPONENT carrier this tick
# (AIBodyCheck). No-commit when the puck is loose, ours, or absent. Called by
# PRESSURE (and F1) and by TRACK_PUCK once goal-side; RUSH_D1 never calls it.
static func evaluate_body_check(ctx: RoleContext) -> AIBodyCheck.Result:
	if ctx.snapshot == null or ctx.snapshot.puck_state == null:
		return AIBodyCheck.Result.new()
	var carrier_pid: int = ctx.snapshot.puck_state.carrier_peer_id
	if carrier_pid == -1 or ctx.team_id_by_peer.get(carrier_pid, -1) == ctx.team_id:
		return AIBodyCheck.Result.new()
	if not ctx.snapshot.skater_states.has(carrier_pid):
		return AIBodyCheck.Result.new()
	# check_aggression: 0 = never commit; below 1 raises the required
	# separating-hit impulse inversely, so an easier bot commits only to the
	# hardest hits.
	if ctx.check_aggression <= 0.0:
		return AIBodyCheck.Result.new()
	var commit_threshold: float = AIBodyCheck.COMMIT_IMPULSE_M_S / ctx.check_aggression
	var carrier: SkaterNetworkState = ctx.snapshot.skater_states[carrier_pid]
	# The victim's real weight — don't commit to a hit you'd bounce off.
	var victim_caps: AISkaterCaps = ctx.caps_by_peer.get(carrier_pid)
	var victim_weight: float = victim_caps.weight if victim_caps != null \
			else AIBodyCheck.LEAGUE_VICTIM_WEIGHT
	return AIBodyCheck.evaluate(
			ctx.self_pos, ctx.self_max_speed, ctx.self_weight,
			ctx.self_body_check_transfer, ctx.self_stagger_timer,
			carrier.position, carrier.velocity, commit_threshold, victim_weight)


# ── Context resolution ──────────────────────────────────────────────────────

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


# The opposing goalie's replicated hand read (hole-model v3), for the
# pre-armed feed keeper (AIGoalieModel.resolve_feed_keeper). INF when no
# state is buffered — the resolver synthesizes the league stance.
static func opp_goalie_hands(ctx: RoleContext) -> Vector4:
	var goalie: GoalieNetworkState = ctx.snapshot.goalie_states.get(1 - ctx.team_id)
	if goalie == null:
		return Vector4.INF
	return goalie.hands_read(ctx.attacking_goal_pos.z)


# OUR goalie's replicated hand read — the defensive mirror.
static func our_goalie_hands(ctx: RoleContext) -> Vector4:
	var goalie: GoalieNetworkState = ctx.snapshot.goalie_states.get(ctx.team_id)
	if goalie == null:
		return Vector4.INF
	return goalie.hands_read(ctx.defending_goal_pos.z)


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
# ctx.scratch_teammate_caps index-matched.
static func collect_teammates_excluding_self(ctx: RoleContext,
		out: Array[Vector3]) -> void:
	out.clear()
	ctx.scratch_teammate_caps.clear()
	for pid: int in ctx.snapshot.skater_states:
		if pid == ctx.peer_id:
			continue
		if ctx.team_id_by_peer.get(pid, -1) == ctx.team_id:
			out.append(ctx.snapshot.skater_states[pid].position)
			ctx.scratch_teammate_caps.append(ctx.caps_by_peer.get(pid))


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
	for pid: int in ctx.snapshot.skater_states:
		if ctx.team_id_by_peer.get(pid, -1) != ctx.team_id:
			var s: SkaterNetworkState = ctx.snapshot.skater_states[pid]
			out_positions.append(lead_threat(s.position, s.velocity, ctx.defensive_anticipation_scale) \
					if anticipate else s.position)
			out_states.append(s)
			ctx.scratch_opp_caps.append(ctx.caps_by_peer.get(pid))
			ctx.scratch_opp_ids.append(pid)


# ── Offensive stations: the pinch read (docs/transition-defense-plan.md §13) ──
# SUPPORT is has_support_behind, NUMBERS is _attacker_behind; CONTROL stays
# unread. See Scripts/domain/ai/CLAUDE.md → "The three facts a station reads".

# While HOLDING, a station demands this much extra separation before it accepts
# that a man has got behind it — one more stick beyond the cover envelope.
const BEHIND_HOLD_EXTRA_M: float = 1.8

# How long a feed may be in flight and still make you a live passing option —
# sized on how long a carrier holds the puck in the offensive zone before he must
# move it.
const PLAY_CONNECTION_FLIGHT_S: float = 1.1


# True when a station may keep its forward stand. It is lost only when they have
# it and it is coming at us, or somebody is behind us and nobody covers for us —
# never because control is contested.
static func may_hold_forward_stand(ctx: RoleContext, was_holding: bool,
		stand: Vector3) -> bool:
	var read: AIRushRead = ctx.rush_read
	# An unwired read knows nothing: hold the shape.
	if not read.is_live:
		return true
	if not _we_possess(ctx) and read.mode == AIRushRead.Mode.RUSH:
		# THEIR puck: possession alone is no reason to bail — a bottled carrier is
		# exactly who you pinch on. The trigger is that they are moving out
		# (Mode.RUSH); bottled or turning back reads REGROUP: hold.
		return false
	# The numbers half: nobody behind us, or somebody covering for us if we get
	# beaten. `was_holding` makes it hysteretic — see _attacker_behind.
	return has_support_behind(ctx) or not _attacker_behind(ctx, stand, was_holding)


# True when one of ours carries the puck — whether a station is making a pinch
# decision at all.
static func _we_possess(ctx: RoleContext) -> bool:
	if ctx.snapshot == null or ctx.snapshot.puck_state == null:
		return false
	var pid: int = ctx.snapshot.puck_state.carrier_peer_id
	return pid != -1 and ctx.team_id_by_peer.get(pid, -1) == ctx.team_id


# The numbers-restoring retreat: only as far back as puts us goal-side of the
# deepest attacker behind our stand as we race him (AIRoleRushD.race_depth_to_net)
# — "count numbers, and if any are behind you, deal with it". With nobody behind
# the stand it is its own floor: no station is walked home for a phantom.
static func numbers_floor(ctx: RoleContext, stand: Vector3) -> Vector3:
	var read: AIRushRead = ctx.rush_read
	var our_net: Vector3 = ctx.defending_goal_pos
	var stand_d: float = xz_distance(stand, our_net)
	var deepest: float = stand_d
	for i: int in read.attackers.size():
		var d: float = AIRoleRushD.race_depth_to_net(ctx, read.attackers[i])
		if d < deepest:
			deepest = d
	if deepest >= stand_d:
		return stand   # nobody behind us — hold
	# Goal-side of him by a cover depth, along our own retreat line.
	var target_d: float = maxf(deepest - AIThreatAssignment.COVER_DEPTH_M, 0.0)
	var dx: float = stand.x - our_net.x
	var dz: float = stand.z - our_net.z
	var len_s: float = sqrt(dx * dx + dz * dz)
	if len_s < 0.001:
		return stand
	return Vector3(our_net.x + dx * (target_d / len_s), 0.0,
			our_net.z + dz * (target_d / len_s))


# Pull a station's target back within feedable range of the puck. See
# Scripts/domain/ai/CLAUDE.md → "The play-connection leash".
static func pull_into_play(ctx: RoleContext, target: Vector3) -> Vector3:
	if ctx.snapshot == null or ctx.snapshot.puck_state == null:
		return target
	# Only while WE have it: there is no passing option to be otherwise.
	if not _we_possess(ctx):
		return target
	var puck: Vector3 = ctx.snapshot.puck_state.position
	var reach: float = AIPuckLane.expected_pass_speed(puck, target) \
			* PLAY_CONNECTION_FLIGHT_S
	var dx: float = target.x - puck.x
	var dz: float = target.z - puck.z
	var d: float = sqrt(dx * dx + dz * dz)
	if d <= reach or d < 0.001:
		return target
	return Vector3(puck.x + dx * (reach / d), 0.0, puck.z + dz * (reach / d))


# The whole offensive-station decision: hold the forward stand (leashed to the
# play) while the read allows it; else restore the numbers layer if we still
# have the puck, or retreat to structure if we don't.
static func offensive_station_target(ctx: RoleContext, stand: Vector3,
		was_holding: bool, as_back_layer: bool = false) -> Vector3:
	if may_hold_forward_stand(ctx, was_holding, stand):
		return pull_into_play(ctx, stand)
	if _we_possess(ctx):
		# No leash on a retreat: clamping a recovery back up-ice toward the puck
		# would undo the coverage the read just called for.
		return numbers_floor(ctx, stand)
	return station_retreat_floor(ctx, stand, as_back_layer)


# The last-man bound for the NEUTRAL shapes (3v3 FLANK, 5v5 DBACK): the same
# read as offensive_station_target, but losing the forward stand restores a
# numbers layer — the deeper of numbers_floor and the caller's `layer_stand` —
# floored at the house gate, rather than a post. `layer_stand` also demands
# home_layer_behind_me to hold. See Scripts/domain/ai/CLAUDE.md → "Last-man
# discipline".
static func neutral_station_target(ctx: RoleContext, stand: Vector3,
		was_holding: bool, layer_stand: Vector3 = Vector3.INF) -> Vector3:
	if may_hold_forward_stand(ctx, was_holding, stand) \
			and (not layer_stand.is_finite() or home_layer_behind_me(ctx)):
		return stand
	var our_net: Vector3 = ctx.defending_goal_pos
	var sagged: Vector3 = numbers_floor(ctx, stand)
	# numbers_floor returns the stand untouched when nobody has beaten us, which
	# says nothing in a loose-puck state; take the deeper so both reasons bind.
	# Both lie on the net → stand ray, so a distance compare suffices.
	if layer_stand.is_finite() \
			and xz_distance(layer_stand, our_net) < xz_distance(sagged, our_net):
		sagged = layer_stand
	if xz_distance(sagged, our_net) >= AIZoneCoverage.HOUSE_TOP_DEPTH_M:
		return sagged
	return house_gate_floor(our_net, sagged)


# ── "If I go, is anybody home?" ──────────────────────────────────────────────
#
# has_support_behind's depth read, minus the elected chaser (committed to the
# puck, he holds nothing) and with a cover-envelope margin, so two bodies level
# with each other cover nothing for one another. Antisymmetric: exactly one body
# draws the layer, and no two can each appoint the other.
static func home_layer_behind_me(ctx: RoleContext) -> bool:
	if ctx.snapshot == null:
		return false
	var chaser: int = ctx.snapshot.closest_to_puck_by_team.get(ctx.team_id, -1)
	var my_depth: float = ctx.own_goal_dir * ctx.self_pos.z \
			+ AIRushRead.cover_envelope_m()
	for pid: int in ctx.snapshot.skater_states:
		if pid == ctx.peer_id or pid == chaser:
			continue
		if ctx.team_id_by_peer.get(pid, -1) != ctx.team_id:
			continue
		var mate: SkaterNetworkState = ctx.snapshot.skater_states[pid]
		if mate.is_ghost:
			continue
		if ctx.own_goal_dir * mate.position.z > my_depth:
			return true
	return false


# Is any attacker deeper (nearer our net) than `stand`, as we have to race him?
static func _attacker_behind(ctx: RoleContext, stand: Vector3,
		was_holding: bool = false) -> bool:
	var our_net: Vector3 = ctx.defending_goal_pos
	var stand_d: float = xz_distance(stand, our_net)
	# "Behind" means past the cover envelope (a goal-side stand plus a stick): a
	# man level with the stand is in the same layer, not past it.
	var margin: float = AIRushRead.cover_envelope_m()
	if was_holding:
		margin += BEHIND_HOLD_EXTRA_M
	for pid: int in ctx.rush_read.attackers:
		if AIRoleRushD.race_depth_to_net(ctx, pid) < stand_d - margin:
			return true
	return false


# ── Last-man step-up discipline ──────────────────────────────────────────────

# True when a teammate is deeper toward our net than we are — a layer that picks
# the carrier up if our challenge is beaten. False: we are the last man back.
# A depth read, not a race: "beaten wide, nobody home" is a positional question.
static func has_support_behind(ctx: RoleContext) -> bool:
	if ctx.snapshot == null:
		return false
	var my_depth: float = ctx.own_goal_dir * ctx.self_pos.z
	for pid: int in ctx.snapshot.skater_states:
		if pid == ctx.peer_id:
			continue
		if ctx.team_id_by_peer.get(pid, -1) != ctx.team_id:
			continue
		if ctx.own_goal_dir * ctx.snapshot.skater_states[pid].position.z > my_depth:
			return true
	return false


# The shallowest stand depth — metres goal-side of `threat_pos` along `dir_net`
# — the last man may take this dispatch, wanting `desired_depth` against a
# threat closing on our net at `closing` m/s. An ICE-FRAME bound: callers apply
# it only to a stand that does not ride a man.
#
# A speed limit on the approach, expressed as the stand that enforces it. In the
# threat-relative frame the defender's depth shrinks at `v + closing`, so
# becoming rush-matched from approach speed `v` costs
#
#     consumed(v) = v²/2B  +  closing·v/B  +  ramp(closing)
#                   \_____/    \________/     \___________/
#                   braking    the rush's     the PIVOT: the stride's distance
#                   distance   share of it    back up to his pace going the
#                                             other way
#
# which must fit in `spare = self_along - desired_depth`. The pivot term is what
# makes it gap control rather than merely arriving stopped. The stand is where a
# body at the cap would begin braking (v²/2B ahead), so the arrival brake is the
# actuator.
#
# The cap depends on the ICE, not the defender's speed, so it is state feedback.
# Never re-derive it as a per-dispatch step-up plan: recomputed with no memory
# of the plan it revises, that shape ratchets.
#
# Returns `desired_depth` unchanged when no bound applies (a stand already
# goal-side of us, or a threat not closing).
static func settable_stand_depth(ctx: RoleContext, threat_pos: Vector3,
		dir_net: Vector3, desired_depth: float, closing: float) -> float:
	var self_along: float = (ctx.self_pos.x - threat_pos.x) * dir_net.x \
			+ (ctx.self_pos.z - threat_pos.z) * dir_net.z
	var spare: float = self_along - desired_depth
	if spare <= 0.0 or closing <= 0.01:
		return desired_depth
	var v_cap: float = approach_speed_cap(
			spare, closing, ctx.self_max_speed, ctx.self_max_accel)
	var brake_lead: float = v_cap * v_cap \
			/ (2.0 * AISteering.ARRIVAL_BRAKE_DECEL_M_S2)
	return maxf(desired_depth, self_along - brake_lead)


# The positive root of settable_stand_depth's `consumed(v) = spare`, clamped to
# [0, v_max]: with less spare depth than the pivot alone costs, he holds.
static func approach_speed_cap(spare: float, closing: float, v_max: float,
		max_accel: float) -> float:
	var brake_decel: float = AISteering.ARRIVAL_BRAKE_DECEL_M_S2
	var pivot: float = AIStrideRamp.distance_to_speed(closing, max_accel)
	# v² + 2·closing·v + 2B·(pivot - spare) = 0
	var disc: float = closing * closing + 2.0 * brake_decel * (spare - pivot)
	if disc <= 0.0:
		return 0.0
	return clampf(sqrt(disc) - closing, 0.0, maxf(v_max, 0.0))


# How much deeper than the stand a home post must be to count as a retreat — one
# stride, so a station standing on its own post falls to the house gate instead.
const HOME_FLOOR_BIND_MARGIN_M: float = 1.0


# offensive_station_target's retreat when the puck is no longer ours: "get back
# to your post", never the crease — defending an actual rush is transition
# defense's job (docs/transition-defense-plan.md §2.1). A station up-ice of its
# home post (AIZoneCoverage.defensive_anchor) floors there; one already at home
# floors at the house gate.
#
# `as_back_layer` forces the DEFENSEMAN's post: ctx.self_is_defense is a lobby
# fact, and in 3v3 every peer reads "forward", so a role that is its team's whole
# back layer (3v3's F3_HIGH) would otherwise floor too shallow.
static func station_retreat_floor(ctx: RoleContext, fwd: Vector3,
		as_back_layer: bool = false) -> Vector3:
	var our_net: Vector3 = ctx.defending_goal_pos
	var home: Vector3 = AIZoneCoverage.defensive_anchor(
			ctx.self_is_defense or as_back_layer, ctx.self_home_side, our_net.z)
	if ctx.own_goal_dir * home.z > ctx.own_goal_dir * fwd.z + HOME_FLOOR_BIND_MARGIN_M:
		return home
	return house_gate_floor(our_net, fwd)


# Holds `pos` OUT at the house gate when it was placed deeper, projecting along
# the net → pos ray (straight up the rink axis from the net itself).
static func hold_out_to_house_gate(our_net: Vector3, pos: Vector3) -> Vector3:
	var dx: float = pos.x - our_net.x
	var dz: float = pos.z - our_net.z
	var dsq: float = dx * dx + dz * dz
	var gate: float = AIZoneCoverage.HOUSE_TOP_DEPTH_M
	if dsq >= gate * gate:
		return pos
	var dl: float = sqrt(dsq)
	if dl < 0.001:
		return Vector3(our_net.x, 0.0, our_net.z - signf(our_net.z) * gate)
	return Vector3(our_net.x + dx * (gate / dl), 0.0, our_net.z + dz * (gate / dl))


# Clamps `fwd` onto the net → `fwd` ray at the house gate when it lies beyond it:
# the deepest a last-man bound may push a field skater. Inside it he duplicates
# the goalie and fights his own crease repel.
static func house_gate_floor(our_net: Vector3, fwd: Vector3) -> Vector3:
	var dx: float = fwd.x - our_net.x
	var dz: float = fwd.z - our_net.z
	var d: float = sqrt(dx * dx + dz * dz)
	if d < 0.001 or d <= AIZoneCoverage.HOUSE_TOP_DEPTH_M:
		return fwd
	var k: float = AIZoneCoverage.HOUSE_TOP_DEPTH_M / d
	return Vector3(our_net.x + dx * k, 0.0, our_net.z + dz * k)


static func xz_distance(a: Vector3, b: Vector3) -> float:
	var dx: float = b.x - a.x
	var dz: float = b.z - a.z
	return sqrt(dx * dx + dz * dz)


# Should I decline a loose puck? True when a committed opponent reaches it a
# clear contest band (CHASE_CONTEST_MARGIN_M) ahead of me AND nobody else contains
# the counter. Inside the band it is a live 50/50 worth racing.
#
# `own_goal_dir` (+1 = our net at +Z) enables the containment read; 0.0 (unit
# tests only) claims no containment.
static func loose_puck_race_lost(
		snapshot: WorldSnapshot, self_pos: Vector3, self_vel: Vector3,
		self_max_speed: float, team_id: int, team_id_by_peer: Dictionary,
		caps_by_peer: Dictionary, self_pid: int = -1,
		own_goal_dir: float = 0.0) -> bool:
	if snapshot == null or snapshot.puck_state == null:
		return false
	var puck_pos: Vector3 = snapshot.puck_state.position
	# Race the puck's predicted path, never its current position, on the chase
	# election's own walk so the decline cannot contradict it.
	var puck_vel: Vector3 = snapshot.puck_state.velocity
	var traj: Array[Vector3] = AILoosePuckChase.race_trajectory(puck_pos, puck_vel)
	var step_dt: float = AILoosePuckChase.RACE_LOOKAHEAD_S \
			/ float(AILoosePuckChase.RACE_STEPS)
	var margin: float = AILoosePuckChase.setup_margin(puck_vel)
	var t_play: float = AILoosePuckChase.race_playable_time(puck_pos, puck_vel)
	var self_vmax: float = maxf(self_max_speed, 1.0)
	var my_eta: float = AILoosePuckChase.path_intercept_time(
			traj, step_dt, puck_pos, self_pos, self_vel, self_vmax, margin,
			AIArrival.SHED_ACCEL_DEFAULT_M_S2, 0.0, t_play)
	var best_opp_eta: float = INF
	var best_opp_meet: Vector3 = puck_pos
	for pid: int in snapshot.skater_states:
		if team_id_by_peer.get(pid, -1) == team_id:
			continue
		var s: SkaterNetworkState = snapshot.skater_states[pid]
		# Lost only to an opponent RUNNING it: the ETA prices a hypothetical run,
		# so a flat-footed body off the line would otherwise veto the chase. A
		# downstream interceptor whose band the puck's path enters counts.
		var speed: float = AILoosePuckChase.race_vmax(caps_by_peer.get(pid))
		var t: float = AILoosePuckChase.path_intercept_time(
				traj, step_dt, puck_pos, s.position, s.velocity, speed, margin,
				AIArrival.SHED_ACCEL_DEFAULT_M_S2, 0.0, t_play)
		var meet: Vector3 = AILoosePuckChase.path_intercept_point(
				traj, step_dt, puck_pos, t)
		var committed: bool = AILoosePuckChase.path_enters_band(traj, puck_pos,
				s.position, AIActionScoring.CHASE_CONTEST_MARGIN_M) \
				or AILoosePuckChase.committed_to_point(s, meet)
		if not committed:
			continue
		if t < best_opp_eta:
			best_opp_eta = t
			best_opp_meet = meet
	if best_opp_eta == INF:
		return false
	var contest_window: float = AIActionScoring.CHASE_CONTEST_MARGIN_M \
			/ maxf(self_max_speed, 1.0)
	if my_eta <= best_opp_eta + contest_window:
		return false
	# Declining buys a pre-contain body, worth it only when nobody else contains.
	return not _has_containment_behind(snapshot, team_id, team_id_by_peer,
			self_pid, best_opp_meet, own_goal_dir)


# Is someone else covering the counter, so that leaving to chase is free? A live
# teammate qualifies if he is GOAL-SIDE of the pickup, or can reach the HOUSE GATE
# inside AIRushRead.LATE_MAN_WINDOW_S — the second because nothing can be
# goal-side of a puck behind our own goal line.
#
# Never re-phrase this as a race to the pickup: behind our goal line the pickup
# IS our net, so the collector is already home and nobody beats him there.
static func _has_containment_behind(snapshot: WorldSnapshot, team_id: int,
		team_id_by_peer: Dictionary, self_pid: int, pickup: Vector3,
		own_goal_dir: float) -> bool:
	if own_goal_dir == 0.0:
		return false
	var gate := Vector3(0.0, 0.0, own_goal_dir
			* (GameRules.GOAL_LINE_Z - AIZoneCoverage.HOUSE_TOP_DEPTH_M))
	for pid: int in snapshot.skater_states:
		if pid == self_pid or team_id_by_peer.get(pid, -1) != team_id:
			continue
		var mate: SkaterNetworkState = snapshot.skater_states[pid]
		if mate.is_ghost:
			continue
		if own_goal_dir * (mate.position.z - pickup.z) \
				> AIActionScoring.CHASE_CONTEST_MARGIN_M:
			return true
		if AIArrival.time_to_arrive(mate.position, gate, mate.velocity) \
				<= AIRushRead.LATE_MAN_WINDOW_S:
			return true
	return false
