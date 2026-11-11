extends GutTest

# A reconcile compares the host's shot state at the ack with the client's live
# one, a whole unacked window later. A wrister the player called off (RMB in
# WRISTER_AIM) is back to SKATING_WITH_PUCK on the client while the host's ack
# still says WRISTER_AIM; applying that put the client back in aim with the
# button up, and its next tick fired a shot the host never took. The replay
# from the host's state through the same inputs reproduces the cancel, which is
# what tells "late" from "diverged" (ShotStateAuthority).

const State = SkaterStateMachine.State
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const T0: float = 10.0


class StubGameState extends Node:
	func is_host() -> bool:
		return false

	func is_movement_locked() -> bool:
		return false


var _c: LocalController = null


func before_each() -> void:
	var puck: Puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	var skater: Skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(skater)
	skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	skater.set_facing(Vector2(0.0, -1.0))
	skater.set_process(false)
	skater.set_physics_process(false)
	var state := StubGameState.new()
	add_child_autofree(state)
	_c = load("res://Scenes/LocalController.tscn").instantiate() as LocalController
	add_child_autofree(_c)
	_c.setup(skater, puck, state)
	_c.set_process(false)
	_c.set_physics_process(false)
	_c.on_puck_picked_up_network()


func _tick(i: int, shoot_pressed: bool, shoot_held: bool, slap_pressed: bool) -> InputState:
	var input := InputState.new()
	input.delta = DT
	input.host_timestamp = T0 + float(i) * DT
	input.mouse_world_pos = _c.skater.global_position + Vector3(0.0, 0.0, -3.0)
	input.shoot_pressed = shoot_pressed
	input.shoot_held = shoot_held
	input.slap_pressed = slap_pressed
	_c._process_input(input, DT)
	_c._input_history.append(input)
	return input


func test_a_called_off_wrister_stays_called_off() -> void:
	_tick(0, true, true, false)
	assert_eq(_c._sm.get_state(), State.WRISTER_AIM, "the control: aiming")
	for i: int in range(1, 6):
		_tick(i, false, true, false)
	_tick(6, false, true, true)  # RMB: call it off
	for i: int in range(7, 12):
		_tick(i, false, false, false)
	assert_eq(_c._sm.get_state(), State.SKATING_WITH_PUCK, "the control: called off")
	# The host's ack sits mid-aim, far enough off to force the replay.
	var server := SkaterNetworkState.new()
	_c.fill_network_state(server)
	server.position += Vector3(0.0, 0.0, 0.5)
	server.last_processed_host_timestamp = T0 + 3.0 * DT
	server.shot_state = State.WRISTER_AIM
	_c.reconcile(server)
	assert_almost_eq(_c.skater.global_position.z, server.position.z, 0.6, "the reconcile ran")
	assert_eq(_c._sm.get_state(), State.SKATING_WITH_PUCK,
			"the lagged WRISTER_AIM must not re-arm a shot the player called off")


func test_a_real_divergence_still_takes_the_hosts_state() -> void:
	# The control for the rule: no input in the unacked window explains the
	# host's state, so the replay lands on it and the host wins.
	for i: int in 6:
		_tick(i, false, false, false)
	var server := SkaterNetworkState.new()
	_c.fill_network_state(server)
	server.position += Vector3(0.0, 0.0, 0.5)
	server.last_processed_host_timestamp = T0 + 2.0 * DT
	server.shot_state = State.SKATING_WITHOUT_PUCK  # the host took the puck off him
	_c.has_puck = false
	_c.reconcile(server)
	assert_eq(_c._sm.get_state(), State.SKATING_WITHOUT_PUCK)
