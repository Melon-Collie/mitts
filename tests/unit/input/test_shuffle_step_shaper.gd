extends GutTest

# ShuffleStepShaper through the real movement model: from a standstill, a tap to
# the side or back is one step of shuffle_step_distance that plants, whatever
# the direction or the build's brake; a press held past the tap window is the
# plain start, to the tick; a press ahead always skates; and under the player's
# own brake the stick never moves the skater.

const DT: float = 1.0 / 120.0
const FACING_UP: float = 0.0   # facing −Z
const FACING := Vector2(0.0, -1.0)
const RIGHT := Vector2(1.0, 0.0)
const AHEAD := Vector2(0.0, -1.0)
const TAP_S: float = 0.05
# A step lets go of the stick on a tick, so it lands within half a tick's travel
# either side of the mark (about 1.5 cm at a step's peak pace).
const LAND_TOL_M: float = 0.02

var _cfg: SkaterMovementRules.MovementConfig = null
var _distance: float = 0.0
var _shaper: ShuffleStepShaper = null
var _pos := Vector3.ZERO
var _vel := Vector3.ZERO


func before_each() -> void:
	var controller := SkaterController.new()
	autofree(controller)
	_cfg = controller._build_movement_config()
	_distance = controller.shuffle_step_distance
	_shaper = ShuffleStepShaper.new()
	_pos = Vector3.ZERO
	_vel = Vector3.ZERO


func _tick(stick: Vector2, brake: bool = false) -> InputState:
	var input := InputState.new()
	input.move_vector = stick
	input.brake = brake
	input.delta = DT
	_shaper.shape(input, _pos, _vel, FACING, _distance, _cfg.stop_decel)
	_vel = SkaterMovementRules.apply_movement(_vel, input.move_vector, FACING_UP, false,
			input.brake, DT, _cfg)
	_pos += _vel * DT
	return input


func _hold(stick: Vector2, seconds: float, brake: bool = false) -> void:
	for _i: int in roundi(seconds / DT):
		_tick(stick, brake)


func _tap(stick: Vector2) -> void:
	_hold(stick, TAP_S)
	_hold(Vector2.ZERO, 1.0)


func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func test_a_tap_to_the_side_is_one_step_that_plants() -> void:
	_tap(RIGHT)
	assert_almost_eq(_pos.x, _distance, LAND_TOL_M)
	assert_almost_eq(_pos.z, 0.0, 1e-4)
	assert_eq(_vel, Vector3.ZERO, "planted again, with no brake from the player")


func test_taps_to_the_side_and_back_step_the_same_distance() -> void:
	for stick: Vector2 in [RIGHT, -RIGHT, -AHEAD, (RIGHT - AHEAD).normalized()]:
		before_each()
		_tap(stick)
		assert_almost_eq(_flat(_pos).length(), _distance, LAND_TOL_M, "stick %s" % stick)
		assert_almost_eq(_flat(_pos).normalized().dot(stick), 1.0, 1e-3, "along %s" % stick)
		assert_eq(_vel, Vector3.ZERO, "planted — stick %s" % stick)


func test_a_tap_ahead_is_a_start_not_a_step() -> void:
	for stick: Vector2 in [AHEAD, (RIGHT + AHEAD).normalized()]:
		before_each()
		var input: InputState = _tick(stick)
		assert_false(input.brake, "stick %s: no step's brake" % stick)
		assert_eq(input.move_vector, stick, "stick %s: the push passes through" % stick)
		_hold(stick, TAP_S)
		_hold(Vector2.ZERO, 1.0)
		assert_gt(_vel.length(), 0.0, "stick %s: gliding on, not planted" % stick)


func test_the_distance_holds_for_any_build_s_brake() -> void:
	for decel: float in [7.0, 11.0]:
		before_each()
		_cfg.stop_decel = decel
		_tap(RIGHT)
		assert_almost_eq(_pos.x, _distance, LAND_TOL_M, "stop_decel %.0f" % decel)


func test_each_tap_is_another_step() -> void:
	for _press: int in 3:
		_tap(RIGHT)
	assert_almost_eq(_pos.x, 3.0 * _distance, 3.0 * LAND_TOL_M)


# A press held past the tap window was never a tap. It pushed off as any start
# does from the first tick, so a held start is the unshaped start exactly.
func test_a_hold_is_a_start_that_loses_nothing() -> void:
	for stick: Vector2 in [RIGHT, -AHEAD, (RIGHT - AHEAD).normalized()]:
		before_each()
		var raw_pos := Vector3.ZERO
		var raw_vel := Vector3.ZERO
		var braked: bool = false
		for _i: int in roundi(1.0 / DT):
			braked = braked or _tick(stick).brake
			raw_vel = SkaterMovementRules.apply_movement(raw_vel, stick, FACING_UP, false,
					false, DT, _cfg)
			raw_pos += raw_vel * DT
		assert_false(braked, "stick %s: no step's brake" % stick)
		assert_eq(_pos, raw_pos, "stick %s: the same start as with no shaping" % stick)
		assert_gt(_vel.length(), SkaterMovementRules.shuffle_ceiling(_cfg),
				"stick %s: skating past the shuffle's pace" % stick)


func test_a_press_while_moving_skates() -> void:
	_vel = Vector3(0.0, 0.0, -3.0)
	var input: InputState = _tick(RIGHT)
	assert_false(input.brake)
	assert_eq(input.move_vector, RIGHT)


func test_under_the_player_s_brake_the_stick_does_not_step() -> void:
	_hold(RIGHT, 1.0, true)
	assert_eq(_pos, Vector3.ZERO)


func test_a_key_held_before_the_brake_lets_go_is_no_press() -> void:
	_hold(RIGHT, 0.5, true)
	var input: InputState = _tick(RIGHT)
	assert_false(input.brake, "releasing Space with the key down is no tap")


# Under the brake the stick never reaches the movement model, so a stop with a
# key still down stops straight and stays stopped.
func test_a_hockey_stop_with_the_stick_held_is_a_stop() -> void:
	_vel = Vector3(0.0, 0.0, -8.0)
	_hold(RIGHT, 2.0, true)
	assert_eq(_vel, Vector3.ZERO)
	assert_almost_eq(_pos.x, 0.0, 1e-4, "never turned toward the stick")


func test_the_player_s_brake_cancels_a_step() -> void:
	_hold(RIGHT, TAP_S)
	_hold(Vector2.ZERO, 1.0, true)
	assert_lt(_pos.x, _distance, "the stop took over mid-step")
	assert_eq(_vel, Vector3.ZERO)


# A pad stick wandering about the press threshold is one press, not several.
func test_a_wobbling_stick_is_one_press() -> void:
	for i: int in roundi(TAP_S / DT):
		_tick(RIGHT * (0.55 if i % 2 == 0 else 0.45))
	_hold(Vector2.ZERO, 1.0)
	assert_almost_eq(_pos.x, _distance, LAND_TOL_M)
