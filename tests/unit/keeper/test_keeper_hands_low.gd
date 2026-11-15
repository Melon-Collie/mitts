extends GutTest

# His hands set low while he is down with a carrier in tight (KeeperHandsLow):
# asked for a height they come down to it at his hands' speed and back up as
# quick, and up whenever he is not free; all the way down the blocker's board
# rests on the pad and the stick still lies flat on the ice through his fist;
# on the way his gear stays out of the ice and nothing jumps; and set low,
# nothing a puck from in tight can lift beside him gets by above his glove's
# bottom edge, where the butterfly's own hands leave it open.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const PAD_GIVE_M: float = 0.025
const HARD_GIVE_M: float = 0.005
const MAX_BONE_STEP_M: float = 12.0 * DT  # nothing on him moves 12 m/s

var _hands: KeeperHandsLow = null
var _pose := KeeperPose.new()
var _skel := KeeperSkeleton.new()


func before_each() -> void:
	_hands = KeeperHandsLow.new()


func _solve() -> void:
	KeeperPoses.butterfly(_pose)
	_hands.lay_over(_pose)
	_skel.pose(_pose)


func _top(part: int) -> float:
	return _edge(part, 1.0)


# The top (`way` +1) or bottom (−1) of `part`'s box.
func _edge(part: int, way: float) -> float:
	var t: Transform3D = KeeperGear.box(_skel, part)
	var h: Vector3 = KeeperGear.half_extents(part)
	return t.origin.y + way * (absf(t.basis.x.y) * h.x + absf(t.basis.y.y) * h.y + absf(t.basis.z.y) * h.z)


func test_they_start_as_the_butterfly_holds_them() -> void:
	assert_eq(_hands.set_m, KeeperHandsLow.highest())
	assert_gt(KeeperHandsLow.highest(), KeeperHandsLow.lowest(), "lower than the butterfly holds them")
	var taught := KeeperPose.new()
	KeeperPoses.butterfly(taught)
	_solve()
	assert_true(KeeperPoseCodec.same(_pose, taught), "nothing laid over it")


func test_they_come_down_at_his_hands_speed_and_back_as_quick() -> void:
	var span: float = KeeperHandsLow.highest() - KeeperHandsLow.lowest()
	_hands.asked = 0.0
	var t: float = 0.0
	while _hands.set_m > KeeperHandsLow.lowest() and t < 2.0:
		var was: float = _hands.set_m
		_hands.step(DT, true)
		assert_lte(was - _hands.set_m, _hands.speed_m_s * DT + 1e-6, "no faster than his hands")
		t += DT
	assert_gte(t, span / _hands.speed_m_s - DT, "no sooner than his hands take all the way down")
	assert_lt(t, 2.5 * span / _hands.speed_m_s, "slowing into place, not much longer")
	assert_eq(_hands.set_m, KeeperHandsLow.lowest(), "no lower than they go")
	_hands.asked = KeeperHandsLow.highest()
	t = 0.0
	while _hands.set_m < KeeperHandsLow.highest() and t < 2.0:
		_hands.step(DT, true)
		t += DT
	assert_lt(t, 2.5 * span / _hands.speed_m_s, "and back up as quick")


func test_not_free_they_come_back_up_and_a_save_takes_them() -> void:
	_hands.asked = 0.0
	for i: int in 90:
		_hands.step(DT, true)
	assert_eq(_hands.set_m, KeeperHandsLow.lowest())
	_hands.step(DT, false)
	assert_gt(_hands.set_m, KeeperHandsLow.lowest(), "coming up while his body has something else to do")
	_hands.cut()
	assert_eq(_hands.set_m, KeeperHandsLow.highest(), "taken into the save's pose")


# Laid over a pose that holds the stick elsewhere (his fall into the
# butterfly), the fist comes down from where that pose holds it, so nothing
# jumps as he lands.
func test_the_fist_comes_down_from_wherever_the_pose_holds_the_stick() -> void:
	_hands.asked = 0.0
	for i: int in 180:
		_hands.step(DT, true)
	var falling := KeeperPose.new()
	var up := KeeperPose.new()
	var down := KeeperPose.new()
	KeeperPoses.low_ready(up)
	KeeperPoses.butterfly(down)
	var was := Vector3.INF
	for i: int in 21:
		falling.blend(up, down, i / 20.0)
		_skel.pose(falling)
		var held: Vector3 = _skel.grip
		_hands.lay_over(falling)
		_skel.pose(falling)
		assert_lt(_skel.grip.y, held.y - 0.05, "%d/20 of the way down: the fist below where the stance holds it" % i)
		if was != Vector3.INF:
			assert_lt(_skel.grip.distance_to(was), 0.08, "%d/20: no jump" % i)
		was = _skel.grip


func test_each_hand_is_set_no_higher_than_asked() -> void:
	var parts: Array[int] = [KeeperGear.Part.GLOVE, KeeperGear.Part.BLOCKER]
	_solve()
	var taught: Array[float] = [_top(parts[0]), _top(parts[1])]
	_hands.asked = 0.0
	for k: int in 180:
		_hands.step(DT, true)
	_solve()
	var low: Array[float] = [_top(parts[0]), _top(parts[1])]
	for i: int in range(0, 9):
		var at: float = lerpf(KeeperHandsLow.lowest(), KeeperHandsLow.highest(), i / 8.0)
		_hands.asked = at
		for k: int in 180:
			_hands.step(DT, true)
		_solve()
		for h: int in 2:
			var what: String = "%s set for %.2f m" % [KeeperGear.Part.keys()[parts[h]], at]
			assert_lte(_top(parts[h]), maxf(at, low[h]) + 0.03, "%s: its top no higher" % what)
			assert_lte(_top(parts[h]), taught[h] + 1e-4, "%s: never above where the butterfly holds it" % what)
			assert_gte(_top(parts[h]), minf(at, taught[h]) - 0.03, "%s: and no lower than that takes" % what)


func test_all_the_way_down_the_board_is_on_the_pad_and_the_stick_on_the_ice() -> void:
	_hands.asked = 0.0
	for i: int in 180:
		_hands.step(DT, true)
	_solve()
	KeeperPoses.butterfly(_pose)
	_skel.pose(_pose)
	var taught: Array[float] = [_edge(KeeperGear.Part.GLOVE, -1.0), _edge(KeeperGear.Part.BLOCKER, -1.0)]
	_solve()
	assert_lt(_edge(KeeperGear.Part.BLOCKER, -1.0), taught[1] - 0.1, "the board well down toward the pad")
	assert_gt(_edge(KeeperGear.Part.BLOCKER, -1.0), KeeperAnatomy.PAD_WIDTH_M, "not into it")
	assert_lt(_edge(KeeperGear.Part.GLOVE, -1.0), taught[0] - 0.25, "the glove well down toward the pad")
	assert_gt(_edge(KeeperGear.Part.GLOVE, -1.0), KeeperAnatomy.PAD_WIDTH_M - PAD_GIVE_M, "resting on it, no deeper than its foam gives")
	assert_lt(_edge(KeeperGear.Part.BLADE, -1.0), 0.02, "the blade still on the ice")
	assert_gt(_edge(KeeperGear.Part.BLADE, -1.0), -HARD_GIVE_M, "and not in it")
	assert_lt(_edge(KeeperGear.Part.BLADE, 1.0), 0.12, "lying flat")
	assert_lt(_skel.grip.distance_to(_skel.xf[KeeperSkeleton.Bone.HAND_B].origin), 0.02, "his fist on it")


func test_on_the_way_his_gear_stays_out_of_the_ice_and_nothing_jumps() -> void:
	_solve()
	var bones: Array[Vector3] = []
	for b: int in KeeperSkeleton.BONE_COUNT:
		bones.append(_skel.xf[b].origin)
	for asked: float in [0.0, KeeperHandsLow.highest()]:
		_hands.asked = asked
		for i: int in 60:
			_hands.step(DT, true)
			_solve()
			for part: int in KeeperGear.PART_COUNT:
				var soft: bool = KeeperGear.save_part(part) == GoalieSaveRules.SavePart.PAD
				assert_gte(_edge(part, -1.0), -(PAD_GIVE_M if soft else HARD_GIVE_M),
						"set %.2f %s" % [_hands.set_m, KeeperGear.Part.keys()[part]])
			for b: int in KeeperSkeleton.BONE_COUNT:
				assert_lt(_skel.xf[b].origin.distance_to(bones[b]), MAX_BONE_STEP_M, "set %.2f bone %d" % [_hands.set_m, b])
				bones[b] = _skel.xf[b].origin


# A puck in tight, straight on, lifted as high as a shot from there goes, at
# the net beside him on either side: the lines that pass him above his glove's
# bottom edge. The butterfly's hands leave some open; set low, none.
func test_set_low_nothing_lifted_from_in_tight_gets_by_beside_him() -> void:
	var out := SweptDiscOBB.Result.new()
	var scratch := SweptDiscOBB.Result.new()
	var lift: float = PlayerAttributes.steepest_loft_tan()
	for far: float in [3.0, 3.5]:
		var depth: float = KeeperPositioning.closing_depth(Vector2(0.0, -far))
		var release := Vector3(0.0, GameRules.PUCK_COLLISION_HALF_HEIGHT, -(far - depth))
		var open: Array[int] = [0, 0]
		for low: int in 2:
			_hands = KeeperHandsLow.new()
			if low == 1:
				_hands.asked = release.y + lift * (far - depth)
				for i: int in 180:
					_hands.step(DT, true)
			_solve()
			var hands_z: float = KeeperGear.box(_skel, KeeperGear.Part.GLOVE).origin.z
			var floor_y: float = _edge(KeeperGear.Part.GLOVE, -1.0) if low == 1 else KeeperAnatomy.PAD_WIDTH_M
			var x: float = 0.5
			while x <= KeeperCoverage.MOUTH_HALF_M + 1e-6:
				var y: float = release.y
				while y <= release.y + lift * far:
					for side: float in [-1.0, 1.0]:
						var target := Vector3(side * x, y, depth)
						var by_him: float = lerpf(release.y, y, (hands_z - release.z) / (depth - release.z))
						if by_him >= floor_y + GameRules.PUCK_COLLISION_HALF_HEIGHT \
								and KeeperGear.nearest(_skel, release, target, GameRules.PUCK_COLLISION_RADIUS, out, scratch) < 0:
							open[low] += 1
					y += 0.04
				x += 0.04
		assert_gt(open[0], 0, "%.1f m: the butterfly's own hands leave it open beside him" % far)
		assert_eq(open[1], 0, "%.1f m: set low, nothing above his glove's bottom gets by" % far)
