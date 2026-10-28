extends GutTest

# The shuffle through the real movement model and its input shaper: Space held
# with a key, slow, steps toward the key at the shuffle's pace, in any
# direction; let go of, it closes its step-together and plants; a key alone is a
# start; and a stop with W held stops, while one with a key across the travel
# slows into the shuffle.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const FACING_UP: float = 0.0   # facing −Z
const RIGHT := Vector2(1.0, 0.0)
const AHEAD := Vector2(0.0, -1.0)
# A step lets go of the stick on a tick, so it lands within half a tick's travel
# either side of its close.
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
	_shaper.shape(input, _vel, _distance, _cfg.stop_decel)
	_vel = SkaterMovementRules.apply_movement(_vel, input.move_vector, FACING_UP, false,
			input.brake, DT, _cfg)
	_pos += _vel * DT
	return input


func _hold(stick: Vector2, seconds: float, brake: bool = false) -> void:
	for _i: int in roundi(seconds / DT):
		_tick(stick, brake)


func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


# How far past its last closed step-together a distance lies, either way.
func _off_a_close(travelled: float) -> float:
	var into: float = fmod(travelled, _distance)
	return minf(into, _distance - into)


func test_space_and_a_key_shuffles_at_its_pace_in_any_direction() -> void:
	for stick: Vector2 in [RIGHT, -RIGHT, -AHEAD, AHEAD, (RIGHT - AHEAD).normalized()]:
		before_each()
		_hold(stick, 1.0, true)
		assert_almost_eq(_flat(_vel).length(), _cfg.shuffle_speed, 0.01, "stick %s: its pace" % stick)
		assert_almost_eq(_flat(_vel).normalized().dot(stick), 1.0, 1e-3, "stick %s: its way" % stick)


func test_letting_go_of_the_key_closes_the_step_and_plants() -> void:
	for held_s: float in [0.3, 0.55, 0.8]:
		before_each()
		_hold(RIGHT, held_s, true)
		_hold(Vector2.ZERO, 1.0, true)
		assert_eq(_vel, Vector3.ZERO, "held %.2f s: planted" % held_s)
		assert_lt(_off_a_close(_pos.x), LAND_TOL_M, "held %.2f s: on a closed step" % held_s)


func test_letting_go_of_both_closes_the_step_and_plants() -> void:
	_hold(RIGHT, 0.55, true)
	_hold(Vector2.ZERO, 1.0)
	assert_eq(_vel, Vector3.ZERO, "planted, with no brake from the player")
	assert_lt(_off_a_close(_pos.x), LAND_TOL_M)


func test_a_quick_press_is_one_whole_step() -> void:
	_hold(RIGHT, 0.03, true)
	_hold(Vector2.ZERO, 1.0, true)
	assert_almost_eq(_pos.x, _distance, LAND_TOL_M)
	assert_eq(_vel, Vector3.ZERO)


func test_the_close_holds_for_any_build_s_brake() -> void:
	for decel: float in [7.0, 11.0]:
		before_each()
		_cfg.stop_decel = decel
		_hold(RIGHT, 0.03, true)
		_hold(Vector2.ZERO, 1.0, true)
		assert_almost_eq(_pos.x, _distance, LAND_TOL_M, "stop_decel %.0f" % decel)


# A key alone is a start, shaped by nothing.
func test_a_key_without_space_is_a_start() -> void:
	for stick: Vector2 in [RIGHT, -AHEAD, AHEAD]:
		before_each()
		var raw_vel := Vector3.ZERO
		for _i: int in roundi(0.05 / DT):
			var input: InputState = _tick(stick)
			assert_false(input.brake, "stick %s: no brake added" % stick)
			raw_vel = SkaterMovementRules.apply_movement(raw_vel, stick, FACING_UP, false,
					false, DT, _cfg)
		assert_eq(_vel, raw_vel, "stick %s: the start exactly" % stick)
		_hold(Vector2.ZERO, 1.0)
		assert_gt(_vel.length(), 0.0, "stick %s: gliding on, not planted" % stick)


func test_releasing_space_with_the_key_down_is_a_start() -> void:
	_hold(RIGHT, 0.5, true)
	var input: InputState = _tick(RIGHT)
	assert_false(input.brake)
	assert_eq(input.move_vector, RIGHT)


# W held into a stop at speed stops, and stays stopped.
func test_a_stop_with_w_held_stops() -> void:
	_vel = Vector3(0.0, 0.0, -8.0)
	_hold(AHEAD, 2.0, true)
	assert_eq(_vel, Vector3.ZERO)
	var at: Vector3 = _pos
	_hold(AHEAD, 1.0, true)
	assert_eq(_pos, at, "no creeping off forward")


func test_a_stop_with_a_key_across_slows_into_the_shuffle() -> void:
	_vel = Vector3(0.0, 0.0, -8.0)
	_hold(RIGHT, 2.0, true)
	assert_almost_eq(_flat(_vel).length(), _cfg.shuffle_speed, 0.01)
	assert_almost_eq(_flat(_vel).normalized().dot(RIGHT), 1.0, 1e-3)


func test_a_key_pressed_once_braking_shuffles() -> void:
	_vel = Vector3(0.0, 0.0, -8.0)
	_hold(Vector2.ZERO, 0.2, true)
	_hold(AHEAD, 2.0, true)
	assert_almost_eq(_flat(_vel).length(), _cfg.shuffle_speed, 0.01)
	assert_almost_eq(_flat(_vel).normalized().dot(AHEAD), 1.0, 1e-3)


# A pad stick wandering about the press threshold is one press, not several.
func test_a_wobbling_stick_is_one_press() -> void:
	for i: int in 4:
		_tick(RIGHT * (0.55 if i % 2 == 0 else 0.45), true)
	_hold(Vector2.ZERO, 1.0, true)
	assert_almost_eq(_pos.x, _distance, LAND_TOL_M)
