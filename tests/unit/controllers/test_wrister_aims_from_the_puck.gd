extends GutTest

# A wrist shot fires from where the frozen puck sits toward the cursor, however
# far the skater carried it during the wind-up: a cut taken with the button held
# moves the puck, and the aim line moves with it.

const DT: float = 1.0 / 90.0
const NET := Vector3(0.0, 0.0, -6.0)
# Screen pixels a tick for the flick: past full power at any sensitivity, so the
# push can cancel the skater's cross motion and the puck goes exactly on the aim.
const FLICK_PX: float = 80.0


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _skater: Skater = null
var _controller: SkaterController = null
var _input := InputState.new()
var _released: Array[Vector3] = []
var _puck_at_release := Vector3.ZERO


func before_each() -> void:
	var puck: Puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	add_child_autofree(puck)
	puck.global_position = Vector3(20.0, 0.0, 20.0)
	_skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(_skater)
	_skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 10.0)
	_skater.set_process(false)
	_skater.set_physics_process(false)
	var state := StubGameState.new()
	add_child_autofree(state)
	_controller = SkaterController.new()
	add_child_autofree(_controller)
	_controller.setup(_skater, puck, state)
	_controller.set_process(false)
	_controller.set_physics_process(false)
	_controller.puck_release_requested.connect(_on_release)
	_input = InputState.new()
	_input.host_timestamp = 10.0
	_released.clear()
	_controller.on_puck_picked_up_network(0)


func _on_release(direction: Vector3, power: float, _is_slapper: bool) -> void:
	_released.append(direction * power)
	_puck_at_release = _skater.get_blade_contact_global()


func _tick(move: Vector2, screen_step: float) -> void:
	_input.delta = DT
	_input.host_timestamp += DT
	_input.move_vector = move
	_input.mouse_world_pos = NET
	_input.mouse_screen_pos += Vector2(screen_step, 0.0)
	_controller._process_input(_input, DT)
	_skater._physics_process(DT)
	_input.shoot_pressed = false


# Skates up the ice in the stance, presses the wrister, cuts `cut` through the
# wind-up and flicks it off. Returns the shot's angle off puck→net (degrees).
func _shot_error_through(cut: Vector2) -> float:
	_input.stance_held = true
	for i: int in 90:
		_tick(Vector2(0.0, -1.0), 0.0)
	var pressed_at: Vector3 = _skater.global_position
	_input.shoot_pressed = true
	_input.shoot_held = true
	for i: int in 50:
		_tick(cut, FLICK_PX if i >= 44 else 0.0)
	assert_gt(Vector2(_skater.global_position.x - pressed_at.x,
			_skater.global_position.z - pressed_at.z).length(), 1.5,
			"the cut carried the puck well off where the button went down")
	_input.shoot_held = false
	_tick(cut, 0.0)
	assert_eq(_released.size(), 1, "the shot went")
	if _released.is_empty():
		return INF
	var to_net := Vector2(NET.x - _puck_at_release.x, NET.z - _puck_at_release.z)
	return rad_to_deg(absf(Vector2(_released[0].x, _released[0].z).angle_to(to_net)))


func test_a_wrister_through_a_cut_left_fires_from_the_puck() -> void:
	assert_lt(_shot_error_through(Vector2(-1.0, 0.0)), 1.0)


func test_a_wrister_through_a_cut_right_fires_from_the_puck() -> void:
	assert_lt(_shot_error_through(Vector2(1.0, 0.0)), 1.0)
