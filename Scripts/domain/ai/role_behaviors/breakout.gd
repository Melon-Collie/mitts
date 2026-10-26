class_name AIRoleBreakout

# The breakout outlets (BREAKOUT: we have the puck in our own zone).
#
#   strong (BREAKOUT_STRONG, both team sizes) — the up-the-wall outlet: samples
#     the strong-side boards from just ahead of the carrier to our blue line
#     and takes the highest spot whose lane is still clean.
#   weak (3v3 BREAKOUT_WEAK, 5v5 BREAKOUT_D2) — the reverse valve: the weak
#     side, held goal-side of the carrier so a reverse is always on and the
#     carrier is never the last man back.
#
# Both argmax the feed to c as the carrier prices it (AIFeedStationPick): our
# possession of c (AIPossessionValue, him there when the pass arrives, moving as
# he is) over the carrier's own lane read (AIRoleReads.feed_lane), less theirs
# where it is picked off, so the outlet stands where his lane really is clean.
# The possession read rewards up-ice progress and, unlike score_pass, stays
# non-zero deep in our zone.

# Lateral inset from the boards for the strong-side wall: a shoulder of air, no
# more. The STRONG outlet is the rim receiver, so the boards line must stay
# inside his ~1.4 m comfortable blade span.
const WALL_INSET_M: float = 1.2

# STRONG wall sampling: samples from STRONG_MIN_LEAD_M up-ice of the carrier to
# our blue line.
const STRONG_WALL_SAMPLES: int = 5
const STRONG_MIN_LEAD_M: float = 3.0

# STRONG's second column: a mid-seam lane at this fraction of the wall offset,
# so the outlet has a move when the wall lane dies. In 5v5 STRONG is a WALL POST
# (docs/breakout-plan.md, Phase C) and gets the column only when the carrier's
# own route occupies the wall lane; 3v3's rover always has it.
const MID_SEAM_FRACTION: float = 0.5
# "The carrier owns the wall lane": within the wall inset plus a body of
# the boards on the outlet's side.
const WALL_LANE_BAND_M: float = 3.0



# `is_strong` selects the strong-side-wall outlet (true) vs the
# weak-side reverse valve (false).
static func decide(ctx: RoleContext, is_strong: bool) -> RoleDecision:
	var d := RoleDecision.new()

	var carrier_pos: Vector3 = AIRoleReads.resolve_offensive_play_ref(ctx)
	if not carrier_pos.is_finite():
		d.target_position = ctx.self_pos
		return d

	var opp_positions: Array[Vector3] = ctx.scratch_opp_positions
	var opp_states: Array[SkaterNetworkState] = ctx.scratch_opp_states
	AIRoleReads.collect_opponents(ctx, opp_positions, opp_states)
	var teammate_positions: Array[Vector3] = ctx.scratch_teammates
	AIRoleReads.collect_teammates_excluding_self(ctx, teammate_positions)

	var side_x: float = ctx.strong_x if is_strong else -ctx.strong_x

	var candidates: Array[Vector3]
	if is_strong:
		candidates = _strong_wall_candidates(ctx, carrier_pos, side_x)
	else:
		var search_center: Vector3 = _weak_search_center(carrier_pos, side_x)
		candidates = AIStationSearch.generate_candidates_around(ctx.self_pos, search_center)
	AIStationSearch.append_incumbent(ctx, candidates)

	var possession: AIPossessionValue = AIRoleReads.attack_possession(ctx,
			opp_positions)
	var theirs: AIPossessionValue = AIRoleReads.defence_possession(ctx, teammate_positions)
	AIRoleReads.collect_feed_defence(ctx)
	var origin: Vector3 = AIRoleReads.feed_origin(ctx, carrier_pos)
	var pick: AIFeedStationPick = ctx.scratch_feed_pick
	pick.reset()
	for c: Vector3 in candidates:
		if not AIStationSearch.is_legal_position(c):
			continue
		if AIStationSearch.too_close_to_teammate(c, teammate_positions):
			continue
		# No offside filter: no candidate here reaches the opp blue line.
		if not is_strong and not AIRoleSupport.is_goal_side_of_carrier(
				c, carrier_pos, ctx.own_goal_dir):
			continue
		var pass_speed: float = AIRoleReads.feed_speed(ctx, origin, c)
		var held: float = possession.at(c, origin.distance_to(c) / pass_speed,
				ctx.self_velocity, ctx.caps_by_peer.get(ctx.peer_id))
		pick.offer(ctx, origin, c, pass_speed, held, AIStationSearch.incumbent_bonus(ctx, c),
				theirs)

	d.target_position = pick.best(ctx.self_pos)
	return d


# STRONG candidate set: depth samples from just ahead of the carrier to our blue
# line, in one or two columns (the wall, and the mid-seam when it is generated),
# plus self_pos as a stand-still fallback.
static func _strong_wall_candidates(ctx: RoleContext, carrier_pos: Vector3,
		side_x: float) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var wall_x: float = side_x * (GameRules.RINK_HALF_WIDTH - WALL_INSET_M)
	var mid_x: float = wall_x * MID_SEAM_FRACTION
	var own_dir: float = ctx.own_goal_dir
	# own_dir * z grows toward our net; up-ice is SMALLER.
	var carrier_depth: float = own_dir * carrier_pos.z
	var blue_depth: float = GameRules.BLUE_LINE_Z
	# maxf: a carrier already near the line collapses the samples onto it.
	var bottom_depth: float = maxf(carrier_depth - STRONG_MIN_LEAD_M, blue_depth)
	var top_depth: float = blue_depth
	# The 5v5 wall post yields its lane only to the carrier's own route.
	var carrier_on_wall: bool = signf(carrier_pos.x) == signf(side_x) \
			and GameRules.RINK_HALF_WIDTH - absf(carrier_pos.x) < WALL_LANE_BAND_M
	var wall_only: bool = ctx.team_size >= 5 and not carrier_on_wall
	for i: int in STRONG_WALL_SAMPLES:
		var t: float = 0.0
		if STRONG_WALL_SAMPLES > 1:
			t = float(i) / float(STRONG_WALL_SAMPLES - 1)
		var depth: float = lerpf(bottom_depth, top_depth, t)
		result.append(Vector3(wall_x, 0.0, own_dir * depth))
		if not wall_only:
			result.append(Vector3(mid_x, 0.0, own_dir * depth))
	result.append(ctx.self_pos)
	return result


# WEAK search center: the weak-side wall, level with the carrier.
static func _weak_search_center(carrier_pos: Vector3, side_x: float) -> Vector3:
	var wall_x: float = side_x * (GameRules.RINK_HALF_WIDTH - WALL_INSET_M)
	return Vector3(wall_x, 0.0, carrier_pos.z)
