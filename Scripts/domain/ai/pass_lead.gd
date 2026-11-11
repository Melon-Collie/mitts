class_name AIPassLead

# Pass-leading for AI passers, shared by the carrier's pass scoring
# (`AICarrierPassSearch.search`) and the state machine's firing aim
# (`SkaterAgentStateMachine._pass_aim_point`), so a pass is never evaluated at
# one aim point and released at another.
#
# The receiver is led at his VELOCITY, with the flight time solved against where
# that puts him (AITrajectory.intercept_time), so a man skating away is not
# under-led. Never by the acceleration read off him (AIAccelerationTracker): that
# is the stride he is in, a few ticks long, and a receiver settling into a
# station does not keep it through a windup and a flight: led on it, a feed lands
# ahead of him, for the man behind him. test_pass_carry_calibration.gd sets each
# receiver against his lead, in the zone, on entries and on breakouts.
#
# The lead is measured from the receiver's BODY. Never aim at
# `blade_contact_world` and extrapolate that by the body's velocity: an off-puck
# bot's ready stance points its stick along its travel, so the stance offset and
# the travel lead add and the aim lands a full stick reach past the receiver
# (tests/unit/ai/test_pass_lead_blade_base.gd). The reception geometry
# (`_pass_receive_aim_and_steer`) is what puts the receiver's blade on the line;
# a ready one-timer man who can set for it, whose zone sits a metre off his
# body, is fed on it instead (feed_point).

# Lead a pass to a moving receiver. `launch_speed` is the puck's RELEASE speed;
# the lead accounts for it bleeding off to ice friction in flight (see
# effective_flight_speed). `release_s` is how long the receiver keeps skating
# before the puck leaves the blade (a carrier pricing a pass at its decision
# passes the pull and the windup). Returns [lead_point: Vector3, flight_t: float]
# — flight_t from the release; the carrier needs it downstream (opponent
# projection, goalie prediction, time-decay).
static func lead(shooter_pos: Vector3, receiver: SkaterNetworkState,
		launch_speed: float, max_lead_s: float, release_s: float = 0.0) -> Array:
	var vel: Vector3 = receiver.velocity
	var body_world: Vector3 = AITrajectory.predict_at(receiver.position, vel, release_s)
	# The intercept solver treats the puck as constant-speed, so feed it the
	# AVERAGE flight speed. Distance to the receiver's body stands in for the
	# pass length; the intercept iteration refines against his motion.
	var eff_speed: float = effective_flight_speed(
			launch_speed, shooter_pos.distance_to(body_world))
	var flight_t: float = AITrajectory.intercept_time(
			shooter_pos, body_world, vel, Vector3.ZERO, eff_speed, max_lead_s)
	return [AITrajectory.predict_at(body_world, vel, flight_t), flight_t]


static func lead_point(shooter_pos: Vector3, receiver: SkaterNetworkState,
		launch_speed: float, max_lead_s: float) -> Vector3:
	return lead(shooter_pos, receiver, launch_speed, max_lead_s)[0]


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
