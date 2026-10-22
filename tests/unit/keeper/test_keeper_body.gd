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


# The skeleton has no hand bone: each forearm is aimed at its hand and stops at
# the wrist, so a hand held in reach ends at most a palm past it. Further, the
# hand is drawn floating off the arm. Standing straight up nobody reaches a
# stick lying flat on the ice, so the upright reference is not held to it.
func test_every_arm_reaches_its_hand() -> void:
	for stance: Array in _stances():
		if stance[0] == "upright":
			continue
		_solve(stance)
		var glove_wrist: Vector3 = _skel.xf[B.FOREARM_G] * Vector3(0.0, -KeeperAnatomy.FOREARM_M, 0.0)
		var blocker_wrist: Vector3 = _skel.xf[B.FOREARM_B] * Vector3(0.0, -KeeperAnatomy.FOREARM_M, 0.0)
		assert_almost_eq(glove_wrist.distance_to(_skel.xf[B.HAND_G].origin), 0.0, 0.002,
				"%s: the glove arm reaches its hand" % stance[0])
		# The fist holds the stick, so the forearm must reach the wrist on it: the
		# glove's cuff has no slack to hide a gap.
		assert_almost_eq(blocker_wrist.distance_to(_skel.xf[B.HAND_B] * KeeperAnatomy.BLOCKER_WRIST),
				0.0, 0.002, "%s: the blocker arm reaches the wrist on the fist" % stance[0])


# The skate never comes up through the pad's toe over it: its cowling, toe and
# instep, stays under the toe's top, inside its sides and behind its front. It
# may show beneath it: the toe is the pad's, rigid with it, and where the foot
# points down under the shin the skate drops out from under it, as a real
# one's does.
func test_no_skate_comes_through_its_boot() -> void:
	for stance: Array in _stances():
		_solve(stance)
		for side: int in 2:
			var skate: Transform3D = KeeperGear.box(_skel, P.SKATE_G + side)
			var sh: Vector3 = KeeperGear.half_extents(P.SKATE_G + side)
			var boot: Transform3D = KeeperGear.box(_skel, P.BOOT_G + side)
			var bh: Vector3 = KeeperGear.half_extents(P.BOOT_G + side)
			var cowling_top: float = -sh.y + KeeperAnatomy.SKATE_LIFT_M + KeeperGearMeshes.SKATE_COWLING_TOP_M
			for x: float in [-sh.x, sh.x]:
				for z: float in [-sh.z * 0.9, -sh.z * 0.5]:
					var local: Vector3 = boot.affine_inverse() * (skate * Vector3(x, cowling_top, z))
					var through := Vector3(maxf(absf(local.x) - bh.x, 0.0), maxf(local.y - bh.y, 0.0),
							maxf(-local.z - bh.z, 0.0))
					assert_lt(through.length(), 0.002, "%s side %d: the skate stays under its boot"
							% [stance[0], side])


# A wrist bends back and to the sides, not through the hand: the forearm goes
# into the trapper at its cuff or its back, never through its fingers, and into
# the blocker from behind the board, never through it.
func test_every_forearm_goes_into_its_glove_from_the_wrist() -> void:
	for stance: Array in _stances():
		if stance[0] == "upright":
			continue
		_solve(stance)
		var glove: Basis = _skel.xf[B.HAND_G].basis
		var into_glove: Vector3 = (glove.inverse() * -_skel.xf[B.FOREARM_G].basis.y).normalized()
		assert_lt(into_glove.y, 0.5, "%s: the forearm comes into the trapper from its cuff or back" % stance[0])
		var blocker: Basis = _skel.xf[B.HAND_B].basis
		var into_blocker: Vector3 = (blocker.inverse() * -_skel.xf[B.FOREARM_B].basis.y).normalized()
		assert_lt(into_blocker.z, 0.5, "%s: the forearm comes into the blocker from behind its board" % stance[0])


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
			P.PADDLE, P.SHAFT:
				# Measured up the stick from the heel, as the rule measures.
				_solve(_stances()[1])
				var along: float = (KeeperGear.box(_skel, part).origin - _skel.stick_heel) \
						.dot(_skel.stick_paddle_dir) + h.y
				var limit: float = KeeperAnatomy.PADDLE_LENGTH_M if part == P.PADDLE \
						else KeeperAnatomy.STICK_LENGTH_M
				assert_almost_eq(along, limit, 1e-4, "%s ends where its length says" % key)


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


# Extended, the leg runs out straight and its knee leaves the middle: the rise
# along the ice must still meet the paddle, or the push opens the five-hole.
func test_the_extension_seals_the_ice() -> void:
	for side: float in [-1.0, 1.0]:
		KeeperPoses.butterfly_extension(_pose, side)
		_skel.pose(_pose)
		_assert_seals_ice("extension %+.0f" % side, side, -0.60, 0.90)


# Kicked, the blade meets the kicking pad and the support pad meets the blade:
# no puck along the ice gets between his skates.
func test_the_kick_seals_the_ice() -> void:
	for side: float in [-1.0, 1.0]:
		KeeperPoses.kick(_pose, side)
		_skel.pose(_pose)
		_assert_seals_ice("kick %+.0f" % side, side, -0.35, 0.80)


# On the post in the RVH, from a sharp angle — a shooter 15° off the goal line
# on that side — no puck along the ice gets between him and the iron, nor
# along the line for a metre in from it.
func test_the_rvh_seals_the_post() -> void:
	var out := SweptDiscOBB.Result.new()
	var scratch := SweptDiscOBB.Result.new()
	var y: float = GameRules.PUCK_COLLISION_HALF_HEIGHT
	var inner: float = GameRules.NET_HALF_WIDTH - GameRules.NET_POST_RADIUS
	for side: float in [-1.0, 1.0]:
		KeeperPoses.rvh(_pose, side)
		_skel.pose(_pose)
		var post: Vector3 = KeeperGear.post_contact(_skel, side)
		var shooter := Vector3(post.x + side * (4.5 - inner), y,
				post.z - 4.5 * tan(deg_to_rad(15.0)))
		var d: float = 0.0
		while d <= 1.0:
			var on_line := Vector3(post.x - side * d, y, post.z)
			var past: Vector3 = on_line + (on_line - shooter).normalized() * 0.3
			var hit: int = KeeperGear.nearest(_skel, shooter, past, GameRules.PUCK_COLLISION_RADIUS,
					out, scratch)
			assert_true(hit >= 0, "rvh %+.0f: a puck along the ice %.2f m in from the post meets him"
					% [side, d])
			d += 0.02


# Every puck along the ice from the shooter, `from` to `to` metres across
# toward `side`, meets him.
func _assert_seals_ice(stance: String, side: float, from: float, to: float) -> void:
	var out := SweptDiscOBB.Result.new()
	var scratch := SweptDiscOBB.Result.new()
	var y: float = GameRules.PUCK_COLLISION_HALF_HEIGHT
	var x: float = from
	while x <= to:
		var hit: int = KeeperGear.nearest(_skel, Vector3(side * x, y, -3.0),
				Vector3(side * x, y, 1.0), GameRules.PUCK_COLLISION_RADIUS, out, scratch)
		assert_true(hit >= 0, "%s: a puck along the ice at x %.2f meets him" % [stance, side * x])
		x += 0.02


func _span_y(part: int) -> Vector2:
	var t: Transform3D = KeeperGear.box(_skel, part)
	var h: Vector3 = KeeperGear.half_extents(part)
	var e: float = absf(t.basis.x.y) * h.x + absf(t.basis.y.y) * h.y + absf(t.basis.z.y) * h.z
	return Vector2(t.origin.y - e, t.origin.y + e)


# Standing straight on his skates the pad runs to the rule's limit above the
# knee: 45% of the knee to the top of the pelvis. In his stance, which its toe
# is built for, it runs down to just off the ice over the skate's toe, its
# inside corner resting on it.
func test_the_pad_is_cut_to_the_rule() -> void:
	KeeperPoses.upright(_pose)
	_skel.pose(_pose)
	for side: int in 2:
		var knee: float = _skel.xf[KeeperSkeleton.SHIN[side]].origin.y
		var top: float = _span_y(P.RISE_G + side).y
		assert_almost_eq(top - knee, 0.45 * KeeperAnatomy.KNEE_TO_PELVIS_TOP_M, 0.002,
				"pad top above the knee, side %d" % side)
	KeeperPoses.ready(_pose)
	_skel.pose(_pose)
	for side: int in 2:
		var bottom: float = minf(_span_y(P.PAD_G + side).x, _span_y(P.BOOT_G + side).x)
		assert_between(bottom, -PAD_GIVE_M, 1.5 * IN_TO_M,
				"in the stance the boot rides just off the ice, side %d" % side)


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


# The stick passes in front of the pads, never through them: in every stance
# no point on the paddle's or the shaft's centre line lies inside a piece of
# leg gear (a centimetre's give for a stick resting on a face).
func test_the_stick_never_passes_through_his_legs() -> void:
	var legs: Array[int] = [P.PAD_G, P.PAD_B, P.RISE_G, P.RISE_B, P.BOOT_G, P.BOOT_B,
			P.THIGH_G, P.THIGH_B]
	var give := Vector3(0.01, 0.01, 0.01)
	var reach: float = KeeperAnatomy.PADDLE_LENGTH_M + KeeperAnatomy.SHAFT_LENGTH_M
	for stance: Array in _stances():
		_solve(stance)
		var along: float = 0.05
		while along <= reach:
			var at: Vector3 = _skel.stick_heel + _skel.stick_paddle_dir * along
			for part: int in legs:
				var local: Vector3 = KeeperGear.box(_skel, part).affine_inverse() * at
				var h: Vector3 = KeeperGear.half_extents(part) - give
				var inside: bool = absf(local.x) < h.x and absf(local.y) < h.y and absf(local.z) < h.z
				assert_false(inside, "%s: the stick %.2f m up its length is inside %s"
						% [stance[0], along, KeeperGear.Part.keys()[part]])
			along += 0.03
