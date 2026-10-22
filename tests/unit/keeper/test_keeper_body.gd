extends GutTest

# The new keeper's body: the skeleton keeps a person's proportions in every
# taught stance, the gear stays inside the rule book and on top of the ice, the
# stick is one rigid piece with its blade flat, and the save boxes are the ones
# the contact test reads.

const B := KeeperSkeleton.Bone
const P := KeeperGear.Part
const IN_TO_M: float = 0.0254
# A pad's foam gives where its edge rests on the ice; nothing else may sink in.
const PAD_GIVE_M: float = 0.025
const HARD_GIVE_M: float = 0.005

var _pose := KeeperPose.new()
var _skel := KeeperSkeleton.new()


func _stances() -> Array:
	return [
		["upright", func(p: KeeperPose) -> void: KeeperPoses.upright(p)],
		["ready", func(p: KeeperPose) -> void: KeeperPoses.ready(p)],
		["butterfly", func(p: KeeperPose) -> void: KeeperPoses.butterfly(p)],
		["half L", func(p: KeeperPose) -> void: KeeperPoses.half_butterfly(p, -1.0)],
		["half R", func(p: KeeperPose) -> void: KeeperPoses.half_butterfly(p, 1.0)],
		["extension L", func(p: KeeperPose) -> void: KeeperPoses.butterfly_extension(p, -1.0)],
		["extension R", func(p: KeeperPose) -> void: KeeperPoses.butterfly_extension(p, 1.0)],
		["kick L", func(p: KeeperPose) -> void: KeeperPoses.kick(p, -1.0)],
		["kick R", func(p: KeeperPose) -> void: KeeperPoses.kick(p, 1.0)],
		["rvh L", func(p: KeeperPose) -> void: KeeperPoses.rvh(p, -1.0)],
		["rvh R", func(p: KeeperPose) -> void: KeeperPoses.rvh(p, 1.0)],
		["vh L", func(p: KeeperPose) -> void: KeeperPoses.vh(p, -1.0)],
		["vh R", func(p: KeeperPose) -> void: KeeperPoses.vh(p, 1.0)],
		["overlap L", func(p: KeeperPose) -> void: KeeperPoses.overlap(p, -1.0)],
		["overlap R", func(p: KeeperPose) -> void: KeeperPoses.overlap(p, 1.0)],
	]


func _solve(stance: Array) -> void:
	(stance[1] as Callable).call(_pose)
	_skel.pose(_pose)


func _lowest(part: int) -> float:
	var t: Transform3D = KeeperGear.box(_skel, part)
	var h: Vector3 = KeeperGear.half_extents(part)
	return t.origin.y - absf(t.basis.x.y) * h.x - absf(t.basis.y.y) * h.y - absf(t.basis.z.y) * h.z


func test_he_stands_six_four_on_his_skates() -> void:
	KeeperPoses.upright(_pose)
	_skel.pose(_pose)
	var skull_top: float = _skel.xf[B.HEAD].origin.y + KeeperAnatomy.SKULL_TOP_ABOVE_HEAD_M
	assert_almost_eq(skull_top, KeeperAnatomy.STATURE_M + KeeperAnatomy.SKATE_LIFT_M, 0.001,
			"barefoot stature plus the skate's lift")
	assert_almost_eq(_skel.xf[B.FOOT_G].origin.y, KeeperAnatomy.ANKLE_ON_SKATES_M, 0.001)


func test_every_stance_keeps_his_bones_their_length() -> void:
	for stance: Array in _stances():
		_solve(stance)
		for side: int in 2:
			var hip: Vector3 = _skel.xf[KeeperSkeleton.THIGH[side]].origin
			var knee: Vector3 = _skel.xf[KeeperSkeleton.SHIN[side]].origin
			var ankle: Vector3 = _skel.xf[KeeperSkeleton.FOOT[side]].origin
			assert_almost_eq(hip.distance_to(knee), KeeperAnatomy.THIGH_M, 0.001,
					"%s thigh %d" % [stance[0], side])
			assert_almost_eq(knee.distance_to(ankle), KeeperAnatomy.SHIN_M, 0.001,
					"%s shin %d" % [stance[0], side])
		for upper: int in [B.UPPER_ARM_G, B.UPPER_ARM_B]:
			var shoulder: Vector3 = _skel.xf[upper].origin
			var elbow: Vector3 = _skel.xf[upper + 1].origin
			assert_almost_eq(shoulder.distance_to(elbow), KeeperAnatomy.UPPER_ARM_M, 0.001,
					"%s upper arm" % stance[0])


func test_every_bone_is_a_rotation() -> void:
	for stance: Array in _stances():
		_solve(stance)
		for b: int in KeeperSkeleton.BONE_COUNT:
			var m: Basis = _skel.xf[b].basis
			var ortho: float = absf(m.x.dot(m.y)) + absf(m.y.dot(m.z)) + absf(m.z.dot(m.x))
			assert_lt(ortho, 1e-4, "%s bone %d is square" % [stance[0], b])
			assert_almost_eq(m.determinant(), 1.0, 1e-4, "%s bone %d is unit" % [stance[0], b])


func test_no_gear_sinks_into_the_ice() -> void:
	for stance: Array in _stances():
		_solve(stance)
		for part: int in KeeperGear.PART_COUNT:
			var soft: bool = KeeperGear.save_part(part) == GoalieSaveRules.SavePart.PAD
			assert_gte(_lowest(part), -(PAD_GIVE_M if soft else HARD_GIVE_M),
					"%s %s" % [stance[0], KeeperGear.Part.keys()[part]])


func test_his_skates_stand_on_the_ice_when_he_is_up() -> void:
	for stance: Array in _stances():
		_solve(stance)
		for side: int in 2:
			var leg: KeeperPose.Leg = _pose.legs[side]
			if leg.foot_mode != KeeperPose.FootMode.FLAT:
				continue
			var skate: int = P.SKATE_G if side == 0 else P.SKATE_B
			assert_almost_eq(_lowest(skate), 0.0, 0.005, "%s skate %d" % [stance[0], side])


func test_the_stick_is_rigid_and_its_blade_lies_flat() -> void:
	var lie: float = deg_to_rad(KeeperAnatomy.PADDLE_TO_BLADE_DEG)
	for stance: Array in _stances():
		_solve(stance)
		assert_almost_eq(_skel.stick_paddle_dir.angle_to(_skel.stick_blade_dir), lie, 1e-4,
				"%s: the lie" % stance[0])
		assert_almost_eq(_skel.stick_blade_dir.y, 0.0, 1e-6, "%s: blade along the ice" % stance[0])
		assert_almost_eq(_lowest(P.BLADE), 0.0, 0.001, "%s: blade on the ice" % stance[0])
		assert_almost_eq(_skel.grip.distance_to(_skel.stick_heel),
				KeeperAnatomy.GRIP_ALONG_STICK_M, 0.001, "%s: grip up the stick" % stance[0])
		assert_lt(_skel.stick_face.z, 0.0, "%s: the blade faces the shooter" % stance[0])
		assert_almost_eq(_skel.xf[B.HAND_B].origin.distance_to(_skel.grip), 0.0, 0.001,
				"%s: the blocker hand holds the grip" % stance[0])


func test_the_gear_is_inside_the_rule_book() -> void:
	assert_lte(KeeperAnatomy.PAD_WIDTH_M, 11.0 * IN_TO_M + 1e-4, "pads 11 in wide")
	assert_lte(KeeperAnatomy.BLOCKER_WIDTH_M, 8.0 * IN_TO_M + 1e-4, "blocker 8 in")
	assert_lte(KeeperAnatomy.BLOCKER_HEIGHT_M, 15.0 * IN_TO_M + 1e-4, "blocker 15 in")
	assert_lte(2.0 * (KeeperAnatomy.GLOVE_WIDTH_M + KeeperAnatomy.GLOVE_HEIGHT_M),
			45.0 * IN_TO_M + 1e-4, "trapper perimeter 45 in")
	assert_lte(KeeperAnatomy.BLADE_HEIGHT_M, 3.5 * IN_TO_M + 1e-4, "blade 3.5 in")
	assert_lte(KeeperAnatomy.PADDLE_WIDTH_M, 3.5 * IN_TO_M + 1e-4, "paddle 3.5 in")
	assert_lte(KeeperAnatomy.PADDLE_LENGTH_M, 26.0 * IN_TO_M + 1e-4, "paddle 26 in")
	assert_lte(KeeperAnatomy.THIGH_PAD_WIDTH_M, 10.0 * IN_TO_M + 1e-4, "thigh guard 10 in")
	for part: int in KeeperGear.PART_COUNT:
		var h: Vector3 = KeeperGear.half_extents(part)
		var key: String = KeeperGear.Part.keys()[part]
		match part:
			P.PAD_G, P.PAD_B, P.RISE_G, P.RISE_B:
				assert_almost_eq(h.x * 2.0, KeeperAnatomy.PAD_WIDTH_M, 1e-6, key)
			P.THIGH_G, P.THIGH_B:
				assert_almost_eq(h.x * 2.0, KeeperAnatomy.THIGH_PAD_WIDTH_M, 1e-6, key)
			P.BLOCKER:
				assert_almost_eq(h.x * 2.0, KeeperAnatomy.BLOCKER_WIDTH_M, 1e-6, key)
				assert_almost_eq(h.y * 2.0, KeeperAnatomy.BLOCKER_HEIGHT_M, 1e-6, key)
			P.BLADE:
				assert_almost_eq(h.y * 2.0, KeeperAnatomy.BLADE_HEIGHT_M, 1e-6, key)


# The packed rows are what GoalieContactDetector's kernel reads: basis columns,
# origin, half extents.
func test_the_packed_boxes_are_the_boxes() -> void:
	KeeperPoses.ready(_pose)
	_skel.pose(_pose)
	var to_world := Transform3D(Basis(Vector3.UP, PI), Vector3(1.0, 0.0, -26.0))
	var packed := PackedFloat32Array()
	var n: int = KeeperGear.fill_boxes(_skel, to_world, packed)
	assert_eq(n, KeeperGear.PART_COUNT)
	for part: int in n:
		var i: int = part * KeeperGear.FLOATS_PER_BOX
		var t: Transform3D = to_world * KeeperGear.box(_skel, part)
		var row := Transform3D(
				Basis(Vector3(packed[i], packed[i + 1], packed[i + 2]),
						Vector3(packed[i + 3], packed[i + 4], packed[i + 5]),
						Vector3(packed[i + 6], packed[i + 7], packed[i + 8])),
				Vector3(packed[i + 9], packed[i + 10], packed[i + 11]))
		assert_almost_eq(row.origin.distance_to(t.origin), 0.0, 1e-4, "origin %d" % part)
		assert_almost_eq(row.basis.x.distance_to(t.basis.x), 0.0, 1e-4, "basis %d" % part)
		assert_almost_eq(Vector3(packed[i + 12], packed[i + 13], packed[i + 14]).distance_to(
				KeeperGear.half_extents(part)), 0.0, 1e-6, "half extents %d" % part)


func test_a_shot_at_the_pad_is_a_pad_save() -> void:
	KeeperPoses.ready(_pose)
	_skel.pose(_pose)
	var out := SweptDiscOBB.Result.new()
	var scratch := SweptDiscOBB.Result.new()
	var pad: Transform3D = KeeperGear.box(_skel, P.PAD_G)
	var at: Vector3 = pad.origin
	var hit: int = KeeperGear.nearest(_skel, at + Vector3(0.0, 0.0, -3.0), at + Vector3(0.0, 0.0, 1.0),
			GameRules.PUCK_COLLISION_RADIUS, out, scratch)
	assert_true(hit >= 0)
	assert_eq(KeeperGear.save_part(hit), GoalieSaveRules.SavePart.PAD, "first contact is a pad")
	assert_lt(out.normal.z, 0.0, "off its face")


# Down, the knees close the five-hole: every puck along the ice from the shooter
# between the pads' outer ends meets him.
func test_the_butterfly_seals_the_ice() -> void:
	KeeperPoses.butterfly(_pose)
	_skel.pose(_pose)
	var out := SweptDiscOBB.Result.new()
	var scratch := SweptDiscOBB.Result.new()
	var y: float = GameRules.PUCK_COLLISION_HALF_HEIGHT
	var x: float = -0.60
	while x <= 0.60:
		var hit: int = KeeperGear.nearest(_skel, Vector3(x, y, -3.0), Vector3(x, y, 1.0),
				GameRules.PUCK_COLLISION_RADIUS, out, scratch)
		assert_true(hit >= 0, "a puck along the ice at x %.2f meets him" % x)
		x += 0.02


func _span_y(part: int) -> Vector2:
	var t: Transform3D = KeeperGear.box(_skel, part)
	var h: Vector3 = KeeperGear.half_extents(part)
	var e: float = absf(t.basis.x.y) * h.x + absf(t.basis.y.y) * h.y + absf(t.basis.z.y) * h.z
	return Vector2(t.origin.y - e, t.origin.y + e)


# Standing straight on his skates the pad runs from its boot, just off the ice
# over the skate's toe, to the rule's limit above the knee: 45% of the knee to
# the top of the pelvis.
func test_the_pad_is_cut_to_the_rule() -> void:
	KeeperPoses.upright(_pose)
	_skel.pose(_pose)
	for side: int in 2:
		var knee: float = _skel.xf[KeeperSkeleton.SHIN[side]].origin.y
		var top: float = _span_y(P.RISE_G + side).y
		assert_almost_eq(top - knee, 0.45 * KeeperAnatomy.KNEE_TO_PELVIS_TOP_M, 0.002,
				"pad top above the knee, side %d" % side)
		var bottom: float = minf(_span_y(P.PAD_G + side).x, _span_y(P.BOOT_G + side).x)
		assert_between(bottom, 0.0, 1.5 * IN_TO_M, "the boot rides just off the ice, side %d" % side)


# Down, each rise carries its pad on along the ice past the knee, and the two
# meet under him.
func test_the_butterfly_rises_lie_flat_and_meet() -> void:
	KeeperPoses.butterfly(_pose)
	_skel.pose(_pose)
	var inner: Array[float] = []
	for side: int in 2:
		var part: int = P.RISE_G + side
		assert_almost_eq(_span_y(part).x, 0.0, 0.01, "rise %d on the ice" % side)
		var t: Transform3D = KeeperGear.box(_skel, part)
		var tip: Vector3 = t * Vector3(0.0, KeeperGear.half_extents(part).y, 0.0)
		inner.append(tip.x)
	assert_gte(inner[0], inner[1], "the glove-side rise reaches the blocker side's: they meet")


# No goalie butterflies post to post: on the goal line his gear, skates and all,
# stops inside the posts, and the low corners are a shot's to find.
func test_the_butterfly_does_not_span_the_net() -> void:
	KeeperPoses.butterfly(_pose)
	_skel.pose(_pose)
	var reach: float = 0.0
	for part: int in KeeperGear.PART_COUNT:
		var t: Transform3D = KeeperGear.box(_skel, part)
		var h: Vector3 = KeeperGear.half_extents(part)
		reach = maxf(reach, absf(t.origin.x) + absf(t.basis.x.x) * h.x
				+ absf(t.basis.y.x) * h.y + absf(t.basis.z.x) * h.z)
	assert_lt(reach, GameRules.NET_HALF_WIDTH - GameRules.NET_POST_RADIUS,
			"his widest gear stops inside the post")
