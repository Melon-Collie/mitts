extends GutTest

# A glove on the stick holds it palm toward the body (SkaterArmRig turns it on
# the shaft): with the stick held upright in tight and the elbow out, that is
# the thumb up by the knob; carried out in front, the palm in all the same.
# Driven through the real controller and render pass.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const UpperBone = SkaterMeshBuilder.UpperBone


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _skater: Skater
var _controller: SkaterController


func _rig(left_handed: bool) -> void:
	var puck: Puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	add_child_autofree(puck)
	puck.global_position = Vector3(30.0, 0.0, 30.0)
	_skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	_skater.is_left_handed = left_handed
	add_child_autofree(_skater)
	_skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	_skater.set_process(false)
	_skater.set_physics_process(false)
	var state := StubGameState.new()
	add_child_autofree(state)
	_controller = SkaterController.new()
	add_child_autofree(_controller)
	_controller.setup(_skater, puck, state)
	_controller.set_process(false)
	_controller.set_physics_process(false)


func _hold(aim: Vector3, ticks: int) -> void:
	var input := InputState.new()
	for t: int in ticks:
		input.delta = DT
		input.host_timestamp += DT
		input.mouse_world_pos = _skater.global_position + aim
		_controller._process_input(input, DT)
		_skater._physics_process(DT)
		_skater._process(DT)


# How square each glove's palm is to the body (1 facing it), top then bottom.
func _palms() -> Array[float]:
	var body: Skeleton3D = _skater._arms._skeleton
	var trunk: Transform3D = body.get_bone_global_pose(UpperBone.TORSO)
	var up: Vector3 = trunk.basis.y.normalized()
	var right_on_top: bool = _skater.shoulder.position.x > 0.0
	var out: Array[float] = []
	for arm: int in 2:
		var glove: Transform3D = body.get_bone_pose(UpperBone.TOP_HAND if arm == 0
				else UpperBone.BOTTOM_HAND)
		var right: bool = right_on_top == (arm == 0)
		var palm: Vector3 = glove.basis.z.normalized() * (-1.0 if right else 1.0)
		var to_body: Vector3 = trunk.origin - glove.origin
		to_body -= up * to_body.dot(up)
		out.append(palm.dot(to_body.normalized()))
	return out


func test_the_palms_face_the_body() -> void:
	for left_handed: bool in [true, false]:
		_rig(left_handed)
		var side: float = 1.0 if left_handed else -1.0
		for aim: Vector3 in [Vector3(0.4 * side, 0.0, -2.0), Vector3(0.2 * side, 0.0, -0.45)]:
			_hold(aim, 60)
			var palms: Array[float] = _palms()
			var label: String = "%s, aim %s" % ["lefty" if left_handed else "righty", aim]
			assert_gt(palms[0], 0.0, "%s: the top palm faces the body" % label)
			assert_gt(palms[1], 0.0, "%s: the bottom palm faces the body" % label)


func test_held_upright_the_top_thumb_is_up() -> void:
	_rig(true)
	_hold(Vector3(0.2, 0.0, -0.45), 60)
	var glove: Transform3D = _skater._arms._skeleton.get_bone_pose(UpperBone.TOP_HAND)
	assert_gt(glove.basis.x.normalized().y, 0.5, "the index points up the shaft, to the knob")
