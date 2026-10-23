extends GutTest

# The keeper draws as one skinned mesh (KeeperBodyRig): each bone is a gear
# piece posed on its save box, so what is drawn stays what saves; every vertex
# rides its own piece's bone alone; and the pieces' surfaces are merged down to
# one per material.

var _keeper: Keeper = null
var _pose := KeeperPose.new()


func before_each() -> void:
	_keeper = Keeper.new()
	add_child_autofree(_keeper)
	KeeperPoses.butterfly(_pose)
	_keeper.apply_pose(_pose)
	_keeper.draw_now()


func _rig() -> KeeperBodyRig:
	return _keeper.find_child("BodyRig", true, false) as KeeperBodyRig


func test_every_bone_is_posed_on_its_save_box() -> void:
	var rig: KeeperBodyRig = _rig()
	assert_eq(rig.get_bone_count(), KeeperGear.PART_COUNT)
	for part: int in KeeperGear.PART_COUNT:
		var box: Transform3D = KeeperGear.box(_keeper.skeleton, part)
		var pose: Transform3D = rig.get_bone_pose(part)
		assert_almost_eq(pose.origin, box.origin, Vector3.ONE * 1e-5, KeeperGear.Part.keys()[part])
		assert_almost_eq(pose.basis.y, box.basis.y, Vector3.ONE * 1e-5, KeeperGear.Part.keys()[part])


func test_every_vertex_rides_one_bone() -> void:
	var mesh: ArrayMesh = _rig().body_mesh().mesh as ArrayMesh
	for s: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		assert_eq(weights.size(), verts.size() * 4, "surface %d is skinned" % s)
		for i: int in verts.size():
			if not is_equal_approx(weights[i * 4], 1.0):
				fail_test("surface %d vertex %d is not rigid to one bone" % [s, i])
				return


# The plain slots are one surface; each kit-shader material adds one.
func test_the_pieces_draw_one_surface_a_material() -> void:
	var mesh: ArrayMesh = _rig().body_mesh().mesh as ArrayMesh
	var kit: Array[Material] = []
	for s: int in range(1, mesh.get_surface_count()):
		var mat: Material = mesh.surface_get_material(s)
		assert_true(mat is ShaderMaterial, "surface %d wears the kit shader" % s)
		assert_false(mat in kit, "surface %d's material has a surface already" % s)
		kit.append(mat)
	assert_eq(mesh.surface_get_material(0), _rig().paint.material, "the plain slots' zones")


# He is drawn at render rate from the skeleton the tick solved, and only once
# a pose has moved it.
func test_a_pose_that_moves_nothing_asks_for_no_redraw() -> void:
	assert_false(_keeper.apply_pose(_pose), "the same pose again")
	_pose.glove_hand += Vector3(0.0, 0.05, 0.0)
	assert_true(_keeper.apply_pose(_pose), "the glove raised")
	var was: Transform3D = _rig().get_bone_pose(KeeperGear.Part.GLOVE)
	_keeper.draw_now()
	assert_ne(_rig().get_bone_pose(KeeperGear.Part.GLOVE), was, "drawn on it")
