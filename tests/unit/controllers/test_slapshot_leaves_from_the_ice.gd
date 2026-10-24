extends GutTest

# A slapshot leaves from where the blade meets the puck on the ice, not from
# under the blade lifted overhead at the release — two metres apart on the
# default build. Held on every path a slapshot fires by: the host's release, a
# loose one-timer the swing meets, and the shooter's own prediction of each.
# Driven through the real controller and rig.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const State = SkaterStateMachine.State
const DT: float = 1.0 / 120.0
const AIM := Vector3(0.0, 0.0, -12.0)
const FLAT_SHOT := Vector3(0.0, 0.0, -1.0)
const POWER: float = 30.0


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _skater: Skater = null
var _puck: Puck = null
var _controller: SkaterController = null
var _input := InputState.new()


func before_each() -> void:
	_puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(_puck)
	_puck.set_physics_process(false)
	_puck.global_position = Vector3(20.0, 0.0, 20.0)
	_skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(_skater)
	_skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 10.0)
	_skater.set_process(false)
	_skater.set_physics_process(false)
	var state := StubGameState.new()
	add_child_autofree(state)
	_controller = SkaterController.new()
	add_child_autofree(_controller)
	_controller.setup(_skater, _puck, state)
	_controller.set_process(false)
	_controller.set_physics_process(false)


func _tick(slap: bool, press: bool = false) -> void:
	_input.delta = DT
	_input.host_timestamp += DT
	_input.move_vector = Vector2.ZERO
	_input.mouse_world_pos = _skater.global_position + AIM
	_input.mouse_world_pos.y = 0.0
	_input.slap_held = slap
	_input.slap_pressed = press
	_controller._process_input(_input, DT)
	_skater._physics_process(DT)


func _strike_spot() -> Vector3:
	var s: Vector2 = _controller.slapper_strike_local()
	return _skater.to_global(Vector3(s.x, 0.0, s.y))


func _gap(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# Carried, set, and wound up for 0.75 s: the tick before the release.
func _wind_up_carried() -> void:
	_puck.set_carrier(_skater)
	_controller.on_puck_picked_up_network()
	_tick(true, true)
	while not _controller._aiming.slapper_setup_done:
		_tick(true)
	for i: int in 90:
		_tick(true)


# A puckless wind-up let go with the puck lying on the strike spot, run through
# the hold to the tick the swing lands.
func _swing_at_a_loose_puck() -> void:
	_controller.on_puck_released_network()
	_tick(true, true)
	for i: int in 90:
		_tick(true)
	var spot: Vector3 = _strike_spot()
	_puck.global_position = Vector3(spot.x, _puck.ice_height, spot.z)
	_puck.linear_velocity = Vector3.ZERO
	for i: int in 120:
		_tick(false)
		if _skater.current_shot_state == State.FOLLOW_THROUGH:
			return


func _client_prediction() -> PuckController:
	var pc := PuckController.new()
	autofree(pc)
	pc.setup(_puck, false)
	return pc


func test_the_raised_blade_is_far_from_the_puck_at_the_release() -> void:
	_wind_up_carried()
	var gap: float = _gap(_skater.get_blade_contact_global(), _skater.get_carry_target_global())
	assert_gt(gap, 0.5, "the case this file exists for: the blade is overhead (%.2f m off)" % gap)


func test_a_carried_slapshot_leaves_from_its_pin() -> void:
	_wind_up_carried()
	var pin: Vector3 = _skater.get_carry_target_global()
	_puck.release(FLAT_SHOT, POWER)
	assert_lt(_gap(_puck.global_position, pin), 0.001)


func test_the_shooters_prediction_leaves_from_where_the_host_fires() -> void:
	_wind_up_carried()
	var pc := _client_prediction()
	pc._local_carrier_skater = _skater
	var predicted: Vector3 = pc.notify_local_release(FLAT_SHOT, POWER)
	_puck.set_carrier(_skater)
	_puck.release(FLAT_SHOT, POWER)
	assert_lt(_gap(predicted, _puck.global_position), 0.001,
			"predicted %s, host fired from %s" % [predicted, _puck.global_position])


# GameManager._host_release_one_timer: the loose puck is handed to the shooter
# and released on the tick the swing lands.
func test_a_loose_one_timer_leaves_from_the_strike_spot() -> void:
	_swing_at_a_loose_puck()
	assert_eq(_skater.current_shot_state, State.FOLLOW_THROUGH, "the swing landed")
	var spot: Vector3 = _strike_spot()
	_puck.set_carrier(_skater)
	_puck.release(FLAT_SHOT, POWER)
	assert_lt(_gap(_puck.global_position, spot), 0.001,
			"fired %.2f m off the strike spot" % _gap(_puck.global_position, spot))


func test_a_loose_one_timers_prediction_leaves_from_the_strike_spot() -> void:
	_swing_at_a_loose_puck()
	var spot: Vector3 = _strike_spot()
	var predicted: Vector3 = _client_prediction().notify_local_release(FLAT_SHOT, POWER, _skater)
	assert_lt(_gap(predicted, spot), 0.001)
