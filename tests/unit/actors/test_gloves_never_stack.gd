extends GutTest

# The two gloves never share the shaft. The bottom hand slides up the stick when
# its arm cannot reach its grip, and with the stick held out it used to slide all
# the way onto the top hand, drawing one fist inside the other. It now stops a
# glove's width below it: a carrier's stick comes in until both hands fit
# (TopHandIK.two_hand_reach), and an empty stick reaching past that lets the
# bottom hand go. This drives the live rig through the poses that stacked them
# and measures the drawn fists.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const UpperBone = SkaterMeshBuilder.UpperBone

# [name, puck, aim, move, stance]
const _POSES: Array = [
	["standing, reaching ahead", false, Vector3(0.0, 0.0, -3.0), Vector2.ZERO, false],
	["standing carry, reaching ahead", true, Vector3(0.0, 0.0, -3.0), Vector2.ZERO, false],
	["standing carry, reaching wide", true, Vector3(2.5, 0.0, -1.0), Vector2.ZERO, false],
	["crouched, reaching wide", false, Vector3(2.5, 0.0, -1.0), Vector2.ZERO, true],
	["skating carry, reaching ahead", true, Vector3(0.0, 0.0, -3.0), Vector2(0.0, -1.0), false],
	["skating carry, in tight", true, Vector3(0.5, 0.0, -1.5), Vector2(0.0, -1.0), false],
]


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


func _fists_apart(pose: Array) -> Vector2:
	var puck: Puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	add_child_autofree(puck)
	puck.global_position = Vector3(30.0, 0.0, 30.0)
	var skater: Skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(skater)
	skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	skater.set_process(false)
	skater.set_physics_process(false)
	var state := StubGameState.new()
	add_child_autofree(state)
	var controller := SkaterController.new()
	add_child_autofree(controller)
	controller.setup(skater, puck, state)
	controller.set_process(false)
	controller.set_physics_process(false)
	if bool(pose[1]):
		puck.set_carrier(skater)
		controller.on_puck_picked_up_network()
	var input := InputState.new()
	var closest: float = INF
	for t: int in 200:
		input.delta = DT
		input.host_timestamp += DT
		input.move_vector = pose[3]
		input.stance_held = pose[4]
		input.mouse_world_pos = skater.global_position + (pose[2] as Vector3)
		controller._process_input(input, DT)
		skater._physics_process(DT)
		skater._process(DT)
		# Held, once the stick has come round: while it swings, the bottom hand is
		# placed a tick behind the top one.
		if t >= 140:
			var body: Skeleton3D = skater._arms._skeleton
			closest = minf(closest, body.get_bone_pose(UpperBone.TOP_HAND).origin.distance_to(
					body.get_bone_pose(UpperBone.BOTTOM_HAND).origin))
	return Vector2(closest, controller._ik._glove_spacing())


func test_the_fists_stay_a_glove_apart() -> void:
	for pose: Array in _POSES:
		var apart: Vector2 = _fists_apart(pose)
		gut.p("%s: fists %.3f m apart (a glove is %.3f)" % [pose[0], apart.x, apart.y])
		assert_gt(apart.x, apart.y - 0.005, "%s: one fist is drawn inside the other" % pose[0])
