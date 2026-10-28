extends GutTest

# Calling a slapshot off is a real fake, and it costs the stick coming back down
# (docs/slapshot-realism-plan.md, Phase 2): the puck stays where it lies, every
# on-puck action waits for a recovery that grows with the wind-up, a press inside
# it fires on the first input past it, and the carry takes the puck back without
# moving it. Driven through the real controller and rig.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const State = SkaterStateMachine.State
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const AHEAD := Vector3(0.0, 0.0, -12.0)


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _skater: Skater = null
var _controller: SkaterController = null
var _input := InputState.new()


func before_each() -> void:
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	puck.global_position = Vector3(20.0, 0.0, 20.0)
	_skater = SKATER_SCENE.instantiate() as Skater
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
	puck.set_carrier(_skater)
	_controller.on_puck_picked_up_network()


func _tick(slap: bool, slap_press: bool = false, shoot_press: bool = false,
		shoot: bool = false) -> void:
	_input.delta = DT
	_input.host_timestamp += DT
	_input.move_vector = Vector2.ZERO
	_input.mouse_world_pos = _skater.global_position + AHEAD
	_input.mouse_world_pos.y = 0.0
	_input.slap_held = slap
	_input.slap_pressed = slap_press
	_input.shoot_pressed = shoot_press
	_input.shoot_held = shoot or shoot_press
	_controller._process_input(_input, DT)
	_skater._physics_process(DT)


# The puck off the skater, world XZ: it travels with him, and his hips turning
# back out of the stance must not swing it.
func _puck_off_skater() -> Vector2:
	var p: Vector3 = _skater.get_carry_target_global() - _skater.global_position
	return Vector2(p.x, p.z)


# Settled carrying straight up the ice, then pressed and held `wind_ticks` past
# the set-up.
func _wind_up(wind_ticks: int) -> void:
	for i: int in 60:
		_tick(false)
	_tick(true, true)
	while not _controller._aiming.slapper_setup_done:
		_tick(true)
	for i: int in wind_ticks:
		_tick(true)


func _cancel() -> void:
	_tick(true, false, true)


func test_the_fake_costs_longer_the_higher_the_stick_went() -> void:
	_wind_up(10)
	var low_t: float = _controller.slapper_wind_up_t()
	_cancel()
	var short_lock: float = _controller._settle.time_left(_input.host_timestamp)
	before_each()
	_wind_up(100)
	var high_t: float = _controller.slapper_wind_up_t()
	_cancel()
	var long_lock: float = _controller._settle.time_left(_input.host_timestamp)
	assert_almost_eq(short_lock, SlapperRules.recover_time(low_t,
			_controller.slapper_recover_min_s, _controller.slapper_recover_max_s), 0.002)
	assert_almost_eq(high_t, 1.0, 0.001, "wound to the top")
	assert_almost_eq(long_lock, _controller.slapper_recover_max_s, 0.002, "from the top, the whole recovery")
	assert_gt(long_lock, short_lock + 0.2)


func test_a_press_inside_the_recovery_waits_for_the_stick() -> void:
	_wind_up(100)
	_cancel()
	assert_eq(_skater.current_shot_state, State.SKATING_WITH_PUCK, "called off, back to the carry")
	_tick(false, false, true)
	assert_eq(_skater.current_shot_state, State.SKATING_WITH_PUCK, "the wrister waits for the stick")
	var ticks: int = 1
	while _skater.current_shot_state == State.SKATING_WITH_PUCK and ticks < 120:
		_tick(false, false, false, true)
		ticks += 1
	assert_eq(_skater.current_shot_state, State.WRISTER_AIM, "the queued wrister fires once the stick is down")
	assert_almost_eq(ticks * DT, _controller.slapper_recover_max_s, 2.0 * DT,
			"after the whole recovery (%.3f s)" % (ticks * DT))


func test_the_puck_does_not_move_through_the_fake() -> void:
	_wind_up(100)
	var held: Vector2 = _puck_off_skater()
	_cancel()
	var worst: float = held.distance_to(_puck_off_skater())
	var before: Vector2 = _puck_off_skater()
	_tick(false)
	while _skater.is_slapshot_pinning():
		worst = maxf(worst, held.distance_to(_puck_off_skater()))
		before = _puck_off_skater()
		_tick(false)
	assert_lt(worst, 0.005, "the puck stays put while the stick comes down (%.3f m)" % worst)
	var step: float = before.distance_to(_puck_off_skater())
	assert_lt(step, _controller.max_blade_speed * DT * 1.5,
			"the carry takes it back where it lies, moving it no faster than the blade (%.3f m)" % step)


func test_letting_go_before_the_puck_is_set_costs_the_floor() -> void:
	for i: int in 60:
		_tick(false)
	_tick(true, true)
	_tick(false)
	assert_eq(_skater.current_shot_state, State.SKATING_WITH_PUCK)
	assert_almost_eq(_controller._settle.time_left(_input.host_timestamp),
			_controller.slapper_recover_min_s, 0.002, "even an unset slapshot is not free to call off")


func test_a_puckless_wind_up_locks_nothing() -> void:
	_controller.on_puck_released_network()
	_tick(true, true)
	for i: int in 60:
		_tick(true)
	_cancel()
	assert_eq(_skater.current_shot_state, State.SKATING_WITHOUT_PUCK)
	assert_eq(_controller._settle.time_left(_input.host_timestamp), 0.0)
	assert_false(_skater.is_slapshot_pinning())
