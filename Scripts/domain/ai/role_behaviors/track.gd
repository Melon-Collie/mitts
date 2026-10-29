class_name AIRoleTrack

# The backcheck (TRANS_DEFENSE, both team sizes) — what the neutral zone's "1"s
# do once the carrier is past them (AIRoleNeutralZone). Design:
# docs/transition-defense-plan.md §5, §7.
#
#   NZ_F1 — runs the CARRIER down, and may finish a check once goal-side of him.
#   NZ_MID (5v5) — back through MID-ICE to just inside the circle tops, then
#     picks up whoever enters the middle.
#
# Backcheckers race until they are back, THEN pick up: a tracker the shared read
# classifies as not yet inside skates his recovery post at full pace and runs no
# argmax. Never run a cover argmax from behind the play — its arrival brake,
# anti-crowd and hysteresis exist to stabilize a stationary post, and from 20 m
# back it reads as lazy escorting.

# A mid tracker stops this far inside the house gate (the tops of the circles).
const CIRCLE_TOP_INSET_M: float = 0.5

# NZ_F1's target: the carrier's hip, this far goal-side of his REAL
# position, so the tracker takes the puck rather than riding alongside. Never
# lead it: the hip rides him, and a lead would put it out of reach.
const HIP_GOAL_SIDE_M: float = 0.8

# A tracker may commit a check only once goal-side of the carrier by this
# margin: a run at the play from up-ice that misses removes him from it.
const CHECK_GOAL_SIDE_MARGIN_M: float = 0.5


static func decide(ctx: RoleContext, slot: int) -> RoleDecision:
	if slot == AIRoleSlots.Slot.NZ_F1:
		return _decide_puck(ctx)
	return _decide_mid(ctx)


# ── NZ_F1: run the carrier down ──────────────────────────────────────────────

static func _decide_puck(ctx: RoleContext) -> RoleDecision:
	var d := RoleDecision.new()
	var read: AIRushRead = ctx.rush_read

	var ap: AICarrierApproach = ctx.scratch_carrier_approach
	if not AIDefensiveVerbs.read_carrier_approach(ctx, ap):
		d.target_position = ctx.self_pos
		return d
	var carrier_pos: Vector3 = ap.carrier_pos
	var hip: Vector3 = carrier_pos
	if ap.dir_net != Vector3.ZERO:
		# NOT angled, unlike carrier_stand: a backchecker catching up has no
		# inside to take, and a shade would only lengthen the chase.
		hip = carrier_pos + ap.dir_net * _hip_gap(ctx, ap, read.carrier_peer)

	if _is_goal_side_of(ctx, carrier_pos, CHECK_GOAL_SIDE_MARGIN_M):
		var check: AIBodyCheck.Result = AIDefensiveVerbs.evaluate_body_check(ctx)
		if check.commit:
			d.commit_check = true
			d.target_position = check.target
			return d

	d.target_position = hip
	d.target_velocity = AIRoleReads.stand_ride_velocity(ctx)
	# No brake at the hip; riding a man already expresses that, so this covers
	# the loose-puck fallback.
	d.arrive_at_speed = true
	# Stick on the puck, so the poke / lift is live the moment he is in reach.
	if read.mode != AIRushRead.Mode.NONE:
		d.aim_world_pos = carrier_pos
		d.has_aim_override = true
	return d


# How far goal-side of the carrier the hip may ask this tracker to stand. The
# hip is a catch-up target, but the election can hand NZ_F1 to a body
# already goal-side, who must not be sent up-ice as a second challenger on
# BACK_STRONG's man. So:
#   · behind him — the plain hip;
#   · goal-side inside the ladder (AIRoleRushD.ladder_gap_m) — hold the depth
#     you own;
#   · goal-side beyond the ladder — close to the ladder's gap and no further.
static func _hip_gap(ctx: RoleContext, ap: AICarrierApproach,
		carrier_peer: int) -> float:
	var own_depth: float = (ctx.self_pos.x - ap.carrier_pos.x) * ap.dir_net.x \
			+ (ctx.self_pos.z - ap.carrier_pos.z) * ap.dir_net.z
	if own_depth <= HIP_GOAL_SIDE_M:
		return HIP_GOAL_SIDE_M
	var ladder: float = AIRoleRushD.ladder_gap_m(
			ap.carrier_pos, ctx.own_goal_dir, ctx.self_blade_reach,
			AIRoleRushD.ramp_cushion_m(ctx, ap, carrier_peer))
	return minf(minf(own_depth, maxf(ladder, HIP_GOAL_SIDE_M)), ap.net_dist)


# ── NZ_MID: back through the middle, stop at the circle tops ─────────────────

static func _decide_mid(ctx: RoleContext) -> RoleDecision:
	var d := RoleDecision.new()
	var read: AIRushRead = ctx.rush_read

	# RECOVERING: no argmax, no man — cut inside to the post he will hold once
	# home, hard (§7), not a pursuit curve at the rush's shoulder.
	if not is_inside(ctx, read):
		d.target_position = _post(ctx, read)
		d.arrive_at_speed = true
		return d

	# HOME: cover the man in my ice; with nobody there, hold the post — never
	# chase out of the structure.
	if AIDefensiveVerbs.cover_threat(ctx, d,
			man_in_lane_peer(ctx, read, 0.0, _pickup_depth_m()),
			AIRoleReads.resolve_defensive_play_ref(ctx)):
		return d
	d.target_position = _post(ctx, read)
	return d


# The mid tracker's post: just inside the circle tops along `read.threat_axis`
# (so it rotates with the rush's bearing).
static func _post(ctx: RoleContext, read: AIRushRead) -> Vector3:
	var axis: Vector3 = read.threat_axis
	if axis == Vector3.ZERO or not axis.is_finite():
		axis = Vector3(0.0, 0.0, -ctx.own_goal_dir)
	return ctx.defending_goal_pos - axis * _post_depth()


# How far off our net a man may be and still be in "my ice": the post plus a
# cover envelope. Bounding the man bounds the stand, since cover_man_target sits
# goal-side of him — so "never chase out of the structure" holds.
static func _pickup_depth_m() -> float:
	return _post_depth() + AIRushRead.cover_envelope_m()


# Depth of the mid tracker's post off our own goal line.
static func _post_depth() -> float:
	return AIZoneCoverage.HOUSE_TOP_DEPTH_M - CIRCLE_TOP_INSET_M


# Lane ownership, not man-marking: the attacker (not the carrier) nearest our
# net on my side of centre (`side` ±1; 0 is the whole ice) and within
# `pickup_m` of our net. -1 when nobody is.
static func man_in_lane_peer(ctx: RoleContext, read: AIRushRead,
		side: float, pickup_m: float) -> int:
	var i: int = _man_in_lane_index(ctx, read, side, pickup_m)
	return read.attackers[i] if i != -1 else -1


static func _man_in_lane_index(ctx: RoleContext, read: AIRushRead,
		side: float, pickup_m: float) -> int:
	var best: int = -1
	var best_depth: float = pickup_m
	var our_net: Vector3 = ctx.defending_goal_pos
	for i: int in read.attackers.size():
		if read.attackers[i] == read.carrier_peer:
			continue
		var lead: Vector3 = read.attacker_leads[i]
		# Half-ice filter only when there IS a neighbour (side != 0).
		if side != 0.0 and lead.x * side < 0.0:
			continue  # other half of the ice — the neighbour's man
		# Seeded at the pickup bound: a man outside my ice never wins.
		var depth: float = lead.distance_to(our_net)
		if depth < best_depth:
			best_depth = depth
			best = i
	return best


# Have I got back goal-side of the rush? AIRushRead's own recovery
# classification, so the mode switch agrees with the read.
static func is_inside(ctx: RoleContext, read: AIRushRead) -> bool:
	if read.mode == AIRushRead.Mode.NONE:
		return true
	return read.recovery_by_peer.get(ctx.peer_id, AIRushRead.Recovery.INSIDE) \
			== AIRushRead.Recovery.INSIDE


# Am I goal-side of `them` by at least `margin`, radially off our net?
static func _is_goal_side_of(ctx: RoleContext, them: Vector3,
		margin: float) -> bool:
	var our_net: Vector3 = ctx.defending_goal_pos
	return ctx.self_pos.distance_to(our_net) + margin < them.distance_to(our_net)
