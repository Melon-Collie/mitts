extends GutTest

# The glove is a right or a left one (SkaterMeshBuilder.shared_glove_fist): its
# thumb wraps round the shaft on the palm's side, which in the glove's frame
# (SkaterArmPoses.glove_basis: +X the thumb's side, +Y the wrist) is −Z for a
# right hand and +Z for a left. The skater's body wears the pair its shot puts
# on the stick — a left shot's top hand is his right — and changes them with
# his shot (SkaterConnectedRig.pose).

const _SCENE: String = "res://Scenes/Skater.tscn"


func _thumb(right: bool) -> PackedVector3Array:
	return SkaterMeshBuilder.shared_glove_fist(right).surface_get_arrays(
			SkaterMeshBuilder.FIST_PART_THUMB)[Mesh.ARRAY_VERTEX]


func _centroid(verts: PackedVector3Array) -> Vector3:
	var sum := Vector3.ZERO
	for v: Vector3 in verts:
		sum += v
	return sum / verts.size()


func test_the_thumb_is_on_the_palms_side_of_each_hand() -> void:
	assert_lt(_centroid(_thumb(true)).z, -0.2, "a right hand's palm is its −Z")
	assert_gt(_centroid(_thumb(false)).z, 0.2, "a left hand's palm is its +Z")
	var right: PackedVector3Array = _thumb(true)
	var left: PackedVector3Array = _thumb(false)
	assert_eq(right.size(), left.size())
	var unmatched: int = 0
	for v: Vector3 in right:
		var found: bool = false
		for w: Vector3 in left:
			if w.distance_to(Vector3(v.x, v.y, -v.z)) < 0.0001:
				found = true
				break
		if not found:
			unmatched += 1
	assert_eq(unmatched, 0, "the two thumbs mirror across the palm")


func test_the_body_wears_the_gloves_his_shot_puts_on_the_stick() -> void:
	var skater: Skater = (load(_SCENE) as PackedScene).instantiate() as Skater
	add_child_autofree(skater)
	skater.set_process(false)
	skater.set_physics_process(false)
	skater.set_uniform(TeamColorRegistry.get_colors(0, 0))
	var body_mesh: MeshInstance3D = skater.mesh_root.find_child("Body", true, false) \
			as MeshInstance3D
	var body: Material = body_mesh.get_surface_override_material(0)
	skater.is_left_handed = true
	skater._process(1.0 / 60.0)
	assert_eq(body_mesh.mesh, SkaterBodyMesh.shared_mesh(GearModelRegistry.TUCK_NONE, true),
			"a left shot holds the top of the stick in his right hand")
	skater.is_left_handed = false
	skater._process(1.0 / 60.0)
	assert_eq(body_mesh.mesh, SkaterBodyMesh.shared_mesh(GearModelRegistry.TUCK_NONE, false),
			"a right shot in his left")
	assert_eq(body_mesh.get_surface_override_material(0), body, "the body material stays on")
