extends GutTest

# The top arm stays out of the trunk with the blade pulled in tight. There the
# tracked IK holds the top hand close under its shoulder against the side of the
# ribs (TopHandIK's CLOSE regime), so the fist is drawn out of the jersey
# (SkaterArmRig.torso_push, through Skater.drawn_top_hand) and the arm reaches
# it through a wrist (SkaterArmPoses.place_wrist), its elbow on a pole that does
# not go blind there (TwoBoneIK.blended_pole). Measured against the jersey's
# own rings (SkaterMeshBuilder.torso_clearance) on the live rig, both paths.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const UpperBone = SkaterMeshBuilder.UpperBone
# Cursor offsets from the skater: the carry, then in to the forehand and to the
# feet.
const _AIMS: Array[Vector3] = [
	Vector3(0.6, 0.0, -2.2),
	Vector3(-0.6, 0.0, -0.5),
	Vector3(-0.35, 0.0, -0.15),
	Vector3(0.0, 0.0, -0.35),
	Vector3(0.35, 0.0, -0.2),
]


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


func _posed(aim: Vector3, native: bool) -> Skater:
	var puck: Puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	add_child_autofree(puck)
	puck.global_position = Vector3(30.0, 0.0, 30.0)
	var skater: Skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(skater)
	skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	skater.set_process(false)
	skater.set_physics_process(false)
	skater._arms.native_enabled = native
	var state := StubGameState.new()
	add_child_autofree(state)
	var controller := SkaterController.new()
	add_child_autofree(controller)
	controller.setup(skater, puck, state)
	controller.set_process(false)
	controller.set_physics_process(false)
	puck.set_carrier(skater)
	controller.on_puck_picked_up_network()
	var input := InputState.new()
	for step: Vector3 in [Vector3(0.4, 0.0, -2.0), aim]:
		for _t: int in 50:
			input.delta = DT
			input.host_timestamp += DT
			input.mouse_world_pos = skater.global_position + step
			controller._process_input(input, DT)
			skater._physics_process(DT)
			skater._process(DT)
	return skater


func test_the_top_arm_stays_out_of_the_trunk() -> void:
	for native: bool in [false, true]:
		for aim: Vector3 in _AIMS:
			var skater: Skater = _posed(aim, native)
			var body: Skeleton3D = skater._arms._skeleton
			var to_torso: Transform3D = body.get_bone_global_pose(UpperBone.TORSO).affine_inverse()
			var forearm: Transform3D = body.get_bone_global_pose(UpperBone.TOP_FOREARM)
			var along: Vector3 = -forearm.basis.z.normalized() * forearm.basis.get_scale().z * 0.5
			var elbow: Vector3 = forearm.origin - along
			var wrist: Vector3 = forearm.origin + along
			var fist: Transform3D = body.get_bone_global_pose(UpperBone.TOP_HAND)
			var at: String = "cursor %s%s" % [aim, " (native)" if native else ""]
			var sunk: float = INF
			for k: int in 11:
				sunk = minf(sunk, SkaterMeshBuilder.torso_clearance(
						to_torso * elbow.lerp(wrist, float(k) / 10.0)))
			assert_gt(sunk, 0.0, "the forearm runs outside the jersey: %s" % at)
			assert_gt(SkaterMeshBuilder.torso_clearance(to_torso * fist.origin), 0.0,
					"and the fist's middle is outside it: %s" % at)
			assert_almost_eq(wrist.distance_to(fist.origin), skater.hand_length, 0.001,
					"the forearm ends at the wrist, a hand short of the fist: %s" % at)
			var bend: float = (wrist - elbow).angle_to(-fist.basis.y)
			assert_lt(bend, deg_to_rad(skater.wrist_break_max_deg) + 0.01,
					"and the hand bends off it there within the wrist's range: %s" % at)
