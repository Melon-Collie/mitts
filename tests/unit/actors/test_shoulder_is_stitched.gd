extends GutTest

# The skinned figure's shoulder is the top of its sleeve
# (SkaterMeshBuilder._append_cap_surface): a base ring laid on the torso, rings
# on the deltoid turned half as far as the arm, and a seam ring on the cap bone
# that IS the upper arm prism's top ring, where the prism carries the sleeve on.
# The seam closes only while the cap bone and the prism stand in one frame
# (SkaterArmRig._pose_arm_chain carries the arm's frame down from the cap) and
# the cap's −Y and the prism are the same length of arm.

const UpperBone = SkaterMeshBuilder.UpperBone
const CASES: int = 200
const SEED: int = 0x53484C44  # "SHLD"

var _rng := RandomNumberGenerator.new()


# Where a cap-local point of the seam ring sits in the upper arm prism's frame.
func _in_prism(q: Vector3) -> Vector3:
	return Vector3(q.x / SkaterMeshBuilder.SLEEVE_RADIUS_M, -q.z / SkaterMeshBuilder.SLEEVE_RADIUS_M,
			0.5 + q.y / SkaterMeshBuilder.UPPER_ARM_LENGTH_M)


func _seam(cap: int) -> PackedVector3Array:
	var arrays: Array = SkaterMeshBuilder.shared_upper_skin_mesh().surface_get_arrays(
			SkaterMeshBuilder.UpperSurface.SHOULDER_L if cap == UpperBone.SHOULDER_L
			else SkaterMeshBuilder.UpperSurface.SHOULDER_R)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var out := PackedVector3Array()
	for v: int in verts.size():
		if bones[v * 4] == cap:
			out.append(verts[v])
	return out


func test_the_upper_arm_length_is_the_skaters() -> void:
	var sk := Skater.new()
	assert_almost_eq(SkaterMeshBuilder.UPPER_ARM_LENGTH_M, sk.upper_arm_length, 1e-6,
			"the seam's place on the prism is a fraction of the default upper arm")
	sk.free()


func test_the_seam_ring_is_the_prisms_top_ring() -> void:
	var prism: PackedVector3Array = SkaterMeshBuilder.shared_upper_arm_bone_z() \
			.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for cap: int in [UpperBone.SHOULDER_L, UpperBone.SHOULDER_R]:
		var seam: PackedVector3Array = _seam(cap)
		assert_gt(seam.size(), 0, "the cap bone carries the seam ring")
		for q: Vector3 in seam:
			var on_prism: bool = false
			for p: Vector3 in prism:
				if p.is_equal_approx(_in_prism(q)):
					on_prism = true
					break
			assert_true(on_prism, "%s lands on the prism's top ring" % q)


func test_the_base_ring_lies_on_the_torso() -> void:
	var arrays: Array = SkaterMeshBuilder.shared_upper_skin_mesh().surface_get_arrays(
			SkaterMeshBuilder.UpperSurface.SHOULDER_R)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var on_torso: int = 0
	for v: int in verts.size():
		if bones[v * 4] != UpperBone.TORSO:
			continue
		on_torso += 1
		var p: Vector3 = verts[v]
		var radius: float = SkaterMeshBuilder._torso_radius_at(p.y)
		var across: float = Vector2(p.x / (radius * SkaterMeshBuilder._TORSO_X_SCALE),
				p.z / (radius * SkaterMeshBuilder._TORSO_Z_SCALE)).length()
		assert_almost_eq(across, SkaterMeshBuilder._CAP_SEAT_INSET, 1e-3,
				"%s is on the torso's lathe" % p)
	assert_gt(on_torso, 0, "the torso carries the shoulder's base ring")


func test_the_sleeve_closes_at_the_seam_and_the_deltoid_is_halfway() -> void:
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
	# Each arm's upper arm bone, by the side its shoulder is on.
	var arm_of: Dictionary = {}
	arm_of[UpperBone.SHOULDER_L if sk.shoulder.position.x < 0.0 else UpperBone.SHOULDER_R] = \
			UpperBone.TOP_UPPER_ARM
	arm_of[UpperBone.SHOULDER_L if sk.bottom_shoulder.position.x < 0.0
			else UpperBone.SHOULDER_R] = UpperBone.BOTTOM_UPPER_ARM
	var paths: Array[bool] = [false]
	if ClassDB.class_exists(&"NativeArmRig"):
		paths.append(true)
	var worst_gap: float = 0.0
	var worst_share: float = 0.0
	for i: int in CASES:
		sk.set_facing(Vector2.from_angle(_rng.randf() * TAU))
		sk.set_upper_body_rotation(_rng.randf_range(-1.0, 1.0))
		sk.set_upper_body_lean(_rng.randf_range(-0.5, 0.5), _rng.randf_range(-0.3, 0.3), 0.0)
		sk.set_trunk_texture(_rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.3, 0.3))
		sk.set_top_hand_position(top + Vector3(_rng.randf_range(-0.8, 0.8),
				_rng.randf_range(-0.6, 0.9), _rng.randf_range(-0.8, 0.8)))
		sk.set_bottom_hand_position(bottom + Vector3(_rng.randf_range(-0.8, 0.8),
				_rng.randf_range(-0.6, 0.9), _rng.randf_range(-0.8, 0.8)))
		sk.update_stick_mesh()
		sk._spine.update()
		for native: bool in paths:
			rig.native_enabled = native
			rig.update_top_arm()
			rig.update_bottom_arm()
			for cap: int in arm_of:
				var cap_pose: Transform3D = body.get_bone_global_pose(cap)
				var prism_pose: Transform3D = body.get_bone_global_pose(arm_of[cap])
				for q: Vector3 in _seam(cap):
					worst_gap = maxf(worst_gap,
							(cap_pose * q).distance_to(prism_pose * _in_prism(q)))
				var side: float = -1.0 if cap == UpperBone.SHOULDER_L else 1.0
				var rest := Quaternion(SkaterMeshBuilder.shoulder_cap_rest(side))
				var full := Quaternion(rig._basis[cap])
				var half := Quaternion(body.get_bone_pose(SkaterBodySkeleton.deltoid_bone(cap))
						.basis.orthonormalized())
				# Both poses carry the trunk texture; strip it to compare the turns.
				half = Quaternion(rig._trunk_texture.transposed()) * half
				worst_share = maxf(worst_share,
						absf(rest.angle_to(half) - half.angle_to(full)))
	gut.p("shoulder: worst seam gap %.6f m, worst deltoid share error %.6f rad"
			% [worst_gap, worst_share])
	assert_lt(worst_gap, 1e-4, "the shoulder's seam ring stays on the upper arm's prism")
	assert_lt(worst_share, 1e-3, "the deltoid turns halfway from the rest hang to the cap")
