class_name SkaterConnectedRig
extends RefCounted

# Draws the skater's body (SkaterBodyMesh: the skin, SkaterConnectedMesh, and
# the rigid parts in one surface) and poses the skin's deform bones. It
# reads the bones the other rigs posed this frame and writes only its own: per
# sleeve the girdle, the shoulder's middle, the upper arm, the elbow's middle and
# the forearm, framed on the elbow's hinge (the ELBOW bone's Z) and scaled by the
# live arm against the bind arm; per knee the middle of the bend, half the
# shin's turn on its LEG bone. Called after the rigs' render pass, so it reads
# this frame's poses. A display figure with no Skater (LockerMannequin) drives it
# the same way, through build and pose.

const _UpperBone = SkaterMeshBuilder.UpperBone
const _LegBone = SkaterMeshBuilder.LegBone
# Per arm (top, bottom): upper arm, forearm, elbow.
const _ARM_BONES: Array[Array] = [
	[_UpperBone.TOP_UPPER_ARM, _UpperBone.TOP_FOREARM, _UpperBone.TOP_ELBOW],
	[_UpperBone.BOTTOM_UPPER_ARM, _UpperBone.BOTTOM_FOREARM, _UpperBone.BOTTOM_ELBOW],
]

var _skater: Skater = null
var _skeleton: Skeleton3D = null
var _mesh: MeshInstance3D = null
var _tuck: int = -1
# Whether the gloves drawn are a right top hand and a left bottom one.
var _top_right: bool = true
# SkaterConnectedMesh.bind_rests, and their inverses where a pose is read back
# against them.
var _rests: Array[Transform3D] = []


func setup(skater: Skater) -> void:
	_skater = skater


func build(skeleton: Skeleton3D, body_material: Material, tuck: int) -> void:
	_skeleton = skeleton
	_rests = SkaterConnectedMesh.bind_rests()
	_mesh = MeshInstance3D.new()
	_mesh.name = "Body"
	_mesh.skin = SkaterBodyMesh.shared_skin()
	_mesh.skeleton = NodePath("..")
	_skeleton.add_child(_mesh)
	_mesh.set_instance_shader_parameter(&"flat_from_position", 1.0)
	set_tuck(tuck)
	_mesh.set_surface_override_material(0, body_material)


func set_tuck(tuck: int) -> void:
	if _mesh == null or tuck == _tuck:
		return
	_tuck = tuck
	_remesh()


func _remesh() -> void:
	var material: Material = _mesh.get_surface_override_material(0) \
			if _mesh.mesh != null else null
	_mesh.mesh = SkaterBodyMesh.shared_mesh(_tuck, _top_right)
	if material != null:
		_mesh.set_surface_override_material(0, material)


func update() -> void:
	pose(0 if _skater.shoulder.position.x < 0.0 else 1)


# The deform bones off the bones posed this frame; `top_side` is the side the
# top hand's arm hangs from (0 left, 1 right), which also says which glove is
# which hand's.
func pose(top_side: int) -> void:
	if (top_side == 1) != _top_right and _mesh != null:
		_top_right = top_side == 1
		_remesh()
	for arm: int in 2:
		_pose_sleeve(_ARM_BONES[arm], top_side if arm == 0 else 1 - top_side)
	for side: int in 2:
		_pose_knee(side)


func _pose_sleeve(bones: Array, side: int) -> void:
	var upper: Transform3D = _skeleton.get_bone_pose(bones[0])
	var fore: Transform3D = _skeleton.get_bone_pose(bones[1])
	# Unposed (an arm the IK has not reached yet) its prisms have no length.
	if upper.basis.z.length_squared() < 1e-8 or fore.basis.z.length_squared() < 1e-8:
		return
	var elbow_pose: Transform3D = _skeleton.get_bone_pose(bones[2])
	# The arm bones are prisms from +Z (the near joint) to −Z, scaled by length.
	var shoulder: Vector3 = upper * Vector3(0.0, 0.0, 0.5)
	var elbow: Vector3 = upper * Vector3(0.0, 0.0, -0.5)
	var hand: Vector3 = fore * Vector3(0.0, 0.0, -0.5)
	var hinge: Vector3 = elbow_pose.basis.z
	if hinge.length_squared() < 1e-10:
		hinge = Vector3.RIGHT
	var frames: Array[Transform3D] = SkaterConnectedMesh.sleeve_frames(
			[shoulder, elbow, hand, hinge.normalized()])
	var girth: float = upper.basis.x.length() / SkaterConnectedMesh.BIND_SLEEVE_RADIUS_M
	var upper_len: float = shoulder.distance_to(elbow) / SkaterConnectedMesh.BIND_ARM_SEGMENT_M
	var fore_len: float = elbow.distance_to(hand) / SkaterConnectedMesh.BIND_ARM_SEGMENT_M
	var first: int = SkaterConnectedMesh.Deform.UPPER_L if side == 0 \
			else SkaterConnectedMesh.Deform.UPPER_R
	var bind_upper: int = SkaterConnectedMesh.Bind.UPPER_L if side == 0 \
			else SkaterConnectedMesh.Bind.UPPER_R
	# The upper arm's turn off the chest, as a swing (the bind arm carried by the
	# chest, swung by the shortest arc onto the arm) and a twist about the arm on
	# top of it (what the elbow's hinge rolls the arm by). The shoulder takes half
	# the swing and none of the twist, the upper arm all the swing and half the
	# twist, the elbow and forearm the rest: a sleeve twisted end to end all at one
	# ring pinches shut.
	var chest: Basis = _skeleton.get_bone_global_pose(_UpperBone.TORSO).basis.orthonormalized()
	var rest_upper: Basis = _rests[bind_upper].basis
	var carried: Basis = chest * rest_upper
	var swing := Quaternion(carried.y, frames[0].basis.y) \
			if carried.y.dot(frames[0].basis.y) > -0.999 else Quaternion.IDENTITY
	var swung: Basis = Basis(swing) * carried
	var axis: Vector3 = frames[0].basis.y
	var twist: float = atan2(swung.x.cross(frames[0].basis.x).dot(axis),
			swung.x.dot(frames[0].basis.x))
	var upper_basis: Basis = Basis(axis, twist * 0.5) * swung
	_skeleton.set_bone_pose(SkaterBodySkeleton.deform_bone(first), Transform3D(
			upper_basis.scaled_local(Vector3(girth, upper_len, girth)), frames[0].origin))
	_skeleton.set_bone_pose(SkaterBodySkeleton.deform_bone(first + 1), Transform3D(
			frames[1].basis.scaled_local(Vector3.ONE * girth), frames[1].origin))
	_skeleton.set_bone_pose(SkaterBodySkeleton.deform_bone(first + 2), Transform3D(
			frames[2].basis.scaled_local(Vector3(girth, fore_len, girth)), frames[2].origin))
	# The shoulder's middle and its girdle: each the chest's carry of the bind
	# shoulder moved toward the arm's root and turned by its share of the swing.
	var chest_carry: Transform3D = _skeleton.get_bone_global_pose(_UpperBone.TORSO) \
			* _rests[SkaterConnectedMesh.Bind.TORSO].affine_inverse()
	var joint: Vector3 = chest_carry * _rests[bind_upper].origin
	var rise: float = frames[0].basis.y.dot(chest.y) - rest_upper.y.y
	var span: Vector2 = SkaterConnectedMesh.GIRDLE_RISE_SPAN
	var girdle_share: float = lerpf(SkaterConnectedMesh.GIRDLE_SWING_SHARE.x,
			SkaterConnectedMesh.GIRDLE_SWING_SHARE.y,
			smoothstep(span.x, span.y, rise))
	for bone: Array in [
			[SkaterConnectedMesh.Deform.SHOULDER_L, SkaterConnectedMesh.SHOULDER_SWING_SHARE],
			[SkaterConnectedMesh.Deform.GIRDLE_L, girdle_share]]:
		var share: float = bone[1]
		var turn := Basis(Quaternion.IDENTITY.slerp(swing, share))
		_skeleton.set_bone_pose(SkaterBodySkeleton.deform_bone(int(bone[0]) + side),
				Transform3D((turn * chest).scaled(Vector3.ONE * lerpf(1.0, girth, share)),
				joint.lerp(frames[0].origin, share)))


func _pose_knee(side: int) -> void:
	var off: int = SkaterBodySkeleton.LEG_BONE_OFFSET
	var shin: Transform3D = _skeleton.get_bone_pose(
			off + (_LegBone.SHIN_L if side == 0 else _LegBone.SHIN_R))
	var bulk: Vector3 = _skeleton.get_bone_pose(
			off + (_LegBone.THIGH_L if side == 0 else _LegBone.THIGH_R)).basis.get_scale()
	var half: Quaternion = Quaternion.IDENTITY.slerp(shin.basis.get_rotation_quaternion(), 0.5)
	_skeleton.set_bone_pose(SkaterBodySkeleton.deform_bone(
			SkaterConnectedMesh.Deform.KNEE_L if side == 0 else SkaterConnectedMesh.Deform.KNEE_R),
			Transform3D(Basis(half).scaled_local(bulk), shin.origin))
