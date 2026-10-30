extends GutTest

# How far each drawn arm runs into the drawn trunk, carrying the puck with the
# blade swept round the body at several reaches, a few ticks after each move
# (before the body has turned onto it). Prints a table; asserts nothing.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const UpperBone = SkaterMeshBuilder.UpperBone


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _skater: Skater = null
var _controller: SkaterController = null


func _rig() -> void:
	var puck: Puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	add_child_autofree(puck)
	puck.global_position = Vector3(30.0, 0.0, 30.0)
	_skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
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
	var attrs := PlayerAttributes.new(73, 201)
	_skater.apply_appearance(attrs)
	_controller.apply_attributes(attrs)


func _hold(aim: Vector3, ticks: int) -> void:
	var input := InputState.new()
	for t: int in ticks:
		input.delta = DT
		input.host_timestamp += DT
		input.mouse_world_pos = _skater.global_position + aim
		_controller._process_input(input, DT)
		_skater._physics_process(DT)
		_skater._process(DT)


# How far one drawn arm runs into the trunk, in centimetres at the chest's
# depth, by the trunk the elbow solve keeps it out of (Skater.arm_trunk_keep_out,
# TwoBoneIK._arm_intrusion): 0 when its sleeve's middle stays outside.
func _arm_depth(upper: int, forearm: int) -> float:
	var body: Skeleton3D = _skater._arms._skeleton
	var to_trunk: Transform3D = body.get_bone_global_pose(UpperBone.TORSO).affine_inverse()
	var up: Transform3D = body.get_bone_pose(upper)
	var fore: Transform3D = body.get_bone_pose(forearm)
	var elbow_end: float = signf((fore.origin - up.origin).dot(up.basis.z))
	var root: Vector3 = up.origin - up.basis.z * 0.5 * elbow_end
	var elbow: Vector3 = up.origin + up.basis.z * 0.5 * elbow_end
	var hand: Vector3 = fore.origin * 2.0 - elbow
	return TwoBoneIK._arm_intrusion(to_trunk * root, to_trunk * elbow, to_trunk * hand,
			_skater.arm_trunk_keep_out, _skater.arm_root_share) \
			* _skater.arm_trunk_keep_out.y * 100.0


func test_print_arm_depths_round_the_body() -> void:
	_rig()
	_hold(Vector3(0.4, 0.0, -2.0), 60)
	var lines: PackedStringArray = ["bearing  reach   top cm  bottom cm"]
	for reach: float in [0.35, 0.6, 1.0, 1.6, 2.4]:
		for deg: float in [-150.0, -90.0, -30.0, 0.0, 30.0, 90.0]:
			var a: float = deg_to_rad(deg)
			# Held for a few ticks only: the body has not turned onto it yet.
			_hold(Vector3(0.0, 0.0, -1.5), 60)
			var fwd: Vector3 = -_skater.global_transform.basis.z
			var side: Vector3 = _skater.global_transform.basis.x
			_hold((side * sin(a) + fwd * cos(a)) * reach, 8)
			lines.append("%7.0f  %5.2f  %7.1f  %9.1f" % [deg, reach,
					_arm_depth(UpperBone.TOP_UPPER_ARM, UpperBone.TOP_FOREARM),
					_arm_depth(UpperBone.BOTTOM_UPPER_ARM, UpperBone.BOTTOM_FOREARM)])
	print("\n".join(lines))
	assert_true(true)
