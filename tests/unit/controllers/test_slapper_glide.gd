extends GutTest

# Wound up, a skater glides (docs/slapshot-realism-plan.md, Phase 4): the
# wind-up neither strides nor plants, so a slapshot taken at speed keeps that
# speed as a coast would, and the stick adds nothing. Waiting on a feed with no
# puck yet, he can still step-together onto its line. Driven through the real
# controller.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const State = SkaterStateMachine.State
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const UP_ICE := Vector2(0.0, -1.0)


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _skater: Skater = null
var _controller: SkaterController = null
var _puck: Puck = null
var _input := InputState.new()


func before_each() -> void:
	_puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(_puck)
	_puck.set_physics_process(false)
	_puck.global_position = Vector3(20.0, 0.0, 20.0)
	_skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(_skater)
	_skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 20.0)
	_skater.set_process(false)
	_skater.set_physics_process(false)
	var state := StubGameState.new()
	add_child_autofree(state)
	_controller = SkaterController.new()
	add_child_autofree(_controller)
	_controller.setup(_skater, _puck, state)
	_controller.set_process(false)
	_controller.set_physics_process(false)


func _carry() -> void:
	_puck.set_carrier(_skater)
	_controller.on_puck_picked_up_network()


func _tick(move: Vector2, slap: bool, press: bool = false, brake: bool = false) -> void:
	_input.delta = DT
	_input.host_timestamp += DT
	_input.move_vector = move
	_input.brake = brake
	_input.mouse_world_pos = _skater.global_position + Vector3(0.0, 0.0, -12.0)
	_input.mouse_world_pos.y = 0.0
	_input.slap_held = slap
	_input.slap_pressed = press
	_controller._process_input(_input, DT)
	_skater._physics_process(DT)


func _speed() -> float:
	return Vector2(_skater.velocity.x, _skater.velocity.z).length()


# Skated up the ice to speed, then `ticks` more of `then`: a coast (no stick) or
# a slapshot wound up with the stick still held up the ice.
func _from_speed(wind_up: bool, ticks: int) -> float:
	for i: int in 240:
		_tick(UP_ICE, false)
	_tick(UP_ICE, wind_up, wind_up)
	for i: int in ticks:
		_tick(UP_ICE if wind_up else Vector2.ZERO, wind_up)
	return _speed()


func test_a_wind_up_at_speed_keeps_it_as_a_coast_would() -> void:
	_carry()
	var wound: float = _from_speed(true, 60)
	assert_eq(_skater.current_shot_state, State.SLAPPER_CHARGE_WITH_PUCK)
	before_each()
	_carry()
	var coasted: float = _from_speed(false, 60)
	assert_gt(coasted, 5.0, "the control skated up to speed")
	assert_almost_eq(wound, coasted, 0.05,
			"wound up, the skater glides on — no plant, and no stride from the held stick")


func test_the_stick_does_not_turn_a_wound_up_skater() -> void:
	_carry()
	for i: int in 240:
		_tick(UP_ICE, false)
	var heading := Vector2(_skater.velocity.x, _skater.velocity.z).normalized()
	_tick(UP_ICE, true, true)
	for i: int in 60:
		_tick(Vector2(1.0, 0.0), true)
	var after := Vector2(_skater.velocity.x, _skater.velocity.z).normalized()
	assert_almost_eq(rad_to_deg(heading.angle_to(after)), 0.0, 0.5, "the glide holds its line")
	assert_eq(_skater.move_intent, Vector2.ZERO, "and publishes no intent to skate")


func test_waiting_on_a_feed_the_shooter_can_step_onto_its_line() -> void:
	_tick(Vector2.ZERO, true, true)
	for i: int in 60:
		_tick(Vector2(1.0, 0.0), true, false, true)
	assert_eq(_skater.current_shot_state, State.SLAPPER_CHARGE_WITHOUT_PUCK)
	assert_gt(_skater.velocity.x, 0.5, "the shuffle steps him sideways (%.2f m/s)" % _skater.velocity.x)
	assert_lt(_speed(), SkaterMovementRules.SHUFFLE_MAX_SPEED + 0.01, "at a step's pace, never a skate")


func test_with_the_puck_he_cannot_step() -> void:
	_carry()
	for i: int in 60:
		_tick(Vector2.ZERO, false)
	_tick(Vector2.ZERO, true, true)
	for i: int in 60:
		_tick(Vector2(1.0, 0.0), true, false, true)
	assert_eq(_skater.current_shot_state, State.SLAPPER_CHARGE_WITH_PUCK)
	assert_lt(_speed(), 0.05, "the stance is set: no step, no skate")
