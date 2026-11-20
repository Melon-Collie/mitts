class_name AIArrival

# The momentum-honest arrival clock the bots share: how long a body carrying
# its current velocity takes to reach a point, routed around the nets, or to
# meet another body. A leaf — it reads GameRules, SkaterMovementRules,
# AIStrideRamp and AINetObstacle only — so the scorer and AICarrySpace can both
# depend on it (test_scoring_split_stays_acyclic.gd).

# Reference (league-average) top skating speed, shared with
# SkaterController.max_speed via GameRules. A FALLBACK: a read with a peer in
# view resolves his real top speed through AISkaterCaps (caps_by_peer). The
# sites that price at this reference by design — the realization discount and
# the counter-cover teammate races — say so at the site.
const SKATER_REF_SPEED_M_S: float = GameRules.DEFAULT_SKATER_MAX_SPEED_M_S

# Floor (m/s) for momentum-adverse `time_to_arrive` returns, so reverse
# candidates get finite (large) ETAs rather than infinite ones.
const MIN_TRAVEL_SPEED_M_S: float = 1.0

# League-default all-direction thrust — the redirect authority a caps-less
# time_to_arrive caller assumes for the cross-momentum shed. Per-bot callers
# pass the skater's real AISkaterCaps.max_accel instead. Mirrors
# SkaterController.thrust.
const SHED_ACCEL_DEFAULT_M_S2: float = GameRules.DEFAULT_SKATER_THRUST_M_S2

# ── Calibrated phase model ─────────────────────────────────────────────────────
# The measured controller (SkaterMovementRules at the tick driven by the bot's
# own steering — the velocity-matched seek, the pivot brake or its stance cut,
# the stance carve; tests/unit/ai/test_time_to_arrive_calibration.gd holds the
# model against simulated arrivals) decomposes into:
#
#   TURN — cross-momentum past the seek's free band (REDIRECT's) is carved
#     round onto the point on the loaded stance's edges (turn_accel × grip ×
#     the stance's grip) while the speed bleeds at the scrape, the glide and
#     the stick's share along travel: a skid where the seek points it behind
#     the travel, a stride where ahead.
#     Constant lateral authority over a constant bleed is a logarithmic spiral,
#     so the carve is closed form. The bearing swings while the body travels,
#     so a second carve takes up what the first left. A point inside the
#     carve's curl is flown past, and what is left is a REVERSAL.
#   REDIRECT — cross-momentum the carve leaves beyond what the seek sheds for
#     free: only the EXCESS above VM_FREE_SHED_M_S pays, at the measured net
#     shed rate.
#   REVERSAL — velocity pointed away brakes out at the brake key's real
#     stop decel and gives back the ground lost while braking.
#   PURSUIT — the stride's own ramp at the NET push the movement model
#     delivers after glide losses: constant accel up to the power knee,
#     constant power above it (AIStrideRamp), up to top speed,
#     then cruise. A standing start genuinely pays ~0.5 s over a plain
#     dist/speed read; a full-speed head-on drive pays nothing.
#
# Never collapse this to `effective = ref + v_along` with the shed as a pure
# delay: that credits a full-speed closer with up to DOUBLE top speed and hands
# standing starts top speed for free. The one place the clock can be off by
# more than ERROR_FRAC is the edge between a short cut at speed the carve just
# makes and one it just flies past, where a few tenths of a metre decide a
# loop: up to ~2× either way there.

# The clock's error against the live controller on the clean families: a share
# of the trip, with a floor (test_time_to_arrive_calibration.gd holds it).
const ERROR_FRAC: float = 0.25
const ERROR_FLOOR_S: float = 0.18

# Cross speed the velocity-matched seek redirects for free (costs no time).
# Measured.
const VM_FREE_SHED_M_S: float = 2.0
# Net shed rate for cross speed beyond the free band. Measured.
const VM_SHED_DECEL_M_S2: float = 11.0
# Brake-key deceleration for reversals — the hockey stop itself.
const REVERSAL_BRAKE_DECEL_M_S2: float = GameRules.DEFAULT_SKATER_STOP_DECEL_M_S2
# Within a blade's contact of a point the body has arrived at it: the clock's
# arrival, which the calibration measures to.
const ARRIVE_CONTACT_M: float = 0.5
# Carves the TURN takes: the first onto the bearing at the start, the second
# onto where the first left the point.
const TURN_CARVES: int = 2
# The league body the carve's stance edges, scrape and glide are read from;
# grip, thrust and top speed come in per call.
static var _body: SkaterMovementRules.MovementConfig = SkaterMovementRules.league_config()


# A first carve (first_carve), filled in place by the caller's scratch.
class Carve:
	var exit_pos: Vector3 = Vector3.ZERO
	var exit_vel: Vector3 = Vector3.ZERO
	var time: float = 0.0


# `ref_speed_m_s` is the actor's flat skating speed; `accel_m_s2` its all-direction
# thrust (Acceleration-scaled) — both default to league references so cross-player
# callers (opponent / teammate ETA, the loose-puck election that must stay
# consistent across all bots) keep the shared baseline. A bot estimating ITS OWN
# arrival passes its attribute-scaled top speed AND max_accel (a higher-Acceleration
# build redirects and ramps faster, so it reaches an off-axis cut sooner).
#
# NET-AWARE: a route whose straight line crosses a cage prices the real
# around-the-cage detour (_time_to_arrive_routed). The common open-ice case
# pays only the cheap z-gate below (a segment that never reaches the goal line
# cannot cross a cage).
static func time_to_arrive(from_pos: Vector3, dest: Vector3,
		from_velocity: Vector3, ref_speed_m_s: float = SKATER_REF_SPEED_M_S,
		accel_m_s2: float = SHED_ACCEL_DEFAULT_M_S2,
		lateral_grip: float = 1.0) -> float:
	# Route only when the segment passes THROUGH a cage — an endpoint inside
	# the inflated frame box is a conceptual "at the net" destination (race-
	# home reads target the net center as their home proxy; a pinned body
	# starts against the mesh) and keeps the direct model.
	if maxf(absf(from_pos.z), absf(dest.z)) \
			>= GameRules.GOAL_LINE_Z - AINetObstacle.CARRY_NET_CLEAR_MARGIN_M \
			and AINetObstacle.carry_path_blocked_by_net(from_pos, dest) \
			and not AINetObstacle.point_in_cage_box(from_pos) \
			and not AINetObstacle.point_in_cage_box(dest):
		return _time_to_arrive_routed(
				from_pos, dest, from_velocity, ref_speed_m_s, accel_m_s2,
				lateral_grip)
	return _time_to_arrive_direct(
			from_pos, dest, from_velocity, ref_speed_m_s, accel_m_s2,
			lateral_grip)


# ETA for the BLADE to touch `point`, rather than for the body to land on it.
# The destination is the nearest spot on the reach circle around `point` — the
# path point pulled `reach` back along the approach line — so the last stick-
# length is never charged as travel. Already inside reach is 0: the stick is on
# it now.
static func reach_eta(from_pos: Vector3, point: Vector3, vel: Vector3,
		max_speed: float, accel: float, reach: float) -> float:
	if reach <= 0.0:
		return time_to_arrive(from_pos, point, vel, max_speed, accel)
	var dx: float = point.x - from_pos.x
	var dz: float = point.z - from_pos.z
	var d: float = sqrt(dx * dx + dz * dz)
	if d <= reach:
		return 0.0
	var f: float = (d - reach) / d
	return time_to_arrive(from_pos,
			Vector3(from_pos.x + dx * f, point.y, from_pos.z + dz * f),
			vel, max_speed, accel)


# Extra lateral/depth clearance the net-aware ETA's corner waypoints keep
# beyond the inflated frame — a body's half-width, the corner is skated
# around, not clipped (see _time_to_arrive_routed).
const NET_ROUTE_CLEAR_M: float = 0.4


# The around-the-cage route: the best of four waypoints — beside either post at
# mid-cage depth, the behind-net alley, and the front lip — which together give
# every crossing geometry its small detour. Each leg runs the calibrated direct
# model, carrying pace through the waypoint. Legs are not re-checked for
# blockage: the waypoints sit a body's clearance outside the inflated frame.
static func _time_to_arrive_routed(from_pos: Vector3, dest: Vector3,
		from_velocity: Vector3, ref_speed_m_s: float,
		accel_m_s2: float, lateral_grip: float = 1.0) -> float:
	return _time_via(from_pos, cage_waypoint(from_pos, dest, from_velocity, ref_speed_m_s,
			accel_m_s2, lateral_grip), dest, from_velocity, ref_speed_m_s, accel_m_s2,
			lateral_grip)


# The waypoint of the quickest route round the cage from `from_pos` to `dest`
# (see _time_to_arrive_routed). A carrier round his OWN cage (`carrier_own_goal_dir`,
# 0 for anyone else) skates the side and front waypoints at the edge of the
# keep-out of his own mouth (AINetObstacle.own_mouth_keep_out_depth), so the puck
# on his stick cannot reach it on the way.
static func cage_waypoint(from_pos: Vector3, dest: Vector3, from_velocity: Vector3,
		ref_speed_m_s: float, accel_m_s2: float, lateral_grip: float = 1.0,
		carrier_own_goal_dir: float = 0.0) -> Vector3:
	# The cage being crossed is on the side the route actually reaches.
	var s: float = signf(from_pos.z) \
			if absf(from_pos.z) >= absf(dest.z) else signf(dest.z)
	var side_x: float = GameRules.NET_BACK_HALF_WIDTH \
			+ AINetObstacle.CARRY_NET_CLEAR_MARGIN_M + NET_ROUTE_CLEAR_M
	var front_in: float = AINetObstacle.CARRY_NET_CLEAR_MARGIN_M + NET_ROUTE_CLEAR_M
	if carrier_own_goal_dir != 0.0 and s == carrier_own_goal_dir:
		side_x = maxf(side_x,
				AINetObstacle.OWN_MOUTH_HALF_WIDTH_M + AINetObstacle.OWN_MOUTH_KEEP_OUT_M)
		front_in = maxf(front_in,
				AINetObstacle.OWN_MOUTH_DEPTH_M + AINetObstacle.OWN_MOUTH_KEEP_OUT_M)
	var mid_z: float = s * (GameRules.GOAL_LINE_Z + GameRules.NET_DEPTH * 0.5)
	var back_z: float = s * (GameRules.GOAL_LINE_Z + GameRules.NET_DEPTH \
			+ AINetObstacle.CARRY_NET_CLEAR_MARGIN_M + NET_ROUTE_CLEAR_M)
	var front_z: float = s * (GameRules.GOAL_LINE_Z - front_in)
	var best: float = INF
	var best_wp: Vector3 = dest
	for wp: Vector3 in [
			Vector3(-side_x, 0.0, mid_z), Vector3(side_x, 0.0, mid_z),
			Vector3(0.0, 0.0, back_z), Vector3(0.0, 0.0, front_z)]:
		var t: float = _time_via(from_pos, wp, dest, from_velocity, ref_speed_m_s,
				accel_m_s2, lateral_grip)
		if t < best:
			best = t
			best_wp = wp
	return best_wp


# The two direct legs from_pos → wp → dest, pace carried through the waypoint.
static func _time_via(from_pos: Vector3, wp: Vector3, dest: Vector3,
		from_velocity: Vector3, ref_speed_m_s: float, accel_m_s2: float,
		lateral_grip: float) -> float:
	var vmax: float = maxf(ref_speed_m_s, MIN_TRAVEL_SPEED_M_S)
	var t1: float = _time_to_arrive_direct(
			from_pos, wp, from_velocity, ref_speed_m_s, accel_m_s2, lateral_grip)
	var to_dest: Vector3 = dest - wp
	to_dest.y = 0.0
	var v_wp := Vector3.ZERO
	if to_dest.length_squared() > 0.0001:
		v_wp = to_dest.normalized() * minf(
				from_pos.distance_to(wp) / maxf(t1, 0.001), vmax)
	return t1 + _time_to_arrive_direct(
			wp, dest, v_wp, ref_speed_m_s, accel_m_s2, lateral_grip)


# The calibrated direct-route travel model (no net awareness — the public
# time_to_arrive gates and routes; the routed legs call this).
static func _time_to_arrive_direct(from_pos: Vector3, dest: Vector3,
		from_velocity: Vector3, ref_speed_m_s: float = SKATER_REF_SPEED_M_S,
		accel_m_s2: float = SHED_ACCEL_DEFAULT_M_S2,
		lateral_grip: float = 1.0) -> float:
	var dx: float = dest.x - from_pos.x
	var dz: float = dest.z - from_pos.z
	if dx * dx + dz * dz < 0.000001:
		return 0.0
	var vmax: float = maxf(ref_speed_m_s, MIN_TRAVEL_SPEED_M_S)
	var grip: float = maxf(lateral_grip, 0.001)
	var vx: float = from_velocity.x
	var vz: float = from_velocity.z
	var t: float = 0.0
	for _carve: int in TURN_CARVES:
		var c: Vector4 = _carve_from(vx, vz, dx, dz, vmax, accel_m_s2, grip)
		if c.z < 0.0:
			break
		t += c.z
		var after: Vector4 = _after_carve(vx, vz, dx, dz, c)
		dx = after.x
		dz = after.y
		vx = after.z
		vz = after.w
	var dist: float = sqrt(dx * dx + dz * dz)
	if dist < 0.001:
		return t
	var inv: float = 1.0 / dist
	var v_along: float = vx * dx * inv + vz * dz * inv
	var v_perp: float = sqrt(maxf(0.0, vx * vx + vz * vz - v_along * v_along))
	# REDIRECT: only the cross momentum the seek can't shed for free pays,
	# scaled by this build's edge grip — the turn authority SkaterMovementRules
	# scales in the real body (turning redirects momentum on the edges; the
	# stride plays no part, and grip never limits the ramp below).
	t += maxf(0.0, v_perp - VM_FREE_SHED_M_S * grip) / (VM_SHED_DECEL_M_S2 * grip)
	var r: float = dist
	var v0: float = v_along
	if v0 < 0.0:
		# Reversal: brake the retreat out, giving back the ground lost while
		# braking; the pursuit then ramps from rest. (Brake friction is
		# attribute-flat — the brake key, not thrust.)
		t += -v0 / REVERSAL_BRAKE_DECEL_M_S2
		r += v0 * v0 / (2.0 * REVERSAL_BRAKE_DECEL_M_S2)
		v0 = 0.0
	return t + AIStrideRamp.time_to_cover(v0, r, vmax, accel_m_s2)



# One carve of the TURN, from velocity (vx, vz) onto the point (dx, dz) off:
# Vector4(ahead, aside, time, exit speed), `ahead` along the entry heading and
# `aside` toward the point's side of it. Time < 0: no carve — too slow to have a
# heading, the point behind him (a REVERSAL), cross speed inside the seek's free
# band (REDIRECT), or a point the travel already passes within contact of.
static func _carve_from(vx: float, vz: float, dx: float, dz: float, vmax: float,
		accel_m_s2: float, grip: float) -> Vector4:
	var speed_sq: float = vx * vx + vz * vz
	var to_dest: float = sqrt(dx * dx + dz * dz)
	if speed_sq <= SkaterMovementRules.GRIP_MIN_SPEED * SkaterMovementRules.GRIP_MIN_SPEED \
			or to_dest < 0.001:
		return Vector4(0.0, 0.0, -1.0, 0.0)
	var speed: float = sqrt(speed_sq)
	var cos_off: float = (vx * dx + vz * dz) / (speed * to_dest)
	var sin_off: float = absf((vx * dz - vz * dx) / (speed * to_dest))
	if cos_off <= 0.0 or speed * sin_off <= VM_FREE_SHED_M_S * grip \
			or to_dest * sin_off <= ARRIVE_CONTACT_M:
		return Vector4(0.0, 0.0, -1.0, 0.0)
	# Carved from no faster than top speed, as the ramp prices: no return then
	# beats the straight distance over vmax (the callers' exact prunes).
	var v: float = minf(speed, vmax)
	# The edges: the stance's authority, the turn-rate ceiling binding at low
	# speed, and the scrape for what it holds past the upright edges.
	var upright: float = minf(GameRules.DEFAULT_SKATER_TURN_ACCEL_M_S2 * grip,
			GameRules.DEFAULT_SKATER_MAX_TURN_RATE_RAD_S * v)
	var lateral: float = minf(
			GameRules.DEFAULT_SKATER_TURN_ACCEL_M_S2 * grip * _body.stance_grip_mult,
			GameRules.DEFAULT_SKATER_MAX_TURN_RATE_RAD_S * v)
	# The seek's stick (the bearing less the cross drift over vmax) along
	# travel: behind it is the skid, ahead of it the stance's stride.
	var drift: float = v * sin_off / vmax
	var along: float = (cos_off - drift * sin_off) / sqrt(1.0 + drift * drift)
	var bleed: float = _body.friction + _body.friction_drag * v \
			+ _body.stance_scrape * (lateral - upright)
	if along < 0.0:
		bleed -= along * REVERSAL_BRAKE_DECEL_M_S2 * _body.reverse_skid_fraction
	else:
		bleed -= along * minf(accel_m_s2, accel_m_s2 \
				* GameRules.DEFAULT_SKATER_POWER_KNEE_M_S / v) * _body.stance_stride_mult
	# The spiral through the heading change `off`: speed v·e^(−bleed·φ/lateral)
	# at heading φ, radius speed²/lateral.
	var off: float = atan2(sin_off, cos_off)
	var c: float = 2.0 * bleed / lateral
	var e: float = exp(-c * off)
	var kept: float = sqrt(e)
	var arm: float = v * v / lateral / (1.0 + c * c)
	return Vector4(arm * (e * (sin_off - c * cos_off) + c),
			arm * (1.0 - e * (c * sin_off + cos_off)),
			v * off / lateral if absf(bleed) < 0.0001 else v * (1.0 - kept) / bleed,
			minf(v * kept, vmax))


# What a carve `c` (_carve_from) leaves: Vector4(the point's x, z off the body,
# the body's velocity x, z). He leaves it on the bearing he started it on.
static func _after_carve(vx: float, vz: float, dx: float, dz: float, c: Vector4) -> Vector4:
	var speed: float = sqrt(vx * vx + vz * vz)
	var to_dest: float = sqrt(dx * dx + dz * dz)
	var hx: float = vx / speed
	var hz: float = vz / speed
	var side: float = signf(vx * dz - vz * dx)
	return Vector4(dx - (c.x * hx - c.y * hz * side), dz - (c.x * hz + c.y * hx * side),
			dx / to_dest * c.w, dz / to_dest * c.w)


# Where the clock's first carve from `from_pos` toward `dest` leaves the body:
# filled into `out` (the exit, its velocity, and its time), true when the clock
# carves at all; false leaves `out` at the start, still, at time 0. The carve
# time_to_arrive prices (_carve_from), so a reader walking the route and the
# clock cannot disagree on it.
static func first_carve(out: Carve, from_pos: Vector3, dest: Vector3,
		from_velocity: Vector3, ref_speed_m_s: float = SKATER_REF_SPEED_M_S,
		accel_m_s2: float = SHED_ACCEL_DEFAULT_M_S2, lateral_grip: float = 1.0) -> bool:
	var dx: float = dest.x - from_pos.x
	var dz: float = dest.z - from_pos.z
	var c: Vector4 = _carve_from(from_velocity.x, from_velocity.z, dx, dz,
			maxf(ref_speed_m_s, MIN_TRAVEL_SPEED_M_S), accel_m_s2, maxf(lateral_grip, 0.001))
	if c.z < 0.0:
		out.exit_pos = from_pos
		out.exit_vel = from_velocity
		out.time = 0.0
		return false
	var after: Vector4 = _after_carve(from_velocity.x, from_velocity.z, dx, dz, c)
	out.exit_pos = Vector3(dest.x - after.x, from_pos.y, dest.z - after.y)
	out.exit_vel = Vector3(after.z, 0.0, after.w)
	out.time = c.z
	return true

# How long (s, at most `horizon_s`) a skater at `pos` carrying `vel` skates before
# his body meets one of `others`, each dead-reckoned on his own velocity, their
# centres `contact_m` apart then: nobody skates through a body. A man he is
# already against counts only while he is still skating into him.
static func body_contact_time(pos: Vector3, vel: Vector3, others: Array[Vector3],
		other_vels: Array[Vector3], contact_m: float, horizon_s: float) -> float:
	var t_c: float = horizon_s
	var n: int = others.size()
	if other_vels.size() != n:
		return t_c
	var contact_sq: float = contact_m * contact_m
	for i: int in n:
		var rx: float = pos.x - others[i].x
		var rz: float = pos.z - others[i].z
		var wx: float = vel.x - other_vels[i].x
		var wz: float = vel.z - other_vels[i].z
		var b: float = rx * wx + rz * wz
		if b >= 0.0:
			continue   # not closing on him
		var c: float = rx * rx + rz * rz - contact_sq
		if c <= 0.0:
			return 0.0
		var a: float = wx * wx + wz * wz
		var disc: float = b * b - a * c
		if disc < 0.0:
			continue   # his line passes clear of the body
		t_c = minf(t_c, (-b - sqrt(disc)) / a)
	return t_c
