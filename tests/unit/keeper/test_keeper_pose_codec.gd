extends GutTest

# His pose on the wire (KeeperPoseCodec): every taught stance and every tick of
# a sequence of his moves, written and read back, solves to the same body, each
# piece of gear where the host's was; the flags come back as they went; and a
# pose blended between two snapshots is each at its ends.

const DT: float = 1.0 / 120.0
# How far a piece of gear may lie from the host's once its pose has been on the
# wire: the quantization's millimetres and fraction of a degree carried out
# along a limb.
const GEAR_TOLERANCE_M: float = 0.01

var _skel := KeeperSkeleton.new()
var _back := KeeperSkeleton.new()
var _bytes := PackedByteArray()


func before_all() -> void:
	_bytes.resize(KeeperPoseCodec.SIZE)


# The worst distance between a piece of gear posed from `p` and from `p` after
# the wire.
func _worst_gear_m(p: KeeperPose) -> float:
	var read := KeeperPose.new()
	KeeperPoseCodec.write(p, _bytes, 0)
	KeeperPoseCodec.read(_bytes, 0, read)
	_skel.pose(p)
	_back.pose(read)
	var worst: float = 0.0
	for part: int in KeeperGear.PART_COUNT:
		var a: Transform3D = KeeperGear.box(_skel, part)
		var b: Transform3D = KeeperGear.box(_back, part)
		var h: Vector3 = KeeperGear.half_extents(part)
		# The box's corners, so a turn shows as much as a shift.
		for corner: int in 8:
			var c := Vector3(h.x * (1 if corner & 1 else -1), h.y * (1 if corner & 2 else -1),
					h.z * (1 if corner & 4 else -1))
			worst = maxf(worst, (a * c).distance_to(b * c))
	return worst


func test_every_stance_comes_back_the_same_body() -> void:
	var stances: Array = []
	for f: Callable in [KeeperPoses.ready, KeeperPoses.low_ready, KeeperPoses.butterfly, KeeperPoses.upright]:
		var p := KeeperPose.new()
		f.call(p)
		stances.append(p)
	for side: float in [-1.0, 1.0]:
		for f: Callable in [KeeperPoses.half_butterfly, KeeperPoses.butterfly_extension, KeeperPoses.kick,
				KeeperPoses.rvh, KeeperPoses.butterfly_push, KeeperPoses.half_butterfly_loaded]:
			var p := KeeperPose.new()
			f.call(p, side)
			stances.append(p)
	for i: int in stances.size():
		assert_lt(_worst_gear_m(stances[i]), GEAR_TOLERANCE_M, "stance %d" % i)


# His moves strung together, every tick: footwork, the drop, a slide, the post,
# a save with the hand out. Only a breach is asserted.
func test_every_tick_of_his_moves_comes_back_the_same_body() -> void:
	var motor := KeeperMotor.new()
	var save := KeeperSave.new()
	var p := KeeperPose.new()
	motor.go_to(Vector2(0.6, -1.2), -0.4)
	var worst: float = 0.0
	var steps: Array = [
		func() -> void: motor.go_to(Vector2(-0.5, -1.0), 0.3),
		func() -> void: motor.go_to(Vector2(0.0, -0.8), 0.0, KeeperRoute.Rest.DOWN),
		func() -> void: motor.seal(Vector2(GameRules.NET_HALF_WIDTH, 0.0), 1.0),
		func() -> void: motor.go_to(Vector2(0.0, -1.5), 0.0),
	]
	for step: Callable in steps:
		step.call()
		for i: int in 240:
			motor.step(DT)
			motor.pose(p)
			save.overlay(p)
			var off: float = _worst_gear_m(p)
			if off >= GEAR_TOLERANCE_M:
				assert_lt(off, GEAR_TOLERANCE_M, "tick %d" % i)
			worst = maxf(worst, off)
	gut.p("worst gear off after the wire: %.4f m" % worst)
	assert_lt(worst, GEAR_TOLERANCE_M)


func test_the_flags_come_back_as_they_went() -> void:
	var p := KeeperPose.new()
	KeeperPoses.rvh(p, 1.0)
	p.legs[0].knee_pinned = true
	p.legs[1].knee_pinned = false
	p.legs[0].foot_mode = KeeperPose.FootMode.ALONG_SHIN
	p.legs[1].foot_mode = KeeperPose.FootMode.FLAT
	p.glove_from_chest = true
	p.blocker_reach = true
	var read := KeeperPose.new()
	KeeperPoseCodec.write(p, _bytes, 0)
	KeeperPoseCodec.read(_bytes, 0, read)
	assert_true(read.legs[0].knee_pinned)
	assert_false(read.legs[1].knee_pinned)
	assert_eq(read.legs[0].foot_mode, KeeperPose.FootMode.ALONG_SHIN)
	assert_eq(read.legs[1].foot_mode, KeeperPose.FootMode.FLAT)
	assert_true(read.glove_from_chest)
	assert_true(read.blocker_reach)


# Blended, a pose is each snapshot at its ends; a target whose flag differs
# between them goes with its flag rather than blending across two frames.
func test_a_blend_is_each_pose_at_its_ends() -> void:
	var a := KeeperPose.new()
	var b := KeeperPose.new()
	KeeperPoses.ready(a)
	KeeperPoses.butterfly(b)
	a.glove_from_chest = false
	b.glove_from_chest = true
	var mid := KeeperPose.new()
	for end: Array in [[0.0, a], [1.0, b]]:
		mid.blend(a, b, end[0])
		var want: KeeperPose = end[1]
		_skel.pose(mid)
		_back.pose(want)
		for bone: int in KeeperSkeleton.BONE_COUNT:
			assert_almost_eq(_skel.xf[bone].origin, _back.xf[bone].origin, Vector3.ONE * 1e-5,
					"t %.0f bone %d" % [end[0], bone])
	mid.blend(a, b, 0.25)
	assert_false(mid.glove_from_chest, "a quarter of the way: the first's frame")
	assert_eq(mid.glove_hand, a.glove_hand, "and its hand there, not a blend of two frames")
	mid.blend(a, b, 0.75)
	assert_true(mid.glove_from_chest)
	assert_eq(mid.glove_hand, b.glove_hand)
