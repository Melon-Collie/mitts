class_name AIPassLead

# Pass-leading for AI passers, shared by the carrier's pass scoring
# (`AICarrierPassSearch.search`) and the state machine's firing aim
# (`SkaterAgentStateMachine._pass_aim_point`), so a pass is never evaluated at
# one aim point and released at another.
#
# Two refinements over a naive `pos + vel·t` lead:
#
#   1. Intercept-time solve (AITrajectory.intercept_time): flight time is solved
#      against the receiver's PREDICTED position, so a receiver skating away
#      isn't under-led.
#
#   2. Along-velocity acceleration only (along_velocity_component): a turning
#      skater's acceleration is largely centripetal, and the ½·a·t² term along
#      it aims the pass off the side of the curve into ice the receiver never
#      enters. Only the speeding-up / slowing-down component is kept.
#
# The lead is measured from the receiver's BODY. Never aim at
# `blade_contact_world` and extrapolate that by the body's velocity: an off-puck
# bot's ready stance points its stick along its travel, so the stance offset and
# the travel lead add and the aim lands a full stick reach past the receiver
# (tests/unit/ai/test_pass_lead_blade_base.gd). The reception geometry
# (`_pass_receive_aim_and_steer`) is what puts the receiver's blade on the line;
# a ready one-timer man who can set for it, whose zone sits a metre off his
# body, is fed on it instead (feed_point).

# Below this speed (m/s) there's no reliable travel direction to project onto,
# so the raw accel — here "starting to move" — is kept as-is.
const MIN_SPEED_FOR_PROJECTION: float = 0.5


# Lead a pass to a moving receiver. `launch_speed` is the puck's RELEASE speed;
# the lead accounts for it bleeding off to ice friction in flight (see
# effective_flight_speed). `receiver_caps` is the receiver's real attribute-scaled
# build (AISkaterCaps) — its max_accel caps how hard it can keep accelerating
# into the lead, and its max_speed how far ahead it can get; null is the league
# baseline. `release_s` is how long the receiver keeps skating before the puck
# leaves the blade (a carrier pricing a pass at its decision passes the windup).
# Returns [lead_point: Vector3, flight_t: float] — flight_t from the release; the
# carrier needs it downstream (opponent projection, goalie prediction,
# time-decay).
static func lead(shooter_pos: Vector3, receiver: SkaterNetworkState,
		accel: Vector3, launch_speed: float, max_lead_s: float,
		receiver_caps: AISkaterCaps = null, release_s: float = 0.0) -> Array:
	var a: Vector3 = along_velocity_component(accel, receiver.velocity)
	# Observed accel is low-passed and can spike above what the body can pull,
	# which over-leads a low-Acceleration receiver into ice it can't reach.
	var max_accel: float = receiver_caps.max_accel if receiver_caps != null \
			else GameRules.DEFAULT_SKATER_THRUST_M_S2
	if a.length() > max_accel:
		a = a.normalized() * max_accel
	# The LARGER of top speed and current speed, so a receiver already moving
	# faster (a body-check boost, say) is never under-led.
	var speed_cap: float = maxf(
			_speed_xz(receiver.velocity),
			receiver_caps.max_speed if receiver_caps != null else GameRules.DEFAULT_SKATER_MAX_SPEED_M_S)
	var body_world: Vector3 = receiver.position
	var vel: Vector3 = receiver.velocity
	if release_s > 0.0:
		body_world = AITrajectory.predict_at(body_world, vel, release_s, 6, a, speed_cap)
		vel += a * release_s
		var v_len: float = _speed_xz(vel)
		if v_len > speed_cap:
			vel *= speed_cap / v_len
	# The intercept solver treats the puck as constant-speed, so feed it the
	# AVERAGE flight speed. Distance to the receiver's body stands in for the
	# pass length; the intercept iteration refines against his motion.
	var eff_speed: float = effective_flight_speed(
			launch_speed, shooter_pos.distance_to(body_world))
	var flight_t: float = AITrajectory.intercept_time(
			shooter_pos, body_world, vel, a,
			eff_speed, max_lead_s, 6, speed_cap)
	var point: Vector3 = AITrajectory.predict_at(
			body_world, vel, flight_t, 6, a, speed_cap)
	return [point, flight_t]


static func _speed_xz(v: Vector3) -> float:
	return sqrt(v.x * v.x + v.z * v.z)


static func lead_point(shooter_pos: Vector3, receiver: SkaterNetworkState,
		accel: Vector3, launch_speed: float, max_lead_s: float,
		receiver_caps: AISkaterCaps = null) -> Vector3:
	return lead(shooter_pos, receiver, accel, launch_speed, max_lead_s, receiver_caps)[0]


# Average (time-mean) speed of a pass over `distance`, given it launches at
# `launch_speed` and sheds speed to constant Coulomb ice friction. Under constant
# deceleration velocity is linear in TIME, so the time-average is exactly
# (launch + arrival)/2, and as the intercept solver's constant speed it
# reproduces the true flight time.
static func effective_flight_speed(launch_speed: float, distance: float) -> float:
	var arrival_sq: float = launch_speed * launch_speed \
			- 2.0 * GameRules.PUCK_ICE_DECEL_M_S2 * maxf(distance, 0.0)
	var arrival: float = sqrt(arrival_sq) if arrival_sq > 0.0 else 0.0
	return (launch_speed + arrival) * 0.5


# The component of `accel` parallel to `vel`; `accel` unchanged below
# MIN_SPEED_FOR_PROJECTION.
static func along_velocity_component(accel: Vector3, vel: Vector3) -> Vector3:
	var speed: float = vel.length()
	if speed < MIN_SPEED_FOR_PROJECTION:
		return accel
	var dir: Vector3 = vel / speed
	return dir * accel.dot(dir)


# Where a one-timer-ready receiver whose body meets the feed at `body` takes it:
# his slapper zone, the strike spot of a stance set for `attacking_goal` from
# there (SkaterAgentOneTimer.zone_center), so the feed arrives on the line he
# would otherwise have to shuffle onto. Fed at the body, a cross-crease feed
# reaches him before he can set.
static func one_timer_tape(body: Vector3, receiver_caps: AISkaterCaps,
		attacking_goal: Vector3) -> Vector3:
	var caps: AISkaterCaps = receiver_caps if receiver_caps != null else AISkaterCaps.new()
	var to_net := Vector2(attacking_goal.x - body.x, attacking_goal.z - body.z)
	if to_net.length_squared() < 0.000001:
		return body
	var side: float = -1.0 if caps.is_left_handed else 1.0
	var off: Vector2 = SlapperRules.strike_offset(to_net.normalized(),
			Vector2(caps.slapper_strike_local.x * side, caps.slapper_strike_local.y), side,
			caps.slapper_stance_open_rad)
	return Vector3(body.x + off.x, body.y, body.z + off.y)


# Whether a one-timer-ready receiver led to `body` (his body there in `flight_t`)
# can set for a feed on his tape before it arrives (SlapperRules.time_to_set, as
# he reads it on the release tick). Fed there, the circle meets the line wherever
# his glide takes him, so what is left is his hips' pivot and any lead his glide
# alone does not cover.
static func one_timer_sets(receiver: SkaterNetworkState, body: Vector3, flight_t: float,
		receiver_caps: AISkaterCaps, attacking_goal: Vector3) -> bool:
	var caps: AISkaterCaps = receiver_caps if receiver_caps != null else AISkaterCaps.new()
	var tape: Vector3 = one_timer_tape(body, caps, attacking_goal)
	var shot := Vector2(attacking_goal.x - tape.x, attacking_goal.z - tape.z)
	if shot.length_squared() < 0.000001:
		return true
	return SlapperRules.time_to_set(receiver.facing,
			Vector2(receiver.velocity.x, receiver.velocity.z),
			Vector2(body.x - receiver.position.x, body.z - receiver.position.z),
			shot.normalized(), flight_t, -1.0 if caps.is_left_handed else 1.0,
			caps.slapper_stance_open_rad, caps.slapper_stance_turn_rad_s,
			caps.movement.shuffle_speed) <= flight_t


# Where a pass leading its receiver to `body` in `flight_t` is aimed: his tape
# when he is one-timer ready and can set for it, else his body.
static func feed_point(receiver: SkaterNetworkState, body: Vector3, flight_t: float,
		one_timer_ready: bool, receiver_caps: AISkaterCaps, attacking_goal: Vector3) -> Vector3:
	if one_timer_ready and one_timer_sets(receiver, body, flight_t, receiver_caps,
			attacking_goal):
		return one_timer_tape(body, receiver_caps, attacking_goal)
	return body
