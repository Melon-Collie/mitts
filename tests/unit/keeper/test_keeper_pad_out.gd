extends GutTest

# A pad out along the ice while he is on his knees (KeeperPadOut): asked for a
# side it goes out in its time and comes back as quick, one side in before the
# other goes out, and in whenever the leg is not free; laid over the butterfly
# all the way out it is the butterfly extension; and laid over at every share
# his gear stays out of the ice.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const PAD_GIVE_M: float = 0.025
const HARD_GIVE_M: float = 0.005

var _pad: KeeperPadOut = null
var _pose := KeeperPose.new()
var _skel := KeeperSkeleton.new()


func before_each() -> void:
	_pad = KeeperPadOut.new()


func _steps(free: bool = true) -> float:
	var t: float = 0.0
	var was: float = _pad.share
	_pad.step(DT, free)
	while _pad.share != was and t < 2.0:
		was = _pad.share
		_pad.step(DT, free)
		t += DT
	return t + DT


func test_it_goes_out_in_its_time_and_comes_back_as_quick() -> void:
	_pad.asked = 1.0
	assert_almost_eq(_steps(), _pad.out_s, 2.0 * DT, "out")
	assert_eq(_pad.side, 1.0)
	assert_eq(_pad.share, 1.0)
	_pad.asked = 0.0
	assert_almost_eq(_steps(), _pad.out_s, 2.0 * DT, "back")
	assert_eq(_pad.side, 0.0, "in: no side")
	assert_eq(_pad.share, 0.0)


func test_one_side_comes_in_before_the_other_goes_out() -> void:
	_pad.asked = 1.0
	_steps()
	_pad.asked = -1.0
	_pad.step(DT, true)
	assert_eq(_pad.side, 1.0, "the pad that is out still the one out")
	assert_lt(_pad.share, 1.0, "coming in")
	while _pad.side == 1.0:
		_pad.step(DT, true)
	assert_eq(_pad.share, 0.0, "all the way in first")
	_pad.step(DT, true)
	assert_eq(_pad.side, -1.0, "then the other")
	assert_gt(_pad.share, 0.0)


func test_a_leg_that_is_not_free_comes_in() -> void:
	_pad.asked = 1.0
	_steps()
	assert_almost_eq(_steps(false), _pad.out_s, 2.0 * DT, "asked still, the leg needed: back in")
	assert_eq(_pad.share, 0.0)
	assert_eq(_pad.asked, 1.0, "what was asked is his controller's")
	_pad.step(DT, true)
	assert_gt(_pad.share, 0.0, "free again: out again")


func test_all_the_way_out_over_the_butterfly_is_the_extension() -> void:
	for side: float in [-1.0, 1.0]:
		_pad = KeeperPadOut.new()
		_pad.asked = side
		_steps()
		KeeperPoses.butterfly(_pose)
		_pad.lay_over(_pose)
		var taught := KeeperPose.new()
		KeeperPoses.butterfly_extension(taught, side)
		var leg: int = 0 if side < 0.0 else 1
		var what: String = "%+.0f" % side
		assert_almost_eq(_pose.legs[leg].knee, taught.legs[leg].knee, Vector3.ONE * 1e-6, "%s: the knee" % what)
		assert_almost_eq(_pose.legs[leg].ankle, taught.legs[leg].ankle, Vector3.ONE * 1e-6, "%s: the ankle" % what)
		assert_almost_eq(_pose.legs[1 - leg].knee, taught.legs[1 - leg].knee, Vector3.ONE * 1e-6,
				"%s: the other knee down under him" % what)
		assert_almost_eq(_pose.pelvis, taught.pelvis, Vector3.ONE * 1e-6, "%s: the hips" % what)
		assert_almost_eq(_pose.pelvis_rot, taught.pelvis_rot, Vector3.ONE * 1e-6, "%s: rolled over it" % what)
		assert_almost_eq(_pose.blade_center, taught.blade_center, Vector3.ONE * 1e-6, "%s: the blade" % what)


func test_on_the_way_out_his_gear_stays_out_of_the_ice() -> void:
	for side: float in [-1.0, 1.0]:
		_pad = KeeperPadOut.new()
		_pad.asked = side
		while _pad.share < 1.0:
			_pad.step(DT, true)
			KeeperPoses.butterfly(_pose)
			_pad.lay_over(_pose)
			_skel.pose(_pose)
			for part: int in KeeperGear.PART_COUNT:
				var t: Transform3D = KeeperGear.box(_skel, part)
				var h: Vector3 = KeeperGear.half_extents(part)
				var lowest: float = t.origin.y - absf(t.basis.x.y) * h.x - absf(t.basis.y.y) * h.y - absf(t.basis.z.y) * h.z
				var soft: bool = KeeperGear.save_part(part) == GoalieSaveRules.SavePart.PAD
				assert_gte(lowest, -(PAD_GIVE_M if soft else HARD_GIVE_M),
						"%+.0f share %.2f %s" % [side, _pad.share, KeeperGear.Part.keys()[part]])


func test_cut_it_is_gone() -> void:
	_pad.asked = 1.0
	_steps()
	_pad.cut()
	KeeperPoses.butterfly(_pose)
	var was := KeeperPose.new()
	KeeperPoses.butterfly(was)
	_pad.lay_over(_pose)
	assert_almost_eq(_pose.legs[1].ankle, was.legs[1].ankle, Vector3.ONE * 1e-6, "nothing laid over")
