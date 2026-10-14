extends GutTest

# Closed-form released-puck landing (AITrajectory.puck_release_landing and the
# runout) — where a dumped puck actually comes to REST.
#
# The dump-in prices its race where the puck STOPS, not at the spot it aims
# through, and asks per delivery inside the carrier compete (the stepped walk is
# ~1 us/step and a full runout is ~270 steps — see
# benchmarks/test_ai_micro_benchmark.gd).
#
# The load-bearing test in this file is the cross-validation: a closed form that
# disagrees with AITrajectory's own stepped integrator would be worse than no
# model at all, because every other consumer of puck paths (reception gate,
# chase election, shadow comparator) walks the stepped one.

const STEP_DT: float = 0.005


func _stepped_landing(origin: Vector3, vel: Vector3, seconds: float) -> Vector3:
	# board_margin = the puck radius, matching every live puck entry point: the
	# reference has to be the walk the game actually runs, or the cross-
	# validation below certifies agreement with a puck nobody simulates.
	return AITrajectory.predict_final(
			origin, vel, int(seconds / STEP_DT), STEP_DT,
			GameRules.PUCK_ICE_DECEL_M_S2, GameRules.PUCK_BOARD_COR_SCALE,
			Vector3.ZERO, 0.0, GameRules.PUCK_BOARD_FRICTION,
			GameRules.PUCK_COLLISION_RADIUS)


func _landing(origin: Vector3, vel: Vector3) -> Vector3:
	return AITrajectory.puck_release_landing(origin, vel)


# ── The runout pair ──────────────────────────────────────────────────────────

func test_runout_is_the_v_squared_over_2a_slide() -> void:
	# Hand-checked against the constants rather than the implementation:
	# 14^2 / (2 * 0.05 * 9.8) = 200 m.
	assert_almost_eq(AITrajectory.puck_runout_m(14.0), 200.0, 0.5,
			"quick-pass pace slides ~200 m — three rink lengths")
	assert_eq(AITrajectory.puck_runout_m(0.0), 0.0)


func test_no_release_the_bot_can_produce_dies_inside_the_rink() -> void:
	# The finding that shapes the dump-in: the softest release in the wrister
	# band, and the fixed quick-pass pace, both out-slide the rink, so where a
	# dump stops is set by what the boards take out of it, not by pace alone.
	var rink_length: float = 2.0 * GameRules.INNER_HALF_LENGTH
	assert_gt(AITrajectory.puck_runout_m(GameRules.DEFAULT_WRISTER_POWER_MIN_M_S),
			rink_length, "the softest wrister still out-slides the rink")
	assert_gt(AITrajectory.puck_runout_m(GameRules.DEFAULT_QUICK_PASS_POWER_M_S),
			rink_length, "the quick-pass pace still out-slides the rink")


# ── Open ice: the closed form IS the runout ──────────────────────────────────

func test_open_ice_landing_is_the_runout_along_the_launch_line() -> void:
	# Slow enough to stop before any board, so there is one leg and the answer
	# is pure arithmetic.
	var origin := Vector3(0.0, 0.0, 10.0)
	var vel := Vector3(0.0, 0.0, -3.0)
	var landing: Vector3 = _landing(origin, vel)
	assert_almost_eq(landing.z, 10.0 - AITrajectory.puck_runout_m(3.0), 0.01,
			"stops at origin + runout down the launch line")
	assert_almost_eq(landing.x, 0.0, 0.01, "no lateral drift on a straight slide")


# ── Cross-validation against the stepped integrator ──────────────────────────

func test_matches_the_stepped_walk_in_open_ice() -> void:
	var origin := Vector3(-4.0, 0.0, 12.0)
	var vel := Vector3(1.5, 0.0, -4.0)
	var closed: Vector3 = _landing(origin, vel)
	var stepped: Vector3 = _stepped_landing(origin, vel, 12.0)
	assert_almost_eq(closed.x, stepped.x, 0.25, "open-ice landing x matches the walk")
	assert_almost_eq(closed.z, stepped.z, 0.25, "open-ice landing z matches the walk")


func test_matches_the_stepped_walk_through_a_side_board() -> void:
	# Fired into the side wall at a steep angle — the contact that actually
	# sheds speed, so both the carom direction and the bleed have to agree.
	var origin := Vector3(0.0, 0.0, 0.0)
	var vel := Vector3(6.0, 0.0, -3.0)
	var closed: Vector3 = _landing(origin, vel)
	var stepped: Vector3 = _stepped_landing(origin, vel, 20.0)
	assert_almost_eq(closed.x, stepped.x, 0.6, "post-carom landing x matches the walk")
	assert_almost_eq(closed.z, stepped.z, 0.6, "post-carom landing z matches the walk")


func test_matches_the_stepped_walk_around_a_corner() -> void:
	# The rim into the corner — the delivery the dump model exists to price.
	#
	# This is the closed form's WEAK case and the tolerances say so. A corner rim
	# takes many near-tangential contacts, and on an arc the inward normal turns
	# with the contact point, so a few centimetres of disagreement about where a
	# contact happened rotates the next leg and compounds. The two models agree
	# closely on the axis the decision usually rests on (the puck ends deep in
	# the far end) and only loosely across the ice.
	#
	# The x spread here exceeds AIActionScoring.CHASE_CONTEST_MARGIN_M, so it is
	# large enough to flip a recovery race. That is the argument for spending one
	# stepped walk to CONFIRM a chosen corner delivery rather than trusting the
	# closed form's lateral answer — the closed form is for ranking candidates,
	# which is what keeps the compete affordable.
	var origin := Vector3(11.0, 0.0, 8.0)
	var vel := Vector3(1.0, 0.0, 7.0)
	var closed: Vector3 = _landing(origin, vel)
	var stepped: Vector3 = _stepped_landing(origin, vel, 20.0)
	assert_almost_eq(closed.z, stepped.z, 1.0, "corner landing z matches the walk")
	assert_almost_eq(closed.x, stepped.x, 2.5,
			"corner landing x tracks the walk to within a contest band")


func test_landing_is_always_on_the_playing_surface() -> void:
	for speed: float in [4.0, 9.0, 14.0]:
		for deg: float in [0.0, 35.0, 90.0, 145.0, 200.0, 290.0]:
			var vel: Vector3 = Vector3(0.0, 0.0, speed).rotated(
					Vector3.UP, deg_to_rad(deg))
			var landing: Vector3 = _landing(Vector3(3.0, 0.0, 14.0), vel)
			var clamped: Vector2 = GameRules.clamp_to_rink_inner(
					Vector2(landing.x, landing.z), GameRules.PUCK_COLLISION_RADIUS)
			assert_almost_eq(Vector2(landing.x, landing.z).distance_to(clamped), 0.0,
					0.01, "landing stays in the rink (%.0f m/s at %.0f deg)" % [speed, deg])
