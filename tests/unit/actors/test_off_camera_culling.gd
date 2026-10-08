extends GutTest

# A skater the camera cannot see skips the rig's mesh work (Skater.on_camera),
# but nothing gameplay reads may depend on whether he is drawn: a held pose's
# crouch moves the gameplay frame, so the gait keeps computing off camera.

const DT: float = 1.0 / 120.0
const UpperBone = SkaterMeshBuilder.UpperBone


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _camera: Camera3D = null


func before_each() -> void:
	_camera = Camera3D.new()
	_camera.far = 400.0
	add_child_autofree(_camera)
	_camera.global_position = Vector3(0.0, 30.0, 0.0)
	_camera.look_at(Vector3.ZERO, Vector3.FORWARD)
	_camera.current = true


func _rig(pos: Vector3) -> SkaterController:
	var puck: Puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	add_child_autofree(puck)
	puck.global_position = Vector3(300.0, 0.0, 300.0)
	var sk: Skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(sk)
	sk.global_position = Vector3(pos.x, GameRules.FACEOFF_SPAWN_HEIGHT, pos.z)
	sk.set_process(false)
	sk.set_physics_process(false)
	var state := StubGameState.new()
	add_child_autofree(state)
	var c := SkaterController.new()
	add_child_autofree(c)
	c.setup(sk, puck, state)
	c.set_process(false)
	c.set_physics_process(false)
	return c


# Two ticks and a drawn frame, the shape of a 60 fps frame.
func _frame(c: SkaterController, input: InputState, move: Vector2, block: bool) -> void:
	for _t: int in 2:
		input.delta = DT
		input.host_timestamp += DT
		input.move_vector = move
		input.block_held = block
		input.mouse_world_pos = c.skater.global_position + Vector3(0.8, 0.0, -2.5)
		c._process_input(input, DT)
		c.skater._physics_process(DT)
	c.skater._process(2.0 * DT)


func test_without_a_camera_nothing_is_culled() -> void:
	_camera.free()
	var c: SkaterController = _rig(Vector3(500.0, 0.0, 500.0))
	_frame(c, InputState.new(), Vector2(0.0, -1.0), false)
	assert_true(c.skater.on_camera(), "no camera, no culling")


# The same skater on the same ice twice, once in frame and once with the camera
# turned away: skate, then drop into a shot block — the held pose whose crouch
# takes the gameplay frame down with it.
func _track(seen: bool) -> Array[Vector3]:
	if seen:
		_camera.look_at(Vector3.ZERO, Vector3.FORWARD)
	else:
		_camera.look_at(Vector3(0.0, 30.0, 100.0), Vector3.UP)
	var c: SkaterController = _rig(Vector3.ZERO)
	var input := InputState.new()
	var out: Array[Vector3] = []
	for f: int in 90:
		var block: bool = f >= 40
		_frame(c, input, Vector2.ZERO if block else Vector2(0.0, -1.0), block)
		out.append(c.skater.upper_body.position)
		out.append(c.skater.get_blade_position())
	assert_eq(c.skater.on_camera(), seen, "drawn: %s" % seen)
	if seen:
		assert_gt(c.skater._frame_drop, 0.01, "the block took the frame down")
	c.skater.free()
	return out


func test_the_gameplay_frames_do_not_depend_on_being_drawn() -> void:
	var drawn: Array[Vector3] = _track(true)
	var culled: Array[Vector3] = _track(false)
	var worst: float = 0.0
	for i: int in drawn.size():
		worst = maxf(worst, drawn[i].distance_to(culled[i]))
	assert_lt(worst, 1e-5, "UpperBody and the blade sit the same drawn or not (worst %f)" % worst)


func test_an_unseen_skater_skips_the_rig_and_catches_up_when_seen() -> void:
	_camera.look_at(Vector3(0.0, 30.0, 100.0), Vector3.UP)
	var c: SkaterController = _rig(Vector3.ZERO)
	var input := InputState.new()
	var body: Skeleton3D = c.skater.mesh_root.get_node("BodyRig") as Skeleton3D
	_frame(c, input, Vector2(0.0, -1.0), false)
	var arm_before: Transform3D = body.get_bone_pose(UpperBone.TOP_FOREARM)
	for _f: int in 30:
		_frame(c, input, Vector2(0.0, -1.0), false)
	assert_false(c.skater.on_camera(), "out of frame")
	assert_eq(body.get_bone_pose(UpperBone.TOP_FOREARM), arm_before,
			"the arms are not rebuilt off camera")
	# The camera comes round: the first drawn frame rebuilds the arm onto the hand.
	_camera.look_at(c.skater.global_position, Vector3.FORWARD)
	_frame(c, input, Vector2(0.0, -1.0), false)
	assert_true(c.skater.on_camera(), "in frame")
	assert_ne(body.get_bone_pose(UpperBone.TOP_FOREARM), arm_before, "the arm is rebuilt")
	var hand: Vector3 = c.skater.upper_body.transform * c.skater.top_hand.position
	var elbow: Vector3 = body.get_bone_pose(UpperBone.TOP_ELBOW).origin
	assert_lt(absf(elbow.distance_to(hand) - c.skater.forearm_length), 0.01,
			"and the forearm spans elbow to hand again")
