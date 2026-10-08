extends GutTest

# The slapper wind-up keeps the posture under its coil. Its hands are authored,
# so it takes no reach lean — but the skating lean and a stagger's reel carry on
# through the charge as in every other state, and a remote machine applying the
# lean off the wire lands on the same torso as the shooter's own.

const State = SkaterStateMachine.State
const DT: float = 1.0 / 120.0


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _skater: Skater = null
var _controller: SkaterController = null
var _input := InputState.new()


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


# `press` starts a charge on the first tick; `slap` holds it.
func _tick(count: int, slap: bool, press: bool = false) -> void:
	for i: int in count:
		_input.delta = DT
		_input.host_timestamp += DT
		_input.move_vector = Vector2(0.0, -1.0)
		_input.mouse_world_pos = _skater.global_position + Vector3(0.6, 0.0, -3.0)
		_input.slap_held = slap
		_input.slap_pressed = press and i == 0
		_controller._process_input(_input, DT)
		_skater._physics_process(DT)


func _charging() -> bool:
	var s: int = _skater.current_shot_state
	return s == State.SLAPPER_CHARGE_WITHOUT_PUCK or s == State.SLAPPER_CHARGE_WITH_PUCK


func test_the_wind_up_keeps_the_skating_lean() -> void:
	_tick(150, false)
	_tick(1, true, true)
	assert_true(_charging(), "the slapper wind-up started")
	_tick(60, true)
	assert_true(_charging(), "still winding up")
	var lean: float = _controller._pose.velocity_lean_x
	assert_gt(absf(lean), 0.03, "skating at speed carries a posture lean (%.3f)" % lean)
	assert_almost_eq(_skater.upper_body.rotation.x, lean, 0.002,
			"the wind-up's torso pitch is the skating lean, with no reach lean on it")


func test_a_stagger_reels_through_the_wind_up() -> void:
	_tick(150, false)
	_tick(30, true, true)
	var before: float = _skater.upper_body.rotation.x
	_controller.stagger_recoil_dir = Vector2(0.0, 1.0)  # shoved backward
	_controller.stagger_timer = _controller.stagger_max_seconds
	_tick(2, true)
	assert_true(_charging(), "still winding up")
	assert_gt(_skater.upper_body.rotation.x, before + 0.05,
			"the torso reels back off the hit during the charge")


func test_a_remote_sees_the_wind_up_the_shooter_sees() -> void:
	_tick(150, false)
	_tick(60, true, true)
	assert_true(_charging(), "still winding up")
	var local := Vector2(_skater.upper_body.rotation.x, _skater.upper_body.rotation.z)
	var wire := SkaterNetworkState.new()
	_controller.fill_network_state(wire)
	var received: SkaterNetworkState = WorldStateCodec._decode_skater_quantized(
			WorldStateCodec._encode_skater_quantized(wire))
	_controller._pose.apply_wire_lean(SkaterNetworkState.new())  # a receiver's blank pose
	_controller._pose.apply_wire_lean(received)
	var remote := Vector2(_skater.upper_body.rotation.x, _skater.upper_body.rotation.z)
	assert_almost_eq(remote.x, local.x, 0.001, "same torso pitch")
	assert_almost_eq(remote.y, local.y, 0.001, "same torso roll")
