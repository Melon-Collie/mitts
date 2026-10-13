extends GutTest

# WristerPocket — where to hold the puck so a release toward an aim carries the
# most it can. World XZ; "ahead" is −Z, a lefty's stick side is −X (left).

const AHEAD := Vector2(0.0, -1.0)
const LEFT := Vector2(-1.0, 0.0)
const RIGHT := Vector2(1.0, 0.0)
const LEFTY: bool = true
const RIGHTY: bool = false

var _load_cfg := WristerLoad.Config.new()
var _facing_cfg := FacingRules.Config.new()
var _out := WristerPocket.Result.new()
var _facing := FacingRules.Result.new()
var _load := WristerLoad.Result.new()


func _solve(aim: Vector2, velocity: Vector2, left_handed: bool,
		facing: Vector2 = AHEAD) -> WristerPocket.Result:
	WristerPocket.solve(_out, aim, velocity, facing, left_handed, _load_cfg, _facing_cfg,
			0.6, 0.75, _facing, _load)
	return _out


func _off(dir: Vector2) -> float:
	return rad_to_deg(absf(_out.dir.angle_to(dir)))


func test_skating_a_shot_ahead_is_held_beside_the_stick_hip() -> void:
	_solve(AHEAD, AHEAD * 6.0, LEFTY)
	assert_false(_out.is_backhand)
	assert_almost_eq(_out.power_share, 1.0, 0.001)
	assert_lt(_off(LEFT), 46.0, "a lefty's pocket is out on the left")


func test_skating_a_shot_across_to_the_off_side_sweeps_across_the_front() -> void:
	_solve(RIGHT, AHEAD * 6.0, LEFTY)
	assert_false(_out.is_backhand)
	assert_almost_eq(_out.power_share, 1.0, 0.001)


func test_skating_a_shot_to_the_stick_side_takes_the_best_it_can() -> void:
	# A forehand to the stick side would need the puck behind the body; the
	# backhand sweeping the puck across from in front is the loaded release.
	_solve(LEFT, AHEAD * 6.0, LEFTY)
	assert_gt(_out.power_share, 0.74)


func test_standing_turns_side_on_with_the_puck_in_front() -> void:
	# At rest the body faces the cursor, so the pocket off to the stick side
	# becomes "puck in front, aim off to the side": a full forehand.
	_solve(AHEAD, Vector2.ZERO, LEFTY)
	assert_false(_out.is_backhand)
	assert_almost_eq(_out.power_share, 1.0, 0.001)


func test_right_handed_mirrors() -> void:
	_solve(AHEAD, AHEAD * 6.0, RIGHTY)
	assert_false(_out.is_backhand)
	assert_almost_eq(_out.power_share, 1.0, 0.001)
	assert_lt(_off(RIGHT), 46.0, "a righty's pocket is out on the right")


func test_no_aim_leaves_everything_alone() -> void:
	_solve(Vector2.ZERO, AHEAD * 6.0, LEFTY)
	assert_almost_eq(_out.power_share, 1.0, 0.001)
