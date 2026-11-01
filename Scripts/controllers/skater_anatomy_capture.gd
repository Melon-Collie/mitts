class_name SkaterAnatomyCapture
extends RefCounted

# A built skater read into the numbers ArmAnatomy measures him with
# (ArmAnatomyBody), and his trunk and hips as the body skeleton has them now.
# Read once, standing at rest after a render pass, with the stick empty: the
# shoulders are read off the trunk the arms are drawn from, which a carry's
# fold would tip.

# How far down the shaft the bottom hand can hold, of the stick's length: a
# body reaches that far; how far a player does is technique's to say.
const SPACING_MAX_SHARE: float = 0.7
# The carry the top fist's square roll is read at (ArmAnatomyBody
# .top_roll_square), in the trunk's frame off the top shoulder: the hand low in
# front of its hip, the blade ahead on the forehand side.
const SQUARE_HAND_OFF_SHOULDER := Vector3(-0.08, -0.45, -0.3)
const SQUARE_HEEL_AHEAD_M: float = 1.0


static func capture(controller: SkaterController) -> ArmAnatomyBody:
	var skater: Skater = controller.skater
	var body := ArmAnatomyBody.new()
	var skel: Skeleton3D = skeleton(skater)
	var spine: Transform3D = skel.get_bone_global_pose(SkaterBodySkeleton.SPINE_BONE)
	var to_spine: Transform3D = spine.affine_inverse() * skater.drawn_upper_body()
	body.top_shoulder = to_spine * skater.visible_shoulder(skater.shoulder.position)
	body.bottom_shoulder = to_spine * skater.visible_shoulder(skater.bottom_shoulder.position)
	body.upper_len = skater.upper_arm_length
	body.fore_len = skater.forearm_length
	body.working_extension = skater.arm_working_extension
	body.girdle_slack = skater.shoulder_reach_m
	body.torso_in_spine = spine.affine_inverse() \
			* skel.get_bone_global_pose(SkaterMeshBuilder.UpperBone.TORSO)
	body.torso_profile = SkaterMeshBuilder.TORSO_PROFILE
	body.torso_sway = SkaterMeshBuilder.TORSO_REAR_SWAY
	body.torso_xz_scale = SkaterMeshBuilder.TORSO_XZ_SCALE
	body.sleeve_radius = SkaterMeshBuilder.SLEEVE_RADIUS_M
	body.sleeve_contact = SkaterArmPoses.STEER_CONTACT_M
	body.hand_radius = skater.arm_ball_radius(SkaterMeshBuilder.UpperBone.TOP_HAND)
	body.stick_length = controller._ik.solve_stick_length()
	body.spacing_min = controller._ik._glove_spacing()
	body.spacing_max = body.stick_length * SPACING_MAX_SHARE
	body.top_grip_angle = deg_to_rad(skater.top_grip_angle_deg)
	body.bottom_grip_angle = deg_to_rad(skater.bottom_grip_angle_deg)
	body.knob_extend = SkaterStickRig.SHAFT_BUTT_EXTEND_M
	body.blade_length = skater.blade_length
	body.blade_lie = deg_to_rad(skater.blade_lie_deg)
	body.left_shot = skater.is_left_handed
	body.top_roll_square = _square_roll(body, pivot_height(skater) - controller.blade_height)
	return body


static func skeleton(skater: Skater) -> Skeleton3D:
	for child: Node in skater.mesh_root.get_children():
		if child is Skeleton3D:
			return child as Skeleton3D
	return null


# The hips' frame in the world: at the trunk's pivot, turned to where the hips
# point (as SkaterSpineRig places them, the trunk's twist off the facing within
# its limit), level.
static func hips_frame(skater: Skater) -> Transform3D:
	var skel: Skeleton3D = skeleton(skater)
	var spine: Transform3D = skel.get_bone_global_pose(SkaterBodySkeleton.SPINE_BONE)
	var hip: Vector3 = skater.drawn_lower_body_rotation()
	var trunk: Vector3 = skater.drawn_upper_body_rotation()
	var twist: float = clampf(angle_difference(hip.y, trunk.y), -SkaterSpineRig.TWIST_LIMIT,
			SkaterSpineRig.TWIST_LIMIT)
	var world: Transform3D = skel.global_transform * Transform3D(
			Basis(Vector3.UP, trunk.y - twist), spine.origin)
	return Transform3D(Basis(Vector3.UP, world.basis.get_euler().y), world.origin)


# The trunk as the skater holds it now (ArmAnatomySearch.TrunkState), its twist
# left to the search: the tilt, fold, lean and side bend off the skater and
# the two frames as SkaterSpineRig reads them, and the chest's own turn off the
# torso bone against where `body` has it at rest.
static func trunk_state(skater: Skater, body: ArmAnatomyBody) -> ArmAnatomySearch.TrunkState:
	var trunk := ArmAnatomySearch.TrunkState.new()
	var rig_fold: float = skater.trunk_fold()
	var frame: Vector3 = skater.drawn_upper_body_rotation()
	trunk.fold = -rig_fold
	trunk.pitch = -(frame.x - rig_fold)
	trunk.side = -frame.z
	var skel: Skeleton3D = skeleton(skater)
	# The trunk's lean as SkaterSpineRig lays it, in the skeleton's frame, then the
	# hips'.
	var lean: Vector2 = skater.trunk_tilt()
	var tilt3: Vector3 = skater.global_transform.basis.inverse() * Vector3(lean.x, 0.0, lean.y)
	if tilt3.length() > 1e-4:
		var yaw := Basis(Vector3.UP, (skel.global_transform.basis.inverse()
				* hips_frame(skater).basis).get_euler().y)
		trunk.tilt = yaw.inverse() * Basis(Vector3.UP.cross(tilt3.normalized()),
				tilt3.length()) * yaw
	var spine: Transform3D = skel.get_bone_global_pose(SkaterBodySkeleton.SPINE_BONE)
	var torso: Transform3D = skel.get_bone_global_pose(SkaterMeshBuilder.UpperBone.TORSO)
	trunk.chest = (spine.affine_inverse() * torso * body.torso_in_spine.affine_inverse()) \
			.basis.orthonormalized()
	return trunk


# The trunk's pivot above the ice (m).
static func pivot_height(skater: Skater) -> float:
	return hips_frame(skater).origin.y


# The top fist's roll on the shaft at the reference carry, the hand free to roll
# to where its forearm holds it at rest: the roll the face is square at.
static func _square_roll(body: ArmAnatomyBody, pivot_above_blade: float) -> float:
	var setup := ArmAnatomy.ArmSetup.new()
	setup.body = body
	setup.side = signf(body.top_shoulder.x)
	setup.shoulder = body.top_shoulder
	setup.torso = body.torso_in_spine
	setup.hand = body.top_shoulder + Vector3(SQUARE_HAND_OFF_SHOULDER.x * setup.side,
			SQUARE_HAND_OFF_SHOULDER.y, SQUARE_HAND_OFF_SHOULDER.z)
	var heel := Vector3(body.bottom_shoulder.x, -pivot_above_blade, -SQUARE_HEEL_AHEAD_M)
	setup.shaft = (heel - setup.hand).normalized()
	setup.grip_angle = body.top_grip_angle
	setup.roll_free = true
	var pose := ArmAnatomy.ArmPose.new()
	ArmAnatomy.solve(setup, pose, ArmAnatomy.ArmPose.new())
	return pose.roll
