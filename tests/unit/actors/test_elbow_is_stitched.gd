extends GutTest

# The skinned arm's elbow is a band stitched from the upper arm's elbow-end ring,
# through a ring on the elbow bone, to the forearm's
# (SkaterMeshBuilder._append_elbow_surface). It closes the sleeve only while its
# outer rings ARE the prisms' end rings, and it lies flat only while ring point k
# is the same facet on all three bones: one frame carried through the bend, the
# elbow's turned half of it and the forearm's all of it
# (SkaterArmRig._pose_arm_chain). Rolled each from its own up, the band twisted
# by whatever the two rolls made with each other.

const UpperBone = SkaterMeshBuilder.UpperBone
const CASES: int = 200
const SEED: int = 0x454C424F  # "ELBO"
const _ARMS: Array = [
	[UpperBone.TOP_UPPER_ARM, UpperBone.TOP_ELBOW, UpperBone.TOP_FOREARM],
	[UpperBone.BOTTOM_UPPER_ARM, UpperBone.BOTTOM_ELBOW, UpperBone.BOTTOM_FOREARM],
]

var _rng := RandomNumberGenerator.new()


func _has_point(mesh: ArrayMesh, p: Vector3) -> bool:
	for q: Vector3 in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array:
		if q.is_equal_approx(p):
			return true
	return false


func test_the_band_ends_on_the_prisms_end_rings() -> void:
	var skin: ArrayMesh = SkaterMeshBuilder.shared_upper_skin_mesh()
	var upper_prism: ArrayMesh = SkaterMeshBuilder.shared_upper_arm_bone_z()
	var forearm_prism: ArrayMesh = SkaterMeshBuilder._forearm_bone_z()
	for arm: Array in _ARMS:
		var arrays: Array = skin.surface_get_arrays(arm[1])
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var counts: Array[int] = [0, 0, 0]
		for v: int in verts.size():
			var ring: int = arm.find(bones[v * 4])
			assert_ne(ring, -1, "a band vertex rides one of its arm's three bones")
			if ring == -1:
				continue
			counts[ring] += 1
			if ring == 0:
				assert_true(_has_point(upper_prism, verts[v]),
						"%s is on the upper arm's elbow-end ring" % verts[v])
			elif ring == 2:
				assert_true(_has_point(forearm_prism, verts[v]),
						"%s is on the forearm's elbow-end ring" % verts[v])
		for ring: int in 3:
			assert_gt(counts[ring], 0, "ring %d is stitched in" % ring)


# How far the elbow and the forearm are from the upper arm's frame turned half
# and all the way through the bend: the largest axis error of the two.
func _carry_error(body: Skeleton3D, arm: Array) -> float:
	var upper: Basis = body.get_bone_pose(arm[0]).basis.orthonormalized()
	var fore: Basis = body.get_bone_pose(arm[2]).basis.orthonormalized()
	var bend := Quaternion(-upper.z, -fore.z)
	var worst: float = 0.0
	var turned: Array[Basis] = [Basis(Quaternion.IDENTITY.slerp(bend, 0.5)) * upper,
			Basis(bend) * upper]
	var drawn: Array[Basis] = [body.get_bone_pose(arm[1]).basis.orthonormalized(), fore]
	for i: int in 2:
		for axis: int in 3:
			worst = maxf(worst, (turned[i][axis] - drawn[i][axis]).length())
	return worst


func test_one_frame_is_carried_through_the_bend() -> void:
	_rng.seed = SEED
	var sk: Skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(sk)
	sk.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	sk.set_process(false)
	sk.set_physics_process(false)
	var rig: SkaterArmRig = sk._arms
	var body: Skeleton3D = rig._skeleton
	var top: Vector3 = sk.top_hand.position
	var bottom: Vector3 = sk.bottom_hand.position
	var paths: Array[bool] = [false]
	if ClassDB.class_exists(&"NativeArmRig"):
		paths.append(true)
	var worst: float = 0.0
	for i: int in CASES:
		sk.set_facing(Vector2.from_angle(_rng.randf() * TAU))
		sk.set_upper_body_rotation(_rng.randf_range(-1.0, 1.0))
		sk.set_upper_body_lean(_rng.randf_range(-0.5, 0.5), _rng.randf_range(-0.3, 0.3), 0.0)
		sk.set_top_hand_position(top + Vector3(_rng.randf_range(-0.6, 0.6),
				_rng.randf_range(-0.6, 0.6), _rng.randf_range(-0.6, 0.6)))
		sk.set_bottom_hand_position(bottom + Vector3(_rng.randf_range(-0.6, 0.6),
				_rng.randf_range(-0.6, 0.6), _rng.randf_range(-0.6, 0.6)))
		sk.update_stick_mesh()
		sk._spine.update()
		for native: bool in paths:
			rig.native_enabled = native
			rig.update_top_arm()
			rig.update_bottom_arm()
			for arm: Array in _ARMS:
				worst = maxf(worst, _carry_error(body, arm))
	gut.p("elbow carry: worst axis error %s" % String.num_scientific(worst))
	assert_lt(worst, 1e-4, "the elbow and the forearm are the upper arm's frame carried "
			+ "through the bend")
