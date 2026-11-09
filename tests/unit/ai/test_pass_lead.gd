extends GutTest

# AIPassLead is the unified pass-leading helper shared by the carrier role's
# pass scoring and the state machine's firing aim. The receiver is led at his
# velocity, the flight solved against where that puts him (a receiver skating
# away is led further than the current-distance estimate would), and nothing of
# the acceleration read off him.


func _receiver(pos: Vector3, vel: Vector3) -> SkaterNetworkState:
	var s := SkaterNetworkState.new()
	s.position = pos
	s.velocity = vel
	s.blade_contact_world = pos  # aim at the (here, body-coincident) blade
	return s


# ── Intercept-time solve ────────────────────────────────────────────────────

func test_intercept_leads_further_for_fleeing_target() -> void:
	# Shooter at origin, receiver 8 m up-ice skating further away. The
	# naive current-distance time underestimates flight; the intercept
	# solve should lead PAST the naive pos+vel·t point.
	var shooter := Vector3.ZERO
	var pos := Vector3(0, 0, 8)
	var vel := Vector3(0, 0, 6)  # skating away at 6 m/s
	var speed := 14.0
	var max_lead := 0.6

	var naive_t: float = 8.0 / speed
	var naive_point := pos + vel * naive_t

	var solved_t := AITrajectory.intercept_time(
			shooter, pos, vel, Vector3.ZERO, speed, max_lead)
	var solved_point := AITrajectory.predict_at(pos, vel, solved_t)

	assert_gt(solved_t, naive_t,
			"fleeing target should be led with a longer flight time")
	assert_gt(solved_point.z, naive_point.z,
			"solved intercept should sit further up-ice than the naive lead")


func test_intercept_converges_for_stationary_target() -> void:
	# A stationary target's intercept time is just distance / speed.
	var t := AITrajectory.intercept_time(
			Vector3.ZERO, Vector3(0, 0, 7), Vector3.ZERO, Vector3.ZERO,
			14.0, 0.6)
	assert_almost_eq(t, 7.0 / 14.0, 0.001)


func test_intercept_clamped_to_max_lead() -> void:
	# Target far enough that distance/speed exceeds the cap → clamps.
	var t := AITrajectory.intercept_time(
			Vector3.ZERO, Vector3(0, 0, 30), Vector3.ZERO, Vector3.ZERO,
			14.0, 0.6)
	assert_almost_eq(t, 0.6, 0.001)


func test_intercept_zero_speed_returns_zero() -> void:
	var t := AITrajectory.intercept_time(
			Vector3.ZERO, Vector3(0, 0, 5), Vector3.ZERO, Vector3.ZERO,
			0.0, 0.6)
	assert_eq(t, 0.0)


# ── End-to-end lead() ───────────────────────────────────────────────────────

func test_lead_returns_point_and_flight_time() -> void:
	var receiver := _receiver(Vector3(0, 0, 6), Vector3(0, 0, 4))
	var out := AIPassLead.lead(Vector3.ZERO, receiver, 14.0, 0.6)
	assert_eq(out.size(), 2)
	var point: Vector3 = out[0]
	var flight_t: float = out[1]
	assert_gt(flight_t, 0.0)
	# Receiver moving up-ice → lead point ahead of the start blade pos.
	assert_gt(point.z, 6.0, "lead point should be ahead of the receiver")


func test_lead_point_matches_lead_first_element() -> void:
	var receiver := _receiver(Vector3(2, 0, 5), Vector3(1, 0, 3))
	var full := AIPassLead.lead(Vector3.ZERO, receiver, 14.0, 0.6)
	var point := AIPassLead.lead_point(Vector3.ZERO, receiver, 14.0, 0.6)
	assert_eq(point, full[0], "lead_point must equal lead()[0]")


func test_the_lead_is_his_travel_at_his_velocity() -> void:
	# Through the windup and the flight he is led where his velocity takes him,
	# a turning or still-accelerating man alike: the spot is his body carried on
	# at the velocity he has, nothing more.
	var receiver := _receiver(Vector3(3, 0, 8), Vector3(1.5, 0, 5))
	var release_s: float = 0.135
	var out := AIPassLead.lead(Vector3.ZERO, receiver, 16.0, 1.0, release_s)
	var point: Vector3 = out[0]
	var flight_t: float = out[1]
	var travel: Vector3 = receiver.position + receiver.velocity * (release_s + flight_t)
	assert_almost_eq(point.x, travel.x, 0.001)
	assert_almost_eq(point.z, travel.z, 0.001)


func test_he_keeps_skating_through_the_release() -> void:
	# Released later, the same feed is led further along his travel.
	var receiver := _receiver(Vector3(0, 0, 8), Vector3(0, 0, 5))
	var now: Vector3 = AIPassLead.lead(Vector3.ZERO, receiver, 16.0, 1.0)[0]
	var later: Vector3 = AIPassLead.lead(Vector3.ZERO, receiver, 16.0, 1.0, 0.3)[0]
	assert_gt(later.z, now.z, "a release 0.3 s later leads him further on")


func test_lead_falls_back_to_body_when_blade_unpopulated() -> void:
	var s := SkaterNetworkState.new()
	s.position = Vector3(0, 0, 5)
	s.velocity = Vector3.ZERO
	# blade_contact_world left at ZERO → fallback to body position.
	var point := AIPassLead.lead_point(Vector3.ZERO, s, 14.0, 0.6)
	assert_almost_eq(point.z, 5.0, 0.001,
			"unpopulated blade should aim at body position")


# ── effective_flight_speed: friction-aware lead ─────────────────────────────

func test_effective_flight_speed_below_launch_and_drops_with_distance() -> void:
	# The puck sheds speed in flight, so its average speed is below launch, and
	# more so over a longer pass.
	var launch := 20.0
	var near: float = AIPassLead.effective_flight_speed(launch, 5.0)
	var far: float = AIPassLead.effective_flight_speed(launch, 25.0)
	assert_lt(near, launch, "average flight speed is below the launch speed")
	assert_lt(far, near, "a longer pass averages even slower")
	# Closed form at 25 m: arrival = √(20² − 2·a·25), avg = (20 + arrival)/2.
	var arrival: float = sqrt(400.0 - 2.0 * GameRules.PUCK_ICE_DECEL_M_S2 * 25.0)
	assert_almost_eq(far, (20.0 + arrival) * 0.5, 0.001)


func test_effective_flight_speed_negligible_at_zero_distance() -> void:
	# A point-blank pass hasn't decelerated yet → average ≈ launch.
	assert_almost_eq(AIPassLead.effective_flight_speed(18.0, 0.0), 18.0, 0.001)


func test_friction_leads_a_long_pass_further_than_constant_speed() -> void:
	# A receiver cutting up-ice, led over a long pass. Because the puck slows in
	# flight, the friction-aware lead must sit further ahead than a naive
	# constant-launch-speed lead (longer flight time → receiver travels further).
	var receiver := _receiver(Vector3(0, 0, 20), Vector3(0, 0, 6))
	var launch := 20.0
	var friction_aware: float = AIPassLead.lead_point(
			Vector3.ZERO, receiver, launch, 1.5).z
	# Constant-speed reference: feed intercept_time the raw launch speed.
	var eff_t: float = AITrajectory.intercept_time(
			Vector3.ZERO, Vector3(0, 0, 20), Vector3(0, 0, 6), Vector3.ZERO, launch, 1.5)
	var constant_speed: float = AITrajectory.predict_at(
			Vector3(0, 0, 20), Vector3(0, 0, 6), eff_t).z
	assert_gt(friction_aware, constant_speed,
			"friction-aware lead sits further ahead than the constant-speed lead")
