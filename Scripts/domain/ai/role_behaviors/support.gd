class_name AIRoleSupport

# SUPPORT (3v3 OZONE / TRANS_OFFENSE), TRAILER (5v5 TRANS_OFFENSE), the 5v5
# spare body while we possess, and a just-released passer still slotted CARRIER.
# Be a pass option AND recoverable: in the OZ the third man high (point outlet,
# first man back); in transition, the goal-side trail.
#
# Argmax over `score_pass(carrier, c) − counter_rush_cost(c)`: the threat a
# turnover at the carrier generates, surviving only the bodies — this one,
# racing back from `c`, included — that beat the counter home, weighted by the
# carrier's live turnover probability.

# Polar sampling radius around the carrier in transition (a sampling parameter).
const SEARCH_RADIUS_M: float = 5.0

# The third man's OZ station, this far inside the attacking blue line: near
# enough to keep pucks in and be first back, inside enough to stay onside.
const HIGH_POST_INSET_M: float = 3.0

# Safety-valve slack, about one stick: SUPPORT stays goal-side of the carrier
# (roughly even at most) so he is never the last man back. A hard filter, since
# the pass term alone pulls SUPPORT past him on a clean breakout.
const GOAL_SIDE_TOLERANCE_M: float = 1.5

# Covering-set exposure scratch, refilled once per decide.
static var _scratch_opp_vels: Array[Vector3] = []
static var _scratch_mate_etas: Array[float] = []
static var _scratch_threat_by_cover: Array[float] = []


static func decide(ctx: RoleContext) -> RoleDecision:
	var d := RoleDecision.new()

	var carrier_pos: Vector3 = AIRoleHelpers.resolve_offensive_play_ref(ctx)
	if not carrier_pos.is_finite():
		d.target_position = ctx.self_pos
		return d

	var our_net: Vector3 = ctx.defending_goal_pos
	var goalie_pos: Vector3 = AIRoleHelpers.resolve_opp_goalie_pos(ctx)

	var opp_positions: Array[Vector3] = ctx.scratch_opp_positions
	var opp_states: Array[SkaterNetworkState] = ctx.scratch_opp_states
	AIRoleHelpers.collect_opponents(ctx, opp_positions, opp_states)

	var teammate_positions: Array[Vector3] = ctx.scratch_teammates
	AIRoleHelpers.collect_teammates_excluding_self(ctx, teammate_positions)

	# Candidate-invariant exposure inputs; an unpressured carrier gives prior 0
	# and the cost short-circuits.
	_scratch_opp_vels.clear()
	for s: SkaterNetworkState in opp_states:
		_scratch_opp_vels.append(s.velocity)
	var turnover_prior: float = 0.0
	if not opp_positions.is_empty():
		turnover_prior = 1.0 - AICarrySpace.carry_safety(
				carrier_pos, carrier_pos, AICarrySpace.EVADE_HORIZON_S,
				opp_positions, _scratch_opp_vels, ctx.scratch_opp_caps)
	AIActionScoring.fill_counter_cover_etas(
			our_net, teammate_positions, _scratch_mate_etas)
	_scratch_threat_by_cover.clear()
	for _i: int in teammate_positions.size() + 2:
		_scratch_threat_by_cover.append(-1.0)
	var our_goalie: Vector3 = AIRoleHelpers.resolve_our_goalie_pos(ctx)

	# Far from the station, skate at the calculated post (STATION_ARGMAX_LOD_M).
	# In transit it is the goal-side trail a step behind the carrier.
	var station: Vector3
	if AIActionScoring.in_offensive_zone(carrier_pos, ctx.attacking_goal_pos):
		station = Vector3(
				carrier_pos.x * 0.5, 0.0,
				-ctx.own_goal_dir * GameRules.BLUE_LINE_Z
						- ctx.own_goal_dir * HIGH_POST_INSET_M)
	else:
		station = carrier_pos + Vector3(
				0.0, 0.0, ctx.own_goal_dir * AIRoleHelpers.SEARCH_STEP_M)
	if not AIRoleHelpers.station_needs_refinement(ctx.self_pos, station):
		return _hold_or_restore_numbers(ctx, d, station)

	var candidates: Array[Vector3] = _generate_candidates(ctx, carrier_pos)
	AIRoleHelpers.append_incumbent(ctx, candidates)

	var best_pos: Vector3 = ctx.self_pos
	var best_score: float = -INF
	for c: Vector3 in candidates:
		if not AIRoleHelpers.is_legal_position(c):
			continue
		if AIRoleHelpers.too_close_to_teammate(c, teammate_positions):
			continue
		if not _is_goal_side_of_carrier(c, carrier_pos, ctx.own_goal_dir):
			continue
		var pass_speed: float = AIActionScoring.expected_pass_speed(carrier_pos, c)
		# Pre-armed feed keeper (GoalieBehaviorRules.backdoor_depth_cap).
		var cand_flight: float = carrier_pos.distance_to(c) / maxf(pass_speed, 1.0)
		AIActionScoring.resolve_feed_keeper(
				goalie_pos, ctx.attacking_goal_pos, cand_flight, c, carrier_pos,
				AIRoleHelpers.opp_goalie_hands(ctx), pass_speed, opp_positions)
		var pass_value: float = AIActionScoring.score_pass(
				carrier_pos, c, ctx.attacking_goal_pos,
				AIActionScoring.feed_keeper_pos, GameRules.NET_HALF_WIDTH,
				opp_positions, pass_speed, AIActionScoring.feed_keeper_unsettled,
				-1.0, AIActionScoring.feed_keeper_hands, Vector4.INF,
				ctx.scratch_opp_caps)
		var counter_cost: float = AIActionScoring.counter_rush_cost(
				carrier_pos, turnover_prior, our_net, our_goalie,
				GameRules.NET_HALF_WIDTH, teammate_positions, c,
				ctx.self_max_speed, opp_positions, _scratch_opp_vels,
				ctx.scratch_opp_caps, _scratch_mate_etas, _scratch_threat_by_cover)
		var score: float = pass_value - counter_cost + AIRoleHelpers.incumbent_bonus(ctx, c)
		if score > best_score:
			best_score = score
			best_pos = c

	return _hold_or_restore_numbers(ctx, d, best_pos)


# In the OZ the help player counts numbers like every other last layer
# (may_hold_forward_stand). The counter cost prices a loss AT the carrier and
# cannot see a man already leaving the zone.
static func _hold_or_restore_numbers(ctx: RoleContext, d: RoleDecision,
		stand: Vector3) -> RoleDecision:
	d.target_position = stand
	if AIActionScoring.in_offensive_zone(stand, ctx.attacking_goal_pos) \
			and not AIRoleHelpers.may_hold_forward_stand(
					ctx, ctx.prev_held_forward_stand, stand):
		d.target_position = AIRoleHelpers.numbers_floor(ctx, stand)
	d.held_forward_stand = d.target_position.distance_to(stand) < 0.5
	return d


# True when `c` is no further toward the opp net than the carrier, within
# GOAL_SIDE_TOLERANCE_M (own_goal_dir * z grows toward our net).
static func _is_goal_side_of_carrier(c: Vector3, carrier_pos: Vector3,
		own_goal_dir: float) -> bool:
	return own_goal_dir * c.z >= own_goal_dir * carrier_pos.z - GOAL_SIDE_TOLERANCE_M


# ── Candidate generation (in-game-ref) ──────────────────────────────────────

# Carrier in the offensive zone: the named third-man-high stations — an orbit
# around the carrier would never contain a high candidate. In transit:
# carrier-orbit samples, since the high post would be ahead of the play and the
# goal-side filter would reject it.
static func _generate_candidates(ctx: RoleContext, carrier_pos: Vector3) -> Array[Vector3]:
	var result: Array[Vector3] = []
	result.append(ctx.self_pos)
	if AIActionScoring.in_offensive_zone(carrier_pos, ctx.attacking_goal_pos):
		var blue_z: float = -ctx.own_goal_dir * GameRules.BLUE_LINE_Z
		var post_z: float = blue_z - ctx.own_goal_dir * HIGH_POST_INSET_M
		var wall_sign: float = signf(carrier_pos.x) if absf(carrier_pos.x) > 0.1 \
				else ctx.strong_x
		# HIGH POST — top of the zone, shaded to the carrier's side.
		var high_post := Vector3(carrier_pos.x * 0.5, 0.0, post_z)
		result.append(high_post)
		# HALF-WALL BUMP — between the high post and the carrier.
		result.append((high_post + carrier_pos) * 0.5)
		# CENTER POINT — the middle of the line.
		result.append(Vector3(0.0, 0.0, post_z))
		# WEAK FLANK — the far dot lane at the top of the circles.
		result.append(Vector3(
				-wall_sign * GameRules.END_ZONE_FACEOFF_DOT_X, 0.0,
				ctx.attacking_goal_pos.z + ctx.own_goal_dir
						* (GameRules.GOAL_LINE_Z - GameRules.ICING_FACEOFF_DOT_Z + 3.0)))
		return result
	result.append(carrier_pos)
	for angle: float in AIRoleHelpers.POLAR_ANGLES:
		result.append(Vector3(
				carrier_pos.x + SEARCH_RADIUS_M * cos(angle),
				0.0,
				carrier_pos.z + SEARCH_RADIUS_M * sin(angle)))
	return result


