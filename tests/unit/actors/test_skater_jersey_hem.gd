extends GutTest

# The jersey's tail above the belt: the share the hips carry hangs from the
# waist, on a bone that is the torso as the hips hold it.


func _skater() -> Skater:
	var skater: Skater = (load("res://Scenes/Skater.tscn") as PackedScene).instantiate()
	add_child_autofree(skater)
	skater.set_process(false)   # the test drives the hem itself
	return skater


func _rig(skater: Skater) -> Skeleton3D:
	return skater.mesh_root.get_node("BodyRig") as Skeleton3D


func test_the_tail_hangs_from_the_waist() -> void:
	var rig: Skeleton3D = _rig(_skater())
	assert_eq(rig.get_bone_parent(SkaterBodySkeleton.TAIL_BONE), SkaterBodySkeleton.WAIST_BONE)


# The tail is the torso as the hips hold it: at rest exactly the torso's
# placement (so a jersey at rest is the lathe it was built as), and it keeps it
# however far the chest folds — the fold is what the tail is there to stay out of.
func test_the_tail_is_the_torso_placed_on_the_waist_and_does_not_fold() -> void:
	var skater: Skater = _skater()
	var rig: Skeleton3D = _rig(skater)
	var torso: Transform3D = rig.get_bone_pose(SkaterMeshBuilder.UpperBone.TORSO)
	assert_eq(rig.get_bone_pose(SkaterBodySkeleton.TAIL_BONE), torso)
	skater.set_trunk_texture(-deg_to_rad(48.0), 0.0)
	assert_ne(rig.get_bone_pose(SkaterMeshBuilder.UpperBone.TORSO), torso, "the chest folds")
	assert_eq(rig.get_bone_pose(SkaterBodySkeleton.TAIL_BONE), torso, "and the tail does not")
	# The sizing seam reposes the torso too, and the tail goes with its scale.
	skater.set_upper_bone_scale(SkaterMeshBuilder.UpperBone.TORSO, Vector3.ONE * 1.1)
	var tail: Transform3D = rig.get_bone_pose(SkaterBodySkeleton.TAIL_BONE)
	assert_almost_eq(tail.basis.get_scale(), Vector3.ONE * 1.1, Vector3.ONE * 1e-5)
	assert_almost_eq(tail.basis.orthonormalized().get_euler().x, 0.0, 1e-5,
			"and stays unfolded")
