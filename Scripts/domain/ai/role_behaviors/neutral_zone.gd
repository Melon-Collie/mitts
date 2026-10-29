class_name AIRoleNeutralZone

# The set neutral-zone shape (TRANS_DEFENSE): 5v5's 1-1-3 and 3v3's 1-2, filled
# from the back. See Scripts/domain/ai/CLAUDE.md → "Forecheck or set up".
#
#   NZ_F1 — the high "1": in their half and goal-side of the carrier, steers him
#     to the outside from a stand off him; once he is past, or in our half, he
#     runs him down (AIRoleTrack's hip).
#   NZ_MID (5v5) — the middle "1": mid-ice between the carrier and our line, a
#     layer up from it; once the carrier is past him, back through the middle
#     (AIRoleTrack's mid recovery).
#   BACK_WEAK (5v5) — our line's weak lane: picks up whoever enters it.
#
# BACK_STRONG and BACK_MID are AIRoleRushD's: the man who stands the carrier up
# and the man who holds the middle behind him.

# Our line's stand: this far on the neutral-zone side of the blue line, so the
# back line meets a carrier AT the line rather than inside it.
const BACK_LINE_STAND_OUT_M: float = 0.5
# 5v5's BACK_MID shades this far weak of centre: the strong side is BACK_STRONG's.
const BACK_MID_SHADE_M: float = 1.5
# NZ_MID stays this far up-ice of our line: a layer in front of the back three,
# never a fourth man on it. Two strides.
const NZ_MID_LAYER_M: float = 4.0
# NZ_MID's lane: the middle third of the ice, shaded half the carrier's way.
const NZ_MID_HALF_WIDTH_M: float = GameRules.END_ZONE_FACEOFF_DOT_X * 0.5
const NZ_MID_PUCK_SHADE: float = 0.5
# Goal-side of the carrier by at least this, NZ_F1 and NZ_MID still stand in front
# of him; less, he is past them and they backcheck.
const PAST_MARGIN_M: float = AIRoleTrack.CHECK_GOAL_SIDE_MARGIN_M


static func decide(ctx: RoleContext, slot: int) -> RoleDecision:
	match slot:
		AIRoleSlots.Slot.NZ_F1:
			return _decide_f1(ctx)
		AIRoleSlots.Slot.NZ_MID:
			return _decide_mid(ctx)
		_:
			return _decide_back_weak(ctx)


# Depth (metres off our goal line) of our line's stand.
static func line_depth_m() -> float:
	return GameRules.GOAL_LINE_Z - GameRules.BLUE_LINE_Z + BACK_LINE_STAND_OUT_M


# Depth (metres off our goal line) of `pos`.
static func depth_of(ctx: RoleContext, pos: Vector3) -> float:
	return GameRules.GOAL_LINE_Z - ctx.own_goal_dir * pos.z


# Where the back line stands, as a depth off our goal line: on our line while
# the carrier is a gap away from it, then level with the gap a defender in front
# of him keeps (the ladder plus this body's own ramp cushion, so a man standing
# still against a carrier at speed is already giving ground), never deeper than
# the house gate.
static func back_line_depth_m(ctx: RoleContext, ap: AICarrierApproach) -> float:
	var gap: float = AIRoleRushD.ladder_gap_m(ap.carrier_pos, ctx.own_goal_dir,
			ctx.self_blade_reach, AIRoleRushD.ramp_cushion_m(ctx, ap,
					ctx.rush_read.carrier_peer))
	return clampf(depth_of(ctx, ap.carrier_pos) - gap,
			AIZoneCoverage.HOUSE_TOP_DEPTH_M, line_depth_m())


# The back line's post at world-x `x`.
static func back_post(ctx: RoleContext, ap: AICarrierApproach, x: float) -> Vector3:
	return Vector3(x, 0.0,
			ctx.own_goal_dir * (GameRules.GOAL_LINE_Z - back_line_depth_m(ctx, ap)))


# ── NZ_F1: steer him wide, then run him down ─────────────────────────────────

static func _decide_f1(ctx: RoleContext) -> RoleDecision:
	var ap: AICarrierApproach = ctx.scratch_carrier_approach
	if not AIDefensiveVerbs.read_carrier_approach(ctx, ap) or ap.dir_net == Vector3.ZERO:
		return AIRoleTrack.decide(ctx, AIRoleSlots.Slot.NZ_F1)
	var carrier_depth: float = depth_of(ctx, ap.carrier_pos)
	if carrier_depth <= GameRules.GOAL_LINE_Z \
			or depth_of(ctx, ctx.self_pos) + PAST_MARGIN_M > carrier_depth:
		return AIRoleTrack.decide(ctx, AIRoleSlots.Slot.NZ_F1)

	var d := RoleDecision.new()
	var gap: float = ctx.pursuit_standoff_m + AIRoleRushD.ladder_gap_m(ap.carrier_pos,
			ctx.own_goal_dir, ctx.self_blade_reach,
			AIRoleRushD.ramp_cushion_m(ctx, ap, ctx.rush_read.carrier_peer))
	var stand: Vector3 = AIDefensiveVerbs.carrier_stand(ap, gap)
	# Not into their zone past their circle tops (the forecheck we did not take),
	# nor into our half (past the red line he is the backcheck, not a second D).
	var their_depth: float = GameRules.GOAL_LINE_Z + ctx.own_goal_dir * stand.z
	var held: bool = false
	if their_depth < AIZoneCoverage.HOUSE_TOP_DEPTH_M:
		stand.z = -ctx.own_goal_dir * (GameRules.GOAL_LINE_Z - AIZoneCoverage.HOUSE_TOP_DEPTH_M)
		held = true
	elif ctx.own_goal_dir * stand.z > 0.0:
		stand.z = 0.0
		held = true
	d.target_position = stand
	if not held:
		d.target_velocity = AIRoleReads.stand_ride_velocity(ctx)
	if ctx.rush_read.mode != AIRushRead.Mode.NONE:
		d.aim_world_pos = ap.carrier_pos
		d.has_aim_override = true
	return d


# ── NZ_MID: the middle of the neutral zone, then back through it ─────────────

static func _decide_mid(ctx: RoleContext) -> RoleDecision:
	var ap: AICarrierApproach = ctx.scratch_carrier_approach
	if not AIDefensiveVerbs.read_carrier_approach(ctx, ap):
		return AIRoleTrack.decide(ctx, AIRoleSlots.Slot.NZ_MID)
	var carrier_depth: float = depth_of(ctx, ap.carrier_pos)
	if depth_of(ctx, ctx.self_pos) + PAST_MARGIN_M > carrier_depth:
		return AIRoleTrack.decide(ctx, AIRoleSlots.Slot.NZ_MID)
	var gap: float = AIRoleRushD.ladder_gap_m(ap.carrier_pos, ctx.own_goal_dir,
			ctx.self_blade_reach, AIRoleRushD.ramp_cushion_m(ctx, ap,
					ctx.rush_read.carrier_peer))
	var depth: float = clampf(carrier_depth - gap, line_depth_m() + NZ_MID_LAYER_M,
			GameRules.GOAL_LINE_Z)
	var d := RoleDecision.new()
	d.target_position = Vector3(
			clampf(ap.carrier_pos.x * NZ_MID_PUCK_SHADE, -NZ_MID_HALF_WIDTH_M,
					NZ_MID_HALF_WIDTH_M),
			0.0, ctx.own_goal_dir * (GameRules.GOAL_LINE_Z - depth))
	return d


# ── BACK_WEAK: our line's weak lane ──────────────────────────────────────────

static func _decide_back_weak(ctx: RoleContext) -> RoleDecision:
	var d := RoleDecision.new()
	var ap: AICarrierApproach = ctx.scratch_carrier_approach
	if not AIDefensiveVerbs.read_carrier_approach(ctx, ap):
		d.target_position = ctx.self_pos
		return d
	var side: float = -ctx.strong_x
	var post: Vector3 = back_post(ctx, ap, side * AIRoleSlots.BACK_LANE_X_M)
	# Recovering: no man, at pace to the post (AIRoleTrack's doctrine).
	if not AIRoleTrack.is_inside(ctx, ctx.rush_read):
		d.target_position = post
		d.arrive_at_speed = true
		return d
	var pickup: float = AIRoleReads.xz_distance(post, ctx.defending_goal_pos) \
			+ AIRushRead.cover_envelope_m()
	if AIDefensiveVerbs.cover_threat(ctx, d,
			AIRoleTrack.man_in_lane_peer(ctx, ctx.rush_read, side, pickup),
			AIRoleReads.resolve_defensive_play_ref(ctx)):
		d.target_position = AILastManDiscipline.hold_out_to_house_gate(
				ctx.defending_goal_pos, d.target_position)
		return d
	d.target_position = post
	return d
