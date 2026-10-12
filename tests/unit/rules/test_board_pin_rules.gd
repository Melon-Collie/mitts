extends GutTest

# BoardPinRules and FrozenPuckRules: the boards as a backstop, the pin's onset
# and wear, and the frozen puck's count.

const R: float = 0.35
var _side_x: float = GameRules.INNER_HALF_WIDTH   # the +x side boards' inner face


func _at_the_wall(gap: float) -> Vector3:
	return Vector3(_side_x - R - gap, 0.0, 0.0)


func test_the_wall_normal_points_out_only_near_the_boards() -> void:
	assert_eq(BoardPinRules.wall_normal(_at_the_wall(0.05), R, 0.25), Vector2(1.0, 0.0))
	assert_eq(BoardPinRules.wall_normal(_at_the_wall(1.0), R, 0.25), Vector2.ZERO)
	assert_eq(BoardPinRules.wall_normal(Vector3.ZERO, R, 0.25), Vector2.ZERO)


func test_a_hit_square_into_the_boards_lands_its_whole_closing_speed() -> void:
	var out := Vector2(1.0, 0.0)
	assert_eq(BoardPinRules.backstop_hit_strength(2.0, 6.0, 0.8, Vector2(1.0, 0.0), out),
			6.0 * 0.8, "square in: the wall takes the recoil")
	assert_eq(BoardPinRules.backstop_hit_strength(2.0, 6.0, 0.8, Vector2(0.0, 1.0), out),
			2.0, "along the wall: open-ice")
	assert_eq(BoardPinRules.backstop_hit_strength(2.0, 6.0, 0.8, Vector2(1.0, 0.0), Vector2.ZERO),
			2.0, "no wall: open-ice")
	assert_eq(BoardPinRules.backstop_hit_strength(5.0, 6.0, 0.8, Vector2(1.0, 0.0), out),
			5.0, "never weaker than the open-ice hit")


func test_a_pin_needs_a_committed_drive_into_the_wall() -> void:
	var out := Vector2(1.0, 0.0)
	var into := Vector2(1.0, 0.0)
	assert_true(BoardPinRules.pin_holds(true, into, Vector3(1.5, 0, 0), Vector2.ZERO, out))
	assert_true(BoardPinRules.pin_holds(true, into, Vector3.ZERO, Vector2(1.0, 0.0), out),
			"pressed flat against him, the stick held into the wall still drives")
	assert_false(BoardPinRules.pin_holds(false, into, Vector3(1.5, 0, 0), Vector2.ZERO, out),
			"not committed")
	assert_false(BoardPinRules.pin_holds(true, into, Vector3.ZERO, Vector2.ZERO, out),
			"not driving")
	assert_false(BoardPinRules.pin_holds(true, Vector2(0.0, 1.0), Vector3(1.5, 0, 0),
			Vector2.ZERO, out), "pushing along the wall is not pinning")
	assert_false(BoardPinRules.pin_holds(true, into, Vector3(1.5, 0, 0), Vector2.ZERO,
			Vector2.ZERO), "no wall")


func test_the_heavier_body_pins_harder() -> void:
	assert_almost_eq(BoardPinRules.pin_strength(1.0, 1.0), 0.5, 1e-6)
	assert_gt(BoardPinRules.pin_strength(1.2, 0.8), 0.5)


func test_working_along_the_wall_wears_the_pin_down_faster() -> void:
	var out := Vector2(1.0, 0.0)
	assert_eq(BoardPinRules.escape_drive(Vector2(0.0, 1.0), out), 1.0)
	assert_eq(BoardPinRules.escape_drive(Vector2(1.0, 0.0), out), 0.0, "into the wall is no escape")
	assert_eq(BoardPinRules.budget_drain_rate(0.0, 0.5), 1.0)
	assert_gt(BoardPinRules.budget_drain_rate(1.0, 0.3), BoardPinRules.budget_drain_rate(1.0, 0.7),
			"a weaker pin wears faster")


func test_the_pin_bleeds_only_the_slide_along_the_wall() -> void:
	var out := Vector2(1.0, 0.0)
	var v: Vector3 = BoardPinRules.apply_pin(Vector3(0.5, 0.0, 3.0), out, 1.0, 0.1)
	assert_almost_eq(v.z, 3.0 - BoardPinRules.PIN_HOLD_DECEL_M_S2 * 0.1, 1e-5)
	assert_eq(v.x, 0.5, "the push into the wall is the wall's business")


func test_the_forward_correction_slows_a_pinned_slide() -> void:
	var r := SkaterMovementRules.ForwardResult.new()
	r.position = Vector3(10.0, 0.0, 1.0)
	r.velocity = Vector3(0.0, 0.0, 3.0)
	BoardPinRules.forward_correction(r, Vector2(1.0, 0.0), 0.15, 0.5, 0.1)
	assert_lt(r.velocity.z, 3.0)
	assert_lt(r.position.z, 1.0, "and it covers less ground")
	var free := SkaterMovementRules.ForwardResult.new()
	free.velocity = Vector3(0.0, 0.0, 3.0)
	BoardPinRules.forward_correction(free, Vector2(1.0, 0.0), 0.0, 0.5, 0.1)
	assert_eq(free.velocity.z, 3.0, "no grip, no correction")


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


func test_the_squirt_runs_along_the_wall_away_from_the_pinned_body() -> void:
	var p := Vector3(GameRules.INNER_HALF_WIDTH - 0.1, 0.0, 0.0)
	var v: Vector3 = FrozenPuckRules.squirt_velocity(p, p + Vector3(-0.3, 0.0, -0.5))
	assert_almost_eq(v.x, 0.0, 1e-6)
	assert_gt(v.z, 0.0)
	assert_almost_eq(v.length(), FrozenPuckRules.SQUIRT_SPEED_M_S, 1e-5)
