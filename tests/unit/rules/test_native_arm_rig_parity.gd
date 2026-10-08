extends GutTest

# Parity fuzz: the C++ arm solve (NativeArmRig, native/src/) against its
# GDScript reference (SkaterArmRig._update_arm). Seeded RNG over the live rig:
# hands in and out of reach (the girdle's give and the IK clamp), trunk
# texture, a twisted and leaned trunk, the balance lean, a check load, and
# per-build arm lengths and part thicknesses. Every arm bone, both deltoid caps
# and the girdle offsets must agree, and again once a trunk-texture change has
# reposed the caps from the rig's read-back of the native's cap state.
#
# Pending without the extension (fresh clone, CI without a native build) — run
# native/build.sh.

const TOLERANCE: float = 0.0001
const CASES: int = 600
const SEED: int = 0x41524D53  # "ARMS" — fixed so failures reproduce.
const UpperBone = SkaterMeshBuilder.UpperBone
const _BONES: Array[int] = [
	UpperBone.TOP_UPPER_ARM, UpperBone.TOP_FOREARM, UpperBone.TOP_CUFF,
	UpperBone.TOP_ELBOW, UpperBone.TOP_HAND,
	UpperBone.BOTTOM_UPPER_ARM, UpperBone.BOTTOM_FOREARM, UpperBone.BOTTOM_CUFF,
	UpperBone.BOTTOM_ELBOW, UpperBone.BOTTOM_HAND,
	UpperBone.SHOULDER_L, UpperBone.SHOULDER_R,
]

var _rng := RandomNumberGenerator.new()


func _v(spread: float) -> Vector3:
	return Vector3(_rng.randf_range(-spread, spread), _rng.randf_range(-spread, spread),
			_rng.randf_range(-spread, spread))


func _poses(sk: Skater) -> Array[Transform3D]:
	var body: Skeleton3D = sk._arms._skeleton
	var out: Array[Transform3D] = []
	for bone: int in _BONES:
		out.append(body.get_bone_pose(bone))
	out.append(Transform3D(Basis.IDENTITY, sk._arms._girdle[0]))
	out.append(Transform3D(Basis.IDENTITY, sk._arms._girdle[1]))
	return out


func _worst(a: Array[Transform3D], b: Array[Transform3D]) -> float:
	var worst: float = 0.0
	for i: int in a.size():
		worst = maxf(worst, a[i].origin.distance_to(b[i].origin))
		for axis: int in 3:
			worst = maxf(worst, (a[i].basis[axis] - b[i].basis[axis]).length())
	return worst


func test_the_native_arm_solve_matches_the_gdscript() -> void:
	if not ClassDB.class_exists(&"NativeArmRig"):
		NativeParityGuard.report_missing(self, "NativeArmRig")
		return
	_rng.seed = SEED
	var sk: Skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(sk)
	sk.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	sk.set_process(false)
	sk.set_physics_process(false)
	var rig: SkaterArmRig = sk._arms
	var top: Vector3 = sk.top_hand.position
	var bottom: Vector3 = sk.bottom_hand.position
	var worst: float = 0.0
	var worst_case: int = -1
	var native_ran: int = 0
	for i: int in CASES:
		sk.upper_arm_length = _rng.randf_range(0.28, 0.38)
		sk.forearm_length = _rng.randf_range(0.28, 0.38)
		sk.shoulder_reach_m = _rng.randf_range(0.0, 0.1)
		sk.set_arm_bone_radius(UpperBone.TOP_FOREARM, _rng.randf_range(0.03, 0.06))
		sk.set_facing(Vector2.from_angle(_rng.randf() * TAU))
		sk.set_upper_body_rotation(_rng.randf_range(-1.0, 1.0))
		sk.set_upper_body_lean(_rng.randf_range(-0.5, 0.5), _rng.randf_range(-0.3, 0.3), 0.0)
		sk.set_lower_body_lean(_rng.randf_range(-0.3, 0.3))
		sk.set_balance_tilt(Vector2(_rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.3, 0.3)),
				Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)))
		var texture := Vector2(_rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.3, 0.3))
		var after := Vector2(_rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.3, 0.3))
		sk._check_lead = _rng.randf_range(-1.0, 1.0) if _rng.randf() < 0.3 else 0.0
		# Hands from in tight to well past the arm (the girdle and the IK clamp).
		sk.set_top_hand_position(top + _v(0.9))
		sk.set_bottom_hand_position(bottom + _v(0.9))
		sk.set_trunk_texture(texture.x, texture.y)
		sk._spine.update()
		rig.native_enabled = false
		rig.update_top_arm()
		rig.update_bottom_arm()
		var reference: Array[Transform3D] = _poses(sk)
		# A texture change after the arms reposes the caps from the rig's own
		# view of them, which the native path has to have handed back.
		sk.set_trunk_texture(after.x, after.y)
		reference.append_array(_poses(sk))
		sk.set_trunk_texture(texture.x, texture.y)
		rig.native_enabled = true
		rig.update_top_arm()
		rig.update_bottom_arm()
		var native: Array[Transform3D] = _poses(sk)
		sk.set_trunk_texture(after.x, after.y)
		native.append_array(_poses(sk))
		var err: float = _worst(reference, native)
		if rig._native_update_arm(0, sk.shoulder.position, sk.top_hand.position,
				1.0 if sk.is_left_handed else -1.0):
			native_ran += 1
		if err > worst:
			worst = err
			worst_case = i
	gut.p("arm rig: %d cases, worst |Δ| %s at case %d" % [CASES, String.num_scientific(worst), worst_case])
	assert_lt(worst, TOLERANCE, "the native arm solve stayed within tolerance")
	assert_gt(float(native_ran), CASES * 0.95, "and it ran, rather than falling back (%d/%d)" % [native_ran, CASES])
