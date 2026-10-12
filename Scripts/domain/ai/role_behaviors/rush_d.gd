class_name AIRoleRushD

# RUSH_D1 / RUSH_D2 — the two defensemen defending a rush (5v5 TRANS_DEFENSE).
# Design: docs/transition-defense-plan.md §5–§6.
#
#   RUSH_D1 — the strong-side D. He OWNS THE CARRIER: hold a gap sized by the
#     ice remaining, angle him off the middle, and attack the moment his speed
#     advantage is gone. He keeps the carrier across the blue line (the state
#     does not flip there — see the coverage gate), so there is no handoff and
#     no target discontinuity mid-rush.
#   RUSH_D2 — the weak-side D. He holds MID-ICE and takes the mid-lane drive
#     ("the mid-lane drive is fed to D2"). On a DOWN_ONE read he is the man in
#     the passing lane; with only one D back, RUSH_D1 inherits that job.
#
# ── Gap control ──────────────────────────────────────────────────────────────
# The gap is a LADDER ON ICE REMAINING, plus the RAMP CUSHION: the ground the
# carrier gains while this body builds to his speed (ramp_cushion_m). The ladder
# is the gap between two bodies already travelling together; the cushion is what
# it costs to become one, and it is nil once you are. Sizing the gap off the
# carrier's pace ALONE holds the offensive blue line's gap all the way back to
# your own net, which is the sag — the cushion cannot, because a defender riding
# the rush at its pace has nothing left to build.
#
# Modifiers must be able to run BOTH ways — something has to be able to say
# CLOSE THE GAP, not just widen it — and they read the team's shared numbers
# rather than each defender's private depth scan, which on a rush sees nobody
# home and disables the blue-line stand for everyone.
#
# THE GAP IS MEASURED OFF HIS REAL POSITION, never a velocity-led one. The route
# carries his velocity as a feed-forward, so a lead on top of it double-counts
# his motion: at a 7.7 m/s rush that is 2.67 m of doctrine plus 2.31 m of lead,
# 86% wider than the ladder asks for. Note test_role_rush_d measures against the
# LED point on purpose to isolate the ladder — the carrier is beaten off his real
# body, so that difference is an artifact of the test, not of the doctrine.

# The gap ladder, in stick lengths (BLADE_REACH_M — the honest physical unit,
# already attribute-scaled, so a long-stick D legitimately plays a hair wider).
const GAP_MIN_STICKS: float = 1.0
const GAP_MAX_STICKS: float = 3.0
# One rung of the ladder: the step every modifier moves the gap by.
const GAP_RUNG_STICKS: float = 1.0

# Backpressure that lets the D tighten and stand up (the repo's own doctrine,
# docs/5v5-ai-plan.md:548 — "a backchecker within ~1-2 s of the carrier lets the
# D tighten the gap and stand up; without it, default conservative").
const BACKPRESSURE_TIGHTEN_S: float = 1.5

# ── Gap-up trigger ───────────────────────────────────────────────────────────
# When the carrier's speed advantage is gone, ATTACK — close to stick range on
# an angle, skating forward. This is the modern read ("defend by skating
# forward, kill the rush early").
#
# He isn't coming at pace — and, under the stride ramp, he can't BUILD it past us
# either (see should_gap_up):
const GAP_UP_CLOSING_M_S: float = 3.0
# Steered inside this of the boards: no room left to take outside.
const GAP_UP_WALL_M: float = 2.0

# ── Odd-man lane fan ─────────────────────────────────────────────────────────
const RUSH_LANE_FAN_FRACTIONS: Array[float] = [0.25, 0.5, 0.75, 1.0]
const LINE_HOLD_MARGIN: float = 0.04
const LANE_PLAY_DANGER_BAR: float = 0.5

# RUSH_D2's mid-ice post: how far off the net he holds when there is no mid-lane
# man to pick up, measured along the threat axis. Just above the house gate —
# he is the layer behind RUSH_D1, not a second body on the puck.
const D2_MID_DEPTH_M: float = 12.0
# How far off centre an attacker may be and still count as the MID-LANE drive
# D2 exists to take: the end-zone dot lane, which is what bounds the middle of
# the ice. Without this the pick was argmin|x| over the whole rush, so a lone
# second attacker hugging the boards read as "the mid-lane man" and pulled D2
# off mid-ice — vacating the exact lane the layered defense keeps him in. A wide
# man is the mid trackers' pickup as he cuts in, not D2's to chase.
const D2_MID_LANE_HALF_WIDTH_M: float = GameRules.END_ZONE_FACEOFF_DOT_X
# How far weak-side of centre D2 shades while holding mid-ice.
const D2_WEAK_SHADE_M: float = 2.0


static func decide(ctx: RoleContext, slot: int) -> RoleDecision:
	if slot == AIRoleSlots.Slot.RUSH_D2:
		return _decide_d2(ctx)
	return _decide_d1(ctx)


# ── RUSH_D1: own the carrier ─────────────────────────────────────────────────

static func _decide_d1(ctx: RoleContext) -> RoleDecision:
	var d := RoleDecision.new()
	var read: AIRushRead = ctx.rush_read

	var ap: AICarrierApproach = ctx.scratch_carrier_approach
	if not AIRoleHelpers.read_carrier_approach(ctx, ap):
		d.target_position = ctx.self_pos
		return d
	var carrier_pos: Vector3 = ap.carrier_pos
	var our_net: Vector3 = ctx.defending_goal_pos
	if ap.dir_net == Vector3.ZERO:
		d.target_position = carrier_pos   # on top of our net — no line to hold
		return d
	var dir_net: Vector3 = ap.dir_net
	var dist: float = ap.net_dist
	var closing: float = ap.closing

	var cushion: float = ramp_cushion_m(ctx, ap, read.carrier_peer)
	var gap: float = _gap_for(ctx, read, carrier_pos, cushion)
	gap = minf(gap, dist)   # never project the stand past the net

	# GAP UP: his speed advantage is gone, so stop retreating and take the ice.
	# Closing to stick range on an angle IS the attack. It is exempt from the
	# step-up bound below, because the bound prices exactly the risk the gap-up's
	# triggers rule out — being beaten by pace you cannot match.
	var gapping_up: bool = should_gap_up(ctx, read, ap, cushion)
	# The stand rides him, so the trip ends with this body already travelling at
	# the rush's pace at the ladder's gap. That is what gap control IS, and it is
	# also what stands the approach bound down — see _settable_gap.
	var ride: Vector3 = AIRoleHelpers.stand_ride_velocity(ctx)
	if gapping_up:
		gap = minf(stick_m(ctx) * GAP_MIN_STICKS, dist)
	elif ride == Vector3.ZERO:
		gap = minf(_settable_gap(ctx, carrier_pos, dir_net, gap, closing), dist)
	# Stepping UP into the stand, or retreating with it? Measured off the carrier
	# on the same axis the gap is, so the comparison is exact and carries no dead
	# band of its own — the arrival brake it selects (below) has its own
	# engage/release hysteresis and a speed floor, so the one regime where this
	# can flicker is a near-stationary body, where the brake is inert anyway.
	var stepping_up: bool = _depth_along(ctx, carrier_pos, dir_net) > gap

	var stand: Vector3 = AIRoleHelpers.carrier_stand(ap, gap)

	# Odd-man: play the pass. The lane fan finds the feed lane from the
	# evaluators; the numbers read decides WHEN that doctrine applies, rather
	# than the fan inferring it from receiver danger alone.
	if read.numbers != AIRushRead.Numbers.EVEN_OR_UP and ctx.plays_rush_pass_lanes:
		var fan: Vector3 = _lane_fan_target(ctx, read, carrier_pos, our_net,
				dir_net, carrier_pos.distance_to(stand))
		if fan.is_finite():
			stand = fan

	d.target_position = _clamp_to_house(ctx, stand)
	d.target_velocity = ride
	set_house_retreat_floor(ctx, ap, d)
	# The arrival brake is an ICE-frame read, so it only reaches this role when
	# there is no man to ride (a loose puck) — a moving stand stands it down
	# outright. There a stand sweeping toward us at the play's pace is not a
	# station, so braking at it parks us short and the play arrives while we are
	# stopped: a RETREAT is paced, and a step-UP wants the brake because the
	# approach bound placed that stand precisely as its trigger. The gap-up drives
	# through either way — against a carrier with no speed to beat us with, taking
	# the ice IS the attack.
	d.arrive_at_speed = gapping_up or not stepping_up
	return d


# How far goal-side of `threat_pos` this bot currently stands, along `dir_net` —
# the same axis and origin the gap is expressed in, so the two are comparable.
static func _depth_along(ctx: RoleContext, threat_pos: Vector3,
		dir_net: Vector3) -> float:
	return (ctx.self_pos.x - threat_pos.x) * dir_net.x \
			+ (ctx.self_pos.z - threat_pos.z) * dir_net.z


# The BASE ladder, in stick lengths: ice remaining to OUR blue line gives 3
# sticks at their blue line, 2 at the red line, 1 at ours. Zero ice left (he is
# in the zone) means you are on him.
#
# The divisor is BLUE_LINE_Z — one zone-to-centre span — because that is the ice
# between consecutive rungs: their blue line is 2·BLUE_LINE_Z of remaining ice,
# the red line is 1·, ours is 0·, so `1 + ice / BLUE_LINE_Z` lands the table
# above exactly. Doubling it (the §6 prose reads "2 zones", which is the same
# distance said differently) halves the ramp to 2 / 1.5 / 1 and leaves
# GAP_MAX_STICKS unreachable from the base term, while still tightening with
# depth — which is all a monotonicity test can see.
static func _ladder_sticks(threat_pos: Vector3, own_goal_dir: float) -> float:
	var ice_to_line: float = maxf(
			GameRules.BLUE_LINE_Z - own_goal_dir * threat_pos.z, 0.0)
	return clampf(GAP_MIN_STICKS + ice_to_line / GameRules.BLUE_LINE_Z,
			GAP_MIN_STICKS, GAP_MAX_STICKS)


# The ladder gap in metres WITHOUT the shared read's numbers/backpressure rungs,
# plus the ramp cushion (ramp_cushion_m). Public so the lost-race pre-contain can
# stand where RUSH_D1 is going to want it: two different formulas leave the
# declining chaser planted somewhere the gap defender has to correct off the
# moment possession flips. The rungs are deliberately excluded — a NEUTRAL
# chaser has no rush posture to read yet.
static func ladder_gap_m(threat_pos: Vector3, own_goal_dir: float,
		stick: float, cushion_m: float) -> float:
	return _with_cushion(_ladder_sticks(threat_pos, own_goal_dir) \
			* maxf(stick, 0.5), cushion_m, threat_pos, own_goal_dir)


# The cushion deepens the stand only as far as the house gate: it is the price
# of a retreat race that finishes there (ramp_cushion_m), so it never pushes a
# stand past it. The ladder alone still applies inside, where it is the in-zone
# "on him" gap.
static func _with_cushion(ladder_m: float, cushion_m: float,
		threat_pos: Vector3, own_goal_dir: float) -> float:
	var dz: float = own_goal_dir * GameRules.GOAL_LINE_Z - threat_pos.z
	var ice_to_gate: float = sqrt(threat_pos.x * threat_pos.x + dz * dz) \
			- AIZoneCoverage.HOUSE_TOP_DEPTH_M
	return maxf(ladder_m, minf(ladder_m + cushion_m, ice_to_gate))


# The ground the threat gains on this body while it builds to his speed, both
# driving flat out down `ap.dir_net` from now (AIStrideRamp.head_start). Our
# momentum the other way is braked out first, so a defender still drifting
# up-ice from the attack owes that too.
#
# The race finishes at the HOUSE GATE (the top of the circles — AIRushRead's
# finish line for the same race). Past it there is no ice left to build speed
# in, and standing up is the in-zone ladder's job: so the horizon is his trip to
# the gate, and the head start is never more than the ice he has left to it.
# Without that bound a defender already home read a flying carrier as metres of
# cushion to concede and was walked into his own crease; _with_cushion holds the
# stand itself to the same line.
#
# This is the gap's honest pace term. The ladder describes two bodies already
# travelling together; a standing defender against a carrier at 9 m/s concedes
# ~5.5 m before he is one, which is more than the whole 3-stick ladder. Once he
# rides the rush at its pace the cushion is nil and the ladder alone sets the
# gap, so it cannot hold an O-zone gap at our own net the way pace-sizing did.
#
# Along the line only: lateral momentum has its own redirect cost, which this
# does not price. `threat_peer` -1 (a loose puck) prices a league skater. Caps
# carry no puck-carry speed cap, so a carrier is priced at his free top speed —
# a slight over-read of the cushion, in the safe direction.
static func ramp_cushion_m(ctx: RoleContext, ap: AICarrierApproach,
		threat_peer: int) -> float:
	return head_start_on_me(ctx, ap.dir_net, ap.carrier_vel, ap.net_dist,
			threat_peer)


# Ends a ridden retreat at the HOUSE GATE for a defender still in front of the
# carrier he owns — the same finish line the ladder's retreat race is priced to
# (ramp_cushion_m). Inside it there is no ice left to build speed in, so riding
# him on toward our net only decides where the shot comes from with us in our
# own crease; standing him up is the in-zone ladder's job. Once he is level with
# us the floor lifts, because a beaten defender has to chase.
static func set_house_retreat_floor(ctx: RoleContext, ap: AICarrierApproach,
		d: RoleDecision) -> void:
	if d.target_velocity == Vector3.ZERO or ap.dir_net == Vector3.ZERO:
		return
	var depth: float = (ctx.self_pos.x - ap.carrier_pos.x) * ap.dir_net.x \
			+ (ctx.self_pos.z - ap.carrier_pos.z) * ap.dir_net.z
	if depth <= 0.0:
		return
	d.retreat_floor_center = ctx.defending_goal_pos
	d.retreat_floor_radius_m = AIZoneCoverage.HOUSE_TOP_DEPTH_M


# ramp_cushion_m's race for any threat: `dir_net` his line to our net,
# `net_dist` his ice to it. Also what "behind me" means to an offensive station
# (race_depth_to_net).
static func head_start_on_me(ctx: RoleContext, dir_net: Vector3,
		threat_vel: Vector3, net_dist: float, threat_peer: int) -> float:
	var caps: AISkaterCaps = ctx.caps_by_peer.get(threat_peer) \
			if threat_peer != -1 else null
	var lead_vmax: float = caps.max_speed if caps != null \
			else AIActionScoring.SKATER_REF_SPEED_M_S
	var lead_accel: float = caps.max_accel if caps != null \
			else AIActionScoring.SHED_ACCEL_DEFAULT_M_S2
	var lead_v: float = threat_vel.x * dir_net.x + threat_vel.z * dir_net.z
	var self_v: float = ctx.self_velocity.x * dir_net.x \
			+ ctx.self_velocity.z * dir_net.z
	var ice_to_gate: float = net_dist - AIZoneCoverage.HOUSE_TOP_DEPTH_M
	if ice_to_gate <= 0.0:
		return 0.0
	var horizon: float = AIStrideRamp.time_to_cover(
			maxf(lead_v, 0.0), ice_to_gate, lead_vmax, lead_accel)
	return minf(AIStrideRamp.head_start(lead_v, lead_vmax, lead_accel,
			self_v, ctx.self_max_speed, ctx.self_max_accel,
			AIActionScoring.REVERSAL_BRAKE_DECEL_M_S2, horizon), ice_to_gate)


# How far from our net an attacker is, as this body has to race him: his
# distance less the ground he gains on us while we build to his pace
# (AIRoleRushD.head_start_on_me). "Behind me" is a race under the stride ramp —
# a man level with a standing station at 8 m/s is already past it by the time
# it is moving — so counting numbers off where he stands reads him late.
static func race_depth_to_net(ctx: RoleContext, pid: int) -> float:
	var s: SkaterNetworkState = ctx.snapshot.skater_states.get(pid)
	if s == null:
		return INF
	var our_net: Vector3 = ctx.defending_goal_pos
	var d: float = AIRoleHelpers.xz_distance(s.position, our_net)
	if d < 0.001:
		return 0.0
	var dir_net := Vector3((our_net.x - s.position.x) / d, 0.0,
			(our_net.z - s.position.z) / d)
	return maxf(d - head_start_on_me(ctx, dir_net, s.velocity, d,
			pid), 0.0)

# The gap ladder plus its modifiers, in metres.
static func _gap_for(ctx: RoleContext, read: AIRushRead, carrier_pos: Vector3,
		cushion_m: float) -> float:
	var sticks: float = _ladder_sticks(carrier_pos, ctx.own_goal_dir)

	# Numbers. EVEN_OR_UP is licence to challenge; DOWN_TWO_PLUS buys time for
	# the backcheck. DOWN_ONE deliberately does NOT widen — an odd-man
	# concession is LATERAL (into the pass lane, below), never deeper. Conceding
	# depth on a 2-on-1 is how it turns into a breakaway.
	if read.numbers == AIRushRead.Numbers.EVEN_OR_UP:
		sticks -= GAP_RUNG_STICKS
	elif read.numbers == AIRushRead.Numbers.DOWN_TWO_PLUS:
		sticks += GAP_RUNG_STICKS

	# Live backpressure lets us stand up (see BACKPRESSURE_TIGHTEN_S).
	if read.backpressure_s < BACKPRESSURE_TIGHTEN_S:
		sticks -= GAP_RUNG_STICKS

	sticks = clampf(sticks, GAP_MIN_STICKS, GAP_MAX_STICKS)
	return _with_cushion(sticks * stick_m(ctx), cushion_m, carrier_pos,
			ctx.own_goal_dir)


# Is his speed advantage gone?
#
# He is not coming at pace, AND he cannot build it past us: whatever he does
# from here, he gains less than a stick on us before we are travelling at his
# speed (`cushion_m`, ramp_cushion_m), so from one stick off him he never gets
# outside our reach. His pace alone cannot answer this under the stride ramp: a
# standing defender stepped up on a fresh receiver is beaten by the burst, and
# one already backing off at that pace is not. The race alone cannot either: a
# defender riding a full-speed rush has nothing to build, but the ladder's
# cushion is there for the cut, not the burst.
#
# And when the retreat cannot hold a gap — by the time I am up to his speed he
# has eaten all but a stick of the ice I own — retreating only decides where he
# reaches me, and I would meet him turning. If I stand in his lane, his path runs
# through my reach and meeting him now, skating at him, is the contest I can
# still win: step up. Off his lane I keep retreating; a step-up across to him is
# a second lost race, spent skating sideways while he builds speed.
# (tests/unit/ai/test_nz_turnover_recovery.gd measures both halves.)
#
# The race only means something while he is coming at us. A carrier not
# advancing on our net has no rush to beat us with — the ladder has no domain
# (see AIRolePressure: the forechecker's F1, a D retrieving behind his own
# line) — and he is attacked outright, as is one steered to the wall.
#
# Public because AIRolePressure asks the identical question. The two roles that
# own a carrier already share the gap LADDER; they have to share the read that
# says when the ladder stops applying, or the answer changes at the handoff —
# and for the forechecking F1 (which dispatches into PRESSURE) the ladder never
# applied in the first place. See AIRolePressure.decide.
static func should_gap_up(ctx: RoleContext, read: AIRushRead,
		ap: AICarrierApproach, cushion_m: float) -> bool:
	# Never step up into a rush we're outnumbered against — that is the one case
	# where being beaten is a goal rather than a scoring chance.
	if read.numbers == AIRushRead.Numbers.DOWN_TWO_PLUS:
		return false
	if ap.closing < AIRushRead.REGROUP_CLOSING_M_S:
		return true
	# Steered to the wall: no outside left to give him.
	if GameRules.INNER_HALF_WIDTH - absf(ap.carrier_pos.x) < GAP_UP_WALL_M:
		return true
	var stick: float = stick_m(ctx)
	if ap.closing < GAP_UP_CLOSING_M_S and cushion_m < stick:
		return true
	var dx: float = ctx.self_pos.x - ap.carrier_pos.x
	var dz: float = ctx.self_pos.z - ap.carrier_pos.z
	var depth: float = dx * ap.dir_net.x + dz * ap.dir_net.z
	var off_lane: float = absf(dx * ap.dir_net.z - dz * ap.dir_net.x)
	return depth < cushion_m + stick and off_lane <= stick


# ── Step-up discipline ───────────────────────────────────────────────────────
# The ladder says WHERE the stand is; it does not say whether this body can GET
# there and still be a defender when the rush arrives. That bites in one regime:
# a defender already DEEPER than the stand — a D at home with the rush still in
# the neutral zone — where the ladder names a stand 10–18 m up-ice, a committed
# skate rather than positioning, so he arrives carrying a full stride of up-ice momentum and
# any cut leaves him reversing while the rush is gone (unbounded, 4.2 m/s of
# up-ice speed at the meet, a mean 10.9 m off his own net).
#
# So an ICE-FRAME approach is bounded by the speed the rendezvous leaves room
# for: close on the rush no faster than you can still be travelling WITH it by
# the time it arrives. Skipped with a layer home behind us — a beaten challenge
# is then a scoring chance rather than a breakaway, which is what licenses D1 to
# step into the rush while D2 holds mid-ice behind him.
#
# Never apply it while the stand RIDES a man, which on a live rush is always.
# The moving-frame route already regulates its own approach, so a bound on top is
# two controllers on one axis: it charges `closing²/2a` for a PIVOT the route no
# longer performs (≈3.8 m of the ≈6 m spare against a 7.5 m/s rush) and places
# the stand within 0.3 m of wherever the defender already stands. A defender
# whose stand is always where he is has no error to close, and the pair produces
# a D backing up 7 m in front of a rush for the length of the ice.
static func _settable_gap(ctx: RoleContext, carrier_pos: Vector3,
		dir_net: Vector3, gap: float, closing: float) -> float:
	if AIRoleHelpers.has_support_behind(ctx):
		return gap
	return AIRoleHelpers.settable_stand_depth(
			ctx, carrier_pos, dir_net, gap, closing)


# ── RUSH_D2: hold mid-ice, take the mid-lane drive ───────────────────────────

static func _decide_d2(ctx: RoleContext) -> RoleDecision:
	var d := RoleDecision.new()
	var read: AIRushRead = ctx.rush_read
	var our_net: Vector3 = ctx.defending_goal_pos

	# The mid-lane drive man: the attacker closest to the middle of the ice who
	# isn't the carrier. He is the one D2 exists to take.
	if AIRoleHelpers.cover_threat(ctx, d, _mid_lane_man_peer(read),
			AIRoleHelpers.resolve_defensive_play_ref(ctx)):
		d.target_position = _clamp_to_house(ctx, d.target_position)
		d.arrive_at_speed = true
		return d

	# Nobody driving the middle: hold the mid-ice post behind RUSH_D1, shaded
	# weak side. Depth is paced off the rush so he stays a layer, not a chaser.
	var axis: Vector3 = read.threat_axis
	if axis == Vector3.ZERO:
		axis = Vector3(0.0, 0.0, -ctx.own_goal_dir)
	var post: Vector3 = our_net - axis * D2_MID_DEPTH_M
	post.x -= ctx.strong_x * D2_WEAK_SHADE_M
	d.target_position = _clamp_to_house(ctx, post)
	return d


# The attacker (excluding the carrier) driving the MIDDLE — the most central one
# inside the mid-lane band, as a peer id. -1 when nobody is in the middle, which
# is D2's cue to hold his post rather than chase a wide man (see
# D2_MID_LANE_HALF_WIDTH_M).
static func _mid_lane_man_peer(read: AIRushRead) -> int:
	var i: int = _mid_lane_man_index(read)
	return read.attackers[i] if i != -1 else -1


static func _mid_lane_man_index(read: AIRushRead) -> int:
	var best: int = -1
	var best_x: float = D2_MID_LANE_HALF_WIDTH_M
	for i: int in read.attackers.size():
		if read.attackers[i] == read.carrier_peer:
			continue
		var lead: Vector3 = read.attacker_leads[i]
		if absf(lead.x) < best_x:
			best_x = absf(lead.x)
			best = i
	return best


# ── Shared ───────────────────────────────────────────────────────────────────

# This bot's stick length — the ladder's unit. Public for the same reason
# should_gap_up is: PRESSURE sizes a gapped-up stand in the same unit, and two
# roles holding "one stick" must not compute two different metres.
static func stick_m(ctx: RoleContext) -> float:
	return maxf(ctx.self_blade_reach, 0.5)


# No rush role ever stands deeper than the house gate (top of the circles) — the
# doorstep belongs to in-zone coverage, which is a different state.
static func _clamp_to_house(ctx: RoleContext, pos: Vector3) -> Vector3:
	return AIRoleHelpers.hold_out_to_house_gate(ctx.defending_goal_pos, pos)


# Argmax over the retreat-line point plus fan candidates toward each receiver's
# feed lane, all at `gap` distance from the carrier. 2-on-1 doctrine is DERIVED
# rather than scripted: the goalie is in both terms, so "the goalie takes the
# shooter, I take the pass" falls out of the max. The numbers read decides when
# the doctrine applies; the fan never infers an odd-man rush from receiver
# danger alone.
#
# KNOWN GAP (carried over): a wide-but-DEEP receiver reads as near-certain
# because the planning keeper has no sharp-angle post play outside the 2 m seal
# zone, so RUSH_D1 respects wide-deep feed lanes more than the textbook says to.
static func _lane_fan_target(ctx: RoleContext, read: AIRushRead,
		carrier_pos: Vector3, our_net: Vector3, dir_net: Vector3,
		gap: float) -> Vector3:
	var receivers: Array[Vector3] = ctx.scratch_opp_receivers
	receivers.clear()
	for i: int in read.attackers.size():
		if read.attackers[i] == read.carrier_peer:
			continue
		receivers.append(read.attacker_leads[i])
	if receivers.is_empty():
		return Vector3.INF

	var teammates: Array[Vector3] = ctx.scratch_teammates
	AIRoleHelpers.collect_teammates_excluding_self(ctx, teammates)
	var our_goalie_pos: Vector3 = AIRoleHelpers.resolve_our_goalie_pos(ctx)

	var self_caps: AISkaterCaps = ctx.caps_by_peer.get(ctx.peer_id)
	var on_line: Vector3 = carrier_pos + dir_net * gap
	var best_pos: Vector3 = on_line
	var best_score: float = LINE_HOLD_MARGIN - AIRoleHelpers.carrier_live_option(
			on_line, carrier_pos, our_net, our_goalie_pos, teammates, receivers,
			INF, ctx.scratch_teammate_caps, self_caps)

	var no_defenders: Array[Vector3] = []
	var a_net: float = atan2(dir_net.z, dir_net.x)
	for i: int in receivers.size():
		# Only leave the shooter for a receiver who is a genuine immediate
		# threat: his finish-if-fed must clear the bar with the keeper predicted
		# over the FEED'S flight. A trailing, low-danger receiver never pulls us
		# off the carrier however open his lane.
		var feed_speed: float = AIActionScoring.expected_pass_speed(
				carrier_pos, receivers[i])
		var feed_flight: float = carrier_pos.distance_to(receivers[i]) \
				/ maxf(feed_speed, 1.0)
		AIActionScoring.resolve_feed_keeper(
				our_goalie_pos, our_net, feed_flight, receivers[i], carrier_pos,
				AIRoleHelpers.our_goalie_hands(ctx), feed_speed, teammates)
		var recv_seal: float = AIActionScoring.derive_post_seal_x_sign(
				receivers[i], our_net)
		var recv_danger: float = AIActionScoring.score_shoot(
				receivers[i], our_net, AIActionScoring.feed_keeper_pos,
				GameRules.NET_HALF_WIDTH,
				no_defenders, AIActionScoring.WRISTER_SHOT_SPEED_M_S,
				AIActionScoring.feed_keeper_unsettled, [], -1.0, false,
				recv_seal, recv_seal != 0.0, 0.0, [],
				AIActionScoring.feed_keeper_hands)
		if recv_danger < LANE_PLAY_DANGER_BAR:
			continue
		var lane_x: float = receivers[i].x - carrier_pos.x
		var lane_z: float = receivers[i].z - carrier_pos.z
		if lane_x * lane_x + lane_z * lane_z < 0.25:
			continue  # receiver on top of the carrier — no lane to play
		var a_delta: float = wrapf(atan2(lane_z, lane_x) - a_net, -PI, PI)
		for f: float in RUSH_LANE_FAN_FRACTIONS:
			var a_off: float = a_delta * f
			if absf(a_off) >= PI * 0.5:
				continue  # never rotate past goal-side of the carrier
			var a: float = a_net + a_off
			var c := Vector3(
					carrier_pos.x + cos(a) * gap, 0.0,
					carrier_pos.z + sin(a) * gap)
			if not AIRoleHelpers.is_legal_position(c):
				continue
			var score: float = -AIRoleHelpers.carrier_live_option(
					c, carrier_pos, our_net, our_goalie_pos, teammates, receivers,
					-best_score, ctx.scratch_teammate_caps, self_caps)
			if score > best_score:
				best_score = score
				best_pos = c
	return best_pos
