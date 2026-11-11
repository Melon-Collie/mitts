extends GutTest

# Parity fuzz: the C++ cloth flaps (NativeHemFlaps, native/src/) against their
# GDScript reference (HemFlaps.step), for the skater's jersey tail over his
# colliders (SkaterHemColliders) and the keeper's over his (KeeperTailColliders).
# Seeded RNG over two live rigs posed alike: the trunk, the tail frame, the
# pants and both legs turned and lifted into the hem, the drape's points
# scattered round their rest (into the colliders, past their lengths) with a
# velocity, a step from under a frame to past the solver's cap, gravity less
# the figure's acceleration, and for the skater every tuck. Every point of the
# state and every flap bone must agree after one step, and after a run of
# steps from one shared start.
#
# Pending without the extension (fresh clone, CI without a native build) — run
# native/build.sh.

const TOLERANCE: float = 0.0001
const CASES: int = 400
const RUNS: int = 40
const RUN_STEPS: int = 12
const SEED: int = 0x48454D53  # "HEMS" — fixed so failures reproduce.
const _POSED: Array[int] = [
	SkaterBodySkeleton.HIPS_BONE, SkaterBodySkeleton.WAIST_BONE, SkaterBodySkeleton.SPINE_BONE,
	SkaterMeshBuilder.UpperBone.TORSO, SkaterBodySkeleton.TAIL_BONE,
	SkaterMeshBuilder.UpperBone.PELVIS,
	SkaterBodySkeleton.LEG_BONE_OFFSET + SkaterMeshBuilder.LegBone.LEG_L,
	SkaterBodySkeleton.LEG_BONE_OFFSET + SkaterMeshBuilder.LegBone.LEG_R,
	SkaterBodySkeleton.LEG_BONE_OFFSET + SkaterMeshBuilder.LegBone.THIGH_L,
	SkaterBodySkeleton.LEG_BONE_OFFSET + SkaterMeshBuilder.LegBone.THIGH_R,
]

var _rng := RandomNumberGenerator.new()


func _v(spread: float) -> Vector3:
	return Vector3(_rng.randf_range(-spread, spread), _rng.randf_range(-spread, spread),
			_rng.randf_range(-spread, spread))


func _skater() -> Skater:
	var sk: Skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(sk)
	sk.set_process(false)
	sk.set_physics_process(false)
	return sk


func _rig(sk: Skater) -> Skeleton3D:
	return sk.mesh_root.get_node("BodyRig") as Skeleton3D


func _worst(a: HemFlaps, b: HemFlaps, rig_a: Skeleton3D, rig_b: Skeleton3D, first_column_bone: int) -> float:
	var worst: float = 0.0
	var sa: PackedVector3Array = a.get_state()
	var sb: PackedVector3Array = b.get_state()
	for i: int in sa.size():
		worst = maxf(worst, sa[i].distance_to(sb[i]))
	for k: int in a.columns:
		for joint: int in 2:
			var bone: int = first_column_bone + 2 * k + joint
			var pa: Transform3D = rig_a.get_bone_pose(bone)
			var pb: Transform3D = rig_b.get_bone_pose(bone)
			worst = maxf(worst, pa.origin.distance_to(pb.origin))
			for axis: int in 3:
				worst = maxf(worst, (pa.basis[axis] - pb.basis[axis]).length())
	return worst


# Poses both rigs alike, off their built rest; the legs swing far enough to
# put a thigh through the hem.
func _pose(rig_a: Skeleton3D, rig_b: Skeleton3D, base: Array[Transform3D]) -> void:
	for i: int in _POSED.size():
		var spread: float = 1.4 if i >= 6 else 0.35
		var pose: Transform3D = base[i] * Transform3D(Basis.from_euler(_v(spread)), _v(0.03))
		rig_a.set_bone_pose(_POSED[i], pose)
		rig_b.set_bone_pose(_POSED[i], pose)


# A state round the rest drape the reference would start from: points kicked
# off it, prev points behind them by a velocity.
func _scatter(flaps: HemFlaps) -> PackedVector3Array:
	var start: PackedVector3Array = flaps.get_state()
	var n: int = flaps.columns * 2
	for i: int in n:
		start[i] += _v(0.06)
		start[n + i] = start[i] - _v(0.02)
	return start


# Held off, the hem's lean round the ring is the plain solver, the keeper's.
func test_the_native_drape_matches_the_gdscript() -> void:
	_skater_parity(0.0)


func test_the_native_drape_matches_with_the_hem_held_to_its_column() -> void:
	_skater_parity(SkaterHemFlaps.SHEAR_STIFFNESS)


func _skater_parity(shear: float) -> void:
	if not ClassDB.class_exists(&"NativeHemFlaps"):
		NativeParityGuard.report_missing(self, "NativeHemFlaps")
		return
	_rng.seed = SEED
	var sk_a: Skater = _skater()
	var sk_b: Skater = _skater()
	var rig_a: Skeleton3D = _rig(sk_a)
	var rig_b: Skeleton3D = _rig(sk_b)
	var ref: SkaterHemFlaps = sk_a._arms._hem
	var port: SkaterHemFlaps = sk_b._arms._hem
	ref.native_enabled = false
	ref.shear_stiffness = shear
	port.shear_stiffness = shear
	var base: Array[Transform3D] = []
	for bone: int in _POSED:
		base.append(rig_a.get_bone_pose(bone))
	var worst: float = 0.0
	for c: int in CASES + RUNS:
		var tuck: int = _rng.randi_range(0, GearModelRegistry.tuck_count() - 1)
		ref.set_tuck(tuck)
		port.set_tuck(tuck)
		_pose(rig_a, rig_b, base)
		ref.step(1.0 / 60.0, Vector3(0.0, -9.8, 0.0), false)
		var start: PackedVector3Array = _scatter(ref)
		var last_dt: float = _rng.randf_range(1.0 / 240.0, 1.0 / 20.0)
		ref.set_state(start, last_dt)
		port.set_state(start, last_dt)
		var steps: int = 1 if c < CASES else RUN_STEPS
		for s: int in steps:
			var dt: float = _rng.randf_range(1.0 / 240.0, 1.0 / 15.0)
			var g := Vector3(0.0, -9.8, 0.0) + _v(4.0)
			ref.step(dt, g, true)
			port.step(dt, g, true)
		var case_worst: float = _worst(ref, port, rig_a, rig_b, SkaterBodySkeleton.COLUMN_BONE_BASE)
		if case_worst > TOLERANCE:
			fail_test("case %d (tuck %d, %d steps, shear %.2f) differs by %.6f m" % [c, tuck, steps,
					shear, case_worst])
			return
		worst = maxf(worst, case_worst)
	assert_lt(worst, TOLERANCE, "worst over %d cases" % (CASES + RUNS))


func _keeper() -> Keeper:
	var keeper := Keeper.new()
	add_child_autofree(keeper)
	keeper.set_process(false)
	return keeper


func test_the_native_keeper_tail_matches_the_gdscript() -> void:
	if not ClassDB.class_exists(&"NativeHemFlaps"):
		NativeParityGuard.report_missing(self, "NativeHemFlaps")
		return
	_rng.seed = SEED
	var keeper_a: Keeper = _keeper()
	var keeper_b: Keeper = _keeper()
	var rig_a := keeper_a.find_child("BodyRig", true, false) as Skeleton3D
	var rig_b := keeper_b.find_child("BodyRig", true, false) as Skeleton3D
	var ref: HemFlaps = (keeper_a.find_child("JerseyTail", true, false) as KeeperJerseyTail).flaps
	var port: HemFlaps = (keeper_b.find_child("JerseyTail", true, false) as KeeperJerseyTail).flaps
	ref.native_enabled = false
	var posed: Array[int] = [KeeperGear.Part.CHEST]
	posed.append_array(KeeperTailColliders.PARTS)
	var base: Array[Transform3D] = []
	for bone: int in posed:
		base.append(rig_a.get_bone_pose(bone))
	var worst: float = 0.0
	for c: int in CASES + RUNS:
		for i: int in posed.size():
			# The thighs swing far enough to lift a guard through the cloth.
			var spread: float = 0.9 if i >= 2 else 0.3
			var pose: Transform3D = base[i] * Transform3D(Basis.from_euler(_v(spread)), _v(0.04))
			rig_a.set_bone_pose(posed[i], pose)
			rig_b.set_bone_pose(posed[i], pose)
		ref.restart()
		port.restart()
		ref.step(1.0 / 60.0, Vector3(0.0, -9.8, 0.0), false)
		var start: PackedVector3Array = _scatter(ref)
		var last_dt: float = _rng.randf_range(1.0 / 240.0, 1.0 / 20.0)
		ref.set_state(start, last_dt)
		port.set_state(start, last_dt)
		var steps: int = 1 if c < CASES else RUN_STEPS
		for s: int in steps:
			var dt: float = _rng.randf_range(1.0 / 240.0, 1.0 / 15.0)
			var g := Vector3(0.0, -9.8, 0.0) + _v(12.0)
			ref.step(dt, g, true)
			port.step(dt, g, true)
		var case_worst: float = _worst(ref, port, rig_a, rig_b, KeeperJerseyTail.first_flap_bone())
		if case_worst > TOLERANCE:
			fail_test("keeper case %d (%d steps) differs by %.6f m" % [c, steps, case_worst])
			return
		worst = maxf(worst, case_worst)
	assert_lt(worst, TOLERANCE, "worst over %d cases" % (CASES + RUNS))
