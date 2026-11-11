extends GutTest

# The neck stands in the collar. Its foot rides a deform bone the torso carries
# (SkaterConnectedMesh.Deform.NECK_FOOT) and only its top the helmet, so a head
# carried off the trunk's line (the trunk folded under a level head, a nod, a
# lean taken back) bends the neck over the collar. Rigid to the helmet, its
# column swings out through the back of the collar and hides it.

const _UpperBone = SkaterMeshBuilder.UpperBone
const _SCENE: String = "res://Scenes/Skater.tscn"
# A head carried back off the trunk and tipped, as a folded trunk under a
# level head carries it, and turned to look across the body.
const _CARRY := Vector3(0.01, -0.005, 0.05)
const _TIP_RAD: float = 0.25
const _TURN_RAD: float = 1.0

var _skeleton: Skeleton3D = null
var _rig: SkaterConnectedRig = null


func before_each() -> void:
	_skeleton = SkaterBodySkeleton.new_body_skeleton()
	add_child_autofree(_skeleton)
	_rig = SkaterConnectedRig.new()
	_rig.build(_skeleton, null, GearModelRegistry.TUCK_NONE)
	_skeleton.set_bone_pose(_UpperBone.TORSO,
			SkaterConnectedMesh.bind_rests()[SkaterConnectedMesh.Bind.TORSO])
	_head(Transform3D.IDENTITY)


# Carries the helmet off its rest place by `off`, in the trunk's frame.
func _head(off: Transform3D) -> void:
	_skeleton.set_bone_pose(_UpperBone.HELMET, off * SkaterRigidParts.HELMET_REST)
	_rig._pose_neck_foot()


# The neck's vertices as drawn, skeleton space, beside their helmet-local
# heights.
func _neck() -> Array:
	var skin: Skin = SkaterBodyMesh.shared_skin()
	var base: int = SkaterBodyMesh.upper_bind_base()
	var arrays: Array = SkaterRigidParts.upper_body_mesh().surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var drawn := PackedVector3Array()
	var heights := PackedFloat32Array()
	for v: int in verts.size():
		if bones[v * 4 + 1] != SkaterRigidParts.NECK_FOOT_BIND or weights[v * 4 + 1] <= 0.0:
			continue
		var p := Vector3.ZERO
		for k: int in 2:
			var bind: int = base + bones[v * 4 + k]
			p += (_skeleton.get_bone_global_pose(skin.get_bind_bone(bind))
					* skin.get_bind_pose(bind) * verts[v]) * weights[v * 4 + k]
		drawn.append(p)
		heights.append(verts[v].y)
	return [drawn, heights]


func test_the_helmets_rest_is_the_scenes() -> void:
	var skater: Node = (load(_SCENE) as PackedScene).instantiate()
	var helmet: Node3D = skater.get_node("MeshRoot/UpperBody/Helmet") as Node3D
	assert_true(helmet.transform.is_equal_approx(SkaterRigidParts.HELMET_REST),
			"HELMET_REST is where the scene places the helmet")
	skater.free()


func test_the_neck_is_the_torsos_up_to_the_collars_lip() -> void:
	# The neck's collar station, from which down it rides its foot alone, is
	# level with the top of the collar's band or just over it.
	var lip_top: float = SkaterConnectedMesh._TORSO_Y_M + SkaterConnectedMesh._CHEST[0].x \
			+ SkaterConnectedMesh._NECK_RISE_M + SkaterConnectedMesh._COLLAR_RISE_M
	var station: float = (SkaterRigidParts.HELMET_REST * Vector3(0.0, SkaterMeshBuilder.NECK_PROFILE[
			SkaterMeshBuilder.NECK_COLLAR_STATION].x, 0.0)).y
	assert_between(station, lip_top, lip_top + 0.01, "the collar station at the collar's lip")
	assert_eq(SkaterRigidParts.neck_foot_share(SkaterMeshBuilder.NECK_PROFILE[
			SkaterMeshBuilder.NECK_COLLAR_STATION].x), 1.0)
	assert_eq(SkaterRigidParts.neck_foot_share(SkaterMeshBuilder.NECK_PROFILE[0].x), 0.0,
			"and its top, inside the head, is the head's")


func test_a_head_carried_off_the_trunk_leaves_the_necks_foot_in_the_collar() -> void:
	var rest: Array = _neck()
	_head(Transform3D(Basis(Vector3.RIGHT, _TIP_RAD), _CARRY))
	var carried: Array = _neck()
	var collar_y: float = SkaterMeshBuilder.NECK_PROFILE[SkaterMeshBuilder.NECK_COLLAR_STATION].x
	var top_y: float = SkaterMeshBuilder.NECK_PROFILE[0].x
	var held: int = 0
	var worst: float = 0.0
	var top_moved: float = INF
	for i: int in (rest[0] as PackedVector3Array).size():
		var moved: float = (carried[0][i] as Vector3).distance_to(rest[0][i])
		if rest[1][i] <= collar_y + 1e-5:
			held += 1
			worst = maxf(worst, moved)
		elif rest[1][i] >= top_y - 1e-5:
			top_moved = minf(top_moved, moved)
	assert_gt(held, 16, "the neck has rings in the collar")
	assert_lt(worst, 1e-4, "from the collar's lip down the neck stays where the torso holds it")
	assert_gt(top_moved, _CARRY.length() * 0.5, "and its top goes with the head")


func test_a_turned_head_turns_the_neck_whole() -> void:
	# The foot turns about the neck's own axis as far as the head does, so each
	# column of the neck stays over itself: held still, the column is wrung.
	_head(Transform3D(Basis(Vector3.UP, _TURN_RAD), Vector3.ZERO))
	var foot: Transform3D = _skeleton.get_bone_global_pose(
			SkaterBodySkeleton.deform_bone(SkaterConnectedMesh.Deform.NECK_FOOT))
	var head: Transform3D = _skeleton.get_bone_global_pose(_UpperBone.HELMET)
	assert_true(foot.is_equal_approx(head), "a head turned on its axis takes the foot with it")
	# Tipped as well, the foot keeps the torso's axis and takes only the turn.
	_head(Transform3D(Basis(Vector3.UP, _TURN_RAD) * Basis(Vector3.RIGHT, _TIP_RAD), _CARRY))
	foot = _skeleton.get_bone_global_pose(
			SkaterBodySkeleton.deform_bone(SkaterConnectedMesh.Deform.NECK_FOOT))
	assert_almost_eq(foot.basis.y.normalized().dot(Vector3.UP), 1.0, 1e-5,
			"the foot's axis stays the torso's")
	assert_almost_eq(foot.origin, SkaterRigidParts.HELMET_REST.origin, Vector3.ONE * 1e-5,
			"and its place")
	var turned: float = atan2(-foot.basis.x.z, foot.basis.x.x)
	assert_almost_eq(turned, _TURN_RAD, 0.05, "turned as far as the head is")
