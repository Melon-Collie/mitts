extends GutTest

# CrossCheckRules: the phase machine on the Ctrl press, the reach and the cone,
# and the push model — a stride delivered through the arms, answered by the
# victim's edges across his blades and his own stride pushing back.

const Phase = CrossCheckRules.Phase
const DT: float = 1.0 / 120.0
const THRUST: float = GameRules.DEFAULT_SKATER_THRUST_M_S2
const FACING_PLUS_X := Vector2(1.0, 0.0)

var _cfg: SkaterMovementRules.MovementConfig = SkaterMovementRules.league_config()


func _run(phase: int, elapsed: float, seconds: float) -> Vector2:
	var s := Vector2(phase, elapsed)
	for _i: int in roundi(seconds / DT):
		s = CrossCheckRules.step(int(s.x), s.y, false, true, false, DT)
	return s


# ── phases ───────────────────────────────────────────────────────────────────

func test_a_press_throws_then_the_stick_comes_back_then_rearms() -> void:
	var s: Vector2 = CrossCheckRules.step(Phase.IDLE, 0.0, true, true, false, DT)
	assert_eq(int(s.x), Phase.EXTEND)
	s = _run(int(s.x), s.y, CrossCheckRules.PUSH_S + DT)
	assert_eq(int(s.x), Phase.RECOVER)
	s = _run(int(s.x), s.y, CrossCheckRules.RECOVER_S + DT)
	assert_eq(int(s.x), Phase.REARM)
	s = _run(int(s.x), s.y, CrossCheckRules.REARM_S + DT)
	assert_eq(int(s.x), Phase.IDLE)


func test_no_throw_without_a_press_or_while_ineligible() -> void:
	assert_eq(int(CrossCheckRules.step(Phase.IDLE, 0.0, false, true, false, DT).x), Phase.IDLE)
	assert_eq(int(CrossCheckRules.step(Phase.IDLE, 0.0, true, false, false, DT).x), Phase.IDLE)


func test_a_press_during_the_rearm_is_ignored_and_an_interruption_drops_it() -> void:
	var s: Vector2 = CrossCheckRules.step(Phase.REARM, 0.0, true, true, false, DT)
	assert_eq(int(s.x), Phase.REARM)
	s = CrossCheckRules.step(Phase.EXTEND, 0.02, false, true, true, DT)
	assert_eq(int(s.x), Phase.IDLE)


func test_only_the_push_lands_and_the_stick_is_out_through_the_recovery() -> void:
	assert_true(CrossCheckRules.can_land(Phase.EXTEND))
	for phase: int in [Phase.IDLE, Phase.RECOVER, Phase.REARM]:
		assert_false(CrossCheckRules.can_land(phase))
	assert_true(CrossCheckRules.is_stick_busy(Phase.EXTEND))
	assert_true(CrossCheckRules.is_stick_busy(Phase.RECOVER))
	assert_false(CrossCheckRules.is_stick_busy(Phase.REARM))
	assert_false(CrossCheckRules.is_stick_busy(Phase.IDLE))


func test_the_wire_round_trips_every_timed_phase() -> void:
	for phase: int in [Phase.IDLE, Phase.EXTEND, Phase.RECOVER, Phase.REARM]:
		var elapsed: float = 0.3 if phase == Phase.REARM else 0.05
		var packed: int = CrossCheckRules.pack(phase, elapsed)
		assert_lt(packed, 256, "one byte")
		assert_eq(CrossCheckRules.unpack_phase(packed), phase)
		assert_almost_eq(CrossCheckRules.unpack_elapsed(packed), elapsed, 0.5 / 120.0)
	assert_lte(roundi(CrossCheckRules.REARM_S * 120.0), 63, "the longest phase fits its bits")


# ── reach ────────────────────────────────────────────────────────────────────

func test_reach_is_an_arms_length_in_front_of_the_chest() -> void:
	var r: float = 0.35
	var near := Vector3(2.0 * r + CrossCheckRules.REACH_M - 0.05, 0.0, 0.0)
	var far := Vector3(2.0 * r + CrossCheckRules.REACH_M + 0.05, 0.0, 0.0)
	assert_true(CrossCheckRules.in_reach(Vector3.ZERO, FACING_PLUS_X, r, near, r))
	assert_false(CrossCheckRules.in_reach(Vector3.ZERO, FACING_PLUS_X, r, far, r), "out of reach")
	assert_false(CrossCheckRules.in_reach(Vector3.ZERO, -FACING_PLUS_X, r, near, r),
			"behind him")
	assert_false(CrossCheckRules.in_reach(Vector3.ZERO, FACING_PLUS_X.rotated(deg_to_rad(60.0)), r, near, r),
			"off his shoulder, outside the cone")


# ── the push ─────────────────────────────────────────────────────────────────

func _dv(m_s: float, m_v: float, victim_facing: Vector2, edge: float = 0.0,
		intent: Vector2 = Vector2.ZERO, drive: float = 0.0) -> float:
	return CrossCheckRules.victim_dv(m_s, THRUST, m_v, Vector2(1.0, 0.0), victim_facing,
			edge, intent, drive)


func test_the_shove_is_the_shovers_stride_on_the_victims_mass() -> void:
	assert_almost_eq(_dv(1.0, 1.0, FACING_PLUS_X), THRUST * CrossCheckRules.PUSH_S, 1e-5,
			"neutral, along his blades, unresisted")
	assert_gt(_dv(1.28, 1.0, FACING_PLUS_X), _dv(1.0, 1.0, FACING_PLUS_X), "heavier shover")
	assert_gt(_dv(1.0, 0.79, FACING_PLUS_X), _dv(1.0, 1.0, FACING_PLUS_X), "lighter victim")


func test_across_the_blades_the_edges_hold_and_the_stance_holds_more() -> void:
	var across := Vector2(0.0, -1.0)   # the push along +x is square across his blades
	var upright: float = CrossCheckRules.edge_accel(_cfg, SkaterMovementRules.Posture.UPRIGHT, 1.0)
	var stance: float = CrossCheckRules.edge_accel(_cfg, SkaterMovementRules.Posture.STANCE, 1.0)
	assert_gt(stance, upright)
	var along_dv: float = _dv(1.0, 1.0, FACING_PLUS_X, upright)
	var across_dv: float = _dv(1.0, 1.0, across, upright)
	assert_lt(across_dv, along_dv, "his edges take the push across his blades")
	assert_almost_eq(along_dv, THRUST * CrossCheckRules.PUSH_S, 1e-5, "and none of it along them")
	assert_lte(_dv(1.0, 1.0, across, stance), across_dv, "loaded low, he gives less")
	var staggered: float = CrossCheckRules.edge_accel(_cfg, SkaterMovementRules.Posture.UPRIGHT, 0.6)
	assert_gte(_dv(1.0, 1.0, across, staggered), across_dv, "off his edges, he gives more")


func test_pushing_back_into_it_resists_and_nothing_pulls_him() -> void:
	var drive: float = CrossCheckRules.drive_accel(_cfg, SkaterMovementRules.Posture.UPRIGHT, THRUST)
	var free: float = _dv(1.0, 1.0, FACING_PLUS_X)
	assert_lt(_dv(1.0, 1.0, FACING_PLUS_X, 0.0, Vector2(-1.0, 0.0), drive), free, "leaning in")
	assert_almost_eq(_dv(1.0, 1.0, FACING_PLUS_X, 0.0, Vector2(1.0, 0.0), drive), free, 1e-5,
			"skating away adds nothing: the push is the shover's")
	assert_eq(_dv(0.79, 1.28, Vector2(0.0, -1.0),
			CrossCheckRules.edge_accel(_cfg, SkaterMovementRules.Posture.STANCE, 1.0),
			Vector2(-1.0, 0.0), drive), 0.0, "a set man is not moved, nor pulled")


func test_a_neutral_shove_along_the_blades_staggers() -> void:
	var cfg := BodyCheckRules.Config.new()
	var dv: float = _dv(1.0, 1.0, FACING_PLUS_X)
	assert_gt(dv, cfg.min_impulse, "it lands")
	assert_lt(dv, cfg.knockdown_impulse)


func test_no_legal_pair_of_builds_knocks_down_on_a_standstill_shove() -> void:
	var cfg := BodyCheckRules.Config.new()
	var most_force: float = 0.0
	var least_mass: float = INF
	for h: int in range(PlayerAttributes.HEIGHT_MIN, PlayerAttributes.HEIGHT_MAX + 1):
		for w: int in range(PlayerAttributes.weight_min(h), PlayerAttributes.weight_max(h) + 1):
			for profile: int in [PlayerAttributes.PROFILE_AGILITY, PlayerAttributes.PROFILE_BALANCED,
					PlayerAttributes.PROFILE_POWER]:
				var a := PlayerAttributes.new(h, w, profile)
				most_force = maxf(most_force, a.mass_mult() * THRUST * a.accel_mult())
				least_mass = minf(least_mass, a.mass_mult())
	var worst: float = CrossCheckRules.victim_dv(most_force / THRUST, THRUST, least_mass,
			Vector2(1.0, 0.0), FACING_PLUS_X, 0.0, Vector2.ZERO, 0.0)
	assert_lt(worst, cfg.knockdown_impulse,
			"the hardest legal shove on the lightest body, unresisted: %.2f m/s" % worst)
