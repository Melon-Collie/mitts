extends GutTest

# Pins the stick's model — geometry in, coverage out.


# A goalie stick's lie is in the plane of the blade's face, and the paddle
# leaning its complement off vertical is what lays the blade's length flush.
# Rolled any other way the blade rests on its heel or its toe. The curve turns
# the blade a few degrees in plan, so a laid-back paddle lifts the toe by a
# fraction of that — a curved blade's toe does ride up off a tilted stick.
func test_the_flush_roll_lays_the_blade_level_at_any_tilt() -> void:
	for tilt: float in [0.0, GoalieStickRules.UPRIGHT_TILT_DEG, 55.0]:
		var b: Basis = GoalieStickRules.blade_basis(tilt, GoalieStickRules.FLUSH_ROLL_DEG)
		var lift: float = rad_to_deg(asin(absf(b.x.y)))
		assert_lt(lift, GoalieStickRules.blade_curve_face_deg(),
				"tilt %.0f: the blade's long axis is %.1f deg off level" % [tilt, lift])
	var off: Basis = GoalieStickRules.blade_basis(
			GoalieStickRules.UPRIGHT_TILT_DEG, GoalieStickRules.FLUSH_ROLL_DEG - 10.0)
	assert_gt(absf(off.x.y), 0.1, "ten degrees off the flush roll tips it")


func test_the_lie_is_the_paddle_to_blade_angle_in_the_face_plane() -> void:
	var b: Basis = GoalieStickRules.blade_basis(0.0, 0.0)
	var paddle_down := Vector3(0.0, -1.0, 0.0)
	var toe: Vector3 = -b.x
	assert_almost_eq(rad_to_deg(paddle_down.angle_to(toe)),
			180.0 - GoalieStickRules.PADDLE_TO_BLADE_DEG, 0.5,
			"blade and paddle meet at the lie")
	assert_almost_eq(b.z.dot(Vector3(0.0, 0.0, 1.0)), 1.0, 0.01,
			"in the plane of the face, not about the blade's length")


# The blade lies across the five-hole, not out to one side of it.
func test_the_ready_blade_rests_across_the_five_hole() -> void:
	var centre: float = GoalieStickRules.blade_center_x(
			GoalieStickRules.READY_WRIST_X_M, GoalieStickRules.UPRIGHT_TILT_DEG, 0.0)
	assert_lt(absf(centre), 0.05, "blade centre %.3f m off the midline" % centre)


func test_reach_tracks_the_blade_geometry() -> void:
	# Derived, not declared: the blade's own half-width is inside the answer.
	var reach: float = GoalieStickRules.standing_lateral_reach()
	var center: float = reach - GoalieStickRules.BLADE_WIDTH_M * 0.5
	assert_almost_eq(center,
			GoalieStickRules.blade_center_x(GoalieStickRules.READY_WRIST_X_M,
					GoalieStickRules.UPRIGHT_TILT_DEG,
					-GoalieStickRules.ACTIVE_YAW_CAP_DEG),
			0.001,
			"reach is the furthest blade CENTRE the yaw cap allows, plus its half-width")


func test_the_blade_closes_the_standing_five_hole() -> void:
	# The standing slot is ~0.16-0.20 m (GoalieBehaviorRules.five_hole_gap_m);
	# the blade is 0.38 m and lies across it. Measured: a dead-centre flat
	# release at 2.5-4.0 m is stick-saved 24/24.
	var standing_slot: float = GoalieBehaviorRules.five_hole_gap_m(false, 0.02)
	assert_eq(GoalieStickRules.five_hole_gap_after_blade(standing_slot), 0.0,
			"the paddle across the slot closes the standing five-hole outright")


func test_a_down_slide_leak_survives_the_blade() -> void:
	# The five-hole that genuinely exists is the DOWN goalie's slide leak, and
	# the blade must not erase it — otherwise closing the standing hole would
	# have cost the real one.
	assert_gt(GoalieStickRules.five_hole_gap_after_blade(0.36 + 0.38), 0.0,
			"a wide mid-slide leak is still a hole with the blade in it")


func test_yaw_aims_the_blade_not_the_assembly() -> void:
	# Closed-loop: after yawing, the blade CENTRE should sit on the wrist→target
	# bearing — not merely point the assembly the right way. This is the property
	# the old atan2(puck_x, fixed_lookahead) heuristic lacked.
	var wrist_x: float = GoalieStickRules.READY_WRIST_X_M
	var wrist_z: float = -0.32
	var target_x: float = 0.10
	var target_z: float = -1.40
	var yaw: float = GoalieStickRules.yaw_to_target(
			wrist_x, wrist_z, target_x, target_z,
			GoalieStickRules.UPRIGHT_TILT_DEG, 90.0)
	var b: Vector2 = GoalieStickRules.blade_offset_from_wrist(
			GoalieStickRules.UPRIGHT_TILT_DEG)
	var t: float = deg_to_rad(yaw)
	var bx: float = b.x * cos(t) + b.y * sin(t)
	var bz: float = -b.x * sin(t) + b.y * cos(t)
	var want: float = atan2(-(target_x - wrist_x), -(target_z - wrist_z))
	assert_almost_eq(atan2(-bx, -bz), want, 0.001,
			"the solved yaw puts the BLADE on the wrist→target line")


func test_yaw_is_capped() -> void:
	# The blocker pad is rigidly attached, so an uncapped swing takes it off the
	# body. A target hard out on the blocker side (the blade already hangs toward
	# the glove side of the hand) must saturate, not over-rotate.
	var yaw: float = GoalieStickRules.yaw_to_target(
			0.44, -0.32, 4.0, -0.4, GoalieStickRules.UPRIGHT_TILT_DEG,
			GoalieStickRules.ACTIVE_YAW_CAP_DEG)
	assert_almost_eq(absf(yaw), GoalieStickRules.ACTIVE_YAW_CAP_DEG, 0.001,
			"a far-side target saturates the yaw cap")


func test_degenerate_inputs_hold_neutral() -> void:
	assert_eq(GoalieStickRules.yaw_to_target(0.44, -0.32, 0.44, -0.32,
			GoalieStickRules.UPRIGHT_TILT_DEG, 25.0), 0.0,
			"a target at the wrist has no defined direction")
	# Zero TILT is NOT degenerate — the blade still hangs ASSEMBLY_LATERAL_M to
	# the side, so there is still a lever to swing. (The builder comment this
	# model replaced claimed the opposite; the guard only covers a blade sitting
	# exactly on the wrist, which the real geometry never produces.)
	assert_ne(GoalieStickRules.yaw_to_target(0.44, -0.32, 0.0, -2.0, 0.0, 25.0), 0.0,
			"a flat stick still has a lateral lever for yaw to act on")


# ── The lunge is a strike, so it is the last resort ──────────────────────────
# Three physical numbers, no threshold: where the blade is, how far it affects
# the puck, and how far the jab extends it.

const POKE: float = 0.25
const EXTENSION: float = 0.35


func test_no_jab_when_the_blade_is_already_on_it() -> void:
	# THE MEASURED BUG. The blade sat 0.15-0.24 m from the puck — inside poke
	# range — in every case the old distance trigger fired, so he paid the
	# fully-unset read penalty for a jab that bought nothing.
	assert_false(GoalieStickRules.lunge_is_the_only_reach(0.19, POKE, EXTENSION))
	assert_false(GoalieStickRules.lunge_is_the_only_reach(0.24, POKE, EXTENSION))
	assert_false(GoalieStickRules.lunge_is_the_only_reach(0.0, POKE, EXTENSION),
			"a blade on top of the puck least of all")


func test_he_jabs_when_the_jab_is_what_closes_the_gap() -> void:
	# Just outside poke range, inside poke + extension: this is the whole case
	# the lunge exists for.
	assert_true(GoalieStickRules.lunge_is_the_only_reach(0.27, POKE, EXTENSION))
	assert_true(GoalieStickRules.lunge_is_the_only_reach(0.57, POKE, EXTENSION))


func test_no_jab_at_a_puck_the_jab_cannot_reach_either() -> void:
	# Past poke + extension the jab does not get there, so it is pure cost — a
	# goalie flailing at a puck he was never going to touch, and unset for it.
	assert_false(GoalieStickRules.lunge_is_the_only_reach(0.61, POKE, EXTENSION))
	assert_false(GoalieStickRules.lunge_is_the_only_reach(1.04, POKE, EXTENSION))


func test_the_window_is_exactly_the_extension() -> void:
	# It opens where the blade stops reaching and closes where the jab stops
	# reaching — so the lever that sets the jab's length sets its trigger too,
	# and they cannot drift apart.
	assert_false(GoalieStickRules.lunge_is_the_only_reach(POKE, POKE, EXTENSION),
			"closed at the poke radius")
	assert_true(GoalieStickRules.lunge_is_the_only_reach(POKE + 0.001, POKE, EXTENSION),
			"open just past it")
	assert_true(GoalieStickRules.lunge_is_the_only_reach(POKE + EXTENSION, POKE, EXTENSION),
			"open out to full extension")
	assert_false(GoalieStickRules.lunge_is_the_only_reach(
			POKE + EXTENSION + 0.001, POKE, EXTENSION), "closed past it")
