class_name AIRolePressure

# PRESSURE (3v3 DZONE) and F1_PRESSURE (the forecheck, both team sizes) — the
# puck pressurer: get goal-side of the carrier and take away his best option.
#
# INVERSE SCORING: each candidate is scored by how much our body there deflates
# the carrier's best option (AIDefensiveVerbs.carrier_best_option). The argmax
# takes carrier_stand as the ring's centre and the gap and inside shade as
# floors, then picks the bearing.

# Engaged/closing boundary: inside it the argmax runs the full polar ring,
# outside it only the calculated closing stands. 1.5 search steps.
const PRESSURE_INNER_RING_RANGE_M: float = 4.5


# `cover_priced`: the caller has already priced who picks the play up if the
# challenge is beaten (the pinch's rotation), so the hit needs no man behind.
static func decide(ctx: RoleContext, cover_priced: bool = false) -> RoleDecision:
	var d := RoleDecision.new()

	# A loose puck is a live read; stand still only with no puck at all.
	var ap: AICarrierApproach = ctx.scratch_carrier_approach
	if not AIDefensiveVerbs.read_carrier_approach(ctx, ap):
		d.target_position = ctx.self_pos
		return d
	var carrier_pos: Vector3 = ap.carrier_pos

	# A committed hit loads him on a shoulder at half a stride, so a carrier who
	# cuts is gone: the last man back never throws one (has_support_behind).
	if cover_priced or AILastManDiscipline.has_support_behind(ctx):
		var check: AIBodyCheck.Result = AIDefensiveVerbs.evaluate_body_check(ctx)
		if check.commit:
			d.commit_check = true
			d.target_position = check.target
			return d

	var our_net: Vector3 = ctx.defending_goal_pos
	var our_goalie_pos: Vector3 = AIRoleReads.resolve_our_goalie_pos(ctx)

	var our_team_excluding_self: Array[Vector3] = ctx.scratch_teammates
	AIRoleReads.collect_teammates_excluding_self(ctx, our_team_excluding_self)

	# Anticipated, so PRESSURE shades toward where a feed is going.
	var opp_teammates: Array[Vector3] = ctx.scratch_opp_receivers
	AIRoleReads.collect_opp_team_excluding_carrier(ctx, opp_teammates, true)

	# The cut-off distance is the shared gap ladder, sized off the carrier's REAL
	# position — never a led one (the stand rides him). Its domain is
	# should_gap_up: see Scripts/domain/ai/CLAUDE.md → "The ladder has a domain".
	var carrier_velocity: Vector3 = ap.carrier_vel
	var closing_now: float = ap.closing
	var cushion: float = AIRoleRushD.ramp_cushion_m(
			ctx, ap, ctx.rush_read.carrier_peer)
	var gapping_up: bool = AIRoleRushD.should_gap_up(
			ctx, ctx.rush_read, ap, cushion)
	# The pace knob widens every stand, the gap-up's included.
	var gap: float = ctx.pursuit_standoff_m
	if gapping_up:
		gap += AIRoleRushD.GAP_MIN_STICKS * AIRoleRushD.stick_m(ctx)
	else:
		gap += AIRoleRushD.ladder_gap_m(
				carrier_pos, ctx.own_goal_dir, ctx.self_blade_reach, cushion)
	# The stand is angled (AIDefensiveVerbs.carrier_stand), as BACK_STRONG's is.
	var inside_dir := Vector3.ZERO
	var inside_shade: float = 0.0
	var search_center: Vector3 = carrier_pos
	if ap.dir_net != Vector3.ZERO:
		search_center = AIDefensiveVerbs.carrier_stand(ap, gap)
		inside_dir = AIDefensiveVerbs.inside_dir(carrier_pos, ap.dir_net)
		inside_shade = AIDefensiveVerbs.inside_shade_m(carrier_pos)
	# The lead is used only by the pass-lane stand below — where a feed would be
	# thrown from, not how close to stand.
	var lead: Vector3 = carrier_pos \
			+ carrier_velocity * AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S

	# Last man: take the cut-off set, never lunge into it — an ICE-FRAME bound,
	# so a loose puck only. Never apply it to a live carrier: it would name a
	# stand wherever the body already is, and a pressurer walked toward his own
	# net could never close. The gap-up is exempt, as BACK_STRONG's is.
	var min_depth: float = -INF
	var depth_dir: Vector3 = Vector3.ZERO
	if not gapping_up and AIRoleReads.stand_ride_velocity(ctx) == Vector3.ZERO \
			and not AILastManDiscipline.has_support_behind(ctx):
		if ap.dir_net != Vector3.ZERO:
			var net_dir: Vector3 = ap.dir_net
			var want: float = (search_center.x - carrier_pos.x) * net_dir.x \
					+ (search_center.z - carrier_pos.z) * net_dir.z
			var settable: float = AILastManDiscipline.settable_stand_depth(
					ctx, carrier_pos, net_dir, want, closing_now)
			if settable > want:
				# Re-centre the ring on the settable line so the argmax still picks
				# the angle; the ring spans ±SEARCH_STEP_M, so depth is also
				# filtered per candidate below.
				search_center += net_dir * (settable - want)
				min_depth = settable
				depth_dir = net_dir

	# Upper bounds for carrier_best_option's early-out, and the data the
	# calculated closing stands are built from.
	var poss: AIPossessionValue = AIRoleReads.defence_possession(ctx,
			our_team_excluding_self)
	var bases: Array[float] = ctx.scratch_option_bases
	AIDefensiveVerbs.carrier_option_bases(poss, carrier_pos, carrier_velocity,
			our_goalie_pos, opp_teammates, bases)

	# ENGAGED: the full ring with half-step samples, for small live corrections.
	# CLOSING (the common case): the ring's ±SEARCH_STEP_M refinements are
	# invisible at full stride, so score only the computable stands — the shot-line
	# cut-off, the stand-off on the carrier's best pass lane, and their midpoint.
	var near_cutoff: bool = ctx.self_pos.distance_squared_to(search_center) \
			< PRESSURE_INNER_RING_RANGE_M * PRESSURE_INNER_RING_RANGE_M
	var candidates: Array[Vector3] = []
	if near_cutoff:
		candidates = AIStationSearch.generate_candidates_around(
				ctx.self_pos, search_center, true)
	else:
		candidates.append(search_center)
		var worst_pass: int = -1
		for i: int in range(1, bases.size()):
			if worst_pass == -1 or bases[i] > bases[worst_pass]:
				worst_pass = i
		if worst_pass != -1 and bases[worst_pass] > 0.0:
			var lane: Vector3 = opp_teammates[worst_pass - 1] - lead
			var lane_len: float = sqrt(lane.x * lane.x + lane.z * lane.z)
			if lane_len > 0.001:
				var pass_stand: Vector3 = lead + lane * (
						(AIBotMechanics.BLADE_REACH_M
								+ ctx.pursuit_standoff_m) / lane_len)
				candidates.append(pass_stand)
				candidates.append((search_center + pass_stand) * 0.5)
	# Switch-hysteresis: "block the shot" and "block the best pass" are often
	# near-equal, and trading them every dispatch covers neither.
	AIStationSearch.append_incumbent(ctx, candidates)

	var ride: Vector3 = AIRoleReads.stand_ride_velocity(ctx)
	var best_pos: Vector3 = ctx.self_pos
	var best_score: float = -INF
	var found: bool = false
	# The ladder is a FLOOR on the gap: the score improves monotonically as you
	# close, so a free argmax collapses onto him.
	var min_gap_sq: float = gap * gap
	for raw: Vector3 in candidates:
		# A clamp, not a filter: filtering empties the set exactly when the ring
		# has closed onto the man. The distance is doctrine; the argmax picks the
		# bearing.
		var c: Vector3 = raw
		var gx: float = raw.x - carrier_pos.x
		var gz: float = raw.z - carrier_pos.z
		var gd_sq: float = gx * gx + gz * gz
		if gd_sq < min_gap_sq:
			if gd_sq > 0.0001:
				var k: float = gap / sqrt(gd_sq)
				c = Vector3(carrier_pos.x + gx * k, 0.0, carrier_pos.z + gz * k)
			elif ap.dir_net != Vector3.ZERO:
				c = carrier_pos + ap.dir_net * gap
		# The shade is a floor too: re-centring by at most ANGLE_INSIDE_M is
		# invisible to a ±SEARCH_STEP_M ring, which could pick the outside sample.
		# Nudged, not rejected, so the set never empties.
		if inside_shade > 0.001:
			var off: float = (c.x - carrier_pos.x) * inside_dir.x \
					+ (c.z - carrier_pos.z) * inside_dir.z
			if off < inside_shade:
				c += inside_dir * (inside_shade - off)
		if not AIStationSearch.is_legal_position(c):
			continue
		if not _is_goal_side(c, carrier_pos, our_net):
			continue
		if min_depth > -INF and (c.x - carrier_pos.x) * depth_dir.x \
				+ (c.z - carrier_pos.z) * depth_dir.z < min_depth - 0.01:
			continue  # up-ice of the settable stand — a lunge (see above)
		if AIStationSearch.too_close_to_teammate(c, our_team_excluding_self):
			continue

		# Higher = better for us, i.e. lower for the carrier.
		var pressure_score: float = -AIDefensiveVerbs.carrier_best_option(
				poss, c, ride, ctx.caps_by_peer.get(ctx.peer_id), carrier_pos,
				carrier_velocity, our_goalie_pos, opp_teammates, bases) \
				+ AIStationSearch.incumbent_bonus(ctx, c)
		if pressure_score > best_score:
			best_score = pressure_score
			best_pos = c
			found = true

	d.target_position = best_pos
	# Unlike BACK_STRONG, the arrival brake stays ON while gapping up: a carrier
	# gapped up on isn't coming at pace, so braking onto the stand settles on him
	# instead of orbiting him.
	#
	# Publish the ride only when a candidate survived: otherwise `best_pos` is our
	# own feet, a HOLD, and a hold that rides a man matches his velocity forever.
	# The argmax picks the bearing; the route is BACK_STRONG's, so the D who owned the
	# rush skates it the same way after the line. A forecheck (the carrier in
	# his own zone) has no retreat to manage, so its route stays free.
	if found:
		d.target_velocity = ride
		var retreating: bool = ap.dir_net != Vector3.ZERO \
				and not AIActionScoring.in_offensive_zone(carrier_pos, ctx.attacking_goal_pos)
		if retreating and d.target_velocity != Vector3.ZERO:
			AIRoleRushD.set_retreat_facing(ctx, ap, d, gapping_up, best_pos)
			d.target_position = AIRoleRushD.depth_first(ctx, ap, best_pos, d)
		AIRoleRushD.set_retreat_floor(ctx, ap, d)
		if retreating:
			AIRoleRushD.set_advance_cap(ctx, ap, d, gap)
		# The gap we just sized is ours to hold (RoleDecision.engaged_peer_id).
		if ctx.snapshot != null and ctx.snapshot.puck_state != null:
			var pid: int = ctx.snapshot.puck_state.carrier_peer_id
			if pid != -1 and ctx.team_id_by_peer.get(pid, -1) != ctx.team_id:
				d.engaged_peer_id = pid
	return d


# True if `c` is on our net's side of the carrier — never lose inside position.
static func _is_goal_side(c: Vector3, carrier_pos: Vector3,
		our_net: Vector3) -> bool:
	var to_net: Vector3 = our_net - carrier_pos
	if to_net.length_squared() < 0.001:
		return true
	var to_c: Vector3 = c - carrier_pos
	return to_net.x * to_c.x + to_net.z * to_c.z > 0.0
