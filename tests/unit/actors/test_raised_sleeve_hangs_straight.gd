extends GutTest

# A loose sleeve is cloth hung between the armhole and the elbow. With the arm
# raised its underside is drawn out from the flank, so the armhole's bottom
# stays on the chest it hangs from. Riding the shoulder's bones instead, the
# armhole's bottom and the sleeve's first rings swing up with the arm as a
# ball that the arm steps out of.
#
# Both arms are posed raised on a bare body skeleton, the trunk at its bind, and
# the right sleeve is skinned as drawn.

const _UpperBone = SkaterMeshBuilder.UpperBone
# The raised arm: out to the side and up, the forearm on up from the elbow.
const _UPPER_DIR := Vector3(0.75, 0.62, -0.2)
const _FORE_DIR := Vector3(-0.05, 0.98, -0.2)

var _skeleton: Skeleton3D = null
var _rig: SkaterConnectedRig = null
var _shoulder := Vector3.ZERO


func before_each() -> void:
	_skeleton = SkaterBodySkeleton.new_body_skeleton()
	add_child_autofree(_skeleton)
	var rests: Array[Transform3D] = SkaterConnectedMesh.bind_rests()
	_skeleton.set_bone_pose(_UpperBone.TORSO, rests[SkaterConnectedMesh.Bind.TORSO])
	_rig = SkaterConnectedRig.new()
	_rig.build(_skeleton, null, GearModelRegistry.TUCK_NONE)
	var girth: Vector3 = Vector3.ONE * SkaterConnectedMesh.BIND_SLEEVE_RADIUS_M
	# The top arm's bones are the right arm's, the bottom arm's the left's.
	for arm: Array in [
			[1.0, _UpperBone.TOP_UPPER_ARM, _UpperBone.TOP_FOREARM, _UpperBone.TOP_ELBOW],
			[-1.0, _UpperBone.BOTTOM_UPPER_ARM, _UpperBone.BOTTOM_FOREARM,
			_UpperBone.BOTTOM_ELBOW]]:
		var mirror := Vector3(arm[0], 1.0, 1.0)
		var shoulder: Vector3 = SkaterConnectedMesh.bind_arm(arm[0])[0]
		var elbow: Vector3 = shoulder + (_UPPER_DIR * mirror).normalized() \
				* SkaterConnectedMesh.BIND_ARM_SEGMENT_M
		var hand: Vector3 = elbow + (_FORE_DIR * mirror).normalized() \
				* SkaterConnectedMesh.BIND_ARM_SEGMENT_M
		_skeleton.set_bone_pose(arm[1], SkaterArmPoses.segment_pose(shoulder, elbow, girth))
		_skeleton.set_bone_pose(arm[2], SkaterArmPoses.segment_pose(elbow, hand, girth))
		_skeleton.set_bone_pose(arm[3], SkaterArmPoses.elbow_pose(shoulder, elbow, hand,
				Vector3(arm[0], -0.5, 0.0), Vector3.ONE))
		if arm[0] > 0.0:
			_shoulder = shoulder
	_rig.pose(1)


# The right sleeve's vertices, at their bind and as skinned, skeleton space.
func _right_sleeve() -> Array[PackedVector3Array]:
	var arrays: Array = SkaterConnectedMesh.shared_mesh(GearModelRegistry.TUCK_NONE) \
			.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var zones: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var skin: Skin = SkaterConnectedMesh.shared_skin()
	var xforms: Array[Transform3D] = []
	for i: int in skin.get_bind_count():
		xforms.append(_skeleton.get_bone_global_pose(skin.get_bind_bone(i)) * skin.get_bind_pose(i))
	var zone: int = SkaterConnectedMesh.zone(SkaterConnectedMesh.sleeve_surface(1.0))
	var bind := PackedVector3Array()
	var drawn := PackedVector3Array()
	for v: int in verts.size():
		if roundi(zones[v].x) != zone:
			continue
		var p := Vector3.ZERO
		for k: int in 4:
			if weights[v * 4 + k] > 0.0:
				p += (xforms[bones[v * 4 + k]] * verts[v]) * weights[v * 4 + k]
		bind.append(verts[v])
		drawn.append(p)
	return [bind, drawn]


func test_the_armholes_bottom_stays_on_the_chest() -> void:
	var sleeve: Array[PackedVector3Array] = _right_sleeve()
	var bind: PackedVector3Array = sleeve[0]
	# The armpit: the lowest of the sleeve's vertices beside the shoulder joint,
	# which is the seam's bottom (the sleeve below it is further down the arm).
	var armpit: int = -1
	for v: int in bind.size():
		if bind[v].distance_to(_shoulder) > 0.16:
			continue
		if armpit < 0 or bind[v].y < bind[armpit].y:
			armpit = v
	assert_gt(armpit, -1)
	assert_almost_eq(sleeve[1][armpit], bind[armpit], Vector3.ONE * 0.005,
			"the raised arm leaves the armpit where the chest holds it")

