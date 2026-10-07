extends GutTest

# The gait's crouch is computed at render rate, so the skating crouch and its
# stride bob lower the visible body and never the gameplay frames the hands and
# blade hang from — gameplay geometry must not depend on frame rate. The held
# poses (block, faceoff, knockdown) are the exception: their hands are posed in
# a frame that goes down with the body (Skater.set_skating_crouch_drop).

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


# One physics tick, then `frames` render passes splitting it (frame rate).
func _tick(frames: int, block: bool = false) -> void:
	_input.delta = DT
	_input.host_timestamp += DT
	_input.move_vector = Vector2.ZERO if block else Vector2(0.0, -1.0)
	_input.mouse_world_pos = _skater.global_position + Vector3(0.6, 0.0, -3.0)
	_input.block_held = block
	_controller._process_input(_input, DT)
	_skater._physics_process(DT)
	for _f: int in frames:
		_skater._process(DT / frames)


func _hips_height() -> float:
	var body: Skeleton3D = _skater.mesh_root.get_node("BodyRig") as Skeleton3D
	return body.get_bone_pose_position(SkaterBodySkeleton.HIPS_BONE).y


func test_the_skating_crouch_moves_the_body_not_the_frame() -> void:
	var frame_y: float = _skater.upper_body.position.y
	var lowest_hips: float = INF
	var highest_hips: float = -INF
	for i: int in 300:
		_tick(1 + i % 3)  # 120, 240 and 360 fps in turn
		assert_eq(_skater.upper_body.position.y, frame_y, "the gameplay frame holds its height")
		if i > 150:
			lowest_hips = minf(lowest_hips, _hips_height())
			highest_hips = maxf(highest_hips, _hips_height())
	var crouch: float = _controller._skating.crouch_drop
	gut.p("skating: crouch %.3f m, visible hips %.3f..%.3f below the frame" % [
			crouch, frame_y - highest_hips, frame_y - lowest_hips])
	assert_gt(crouch, 0.02, "skating at speed crouches")
	assert_gt(frame_y - highest_hips, 0.02, "and the visible body sits down")
	assert_gt(highest_hips - lowest_hips, 0.002, "riding the stride's bob")


func test_a_held_pose_takes_the_frame_down_with_the_body() -> void:
	for _i: int in 60:
		_tick(1, true)
	var c: SkaterSkatingCoordinator = _controller._skating
	assert_gt(c.crouch_drop, 0.2, "the block drops to one knee")
	assert_almost_eq(c.frame_drop, c.crouch_drop, 0.002, "and the frame goes with it")
	assert_almost_eq(_skater.body_drop_below_frame(), 0.0, 0.002, "the body on its frame")
