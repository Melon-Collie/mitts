extends GutTest

# The whole body is one surface (SkaterBodyMesh), so it is one draw in every
# pass it is in — the view and each shadow map that holds it. Its rigid parts
# must ride the bones they rode on their own meshes, at identity.

const _SCENE: String = "res://Scenes/Skater.tscn"


func test_a_skater_draws_its_body_as_one_surface() -> void:
	var skater: Skater = (load(_SCENE) as PackedScene).instantiate() as Skater
	add_child_autofree(skater)
	skater.set_process(false)
	skater.set_physics_process(false)
	var rig: Skeleton3D = skater.mesh_root.get_node("BodyRig") as Skeleton3D
	var meshes: Array[MeshInstance3D] = []
	for child: Node in rig.get_children():
		if child is MeshInstance3D:
			meshes.append(child as MeshInstance3D)
	assert_eq(meshes.size(), 1, "one mesh on the body's skeleton")
	assert_eq(meshes[0].mesh.get_surface_count(), 1, "of one surface")


func test_the_body_holds_the_skin_and_every_rigid_part() -> void:
	var count := func(m: ArrayMesh) -> int:
		return (m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	for tuck: int in GearModelRegistry.tuck_count():
		assert_eq(count.call(SkaterBodyMesh.shared_mesh(tuck)),
				count.call(SkaterConnectedMesh.shared_mesh(tuck))
				+ count.call(SkaterRigidParts.upper_body_mesh())
				+ count.call(SkaterRigidParts.leg_body_mesh()), "tuck %d" % tuck)


# Each rigid vertex's bind names the bone its own mesh's skin bound it to, at
# identity; the skin's vertices keep the skin's binds.
func test_the_rigid_parts_bind_to_their_own_bones() -> void:
	var skin: Skin = SkaterBodyMesh.shared_skin()
	var arrays: Array = SkaterBodyMesh.shared_mesh(GearModelRegistry.TUCK_NONE).surface_get_arrays(0)
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var skin_verts: int = (SkaterConnectedMesh.shared_mesh(GearModelRegistry.TUCK_NONE)
			.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var upper: Array = SkaterRigidParts.upper_body_mesh().surface_get_arrays(0)
	var upper_verts: int = (upper[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var upper_bones: PackedInt32Array = upper[Mesh.ARRAY_BONES]
	var leg_bones: PackedInt32Array = SkaterRigidParts.leg_body_mesh() \
			.surface_get_arrays(0)[Mesh.ARRAY_BONES]
	var base: int = SkaterBodyMesh.upper_bind_base()
	var bad: int = 0
	for v: int in bones.size() / 4:
		for k: int in 4:
			if weights[v * 4 + k] <= 0.0:
				continue
			var bind: int = bones[v * 4 + k]
			if bind < 0 or bind >= skin.get_bind_count():
				bad += 1
				continue
			if v < skin_verts:
				if bind >= base:
					bad += 1
				continue
			var own: int = upper_bones[(v - skin_verts) * 4 + k] if v < skin_verts + upper_verts \
					else SkaterBodySkeleton.LEG_BONE_OFFSET \
					+ leg_bones[(v - skin_verts - upper_verts) * 4 + k]
			if skin.get_bind_bone(bind) != own or skin.get_bind_pose(bind) != Transform3D.IDENTITY:
				bad += 1
	assert_eq(bad, 0, "every weighted influence binds where its part's own mesh bound it")
