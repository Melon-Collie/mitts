extends GutTest

# A reconcile snaps the facing and resets the facing-turn lag, and then has to
# publish the lower body's yaw the way every tick does — the lag plus the
# gait's channels (hip-to-travel alignment, hockey stop, shot coil). Writing the
# lag alone squares the hips under a skater striding off his facing until the
# next tick, and reconciles arrive at broadcast rate.

class StubGameState extends Node:
	func is_host() -> bool:
		return false

	func is_movement_locked() -> bool:
		return false


var _controller: LocalController = null
var _skater: Skater = null


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
	_controller = load("res://Scenes/LocalController.tscn").instantiate() as LocalController
	add_child_autofree(_controller)
	_controller.setup(_skater, puck, state)
	_controller.set_process(false)
	_controller.set_physics_process(false)


func test_a_reconcile_keeps_the_hips_on_the_travel_line() -> void:
	# Striding 40° off the facing: the hips align toward travel.
	_skater.set_facing(Vector2(0.0, -1.0))
	_skater.velocity = Vector3(5.0, 0.0, -6.0)
	_skater.move_intent = Vector2(0.64, -0.77)
	for _i: int in 120:
		_controller._skating.apply(1.0 / 120.0)
	var gait_yaw: float = _controller._skating.travel_align_yaw \
			+ _controller._skating.stop_yaw_offset + _controller._skating.shot_hip_yaw
	assert_gt(absf(gait_yaw), 0.1, "the hips turned toward travel (%.3f rad)" % gait_yaw)
	# A host state far enough off to force the snap.
	var server := SkaterNetworkState.new()
	server.position = _skater.global_position + Vector3(0.5, 0.0, 0.0)
	server.velocity = _skater.velocity
	server.facing = Vector2(0.0, -1.0)
	server.last_processed_host_timestamp = 1.0
	server.shot_state = _skater.current_shot_state
	_controller.reconcile(server)
	assert_almost_eq(_skater.global_position.x, server.position.x, 0.001, "the reconcile snapped")
	assert_almost_eq(_skater.lower_body.rotation.y, gait_yaw, 0.001,
			"the hips keep the gait's yaw through the reconcile")


# The lean is replicated state like stamina: the reconcile adopts the host's
# lean and spring rate at the ack, then replays forward from it.
func test_a_reconcile_adopts_the_hosts_lean() -> void:
	_skater.set_facing(Vector2(0.0, -1.0))
	var server := SkaterNetworkState.new()
	server.position = _skater.global_position + Vector3(0.5, 0.0, 0.0)
	server.velocity = Vector3(0.0, 0.0, -6.0)
	server.facing = Vector2(0.0, -1.0)
	server.last_processed_host_timestamp = 1.0
	server.shot_state = _skater.current_shot_state
	server.balance_tilt = Vector2(0.3, -0.1)
	server.balance_tilt_vel = Vector2(-1.0, 0.5)
	server.torso_lean = Vector2(-0.2, 0.15)
	server.posture_lean = -0.12
	_controller.reconcile(server)
	assert_almost_eq(_skater.balance_tilt().x, 0.3, 1e-6, "the host's lean")
	assert_almost_eq(_skater.balance_tilt().y, -0.1, 1e-6, "the host's lean")
	assert_almost_eq(_controller.balance_tilt_vel.x, -1.0, 1e-6, "and its rate")
	assert_almost_eq(_controller._pose.upper_body_lean, -0.2, 1e-6, "the host's reach lean")
	assert_almost_eq(_controller._pose.upper_body_lean_roll, 0.15, 1e-6, "the host's reach roll")
	assert_almost_eq(_controller._pose.velocity_lean_x, -0.12, 1e-6, "the host's posture")
