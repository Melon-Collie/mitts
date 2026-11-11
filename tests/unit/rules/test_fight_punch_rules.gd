extends GutTest

# FightPunchRules: the sweep tests a punch is judged by, and what a landed one
# does — the rattle it adds and wears off, and the balance and fist speed it
# takes away. Properties, not calibration.

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


func test_a_rattled_man_has_less_balance_and_slower_fists() -> void:
	assert_eq(FightPunchRules.balance_scale(0.0), 1.0)
	assert_eq(FightPunchRules.fist_scale(0.0), 1.0)
	var full: float = FightPunchRules.RATTLE_MAX_S
	assert_gt(FightPunchRules.balance_scale(full * 0.5), 1.0)
	assert_gt(FightPunchRules.balance_scale(full), FightPunchRules.balance_scale(full * 0.5))
	assert_lt(FightPunchRules.fist_scale(full), 1.0)


func test_no_punch_moves_a_man_like_a_check() -> void:
	var dv: float = FightPunchRules.impulse_dv(FightFistRules.MAX_SPEED_M_S, 90.0)
	assert_lt(dv, BodyBalanceRules.Config.new().balance_ref_dv * 0.5,
			"a sound man rides any punch on his feet")


func test_a_full_rattle_leaves_a_clean_shot_enough_to_drop_him() -> void:
	var cfg := BodyBalanceRules.Config.new()
	var dv: float = FightPunchRules.impulse_dv(FightFistRules.MAX_SPEED_M_S, 90.0)
	# Straight back off a punch to the face, square to the hitter.
	var hit := Vector2(0.0, dv)
	var facing := Vector2(0.0, -1.0)
	var posture: int = BodyBalanceRules.Posture.UPRIGHT
	assert_lt(BodyBalanceRules.overshoot(hit, facing, posture, 1.0, cfg), 1.0, "sound, he rides it")
	var rattled: Vector2 = hit * FightPunchRules.balance_scale(FightPunchRules.RATTLE_MAX_S)
	assert_gt(BodyBalanceRules.overshoot(rattled, facing, posture, 1.0, cfg), 1.0,
			"rattled to the full, it puts him down")


func test_the_head_is_the_hardest_feedback() -> void:
	var s: float = FightFistRules.MAX_SPEED_M_S
	assert_gt(FightPunchRules.intensity(Hit.HEAD, s), FightPunchRules.intensity(Hit.BODY, s))
	assert_gt(FightPunchRules.intensity(Hit.BODY, s), FightPunchRules.intensity(Hit.BLOCKED, s))
	assert_eq(FightPunchRules.reel(Hit.BLOCKED, s), 0.0, "a block reels nobody")
