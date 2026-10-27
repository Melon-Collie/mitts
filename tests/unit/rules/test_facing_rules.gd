extends GutTest

# FacingRules — where a skater's body heads, from its facing, the cursor and its
# velocity. World XZ; the skater faces −Z ("ahead") unless a test says otherwise,
# and shoots left unless it says otherwise, so the forehand is the LEFT side.

const AHEAD := Vector2(0.0, -1.0)
const LEFT := Vector2(-1.0, 0.0)
const BEHIND := Vector2(0.0, 1.0)

var _cfg := FacingRules.Config.new()
var _out := FacingRules.Result.new()


func before_each() -> void:
	_cfg = FacingRules.Config.new()


func _solve(facing: Vector2, cursor: Vector2, velocity: Vector2,
		brake: bool = false, stance: bool = false, lefty: bool = true) -> FacingRules.Result:
	FacingRules.solve(_out, facing, cursor, velocity, brake, stance, lefty, _cfg)
	return _out


func _off(dir: Vector2) -> float:
	return rad_to_deg(absf(_out.target.angle_to(dir)))


# `deg` round from straight ahead, toward the left.
func _left_of_ahead(deg: float) -> Vector2:
	return AHEAD.rotated(-deg_to_rad(deg))


func _right_of_ahead(deg: float) -> Vector2:
	return AHEAD.rotated(deg_to_rad(deg))


func test_standing_faces_the_cursor() -> void:
	_solve(AHEAD, LEFT, Vector2.ZERO)
	assert_almost_eq(_off(LEFT), 0.0, 0.01)


func test_skating_faces_the_line_with_the_cursor_out_wide() -> void:
	_solve(AHEAD, LEFT, AHEAD * 6.0)
	assert_almost_eq(_off(AHEAD), 0.0, 0.01)
	assert_false(_out.pivoting)


func test_taking_up_the_line_needs_skating_speed() -> void:
	# Facing the cursor, moving at side-step pace: stays on the cursor.
	_solve(LEFT, LEFT, AHEAD * 1.5)
	assert_almost_eq(_off(LEFT), 0.0, 0.01, "a side-step tap stays squared")
	_solve(LEFT, LEFT, AHEAD * 2.4)
	assert_almost_eq(_off(AHEAD), 0.0, 0.01, "past the engage band it takes the line")


func test_keeping_the_line_holds_down_to_a_crawl() -> void:
	# Already on the line: a coast keeps it well below the engage band.
	_solve(AHEAD, LEFT, AHEAD * 1.5)
	assert_almost_eq(_off(AHEAD), 0.0, 0.01)
	_solve(AHEAD, LEFT, AHEAD * 0.4)
	assert_almost_eq(_off(LEFT), 0.0, 0.01, "nearly stopped, it hands back to the cursor")


func test_braking_faces_the_cursor() -> void:
	_solve(AHEAD, LEFT, AHEAD * 6.0, true)
	assert_almost_eq(_off(LEFT), 0.0, 0.01)


func test_the_hips_hold_the_line_to_the_reach_edge() -> void:
	var edge: float = rad_to_deg(_cfg.forehand_edge_rad)
	_solve(AHEAD, _left_of_ahead(edge - 5.0), AHEAD * 6.0)
	assert_almost_eq(_off(AHEAD), 0.0, 0.01, "inside the edge the torso and arms reach for it")
	assert_false(_out.pivoting)
	_solve(AHEAD, _left_of_ahead(edge + 5.0), AHEAD * 6.0)
	assert_true(_out.pivoting, "past it the hips pivot")
	assert_almost_eq(_off(BEHIND), 0.0, 0.01, "onto the backward line")


func test_skating_backward_keeps_the_hips_on_the_line() -> void:
	_solve(BEHIND, BEHIND.rotated(deg_to_rad(60.0)), AHEAD * 6.0)
	assert_almost_eq(_off(BEHIND), 0.0, 0.01, "squared along the line, not to the cursor")
	assert_false(_out.pivoting)


func test_skating_backward_pivots_forward_at_the_edge() -> void:
	_solve(BEHIND, _left_of_ahead(10.0), AHEAD * 6.0)
	assert_true(_out.pivoting)
	assert_almost_eq(_off(AHEAD), 0.0, 0.01)


func test_a_pivot_cannot_flip_straight_back() -> void:
	# Pivoted onto the backward line, the cursor that sent it there sits far inside
	# the new line's edge.
	var cursor := _left_of_ahead(rad_to_deg(_cfg.forehand_edge_rad) + 5.0)
	_solve(BEHIND, cursor, AHEAD * 6.0)
	assert_false(_out.pivoting)
	assert_almost_eq(_off(BEHIND), 0.0, 0.01)


func test_each_side_pivots_at_its_own_edge() -> void:
	_cfg.forehand_edge_rad = deg_to_rad(120.0)
	_cfg.backhand_edge_rad = deg_to_rad(170.0)
	_solve(AHEAD, _left_of_ahead(140.0), AHEAD * 6.0)
	assert_true(_out.pivoting, "a lefty's forehand is the left, and 140° is past it")
	_solve(AHEAD, _right_of_ahead(140.0), AHEAD * 6.0)
	assert_false(_out.pivoting, "a lefty's backhand is the right, and reaches 140°")
	_solve(AHEAD, _right_of_ahead(140.0), AHEAD * 6.0, false, false, false)
	assert_true(_out.pivoting, "a righty's forehand is the right")


func test_the_stance_squares_only_when_slow() -> void:
	_solve(LEFT, LEFT, AHEAD * 2.0, false, true)
	assert_almost_eq(_off(LEFT), 0.0, 0.01, "slow in the stance squares to the cursor")
	_solve(AHEAD, LEFT, AHEAD * 6.0, false, true)
	assert_almost_eq(_off(AHEAD), 0.0, 0.01, "at speed the stance just crouches")


# A cursor held on the edge flips the pivot on float noise, and each flip swung
# the hips toward the other line and back: they sat between the two.
func test_a_pivot_under_way_carries_through() -> void:
	_cfg.backhand_edge_rad = deg_to_rad(67.0)
	var cursor: Vector2 = _right_of_ahead(65.0)
	_solve(AHEAD, cursor, AHEAD * 6.0)
	assert_false(_out.pivoting, "on the line, 2° inside the edge holds it")
	_solve(_right_of_ahead(15.0), cursor, AHEAD * 6.0)
	assert_true(_out.pivoting, "hips already turning toward the cursor carry on round")
	_solve(_left_of_ahead(15.0), cursor, AHEAD * 6.0)
	assert_false(_out.pivoting, "hips turned the other way are no pivot under way")


func test_taking_the_line_up_is_not_a_pivot_under_way() -> void:
	_cfg.backhand_edge_rad = deg_to_rad(67.0)
	var cursor: Vector2 = _right_of_ahead(62.0)
	_solve(cursor, cursor, AHEAD * 1.8)
	assert_false(_out.pivoting, "squared to the cursor in the engage band, the line still wins")


func test_turning_round_goes_the_cursors_way() -> void:
	# Backward, leaning a touch right of straight back, so the short way to the
	# travel is round the right; the cursor is ahead-left, so it goes round the left.
	var facing := BEHIND.rotated(deg_to_rad(5.0))
	var cursor := AHEAD.rotated(deg_to_rad(10.0))
	var short_way: float = facing.angle_to(AHEAD)
	var turn: float = FacingRules.turn_round_angle(facing, AHEAD, cursor)
	assert_eq(signf(turn), signf(facing.angle_to(cursor)), "round on the cursor's side")
	assert_ne(signf(turn), signf(short_way), "which here is the long way")
	assert_almost_eq(absf(turn), TAU - absf(short_way), 0.0001)


func test_turning_round_to_a_cursor_dead_behind_keeps_the_lean() -> void:
	var facing := BEHIND.rotated(deg_to_rad(5.0))
	var turn: float = FacingRules.turn_round_angle(facing, AHEAD, AHEAD)
	assert_almost_eq(turn, facing.angle_to(AHEAD), 0.0001)


# ── turn_rate ─────────────────────────────────────────────────────────────────

const _ACCEL: float = 300.0
const _DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION


func test_a_turn_winds_up_at_the_limit() -> void:
	var rate: float = 0.0
	for i: int in 3:
		rate = FacingRules.turn_rate(rate, 15.0, _ACCEL, _DT)
		assert_almost_eq(rate, _ACCEL * _DT * (i + 1), 1e-5, "tick %d" % i)


func test_a_turn_gives_its_rate_up_at_once() -> void:
	assert_eq(FacingRules.turn_rate(15.0, 2.0, _ACCEL, _DT), 2.0)
	assert_eq(FacingRules.turn_rate(-15.0, 0.0, _ACCEL, _DT), 0.0)


# Reversing is giving the rate up, then winding up the other way from rest.
func test_a_reversal_winds_up_from_rest() -> void:
	assert_almost_eq(FacingRules.turn_rate(10.0, -10.0, _ACCEL, _DT), -_ACCEL * _DT, 1e-5)


func test_a_small_change_passes_through() -> void:
	assert_eq(FacingRules.turn_rate(1.0, 2.0, _ACCEL, _DT), 2.0)


# A carrier's hips yield to a cursor going round the forehand, just far enough
# to keep it at forehand_yield_rad.
func test_the_hips_yield_to_a_cursor_round_the_forehand() -> void:
	_cfg.forehand_yield_rad = deg_to_rad(110.0)
	var inside: Vector2 = FacingRules.yield_on_forehand(AHEAD, _left_of_ahead(100.0), true, _cfg)
	assert_eq(inside, AHEAD, "inside it the body heads where the rule put it")
	var yielded: Vector2 = FacingRules.yield_on_forehand(AHEAD, _left_of_ahead(130.0), true, _cfg)
	assert_almost_eq(rad_to_deg(yielded.angle_to(_left_of_ahead(130.0))), -110.0, 0.01,
			"past it, turned toward the cursor until it sits there")
	assert_eq(FacingRules.yield_on_forehand(AHEAD, _right_of_ahead(130.0), true, _cfg), AHEAD,
			"a lefty's backhand does not yield")
	yielded = FacingRules.yield_on_forehand(AHEAD, _right_of_ahead(130.0), false, _cfg)
	assert_almost_eq(rad_to_deg(yielded.angle_to(_right_of_ahead(130.0))), 110.0, 0.01,
			"a righty's forehand is the right")


func test_the_yield_never_turns_the_body_away_from_the_cursor() -> void:
	_cfg.forehand_yield_rad = deg_to_rad(110.0)
	var cursor: Vector2 = _left_of_ahead(170.0)
	# Heading back toward a line the cursor has gone far round from.
	var turned: Vector2 = _left_of_ahead(30.0)
	var yielded: Vector2 = FacingRules.yield_on_forehand(turned, cursor, true, _cfg)
	assert_gt(absf(turned.angle_to(cursor)), absf(yielded.angle_to(cursor)), "turned on toward it")


func test_an_empty_stick_never_yields() -> void:
	assert_eq(FacingRules.yield_on_forehand(AHEAD, _left_of_ahead(150.0), true, _cfg), AHEAD)
