extends GutTest

# LegIK is a model of the leg rig: an ankle it places must be where the rig's own
# bones put the shin's end for the same joints, and the segment lengths the gait
# hands it must be the ones the build gave the bones.

const LegBone = SkaterMeshBuilder.LegBone

var _skater: Skater = null
var _controller: SkaterController = null


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


func before_each() -> void:
	var puck: Puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	add_child_autofree(puck)
	_skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(_skater)
	_skater.set_process(false)
	_skater.set_physics_process(false)
	var state := StubGameState.new()
	add_child_autofree(state)
	_controller = SkaterController.new()
	add_child_autofree(_controller)
	_controller.setup(_skater, puck, state)


func _apply(height_in: int) -> void:
	var attrs := PlayerAttributes.new(height_in, 201, 1, 1, 1, 1)
	_skater.apply_appearance(attrs)
	_controller.apply_attributes(attrs)


# The shin's end, in the leg pivot's parent frame from the pivot, as the bones
# stand.
func _rig_ankle(leg_bone: int, shin_bone: int, foot_bone: int) -> Vector3:
	var leg: Transform3D = Transform3D(Basis.from_euler(_skater.leg_bone_euler(leg_bone)),
			Vector3.ZERO)
	var shin: Transform3D = Transform3D(Basis.from_euler(_skater.leg_bone_euler(shin_bone)),
			_skater.leg_bone_position(shin_bone))
	return leg * shin * Vector3(0.0, _skater.leg_bone_position(foot_bone).y, 0.0)


func test_the_rig_is_the_solve_model() -> void:
	for side: int in 2:
		var shin_bone: int = LegBone.SHIN_L if side == 0 else LegBone.SHIN_R
		var foot_bone: int = LegBone.FOOT_L if side == 0 else LegBone.FOOT_R
		var shin_pos: Vector3 = _skater.leg_bone_position(shin_bone)
		assert_eq(Vector2(shin_pos.x, shin_pos.z), Vector2.ZERO, "the knee hangs straight below the hip")
		assert_eq(_skater.leg_bone_position(foot_bone).x, 0.0, "the boot is in the leg's plane")
		assert_eq(_skater.leg_bone_euler(shin_bone), Vector3.ZERO, "no authored shin rotation")


func test_an_ankle_the_solve_places_is_where_the_bones_put_it() -> void:
	_apply(76)
	var thigh: float = GaitPose.THIGH_LEN * _controller._skating.leg_scale
	var shin: float = GaitPose.SHIN_LEN * _controller._skating.leg_scale
	assert_almost_eq(-_skater.leg_bone_position(LegBone.SHIN_L).y, thigh, 1e-5,
			"the build's thigh")
	assert_almost_eq(-_skater.leg_bone_position(LegBone.FOOT_L).y, shin, 1e-5,
			"the build's shin")
	var leg := LegIK.Leg.new()
	for pose: Vector4 in [Vector4(0.4, 0.2, -0.3, -0.9), Vector4(-0.3, -0.25, 0.2, -0.2),
			Vector4(0.9, 0.0, 0.1, -1.6)]:
		leg.pitch = pose.x
		leg.yaw = pose.y
		leg.roll = pose.z
		leg.knee = pose.w
		LegIK.place(leg, thigh, shin)
		_skater.set_leg_swing(leg.pitch, leg.roll, leg.knee, leg.pitch, leg.roll, leg.knee,
				leg.yaw, leg.yaw)
		var rig: Vector3 = _rig_ankle(LegBone.LEG_L, LegBone.SHIN_L, LegBone.FOOT_L)
		assert_almost_eq(rig, Vector3(leg.x, leg.y, leg.z), Vector3.ONE * 1e-5, "pose %s" % pose)


func test_the_hip_pivots_and_the_boot_are_where_the_gait_puts_them() -> void:
	_apply(76)
	var scale: float = _controller._skating.leg_scale
	assert_almost_eq(_skater.leg_bone_position(LegBone.LEG_L),
			Vector3(-GaitPose.HIP_HALF_WIDTH, -GaitPose.HIP_DROP * scale, 0.0), Vector3.ONE * 1e-5)
	assert_almost_eq(_skater.leg_bone_position(LegBone.LEG_R),
			Vector3(GaitPose.HIP_HALF_WIDTH, -GaitPose.HIP_DROP * scale, 0.0), Vector3.ONE * 1e-5)
	assert_almost_eq(-_skater.leg_bone_position(LegBone.FOOT_L).z, GaitPose.FOOT_FWD, 1e-5,
			"the build lengthens the leg, not the boot")
	assert_almost_eq(_controller._skating.leg_segment_lengths().z, GaitPose.FOOT_FWD, 1e-6)


# The runner's depth below the ankle the solve aims by, against the rig's own
# boot with the blade laid flat on its length, tipped onto an edge.
func test_the_runner_depth_is_the_rigs() -> void:
	var leg := LegIK.Leg.new()
	var ice := Basis(Vector3.RIGHT, 0.12) * Basis(Vector3.FORWARD, 0.05)
	for pose: Vector4 in [Vector4(0.3, 0.0, 0.0, -0.9), Vector4(-0.2, 0.4, -0.45, -0.4),
			Vector4(0.1, -0.3, 0.3, -1.2)]:
		leg.pitch = pose.x
		leg.yaw = pose.y
		leg.roll = pose.z
		leg.knee = pose.w
		_skater.set_leg_swing(leg.pitch, leg.roll, leg.knee, leg.pitch, leg.roll, leg.knee,
				leg.yaw, leg.yaw)
		_skater.set_ankle_flatten(0.0, 0.0, 1.0, 1.0, ice)
		var hip_frame: Transform3D = Transform3D(ice, Vector3.ZERO) \
				* Transform3D(Basis.from_euler(_skater.leg_bone_euler(LegBone.LEG_L)), Vector3.ZERO) \
				* Transform3D(Basis.from_euler(_skater.leg_bone_euler(LegBone.SHIN_L)),
						_skater.leg_bone_position(LegBone.SHIN_L))
		var ankle: Vector3 = hip_frame * Vector3(0.0, _skater.leg_bone_position(LegBone.FOOT_L).y, 0.0)
		var sk: Skeleton3D = _skater._legs._skeleton
		var foot: Transform3D = hip_frame * sk.get_bone_pose(SkaterLegRig._OFFSET + LegBone.FOOT_L)
		var toe: Vector3 = foot * Vector3(0.0, SkaterMeshBuilder.RUNNER_TOE_Y, SkaterMeshBuilder.BLADE_ICE_Z)
		var heel: Vector3 = foot * Vector3(0.0, SkaterMeshBuilder.RUNNER_HEEL_Y, SkaterMeshBuilder.BLADE_ICE_Z)
		assert_almost_eq(toe.y, heel.y, 1e-4, "the blade lies flat along its length, pose %s" % pose)
		assert_almost_eq(ankle.y - toe.y, GaitPose._runner_depth(leg, ice), 1e-4, "pose %s" % pose)
