extends GutTest

# KeeperKneeShuffle: the steps his legs take under a scoot on his knees. At
# rest it changes nothing; scooting, the knee that is down stays where it is on
# the ice while the other steps over it, his knees never closer than the
# butterfly has them nor further apart than a stride more; a scoot the other
# way and a stop jump nothing, and stopped he is back in the butterfly.

const DT: float = 1.0 / 90.0
const MAX_BONE_STEP_M: float = 12.0 * DT  # nothing on him moves 12 m/s
const SPEED: float = KeeperSlide.KNEE_SHUFFLE_M_S

var _steps: KeeperKneeShuffle = null
var _down := KeeperPose.new()
var _pose := KeeperPose.new()
var _skel := KeeperSkeleton.new()
# How far he has scooted to his own right.
var _x: float = 0.0


func before_each() -> void:
	_steps = KeeperKneeShuffle.new()
	KeeperPoses.butterfly(_down)
	_x = 0.0


func _scoot(way: float) -> void:
	_x += way * SPEED * DT
	_steps.step(DT, way * SPEED * DT)
	_lay()


func _lay() -> void:
	_pose.copy_from(_down)
	_steps.lay_over(_pose)


func _bones() -> Array[Vector3]:
	_skel.pose(_pose)
	var out: Array[Vector3] = []
	for b: int in KeeperSkeleton.BONE_COUNT:
		out.append(_skel.xf[b].origin + Vector3(_x, 0.0, 0.0))
	return out


func _knee_on_the_ice(i: int) -> float:
	return _x + _pose.legs[i].knee.x


func test_at_rest_it_changes_nothing() -> void:
	for i: int in 30:
		_steps.step(DT, 0.0)
	_lay()
	for i: int in 2:
		assert_eq(_pose.legs[i].knee, _down.legs[i].knee, "knee %d" % i)
		assert_eq(_pose.legs[i].ankle, _down.legs[i].ankle, "ankle %d" % i)
	assert_eq(_pose.pelvis, _down.pelvis, "hips")
	assert_eq(_pose.pelvis_rot, _down.pelvis_rot, "hips' turn")


func test_the_knee_that_is_down_stays_where_it_is_on_the_ice() -> void:
	for way: float in [1.0, -1.0]:
		before_each()
		for i: int in ceili(KeeperKneeShuffle.SETTLE_S / DT):
			_scoot(way)
		var was: Array[float] = [_knee_on_the_ice(0), _knee_on_the_ice(1)]
		var stepped: Array[int] = [0, 0]
		var widest: float = 0.0
		for tick: int in ceili(4.0 * KeeperKneeShuffle.STRIDE_M / (SPEED * DT)):
			_scoot(way)
			var what: String = "%+.0f tick %d" % [way, tick]
			for i: int in 2:
				var up: float = _pose.legs[i].knee.y - _down.legs[i].knee.y
				assert_gte(up, -1e-6, "%s knee %d: never into the ice" % [what, i])
				assert_almost_eq(_pose.legs[i].ankle - _pose.legs[i].knee, _down.legs[i].ankle - _down.legs[i].knee,
						Vector3.ONE * 1e-6, "%s pad %d: moved whole" % [what, i])
				var at: float = _knee_on_the_ice(i)
				if up > 1e-4:
					stepped[i] += 1
					assert_gt(way * (at - was[i]), 0.0, "%s knee %d: off the ice, on the way he goes" % [what, i])
				elif absf(at - was[i]) > 1e-6:
					# The tick a step lands or lifts is part of the step.
					assert_lt(absf(at - was[i]), 2.0 * SPEED * DT + 1e-6, "%s knee %d: down, not dragged" % [what, i])
				was[i] = at
			assert_true(_pose.legs[0].knee.y - _down.legs[0].knee.y < 1e-4 or _pose.legs[1].knee.y - _down.legs[1].knee.y < 1e-4,
					"%s: one knee down" % what)
			var apart: float = (_pose.legs[1].knee.x - _pose.legs[0].knee.x) - (_down.legs[1].knee.x - _down.legs[0].knee.x)
			assert_gte(apart, -1e-6, "%s: never closer than the butterfly has them" % what)
			widest = maxf(widest, apart)
		assert_gt(stepped[0], 0, "%+.0f: the glove-side knee steps" % way)
		assert_gt(stepped[1], 0, "%+.0f: the blocker-side knee steps" % way)
		assert_almost_eq(widest, KeeperKneeShuffle.STRIDE_M, 0.02, "%+.0f: a stride apart at the widest" % way)


# A knee that is down holds its place through the whole of its turn down: over
# a pair of steps each knee is still on the ice for half of it.
func test_a_planted_knee_does_not_slide() -> void:
	for i: int in ceili(KeeperKneeShuffle.SETTLE_S / DT):
		_scoot(1.0)
	var still: Array[int] = [0, 0]
	var ticks: int = roundi(2.0 * KeeperKneeShuffle.STRIDE_M / (SPEED * DT))
	var was: Array[float] = [_knee_on_the_ice(0), _knee_on_the_ice(1)]
	for tick: int in ticks:
		_scoot(1.0)
		for i: int in 2:
			if absf(_knee_on_the_ice(i) - was[i]) < 1e-6:
				still[i] += 1
			was[i] = _knee_on_the_ice(i)
	for i: int in 2:
		assert_almost_eq(float(still[i]) / float(ticks), 0.5, 0.1, "knee %d still for half of it" % i)


func test_setting_off_turning_back_and_stopping_jump_nothing() -> void:
	_lay()
	var was: Array[Vector3] = _bones()
	var ways: Array[float] = []
	for i: int in 40:
		ways.append(1.0)
	for i: int in 33:
		ways.append(-1.0)
	for i: int in 17:
		ways.append(1.0)
	for i: int in 30:
		ways.append(0.0)
	for tick: int in ways.size():
		if ways[tick] == 0.0:
			_steps.step(DT, 0.0)
			_lay()
		else:
			_scoot(ways[tick])
		var at: Array[Vector3] = _bones()
		for b: int in KeeperSkeleton.BONE_COUNT:
			assert_lt(at[b].distance_to(was[b]), MAX_BONE_STEP_M, "tick %d bone %d" % [tick, b])
		was = at
	assert_eq(_steps.share, 0.0, "stopped: settled out of him")
	for i: int in 2:
		assert_eq(_pose.legs[i].knee, _down.legs[i].knee, "stopped: knee %d back in the butterfly" % i)


func test_a_save_cuts_it() -> void:
	for i: int in 20:
		_scoot(1.0)
	_steps.cut()
	_lay()
	assert_eq(_pose.legs[0].knee, _down.legs[0].knee, "nothing more laid over")
	assert_eq(_steps.share, 0.0)
