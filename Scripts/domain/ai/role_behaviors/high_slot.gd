class_name AIRoleHighSlot

# HIGH_SLOT (5v5 OZONE) — the third forward, F3. Design: docs/5v5-ai-plan.md §2,
# and docs/bot-net-front-offense-plan.md step 1 (the shape is the value's).
#
# He rotates up to a point either D has left (AIRoleDefenseman.rotate_up_to_point).
# Otherwise he stands where the one-timer off the carrier's feed is worth most
# (score_pass_value, the finisher's currency): anywhere from the bumper to the
# circle tops and out to the weak flank, or down at the far post. Nothing holds
# him above the puck: the points are the back layer, and the shared station read
# (offensive_station_target) bounds the result.

# The search grid: depths off the attacked goal line and weak-signed lateral
# offsets (positive away from the puck's side — the seam is usually back across
# the grain). From the bumper to the top of the circles, the strong dot lane to
# the weak one.
const GRID_DEPTHS_M: Array[float] = [5.5, 7.5, 9.5, 11.0]
const GRID_WEAK_U_M: Array[float] = [-2.0, 0.0, 2.0, 4.0, 6.0]
# The far post a downhill F3 arrives at: a body-width outside it, clear of the
# crease (AIRoleFinisher's backdoor station).
const FAR_POST_OUT_M: float = 1.5
const FAR_POST_WIDE_M: float = GameRules.NET_HALF_WIDTH + 1.4
# Where he skates while still far from the grid: the middle of it.
const REST_DEPTH_M: float = 9.5


static func decide(ctx: RoleContext) -> RoleDecision:
	# "D activates, F3 fills": either point.
	var fill: RoleDecision = AIRoleDefenseman.rotate_up_to_point(
			ctx, AIRoleSlots.Slot.POINT_STRONG)
	if fill != null:
		return fill
	var d := RoleDecision.new()
	var own_dir: float = ctx.own_goal_dir
	var opp_net: Vector3 = ctx.attacking_goal_pos

	var carrier_pos: Vector3 = AIRoleReads.resolve_offensive_play_ref(ctx)
	if not carrier_pos.is_finite():
		d.target_position = ctx.self_pos
		return d

	# Far from the grid, skate at its middle (STATION_ARGMAX_LOD_M), still through
	# the station read.
	var rest := Vector3(0.0, 0.0, opp_net.z + own_dir * REST_DEPTH_M)
	if not AIStationSearch.station_needs_refinement(ctx.self_pos, rest):
		return _through_station_read(ctx, d, rest)

	var opp_positions: Array[Vector3] = ctx.scratch_opp_positions
	var opp_states: Array[SkaterNetworkState] = ctx.scratch_opp_states
	AIRoleReads.collect_opponents(ctx, opp_positions, opp_states)
	var teammates: Array[Vector3] = ctx.scratch_teammates
	AIRoleReads.collect_teammates_excluding_self(ctx, teammates)
	var goalie_pos: Vector3 = AIRoleReads.resolve_opp_goalie_pos(ctx)
	AIStationSearch.fill_feed_values(ctx, carrier_pos, goalie_pos, opp_positions, teammates)

	var weak: float = -ctx.strong_x
	var best_pos: Vector3 = Vector3.INF
	var best_score: float = -INF
	for depth: float in GRID_DEPTHS_M:
		for u: float in GRID_WEAK_U_M:
			var c := Vector3(weak * u, 0.0, opp_net.z + own_dir * depth)
			var s: float = _score(ctx, c, carrier_pos, goalie_pos, opp_positions, teammates)
			if s > best_score:
				best_score = s
				best_pos = c
	var far_post := Vector3(weak * FAR_POST_WIDE_M, 0.0, opp_net.z + own_dir * FAR_POST_OUT_M)
	var s_post: float = _score(ctx, far_post, carrier_pos, goalie_pos, opp_positions,
			teammates)
	if s_post > best_score:
		best_score = s_post
		best_pos = far_post
	if ctx.prev_role_target.is_finite():
		var s_prev: float = _score(ctx, ctx.prev_role_target, carrier_pos, goalie_pos,
				opp_positions, teammates)
		if s_prev > best_score:
			best_score = s_prev
			best_pos = ctx.prev_role_target
	if not best_pos.is_finite():
		best_pos = rest
	return _through_station_read(ctx, d, best_pos)


# What `c` adds: the one-timer off the carrier's feed there, less what a
# teammate a defender could cover with it already offers
# (AIStationSearch.shared_cover), plus the switch hysteresis; -INF where nobody
# may stand.
static func _score(ctx: RoleContext, c: Vector3, carrier_pos: Vector3,
		goalie_pos: Vector3, opp_positions: Array[Vector3],
		teammates: Array[Vector3]) -> float:
	if not AIStationSearch.is_legal_position(c):
		return -INF
	if AIStationSearch.too_close_to_teammate(c, teammates):
		return -INF
	if AIRoleReads.xz_distance(c, carrier_pos) < AIStationSearch.ANTI_CROWD_RADIUS_M:
		return -INF
	var feed: float = AIActionScoring.score_pass_value(
			carrier_pos, c, ctx.attacking_goal_pos, goalie_pos, opp_positions,
			AIPuckLane.expected_pass_speed(carrier_pos, c), ctx.scratch_opp_caps, true)
	return feed - AIStationSearch.shared_cover(c, teammates) \
			+ AIStationSearch.incumbent_bonus(ctx, c)


static func _through_station_read(ctx: RoleContext, d: RoleDecision,
		stand: Vector3) -> RoleDecision:
	d.target_position = AILastManDiscipline.offensive_station_target(
			ctx, stand, ctx.prev_held_forward_stand)
	d.held_forward_stand = d.target_position.distance_to(stand) < 0.5
	return d
