class_name AIArrival

# The momentum-honest arrival clock the bots share: how long a body carrying
# its current velocity takes to reach a point, routed around the nets. A leaf —
# it reads GameRules, AIStrideRamp, AINetObstacle and AISkaterCaps only — so the
# scorer and AICarrySpace can both depend on it
# (test_scoring_split_stays_acyclic.gd).

# Reference (league-average) top skating speed, shared with
# SkaterController.max_speed via GameRules. A FALLBACK for a body whose build is
# not in view: a read with a peer in view times him on his own build
# (time_to_arrive_caps).
const SKATER_REF_SPEED_M_S: float = GameRules.DEFAULT_SKATER_MAX_SPEED_M_S

# Floor (m/s) for momentum-adverse `time_to_arrive` returns, so reverse
# candidates get finite (large) ETAs rather than infinite ones.
const MIN_TRAVEL_SPEED_M_S: float = 1.0

# League-default all-direction thrust — the redirect authority a caps-less
# time_to_arrive caller assumes for the cross-momentum shed. Mirrors
# SkaterController.thrust.
const SHED_ACCEL_DEFAULT_M_S2: float = GameRules.DEFAULT_SKATER_THRUST_M_S2

# ── Calibrated phase model ─────────────────────────────────────────────────────
# The measured controller (SkaterMovementRules at 120 Hz driven by the real
# steering — the velocity-matched seek plus the pivot brake, see
# tests/unit/ai/test_time_to_arrive_calibration.gd, which pins every constant
# here against simulated arrivals) decomposes into:
#
#   REDIRECT — cross-momentum beyond what the seek sheds for free. The
#     velocity-matched anchor pull cancels cross-drift out of the thrust's
#     spare headroom, so moderate drift costs nothing; only the EXCESS above
#     VM_FREE_SHED_M_S pays, at the measured net shed rate.
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
# standing starts top speed for free. Errors vs the measured table are within
# ~±20% on the clean families; short diagonal cuts at high speed (the
# controller can overfly the catch window and circle once) run up to ~2× the
# estimate.

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


# `ref_speed_m_s` is the actor's flat skating speed, `accel_m_s2` its all-direction
# thrust and `lateral_grip` its edge grip, each defaulting to the league build. A
# skater in view is timed on his own build, whoever is asking — through
# time_to_arrive_caps, so no read passes his speed and leaves his acceleration
# and grip at the league's. Every bot reads every racer off the same build
# (RoleContext.caps_by_peer), so a race all of them run still ranks alike.
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


# time_to_arrive for a body built as `caps`: his top speed, thrust and edge grip
# (null: the league build).
static func time_to_arrive_caps(from_pos: Vector3, dest: Vector3,
		from_velocity: Vector3, caps: AISkaterCaps) -> float:
	if caps == null:
		return time_to_arrive(from_pos, dest, from_velocity)
	return time_to_arrive(from_pos, dest, from_velocity, caps.max_speed, caps.max_accel,
			caps.lateral_grip)


# The brake a body built as `caps` (null: the league build) owes after arriving
# at full stride before he stands SET there: his top speed shed at the arrival
# brake. Beating a man somewhere stride-for-stride is chasing him, not being
# there first.
static func set_margin_s(caps: AISkaterCaps) -> float:
	var vmax: float = caps.max_speed if caps != null else GameRules.DEFAULT_SKATER_MAX_SPEED_M_S
	return vmax / AISteering.ARRIVAL_BRAKE_DECEL_M_S2


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
# (see _time_to_arrive_routed).
static func cage_waypoint(from_pos: Vector3, dest: Vector3, from_velocity: Vector3,
		ref_speed_m_s: float, accel_m_s2: float, lateral_grip: float = 1.0) -> Vector3:
	# The cage being crossed is on the side the route actually reaches.
	var s: float = signf(from_pos.z) \
			if absf(from_pos.z) >= absf(dest.z) else signf(dest.z)
	var side_x: float = GameRules.NET_BACK_HALF_WIDTH \
			+ AINetObstacle.CARRY_NET_CLEAR_MARGIN_M + NET_ROUTE_CLEAR_M
	var mid_z: float = s * (GameRules.GOAL_LINE_Z + GameRules.NET_DEPTH * 0.5)
	var back_z: float = s * (GameRules.GOAL_LINE_Z + GameRules.NET_DEPTH \
			+ AINetObstacle.CARRY_NET_CLEAR_MARGIN_M + NET_ROUTE_CLEAR_M)
	var front_z: float = s * (GameRules.GOAL_LINE_Z \
			- AINetObstacle.CARRY_NET_CLEAR_MARGIN_M - NET_ROUTE_CLEAR_M)
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
	var dist: float = sqrt(dx * dx + dz * dz)
	if dist < 0.001:
		return 0.0
	var vmax: float = maxf(ref_speed_m_s, MIN_TRAVEL_SPEED_M_S)
	var inv: float = 1.0 / dist
	var v_along: float = from_velocity.x * dx * inv + from_velocity.z * dz * inv
	var v_len_sq: float = from_velocity.x * from_velocity.x \
			+ from_velocity.z * from_velocity.z
	var v_perp: float = sqrt(maxf(0.0, v_len_sq - v_along * v_along))
	# REDIRECT: only the cross momentum the seek can't shed for free pays,
	# scaled by this build's edge grip — the turn authority SkaterMovementRules
	# scales in the real body (turning redirects momentum on the edges; the
	# stride plays no part, and grip never limits the ramp below).
	var grip: float = maxf(lateral_grip, 0.001)
	var t: float = maxf(0.0, v_perp - VM_FREE_SHED_M_S * grip) \
			/ (VM_SHED_DECEL_M_S2 * grip)
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
