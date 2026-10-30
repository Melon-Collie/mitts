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
		for top_right: bool in [true, false]:
			assert_eq(count.call(SkaterBodyMesh.shared_mesh(tuck, top_right)),
					count.call(SkaterConnectedMesh.shared_mesh(tuck))
					+ count.call(SkaterRigidParts.upper_body_mesh(top_right))
					+ count.call(SkaterRigidParts.leg_body_mesh()),
					"tuck %d, top glove %s" % [tuck, "right" if top_right else "left"])


# Each rigid vertex's bind names the bone its own mesh's skin bound it to, at
# identity; the skin's vertices keep the skin's binds.
func test_the_rigid_parts_bind_to_their_own_bones() -> void:
	var skin: Skin = SkaterBodyMesh.shared_skin()
	var arrays: Array = SkaterBodyMesh.shared_mesh(GearModelRegistry.TUCK_NONE).surface_get_arrays(0)
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var skin_verts: int = (SkaterConnectedMesh.shared_mesh(GearModelRegistry.TUCK_NONE)
			.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var upper: Array = SkaterRigidParts.upper_body_mesh(true).surface_get_arrays(0)
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


# The gloves are a left and a right hand: each fist is the same both sides of
# its back, so its thumb is what puts its weight on the palm's side, which is −Z
# on a right hand (SkaterMeshBuilder.glove_thumb_xform). A left-handed shot tops
# the stick with the right hand, and its body wears that mesh.
func test_the_gloves_are_a_left_and_a_right_hand() -> void:
	for top_right: bool in [true, false]:
		var arrays: Array = SkaterRigidParts.upper_body_mesh(top_right).surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var lean := {SkaterMeshBuilder.UpperBone.TOP_HAND: 0.0,
				SkaterMeshBuilder.UpperBone.BOTTOM_HAND: 0.0}
		for v: int in verts.size():
			if lean.has(bones[v * 4]):
				lean[bones[v * 4]] += verts[v].z
		var top_palm: float = -1.0 if top_right else 1.0
		assert_gt(float(lean[SkaterMeshBuilder.UpperBone.TOP_HAND]) * top_palm, 0.0,
				"the top glove's thumb on its palm (top %s)" % ("right" if top_right else "left"))
		assert_lt(float(lean[SkaterMeshBuilder.UpperBone.BOTTOM_HAND]) * top_palm, 0.0,
				"and the bottom glove's on the other side")
	for left_handed: bool in [true, false]:
		var skater: Skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
		skater.is_left_handed = left_handed
		add_child_autofree(skater)
		var rig: Skeleton3D = skater.mesh_root.get_node("BodyRig") as Skeleton3D
		var body: MeshInstance3D = rig.get_node("Body") as MeshInstance3D
		assert_eq(body.mesh, SkaterBodyMesh.shared_mesh(skater.gear_style.jersey_tuck
				if skater.gear_style != null else GearModelRegistry.TUCK_NONE, left_handed),
				"a %s shot wears its top glove on the %s hand" % [
				"left" if left_handed else "right", "right" if left_handed else "left"])
		skater.is_left_handed = not left_handed
		assert_eq(body.mesh, SkaterBodyMesh.shared_mesh(skater.gear_style.jersey_tuck
				if skater.gear_style != null else GearModelRegistry.TUCK_NONE, not left_handed),
				"and swaps them when the shot changes hands")
