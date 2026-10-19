extends GutTest

# BoardPinRules and FrozenPuckRules: the boards as a backstop, the pin's onset,
# its slide caps and escape, and the frozen puck's count.

const R: float = 0.35
var _side_x: float = GameRules.INNER_HALF_WIDTH   # the +x side boards' inner face


func _at_the_wall(gap: float) -> Vector3:
	return Vector3(_side_x - R - gap, 0.0, 0.0)


func test_the_wall_normal_points_out_only_near_the_boards() -> void:
	assert_eq(BoardPinRules.wall_normal(_at_the_wall(0.05), R, 0.25), Vector2(1.0, 0.0))
	assert_eq(BoardPinRules.wall_normal(_at_the_wall(1.0), R, 0.25), Vector2.ZERO)
	assert_eq(BoardPinRules.wall_normal(Vector3.ZERO, R, 0.25), Vector2.ZERO)


func test_the_pinner_finds_the_wall_a_body_off_it() -> void:
	var pinner_gap: float = 0.05 + 2.0 * R + 0.05
	assert_eq(BoardPinRules.locked_wall_normal(_at_the_wall(pinner_gap), R,
			BoardPinRules.Role.PINNER), Vector2(1.0, 0.0))
	assert_eq(BoardPinRules.locked_wall_normal(_at_the_wall(pinner_gap), R,
			BoardPinRules.Role.PINNED), Vector2.ZERO, "the victim's wall is the one he is against")


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


func test_a_pin_needs_a_reaching_drive_into_the_wall() -> void:
	var out := Vector2(1.0, 0.0)
	var into := Vector2(1.0, 0.0)
	assert_true(BoardPinRules.pin_holds(true, false, into, Vector3(1.5, 0, 0), Vector2.ZERO, out))
	assert_true(BoardPinRules.pin_holds(true, false, into, Vector3.ZERO, Vector2(1.0, 0.0), out),
			"pressed flat against him, the stick held into the wall still drives")
	assert_false(BoardPinRules.pin_holds(false, false, into, Vector3(1.5, 0, 0), Vector2.ZERO, out),
			"not reaching")
	assert_false(BoardPinRules.pin_holds(true, false, into, Vector3.ZERO, Vector2.ZERO, out),
			"not driving")
	assert_false(BoardPinRules.pin_holds(true, false, Vector2(0.0, 1.0), Vector3(1.5, 0, 0),
			Vector2.ZERO, out), "pushing along the wall is not pinning")
	assert_false(BoardPinRules.pin_holds(true, false, into, Vector3(1.5, 0, 0), Vector2.ZERO,
			Vector2.ZERO), "no wall")


func test_a_locked_pair_touches_along_the_boards_normal() -> void:
	var victim: Vector3 = _at_the_wall(0.0)
	var pinner: Vector3 = victim + Vector3(-2.0 * R, 0.0, 0.3)
	assert_eq(BoardPinRules.locked_contact_axis(pinner, BoardPinRules.Role.PINNER, R, victim, BoardPinRules.Role.PINNED, R),
			Vector3(1.0, 0.0, 0.0), "pinner to victim: into the wall, whatever the offset")
	assert_eq(BoardPinRules.locked_contact_axis(victim, BoardPinRules.Role.PINNED, R, pinner, BoardPinRules.Role.PINNER, R),
			Vector3(-1.0, 0.0, 0.0), "victim to pinner: out of it")
	assert_eq(BoardPinRules.locked_contact_axis(pinner, BoardPinRules.Role.NONE, R, victim, BoardPinRules.Role.PINNED, R),
			Vector3.ZERO, "a third body touches him as a disc")
	assert_eq(BoardPinRules.locked_contact_axis(pinner, BoardPinRules.Role.PINNER, R, victim, BoardPinRules.Role.PINNER, R),
			Vector3.ZERO, "two pinners are not a pair")


func test_the_locked_gap_ignores_the_along_wall_offset() -> void:
	var victim: Vector3 = _at_the_wall(0.0)
	var out := Vector2(1.0, 0.0)
	assert_almost_eq(BoardPinRules.locked_gap(victim, R, victim + Vector3(-2.0 * R, 0.0, 0.4),
			R, out), 0.0, 1e-6)
	assert_almost_eq(BoardPinRules.locked_gap(victim, R, victim + Vector3(-2.0 * R - 0.1, 0.0, 0.0),
			R, out), 0.1, 1e-6)


func test_a_braced_victim_cannot_be_pinned() -> void:
	assert_false(BoardPinRules.pin_holds(true, true, Vector2(1.0, 0.0), Vector3(1.5, 0, 0),
			Vector2.ZERO, Vector2(1.0, 0.0)), "holding his own commit braces him")


func test_the_heavier_body_pins_harder() -> void:
	assert_almost_eq(BoardPinRules.pin_strength(1.0, 1.0), 0.5, 1e-6)
	assert_gt(BoardPinRules.pin_strength(1.2, 0.8), 0.5)


func test_the_slide_caps_by_role_and_weight() -> void:
	var Role = BoardPinRules.Role
	assert_almost_eq(BoardPinRules.slide_cap(Role.PINNED, 0.5),
			BoardPinRules.PIN_SLIDE_VICTIM_M_S, 1e-6, "equal weight: the stated speed")
	assert_lt(BoardPinRules.slide_cap(Role.PINNED, 0.6), BoardPinRules.slide_cap(Role.PINNED, 0.4),
			"a heavier pinner slows him")
	assert_eq(BoardPinRules.slide_cap(Role.PINNER, 0.5), BoardPinRules.PIN_SLIDE_PINNER_M_S)
	assert_eq(BoardPinRules.slide_cap(Role.NONE, 0.5), INF)


# Across the real weight band, the pinner's cap beats the victim's fastest, and
# the escape offset covers a reversal the pinner reads late by the network lag.
func test_the_escape_holds_against_ping_across_the_weight_band() -> void:
	var lightest: int = 100000
	var heaviest: int = 0
	for h: int in range(PlayerAttributes.HEIGHT_MIN, PlayerAttributes.HEIGHT_MAX + 1):
		lightest = mini(lightest, PlayerAttributes.weight_min(h))
		heaviest = maxi(heaviest, PlayerAttributes.weight_max(h))
	var weakest: float = BoardPinRules.pin_strength(float(lightest), float(heaviest))
	var fastest_victim: float = BoardPinRules.slide_cap(BoardPinRules.Role.PINNED, weakest)
	assert_gt(BoardPinRules.PIN_SLIDE_PINNER_M_S, fastest_victim,
			"a pinner who reads the slide keeps up with the fastest victim")
	assert_gte(BoardPinRules.PIN_ESCAPE_OFFSET_M,
			2.0 * fastest_victim * BoardPinRules.PIN_LAG_BUDGET_S - 1e-6,
			"ping alone never frees the victim")


func test_the_escape_is_either_side() -> void:
	var out := Vector2(1.0, 0.0)
	var pinner := Vector3(5.0, 0.0, 0.0)
	var past := BoardPinRules.PIN_ESCAPE_OFFSET_M + 0.05
	assert_false(BoardPinRules.escaped(BoardPinRules.along_wall_offset(
			pinner + Vector3(0.7, 0.0, 0.3), pinner, out)))
	assert_true(BoardPinRules.escaped(BoardPinRules.along_wall_offset(
			pinner + Vector3(0.7, 0.0, past), pinner, out)))
	assert_true(BoardPinRules.escaped(BoardPinRules.along_wall_offset(
			pinner + Vector3(0.7, 0.0, -past), pinner, out)), "an over-chasing pinner frees him too")


func test_the_cap_clamps_only_the_slide_along_the_wall() -> void:
	var out := Vector2(1.0, 0.0)
	var v: Vector3 = BoardPinRules.apply_slide_cap(Vector3(0.5, 0.2, 3.0), out, 1.0)
	assert_almost_eq(v.z, 1.0, 1e-5)
	assert_eq(v.x, 0.5, "the push into the wall is the wall's business")
	assert_almost_eq(v.y, 0.2, 1e-6)
	var slow: Vector3 = BoardPinRules.apply_slide_cap(Vector3(0.0, 0.0, -0.4), out, 1.0)
	assert_eq(slow, Vector3(0.0, 0.0, -0.4), "under the cap, untouched")


func test_the_forward_cap_matches_the_live_cap() -> void:
	var r := SkaterMovementRules.ForwardResult.new()
	r.position = Vector3(10.0, 0.0, 1.0)
	r.velocity = Vector3(0.0, 0.0, 3.0)
	BoardPinRules.forward_cap(r, Vector2(1.0, 0.0), 1.0, 0.1)
	assert_almost_eq(r.velocity.z, 1.0, 1e-5)
	assert_almost_eq(r.position.z, 1.0 - 2.0 * 0.1, 1e-5, "the excess travel is taken back")
	var free := SkaterMovementRules.ForwardResult.new()
	free.velocity = Vector3(0.0, 0.0, 3.0)
	BoardPinRules.forward_cap(free, Vector2(1.0, 0.0), INF, 0.1)
	assert_eq(free.velocity.z, 3.0, "unlocked, no correction")


func test_the_cap_outlasts_the_frozen_puck_count() -> void:
	assert_gt(BoardPinRules.PIN_MAX_S, FrozenPuckRules.FROZEN_S,
			"with the puck trapped, the whistle lands before the pin gives out")


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
