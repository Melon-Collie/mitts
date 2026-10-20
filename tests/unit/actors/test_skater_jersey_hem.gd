extends GutTest

# The jersey's tail: its chest share swings from the torso, its hips' share
# hangs from the waist and swings alike, and the swing lags the lean the other
# way — a start kicks it back, and it comes to rest again once the skater stops
# accelerating.

const _DT: float = 1.0 / 120.0


func _skater() -> Skater:
	var skater: Skater = (load("res://Scenes/Skater.tscn") as PackedScene).instantiate()
	add_child_autofree(skater)
	skater.set_process(false)   # the test drives the hem itself
	return skater


func _rig(skater: Skater) -> Skeleton3D:
	return skater.mesh_root.get_node("BodyRig") as Skeleton3D


func _hem_bottom(rig: Skeleton3D) -> Vector3:
	return rig.get_bone_pose(SkaterBodySkeleton.HEM_BONE) \
			* Vector3(0.0, SkaterJerseyHem.HEM_Y_M, 0.0)


func test_the_tail_hangs_from_the_chest_and_the_hips() -> void:
	var rig: Skeleton3D = _rig(_skater())
	assert_eq(rig.get_bone_parent(SkaterBodySkeleton.HEM_BONE), SkaterMeshBuilder.UpperBone.TORSO)
	assert_eq(rig.get_bone_parent(SkaterBodySkeleton.TAIL_BONE), SkaterBodySkeleton.WAIST_BONE)
	assert_eq(rig.get_bone_parent(SkaterBodySkeleton.TAIL_HEM_BONE), SkaterBodySkeleton.TAIL_BONE)


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


func test_a_start_kicks_the_hem_back_and_it_settles() -> void:
	var skater: Skater = _skater()
	var rig: Skeleton3D = _rig(skater)
	# Accelerating along the skater's forward (−Z) leans him forward.
	var forward: Vector3 = skater.upper_body.global_basis * Vector3.FORWARD
	skater.set_balance_tilt(Vector2(forward.x, forward.z) * deg_to_rad(15.0))
	for i: int in 60:
		skater._arms.update_hem(_DT, true)
	var bottom: Vector3 = _hem_bottom(rig)
	assert_gt(bottom.z, 0.01, "the hem swings back, behind its rest (+Z is the back)")
	assert_lt(bottom.z, 0.05, "by a few centimetres, inside the room over the seat")
	assert_eq(rig.get_bone_pose(SkaterBodySkeleton.TAIL_HEM_BONE),
			rig.get_bone_pose(SkaterBodySkeleton.HEM_BONE), "both shares swing alike")
	skater.set_balance_tilt(Vector2.ZERO)
	for i: int in 480:
		skater._arms.update_hem(_DT, true)
	assert_almost_eq(_hem_bottom(rig), Vector3(0.0, SkaterJerseyHem.HEM_Y_M, 0.0),
			Vector3.ONE * 1e-3, "and comes back to rest")


# Off camera the swing keeps time but the bone is not written.
func test_off_camera_the_bone_is_left_alone() -> void:
	var skater: Skater = _skater()
	var rig: Skeleton3D = _rig(skater)
	var forward: Vector3 = skater.upper_body.global_basis * Vector3.FORWARD
	skater.set_balance_tilt(Vector2(forward.x, forward.z) * deg_to_rad(15.0))
	for i: int in 30:
		skater._arms.update_hem(_DT, false)
	assert_eq(rig.get_bone_pose(SkaterBodySkeleton.HEM_BONE), Transform3D.IDENTITY)
	assert_eq(rig.get_bone_pose(SkaterBodySkeleton.TAIL_HEM_BONE), Transform3D.IDENTITY)
	assert_gt(skater._arms.hem_swing().length(), 0.0, "the lag still ran")
