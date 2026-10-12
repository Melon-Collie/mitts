extends GutTest

# ShuffleStepShaper through the real movement model: with the brake held, each
# press of a direction is one step of shuffle_step_distance, whatever the
# direction, the build's brake or how long the key stays down.

const DT: float = 1.0 / 120.0
const FACING_UP: float = 0.0   # facing −Z
const RIGHT := Vector2(1.0, 0.0)
const AHEAD := Vector2(0.0, -1.0)

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


func _tick(stick: Vector2, brake: bool) -> InputState:
	var input := InputState.new()
	input.move_vector = stick
	input.brake = brake
	input.delta = DT
	_shaper.shape(input, _pos, _vel, _distance, _cfg.stop_decel,
			SkaterMovementRules.shuffle_ceiling(_cfg))
	_vel = SkaterMovementRules.apply_movement(_vel, input.move_vector, FACING_UP, false,
			input.brake, DT, _cfg)
	_pos += _vel * DT
	return input


func _hold(stick: Vector2, brake: bool, seconds: float) -> void:
	for _i: int in roundi(seconds / DT):
		_tick(stick, brake)


func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func test_a_tap_is_one_step() -> void:
	_hold(Vector2.ZERO, true, 0.1)
	_hold(RIGHT, true, 0.05)
	_hold(Vector2.ZERO, true, 1.0)
	assert_almost_eq(_pos.x, _distance, 0.01)
	assert_almost_eq(_pos.z, 0.0, 1e-4)
	assert_eq(_vel, Vector3.ZERO, "planted again")


func test_holding_the_key_is_still_one_step() -> void:
	_hold(Vector2.ZERO, true, 0.1)
	_hold(RIGHT, true, 2.0)
	assert_almost_eq(_pos.x, _distance, 0.01)
	assert_eq(_vel, Vector3.ZERO)


func test_every_direction_steps_the_same_distance() -> void:
	for stick: Vector2 in [RIGHT, -RIGHT, AHEAD, -AHEAD, (RIGHT + AHEAD).normalized()]:
		before_each()
		_hold(Vector2.ZERO, true, 0.1)
		_hold(stick, true, 2.0)
		assert_almost_eq(_flat(_pos).length(), _distance, 0.01, "stick %s" % stick)
		assert_almost_eq(_flat(_pos).normalized().dot(stick), 1.0, 1e-3, "along %s" % stick)


func test_the_distance_holds_for_any_build_s_brake() -> void:
	for decel: float in [7.0, 11.0]:
		before_each()
		_cfg.stop_decel = decel
		_hold(Vector2.ZERO, true, 0.1)
		_hold(RIGHT, true, 2.0)
		assert_almost_eq(_pos.x, _distance, 0.01, "stop_decel %.0f" % decel)


func test_each_press_is_another_step() -> void:
	_hold(Vector2.ZERO, true, 0.1)
	for _press: int in 3:
		_hold(RIGHT, true, 0.08)
		_hold(Vector2.ZERO, true, 0.6)
	assert_almost_eq(_pos.x, 3.0 * _distance, 0.03)


func test_a_key_held_before_the_brake_is_no_press() -> void:
	_hold(RIGHT, false, 0.02)
	_vel = Vector3.ZERO
	_pos = Vector3.ZERO
	_hold(RIGHT, true, 1.0)
	assert_eq(_pos, Vector3.ZERO)


# The stick never reaches the movement model under the brake outside a step, so
# a stop with a key still down stops straight and stays stopped.
func test_a_hockey_stop_with_the_stick_held_is_a_stop() -> void:
	_hold(RIGHT, false, 0.01)
	_vel = Vector3(0.0, 0.0, -8.0)
	_pos = Vector3.ZERO
	_hold(RIGHT, true, 2.0)
	assert_eq(_vel, Vector3.ZERO)
	assert_almost_eq(_pos.x, 0.0, 1e-4, "never turned toward the stick")


func test_without_the_brake_the_stick_passes_through() -> void:
	var input: InputState = _tick(Vector2(0.3, -0.8), false)
	assert_eq(input.move_vector, Vector2(0.3, -0.8))


# A pad stick wandering about the press threshold is one press, not several.
func test_a_wobbling_stick_is_one_press() -> void:
	_hold(Vector2.ZERO, true, 0.1)
	for i: int in 60:
		_tick(RIGHT * (0.55 if i % 2 == 0 else 0.45), true)
	_hold(Vector2.ZERO, true, 1.0)
	assert_almost_eq(_pos.x, _distance, 0.01)
