extends GutTest

# BoardWallRules and FrozenPuckRules: the boards as a backstop to a hit, the
# squeeze that holds a pressed man against them, and the frozen puck's count.

const R: float = 0.35
var _side_x: float = GameRules.INNER_HALF_WIDTH   # the +x side boards' inner face
const OUT := Vector2(1.0, 0.0)


func _at_the_wall(gap: float) -> Vector3:
	return Vector3(_side_x - R - gap, 0.0, 0.0)


func test_the_wall_normal_points_out_only_near_the_boards() -> void:
	assert_eq(BoardWallRules.wall_normal(_at_the_wall(0.05), R, 0.25), OUT)
	assert_eq(BoardWallRules.wall_normal(_at_the_wall(1.0), R, 0.25), Vector2.ZERO)
	assert_eq(BoardWallRules.wall_normal(Vector3.ZERO, R, 0.25), Vector2.ZERO)


func test_a_hit_square_into_the_boards_lands_the_attackers_whole_impulse() -> void:
	assert_almost_eq(BoardWallRules.backstop_hit_strength(2.0, 6.0, 0.8, OUT, OUT, 1.0, 1.0),
			6.0 * 0.8, 1e-6, "square in, equal mass: the wall takes the recoil")
	assert_eq(BoardWallRules.backstop_hit_strength(2.0, 6.0, 0.8, Vector2(0.0, 1.0), OUT, 1.0, 1.0),
			2.0, "along the wall: open-ice")
	assert_eq(BoardWallRules.backstop_hit_strength(2.0, 6.0, 0.8, OUT, Vector2.ZERO, 1.0, 1.0),
			2.0, "no wall: open-ice")
	assert_eq(BoardWallRules.backstop_hit_strength(5.0, 6.0, 0.8, OUT, OUT, 1.0, 1.0),
			5.0, "never weaker than the open-ice hit")
	assert_almost_eq(BoardWallRules.backstop_hit_strength(0.0, 6.0, 0.8, OUT, OUT, 1.0, 1.0, 0.5),
			6.0 * 0.8 + 0.5, 1e-6, "the legs' kick on top")


func test_on_the_boards_weight_matters_both_ways() -> void:
	var even: float = BoardWallRules.backstop_hit_strength(0.0, 4.0, 0.65, OUT, OUT, 1.0, 1.0)
	assert_gt(BoardWallRules.backstop_hit_strength(0.0, 4.0, 0.65, OUT, OUT, 1.28, 1.0), even,
			"a heavier checker")
	assert_gt(BoardWallRules.backstop_hit_strength(0.0, 4.0, 0.65, OUT, OUT, 1.0, 0.79), even,
			"a lighter victim")
	assert_lt(BoardWallRules.backstop_hit_strength(0.0, 4.0, 0.65, OUT, OUT, 0.79, 1.28), even,
			"light on heavy")


# The squeeze: nothing off the boards, nothing unless he is pushed into them,
# and more the harder and the more squarely he is.
func test_only_a_man_pushed_into_the_boards_is_squeezed() -> void:
	assert_gt(BoardWallRules.squeeze_grip(10.0, OUT, OUT), 0.0)
	assert_eq(BoardWallRules.squeeze_grip(10.0, OUT, Vector2.ZERO), 0.0, "open ice")
	assert_eq(BoardWallRules.squeeze_grip(10.0, Vector2(0.0, 1.0), OUT), 0.0, "pushed along the wall")
	assert_eq(BoardWallRules.squeeze_grip(10.0, -OUT, OUT), 0.0, "pushed off it")
	assert_eq(BoardWallRules.squeeze_grip(0.0, OUT, OUT), 0.0, "he pushes back as hard")
	assert_eq(BoardWallRules.squeeze_grip(-3.0, OUT, OUT), 0.0, "he out-pushes him")


func test_the_squeeze_grows_with_the_push_and_its_squareness() -> void:
	assert_gt(BoardWallRules.squeeze_grip(10.0, OUT, OUT), BoardWallRules.squeeze_grip(5.0, OUT, OUT))
	var off_square: Vector2 = OUT.rotated(deg_to_rad(30.0))
	assert_gt(BoardWallRules.squeeze_grip(10.0, OUT, OUT),
			BoardWallRules.squeeze_grip(10.0, off_square, OUT))


func test_the_grip_takes_only_from_the_slide_along_the_wall() -> void:
	var v := Vector3(2.0, 0.0, 3.0)
	var held: Vector3 = BoardWallRules.gripped(v, OUT, 1.0)
	assert_almost_eq(held.x, 2.0, 1e-6, "across the wall untouched")
	assert_almost_eq(held.z, 2.0, 1e-6)
	assert_almost_eq(BoardWallRules.gripped(Vector3(0.0, 0.0, -0.4), OUT, 1.0).z, 0.0, 1e-6,
			"to rest, never reversed")
	assert_eq(BoardWallRules.gripped(v, Vector2.ZERO, 1.0), v)


# A held man: against the wall, leaned on by an engaged opponent on the open-ice
# side, square to it.
func test_a_man_is_held_only_by_an_engaged_man_square_on_his_open_side() -> void:
	var man: Vector3 = _at_the_wall(0.05)
	var outside: Vector3 = man - Vector3(2.0 * R + 0.03, 0.0, 0.0)
	assert_true(FrozenPuckRules.held_on_boards(man, R, outside, R, true))
	assert_false(FrozenPuckRules.held_on_boards(man, R, outside, R, false), "not engaged")
	assert_false(FrozenPuckRules.held_on_boards(man, R, outside - Vector3(0.5, 0.0, 0.0), R, true),
			"a step off him")
	assert_false(FrozenPuckRules.held_on_boards(man, R, man + Vector3(0.0, 0.0, 2.0 * R), R, true),
			"beside him along the wall")
	assert_false(FrozenPuckRules.held_on_boards(Vector3.ZERO, R, Vector3(-2.0 * R, 0.0, 0.0), R,
			true), "open ice")


func test_a_trapped_puck_freezes_after_its_count() -> void:
	var st := FrozenPuckRules.State.new()
	var p := Vector3(GameRules.INNER_HALF_WIDTH - 0.1, 0.0, 0.0)
	assert_true(FrozenPuckRules.near_boards(p))
	var frozen: bool = false
	var t: float = 0.0
	while t < FrozenPuckRules.FROZEN_S + 0.05 and not frozen:
		frozen = FrozenPuckRules.step(st, p, true, 1.0 / 120.0)
		t += 1.0 / 120.0
	assert_true(frozen)
	assert_gte(t, FrozenPuckRules.FROZEN_S - 1e-3)


func test_a_puck_that_moves_or_is_freed_restarts_the_count() -> void:
	var st := FrozenPuckRules.State.new()
	var p := Vector3(GameRules.INNER_HALF_WIDTH - 0.1, 0.0, 0.0)
	for _i: int in 100:
		FrozenPuckRules.step(st, p, true, 1.0 / 120.0)
	FrozenPuckRules.step(st, p + Vector3(0.0, 0.0, 1.0), true, 1.0 / 120.0)
	assert_lt(st.elapsed, 0.02, "moved off its anchor")
	FrozenPuckRules.step(st, p, false, 1.0 / 120.0)
	assert_eq(st.elapsed, 0.0, "freed")


func test_the_squirt_runs_along_the_wall_away_from_the_held_body() -> void:
	var p := Vector3(GameRules.INNER_HALF_WIDTH - 0.1, 0.0, 0.0)
	var v: Vector3 = FrozenPuckRules.squirt_velocity(p, p + Vector3(-0.3, 0.0, -0.5))
	assert_almost_eq(v.x, 0.0, 1e-6)
	assert_gt(v.z, 0.0)
	assert_almost_eq(v.length(), FrozenPuckRules.SQUIRT_SPEED_M_S, 1e-5)
