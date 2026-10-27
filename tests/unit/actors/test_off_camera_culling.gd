extends GutTest

# A skater the camera cannot see skips the rig's mesh work (Skater.on_camera),
# but nothing gameplay reads may depend on whether he is drawn: a held pose's
# crouch moves the gameplay frame, so the gait keeps computing off camera.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const UpperBone = SkaterMeshBuilder.UpperBone
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")


class StubGameState extends Node:
	var host: bool = true

	func is_host() -> bool:
		return host

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
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	puck.global_position = Vector3(300.0, 0.0, 300.0)
	var sk: Skater = SKATER_SCENE.instantiate() as Skater
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
	var hand: Vector3 = c.skater.upper_body.transform * c.skater.drawn_top_hand()
	var elbow: Vector3 = body.get_bone_pose(UpperBone.TOP_ELBOW).origin
	assert_lt(absf(elbow.distance_to(hand) - c.skater.forearm_length), 0.01,
			"and the forearm spans elbow to hand again")



# A frame the animation LOD thins is off camera to the rig, so it inherits the
# same guarantee: thinning changes when the mesh is posed, never the gameplay.
func _track_thinned() -> Array[Vector3]:
	_camera.look_at(Vector3.ZERO, Vector3.FORWARD)
	var c: SkaterController = _rig(Vector3.ZERO)
	var input := InputState.new()
	var out: Array[Vector3] = []
	var skipped: int = 0
	for f: int in 90:
		var block: bool = f >= 40
		_frame(c, input, Vector2.ZERO if block else Vector2(0.0, -1.0), block)
		if not c.skater.on_camera():
			skipped += 1
		out.append(c.skater.upper_body.position)
		out.append(c.skater.get_blade_position())
	assert_gt(skipped, 30, "the far skater was thinned (%d of 90 frames skipped)" % skipped)
	c.skater.free()
	return out


func test_thinning_the_animation_does_not_move_the_gameplay_frames() -> void:
	var saved: int = SkaterAnimationLod.detail
	SkaterAnimationLod.detail = SkaterAnimationLod.DETAIL_FULL
	var full: Array[Vector3] = _track(true)
	SkaterAnimationLod.detail = SkaterAnimationLod.DETAIL_LOW
	var thinned: Array[Vector3] = _track_thinned()
	SkaterAnimationLod.detail = saved
	var worst: float = 0.0
	for i: int in full.size():
		worst = maxf(worst, full[i].distance_to(thinned[i]))
	assert_lt(worst, 1e-5, "UpperBody and the blade sit the same at any detail (worst %f)" % worst)


# The blade mesh hangs from the Blade marker, which the tick moves on a thinned
# frame too; the shaft waits for the next pass, so the blade has to wait with it.
# Measured on a stick swept side to side, from the first frame the stick is
# drawn: the hosel tip's distance off the drawn shaft's line.
func test_a_thinned_frame_keeps_the_blade_on_the_shaft() -> void:
	var saved: int = SkaterAnimationLod.detail
	SkaterAnimationLod.detail = SkaterAnimationLod.DETAIL_LOW
	_camera.look_at(Vector3.ZERO, Vector3.FORWARD)
	var c: SkaterController = _rig(Vector3.ZERO)
	var sk: Skater = c.skater
	var lie: float = deg_to_rad(sk.blade_lie_deg)
	var hosel_tip := Vector3(0.0, sin(lie), cos(lie)) * sk.blade_hosel_length
	var input := InputState.new()
	var skipped: int = 0
	var drawn: bool = false
	var worst: float = 0.0
	for _f: int in 60:
		for _t: int in 2:
			input.delta = DT
			input.host_timestamp += DT
			input.mouse_world_pos = sk.global_position \
					+ Vector3(0.8 * sin(input.host_timestamp * TAU * 1.5), 0.0, -1.4)
			c._process_input(input, DT)
			sk._physics_process(DT)
		sk._process(2.0 * DT)
		if not sk.on_camera():
			skipped += 1
		drawn = drawn or sk.on_camera()
		if not drawn:
			continue
		var tip: Vector3 = sk._blade_mesh_instance.global_transform * hosel_tip
		var shaft: Transform3D = sk.stick_mesh.global_transform
		var axis: Vector3 = shaft.basis.z.normalized()
		var rel: Vector3 = tip - shaft.origin
		worst = maxf(worst, (rel - axis * rel.dot(axis)).length())
	SkaterAnimationLod.detail = saved
	assert_gt(skipped, 20, "the far skater was thinned (%d of 60 frames skipped)" % skipped)
	assert_lt(worst, 0.001, "the hosel tip stays on the shaft (worst %.4f m off it)" % worst)


# A remote body is posed by RemoteController's own render hook, on the host (a
# client's real inputs) and on a client (an interpolated body) alike. Its off
# hand is mesh like everyone else's, so off camera it waits too.
func _remote(host: bool) -> RemoteController:
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	puck.global_position = Vector3(300.0, 0.0, 300.0)
	var sk: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(sk)
	sk.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	sk.set_process(false)
	sk.set_physics_process(false)
	var state := StubGameState.new()
	state.host = host
	add_child_autofree(state)
	var rc := RemoteController.new()
	add_child_autofree(rc)
	rc.setup(sk, puck, state)
	rc.set_process(false)
	rc.set_physics_process(false)
	return rc


func _off_hand_after_blade_moves(rc: RemoteController) -> Vector3:
	var sk: Skater = rc.skater
	sk.set_blade_position(sk.get_blade_position() + Vector3(0.4, 0.0, -0.3))
	sk._process(2.0 * DT)
	return sk.bottom_hand.position


func test_a_remote_off_hand_waits_off_camera() -> void:
	for host: bool in [false, true]:
		_camera.look_at(Vector3(0.0, 30.0, 100.0), Vector3.UP)
		var rc: RemoteController = _remote(host)
		rc.skater._process(2.0 * DT)
		var before: Vector3 = rc.skater.bottom_hand.position
		assert_eq(_off_hand_after_blade_moves(rc), before,
				"off camera the off hand is not re-solved (host %s)" % host)
		_camera.look_at(Vector3.ZERO, Vector3.FORWARD)
		assert_ne(_off_hand_after_blade_moves(rc), before,
				"in frame it follows the blade again (host %s)" % host)
