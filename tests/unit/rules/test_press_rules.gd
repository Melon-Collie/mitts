extends GutTest

# PressRules' properties: what any honest version of the press does, whatever
# its calibration (tests/CLAUDE.md, Calibration and characterisation tests).

const DT: float = 1.0 / 120.0
const Posture = SkaterMovementRules.Posture
const AHEAD := Vector2(0.0, -1.0)
const SIDE := Vector2(1.0, 0.0)


func _cfg() -> SkaterMovementRules.MovementConfig:
	var cfg := SkaterMovementRules.MovementConfig.new()
	cfg.thrust = 10.5
	cfg.stop_decel = 9.0
	cfg.turn_accel = 9.0
	cfg.lateral_grip = 1.0
	cfg.stance_grip_mult = 2.0
	cfg.stance_stride_mult = 0.6
	cfg.commit_grip_mult = 0.6
	cfg.commit_stride_mult = 0.5
	cfg.crossover_thrust_multiplier = 0.8
	cfg.backward_thrust_multiplier = 0.5
	cfg.move_deadzone = 0.1
	cfg.power_knee_speed = 2.6
	cfg.friction = 0.35
	cfg.friction_drag = 0.09
	return cfg


func _drive(posture: int, intent: Vector2, n: Vector2, braking: bool = false,
		stagger: float = 1.0) -> float:
	return PressRules.drive(_cfg(), 10.5, posture, braking, false, stagger, AHEAD, intent, n, 0.0)


func _hold(posture: int, braking: bool, n: Vector2, stagger: float = 1.0) -> float:
	return PressRules.hold(_cfg(), posture, braking, false, stagger, AHEAD, n, 0.0)


func test_the_commit_drives_harder_than_skating_in() -> void:
	assert_gt(_drive(Posture.COMMIT, AHEAD, AHEAD), _drive(Posture.UPRIGHT, AHEAD, AHEAD))
	assert_gt(_drive(Posture.UPRIGHT, AHEAD, AHEAD), _drive(Posture.STANCE, AHEAD, AHEAD))


func test_braking_and_standing_still_drive_nothing() -> void:
	assert_eq(_drive(Posture.COMMIT, AHEAD, AHEAD, true), 0.0)
	assert_eq(_drive(Posture.COMMIT, Vector2.ZERO, AHEAD), 0.0)


func test_a_push_away_drives_negative() -> void:
	assert_lt(_drive(Posture.COMMIT, -AHEAD, AHEAD), 0.0)


func test_the_stagger_takes_from_the_drive_and_the_hold() -> void:
	assert_lt(_drive(Posture.COMMIT, AHEAD, AHEAD, false, 0.5), _drive(Posture.COMMIT, AHEAD, AHEAD))
	assert_lt(_hold(Posture.STANCE, true, AHEAD, 0.6), _hold(Posture.STANCE, true, AHEAD))


func test_across_the_blades_holds_more_than_along_them() -> void:
	assert_gt(_hold(Posture.UPRIGHT, false, SIDE), _hold(Posture.UPRIGHT, false, AHEAD))
	assert_almost_eq(_hold(Posture.UPRIGHT, false, AHEAD), _cfg().friction, 1e-6,
			"along them the blades glide")


func test_braking_holds_from_any_side() -> void:
	for deg: float in [0.0, 30.0, 90.0, 150.0]:
		var n: Vector2 = AHEAD.rotated(deg_to_rad(deg))
		assert_almost_eq(_hold(Posture.UPRIGHT, true, n), _hold(Posture.UPRIGHT, true, AHEAD), 1e-6)


func test_the_stance_anchors_more_than_upright() -> void:
	assert_gt(_hold(Posture.STANCE, true, AHEAD), _hold(Posture.UPRIGHT, true, AHEAD))
	assert_gt(_hold(Posture.STANCE, false, SIDE), _hold(Posture.UPRIGHT, false, SIDE))


func test_contact_only_pushes() -> void:
	assert_false(PressRules.pressing(0.0, 0.0), "nobody drives")
	assert_false(PressRules.pressing(-3.0, 0.0), "one skates away")
	assert_true(PressRules.pressing(5.0, -1.0), "one drives into the other as he leaves slower")
	assert_true(PressRules.pressing(5.0, 5.0), "both push")


func test_the_edges_hold_and_never_push_back() -> void:
	# At rest under a push the edges can hold, nothing moves.
	assert_eq(PressRules.pair_accel(1.0, 5.0, 0.0, 1.0, 0.0, 9.0, 0.0, DT), 0.0)
	# Moving with nothing driving, the edges stop the pair and never reverse it.
	var a: float = PressRules.pair_accel(1.0, 0.0, 0.0, 1.0, 0.0, 9.0, 0.03, DT)
	assert_almost_eq(0.03 + a * DT, 0.0, 1e-6)


func test_it_is_antisymmetric() -> void:
	for c: Array in [[1.0, 10.5, 0.5, 1.2, 3.0, 9.0, 0.4], [1.3, 0.0, 9.0, 0.8, 6.0, 0.0, -0.2],
			[1.0, 10.5, 0.0, 1.0, 0.0, 13.5, 0.0], [0.9, 10.5, 0.0, 1.1, 0.0, 0.0, 2.0]]:
		var ab: float = PressRules.pair_accel(c[0], c[1], c[2], c[3], c[4], c[5], c[6], DT)
		var ba: float = PressRules.pair_accel(c[3], c[4], c[5], c[0], c[1], c[2], -c[6], DT)
		assert_almost_eq(ab, -ba, 1e-6, str(c))


func test_it_is_continuous_past_the_hold() -> void:
	var h: float = 9.0
	var just_past: float = PressRules.pair_accel(1.0, h + 0.001, 0.0, 1.0, 0.0, h, 0.0, DT)
	assert_between(just_past, 0.0, 0.001, "a man is moved slowly just past his hold, never snapped")


func test_it_is_monotone_in_mass_drive_and_hold() -> void:
	var base: float = PressRules.pair_accel(1.0, 10.5, 0.0, 1.0, 0.0, 9.0, 0.0, DT)
	assert_gt(PressRules.pair_accel(1.2, 10.5, 0.0, 1.0, 0.0, 9.0, 0.0, DT), base, "heavier driver")
	assert_gt(base, PressRules.pair_accel(1.0, 10.5, 0.0, 1.2, 0.0, 9.0, 0.0, DT), "heavier man")
	assert_gt(PressRules.pair_accel(1.0, 12.0, 0.0, 1.0, 0.0, 9.0, 0.0, DT), base, "harder drive")
	assert_gt(base, PressRules.pair_accel(1.0, 10.5, 0.0, 1.0, 0.0, 10.0, 0.0, DT), "firmer hold")
	assert_gt(base, PressRules.pair_accel(1.0, 10.5, 0.0, 1.0, 2.0, 9.0, 0.0, DT), "he pushes back")


# An anchored man (braking, in the stance) holds an equal man's full drive.
func test_an_anchored_man_holds_an_equal_drive() -> void:
	var drive: float = _drive(Posture.COMMIT, AHEAD, AHEAD)
	var anchored: float = _hold(Posture.STANCE, true, AHEAD)
	assert_eq(PressRules.pair_accel(1.0, drive, 0.0, 1.0, 0.0, anchored, 0.0, DT), 0.0)
	assert_gt(PressRules.pair_accel(1.0, drive, 0.0, 1.0, 0.0, _hold(Posture.UPRIGHT, true, AHEAD),
			0.0, DT), 0.0, "upright, the stop alone gives")


func test_the_passive_share_is_the_uncommitted_bumps() -> void:
	var skater := Skater.new()
	assert_almost_eq(PressRules.PASSIVE_DRIVE_SHARE, skater.hit_passive_transfer_mult, 1e-6)
	skater.free()


func test_the_stride_is_power_limited_past_its_knee() -> void:
	var slow: float = PressRules.drive(_cfg(), 10.5, Posture.COMMIT, false, false, 1.0, AHEAD,
			AHEAD, AHEAD, 2.0)
	var fast: float = PressRules.drive(_cfg(), 10.5, Posture.COMMIT, false, false, 1.0, AHEAD,
			AHEAD, AHEAD, 5.2)
	assert_almost_eq(fast, slow * 0.5, 1e-6, "twice the knee, half the drive")
	assert_almost_eq(PressRules.drive(_cfg(), 10.5, Posture.COMMIT, false, false, 1.0, AHEAD,
			AHEAD, AHEAD, -5.2), slow, 1e-6, "pushing against the motion is not power-limited")


func test_touching_is_the_slack_widened_by_a_reader_timing() -> void:
	var slack: float = PressRules.CONTACT_SLACK_M
	assert_true(PressRules.touching(slack - 0.001, 0.0, 0.0))
	assert_false(PressRules.touching(slack, 6.0, 0.0), "a reader with the bodies: the slack alone")
	var timing: float = 0.01
	assert_true(PressRules.touching(slack + 6.0 * timing - 0.001, 6.0, timing))
	assert_true(PressRules.touching(slack + 6.0 * timing - 0.001, -6.0, timing),
			"his travel either way")
	assert_false(PressRules.touching(slack + 6.0 * timing + 0.001, 6.0, timing))
