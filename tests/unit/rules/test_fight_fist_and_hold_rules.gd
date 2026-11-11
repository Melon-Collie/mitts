extends GutTest

# FightFistRules (the punching fist on the cursor) and FightHoldRules (the grip
# and the band it holds the pair in). Properties, not calibration.

const SHOULDER := Vector3(0.2, 0.45, 0.0)
const REACH: float = 0.6
const GUARD_Y: float = 0.57
const CHIN_Y: float = 0.6
const DT: float = 1.0 / 90.0


func test_the_fist_goes_where_the_cursor_is_within_reach() -> void:
	var t: Vector3 = FightFistRules.target(SHOULDER, Vector3(0.25, 0.0, -0.3), REACH,
			GUARD_Y, CHIN_Y)
	assert_almost_eq(Vector2(t.x, t.z), Vector2(0.25, -0.3), Vector2(0.001, 0.001))


func test_a_cursor_past_reach_holds_the_fist_at_the_reach() -> void:
	var t: Vector3 = FightFistRules.target(SHOULDER, Vector3(0.2, 0.0, -3.0), REACH,
			GUARD_Y, CHIN_Y)
	assert_almost_eq(t.distance_to(SHOULDER), REACH, 0.001)
	assert_lt(t.z, SHOULDER.z, "straight out in front")


func test_no_fist_goes_back_into_its_own_chest() -> void:
	var t: Vector3 = FightFistRules.target(SHOULDER, Vector3(0.0, 0.0, 0.5), REACH,
			GUARD_Y, CHIN_Y)
	assert_almost_eq(t.z, SHOULDER.z - FightFistRules.MIN_FORWARD_M, 0.001)


func test_the_fist_rises_from_the_guard_to_his_chin_as_the_arm_straightens() -> void:
	var low_chin: float = 0.3
	var bent: Vector3 = FightFistRules.target(SHOULDER, SHOULDER + Vector3(0.0, 0.0, -0.2),
			REACH, GUARD_Y, low_chin)
	var straight: Vector3 = FightFistRules.target(SHOULDER, SHOULDER + Vector3(0.0, 0.0, -2.0),
			REACH, GUARD_Y, low_chin)
	assert_almost_eq(bent.y, GUARD_Y, 0.001, "held at the guard while bent")
	assert_almost_eq(straight.y, low_chin, 0.001, "at his chin, straight out at him")


func test_the_fist_never_outruns_its_speed_or_acceleration() -> void:
	var pos := Vector3(0.1, GUARD_Y, -0.3)
	var vel := Vector3.ZERO
	var target := Vector3(0.1, CHIN_Y, -0.9)
	var top: float = 0.0
	for i: int in 30:
		var next: Vector3 = FightFistRules.step_velocity(pos, vel, target, DT,
				FightFistRules.MAX_SPEED_M_S, FightFistRules.MAX_ACCEL_M_S2)
		assert_lte((next - vel).length(), FightFistRules.MAX_ACCEL_M_S2 * DT + 1e-4)
		vel = next
		pos += vel * DT
		top = maxf(top, vel.length())
	assert_lte(top, FightFistRules.MAX_SPEED_M_S + 1e-4)
	assert_gt(top, 0.5 * FightFistRules.MAX_SPEED_M_S, "a punch gets up to speed")
	assert_almost_eq(pos.distance_to(target), 0.0, 0.01, "and arrives")


func test_a_straight_arm_holds_the_fist() -> void:
	var held: Vector3 = FightFistRules.held_to_reach(SHOULDER, SHOULDER + Vector3(0, 0, -1.0), REACH)
	assert_almost_eq(held.distance_to(SHOULDER), REACH, 1e-5)
	var inside := SHOULDER + Vector3(0, 0, -0.3)
	assert_eq(FightFistRules.held_to_reach(SHOULDER, inside, REACH), inside)


func test_the_hand_takes_whichever_it_is_nearer_and_can_reach() -> void:
	var shoulder := Vector3.ZERO
	var jersey := Vector3(0.0, 0.0, -0.5)
	var arm := Vector3(0.3, 0.0, -0.4)
	assert_eq(FightHoldRules.choose(Vector3(0.0, 0.0, -0.3), shoulder, REACH, jersey, arm,
			FightHoldRules.Grip.ARM_TOP), FightHoldRules.Grip.JERSEY)
	assert_eq(FightHoldRules.choose(Vector3(0.3, 0.0, -0.3), shoulder, REACH, jersey, arm,
			FightHoldRules.Grip.ARM_TOP), FightHoldRules.Grip.ARM_TOP)
	assert_eq(FightHoldRules.choose(Vector3.ZERO, shoulder, REACH, Vector3(0, 0, -2),
			Vector3(0, 0, -2), FightHoldRules.Grip.ARM_TOP), FightHoldRules.Grip.NONE,
			"out of reach, nothing")


func test_only_the_held_arm_is_tied_up() -> void:
	assert_true(FightHoldRules.tied(FightHoldRules.Side.TOP, FightHoldRules.Grip.ARM_TOP))
	assert_false(FightHoldRules.tied(FightHoldRules.Side.BOTTOM, FightHoldRules.Grip.ARM_TOP),
			"swapping hands frees the punch")
	assert_false(FightHoldRules.tied(FightHoldRules.Side.TOP, FightHoldRules.Grip.JERSEY))


func test_the_sweater_is_taken_at_his_chest_on_the_holders_side() -> void:
	var p: Vector3 = FightHoldRules.jersey_point(Vector3.ZERO, 0.35, Vector3(0.0, 0.0, -1.0), 1.5)
	assert_lt(p.z, 0.0)
	assert_almost_eq(p.y, 1.5 - FightHoldRules.JERSEY_DROP_M, 1e-5)


func test_inside_the_band_each_body_keeps_its_own_velocity() -> void:
	assert_eq(FightHoldRules.band_along(0.8, 1.0, 2.0, 0.7, 1.0, 90.0, 90.0), 1.0)


func test_out_of_the_band_the_parting_is_taken_up_and_shared_by_mass() -> void:
	var m_self: float = 80.0
	var m_other: float = 100.0
	var dist: float = 1.2
	var u_self: float = -1.0   # skating away from him
	var u_other: float = 0.0
	var mine: float = FightHoldRules.band_along(dist, u_self, u_other, 0.7, 1.0, m_self, m_other)
	var his: float = -FightHoldRules.band_along(dist, -u_other, -u_self, 0.7, 1.0, m_other, m_self)
	assert_almost_eq(his - mine, -(dist - 1.0) * FightHoldRules.BAND_RATE, 1e-4,
			"no longer parting: closing back to the band")
	assert_almost_eq(m_self * (mine - u_self), -m_other * (his - u_other), 1e-3,
			"one exchange of momentum, each body's share")
	assert_gt(absf(mine - u_self), absf(his - u_other), "the lighter body moves more")


func test_with_no_grip_they_still_cannot_pass_through_each_other() -> void:
	var mine: float = FightHoldRules.band_along(0.5, 1.0, 0.0, 0.7, INF, 90.0, 90.0)
	assert_lt(mine, 1.0, "driving into him is held off")
	assert_eq(FightHoldRules.band_along(5.0, -3.0, 0.0, 0.7, INF, 90.0, 90.0), -3.0,
			"and nothing holds them together")


func test_an_arm_is_caught_only_while_it_is_thrown() -> void:
	var shoulder := Vector3.ZERO
	assert_false(FightHoldRules.thrown(shoulder, Vector3(0.0, 0.0, -0.3), REACH), "up in a guard")
	assert_true(FightHoldRules.thrown(shoulder, Vector3(0.0, 0.0, -0.55), REACH), "out at him")
	assert_eq(FightHoldRules.choose(Vector3(0.3, 0.0, -0.3), shoulder, REACH,
			Vector3(0.0, 0.0, -0.5), Vector3(0.3, 0.0, -0.4), FightHoldRules.Grip.NONE),
			FightHoldRules.Grip.JERSEY, "an arm not thrown is never the grip")
