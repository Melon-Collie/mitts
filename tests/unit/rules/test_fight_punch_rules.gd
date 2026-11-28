extends GutTest

# FightPunchRules: the sweep tests a punch is judged by, and what a landed one
# does — the rattle it adds, the fist speed it takes away, and the punch that
# is more than a man can take. Properties, not calibration.

const Hit = FightPunchRules.Hit


func test_a_sweep_through_a_ball_touches_it_where_it_enters() -> void:
	var t: float = FightPunchRules.sweep_sphere(Vector3(0, 0, 0), Vector3(0, 0, -1),
			Vector3(0, 0, -0.6), 0.1)
	assert_almost_eq(t, 0.5, 1e-4)
	assert_eq(FightPunchRules.sweep_sphere(Vector3(0, 0, 0), Vector3(0, 0, -1),
			Vector3(0.5, 0, -0.6), 0.1), -1.0, "passing wide misses")
	assert_eq(FightPunchRules.sweep_sphere(Vector3(0, 0, 0), Vector3(0, 0, -0.3),
			Vector3(0, 0, -0.6), 0.1), -1.0, "falling short misses")


func test_a_sweep_across_an_arm_is_caught_on_it() -> void:
	var t: float = FightPunchRules.sweep_capsule(Vector3(0, 0, 0), Vector3(0, 0, -1),
			Vector3(-0.3, 0, -0.5), Vector3(0.3, 0, -0.5), 0.05)
	assert_between(t, 0.4, 0.6)
	assert_eq(FightPunchRules.sweep_capsule(Vector3(0, 0, 0), Vector3(0, 0, -1),
			Vector3(0.4, 0, -0.5), Vector3(0.9, 0, -0.5), 0.05), -1.0)


func test_closing_speed_is_the_fist_on_him() -> void:
	assert_almost_eq(FightPunchRules.closing_speed(Vector3(0, 0, -8), Vector3(0, 0, -2),
			Vector3(0, 0, -1)), 6.0, 1e-4, "a man skating away takes some off it")
	assert_false(FightPunchRules.lands(FightPunchRules.MIN_LAND_M_S - 0.1), "a hand on him")
	assert_true(FightPunchRules.lands(FightPunchRules.MIN_LAND_M_S))


func test_the_head_rattles_most_a_block_least() -> void:
	var s: float = FightFistRules.MAX_SPEED_M_S
	var head: float = FightPunchRules.rattle_added(Hit.HEAD, s)
	var body: float = FightPunchRules.rattle_added(Hit.BODY, s)
	var block: float = FightPunchRules.rattle_added(Hit.BLOCKED, s)
	assert_gt(head, body)
	assert_gt(body, block)
	assert_gt(block, 0.0)
	assert_lt(FightPunchRules.rattle_added(Hit.HEAD, s * 0.5), head, "a harder punch rattles more")


func test_a_rattled_man_has_slower_fists() -> void:
	assert_eq(FightPunchRules.fist_scale(0.0), 1.0)
	var full: float = FightPunchRules.RATTLE_MAX_S
	assert_lt(FightPunchRules.fist_scale(full * 0.5), 1.0)
	assert_lt(FightPunchRules.fist_scale(full), FightPunchRules.fist_scale(full * 0.5))


func test_no_punch_moves_a_man_like_a_check() -> void:
	var dv: float = FightPunchRules.impulse_dv(FightFistRules.MAX_SPEED_M_S, 90.0)
	assert_lt(dv, BodyBalanceRules.Config.new().balance_ref_dv * 0.5,
			"a sound man rides any punch on his feet")


func test_no_one_punch_puts_a_sound_man_down() -> void:
	var s: float = FightFistRules.MAX_SPEED_M_S
	for hit: int in [Hit.HEAD, Hit.BODY, Hit.BLOCKED]:
		assert_false(FightPunchRules.puts_down(hit, 0.0, s))
	assert_gt(FightPunchRules.RATTLE_MAX_S, 2.0 * FightPunchRules.RATTLE_HEAD_S,
			"nor do two")


func test_the_punch_that_is_more_than_he_can_take_puts_him_down() -> void:
	var s: float = FightFistRules.MAX_SPEED_M_S
	var full: float = FightPunchRules.RATTLE_MAX_S
	for hit: int in [Hit.HEAD, Hit.BODY, Hit.BLOCKED]:
		assert_true(FightPunchRules.puts_down(hit, full, s), "rattled to the full, any punch does")
	var nearly: float = full - 0.5 * FightPunchRules.rattle_added(Hit.HEAD, s)
	assert_true(FightPunchRules.puts_down(Hit.HEAD, nearly, s))
	assert_false(FightPunchRules.puts_down(Hit.HEAD, nearly, 0.25 * s), "a light one does not")
	assert_false(FightPunchRules.puts_down(Hit.BLOCKED, nearly, s), "nor one he blocks")


func test_a_guard_takes_more_than_twice_the_punches() -> void:
	var s: float = FightFistRules.MAX_SPEED_M_S
	assert_lt(FightPunchRules.rattle_added(Hit.BLOCKED, s),
			0.5 * FightPunchRules.rattle_added(Hit.HEAD, s))


func test_the_head_is_the_hardest_feedback() -> void:
	var s: float = FightFistRules.MAX_SPEED_M_S
	assert_gt(FightPunchRules.intensity(Hit.HEAD, s), FightPunchRules.intensity(Hit.BODY, s))
	assert_gt(FightPunchRules.intensity(Hit.BODY, s), FightPunchRules.intensity(Hit.BLOCKED, s))
	assert_eq(FightPunchRules.reel(Hit.BLOCKED, s), 0.0, "a block reels nobody")
