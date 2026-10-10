extends GutTest

# Parity fuzz: the C++ leg chain (NativeLegChain, native/src/) against its
# GDScript reference in SkaterLegRig — the ankle's give-back (_foot_pose), a
# runner's height at a knee extension (_chain_low) and the second-foot plant's
# knee walk (_plant_feet). Seeded RNG over the live rig: gait poses from upright
# to the crouches and splays the gait reaches, both ankle give-backs at any
# weight, a tilted ice frame, the hips anywhere, either foot the support, and
# per-build bone scales and positions through the sizing seam.
#
# Pending without the extension (fresh clone, CI without a native build) — run
# native/build.sh.

const TOLERANCE: float = 0.0001
const CASES: int = 1500
const SEED: int = 0x4C454753  # "LEGS" — fixed so failures reproduce.
const LegBone = SkaterMeshBuilder.LegBone

var _rng := RandomNumberGenerator.new()
var _worst: float = 0.0
var _where: String = ""


func _r(spread: float) -> float:
	return _rng.randf_range(-spread, spread)


func _gait_pose(legs: SkaterLegRig) -> void:
	legs.set_swing(_rng.randf_range(-0.4, 1.0), _r(0.5), -_rng.randf_range(0.0, 1.9),
			_rng.randf_range(-0.4, 1.0), _r(0.5), -_rng.randf_range(0.0, 1.9), _r(0.8), _r(0.8))
	var ice := Basis.from_euler(Vector3(_r(0.4), _r(0.6), _r(0.4)))
	legs.set_ankle_flatten(maxf(_r(1.0), 0.0), maxf(_r(1.0), 0.0),
			maxf(_rng.randf_range(-0.3, 1.0), 0.0), maxf(_rng.randf_range(-0.3, 1.0), 0.0), ice)


func _hips() -> Transform3D:
	return Transform3D(Basis.from_euler(Vector3(_r(0.3), _r(PI), _r(0.3))),
			Vector3(_r(0.3), _rng.randf_range(-0.5, -0.1), _r(0.3)))


func _check(want: float, got: float, where: String) -> void:
	var err: float = absf(want - got)
	if err > _worst:
		_worst = err
		_where = where


func _check_xf(want: Transform3D, got: Transform3D, where: String) -> void:
	_check(0.0, want.origin.distance_to(got.origin), where + " origin")
	for axis: int in 3:
		_check(0.0, (want.basis[axis] - got.basis[axis]).length(), where + " basis")


func test_the_native_leg_chain_matches_the_gdscript() -> void:
	if not ClassDB.class_exists(&"NativeLegChain"):
		NativeParityGuard.report_missing(self, "NativeLegChain")
		return
	_rng.seed = SEED
	var sk: Skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(sk)
	sk.set_process(false)
	sk.set_physics_process(false)
	var legs: SkaterLegRig = sk._legs
	var native: RefCounted = legs._native
	assert_not_null(native, "the rig runs the port where the extension is built")
	var planted: int = 0
	var walked: int = 0
	for i: int in CASES:
		if i % 300 == 150:
			# A build: the sizing seam moves and rescales the chain's bones.
			for bone: int in [LegBone.LEG_L, LegBone.SHIN_R, LegBone.FOOT_L, LegBone.FOOT_R]:
				legs.set_bone_position(bone, legs.bone_base_position(bone) * _rng.randf_range(0.9, 1.1))
				legs.set_bone_scale(bone, legs.bone_base_scale(bone) * _rng.randf_range(0.9, 1.1))
		_gait_pose(legs)
		var hips: Transform3D = _hips()
		for side: int in 2:
			var bone: int = LegBone.FOOT_L if side == 0 else LegBone.FOOT_R
			var leg := Vector3(_r(1.0), _r(0.8), _r(0.5))
			var knee: float = -_rng.randf_range(0.0, 2.2)
			var weight: float = maxf(_r(1.0), 0.0)
			var level: float = maxf(_r(1.0), 0.0)
			_check_xf(legs._foot_pose(bone, leg, knee, legs._shin_base_euler[side], weight, level),
					native.foot_pose(side, leg, knee, weight, level), "case %d foot %d" % [i, side])
			var ext: float = _r(1.2)
			_check(legs._chain_low(hips, side, ext), native.chain_low(hips, side, ext),
					"case %d chain %d" % [i, side])
		legs.set_contact(_rng.randf(), _rng.randf(), 0.0)
		legs._plant_feet(hips)
		var got: Vector2 = native.plant(hips, legs._plant[0], legs._plant[1])
		_check(legs._plant_ext[0], got.x, "case %d plant left" % i)
		_check(legs._plant_ext[1], got.y, "case %d plant right" % i)
		if legs._plant_ext[0] != 0.0 or legs._plant_ext[1] != 0.0:
			planted += 1
		if legs._plant_ext[0] * legs._plant_ext[1] != 0.0:
			walked += 1
	gut.p("%d cases (%d planted, %d folded the support too): worst |Δ| %s at %s"
			% [CASES, planted, walked, String.num_scientific(_worst), _where])
	assert_gt(planted, CASES / 4, "the fuzz exercised the plant")
	assert_gt(walked, 10, "and the support's fold")
	assert_lt(_worst, TOLERANCE, "the port matches its reference")
