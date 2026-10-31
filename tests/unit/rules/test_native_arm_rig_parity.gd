extends GutTest

# Parity fuzz: the C++ arm solve (NativeArmRig, native/src/) against its
# GDScript reference (SkaterArmRig._update_arm). Seeded RNG over the live rig:
# hands in and out of reach (the girdle's give and the IK clamp), trunk
# texture, a twisted and leaned trunk, the balance lean, a check load,
# per-build arm lengths and part thicknesses, and gloves on and off the shaft —
# the elbow steered round the torso, the sword grip and the top fist's roll
# with them. Every arm bone must agree.
#
# Pending without the extension (fresh clone, CI without a native build) — run
# native/build.sh.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const TOLERANCE: float = 0.0001
const CASES: int = 600
const SEED: int = 0x41524D53  # "ARMS" — fixed so failures reproduce.
const UpperBone = SkaterMeshBuilder.UpperBone
const _BONES: Array[int] = [
	UpperBone.TOP_UPPER_ARM, UpperBone.TOP_FOREARM, UpperBone.TOP_CUFF,
	UpperBone.TOP_ELBOW, UpperBone.TOP_HAND,
	UpperBone.BOTTOM_UPPER_ARM, UpperBone.BOTTOM_FOREARM, UpperBone.BOTTOM_CUFF,
	UpperBone.BOTTOM_ELBOW, UpperBone.BOTTOM_HAND,
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
	var sk: Skater = SKATER_SCENE.instantiate() as Skater
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
	var gripped: int = 0
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
		sk._check_lead = _rng.randf_range(-1.0, 1.0) if _rng.randf() < 0.3 else 0.0
		# Hands from in tight to well past the arm (the girdle and the IK clamp),
		# the bottom one on the shaft half the time.
		sk.set_top_hand_position(top + _v(0.9))
		sk.set_bottom_hand_position(bottom + _v(0.9))
		sk.update_stick_mesh()
		if _rng.randf() < 0.5:
			sk.set_bottom_hand_position(sk.drawn_top_hand().lerp(sk.blade.position,
					_rng.randf_range(0.1, 0.6)))
		if sk.stick_grip_axis(sk.bottom_hand.position) != Vector3.ZERO:
			gripped += 1
		sk.set_trunk_texture(texture.x, texture.y)
		sk._spine.update()
		rig.native_enabled = false
		rig.update_top_arm()
		rig.update_bottom_arm()
		var reference: Array[Transform3D] = _poses(sk)
		rig.native_enabled = true
		rig.update_top_arm()
		rig.update_bottom_arm()
		var native: Array[Transform3D] = _poses(sk)
		var err: float = _worst(reference, native)
		if rig._native_update_arm(0, -1.0, sk.shoulder.position, sk.top_hand.position,
				sk.stick_grip_axis(sk.drawn_top_hand()), 1.0 if sk.is_left_handed else -1.0):
			native_ran += 1
		if err > worst:
			worst = err
			worst_case = i
	gut.p("arm rig: %d cases, worst |Δ| %s at case %d" % [CASES, String.num_scientific(worst), worst_case])
	assert_lt(worst, TOLERANCE, "the native arm solve stayed within tolerance")
	assert_gt(float(native_ran), CASES * 0.95, "and it ran, rather than falling back (%d/%d)" % [native_ran, CASES])
	assert_between(gripped, int(CASES * 0.3), int(CASES * 0.7),
			"both glove paths ran: the bottom hand on the shaft in %d/%d" % [gripped, CASES])


# The eased angles (the elbow's turn, the top fist's roll) frame by frame: two
# skaters, one on each path, given the same hands swept round the body at a
# real frame time, so each spring runs from its own state.
func test_the_native_arm_eases_as_the_gdscript() -> void:
	if not ClassDB.class_exists(&"NativeArmRig"):
		NativeParityGuard.report_missing(self, "NativeArmRig")
		return
	_rng.seed = SEED
	var skaters: Array[Skater] = []
	for native: bool in [false, true]:
		var sk: Skater = SKATER_SCENE.instantiate() as Skater
		add_child_autofree(sk)
		sk.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
		sk.set_process(false)
		sk.set_physics_process(false)
		sk._arms.native_enabled = native
		skaters.append(sk)
	var top: Vector3 = skaters[0].top_hand.position
	var worst: float = 0.0
	var settling: int = 0
	for frame: int in 240:
		var a: float = TAU * frame / 240.0
		var reach := Vector3(sin(a) * 0.45, -0.05 + 0.1 * sin(a * 3.0), -absf(cos(a)) * 0.35)
		var poses: Array = []
		for sk: Skater in skaters:
			sk.set_upper_body_rotation(0.6 * sin(a * 2.0))
			sk.set_top_hand_position(top + reach)
			sk.update_stick_mesh()
			sk.set_bottom_hand_position(sk.drawn_top_hand().lerp(sk.blade.position, 0.3))
			sk._spine.update()
			sk._arms.update_top_arm(1.0 / 60.0)
			sk._arms.update_bottom_arm(1.0 / 60.0)
			poses.append(_poses(sk))
		if skaters[1]._arms.take_steering():
			settling += 1
		skaters[0]._arms.take_steering()
		worst = maxf(worst, _worst(poses[0], poses[1]))
	gut.p("arm rig eased: worst |Δ| %s, %d frames settling" % [String.num_scientific(worst), settling])
	assert_lt(worst, TOLERANCE, "the native arm eases as the GDScript does")
	assert_gt(settling, 0, "and the eases ran")
