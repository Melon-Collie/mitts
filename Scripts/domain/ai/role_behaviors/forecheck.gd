class_name AIRoleForecheck

# The off-puck forecheckers (FORECHECK: their puck in THEIR zone, and we can get
# on it — AIForecheckRead). F1 is AIRolePressure, dispatched directly.
#
#   F2_NET (both sizes) — reacts in front of their net: takes away the most
#     dangerous breakout PASS (inverse pass-threat scoring) from the slot, where
#     the reverse, the D-to-D behind the net and the net-front outlet run.
#   F3_HIGH (3v3) — high on the near wall at their line, the first man back:
#     holds the line only while the shared pinch read allows it.
#   F3_WALL (5v5) — support on the near wall at half-wall height: the same
#     argmax, which kills the half-wall outlet; fills the strong point while its
#     D pinches.
#
# Nobody is offside here: the puck is in their zone, so F1 and F2 press freely.

# How far off the strong-side boards 3v3's F3 holds at the blue line, so it can
# step to either breakout lane.
const F3_HIGH_WALL_INSET_M: float = 4.0

# F2's read in front of their net: the search centre this far off their goal
# line (the slot), shaded toward the carrier's side, inside the slot corridor.
const F2_NET_DEPTH_OFF_GOAL_M: float = 6.0
const F2_NET_PUCK_SHADE: float = 0.3
const F2_NET_HALF_WIDTH_M: float = AIZoneCoverage.SLOT_HALF_WIDTH_M

# 5v5's F3 on the near wall at half-wall height: the search centre.
const F3_WALL_INSET_M: float = 4.0
const F3_WALL_DEPTH_OFF_GOAL_M: float = 12.0


# ── F2: the read in front of their net ───────────────────────────────────────
static func decide_net(ctx: RoleContext) -> RoleDecision:
	var carrier_pos: Vector3 = AIRoleReads.resolve_defensive_play_ref(ctx)
	if not carrier_pos.is_finite():
		var d := RoleDecision.new()
		d.target_position = ctx.self_pos
		return d
	var center := Vector3(
			clampf(carrier_pos.x * F2_NET_PUCK_SHADE, -F2_NET_HALF_WIDTH_M,
					F2_NET_HALF_WIDTH_M),
			0.0,
			-ctx.own_goal_dir * (GameRules.GOAL_LINE_Z - F2_NET_DEPTH_OFF_GOAL_M))
	return _decide_read_at(ctx, carrier_pos, center)


# ── F3_WALL: support on the near wall ────────────────────────────────────────
static func decide_wall(ctx: RoleContext) -> RoleDecision:
	# The 1-2-2's high forward on the strong side is the one who fills when the
	# strong D pinches down his wall.
	var fill: RoleDecision = AIRoleDefenseman.rotate_up_to_point(
			ctx, AIRoleSlots.Slot.DP_STRONG)
	if fill != null:
		return fill
	var carrier_pos: Vector3 = AIRoleReads.resolve_defensive_play_ref(ctx)
	if not carrier_pos.is_finite():
		var d := RoleDecision.new()
		d.target_position = ctx.self_pos
		return d
	var center := Vector3(
			ctx.strong_x * (GameRules.RINK_HALF_WIDTH - F3_WALL_INSET_M),
			0.0,
			-ctx.own_goal_dir * (GameRules.GOAL_LINE_Z - F3_WALL_DEPTH_OFF_GOAL_M))
	return _decide_read_at(ctx, carrier_pos, center)


# ── F3_HIGH: high safety — hold the line only while the race home is winnable ─
static func decide_high(ctx: RoleContext) -> RoleDecision:
	var d := RoleDecision.new()
	var blue_z: float = -ctx.own_goal_dir * GameRules.BLUE_LINE_Z
	var wall_x: float = ctx.strong_x * (GameRules.RINK_HALF_WIDTH - F3_HIGH_WALL_INSET_M)

	# A rim keep-in is still the line, so the last man stays the last man.
	var keepin: Vector3 = AIRoleDefenseman.wall_rim_keepin(ctx, ctx.strong_x)
	if keepin.is_finite():
		d.target_position = keepin
		d.arrive_at_speed = true
		return d

	var line_stand := Vector3(wall_x, 0.0, blue_z)
	# F3_HIGH (3v3 only) IS the team's back layer, so he retreats to the
	# DEFENSEMAN's home post (as_back_layer).
	d.target_position = AILastManDiscipline.offensive_station_target(
			ctx, line_stand, ctx.prev_held_forward_stand, true)
	d.held_forward_stand = d.target_position.distance_to(line_stand) < 0.5
	return d


# The forecheck's second-layer argmax, F2's and F3_WALL's: minimize the carrier's
# best breakout feed (on PRESSURE's inverse pass-threat surface) around
# `search_center`.
static func _decide_read_at(ctx: RoleContext, carrier_pos: Vector3,
		search_center: Vector3) -> RoleDecision:
	var d := RoleDecision.new()

	var opp_teammates: Array[Vector3] = ctx.scratch_opp_receivers
	AIRoleReads.collect_opp_team_excluding_carrier(ctx, opp_teammates, true)
	if opp_teammates.is_empty():
		# No receivers to deny: sit at the read spot rather than freeze.
		d.target_position = search_center
		return d

	var our_goalie_pos: Vector3 = AIRoleReads.resolve_our_goalie_pos(ctx)
	var our_team_excluding_self: Array[Vector3] = ctx.scratch_teammates
	AIRoleReads.collect_teammates_excluding_self(ctx, our_team_excluding_self)
	var poss: AIPossessionValue = AIRoleReads.defence_possession(ctx,
			our_team_excluding_self)

	var candidates: Array[Vector3] = AIStationSearch.generate_candidates_around(
			ctx.self_pos, search_center)
	# Switch-hysteresis (the cursor snaps to this target).
	AIStationSearch.append_incumbent(ctx, candidates)

	# Per-receiver upper bounds for _max_pass_threat's early-out (see
	# AIDefensiveVerbs.carrier_option_bases).
	var bases: Array[float] = ctx.scratch_option_bases
	bases.clear()
	for opp_pos: Vector3 in opp_teammates:
		bases.append(poss.threat_of_feed(carrier_pos, opp_pos, Vector3.ZERO,
				our_goalie_pos))

	var best_pos: Vector3 = search_center
	var best_score: float = -INF
	for c: Vector3 in candidates:
		if not AIStationSearch.is_legal_position(c):
			continue
		# Stay IN the attacking zone: sagging out concedes the forecheck.
		if ctx.own_goal_dir * c.z > -GameRules.BLUE_LINE_Z:
			continue
		if AIStationSearch.too_close_to_teammate(c, our_team_excluding_self):
			continue
		var threat: float = _max_pass_threat(poss, c, ctx.caps_by_peer.get(ctx.peer_id),
				carrier_pos, opp_teammates, our_goalie_pos, bases)
		var score: float = -threat + AIStationSearch.incumbent_bonus(ctx, c)
		if score > best_score:
			best_score = score
			best_pos = c

	d.target_position = best_pos
	return d


# The biggest threat the carrier's feed to any teammate carries
# (AIPossessionValue.threat_of_feed; receivers led by anticipation, so read
# standing), with our defender at `candidate`. `bases` (per-receiver threats
# without the candidate, in opp_teammates order) bound each term from above, so
# terms evaluate in descending-bound order and stop early — an exact prune.
static func _max_pass_threat(poss: AIPossessionValue, candidate: Vector3,
		self_caps: AISkaterCaps, carrier_pos: Vector3, opp_teammates: Array[Vector3],
		our_goalie_pos: Vector3, bases: Array[float]) -> float:
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
		max_threat = maxf(max_threat, poss.threat_of_feed(carrier_pos,
				opp_teammates[bi], Vector3.ZERO, our_goalie_pos))
	poss.pop_defender()
	return max_threat
