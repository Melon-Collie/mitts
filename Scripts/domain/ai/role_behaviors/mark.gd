class_name AIRoleMark

# MARK — the off-puck man-marker: 3v3 DZONE's two defenders not on the puck, and
# the 5v5 election's spare body outside our possession. Pick up a MAN, not a
# patch of ice; which man (and so net-front vs. weak side) is the threat
# partition's call (AIThreatAssignment), one marker per man.
#
# Fallback (no man assigned — more markers than receivers, a loose puck, no
# brain): recover to the most dangerous ice, argmaxing
#
#     -max over opps of AIPossessionValue.threat_of_carrier(opp)
#
# against our team with us at the candidate.


static func decide(ctx: RoleContext) -> RoleDecision:
	var d := RoleDecision.new()

	if AIDefensiveVerbs.cover_threat(ctx, d, ctx.assigned_threat_peer,
			AIRoleReads.resolve_defensive_play_ref(ctx)):
		d.locked_man_pid = ctx.assigned_threat_peer
		return d

	var opp_positions: Array[Vector3] = ctx.scratch_opp_positions
	var opp_states: Array[SkaterNetworkState] = ctx.scratch_opp_states
	AIRoleReads.collect_opponents(ctx, opp_positions, opp_states, true)
	if opp_positions.is_empty():
		d.target_position = ctx.self_pos
		return d

	var our_net: Vector3 = ctx.defending_goal_pos
	var our_goalie_pos: Vector3 = AIRoleReads.resolve_our_goalie_pos(ctx)
	var our_team_excluding_self: Array[Vector3] = ctx.scratch_teammates
	AIRoleReads.collect_teammates_excluding_self(ctx, our_team_excluding_self)
	var poss: AIPossessionValue = AIRoleReads.defence_possession(ctx,
			our_team_excluding_self)

	# The puck/net midpoint: toward our blue line with the puck out, the slot with
	# it deep — no per-state branch. The slot when there is no puck state.
	var search_center: Vector3
	if ctx.snapshot != null and ctx.snapshot.puck_state != null:
		search_center = (ctx.snapshot.puck_state.position + our_net) * 0.5
	else:
		search_center = Vector3(
				0.0,
				0.0,
				our_net.z - ctx.own_goal_dir * GameRules.SLOT_DIST_M)
	# Per-opp threat upper bounds for _max_shot_threat's early-out (see
	# AIDefensiveVerbs.carrier_option_bases). TeamBrain's memo supplies them when it
	# published: APPROXIMATE (full-team defender set, raw positions, up to a brain
	# tick stale), the accepted price of not paying these per marker. An empty
	# memo computes exactly.
	# Every man is weighed in the currency of where their play is.
	var play_ref: Vector3 = AIRoleReads.resolve_defensive_play_ref(ctx)
	var objective: int = poss.objective_at(
			play_ref if play_ref.is_finite() else search_center, our_goalie_pos)
	var memo: Dictionary[int, float] = ctx.threat_shoot_base_by_opp
	var opp_ids: Array[int] = ctx.scratch_opp_ids
	var bases: Array[float] = ctx.scratch_option_bases
	bases.clear()
	for i: int in opp_positions.size():
		var base: float = memo.get(opp_ids[i], -1.0) if not memo.is_empty() else -1.0
		if base < 0.0:
			base = poss.threat_of_carrier(opp_positions[i], opp_states[i].velocity,
					our_goalie_pos, objective)
		bases.append(base)

	# Far from the recovery region, skate at the cover anchor on the biggest base
	# threat (STATION_ARGMAX_LOD_M).
	if not AIStationSearch.station_needs_refinement(ctx.self_pos, search_center):
		var worst: int = 0
		for i: int in bases.size():
			if bases[i] > bases[worst]:
				worst = i
		d.target_position = AIThreatAssignment.cover_anchor(
				opp_positions[worst], our_net)
		return d

	var candidates: Array[Vector3] = AIStationSearch.generate_candidates_around(
			ctx.self_pos, search_center)
	AIStationSearch.append_incumbent(ctx, candidates)

	var best_pos: Vector3 = ctx.self_pos
	var best_score: float = -INF
	for c: Vector3 in candidates:
		if not AIStationSearch.is_legal_position(c):
			continue
		if AIStationSearch.too_close_to_teammate(c, our_team_excluding_self):
			continue

		var mark_score: float = -_max_threat(poss, c, ctx.caps_by_peer.get(ctx.peer_id),
				opp_positions, opp_states, our_goalie_pos, bases, objective) \
				+ AIStationSearch.incumbent_bonus(ctx, c)
		if mark_score > best_score:
			best_score = mark_score
			best_pos = c

	d.target_position = best_pos
	return d


# The highest threat any opp carries (AIPossessionValue.threat_of_carrier in
# `objective`'s currency) with our defender at `candidate`. On the possession scale, so a gradient survives
# where no opp is in shooting range. `bases` (per-opp threats without the
# candidate, in opp_positions order) bound each term from above, so terms
# evaluate in descending-bound order and stop early — an exact prune.
static func _max_threat(poss: AIPossessionValue, candidate: Vector3,
		self_caps: AISkaterCaps, opp_positions: Array[Vector3],
		opp_states: Array[SkaterNetworkState], our_goalie_pos: Vector3,
		bases: Array[float], objective: int) -> float:
	poss.push_defender(candidate, Vector3.ZERO, self_caps)
	var max_threat: float = 0.0
	var used: int = 0
	while true:
		var bi: int = -1
		var bound: float = -1.0
		for i: int in bases.size():
			if used & (1 << i) == 0 and bases[i] > bound:
				bound = bases[i]
				bi = i
		if bi == -1 or bound <= max_threat:
			break
		used |= 1 << bi
		max_threat = maxf(max_threat, poss.threat_of_carrier(opp_positions[bi],
				opp_states[bi].velocity, our_goalie_pos, objective))
	poss.pop_defender()
	return max_threat
