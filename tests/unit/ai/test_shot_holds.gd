extends GutTest

# AIShotHolds — where a bot holds the puck for a charged release and what each
# hold carries. World XZ offsets off the body; "ahead" is −Z and a right-hander's
# stick side is +X.

const AHEAD := Vector2(0.0, -1.0)
const RIGHT := Vector2(1.0, 0.0)

var _h := AIShotHolds.new()


func _blade_s(k: int) -> float:
	return _h.offset[k].distance_to(_h.offset[0]) / _h.blade_speed


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
