class_name AIDefensiveVerbs

# The defensive verbs every defending role is composed of — cover a threat, take
# the angle on a carrier, cut him off from the middle, read his approach, chase
# the puck, price his best option, deliver a check. See Scripts/domain/ai/CLAUDE.md → "The defensive
# verbs".


# Slack on cover_man_target's goal-side filter: candidates may sit up to this far
# toward the play from the man (roughly even with him) but no further — a
# defender ahead of his man is one burst from being beaten to the net.
#
# Goal-side is measured along the man→our-net LINE, never the Z axis: for a man
# wide of the net, "behind him in Z" admits a spot BESIDE him, off the lane.
const COVER_GOAL_SIDE_TOLERANCE_M: float = 0.5


# The spot that most deflates the threat of the carrier's feed to the man at
# `man_pos`, moving at `man_vel` (AIPossessionValue.threat_of_feed: the lane ×
# his one-timer or his possession of the spot), searched around the threat
# partition's cover anchor (AIThreatAssignment.cover_anchor).
#
# The search center must track the man 1:1: one that moves slower than he does (a
# man/net midpoint, say) lets a cutting man walk away from his check. It is also
# the anchor the partition scored reachability against, so pairing and coverage
# agree. Scoring the ASSIGNED man rather than the max over all opponents is what
# stops two defenders collapsing onto the same one.
static func cover_man_target(ctx: RoleContext, man_pos: Vector3, man_vel: Vector3,
		carrier_pos: Vector3) -> Vector3:
	var our_net: Vector3 = ctx.defending_goal_pos
	var our_goalie_pos: Vector3 = AIRoleReads.resolve_our_goalie_pos(ctx)
	var teammates: Array[Vector3] = ctx.scratch_teammates
	AIRoleReads.collect_teammates_excluding_self(ctx, teammates)
	var poss: AIPossessionValue = AIRoleReads.defence_possession(ctx, teammates)
	var self_caps: AISkaterCaps = ctx.caps_by_peer.get(ctx.peer_id)

	var search_center: Vector3 = AIThreatAssignment.cover_anchor(man_pos, our_net)
	var candidates: Array[Vector3] = AIStationSearch.generate_candidates_around(ctx.self_pos, search_center)
	# Switch-hysteresis: hold the covering spot unless a fresh one deflates the
	# feed clearly more (see AIStationSearch.TARGET_SWITCH_MARGIN).
	AIStationSearch.append_incumbent(ctx, candidates)

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
	# The man's possession with nobody of ours at a candidate: no candidate raises
	# it, so a candidate whose lane times it cannot beat the one-timer skips it.
	var possession_bound: float = poss.feed_possession(carrier_pos, man_pos, man_vel)
	for c: Vector3 in candidates:
		if not AIStationSearch.is_legal_position(c):
			continue
		if AIStationSearch.too_close_to_teammate(c, teammates):
			continue
		poss.push_defender(c, Vector3.ZERO, self_caps)
		var threat: float = poss.threat_of_feed(carrier_pos, man_pos, man_vel,
				our_goalie_pos, possession_bound)
		poss.pop_defender()
		var score: float = -threat + AIStationSearch.incumbent_bonus(ctx, c)
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
	d.target_position = _depth_before_width(ctx, man, man_pid,
			cover_man_target(ctx, man.position, man.velocity, play_ref))
	d.target_velocity = man.velocity
	return true


# `stand`, when it is across the man's line to our net from this body, brought
# no further across than the depth he holds on the man past what building to
# his pace gives up (AIRoleRushD.head_start_on_me). The stride a coverer spends
# crossing in front of a man who gains on him is the stride his retreat needs,
# and the man is past him as he gets there.
static func _depth_before_width(ctx: RoleContext, man: SkaterNetworkState, man_pid: int,
		stand: Vector3) -> Vector3:
	var to_net := Vector3(ctx.defending_goal_pos.x - man.position.x, 0.0,
			ctx.defending_goal_pos.z - man.position.z)
	var net_dist: float = to_net.length()
	if net_dist < 0.001:
		return stand
	var dir_net: Vector3 = to_net / net_dist
	var side := Vector3(-dir_net.z, 0.0, dir_net.x)
	var from_man: Vector3 = ctx.self_pos - man.position
	if from_man.dot(side) * (stand - man.position).dot(side) >= 0.0:
		return stand
	var depth: float = from_man.dot(dir_net)
	var cushion: float = AIRoleRushD.head_start_on_me(ctx, dir_net, man.velocity, net_dist,
			man_pid, AIRoleRushD.RETREAT_FINISH_M)
	if depth <= 0.0 or cushion <= 0.0:
		return stand
	var to_stand := Vector3(stand.x - ctx.self_pos.x, 0.0, stand.z - ctx.self_pos.z)
	var along: float = to_stand.dot(dir_net)
	return ctx.self_pos + dir_net * along \
			+ (to_stand - dir_net * along).limit_length(maxf(depth - cushion, 0.0))


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
# carrier→our-net line, shaded to the inside by `shade_share` of the shade;
# unshaded when the shade is illegal.
static func carrier_stand(ap: AICarrierApproach, gap: float, shade_share: float = 1.0) -> Vector3:
	# Never past the net: beyond his own route there is no ice to hold.
	var stand: Vector3 = ap.carrier_pos + ap.dir_net * minf(gap, ap.net_dist)
	var depth: float = inside_shade_m(ap.carrier_pos) * shade_share
	if depth < 0.001:
		return stand
	var shaded: Vector3 = stand + inside_dir(ap.carrier_pos, ap.dir_net) * depth
	return shaded if AIStationSearch.is_legal_position(shaded) else stand


# The cut-off's walk along the carrier's route to our net: under a stick, so the
# point taken is within a stick of the first one he can be cut off at.
const CUT_OFF_STEP_M: float = 1.0
# Bisections of the exact cut-off's last step: 1/64 of a metre.
const CUT_OFF_BISECTIONS: int = 6
# The carrier's first carve on his route (AIArrival.first_carve) and the point
# cut_off_m last took on it: the AI worker's scratch, read before the next call.
static var _route := AIArrival.Carve.new()
static var _cut_at: Vector3 = Vector3.ZERO


# Whether the middle is open on me: I do not stand between the carrier's line to
# our net, where it passes my depth, and the middle of the ice, give or take a
# stick. Depth before width is for a defender already inside him; one outside
# him, or across the middle from him, holds depth in a lane the carrier is not
# in, and the slot is his.
static func middle_open(ctx: RoleContext, ap: AICarrierApproach) -> bool:
	var my_depth: float = (ctx.self_pos.x - ap.carrier_pos.x) * ap.dir_net.x \
			+ (ctx.self_pos.z - ap.carrier_pos.z) * ap.dir_net.z
	var line_x: float = ap.carrier_pos.x + ap.dir_net.x * my_depth
	var mid_x: float = ctx.defending_goal_pos.x
	var reach: float = AIRoleRushD.stick_m(ctx)
	return ctx.self_pos.x < minf(line_x, mid_x) - reach \
			or ctx.self_pos.x > maxf(line_x, mid_x) + reach


# The first ice on the carrier's route to our net my stick gets to before he
# does (cut_off_m), skated to facing travel and ridden as he moves: `d`'s
# velocity and facing, and the point. Whichever way he goes to the net from
# there, he meets the body or the reach-in.
static func cut_off(ctx: RoleContext, ap: AICarrierApproach, d: RoleDecision) -> Vector3:
	d.face_travel = true
	var finish: float = ap.net_dist - AIRoleRushD.RETREAT_FINISH_M
	if finish <= 0.0:
		d.target_velocity = ap.carrier_vel
		return ap.carrier_pos
	var peer: int = ctx.snapshot.puck_state.carrier_peer_id \
			if ctx.snapshot != null and ctx.snapshot.puck_state != null else -1
	var caps: AISkaterCaps = ctx.caps_by_peer.get(peer) if peer != -1 else null
	cut_off_m(ctx.self_pos, ctx.self_velocity, ctx.self_max_speed, ctx.self_max_accel,
			AIRoleRushD.stick_m(ctx), ap.carrier_pos, ap.carrier_vel, ap.dir_net, finish, caps)
	var at: Vector3 = _cut_at
	# A point a fixed share of the way to a fixed net moves at the rest of the
	# carrier's velocity.
	var left: float = Vector2(ctx.defending_goal_pos.x - at.x,
			ctx.defending_goal_pos.z - at.z).length() / ap.net_dist
	d.target_velocity = ap.carrier_vel * clampf(left, 0.0, 1.0)
	return at


# How far along the carrier's route to our net the first ice is that a body at
# `self_pos` gets his stick to before the carrier, the point in _cut_at. The
# route is the clock's own: his first carve (AIArrival.first_carve, along its
# chord) and the straight from its exit to `finish_m` down his line to our net
# (`dir_net`, the crease's top). The body is raced on its arrival clock from where
# he is and how he moves, the stick reaching the ice `reach_m` at his top speed
# before the body does; the carrier through the carve at its share of the
# carve's time, and on from its exit at its velocity, at his free top speed
# (`his_caps` or the league's, a slight over-read in the safe direction). Never
# race him to the points of the straight line from where he stands: off it at
# speed he skates wide of its first strides, and timed as the loop back onto
# them the race handed them to a defender stepping onto him. The route's length
# when he beats him nowhere short of the finish. Walked in CUT_OFF_STEP_M steps;
# `exact` bisects the last one, for a race between bodies, where the step would
# tie men a step's width apart.
static func cut_off_m(self_pos: Vector3, self_vel: Vector3, self_vmax: float,
		self_accel: float, reach_m: float, carrier_pos: Vector3, carrier_vel: Vector3,
		dir_net: Vector3, finish_m: float, his_caps: AISkaterCaps,
		exact: bool = false) -> float:
	var his_speed: float = his_caps.max_speed if his_caps != null \
			else GameRules.DEFAULT_SKATER_MAX_SPEED_M_S
	var his_accel: float = his_caps.max_accel if his_caps != null \
			else GameRules.DEFAULT_SKATER_THRUST_M_S2
	var his_grip: float = his_caps.lateral_grip if his_caps != null else 1.0
	var finish: Vector3 = carrier_pos + dir_net * finish_m
	AIArrival.first_carve(_route, carrier_pos, finish, carrier_vel, his_speed, his_accel,
			his_grip)
	var carve_m: float = Vector2(_route.exit_pos.x - carrier_pos.x,
			_route.exit_pos.z - carrier_pos.z).length()
	var total: float = carve_m + Vector2(finish.x - _route.exit_pos.x,
			finish.z - _route.exit_pos.z).length()
	var stick_s: float = reach_m / maxf(self_vmax, 0.1)
	var s: float = 0.0
	while s < total:
		if _cuts_off_at(s, carve_m, total, carrier_pos, finish, self_pos, self_vel, self_vmax,
				self_accel, stick_s, his_speed, his_accel, his_grip):
			break
		s += CUT_OFF_STEP_M
	if s >= total:
		_cut_at = finish
		return total
	if exact and s > 0.0:
		var lost: float = s - CUT_OFF_STEP_M
		for _i: int in CUT_OFF_BISECTIONS:
			var mid: float = 0.5 * (lost + s)
			if _cuts_off_at(mid, carve_m, total, carrier_pos, finish, self_pos, self_vel,
					self_vmax, self_accel, stick_s, his_speed, his_accel, his_grip):
				s = mid
			else:
				lost = mid
	_cut_at = _route_point(s, carve_m, total, carrier_pos, finish)
	return s


# The point `s` along the route cut_off_m filled _route for.
static func _route_point(s: float, carve_m: float, total: float, carrier_pos: Vector3,
		finish: Vector3) -> Vector3:
	if s <= carve_m and carve_m > 0.0:
		return carrier_pos.lerp(_route.exit_pos, s / carve_m)
	var straight: float = total - carve_m
	if straight <= 0.0:
		return finish
	return _route.exit_pos.lerp(finish, (s - carve_m) / straight)


static func _cuts_off_at(s: float, carve_m: float, total: float, carrier_pos: Vector3,
		finish: Vector3, self_pos: Vector3, self_vel: Vector3, self_vmax: float,
		self_accel: float, stick_s: float, his_speed: float, his_accel: float,
		his_grip: float) -> bool:
	var at: Vector3 = _route_point(s, carve_m, total, carrier_pos, finish)
	var his_t: float = _route.time * s / carve_m if s <= carve_m and carve_m > 0.0 \
			else _route.time + AIArrival.time_to_arrive(_route.exit_pos, at, _route.exit_vel,
					his_speed, his_accel, his_grip)
	return AIArrival.time_to_arrive(self_pos, at, self_vel, self_vmax, self_accel) \
			<= his_t + stick_s


# Fills `out` with the carrier a defender owns; false only when there is no puck
# at all. A loose puck is a live read (AIRoleReads.resolve_defensive_play_ref falls back to
# it). `out.dir_net` is ZERO when the carrier is on our net — no retreat line,
# and each role handles that case itself.
static func read_carrier_approach(ctx: RoleContext,
		out: AICarrierApproach) -> bool:
	var carrier_pos: Vector3 = AIRoleReads.resolve_defensive_play_ref(ctx)
	if not carrier_pos.is_finite():
		return false
	fill_approach(ctx, carrier_pos, AIRoleReads.resolve_play_ref_velocity(ctx), out)
	return true


# The same read against an explicit subject — the puck for chase_puck, since
# AIRoleReads.resolve_defensive_play_ref answers with the carrier whenever one exists.
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


# Do I go get it? TRUE: we are running the race, and `d` gets the puck — a hint
# CHASE_PUCK steers on until it takes over the real retrieval.
#
# FALSE: an opponent has already won it, and `d` gets the PRE-CONTAIN stand — the
# closing verb applied to the puck (ladder gap, ramp cushion at the puck's pace,
# angled off the middle), so it is exactly the stand BACK_STRONG wants when
# possession flips.
static func chase_puck(ctx: RoleContext, d: RoleDecision) -> bool:
	if ctx.snapshot == null or ctx.snapshot.puck_state == null:
		d.target_position = ctx.self_pos
		return false
	var puck_pos: Vector3 = ctx.snapshot.puck_state.position
	if not AILoosePuckChase.loose_puck_race_lost(
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


# Per-decide upper bounds for carrier_best_option's early-out
# (out_bases[0] = his own threat, [1..] = the feed to each of `opp_teammates`).
# Every threat is monotone NON-INCREASING in the defender set, so the values with
# the current defenders (`poss`, AIRoleReads.defence_possession) bound every
# candidate-adjusted value from above.
static func carrier_option_bases(poss: AIPossessionValue, carrier_pos: Vector3,
		carrier_vel: Vector3, our_goalie_pos: Vector3, opp_teammates: Array[Vector3],
		out_bases: Array[float]) -> void:
	out_bases.clear()
	out_bases.append(poss.threat_of_carrier(carrier_pos, carrier_vel, our_goalie_pos))
	for opp_pos: Vector3 in opp_teammates:
		out_bases.append(poss.threat_of_feed(carrier_pos, opp_pos, Vector3.ZERO,
				our_goalie_pos))


# The opposing carrier's best option — keep it himself, or feed any of
# `opp_teammates` (already led by anticipation, so read standing) — with our
# hypothetical defender at `candidate`, skating at `candidate_vel` (the stand's
# ride: a body holding station on him is not one he out-skates), added to
# `poss`'s defenders. PRESSURE
# argmaxes its negation. On the possession scale, so the gradient survives where
# the shot collapses to 0 far from the net: what a body there takes from his
# possession is what pulls a defender tight to a carrier with no shot. Coverage
# is continuous: a teammate already on a receiver suppresses that feed.
#
# `bases` (carrier_option_bases) prunes exactly: options are evaluated in
# descending-bound order and stop when no remaining bound beats the running max.
#
# `set_in_s`: the defender is set at `candidate` that long from now, and until
# then the carrier skates on. His own option is read from where his skating has
# him by then, the boards stopping him as they stop the defence (predict_at),
# against the defence carried on to then (the candidate with it,
# at `candidate_vel`); always evaluated, since its bound was read where he is
# now. His feeds are read as now.
static func carrier_best_option(poss: AIPossessionValue, candidate: Vector3,
		candidate_vel: Vector3, self_caps: AISkaterCaps, carrier_pos: Vector3,
		carrier_vel: Vector3, our_goalie_pos: Vector3, opp_teammates: Array[Vector3],
		bases: Array[float], set_in_s: float = 0.0) -> float:
	poss.push_defender(candidate, candidate_vel, self_caps)
	var best: float = 0.0
	var used: int = 0
	if set_in_s > 0.0:
		best = poss.threat_of_carrier(AITrajectory.predict_at(carrier_pos, carrier_vel, set_in_s),
				carrier_vel, our_goalie_pos,
				set_in_s)
		used = 1
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
		var v: float = poss.threat_of_carrier(carrier_pos, carrier_vel, our_goalie_pos) \
				if bi == 0 else poss.threat_of_feed(carrier_pos, opp_teammates[bi - 1],
						Vector3.ZERO, our_goalie_pos)
		best = maxf(best, v)
	poss.pop_defender()
	return best


# Whether to commit to a body check on the live OPPONENT carrier this tick
# (AIBodyCheck). No-commit when the puck is loose, ours, or absent. Called by
# PRESSURE (and F1) and by NZ_F1 once goal-side; BACK_STRONG never calls it.
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
	var self_caps: AISkaterCaps = ctx.caps_by_peer.get(ctx.peer_id)
	var contact_m: float = (self_caps.body_radius if self_caps != null else AISkaterCaps.LEAGUE_BODY_RADIUS_M) \
			+ (victim_caps.body_radius if victim_caps != null else AISkaterCaps.LEAGUE_BODY_RADIUS_M)
	return AIBodyCheck.evaluate(
			ctx.self_pos, ctx.self_velocity, ctx.self_max_speed, ctx.self_max_accel,
			ctx.self_weight, ctx.self_body_check_transfer, ctx.self_stagger_timer,
			carrier.position, carrier.velocity, contact_m, commit_threshold, victim_weight)
