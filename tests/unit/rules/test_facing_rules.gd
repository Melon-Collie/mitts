extends GutTest

# FacingRules — where a skater's body heads, from its facing, the cursor and its
# velocity. World XZ; the skater faces −Z ("ahead") unless a test says otherwise.

const AHEAD := Vector2(0.0, -1.0)
const LEFT := Vector2(-1.0, 0.0)
const BEHIND := Vector2(0.0, 1.0)

var _cfg := FacingRules.Config.new()
var _out := FacingRules.Result.new()


func _solve(facing: Vector2, cursor: Vector2, velocity: Vector2,
		brake: bool = false, stance: bool = false) -> FacingRules.Result:
	FacingRules.solve(_out, facing, cursor, velocity, brake, stance, _cfg)
	return _out


func _off(dir: Vector2) -> float:
	return rad_to_deg(absf(_out.target.angle_to(dir)))


func test_standing_faces_the_cursor() -> void:
	_solve(AHEAD, LEFT, Vector2.ZERO)
	assert_almost_eq(_off(LEFT), 0.0, 0.01)


func test_skating_faces_the_travel_with_the_cursor_out_wide() -> void:
	_solve(AHEAD, LEFT, AHEAD * 6.0)
	assert_almost_eq(_off(AHEAD), 0.0, 0.01)
	assert_false(_out.turning_to_cursor_behind)


func test_taking_up_the_travel_needs_skating_speed() -> void:
	# Facing the cursor, moving at side-step pace: stays on the cursor.
	_solve(LEFT, LEFT, AHEAD * 1.5)
	assert_almost_eq(_off(LEFT), 0.0, 0.01, "a side-step tap stays squared")
	_solve(LEFT, LEFT, AHEAD * 2.4)
	assert_almost_eq(_off(AHEAD), 0.0, 0.01, "past the engage band it takes the travel")


func test_keeping_the_travel_holds_down_to_a_crawl() -> void:
	# Already facing the travel: a coast keeps it well below the engage band.
	_solve(AHEAD, LEFT, AHEAD * 1.5)
	assert_almost_eq(_off(AHEAD), 0.0, 0.01)
	_solve(AHEAD, LEFT, AHEAD * 0.4)
	assert_almost_eq(_off(LEFT), 0.0, 0.01, "nearly stopped, it hands back to the cursor")


func test_braking_faces_the_cursor() -> void:
	_solve(AHEAD, LEFT, AHEAD * 6.0, true)
	assert_almost_eq(_off(LEFT), 0.0, 0.01)


func test_a_cursor_behind_the_travel_turns_round() -> void:
	_solve(AHEAD, BEHIND, AHEAD * 6.0)
	assert_almost_eq(_off(BEHIND), 0.0, 0.01)
	assert_true(_out.turning_to_cursor_behind)


func test_the_cone_has_hysteresis() -> void:
	var at_128 := AHEAD.rotated(deg_to_rad(128.0))
	_solve(AHEAD, at_128, AHEAD * 6.0)
	assert_false(_out.turning_to_cursor_behind, "following, 128° is inside 120 + 15")
	_solve(at_128, at_128, AHEAD * 6.0)
	assert_true(_out.turning_to_cursor_behind, "facing the cursor, 128° is past 120 − 15")


func test_the_stance_squares_only_when_slow() -> void:
	_solve(LEFT, LEFT, AHEAD * 2.0, false, true)
	assert_almost_eq(_off(LEFT), 0.0, 0.01, "slow in the stance squares to the cursor")
	_solve(AHEAD, LEFT, AHEAD * 6.0, false, true)
	assert_almost_eq(_off(AHEAD), 0.0, 0.01, "at speed the stance just crouches")


func test_a_backward_skater_takes_up_the_travel_ahead() -> void:
	_solve(BEHIND, AHEAD, AHEAD * 6.0)
	assert_almost_eq(_off(AHEAD), 0.0, 0.01)
	assert_true(_out.free_to_turn_round)


func test_only_a_standing_skater_is_held_off_a_target_behind() -> void:
	_solve(BEHIND, AHEAD.rotated(deg_to_rad(30.0)), AHEAD * 1.0)
	assert_true(_out.free_to_turn_round, "a slow skate below the engage band still turns")
	_solve(AHEAD, BEHIND, AHEAD * 6.0, true)
	assert_true(_out.free_to_turn_round, "so does a stop")
	_solve(AHEAD, BEHIND, AHEAD * 2.0, false, true)
	assert_true(_out.free_to_turn_round, "and the stance when slow")
	_solve(AHEAD, BEHIND, AHEAD * 0.3)
	assert_false(_out.free_to_turn_round, "nearly stopped is standing")
	_solve(AHEAD, BEHIND, Vector2.ZERO)
	assert_false(_out.free_to_turn_round)


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
