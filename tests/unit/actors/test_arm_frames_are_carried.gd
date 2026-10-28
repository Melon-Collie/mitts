extends GutTest

# The sleeve is one skin over the arm's bones (SkaterMeshBuilder._sleeve), so
# their frames have to agree with one another, not just sit in the right place:
# the arm is one frame carried down from the shoulder (SkaterArmRig._pose_arm_chain)
# — the elbow's turned half the bend from the upper arm's, the forearm's all of
# it — and the deltoid turned halfway from the cap's rest hang to the cap, which
# swings there with no twist. Any other roll wrings the sleeve between them.

const UpperBone = SkaterMeshBuilder.UpperBone
const CASES: int = 200
const SEED: int = 0x454C424F  # "ELBO"
const _SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const _ARMS: Array = [
	[UpperBone.TOP_UPPER_ARM, UpperBone.TOP_ELBOW, UpperBone.TOP_FOREARM],
	[UpperBone.BOTTOM_UPPER_ARM, UpperBone.BOTTOM_ELBOW, UpperBone.BOTTOM_FOREARM],
]

var _rng := RandomNumberGenerator.new()


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
	var sk: Skater = _SKATER_SCENE.instantiate() as Skater
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


func test_the_shoulder_swings_and_the_deltoid_goes_halfway() -> void:
	_rng.seed = SEED
	var sk: Skater = _SKATER_SCENE.instantiate() as Skater
	add_child_autofree(sk)
	sk.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	sk.set_process(false)
	sk.set_physics_process(false)
	var rig: SkaterArmRig = sk._arms
	var body: Skeleton3D = rig._skeleton
	var top: Vector3 = sk.top_hand.position
	var paths: Array[bool] = [false]
	if ClassDB.class_exists(&"NativeArmRig"):
		paths.append(true)
	var worst_share: float = 0.0
	var worst_twist: float = 0.0
	for i: int in CASES:
		sk.set_trunk_texture(_rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.3, 0.3))
		sk.set_top_hand_position(top + Vector3(_rng.randf_range(-0.8, 0.8),
				_rng.randf_range(-0.6, 0.9), _rng.randf_range(-0.8, 0.8)))
		sk.update_stick_mesh()
		sk._spine.update()
		var cap: int = UpperBone.SHOULDER_L if sk.shoulder.position.x < 0.0 \
				else UpperBone.SHOULDER_R
		var rest: Basis = SkaterMeshBuilder.shoulder_cap_rest(signf(sk.shoulder.position.x))
		for native: bool in paths:
			rig.native_enabled = native
			rig.update_top_arm()
			if native:
				rig._sync_cap(0 if cap == UpperBone.SHOULDER_L else 1)
			var full: Basis = rig._basis[cap]
			# No twist: the turn from rest carries the hang onto the arm about an
			# axis square to both.
			var turn := Quaternion(full * rest.inverse())
			var axis: Vector3 = turn.get_axis()
			if turn.get_angle() > 1e-3:
				worst_twist = maxf(worst_twist, absf(axis.dot(rest.y.normalized())))
			var half := Quaternion(rig._trunk_texture.transposed() * body.get_bone_pose(
					SkaterBodySkeleton.deltoid_bone(cap)).basis.orthonormalized())
			worst_share = maxf(worst_share, absf(Quaternion(rest).angle_to(half)
					- half.angle_to(Quaternion(full))))
	gut.p("shoulder: worst twist %.6f, worst deltoid share error %.6f rad"
			% [worst_twist, worst_share])
	assert_lt(worst_twist, 1e-3, "the cap swings from its rest hang without twisting")
	assert_lt(worst_share, 1e-3, "the deltoid turns halfway from the rest hang to the cap")
