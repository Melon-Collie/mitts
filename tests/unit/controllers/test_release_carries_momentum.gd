extends GutTest

# SkaterController folds the skater's motion into a quick pass's and a wrist
# shot's release (ReleaseMomentum) before it emits it, so every consumer of
# puck_release_requested — the host's release, the shooter's release seed — fires
# the momentum-carrying puck.

const DT: float = 1.0 / 120.0
const AHEAD := Vector3(0.0, 0.0, -4.0)


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _skater: Skater = null
var _controller: SkaterController = null
var _input := InputState.new()
var _released: Array[Vector3] = []
var _velocity_at_release := Vector3.ZERO


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
	_velocity_at_release = _skater.velocity


func _tick(count: int, move: Vector2) -> void:
	for i: int in count:
		_input.delta = DT
		_input.host_timestamp += DT
		_input.move_vector = move
		_input.mouse_world_pos = _skater.global_position + AHEAD
		_controller._process_input(_input, DT)
		_skater._physics_process(DT)
		_input.quick_pass_pressed = false
		_input.shoot_pressed = false


func _quick_pass_after(move: Vector2) -> Vector3:
	_tick(120, move)
	_input.quick_pass_pressed = true
	_tick(1, move)
	assert_eq(_released.size(), 1, "the pass went")
	return _released[0] if not _released.is_empty() else Vector3.ZERO


func test_a_quick_pass_in_stride_adds_the_skaters_pace() -> void:
	var r: Vector3 = _quick_pass_after(Vector2(0.0, -1.0))
	var v := Vector2(_velocity_at_release.x, _velocity_at_release.z)
	assert_gt(v.length(), 4.0, "the skater is moving")
	var d := Vector2(r.x, r.z).normalized()
	var expected: Vector3 = ReleaseMomentum.release_velocity(
			Vector3(d.x, 0.0, d.y), _controller.quick_pass_power, _velocity_at_release, true)
	assert_almost_eq(Vector2(r.x, r.z).length(), Vector2(expected.x, expected.z).length(), 0.01,
			"the pass carries the body's motion")
	assert_gt(Vector2(r.x, r.z).length(), _controller.quick_pass_power + 3.0)


func test_a_quick_pass_standing_still_is_the_push_alone() -> void:
	var r: Vector3 = _quick_pass_after(Vector2.ZERO)
	assert_almost_eq(r.length(), _controller.quick_pass_power, 0.01)


func test_a_tapped_wrister_in_stride_lands_no_harder_than_the_floor_or_the_stride() -> void:
	var stride := Vector2(0.0, -1.0)
	_tick(120, stride)
	_input.shoot_pressed = true
	_input.shoot_held = true
	_tick(1, stride)
	_input.shoot_held = false
	_tick(1, stride)
	assert_eq(_released.size(), 1, "the tap went")
	if _released.is_empty():
		return
	var r: Vector3 = _released[0]
	var d := Vector2(r.x, r.z).normalized()
	assert_gt(Vector2(_velocity_at_release.x, _velocity_at_release.z).dot(d), 4.0,
			"skating at the target")
	assert_lte(r.length(),
			maxf(_controller.min_wrister_power, _velocity_at_release.length()) + 0.05,
			"the hands cushion the softest touch to the standing floor, or let it ride")

