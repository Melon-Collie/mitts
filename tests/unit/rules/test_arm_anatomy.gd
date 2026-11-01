extends GutTest

# ArmAnatomy's joint angles on poses whose angles anatomy names: the arm
# hanging with the elbow bent ahead and the thumb up is every joint at zero,
# and each motion off it reads as itself, with its sign. A left arm reads as
# its mirror image. The search holds a hand it can and finds the limit it
# cannot.

const DEG: float = PI / 180.0
const TOL: float = 0.5 * DEG
const GRIP: float = 65.0 * DEG
const UPPER: float = 0.33
const FORE: float = 0.33


func _body() -> ArmAnatomyBody:
	var body := ArmAnatomyBody.new()
	body.upper_len = UPPER
	body.fore_len = FORE
	body.working_extension = 1.0
	body.torso_profile = SkaterMeshBuilder.TORSO_PROFILE
	body.torso_sway = SkaterMeshBuilder.TORSO_REAR_SWAY
	body.torso_xz_scale = SkaterMeshBuilder.TORSO_XZ_SCALE
	# An ulnar wrist reads as the hand is posed (no slide below GRIP); the grip's
	# own slide is its test's.
	body.grip_min_angle = GRIP
	return body


# A right arm from the origin, the trunk square, the jersey far away, its hand
# at `hand` with its long axis `axis` and its thumb toward `thumb`: the shaft
# that grip_frame puts across that palm at roll 0 at `grip`.
func _setup(hand: Vector3, axis: Vector3, thumb: Vector3, side: float = 1.0,
		grip: float = GRIP) -> ArmAnatomy.ArmSetup:
	var s := ArmAnatomy.ArmSetup.new()
	s.body = _body()
	s.side = side
	s.torso = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 50.0))
	s.hand = hand
	s.shaft = axis * cos(grip) + thumb * sin(grip)
	s.roll_up = axis * sin(grip) - thumb * cos(grip)
	s.grip_angle = grip
	return s


func _eval(s: ArmAnatomy.ArmSetup) -> ArmAnatomy.ArmPose:
	var out := ArmAnatomy.ArmPose.new()
	ArmAnatomy.evaluate(s, 0.0, 0.0, out)
	return out


func _hanging_bent(axis: Vector3, thumb: Vector3) -> ArmAnatomy.ArmPose:
	return _eval(_setup(Vector3(0.0, -UPPER, -FORE), axis, thumb))


func test_the_hanging_arm_bent_ahead_thumb_up_is_every_joint_at_zero() -> void:
	var p: ArmAnatomy.ArmPose = _hanging_bent(Vector3.FORWARD, Vector3.UP)
	assert_almost_eq(p.elbow, Vector3(0.0, -UPPER, 0.0), Vector3.ONE * 0.001, "elbow under the shoulder")
	assert_almost_eq(p.elevation, 0.0, TOL, "hanging")
	assert_almost_eq(p.axial, 0.0, TOL, "no turn about the upper arm")
	assert_almost_eq(p.elbow_flexion, 90.0 * DEG, TOL, "bent square")
	assert_almost_eq(p.pronation, 0.0, TOL, "thumb up")
	assert_almost_eq(p.wrist_flexion, 0.0, TOL, "wrist straight")
	assert_almost_eq(p.wrist_deviation, 0.0, TOL, "wrist straight")
	assert_true(p.feasible(), "a body holds it")


func test_the_forearm_turned_in_to_the_belly_is_internal_rotation() -> void:
	var s: ArmAnatomy.ArmSetup = _setup(Vector3(-FORE, -UPPER, 0.0), Vector3.LEFT, Vector3.UP)
	var p: ArmAnatomy.ArmPose = _eval(s)
	assert_almost_eq(p.axial, 90.0 * DEG, TOL, "internal")
	assert_almost_eq(p.pronation, 0.0, TOL, "thumb still up")
	assert_eq(p.binding, ArmAnatomy.Limit.SHOULDER_INTERNAL, "past its 70°")


func test_the_palm_turned_down_is_pronation_and_up_supination() -> void:
	var down: ArmAnatomy.ArmPose = _hanging_bent(Vector3.FORWARD, Vector3.LEFT)
	assert_almost_eq(down.pronation, 90.0 * DEG, TOL, "palm down")
	assert_eq(down.binding, ArmAnatomy.Limit.PRONATION, "past its 80°")
	var up: ArmAnatomy.ArmPose = _hanging_bent(Vector3.FORWARD, Vector3.RIGHT)
	assert_almost_eq(up.pronation, -90.0 * DEG, TOL, "palm up")
	assert_eq(up.binding, ArmAnatomy.Limit.SUPINATION, "past its 85°")


func test_the_fingers_bent_toward_the_palm_is_flexion_and_toward_the_little_finger_ulnar() -> void:
	var a: float = 30.0 * DEG
	# The palm faces in (-X) at rest.
	var flexed: ArmAnatomy.ArmPose = _hanging_bent(
			Vector3.FORWARD.rotated(Vector3.UP, a), Vector3.UP)
	assert_almost_eq(flexed.wrist_flexion, a, TOL, "flexion")
	assert_almost_eq(flexed.wrist_deviation, 0.0, TOL, "no deviation")
	var ulnar: ArmAnatomy.ArmPose = _hanging_bent(
			Vector3.FORWARD.rotated(Vector3.RIGHT, -a), Vector3.UP.rotated(Vector3.RIGHT, -a))
	assert_almost_eq(ulnar.wrist_deviation, a, TOL, "ulnar")
	assert_almost_eq(ulnar.wrist_flexion, 0.0, TOL, "no flexion")
	assert_eq(ulnar.binding, ArmAnatomy.Limit.NONE, "inside its range")


func test_the_arm_raised_ahead_is_flexion_and_out_to_the_side_abduction() -> void:
	var reach: float = UPPER + FORE - 0.0001
	var ahead: ArmAnatomy.ArmPose = _eval(_setup(Vector3(0.0, 0.0, -reach), Vector3.FORWARD, Vector3.UP))
	assert_almost_eq(ahead.elevation, 90.0 * DEG, 2.0 * DEG, "raised level")
	assert_almost_eq(ahead.plane, 90.0 * DEG, 2.0 * DEG, "ahead")
	var out: ArmAnatomy.ArmPose = _eval(_setup(Vector3(reach, 0.0, 0.0), Vector3.RIGHT, Vector3.UP))
	assert_almost_eq(out.elevation, 90.0 * DEG, 2.0 * DEG, "raised level")
	assert_almost_eq(out.plane, 0.0, 2.0 * DEG, "out to the side")


func test_the_shoulder_raises_all_the_way_ahead_and_less_behind_and_across() -> void:
	assert_almost_eq(ArmAnatomy.elevation_max(90.0 * DEG), 180.0 * DEG, TOL, "ahead")
	assert_almost_eq(ArmAnatomy.elevation_max(0.0), 180.0 * DEG, TOL, "to the side")
	assert_almost_eq(ArmAnatomy.elevation_max(-90.0 * DEG), 50.0 * DEG, TOL, "extension")
	assert_almost_eq(ArmAnatomy.elevation_max(130.0 * DEG), 90.0 * DEG, TOL,
			"horizontal adduction at shoulder height")
	assert_almost_eq(ArmAnatomy.elevation_max(180.0 * DEG), 40.0 * DEG, TOL, "adduction")


func test_a_left_arm_reads_as_the_right_arm_mirrored() -> void:
	var m := Basis(Vector3(-1.0, 0.0, 0.0), Vector3.UP, Vector3.BACK)
	var hand := Vector3(-0.1, -0.3, -0.3)
	var axis: Vector3 = Vector3(-0.3, 0.2, -1.0).normalized()
	var thumb: Vector3 = (Vector3(0.4, 1.0, 0.1) - axis * Vector3(0.4, 1.0, 0.1).dot(axis)).normalized()
	var right: ArmAnatomy.ArmSetup = _setup(hand, axis, thumb)
	var left: ArmAnatomy.ArmSetup = _setup(m * hand, m * axis, m * thumb, -1.0)
	for swivel: float in [0.0, 0.7, -1.2]:
		var r := ArmAnatomy.ArmPose.new()
		var l := ArmAnatomy.ArmPose.new()
		# A mirror turns every rotation the other way.
		ArmAnatomy.evaluate(right, swivel, 0.3, r)
		ArmAnatomy.evaluate(left, -swivel, -0.3, l)
		assert_almost_eq(l.elbow, m * r.elbow, Vector3.ONE * 0.0001, "elbow mirrored")
		for f: String in ["elevation", "plane", "axial", "elbow_flexion", "pronation",
				"wrist_flexion", "wrist_deviation"]:
			assert_almost_eq(float(l.get(f)), float(r.get(f)), 0.0001, f)


# A palm held to a shaft crossing it 10° nearer square than the hand lies is a
# wrist cocked 10° ulnar; the shaft let slide round in the palm straightens it,
# down to the diagonal grip and up to square across the palm.
func test_the_grip_slides_round_the_shaft_and_straightens_the_wrist() -> void:
	var at: Vector3 = Vector3(0.0, -UPPER, -FORE)
	var s: ArmAnatomy.ArmSetup = _setup(at, Vector3.FORWARD, Vector3.UP)
	s.grip_angle = GRIP + 10.0 * DEG
	s.body.grip_min_angle = s.grip_angle
	assert_almost_eq(_eval(s).wrist_deviation, 10.0 * DEG, TOL, "ulnar by the angle")
	s.body.grip_min_angle = 45.0 * DEG
	var p: ArmAnatomy.ArmPose = _eval(s)
	assert_almost_eq(p.wrist_deviation, 0.0, TOL, "slid straight")
	assert_almost_eq(p.grip_slide, -10.0 * DEG, TOL, "by the angle back")
	s.body.grip_min_angle = GRIP + 5.0 * DEG
	assert_almost_eq(_eval(s).wrist_deviation, 5.0 * DEG, TOL, "slid only to the diagonal")
	var square: ArmAnatomy.ArmSetup = _setup(at, Vector3.FORWARD, Vector3.UP, 1.0, 100.0 * DEG)
	square.grip_angle = 85.0 * DEG
	assert_almost_eq(_eval(square).wrist_deviation, -10.0 * DEG, TOL, "slid only to square")


func test_the_hand_rolls_round_the_shaft_to_where_the_forearm_holds_it_at_rest() -> void:
	var s: ArmAnatomy.ArmSetup = _setup(Vector3(0.0, -UPPER, -FORE), Vector3.FORWARD, Vector3.UP)
	var p := ArmAnatomy.ArmPose.new()
	ArmAnatomy.evaluate(s, 0.0, 1.1, p)
	assert_gt(absf(p.pronation), 30.0 * DEG, "rolled off rest")
	assert_almost_eq(ArmAnatomy._trace_roll(s, p), 0.0, 0.01, "least turned at rest")
	assert_almost_eq(ArmAnatomy._aligned_roll(s, p), 0.0, 0.01, "its long axis on the forearm")
	s.roll_free = false
	s.roll_lo = 0.4
	s.roll_hi = 0.9
	assert_almost_eq(ArmAnatomy._clamp_roll(s, 0.0), 0.4, 0.0001, "held to its range")
	var q := ArmAnatomy.ArmPose.new()
	ArmAnatomy.solve(s, q, ArmAnatomy.ArmPose.new())
	assert_between(q.roll, 0.4, 0.9, "the solve keeps it there")


func test_the_solve_holds_a_hand_in_reach_and_names_the_limit_past_it() -> void:
	var carry: ArmAnatomy.ArmSetup = _setup(Vector3(0.15, -0.35, -0.35), Vector3.FORWARD, Vector3.UP)
	var p := ArmAnatomy.ArmPose.new()
	var scratch := ArmAnatomy.ArmPose.new()
	ArmAnatomy.solve(carry, p, scratch)
	assert_true(p.feasible(), "a hand low in front is held")
	var far: ArmAnatomy.ArmSetup = _setup(Vector3(0.0, -0.3, -1.0), Vector3.FORWARD, Vector3.UP)
	ArmAnatomy.solve(far, p, scratch)
	assert_false(p.feasible(), "a metre out is not")
	assert_eq(p.binding, ArmAnatomy.Limit.REACH, "the arm's length binds")


func test_the_solve_keeps_the_arm_out_of_the_jersey_and_names_a_hand_in_it() -> void:
	var s: ArmAnatomy.ArmSetup = _setup(Vector3(-0.2, -0.45, -0.1), Vector3.FORWARD, Vector3.UP)
	# The jersey square to the shoulder, its shoulder line level with it and its
	# side 7 cm in from the joint, as the armhole puts it.
	s.torso = Transform3D(Basis.IDENTITY, Vector3(-0.3, -0.215, 0.0))
	var p := ArmAnatomy.ArmPose.new()
	ArmAnatomy.solve(s, p, ArmAnatomy.ArmPose.new())
	assert_false(p.feasible(), "the hand is inside it")
	assert_eq(p.binding, ArmAnatomy.Limit.HAND_IN_TORSO, "and that is what binds")
	s.hand = Vector3(0.05, -0.45, -0.45)
	ArmAnatomy.solve(s, p, ArmAnatomy.ArmPose.new())
	assert_lte(p.torso_depth, 0.0, "the elbow goes round it")
