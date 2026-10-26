class_name AIRoleOutlet

# OUTLET (3v3 TRANS_OFFENSE) and BREAKOUT_STRETCH (5v5 BREAKOUT) — the
# stretch-pass option waiting NZ-side of the opp blue line. It accepts being
# past the play; defensive responsibility falls to SUPPORT.
#
# Argmax over `max(lane_clear(carrier → c), BLOCKED_LANE_FLOOR) × our possession
# of c` (AIPossessionValue, him there when the pass arrives, moving as he is), as
# the BREAKOUT outlets do: this far from the opp goal a shot from the spot is ~0,
# so a score_pass argmax would read ~0 for every candidate and go blind to a
# defender on the spot or in the lane.

# How far NZ-side of the opp blue line the set-play search center sits, so most
# samples are onside; _is_offside is the actual guard.
const BLUE_LINE_BUFFER_M: float = 2.5

# Inset from the boards for the weak-side search center, so the ring doesn't
# land against the wall.
const WEAK_SIDE_INSET_M: float = 2.0

# ── In-stride rush entry ─────────────────────────────────────────────────────
# On a rush the staging depth is PACED to the carrier, so the OUTLET reaches the
# line as he crosses, moving — parked at the line it would start from zero
# exactly when the entry happens.

# How far ahead of the carrier's depth the OUTLET stages at full rush.
const RUSH_ENTRY_LEAD_M: float = 4.0

# Rush blend above which the OUTLET arrives at speed and the pace cap engages.
const ARRIVE_AT_SPEED_RUSH: float = 0.25

# Pace cap slack (m): on a rush, candidates further net-ward of the paced depth
# than this are rejected, or the possession read would drag the OUTLET up to park
# at the line.
const PACE_TOLERANCE_M: float = 1.0


static func decide(ctx: RoleContext) -> RoleDecision:
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

	var rush: float = clampf(
			(AIRoleReads.carrier_closing_speed(ctx) - AIRoleFinisher.RUSH_SPEED_LO_M_S)
					/ (AIRoleFinisher.RUSH_SPEED_HI_M_S - AIRoleFinisher.RUSH_SPEED_LO_M_S),
			0.0, 1.0)
	var rushing: bool = rush > ARRIVE_AT_SPEED_RUSH
	d.arrive_at_speed = rushing

	# Both the search-center Z and, on a rush, the pace cap below.
	var paced_z: float = _paced_depth_z(ctx, carrier_pos, rush)
	# The SIDE comes from the brain's hysteretic strong_x, never a raw
	# -carrier.x, which would flip the stretch spot as the carrier crosses centre
	# and cut this bot across the SUPPORT trailer's path.
	var weak_x: float = clampf(-ctx.strong_x * absf(carrier_pos.x),
			-GameRules.RINK_HALF_WIDTH + WEAK_SIDE_INSET_M,
			GameRules.RINK_HALF_WIDTH - WEAK_SIDE_INSET_M)
	var search_center := Vector3(weak_x, 0.0, paced_z)
	var candidates: Array[Vector3] = AIStationSearch.generate_candidates_around(
			ctx.self_pos, search_center)
	# Switch-hysteresis (the cursor snaps to this target).
	AIStationSearch.append_incumbent(ctx, candidates)

	var possession: AIPossessionValue = AIRoleReads.attack_possession(ctx,
			opp_positions)
	var best_pos: Vector3 = ctx.self_pos
	var best_score: float = -INF
	for c: Vector3 in candidates:
		if not AIStationSearch.is_legal_position(c):
			continue
		if _is_offside(c, ctx):
			continue
		# Pace cap: own_goal_dir * z is SMALLER net-ward.
		if rushing and ctx.own_goal_dir * c.z \
				< ctx.own_goal_dir * paced_z - PACE_TOLERANCE_M:
			continue
		if AIStationSearch.too_close_to_teammate(c, teammate_positions):
			continue
		# The speed our carrier would actually fire at — on a long pass, the
		# charged speed.
		var pass_speed: float = AIPuckLane.expected_pass_speed(carrier_pos, c)
		var lane: float = AIPuckLane.lane_clear(
				carrier_pos, c, opp_positions, pass_speed,
				AIActionScoring.EMPTY_VEC3, ctx.scratch_opp_caps)
		var held: float = possession.at(c, carrier_pos.distance_to(c) / pass_speed,
				ctx.self_velocity, ctx.caps_by_peer.get(ctx.peer_id))
		var score: float = maxf(lane, AIRoleBreakout.BLOCKED_LANE_FLOOR) * held \
				+ AIStationSearch.incumbent_bonus(ctx, c)
		if score > best_score:
			best_score = score
			best_pos = c

	d.target_position = best_pos
	return d


# Staging depth (Z), lerped by `rush` from BLUE_LINE_BUFFER_M NZ-side of the opp
# blue line (set play) to RUSH_ENTRY_LEAD_M ahead of the carrier (full rush),
# the lead capped at that same line so it never stages offside.
static func _paced_depth_z(ctx: RoleContext, carrier_pos: Vector3,
		rush: float) -> float:
	var line_z: float = -ctx.own_goal_dir * (GameRules.BLUE_LINE_Z - BLUE_LINE_BUFFER_M)
	var lead_z: float = carrier_pos.z - ctx.own_goal_dir * RUSH_ENTRY_LEAD_M
	if ctx.own_goal_dir * lead_z < ctx.own_goal_dir * line_z:
		lead_z = line_z
	return lerpf(line_z, lead_z, rush)


# Offside filter: the puck is outside the attacking zone in both this role's
# states, so a candidate past the opp blue line is offside. Velocity-corrected:
# a candidate counts as past it if braking to it (v²/2B on the velocity toward
# the line) would stop past the line.
static func _is_offside(c: Vector3, ctx: RoleContext) -> bool:
	var attack: float = -ctx.own_goal_dir
	var v_toward: float = maxf(attack * ctx.self_velocity.z, 0.0)
	var overshoot: float = v_toward * v_toward / (2.0 * AISteering.ARRIVAL_BRAKE_DECEL_M_S2)
	return attack * c.z + overshoot > GameRules.BLUE_LINE_Z
