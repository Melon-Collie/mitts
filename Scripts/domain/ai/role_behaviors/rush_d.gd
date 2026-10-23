class_name AIRoleRushD

# RUSH_D1 / RUSH_D2 — the rush defense's front layer (TRANS_DEFENSE; 3v3 runs
# RUSH_D1 alone). Design: docs/transition-defense-plan.md §5–§6.
#
#   RUSH_D1 — OWNS THE CARRIER: holds the ladder's gap, angles him off the
#     middle, and attacks once his speed advantage is gone. He keeps the carrier
#     across the blue line, so there is no handoff mid-rush.
#   RUSH_D2 (5v5) — holds MID-ICE and takes the mid-lane drive.
#
# The gap ladder, its ramp cushion and its domain: Scripts/domain/ai/CLAUDE.md →
# "The gap ladder is one ladder". Measure the gap off his REAL position, never a
# velocity-led one: the stand rides him, so a lead double-counts his motion.

# The gap ladder, in stick lengths (stick_m: attribute-scaled blade reach).
const GAP_MIN_STICKS: float = 1.0
const GAP_MAX_STICKS: float = 3.0
# One rung of the ladder: the step every modifier moves the gap by.
const GAP_RUNG_STICKS: float = 1.0
# How far off our net a ridden retreat may end: the paint plus the steering's
# crease buffer, ice no body stands on.
const RETREAT_FINISH_M: float = CreaseRules.ARC_RADIUS + AISteering.CREASE_REPEL_EXTENSION

# A backchecker within this many seconds of the carrier lets the D tighten and
# stand up (docs/5v5-ai-plan.md, backpressure doctrine: "~1–2 s").
const BACKPRESSURE_TIGHTEN_S: float = 1.5

# ── Gap-up trigger (should_gap_up) ───────────────────────────────────────────
# Below this closing speed he isn't coming at pace.
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
# D2 takes: the end-zone dot lane. A wide man is the mid trackers' pickup as he
# cuts in, not D2's to chase off mid-ice.
const D2_MID_LANE_HALF_WIDTH_M: float = GameRules.END_ZONE_FACEOFF_DOT_X
# How far weak-side of centre D2 shades while holding mid-ice.
const D2_WEAK_SHADE_M: float = 2.0

# A threat with no caps of his own is a league skater.
static var _league_caps := AISkaterCaps.new()


static func decide(ctx: RoleContext, slot: int) -> RoleDecision:
	if slot == AIRoleSlots.Slot.RUSH_D2:
		return _decide_d2(ctx)
	return _decide_d1(ctx)


# ── RUSH_D1: own the carrier ─────────────────────────────────────────────────

static func _decide_d1(ctx: RoleContext) -> RoleDecision:
	var d := RoleDecision.new()
	var read: AIRushRead = ctx.rush_read

	var ap: AICarrierApproach = ctx.scratch_carrier_approach
	if not AIDefensiveVerbs.read_carrier_approach(ctx, ap):
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

	# The gap-up's STAND is exempt from the step-up bound, and so is any riding
	# stand (see _settable_gap); a riding route is bounded instead by
	# set_advance_cap.
	var gapping_up: bool = should_gap_up(ctx, read, ap, cushion)
	var ride: Vector3 = AIRoleReads.stand_ride_velocity(ctx)
	if gapping_up:
		gap = minf(stick_m(ctx) * GAP_MIN_STICKS, dist)
	elif ride == Vector3.ZERO:
		gap = minf(_settable_gap(ctx, carrier_pos, dir_net, gap, closing), dist)
	# Stepping UP into the stand, or retreating with it? No dead band needed: the
	# arrival brake it selects has its own hysteresis and speed floor.
	var stepping_up: bool = _depth_along(ctx, carrier_pos, dir_net) > gap

	var stand: Vector3 = AIDefensiveVerbs.carrier_stand(ap, gap)

	# Odd-man: play the pass. The numbers read decides WHEN; the fan finds where.
	if read.numbers != AIRushRead.Numbers.EVEN_OR_UP and ctx.plays_rush_pass_lanes:
		var fan: Vector3 = _lane_fan_target(ctx, read, ap, our_net,
				carrier_pos.distance_to(stand))
		if fan.is_finite():
			stand = fan

	d.target_velocity = ride
	set_retreat_facing(ctx, ap, d, gapping_up, stand)
	if not gapping_up:
		stand = depth_first(ctx, ap, stand, d)
	d.target_position = _clamp_to_house(ctx, stand)
	set_retreat_floor(ctx, ap, d)
	set_advance_cap(ctx, ap, d, gap)
	# The arrival brake only matters with no man to ride (a moving stand stands it
	# down). A retreat is paced rather than braked; a step-up wants the brake,
	# since the approach bound placed that stand as its trigger; the gap-up drives
	# through.
	d.arrive_at_speed = gapping_up or not stepping_up
	return d


# Depth before width. A defender short of his stand's depth must keep pace with
# the carrier down the line and win the rest back before the carrier reaches
# him; only the stride left over can take him across (one speed budget, |v| at
# most his top speed on the retreat he skates), and none of it until he has that pace — from a stand,
# every push goes down the line first. So the stand's offset across the line,
# and the ride's sideways part, are capped at the spare speed, scaled by the
# share of the pace he has, over the time his depth buys: the carrier's soonest
# trip down to it (_carrier_time_to), so speed he carries across the line buys
# him only what turning it costs. Mirroring a carrier who skates wide spends the
# retreat, and a turn then finds the defender level with him. Speed he already
# carries across, the way the cap would send him, he keeps: gliding costs no
# stride, and braking it spends the push the depth needs.
static func depth_first(ctx: RoleContext, ap: AICarrierApproach, stand: Vector3,
		d: RoleDecision) -> Vector3:
	var dir_net: Vector3 = ap.dir_net
	var to_stand: Vector3 = stand - ctx.self_pos
	var short: float = to_stand.x * dir_net.x + to_stand.z * dir_net.z
	if short <= 0.0:
		return stand
	var time_s: float = maxf(_carrier_time_to(ctx, ap,
			maxf(_depth_along(ctx, ap.carrier_pos, dir_net), stick_m(ctx))), 0.05)
	var pace: float = maxf(ap.closing, 0.0) + short / time_s
	var have: float = ctx.self_velocity.x * dir_net.x + ctx.self_velocity.z * dir_net.z
	var v_retreat: float = retreat_max_speed(ctx, d.face_travel)
	var spare: float = sqrt(maxf(v_retreat * v_retreat - pace * pace, 0.0)) \
			* clampf(have / maxf(pace, 0.1), 0.0, 1.0)
	var ride: Vector3 = d.target_velocity
	var ride_along: float = ride.x * dir_net.x + ride.z * dir_net.z
	var ride_across := Vector3(ride.x - dir_net.x * ride_along, 0.0,
			ride.z - dir_net.z * ride_along)
	d.target_velocity = dir_net * ride_along \
			+ ride_across.limit_length(maxf(spare, _carried_toward(ctx, ride_across)))
	var across := Vector3(to_stand.x - dir_net.x * short, 0.0, to_stand.z - dir_net.z * short)
	return ctx.self_pos + dir_net * short \
			+ across.limit_length(maxf(spare, _carried_toward(ctx, across)) * time_s)


# This bot's speed along `dir`'s direction, floored at zero.
static func _carried_toward(ctx: RoleContext, dir: Vector3) -> float:
	var dir_len: float = dir.length()
	if dir_len < 0.001:
		return 0.0
	return maxf((ctx.self_velocity.x * dir.x + ctx.self_velocity.z * dir.z) / dir_len, 0.0)


# How far goal-side of `threat_pos` this bot currently stands, along `dir_net` —
# the same axis and origin the gap is expressed in, so the two are comparable.
static func _depth_along(ctx: RoleContext, threat_pos: Vector3,
		dir_net: Vector3) -> float:
	return (ctx.self_pos.x - threat_pos.x) * dir_net.x \
			+ (ctx.self_pos.z - threat_pos.z) * dir_net.z


# The BASE ladder, in stick lengths, on ice remaining to OUR blue line: 3 at
# their blue line, 2 at the red line, 1 at ours and inside.
#
# The divisor is BLUE_LINE_Z because that is the ice between consecutive rungs.
# Do not double it to match §6's "2 zones" prose: that halves the ramp to
# 2 / 1.5 / 1, and a monotonicity test would not notice.
static func _ladder_sticks(threat_pos: Vector3, own_goal_dir: float) -> float:
	var ice_to_line: float = maxf(
			GameRules.BLUE_LINE_Z - own_goal_dir * threat_pos.z, 0.0)
	return clampf(GAP_MIN_STICKS + ice_to_line / GameRules.BLUE_LINE_Z,
			GAP_MIN_STICKS, GAP_MAX_STICKS)


# The ladder gap in metres plus the ramp cushion, WITHOUT the read's numbers /
# backpressure rungs (a NEUTRAL chaser has no rush posture to read yet). Public
# so the lost-race pre-contain stands where RUSH_D1 will want it.
static func ladder_gap_m(threat_pos: Vector3, own_goal_dir: float,
		stick: float, cushion_m: float) -> float:
	return _with_cushion(_ladder_sticks(threat_pos, own_goal_dir) \
			* maxf(stick, 0.5), cushion_m, threat_pos, own_goal_dir)


# The cushion deepens the stand only as far as RETREAT_FINISH_M, where its race
# finishes; the ladder alone still applies inside.
static func _with_cushion(ladder_m: float, cushion_m: float,
		threat_pos: Vector3, own_goal_dir: float) -> float:
	var dz: float = own_goal_dir * GameRules.GOAL_LINE_Z - threat_pos.z
	var ice_to_finish: float = sqrt(threat_pos.x * threat_pos.x + dz * dz) \
			- RETREAT_FINISH_M
	return maxf(ladder_m, minf(ladder_m + cushion_m, ice_to_finish))


# The ground the threat gains on this body while it builds to his speed, both
# driving flat out down `ap.dir_net` (head_start_on_me). The race finishes where
# a ridden retreat ends (RETREAT_FINISH_M), so the horizon is his trip there and
# the head start never exceeds the ice he has left to it.
static func ramp_cushion_m(ctx: RoleContext, ap: AICarrierApproach,
		threat_peer: int) -> float:
	return head_start_on_me(ctx, ap.dir_net, ap.carrier_vel, ap.net_dist,
			threat_peer, RETREAT_FINISH_M)


# Ends a ridden retreat for a defender still in front of the carrier he owns.
# With a gap he may back off as far as the house gate and no further — inside it,
# backing off only walks him into his own net. Draped on the carrier — within a
# stick, or close enough that building to the carrier's pace from here
# (ramp_cushion_m) ends with him there — he rides him in down to
# RETREAT_FINISH_M. Once level the floor lifts: a beaten defender has to chase.
static func set_retreat_floor(ctx: RoleContext, ap: AICarrierApproach,
		d: RoleDecision) -> void:
	if d.target_velocity == Vector3.ZERO or ap.dir_net == Vector3.ZERO:
		return
	var depth: float = (ctx.self_pos.x - ap.carrier_pos.x) * ap.dir_net.x \
			+ (ctx.self_pos.z - ap.carrier_pos.z) * ap.dir_net.z
	if depth <= 0.0:
		return
	var threat: int = ctx.rush_read.carrier_peer if ctx.rush_read != null else -1
	var draped: bool = depth - stick_m(ctx) <= ramp_cushion_m(ctx, ap, threat)
	d.retreat_floor_center = ctx.defending_goal_pos
	d.retreat_floor_radius_m = RETREAT_FINISH_M if draped \
			else minf(AIZoneCoverage.HOUSE_TOP_DEPTH_M,
					AIRoleReads.xz_distance(ctx.self_pos, ctx.defending_goal_pos))


# Bounds a ridden stand's step toward the carrier, set with the retreat floor:
# the route may command no more speed up-ice than the defender can still turn
# into the carrier's pace before the carrier has eaten the depth he holds past
# `gap` (AILastManDiscipline.approach_speed_cap, the step-up bound with its
# pivot), the carrier's pace being his whole speed turned at our net. The stand
# keeps its place and the ride its lateral; only the charge is bounded. Without
# it the moving-frame closing term walks a stepping-up defender up-ice at a
# carrier who is crossing rather than coming, and the turn down beats him.
static func set_advance_cap(ctx: RoleContext, ap: AICarrierApproach,
		d: RoleDecision, gap: float) -> void:
	if d.retreat_floor_radius_m <= 0.0:
		return
	var depth: float = _depth_along(ctx, ap.carrier_pos, ap.dir_net)
	var pace: float = maxf(ap.closing, Vector2(ap.carrier_vel.x, ap.carrier_vel.z).length())
	# A pace past the retreat's top speed is one he never matches on it, so there
	# is no step to take toward him.
	if pace >= retreat_max_speed(ctx, d.face_travel):
		d.advance_cap_m_s = 0.0
		return
	d.advance_cap_m_s = AILastManDiscipline.approach_speed_cap(depth - gap, pace,
			ctx.self_max_speed, retreat_max_accel(ctx, d.face_travel))


# Which way a defender in front of the carrier he owns skates his retreat
# (RoleDecision.face_travel). He faces the play — where he can play the man —
# unless backpedalling loses the race: the carrier gains more on that retreat
# than the depth he holds past a stick. Then he turns to skate down the ice with
# him, if that concedes less (retreat_gains). Draped within a stick of him, or
# stepping up to him, he faces him to play him. The race is priced down the
# carrier's line to the net, so it says nothing of a route to `stand` that is
# mostly across it: covering sideways, he stays square to the man and crossovers,
# and a cut back reverses his crossover rather than a turn he has to undo.
static func set_retreat_facing(ctx: RoleContext, ap: AICarrierApproach,
		d: RoleDecision, gapping_up: bool, stand: Vector3) -> void:
	var depth: float = _depth_along(ctx, ap.carrier_pos, ap.dir_net)
	if gapping_up or depth <= stick_m(ctx):
		return
	var to_stand := Vector3(stand.x - ctx.self_pos.x, 0.0, stand.z - ctx.self_pos.z)
	var down: float = to_stand.dot(ap.dir_net)
	if down * down < to_stand.length_squared() - down * down:
		return
	var threat: int = ctx.rush_read.carrier_peer if ctx.rush_read != null else -1
	var gains: Vector2 = retreat_gains(ctx, ap.dir_net, ap.carrier_vel, ap.net_dist,
			threat, RETREAT_FINISH_M)
	d.face_travel = gains.x > depth - stick_m(ctx) and gains.y < gains.x


# This bot's top speed and stride on a retreat: skating forward down the ice, or
# backward facing the play (SkaterMovementRules' backward multipliers on his
# own build).
static func retreat_max_speed(ctx: RoleContext, forward: bool) -> float:
	if forward:
		return ctx.self_max_speed
	return ctx.self_max_speed * _self_movement(ctx).backward_max_speed_multiplier


static func retreat_max_accel(ctx: RoleContext, forward: bool) -> float:
	if forward:
		return ctx.self_max_accel
	return ctx.self_max_accel * _self_movement(ctx).backward_thrust_multiplier


static func _self_movement(ctx: RoleContext) -> SkaterMovementRules.MovementConfig:
	var caps: AISkaterCaps = ctx.caps_by_peer.get(ctx.peer_id)
	return caps.movement if caps != null else _league_caps.movement


# The ground the threat gains on each of a defender's two retreats (head_start_on_me):
# x backpedalling facing the play, y turned and skating down the ice. Each first
# turns his body from where it points now, at his facing turn rate.
static func retreat_gains(ctx: RoleContext, dir_net: Vector3, threat_vel: Vector3,
		net_dist: float, threat_peer: int, finish_m: float) -> Vector2:
	var facing: Vector2 = _self_facing(ctx, -dir_net)
	return Vector2(
			_threat_gain(ctx, dir_net, threat_vel, net_dist, threat_peer, finish_m,
					retreat_max_speed(ctx, false), retreat_max_accel(ctx, false),
					_turn_s(ctx, facing, -dir_net)),
			_threat_gain(ctx, dir_net, threat_vel, net_dist, threat_peer, finish_m,
					retreat_max_speed(ctx, true), retreat_max_accel(ctx, true),
					_turn_s(ctx, facing, dir_net)))


# Where this bot's body points; `fallback` when it cannot be read.
static func _self_facing(ctx: RoleContext, fallback: Vector3) -> Vector2:
	var me: SkaterNetworkState = ctx.snapshot.skater_states.get(ctx.peer_id) \
			if ctx.snapshot != null else null
	if me == null or me.facing.length_squared() < 0.0001:
		return Vector2(fallback.x, fallback.z)
	return me.facing


# How long turning the body from `facing` to `dir` takes at his facing turn rate.
static func _turn_s(ctx: RoleContext, facing: Vector2, dir: Vector3) -> float:
	return absf(facing.angle_to(Vector2(dir.x, dir.z))) \
			/ maxf(ctx.self_facing_turn_rate, 0.1)


# ramp_cushion_m's race for any threat: `dir_net` his line to our net,
# `net_dist` his ice to it, finishing `finish_m` off the net. Also what "behind
# me" means to an offensive station (race_depth_to_net), finishing at the gate.
#
# Both drive flat out down the line (AIStrideRamp.head_start; our opposing
# momentum braked out first), the threat from the better of two starts: his pace
# along the line now, or his whole speed turned onto it. A turn keeps a skater's
# speed and swings it at his edge-limited rate (SkaterMovementRules), so a man
# crossing the ice at speed has that speed toward our net a moment later; the
# turn costs him the ground the arc gives up against the straight run.
# `threat_peer` -1 (a loose puck) prices a league skater. A carrier is priced at
# his free top speed — a slight over-read, in the safe direction. We are priced
# skating straight there at our forward stride, with no turn: the cushion a
# step-up reads, which a straight race cannot price on the backward caps (a
# carrier bursting from a stick away goes through the defender, not past him in
# a race), so retreat_gains prices the two real retreats separately.
static func head_start_on_me(ctx: RoleContext, dir_net: Vector3,
		threat_vel: Vector3, net_dist: float, threat_peer: int,
		finish_m: float = AIZoneCoverage.HOUSE_TOP_DEPTH_M) -> float:
	return _threat_gain(ctx, dir_net, threat_vel, net_dist, threat_peer, finish_m,
			ctx.self_max_speed, ctx.self_max_accel, 0.0)


static func _threat_gain(ctx: RoleContext, dir_net: Vector3, threat_vel: Vector3,
		net_dist: float, threat_peer: int, finish_m: float, self_vmax: float,
		self_accel: float, self_turn_s: float) -> float:
	var ice_to_finish: float = net_dist - finish_m
	if ice_to_finish <= 0.0:
		return 0.0
	var caps: AISkaterCaps = ctx.caps_by_peer.get(threat_peer) \
			if threat_peer != -1 else null
	if caps == null:
		caps = _league_caps
	var self_v: float = ctx.self_velocity.x * dir_net.x \
			+ ctx.self_velocity.z * dir_net.z
	var along: float = threat_vel.x * dir_net.x + threat_vel.z * dir_net.z
	var gained: float = _head_start_from(along, caps, self_v, self_vmax, self_accel,
			self_turn_s, ice_to_finish)
	var speed: float = Vector2(threat_vel.x, threat_vel.z).length()
	var turn_s: float = _turn_onto_line_s(caps, along, speed)
	if turn_s < INF:
		gained = maxf(gained, _head_start_from(speed, caps, self_v, self_vmax, self_accel,
				self_turn_s, ice_to_finish) - speed * turn_s)
	return minf(gained, ice_to_finish)


# What turning his whole `speed` onto the line costs a man moving `along` it, in
# seconds of straight running: the arc gives up speed·(θ − sin θ)/ω of ground at
# his edge-limited turn rate ω (SkaterMovementRules). INF when there is no turn
# worth making.
static func _turn_onto_line_s(caps: AISkaterCaps, along: float, speed: float) -> float:
	if speed <= along + 0.1:
		return INF
	var off_line: float = acos(clampf(along / speed, -1.0, 1.0))
	var turn_rate: float = minf(caps.movement.turn_accel * caps.lateral_grip / speed,
			caps.movement.max_turn_rate)
	return (off_line - sin(off_line)) / turn_rate


# The soonest the carrier covers `dist` toward our net: from his pace down the
# line, or with his whole speed turned onto it (head_start_on_me's two starts).
static func _carrier_time_to(ctx: RoleContext, ap: AICarrierApproach, dist: float) -> float:
	var peer: int = ctx.rush_read.carrier_peer if ctx.rush_read != null else -1
	var caps: AISkaterCaps = ctx.caps_by_peer.get(peer) if peer != -1 else null
	if caps == null:
		caps = _league_caps
	var t: float = AIStrideRamp.time_to_cover(ap.closing, dist, caps.max_speed, caps.max_accel)
	var speed: float = Vector2(ap.carrier_vel.x, ap.carrier_vel.z).length()
	var turn_s: float = _turn_onto_line_s(caps, ap.closing, speed)
	if turn_s < INF:
		t = minf(t, turn_s + AIStrideRamp.time_to_cover(speed, dist, caps.max_speed,
				caps.max_accel))
	return t


# AIStrideRamp.head_start for a threat starting down the line at `lead_v`, over
# his trip to the finish.
static func _head_start_from(lead_v: float, caps: AISkaterCaps, self_v: float,
		self_vmax: float, self_accel: float, self_turn_s: float,
		ice_to_finish: float) -> float:
	var horizon: float = AIStrideRamp.time_to_cover(
			maxf(lead_v, 0.0), ice_to_finish, caps.max_speed, caps.max_accel)
	return AIStrideRamp.head_start(lead_v, caps.max_speed, caps.max_accel,
			self_v, self_vmax, self_accel,
			AIArrival.REVERSAL_BRAKE_DECEL_M_S2, horizon, self_turn_s)


# An attacker's distance from our net less the ground he gains on us while we
# build to his pace — "behind me" as a race, since a man level with a standing
# station at speed is past it by the time it moves.
static func race_depth_to_net(ctx: RoleContext, pid: int) -> float:
	var s: SkaterNetworkState = ctx.snapshot.skater_states.get(pid)
	if s == null:
		return INF
	var our_net: Vector3 = ctx.defending_goal_pos
	var d: float = AIRoleReads.xz_distance(s.position, our_net)
	if d < 0.001:
		return 0.0
	var dir_net := Vector3((our_net.x - s.position.x) / d, 0.0,
			(our_net.z - s.position.z) / d)
	return maxf(d - head_start_on_me(ctx, dir_net, s.velocity, d,
			pid), 0.0)


# The gap ladder plus its modifiers, in metres. The modifiers run BOTH ways and
# read the team's shared numbers, never a private depth scan.
static func _gap_for(ctx: RoleContext, read: AIRushRead, carrier_pos: Vector3,
		cushion_m: float) -> float:
	var sticks: float = _ladder_sticks(carrier_pos, ctx.own_goal_dir)

	# EVEN_OR_UP is licence to challenge; DOWN_TWO_PLUS buys time for the
	# backcheck. DOWN_ONE deliberately does NOT widen: an odd-man concession is
	# LATERAL (the lane fan), never deeper, or a 2-on-1 becomes a breakaway.
	if read.numbers == AIRushRead.Numbers.EVEN_OR_UP:
		sticks -= GAP_RUNG_STICKS
	elif read.numbers == AIRushRead.Numbers.DOWN_TWO_PLUS:
		sticks += GAP_RUNG_STICKS

	if read.backpressure_s < BACKPRESSURE_TIGHTEN_S:
		sticks -= GAP_RUNG_STICKS

	sticks = clampf(sticks, GAP_MIN_STICKS, GAP_MAX_STICKS)
	return _with_cushion(sticks * stick_m(ctx), cushion_m, carrier_pos,
			ctx.own_goal_dir)


# Is his speed advantage gone — close to stick range and attack? True when:
#   · he is not advancing on our net and cannot build a head start on us (the
#     ladder has no domain) — a man crossing the ice at speed is not regrouping:
#     a turn puts that speed at our net (head_start_on_me) — or is steered to
#     the wall;
#   · he is not coming at pace AND cannot build it past us (cushion under a
#     stick);
#   · the retreat cannot hold a gap (the cushion eats all but a stick of my
#     depth) and I stand in his lane — off it, I keep retreating.
# Shared with AIRolePressure so both carrier-owners agree at the handoff. See
# Scripts/domain/ai/CLAUDE.md → "Pace enters through the stride ramp".
static func should_gap_up(ctx: RoleContext, read: AIRushRead,
		ap: AICarrierApproach, cushion_m: float) -> bool:
	# Outnumbered, being beaten is a goal rather than a scoring chance.
	if read.numbers == AIRushRead.Numbers.DOWN_TWO_PLUS:
		return false
	var stick: float = stick_m(ctx)
	if ap.closing < AIRushRead.REGROUP_CLOSING_M_S and cushion_m < stick:
		return true
	if GameRules.INNER_HALF_WIDTH - absf(ap.carrier_pos.x) < GAP_UP_WALL_M:
		return true
	if ap.closing < GAP_UP_CLOSING_M_S and cushion_m < stick:
		return true
	var dx: float = ctx.self_pos.x - ap.carrier_pos.x
	var dz: float = ctx.self_pos.z - ap.carrier_pos.z
	var depth: float = dx * ap.dir_net.x + dz * ap.dir_net.z
	var off_lane: float = absf(dx * ap.dir_net.z - dz * ap.dir_net.x)
	return depth < cushion_m + stick and off_lane <= stick


# ── Step-up discipline ───────────────────────────────────────────────────────
# A defender deeper than his stand must not charge it: the ladder can name a
# stand 10–18 m up-ice, and he would arrive carrying up-ice momentum into the
# rush. So an ICE-FRAME approach closes no faster than he can still be
# travelling WITH the rush when it arrives (AILastManDiscipline.settable_stand_depth).
# Skipped with a layer home behind us, where a beaten challenge is a scoring
# chance rather than a breakaway.
#
# Never apply it while the stand RIDES a man: the moving-frame route already
# regulates its own approach, and the bound on top pins the stand to wherever
# the defender stands.
static func _settable_gap(ctx: RoleContext, carrier_pos: Vector3,
		dir_net: Vector3, gap: float, closing: float) -> float:
	if AILastManDiscipline.has_support_behind(ctx):
		return gap
	return AILastManDiscipline.settable_stand_depth(
			ctx, carrier_pos, dir_net, gap, closing)


# ── RUSH_D2: hold mid-ice, take the mid-lane drive ───────────────────────────

static func _decide_d2(ctx: RoleContext) -> RoleDecision:
	var d := RoleDecision.new()
	var read: AIRushRead = ctx.rush_read
	var our_net: Vector3 = ctx.defending_goal_pos

	if AIDefensiveVerbs.cover_threat(ctx, d, _mid_lane_man_peer(read),
			AIRoleReads.resolve_defensive_play_ref(ctx)):
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

# This bot's stick length — the ladder's unit. Public so PRESSURE's "one stick"
# is the same metres.
static func stick_m(ctx: RoleContext) -> float:
	return maxf(ctx.self_blade_reach, 0.5)


# No rush role ever stands deeper than the house gate (top of the circles) — the
# doorstep belongs to in-zone coverage, which is a different state.
static func _clamp_to_house(ctx: RoleContext, pos: Vector3) -> Vector3:
	return AILastManDiscipline.hold_out_to_house_gate(ctx.defending_goal_pos, pos)


# Argmax over the retreat-line point plus fan candidates toward each dangerous
# receiver's feed lane, all `gap` from the carrier, each priced by what it takes
# from the carrier's best option (AIDefensiveVerbs.carrier_best_option) at the
# stand's ride. The 2-on-1 doctrine is derived rather than scripted: the goalie
# is in every option, so "the goalie takes the shooter, I take the pass" falls
# out of the max.
static func _lane_fan_target(ctx: RoleContext, read: AIRushRead,
		ap: AICarrierApproach, our_net: Vector3, gap: float) -> Vector3:
	var carrier_pos: Vector3 = ap.carrier_pos
	var dir_net: Vector3 = ap.dir_net
	var receivers: Array[Vector3] = ctx.scratch_opp_receivers
	receivers.clear()
	for i: int in read.attackers.size():
		if read.attackers[i] == read.carrier_peer:
			continue
		receivers.append(read.attacker_leads[i])
	if receivers.is_empty():
		return Vector3.INF

	var teammates: Array[Vector3] = ctx.scratch_teammates
	AIRoleReads.collect_teammates_excluding_self(ctx, teammates)
	var our_goalie_pos: Vector3 = AIRoleReads.resolve_our_goalie_pos(ctx)
	var poss: AIPossessionValue = AIRoleReads.defence_possession(ctx, teammates)
	var bases: Array[float] = ctx.scratch_option_bases
	AIDefensiveVerbs.carrier_option_bases(poss, carrier_pos, ap.carrier_vel,
			our_goalie_pos, receivers, bases)

	var self_caps: AISkaterCaps = ctx.caps_by_peer.get(ctx.peer_id)
	var ride: Vector3 = AIRoleReads.stand_ride_velocity(ctx)
	var on_line: Vector3 = carrier_pos + dir_net * gap
	var best_pos: Vector3 = on_line
	var best_score: float = LINE_HOLD_MARGIN - AIDefensiveVerbs.carrier_best_option(
			poss, on_line, ride, self_caps, carrier_pos, ap.carrier_vel, our_goalie_pos,
			receivers, bases)

	var a_net: float = atan2(dir_net.z, dir_net.x)
	for i: int in receivers.size():
		# Only leave the shooter for a genuine immediate threat: his one-timer off
		# the feed, our keeper square on the carrier as he stands, must clear the
		# bar.
		var recv_danger: float = AIShotValue.feed(carrier_pos, receivers[i],
				AIPuckLane.expected_pass_speed(carrier_pos, receivers[i]), our_net,
				our_goalie_pos, true)
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
			if not AIStationSearch.is_legal_position(c):
				continue
			var score: float = -AIDefensiveVerbs.carrier_best_option(
					poss, c, ride, self_caps, carrier_pos, ap.carrier_vel, our_goalie_pos,
					receivers, bases)
			if score > best_score:
				best_score = score
				best_pos = c
	return best_pos
