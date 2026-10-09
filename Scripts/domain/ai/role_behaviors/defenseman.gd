class_name AIRoleDefenseman

# The off-puck defenseman (5v5 only) — one module, four game moments, one
# philosophy: hold the structure, keep the race home winnable, threaten from
# the line. Design: plan §4; researched point play + gap doctrine in the
# plan's appendix.
#
#   OZONE points (POINT_STRONG / POINT_WEAK) — hold the offensive blue line
#     and WALK IT: a small lateral argmax opens a shooting lane (lane_clear
#     toward the net — the "walking the line" technique: move to open the
#     lane, don't stand in cover). The strong point sinks down his wall as
#     the cycle goes low (the researched staggered pair); the chosen stand is
#     then bounded by the shared pinch read (never held with a man behind you
#     and nobody covering — the keep-in insurance).
#   FORECHECK line pair (DP_STRONG / DP_WEAK) — hold the offensive blue line,
#     per lane, keep their wall clears in, and abandon the line for the
#     defensive home post the moment their breakout is genuinely under way —
#     exactly like the 3v3 forecheck's F3, which runs the same read. The strong
#     side D alone may PINCH down his wall onto a bottled carrier, and only
#     with the rotation behind him.
#
# THE ROTATION. Whenever the strong-side D is deeper than any stand his slot
# takes (pinching, chasing, battling), the weak-side D slides to the middle of
# the line and a forward rotates up to the vacated strong point — HIGH_SLOT in
# the O-zone, F2_WEAK on the forecheck — and drops back when the D recovers.
# The forward's half is `rotate_up_to_point`, called from his own role.
#   TRANS_OFFENSE safety valve (DVALVE) — trail the rush centrally about a zone
#     behind the play, bounded by the shared pinch read: always the reset
#     option, never beaten home.
#   NEUTRAL back shape (DBACK_L / DBACK_R) — the staggered goal-side pair
#     inside the dots at our blue line, shading with the puck's lateral
#     drift (the NZ 1-2-2's back wall).

# Blue-line hold: how far inside the offensive zone the points stand — a full
# puck-handling radius, so a catch's give or a backswing at the point never drags
# the puck back across the line and un-onsides the whole attack. One metre is not
# enough; a routine reception's cushion clears it.
const POINT_INSET_M: float = 2.0
# Strong point's extra sink rows when the cycle is low (puck below the dots)
# — down his wall toward the top of his circle, the researched wall slide.
# Two rows: with the whole defense collapsed low, a point glued to the line
# is no option for anything but a recycle; the keep-in feasibility below is
# what bounds how deep the walk may follow the play.
const POINT_SINK_M: float = 3.5
const POINT_SINK_ROWS: int = 2
const POINT_SINK_PUCK_DEPTH_M: float = 6.0
# Lateral walk-the-line samples (strong-signed u = s·x), wall → middle.
const POINT_STRONG_LANES_U: Array[float] = [9.5, 7.5, 5.5, 3.5, 1.5]
const POINT_WEAK_LANES_U: Array[float] = [6.0, 4.5, 3.0, 1.5, 0.0]
# Forecheck line pair lanes (world-x magnitude, inside the dots).
const DP_STRONG_LANE_X_M: float = 6.7
const DP_WEAK_LANE_X_M: float = 5.0
# Forecheck line-hold stand: this far INSIDE the offensive blue line, on the
# lane. The D pair is the 1-2-2's back wall — the layer the three forwards
# press in FRONT of — so its depth is the line, not the zone
# (docs/5v5-ai-plan.md §2: "the two D hold the offensive blue line inside the
# dots"). A pinch past it is the per-puck read in _wall_pinch.
#
# Inside the line rather than on it because the job at the line is KEEPING
# PUCKS IN, and a stand on the neutral-zone side can only watch a rim leave.
# Kept under a stick, so stepping back out with a breakout is one stride —
# which is the difference between this and the O-zone POINT_INSET_M, where the
# D holds possession and pays a full handling radius for the reception cushion.
const DP_LINE_INSET_M: float = 1.0
# DVALVE: how far behind the play the valve trails, and its goal-line cap.
const DVALVE_TRAIL_M: float = 10.0
const DVALVE_GOAL_LINE_PAD_M: float = 2.0
# DBACK posts: inside the dots at our blue line, with a small puck shade.
const DBACK_X_M: float = 5.0
const DBACK_PUCK_SHADE: float = 0.2
const DBACK_SHADE_MAX_M: float = 1.5

# ── Rim keep-ins (breakout plan §C.3) ────────────────────────────────────────
# A board-hugging clear travelling up a point's wall sails past the walk-the-line
# stands — they hold the line OFF the wall — and out of the zone untouched, which
# is the hole real rims exploit.
const RIM_MIN_SPEED_M_S: float = 8.0     # a FIRED clear — slower loose pucks are the
										 # chase election's ordinary business
const RIM_KEEPIN_WALL_INSET_M: float = 1.0

# ── The pinch and its rotation (5v5 plan §10, appendix: "D pinches, F3 fills")
# One stick of slack past the deepest stand a strong-D slot ever takes: beyond
# it he has left the point, short of it he is merely sinking with the cycle.
const POINT_VACATED_SLACK_M: float = \
		GameRules.DEFAULT_STICK_LENGTH_M + GameRules.DEFAULT_BLADE_LENGTH_M
# A filler whose last target sat this close to the vacated stand is already
# covering it, and keeps covering until the D is back inside his deepest stand.
# Generous because the leash and the numbers bound move the target off the stand.
const ROTATION_HELD_M: float = 3.0
# The weak D's lanes while his partner is down the wall (weak-signed u, so the
# negative entry is the strong side of centre): the middle of the line.
const POINT_WEAK_COVER_LANES_U: Array[float] = [1.5, 0.0, -1.5]
# How far down his wall the strong D may pinch, off their blue line: to the
# half-wall, where F2_STRONG's post (AIRoleForecheck.F2_STRONG_DEPTH_OFF_GOAL_M
# off their goal line) owns the wall below. test_role_defenseman holds the two
# together.
const PINCH_MAX_DEPTH_M: float = 7.36


static func decide(ctx: RoleContext, slot: int) -> RoleDecision:
	match slot:
		AIRoleSlots.Slot.POINT_STRONG:
			return _decide_point(ctx, true)
		AIRoleSlots.Slot.POINT_WEAK:
			return _decide_point(ctx, false)
		AIRoleSlots.Slot.DP_STRONG:
			return _decide_line_hold(ctx, ctx.strong_x * DP_STRONG_LANE_X_M, true)
		AIRoleSlots.Slot.DP_WEAK:
			return _decide_line_hold(ctx, -ctx.strong_x * DP_WEAK_LANE_X_M, false)
		AIRoleSlots.Slot.DVALVE:
			return _decide_valve(ctx)
		AIRoleSlots.Slot.DBACK_L:
			return _decide_back(ctx, -1.0)
		AIRoleSlots.Slot.DBACK_R:
			return _decide_back(ctx, 1.0)
		_:
			# Unreachable: the dispatcher routes exactly the seven slots above
			# here. Hold rather than return a target of (0, 0, 0).
			var d := RoleDecision.new()
			d.target_position = ctx.self_pos
			return d


# ── OZONE point play: hold the line, walk it for a lane ─────────────────────
static func _decide_point(ctx: RoleContext, is_strong: bool) -> RoleDecision:
	var d := RoleDecision.new()
	var own_dir: float = ctx.own_goal_dir
	var opp_net: Vector3 = ctx.attacking_goal_pos
	var line_z: float = -own_dir * (GameRules.BLUE_LINE_Z + POINT_INSET_M)
	var side: float = ctx.strong_x if is_strong else -ctx.strong_x

	# Keep-in pre-empt: a rim coming up MY wall — step to the boards at the line
	# and kill it at pace instead of walking the line while it sails past. A lost
	# race never fires the branch and the stand below holds.
	var keepin: Vector3 = wall_rim_keepin(ctx, side)
	if keepin.is_finite():
		d.target_position = keepin
		d.arrive_at_speed = true
		return d

	var opp_positions: Array[Vector3] = ctx.scratch_opp_positions
	var opp_states: Array[SkaterNetworkState] = ctx.scratch_opp_states
	AIRoleHelpers.collect_opponents(ctx, opp_positions, opp_states)
	var teammates: Array[Vector3] = ctx.scratch_teammates
	AIRoleHelpers.collect_teammates_excluding_self(ctx, teammates)
	# Keep-in insurance is NOT in this argmax: the walk picks the best shot lane,
	# and offensive_station_target below decides whether that stand is holdable.
	#
	# The strong point sinks a row down his wall when the cycle is low — puck
	# depth measured off the ATTACKED goal line, which is what opp_net names.
	var puck_depth: float = INF
	if ctx.snapshot != null and ctx.snapshot.puck_state != null:
		puck_depth = AIZoneCoverage.depth_of(
				opp_net.z, ctx.snapshot.puck_state.position)
	var allow_sink: bool = is_strong and puck_depth < POINT_SINK_PUCK_DEPTH_M

	var lanes: Array[float] = POINT_STRONG_LANES_U if is_strong else POINT_WEAK_LANES_U
	# The rotation's weak-D half: partner down the wall → hold the middle.
	if not is_strong and _partner_vacated(ctx, AIRoleSlots.Slot.POINT_STRONG):
		lanes = POINT_WEAK_COVER_LANES_U
	var shot_speed: float = ctx.self_wrister_shot_speed
	var base_stand := Vector3(side * lanes[0], 0.0, line_z)
	var best_pos: Vector3 = base_stand
	var best_score: float = -INF
	for u: float in lanes:
		for row: int in (POINT_SINK_ROWS + 1 if allow_sink else 1):
			var z: float = line_z - own_dir * (POINT_SINK_M * float(row))
			var c := Vector3(side * u, 0.0, z)
			if not AIRoleHelpers.is_legal_position(c):
				continue
			if AIRoleHelpers.too_close_to_teammate(c, teammates):
				continue
			# Walking the line: prefer the stand whose SHOT LANE is open —
			# lane_clear from the candidate to the net at this D's real shot
			# speed, i.e. "could I get my point shot through from here?".
			var lane: float = AIActionScoring.lane_clear(
					c, opp_net, opp_positions, shot_speed,
					AIActionScoring.EMPTY_VEC3, ctx.scratch_opp_caps)
			var score: float = lane + AIRoleHelpers.incumbent_bonus(ctx, c)
			if score > best_score:
				best_score = score
				best_pos = c
	if best_score == -INF:
		best_pos = base_stand
	# The pinch read: hold the line while there is support behind us or nobody
	# behind us; otherwise back off only as far as restores the numbers, and
	# either way stay inside feedable range — a point 30 m from the play is not a
	# point.
	d.target_position = AIRoleHelpers.offensive_station_target(
			ctx, best_pos, ctx.prev_held_forward_stand)
	d.held_forward_stand = d.target_position.distance_to(best_pos) < 0.5
	return d


# The keep-in intercept stand for a rim coming up `side`'s wall out of the zone
# we attack, or Vector3.INF when there is none / the race is lost. A fired loose
# puck whose PREDICTED path (friction and board caroms — the walk the chase
# election races on) crosses the keep-in line in that side's wall lane, outside
# the dots; the stand is that crossing, just inside the zone (never closer to the
# glass than a body), and the race is my arrival there against the puck's own
# crossing time. Reading the path rather
# than the puck's current heading is what sees a rim coming around the end boards
# while it is still behind the net, and prices the pace it sheds on the way.
#
# Whose rim it was does not enter: our own puck rimming out and their clear up
# the wall are the same keep-in, which is why the forecheck's line stations (here
# and 3v3's F3) call it as well as the points.
static func wall_rim_keepin(ctx: RoleContext, side: float) -> Vector3:
	if ctx.snapshot == null or ctx.snapshot.puck_state == null:
		return Vector3.INF
	var puck: PuckNetworkState = ctx.snapshot.puck_state
	if puck.carrier_peer_id != -1:
		return Vector3.INF
	if Vector2(puck.velocity.x, puck.velocity.z).length() < RIM_MIN_SPEED_M_S:
		return Vector3.INF
	var own_dir: float = ctx.own_goal_dir
	var stand := Vector3(
			side * (GameRules.INNER_HALF_WIDTH - RIM_KEEPIN_WALL_INSET_M),
			0.0, -own_dir * (GameRules.BLUE_LINE_Z + 0.5))
	# Already escaped past the line → gone; the TRANS flip owns it.
	if (puck.position.z - stand.z) * own_dir >= 0.0:
		return Vector3.INF
	var traj: Array[Vector3] = AILoosePuckChase.race_trajectory(
			puck.position, puck.velocity)
	var step_dt: float = AILoosePuckChase.RACE_LOOKAHEAD_S \
			/ float(AILoosePuckChase.RACE_STEPS)
	var prev: Vector3 = puck.position
	for i: int in traj.size():
		var p: Vector3 = traj[i]
		var past: float = (p.z - stand.z) * own_dir
		if past >= 0.0:
			var before: float = (stand.z - prev.z) * own_dir
			var f: float = before / maxf(before + past, 0.001)
			var cross_x: float = lerpf(prev.x, p.x, f)
			if signf(cross_x) != signf(side) \
					or absf(cross_x) < GameRules.END_ZONE_FACEOFF_DOT_X:
				return Vector3.INF
			stand.x = side * minf(absf(cross_x),
					GameRules.INNER_HALF_WIDTH - RIM_KEEPIN_WALL_INSET_M)
			var t_me: float = AIActionScoring.time_to_arrive(
					ctx.self_pos, stand, ctx.self_velocity,
					ctx.self_max_speed, ctx.self_max_accel, ctx.self_lateral_grip)
			return stand if t_me <= (float(i) + f) * step_dt else Vector3.INF
		prev = p
	return Vector3.INF


# ── FORECHECK: hold the line on the lane, or go home ────────────────────────
# The shared offensive-station read applied per lane for the D pair: hold the
# blue line on the lane while the read allows it, abandon it for the defensive
# home post the moment their breakout is genuinely under way. No intermediate
# stand — the read is categorical.
#
# Two things pre-empt the hold. A clear coming up my wall is kept in at the line
# (wall_rim_keepin) by either D: that stand is still the line, so it costs the
# back layer nothing. And the strong-side D alone may PINCH (_wall_pinch). In a
# 1-2-2 the D are the back layer, so a pinch is a per-puck read — the carrier is
# bottled on my wall, I get to him before he gets it out, my partner is home and
# a forward can fill my point — and the weak-side D categorically does not make
# it. Pinching BOTH, or unconditionally, turns every failed forecheck into an
# odd-man rush.
static func _decide_line_hold(ctx: RoleContext, lane_x: float,
		is_strong: bool) -> RoleDecision:
	var d := RoleDecision.new()
	var own_dir: float = ctx.own_goal_dir
	var line_z: float = -own_dir * (GameRules.BLUE_LINE_Z + DP_LINE_INSET_M)

	var keepin: Vector3 = wall_rim_keepin(ctx, signf(lane_x))
	if keepin.is_finite():
		d.target_position = keepin
		d.arrive_at_speed = true
		return d

	var line_stand := Vector3(lane_x, 0.0, line_z)
	if is_strong:
		var pinch: RoleDecision = _wall_pinch(ctx, signf(lane_x), line_stand)
		if pinch != null:
			return pinch
	elif _partner_vacated(ctx, AIRoleSlots.Slot.DP_STRONG):
		# The rotation's weak-D half: partner down the wall → the middle.
		line_stand.x = 0.0
	d.target_position = AIRoleHelpers.offensive_station_target(
			ctx, line_stand, ctx.prev_held_forward_stand)
	d.held_forward_stand = d.target_position.distance_to(line_stand) < 0.5
	return d


# The situational pinch: step down my wall onto an opposing carrier bottled
# between the line and the half-wall, as a pressurer — or null to hold the line.
#
# Gated on both halves of the trade. WINNING it: he is not already on his way
# out (the shared pinch read, the same one that sends the pair home on a
# breakout), and I reach him before his own skating gets the puck to the line.
# COVERING it if I lose: nobody of theirs is already behind my stand, my partner
# is home, and a forward can be on my point inside the late-man window — the
# rotation. A pinch already under way skips the race and the cover checks so it
# finishes rather than flickering, but still bails the moment the breakout forms.
static func _wall_pinch(ctx: RoleContext, side: float,
		line_stand: Vector3) -> RoleDecision:
	if ctx.snapshot == null or ctx.snapshot.puck_state == null:
		return null
	var carrier_pid: int = ctx.snapshot.puck_state.carrier_peer_id
	if carrier_pid == -1 or ctx.team_id_by_peer.get(carrier_pid, -1) == ctx.team_id:
		return null
	var cs: SkaterNetworkState = ctx.snapshot.skater_states.get(carrier_pid)
	if cs == null:
		return null
	# On my wall: outside the dot lane, my side, between the line and the half-wall.
	if signf(cs.position.x) != side \
			or absf(cs.position.x) < GameRules.END_ZONE_FACEOFF_DOT_X:
		return null
	var depth: float = _depth_inside_attacked_zone(ctx, cs.position)
	if depth < 0.0 or depth > PINCH_MAX_DEPTH_M:
		return null
	if not AIRoleHelpers.may_hold_forward_stand(
			ctx, ctx.prev_held_forward_stand, line_stand):
		return null
	var pinching: bool = ctx.prev_role_target.is_finite() \
			and _depth_inside_attacked_zone(ctx, ctx.prev_role_target) \
					> DP_LINE_INSET_M + POINT_VACATED_SLACK_M
	if not pinching:
		var t_me: float = AIActionScoring.time_to_arrive(
				ctx.self_pos, cs.position, ctx.self_velocity,
				ctx.self_max_speed, ctx.self_max_accel, ctx.self_lateral_grip)
		var out_speed: float = cs.velocity.z * ctx.own_goal_dir
		if out_speed > 0.0 and t_me >= depth / out_speed:
			return null
		if not _pinch_is_covered(ctx, line_stand, t_me):
			return null
	var d: RoleDecision = AIRolePressure.decide(ctx)
	d.pressures_puck = true
	# Still the forward posture, so the numbers read keeps its holding hysteresis.
	d.held_forward_stand = true
	return d


# The cover half of the pinch: nobody of theirs behind my stand, my partner on
# the line, and a forward who can take my point before a lost pinch turns into
# their rush (`t_engage` + the late-man window — the same window the house read
# calls "back in time to matter").
static func _pinch_is_covered(ctx: RoleContext, line_stand: Vector3,
		t_engage: float) -> bool:
	var our_net: Vector3 = ctx.defending_goal_pos
	var stand_d: float = AIRoleHelpers.xz_distance(line_stand, our_net)
	for lead: Vector3 in ctx.rush_read.attacker_leads:
		if AIRoleHelpers.xz_distance(lead, our_net) \
				< stand_d - AIRushRead.cover_envelope_m():
			return false
	var partner: SkaterNetworkState = _slot_holder(ctx, AIRoleSlots.Slot.DP_WEAK)
	if partner == null or _depth_inside_attacked_zone(ctx, partner.position) \
			> DP_LINE_INSET_M + POINT_VACATED_SLACK_M:
		return false
	var filler: SkaterNetworkState = _slot_holder(ctx, AIRoleSlots.Slot.F2_WEAK)
	if filler == null:
		return false
	return AIActionScoring.time_to_arrive(filler.position, line_stand,
			filler.velocity) <= t_engage + AIRushRead.LATE_MAN_WINDOW_S


# ── The rotation ─────────────────────────────────────────────────────────────

# The forward's half of the rotation, called from his own role (HIGH_SLOT for
# POINT_STRONG, F2_WEAK for DP_STRONG): the strong point's stand, held as a back
# layer, while the D who owns it is down the wall — or null when he is not.
static func rotate_up_to_point(ctx: RoleContext, strong_slot: int) -> RoleDecision:
	var stand: Vector3 = strong_point_stand(ctx, strong_slot)
	var covering: bool = ctx.prev_role_target.is_finite() \
			and AIRoleHelpers.xz_distance(ctx.prev_role_target, stand) < ROTATION_HELD_M
	if not strong_point_vacated(ctx, strong_slot, covering):
		return null
	var d := RoleDecision.new()
	d.target_position = AIRoleHelpers.offensive_station_target(
			ctx, stand, ctx.prev_held_forward_stand, true)
	d.held_forward_stand = d.target_position.distance_to(stand) < 0.5
	return d


# The strong-side D slot's own line stand: the point he would hold on the strong
# side if he were up.
static func strong_point_stand(ctx: RoleContext, strong_slot: int) -> Vector3:
	var own_dir: float = ctx.own_goal_dir
	if strong_slot == AIRoleSlots.Slot.DP_STRONG:
		return Vector3(ctx.strong_x * DP_STRONG_LANE_X_M, 0.0,
				-own_dir * (GameRules.BLUE_LINE_Z + DP_LINE_INSET_M))
	return Vector3(ctx.strong_x * GameRules.END_ZONE_FACEOFF_DOT_X, 0.0,
			-own_dir * (GameRules.BLUE_LINE_Z + POINT_INSET_M))


# Has the teammate holding `strong_slot` left the point — deeper into the zone we
# attack than any stand that slot takes, by POINT_VACATED_SLACK_M? `covering`
# drops the slack, so a rotation already made holds until he is back inside his
# deepest stand rather than flickering at the threshold. False when nobody holds
# the slot (the election's cross-fill owns an empty one) or no brain is wired.
static func strong_point_vacated(ctx: RoleContext, strong_slot: int,
		covering: bool) -> bool:
	var holder: SkaterNetworkState = _slot_holder(ctx, strong_slot)
	if holder == null:
		return false
	var deepest: float = DP_LINE_INSET_M if strong_slot == AIRoleSlots.Slot.DP_STRONG \
			else POINT_INSET_M + POINT_SINK_M * float(POINT_SINK_ROWS)
	if not covering:
		deepest += POINT_VACATED_SLACK_M
	return _depth_inside_attacked_zone(ctx, holder.position) > deepest


# The weak D's read of the same thing. His "already covering" is standing in the
# middle lanes of the line.
static func _partner_vacated(ctx: RoleContext, strong_slot: int) -> bool:
	var covering: bool = ctx.prev_role_target.is_finite() \
			and absf(ctx.prev_role_target.x) < POINT_WEAK_COVER_LANES_U[0] + 0.5
	return strong_point_vacated(ctx, strong_slot, covering)


# The teammate (not me) the brain has in `slot`, or null.
static func _slot_holder(ctx: RoleContext, slot: int) -> SkaterNetworkState:
	if ctx.team_brain == null or ctx.snapshot == null:
		return null
	for pid: int in ctx.snapshot.skater_states:
		if pid == ctx.peer_id or ctx.team_id_by_peer.get(pid, -1) != ctx.team_id:
			continue
		if ctx.team_brain.get_slot(pid) == slot:
			return ctx.snapshot.skater_states[pid]
	return null


# Metres inside the zone we attack, past its blue line (negative = outside it).
static func _depth_inside_attacked_zone(ctx: RoleContext, pos: Vector3) -> float:
	return -ctx.own_goal_dir * pos.z - GameRules.BLUE_LINE_Z


# ── TRANS_OFFENSE: the safety valve ───────────────────────────────────────────────
static func _decide_valve(ctx: RoleContext) -> RoleDecision:
	var d := RoleDecision.new()
	var own_dir: float = ctx.own_goal_dir
	var play_ref: Vector3 = AIRoleHelpers.resolve_offensive_play_ref(ctx)
	if not play_ref.is_finite():
		d.target_position = ctx.self_pos
		return d
	# Trail the play centrally, one zone behind, never behind our goal line.
	var cap: float = GameRules.GOAL_LINE_Z - DVALVE_GOAL_LINE_PAD_M
	var trail_z: float = clampf(play_ref.z + own_dir * DVALVE_TRAIL_M, -cap, cap)
	var target := Vector3(0.0, 0.0, trail_z)
	# Last-man cap: the valve's whole job is to never be beaten home. A lurker
	# already behind the trail point, with nobody covering, pulls the valve back
	# to its post.
	var valve_stand: Vector3 = target
	target = AIRoleHelpers.offensive_station_target(
			ctx, valve_stand, ctx.prev_held_forward_stand)
	d.held_forward_stand = target.distance_to(valve_stand) < 0.5
	d.target_position = target
	# The rush advances every tick — pace the waypoint, don't brake at it.
	d.arrive_at_speed = true
	return d


# ── NEUTRAL: the goal-side back pair ─────────────────────────────────────────
# The blue-line stand is numbers-bounded like every other station in this file.
# Unbounded it is the puckwatching last man who holds his own blue line into a
# guaranteed breakaway. Nobody behind the pair leaves the stand exactly where it
# was, so the NZ back wall is unchanged in ordinary play; a stretch threat
# already past it sags the pair down the retreat line to the layer covering him.
static func _decide_back(ctx: RoleContext, side: float) -> RoleDecision:
	var d := RoleDecision.new()
	var own_dir: float = ctx.own_goal_dir
	var x: float = side * DBACK_X_M
	if ctx.snapshot != null and ctx.snapshot.puck_state != null:
		# Shade with the puck's lateral drift — the back wall slides, it
		# doesn't chase.
		x += clampf(ctx.snapshot.puck_state.position.x * DBACK_PUCK_SHADE,
				-DBACK_SHADE_MAX_M, DBACK_SHADE_MAX_M)
	var stand := Vector3(x, 0.0, own_dir * GameRules.BLUE_LINE_Z)
	d.target_position = AIRoleHelpers.neutral_station_target(
			ctx, stand, ctx.prev_held_forward_stand)
	d.held_forward_stand = d.target_position.distance_to(stand) < 0.5
	return d
