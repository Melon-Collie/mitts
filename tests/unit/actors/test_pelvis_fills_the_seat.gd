extends GutTest

# The trunk texture rotates the torso bone about the fold pivot at the hips. A
# real pelvis does not fold with the spine, so the rig's PELVIS bone, which the
# skin's pants ride (SkaterConnectedMesh), does not fold with the torso: the
# seat stays under the jersey's hem as it swings up and away.

const _SCENE: String = "res://Scenes/Skater.tscn"


# ── It must not fold ─────────────────────────────────────────────────────────

# The whole point, and a one-line mistake to undo: adding PELVIS to the list of
# bones SkaterArmRig.repose_bone rotates by the trunk texture would give the
# body a second hem that swings away with the first.
func test_the_pelvis_does_not_fold_with_the_chest() -> void:
	var skater: Skater = (load(_SCENE) as PackedScene).instantiate() as Skater
	add_child_autofree(skater)
	skater.set_physics_process(false)
	skater.set_process(false)
	var rig: Skeleton3D = skater.mesh_root.get_node("BodyRig") as Skeleton3D
	var pelvis_rest: Transform3D = rig.get_bone_pose(SkaterMeshBuilder.UpperBone.PELVIS)

	skater.set_trunk_texture(-deg_to_rad(48.0), 0.0)

	assert_gt(rig.get_bone_pose(SkaterMeshBuilder.UpperBone.TORSO).basis.get_euler().x, -1.0,
			"the torso must take the fold")
	assert_lt(rig.get_bone_pose(SkaterMeshBuilder.UpperBone.TORSO).basis.get_euler().x, -0.5,
			"the torso must take the whole fold")
	assert_eq(rig.get_bone_pose(SkaterMeshBuilder.UpperBone.PELVIS), pelvis_rest,
			"and the pelvis must not move at all")

	# The other half, and the one a written-once guard misses: the fold is applied
	# in repose_bone, which every OTHER writer goes through too. The sizing seam
	# reposes this bone on each appearance apply, so a pelvis that is merely
	# absent from set_trunk_texture's call list still folds the moment a build's
	# scale lands on it while a fold is live.
	skater.set_upper_bone_scale(SkaterMeshBuilder.UpperBone.PELVIS, Vector3.ONE * 1.1)
	var reposed: Basis = rig.get_bone_pose(SkaterMeshBuilder.UpperBone.PELVIS).basis
	assert_almost_eq(reposed.get_euler().x, 0.0, 0.001,
			"and it must still be unrotated after anything else reposes it")
