extends GutTest

# AIShotHolds — where a bot holds the puck for a charged release and what each
# hold carries. World XZ offsets off the body; "ahead" is −Z and a right-hander's
# stick side is +X.

const AHEAD := Vector2(0.0, -1.0)
const RIGHT := Vector2(1.0, 0.0)

var _h := AIShotHolds.new()


# The pull's blade time, along the route the cursor walks (every test here faces
# AHEAD): BladeRoute to a hold in front of the body, the swing round to one
# behind, or the blade's travel if that is longer.
func _blade_s(k: int) -> float:
	var travel: float = _h.offset[k].distance_to(_h.offset[0]) / _h.blade_speed
	if _h.offset[k].dot(AHEAD) < 0.0:
		return maxf(absf(_h.offset[0].angle_to(_h.offset[k])) / _h.arc_rate, travel)
	return BladeRoute.length(_h.offset[0], _h.offset[k], AHEAD) / _h.blade_speed


func test_the_puck_where_it_is_comes_first_at_its_own_share() -> void:
	_h.solve_shot(AHEAD, RIGHT * 0.9, Vector2.ZERO, AHEAD)
	assert_eq(_h.offset[0], RIGHT * 0.9)
	assert_almost_eq(_h.share[0], 1.0, 0.001, "beside the stick hip a shot ahead is loaded")
	assert_eq(_h.pull_s[0], 0.0)


func test_a_puck_at_the_body_has_no_bearing_and_carries_the_unloaded_share() -> void:
	_h.solve_shot(AHEAD, Vector2.ZERO, Vector2.ZERO, AHEAD)
	assert_almost_eq(_h.share[0], _h.unloaded_share, 0.001)


func test_a_forehand_pulled_beside_the_hip_waits_only_for_the_blade() -> void:
	# Standing, the cursor out to the side turns the body side-on, but the
	# forehand there is loaded before it moves: the press needs only the blade.
	_h.solve_shot(AHEAD, AHEAD * 0.9, Vector2.ZERO, AHEAD)
	var best: int = 0
	for k: int in _h.count:
		if _h.share[k] > _h.share[best]:
			best = k
	assert_almost_eq(_h.share[best], 1.0, 0.001)
	assert_almost_eq(_h.pull_s[best], _blade_s(best), 0.0001)


func test_a_pull_waits_for_the_turn_only_when_the_turn_loads_it() -> void:
	for a: float in [0.0, 45.0, 90.0, 135.0, 180.0, -45.0, -90.0, -135.0]:
		var aim: Vector2 = AHEAD.rotated(deg_to_rad(a))
		for v: Vector2 in [Vector2.ZERO, AHEAD * 6.0]:
			_h.solve_shot(aim, AHEAD * 0.9, v, AHEAD)
			for k: int in range(1, _h.count):
				assert_gte(_h.pull_s[k], _blade_s(k) - 0.0001)
				if _h.pull_s[k] > _blade_s(k) + 0.0001:
					assert_gt(_h.share[k], _h.share_at(_h.offset[k], aim, AHEAD),
							"aim %.0f°: the turn is only waited for when it buys load" % a)


func test_a_hold_behind_the_body_waits_for_the_swing_round() -> void:
	# Aimed 60° off ahead, one side reach sits behind the body: the cursor swings
	# the puck round to it at arc_rate, slower here than the blade's chord.
	var h := AIShotHolds.new()
	h.arc_rate = 2.0
	h.solve_shot(AHEAD.rotated(deg_to_rad(60.0)), RIGHT * 0.9, Vector2.ZERO, AHEAD)
	var behind: int = -1
	for k: int in range(1, h.count):
		if h.offset[k].dot(AHEAD) < 0.0:
			behind = k
	assert_gt(behind, 0)
	var swing: float = absf(h.offset[0].angle_to(h.offset[behind])) / h.arc_rate
	assert_gt(swing, h.offset[0].distance_to(h.offset[behind]) / h.blade_speed)
	assert_gte(h.pull_s[behind], swing - 0.0001)


func test_the_swing_rate_defaults_to_the_state_machine_s() -> void:
	assert_eq(AIShotHolds.new().arc_rate, SkaterAgentStateMachine.MOUSE_ARC_RATE_RAD_S)
	assert_eq(RoleContext.new().self_arc_rate, SkaterAgentStateMachine.MOUSE_ARC_RATE_RAD_S)


func test_the_pocket_beside_the_hip_is_not_listed_twice() -> void:
	# Skating a shot ahead, the pocket IS a quarter-turn off the aim.
	_h.solve_shot(AHEAD, AHEAD * 0.9, AHEAD * 6.0, AHEAD)
	assert_eq(_h.count, 3)


func test_a_pass_the_puck_can_carry_is_fired_from_where_it_is() -> void:
	_h.solve_pass(AHEAD, RIGHT * 0.9, AHEAD * 6.0, AHEAD, 0.9)
	assert_eq(_h.pass_offset, RIGHT * 0.9)
	assert_almost_eq(_h.pass_share, 0.9, 0.001)


func test_a_pass_the_puck_cannot_carry_goes_to_the_pocket() -> void:
	# Straight out on the pass line the load is nothing: pull it to the pocket.
	_h.solve_pass(AHEAD, AHEAD * 0.9, AHEAD * 6.0, AHEAD, 0.9)
	assert_ne(_h.pass_offset, AHEAD * 0.9)
	assert_almost_eq(_h.pass_offset.length(), _h.handle_reach, 0.001)
	assert_almost_eq(_h.pass_share, 0.9, 0.001, "capped at what the feed needs")


# ── price_keep: the odds the puck is still on the blade at the press ─────────

const _NO_CAPS: Array = []


func _keep_with(man: Vector3, puck_offset: Vector2) -> void:
	_h.solve_shot(AHEAD, puck_offset, Vector2.ZERO, AHEAD)
	var men: Array[Vector3] = [man]
	var vels: Array[Vector3] = [Vector3.ZERO]
	_h.price_keep(Vector3.ZERO, Vector2.ZERO, AHEAD, 0.135, men, vels, _NO_CAPS)


func _hold_toward(x_sign: float) -> int:
	for k: int in range(1, _h.count):
		if _h.offset[k].x * x_sign > 0.5:
			return k
	return -1


func test_nobody_near_keeps_every_hold() -> void:
	_h.solve_shot(AHEAD, RIGHT * 0.9, Vector2.ZERO, AHEAD)
	var none: Array[Vector3] = []
	_h.price_keep(Vector3.ZERO, Vector2.ZERO, AHEAD, 0.135, none, none, _NO_CAPS)
	for k: int in _h.count:
		assert_almost_eq(_h.keep[k], 1.0, 0.001)


func test_a_hold_beside_a_trailing_checker_keeps_less_than_the_far_side() -> void:
	_keep_with(Vector3(1.0, 0.0, 2.0), AHEAD * 0.9)
	var near: int = _hold_toward(1.0)
	var far: int = _hold_toward(-1.0)
	assert_gt(near, 0)
	assert_gt(far, 0)
	assert_lt(_h.keep[near], _h.keep[far], "his stick reaches the hold on his side")


# Fast hands and no charge keep the press inside a man's reaction, so neither
# end of the pull gives him time to close: only the route decides.
func _quick_pull_across(man: Vector3) -> AIShotHolds:
	var h := AIShotHolds.new()
	h.blade_speed = 40.0
	var facing: Vector2 = AHEAD.rotated(-0.2)   # the far side's hold is in front
	h.solve_shot(AHEAD, RIGHT * 0.9, Vector2.ZERO, facing)
	var men: Array[Vector3] = [man]
	var vels: Array[Vector3] = [Vector3.ZERO]
	h.price_keep(Vector3.ZERO, Vector2.ZERO, facing, 0.0, men, vels, _NO_CAPS)
	return h


func _across(h: AIShotHolds) -> int:
	for k: int in range(1, h.count):
		if h.offset[k].x < -0.5:
			return k
	return -1


func test_a_pull_round_the_front_spares_a_checker_behind() -> void:
	var h: AIShotHolds = _quick_pull_across(Vector3(0.0, 0.0, 2.0))
	var across: int = _across(h)
	assert_gt(across, 0)
	assert_almost_eq(h.keep[across], h.keep[0], 0.001,
			"the far side sits as far off him as the near one, and the route stays clear")


func test_a_pull_round_the_front_past_a_checker_ahead_reads_as_the_puck_parked_there() -> void:
	# His stick sweeps its reach faster than the puck crosses it, so the route is
	# worth no more than the puck sitting where it passes him closest: in front
	# of the skates, inside his reach.
	var ahead: float = 2.0
	var h: AIShotHolds = _quick_pull_across(Vector3(0.0, 0.0, -ahead))
	var across: int = _across(h)
	assert_gt(across, 0)
	var parked: float = AICarrySpace.clearance_to_safety(
			ahead - BladeRoute.CLEAR_M - AICarrySpace.EVADE_STICK_REACH_M)
	assert_gt(h.keep[0], parked + 0.1, "both ends sit further off him")
	assert_lte(h.keep[across], parked + 0.05)
