class_name AIRoleHighSlot

# HIGH_SLOT (5v5 OZONE) — the third forward, F3: floats the high slot ABOVE the
# puck as the seam / one-timer option and the first man back. Design:
# docs/5v5-ai-plan.md §2 and the appendix's F3 rules.
#
# A small argmax over the band, scoring the one-timer look (feed lane × shot
# lane), with above-the-puck as a hard filter and the shared station read
# (offensive_station_target) bounding the result.

# The float band: depths off the attacked goal line and lateral samples
# (weak-side shaded — the seam is usually back across the grain).
const BAND_DEPTHS_M: Array[float] = [8.0, 9.5, 11.0]
const BAND_LATERAL_M: Array[float] = [-3.0, -1.5, 0.0, 1.5, 3.0]
# Stay this far above (own-goal-side of) the puck.
const ABOVE_PUCK_MARGIN_M: float = 1.0


static func decide(ctx: RoleContext) -> RoleDecision:
	# "D pinches, F3 fills".
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

	var opp_positions: Array[Vector3] = ctx.scratch_opp_positions
	var opp_states: Array[SkaterNetworkState] = ctx.scratch_opp_states
	AIRoleReads.collect_opponents(ctx, opp_positions, opp_states)
	var teammates: Array[Vector3] = ctx.scratch_teammates
	AIRoleReads.collect_teammates_excluding_self(ctx, teammates)

	# Far from the band, skate at the calculated float spot (STATION_ARGMAX_LOD_M),
	# still through the station read.
	var band_center := Vector3(
			0.0, 0.0, opp_net.z + own_dir * BAND_DEPTHS_M[1])
	if not AIStationSearch.station_needs_refinement(ctx.self_pos, band_center):
		d.target_position = AILastManDiscipline.offensive_station_target(
				ctx, band_center, ctx.prev_held_forward_stand)
		d.held_forward_stand = d.target_position.distance_to(band_center) < 0.5
		return d

	AIRoleReads.collect_feed_defence(ctx)
	var origin: Vector3 = AIRoleReads.feed_origin(ctx, carrier_pos)
	var best_pos: Vector3 = ctx.self_pos
	var best_score: float = -INF
	for depth: float in BAND_DEPTHS_M:
		var z: float = opp_net.z + own_dir * depth
		for x: float in BAND_LATERAL_M:
			var c := Vector3(x, 0.0, z)
			if own_dir * c.z < own_dir * carrier_pos.z + ABOVE_PUCK_MARGIN_M:
				continue
			if not AIStationSearch.is_legal_position(c):
				continue
			if AIStationSearch.too_close_to_teammate(c, teammates):
				continue
			# The seam look: can the carrier feed me here, and can I shoot from here?
			# The feed is read only where the shot lets the spot win (exact: ≤ 1).
			var shot: float = AIPuckLane.lane_clear(
					c, opp_net, opp_positions, ctx.self_wrister_shot_speed,
					AIActionScoring.EMPTY_VEC3, ctx.scratch_opp_caps)
			var bonus: float = AIStationSearch.incumbent_bonus(ctx, c)
			if shot + bonus <= best_score:
				continue
			var score: float = AIRoleReads.feed_lane(ctx, origin, c,
					AIRoleReads.feed_speed(ctx, origin, c)) * shot + bonus
			if score > best_score:
				best_score = score
				best_pos = c
	if best_score == -INF:
		# Whole band filtered (carrier above it, or crowded): 1 m inside the
		# opp blue line.
		best_pos = Vector3(0.0, 0.0,
				opp_net.z + own_dir * (GameRules.GOAL_LINE_Z - GameRules.BLUE_LINE_Z - 1.0))
	d.target_position = AILastManDiscipline.offensive_station_target(
			ctx, best_pos, ctx.prev_held_forward_stand)
	d.held_forward_stand = d.target_position.distance_to(best_pos) < 0.5
	return d
