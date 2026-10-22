extends GutTest

# The stick and the gloves holding it are drawn at the instant the engine draws
# the markers and the frame they hang from, at any frame rate. SceneTreeFTI draws an interpolated node between its transform at
# the start of the latest tick and its transform now; the Blade marker moves on
# the tick, so it is drawn between ticks, and the blade mesh hangs from it. A
# shaft written at render rate and left interpolated was drawn from the pose the
# previous FRAME wrote, so in a frame that ran two ticks it trailed the blade by
# a tick of the stick's travel (2-3 cm through a dangle at 60-90 fps). The
# skeleton is UpperBody's sibling, so a glove placed through the frame the tick
# left sat off the shaft by a tick of the trunk's turn (1.5 cm turning hard).
#
# Run on the real main loop at 60 fps, where every frame runs two ticks. The
# drawn pose is rebuilt here from that rule: each node's transform at the start
# of every tick (the physics_frame signal fires after the engine's pump), lerped
# to its transform after the skater's render pass by the frame's fraction.

const DT: float = 1.0 / 120.0
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


# Dangles the puck across the body, skating and sweeping the cursor round so the
# trunk turns, on the real physics tick.
class Driver extends Node:
	var c: SkaterController
	var input := InputState.new()
	var ticks: int = 0

	func _physics_process(_d: float) -> void:
		var sk: Skater = c.skater
		ticks += 1
		input.delta = DT
		input.host_timestamp += DT
		var t: float = ticks * DT
		input.move_vector = Vector2(0.0, 1.0) if t > 1.0 else Vector2.ZERO
		input.mouse_world_pos = sk.global_position \
				+ Vector3(0.8 * sin(t * TAU * 1.5), 0.0, 1.3).rotated(Vector3.UP, 1.2 * sin(t * TAU * 0.4))
		input.mouse_world_pos.y = 0.0
		c._process_input(input, DT)
		sk._physics_process(DT)


# Runs after the skater's render pass and measures, in UpperBody's frame as
# drawn, how far the drawn hosel tip and the top glove sit off the drawn shaft.
class Probe extends Node:
	var sk: Skater
	var drv: Driver
	var blade_prev: Transform3D
	var mesh_prev: Transform3D
	var shaft_prev: Transform3D
	var frame_prev: Transform3D
	var skeleton: Skeleton3D
	var ticks_at_last_frame: int = 0
	var multi_tick_frames: int = 0
	var worst_tip: float = 0.0
	var worst_glove: float = 0.0

	func on_tick_start() -> void:
		blade_prev = sk.blade.transform
		mesh_prev = sk._blade_mesh_instance.transform
		shaft_prev = sk.stick_mesh.transform
		frame_prev = sk.upper_body.transform

	func _drawn(node: Node3D, prev: Transform3D, f: float) -> Transform3D:
		if node.is_physics_interpolated_and_enabled():
			return prev.interpolate_with(node.transform, f)
		return node.transform

	func _process(_d: float) -> void:
		var ran: int = drv.ticks - ticks_at_last_frame
		ticks_at_last_frame = drv.ticks
		if drv.ticks < 60:
			return
		if ran >= 2:
			multi_tick_frames += 1
		var f: float = Engine.get_physics_interpolation_fraction()
		var lie: float = deg_to_rad(sk.blade_lie_deg)
		var hosel_tip := Vector3(0.0, sin(lie), cos(lie)) * sk.blade_hosel_length
		var tip: Vector3 = _drawn(sk.blade, blade_prev, f) \
				* _drawn(sk._blade_mesh_instance, mesh_prev, f) * hosel_tip
		var shaft: Transform3D = _drawn(sk.stick_mesh, shaft_prev, f)
		var axis: Vector3 = shaft.basis.z.normalized()
		worst_tip = maxf(worst_tip, _off_line(tip - shaft.origin, axis))
		# The glove is a bone: skeleton space is MeshRoot's, where UpperBody is
		# drawn interpolated.
		var frame: Transform3D = _drawn(sk.upper_body, frame_prev, f)
		var glove_s: Vector3 = skeleton.transform \
				* skeleton.get_bone_global_pose(SkaterMeshBuilder.UpperBone.TOP_HAND).origin
		var glove: Vector3 = frame.affine_inverse() * glove_s
		worst_glove = maxf(worst_glove, _off_line(glove - shaft.origin, axis))

	func _off_line(rel: Vector3, axis: Vector3) -> float:
		return (rel - axis * rel.dot(axis)).length()


func test_the_blade_and_the_glove_stay_on_the_shaft_at_60_fps() -> void:
	assert_true(get_tree().physics_interpolation, "the project draws with physics interpolation")
	var saved_fps: int = Engine.max_fps
	Engine.max_fps = 60
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	var sk: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(sk)
	sk.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	sk.set_physics_process(false)
	var gs := StubGameState.new()
	add_child_autofree(gs)
	var c := SkaterController.new()
	add_child_autofree(c)
	c.setup(sk, puck, gs)
	c.set_physics_process(false)
	c.set_process(false)
	c.apply_attributes(PlayerAttributes.neutral())
	puck.set_carrier(sk)
	c.on_puck_picked_up_network()
	var drv := Driver.new()
	drv.c = c
	add_child_autofree(drv)
	var probe := Probe.new()
	probe.sk = sk
	probe.drv = drv
	probe.skeleton = sk.mesh_root.get_node("BodyRig") as Skeleton3D
	probe.process_priority = 1000
	add_child_autofree(probe)
	get_tree().physics_frame.connect(probe.on_tick_start)
	await wait_seconds(2.0)
	get_tree().physics_frame.disconnect(probe.on_tick_start)
	Engine.max_fps = saved_fps
	assert_gt(probe.multi_tick_frames, 20,
			"frames ran two ticks (%d of them)" % probe.multi_tick_frames)
	assert_lt(probe.worst_tip, 0.001,
			"the hosel tip stays on the drawn shaft (worst %.4f m off it)" % probe.worst_tip)
	assert_lt(probe.worst_glove, 0.001,
			"the top glove stays on the drawn shaft (worst %.4f m off it)" % probe.worst_glove)
