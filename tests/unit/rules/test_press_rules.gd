extends GutTest

# PressRules' properties: what any honest version of the press does, whatever
# its calibration (tests/CLAUDE.md, Calibration and characterisation tests).

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
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
		stagger: float = 1.0, facing: Vector2 = AHEAD, u: float = 0.0) -> float:
	return PressRules.drive(_cfg(), 10.5, posture, braking, false, stagger, facing, intent, n, u)


func _hold(posture: int, braking: bool, n: Vector2, stagger: float = 1.0, u: float = 0.0) -> float:
	return PressRules.hold(_cfg(), posture, braking, false, stagger, AHEAD, n, u)


func test_an_engaged_body_drives_harder_than_one_skating_in() -> void:
	assert_gt(_drive(Posture.COMMIT, AHEAD, AHEAD), _drive(Posture.UPRIGHT, AHEAD, AHEAD))


func test_the_stance_is_an_unengaged_body() -> void:
	assert_eq(_drive(Posture.STANCE, AHEAD, AHEAD), _drive(Posture.UPRIGHT, AHEAD, AHEAD))
	for braking: bool in [false, true]:
		assert_eq(_hold(Posture.STANCE, braking, AHEAD), _hold(Posture.UPRIGHT, braking, AHEAD))


func test_braking_and_standing_still_drive_nothing() -> void:
	assert_eq(_drive(Posture.COMMIT, AHEAD, AHEAD, true), 0.0)
	assert_eq(_drive(Posture.COMMIT, Vector2.ZERO, AHEAD), 0.0)


func test_a_push_away_drives_negative() -> void:
	assert_lt(_drive(Posture.COMMIT, -AHEAD, AHEAD), 0.0)


func test_the_stagger_takes_from_the_drive_and_the_hold() -> void:
	assert_lt(_drive(Posture.COMMIT, AHEAD, AHEAD, false, 0.5), _drive(Posture.COMMIT, AHEAD, AHEAD))
	assert_lt(_hold(Posture.COMMIT, true, AHEAD, 0.6), _hold(Posture.COMMIT, true, AHEAD))


# The legs drive the way he faces: the more squarely he faces the man, the
# harder he pushes him.
func test_he_pushes_hardest_chest_on() -> void:
	var prev: float = INF
	for deg: float in [0.0, 30.0, 60.0, 90.0]:
		var facing: Vector2 = AHEAD.rotated(deg_to_rad(deg))
		var d: float = _drive(Posture.COMMIT, AHEAD, AHEAD, false, 1.0, facing)
		assert_lt(d, prev + 1e-6, "%d degrees off him" % deg)
		prev = d
	assert_almost_eq(prev, _drive(Posture.COMMIT, AHEAD, AHEAD) * PressRules.SIDE_ON_SHARE, 1e-6)
	assert_almost_eq(_drive(Posture.COMMIT, AHEAD, AHEAD, false, 1.0, -AHEAD), prev, 1e-6,
			"with his back to him, no better than side-on")


func test_only_an_engaged_body_sets_his_edges() -> void:
	var set_hold: float = _hold(Posture.COMMIT, true, AHEAD)
	assert_gt(set_hold, _drive(Posture.COMMIT, AHEAD, AHEAD), "and they hold an equal drive")
	assert_lt(_hold(Posture.UPRIGHT, true, AHEAD), 0.5 * set_hold, "a stop is not a stand")
	assert_lt(_hold(Posture.COMMIT, false, AHEAD), 0.1 * set_hold, "engaged and not braking, he glides")
	assert_almost_eq(_hold(Posture.UPRIGHT, false, AHEAD), _cfg().friction, 1e-6)


func test_set_edges_hold_from_any_side() -> void:
	for deg: float in [0.0, 30.0, 90.0, 150.0]:
		var n: Vector2 = AHEAD.rotated(deg_to_rad(deg))
		assert_almost_eq(_hold(Posture.COMMIT, true, n), _hold(Posture.COMMIT, true, AHEAD), 1e-6)


# Set, they hold more than once they have broken loose; and a staggered man's
# are loose however still he stands.
func test_edges_broken_loose_hold_less() -> void:
	var set_hold: float = _hold(Posture.COMMIT, true, AHEAD)
	var prev: float = set_hold
	for i: int in 13:
		var h: float = _hold(Posture.COMMIT, true, AHEAD, 1.0, 0.05 * i)
		assert_lte(h, prev + 1e-6, "never firmer the faster he slides")
		prev = h
	assert_almost_eq(prev, set_hold * PressRules.LOOSE_SHARE, 1e-6)
	assert_lt(prev, _drive(Posture.COMMIT, AHEAD, AHEAD), "loose, an equal drive moves him")
	assert_almost_eq(_hold(Posture.COMMIT, true, AHEAD, 0.999), set_hold * 0.999 * PressRules.LOOSE_SHARE,
			1e-6, "staggered")


func test_a_press_fades_out_at_a_walk() -> void:
	var from_rest: float = _drive(Posture.COMMIT, AHEAD, AHEAD)
	var prev: float = from_rest
	for i: int in 16:
		var d: float = _drive(Posture.COMMIT, AHEAD, AHEAD, false, 1.0, AHEAD, 0.1 * i)
		assert_lte(d, prev + 1e-6)
		prev = d
	assert_eq(_drive(Posture.COMMIT, AHEAD, AHEAD, false, 1.0, AHEAD, PressRules.MAX_SPEED_M_S), 0.0)
	assert_almost_eq(_drive(Posture.COMMIT, AHEAD, AHEAD, false, 1.0, AHEAD, -3.0), from_rest, 1e-6,
			"pushing against the motion is whole")


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


func test_the_passive_share_is_the_uncommitted_bumps() -> void:
	var skater := Skater.new()
	assert_almost_eq(PressRules.PASSIVE_DRIVE_SHARE, skater.hit_passive_transfer_mult, 1e-6)
	skater.free()


func test_touching_is_the_slack_widened_by_a_reader_timing() -> void:
	var slack: float = PressRules.CONTACT_SLACK_M
	assert_true(PressRules.touching(slack - 0.001, 0.0, 0.0))
	assert_false(PressRules.touching(slack, 6.0, 0.0), "a reader with the bodies: the slack alone")
	var timing: float = 0.01
	assert_true(PressRules.touching(slack + 6.0 * timing - 0.001, 6.0, timing))
	assert_true(PressRules.touching(slack + 6.0 * timing - 0.001, -6.0, timing),
			"his travel either way")
	assert_false(PressRules.touching(slack + 6.0 * timing + 0.001, 6.0, timing))
