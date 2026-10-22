extends GutTest

# The keeper's T-push (KeeperFootwork): he gets to his spot in the time
# GoaliePushRules gives the push and stop, stopped on it; the push skate stays
# on its plant until the leg is out straight; his skates stay on the ice and
# his gear out of it at every tick; nothing on him jumps between ticks; and
# once the stop has settled out of him he is in the ready stance.

const DT: float = 1.0 / 120.0
const PAD_GIVE_M: float = 0.025
const HARD_GIVE_M: float = 0.005
# A bone's travel in a tick, past which it has jumped: the recovering leg is
# the fastest thing on him, about 7 m/s at its peak.
const MAX_BONE_STEP_M: float = 0.1

var _fw: KeeperFootwork = null
var _pose := KeeperPose.new()
var _skel := KeeperSkeleton.new()


func before_each() -> void:
	_fw = KeeperFootwork.new()


func _solve() -> void:
	_fw.pose(_pose)
	_skel.pose(_pose)


func _lowest(part: int) -> float:
	var t: Transform3D = KeeperGear.box(_skel, part)
	var h: Vector3 = KeeperGear.half_extents(part)
	return t.origin.y - absf(t.basis.x.y) * h.x - absf(t.basis.y.y) * h.y - absf(t.basis.z.y) * h.z


# Steps him until he is set, at most `limit` seconds; the time it took.
func _run(target: float, limit: float = 3.0) -> float:
	_fw.push_to(target)
	var t: float = 0.0
	while _fw.phase != KeeperFootwork.Phase.SET and t < limit:
		_fw.step(DT)
		t += DT
	return t


func test_he_is_set_on_his_spot_in_the_push_rules_time() -> void:
	for dist: float in [0.15, 0.4, 1.0, 1.8, -0.6]:
		_fw = KeeperFootwork.new()
		var t: float = _run(dist)
		var rules: float = GoaliePushRules.time_to_set(absf(dist), _fw.max_speed, _fw.accel)
		assert_almost_eq(t, rules, 2.5 * DT, "a push of %.2f m" % dist)
		assert_eq(_fw.x, dist, "%.2f m: on the spot" % dist)
		assert_eq(_fw.speed, 0.0, "%.2f m: stopped" % dist)


func test_he_never_goes_past_top_speed_or_his_spot() -> void:
	_fw.push_to(1.2)
	while _fw.phase != KeeperFootwork.Phase.SET:
		_fw.step(DT)
		assert_lte(_fw.speed, _fw.max_speed + 1e-6)
		assert_lte(_fw.x, 1.2)


func test_a_spot_the_other_way_mid_push_is_reached() -> void:
	_fw.push_to(1.0)
	for i: int in 30:
		_fw.step(DT)
	var t: float = _run(-0.5)
	assert_lt(t, 3.0, "he gets there")
	assert_eq(_fw.x, -0.5)
	assert_eq(_fw.speed, 0.0)


# The push skate is where his push comes from: it does not move on the ice
# until the leg driving off it is out as far as it goes.
func test_the_push_skate_stays_on_its_plant_until_the_leg_is_out() -> void:
	_fw.push_to(1.0)
	var plant: float = -KeeperPoses.READY_SKATE_HALF_SPACING_M
	var reach: float = KeeperFootwork.TRAIL_REACH * (KeeperAnatomy.THIGH_M + KeeperAnatomy.SHIN_M)
	var planted_ticks: int = 0
	while _fw.phase == KeeperFootwork.Phase.SET or _fw.phase == KeeperFootwork.Phase.PUSH:
		_fw.step(DT)
		if _fw.phase != KeeperFootwork.Phase.PUSH:
			break
		_solve()
		var hip: Vector3 = _skel.xf[KeeperSkeleton.THIGH[0]].origin
		var ankle: Vector3 = _skel.xf[KeeperSkeleton.FOOT[0]].origin
		if absf(ankle.x + _fw.x - plant) < 0.001:
			planted_ticks += 1
		else:
			assert_almost_eq(hip.distance_to(ankle), reach, 0.01,
					"off its plant at x %.3f only with the leg out" % _fw.x)
	assert_gt(planted_ticks, 20, "it is planted for most of the push")


func test_his_skates_stay_on_the_ice_and_his_gear_out_of_it() -> void:
	for target: float in [1.0, -1.0]:
		_fw = KeeperFootwork.new()
		_fw.push_to(target)
		var trail: int = 0 if target > 0.0 else 1
		for i: int in 120:
			_fw.step(DT)
			_solve()
			for part: int in KeeperGear.PART_COUNT:
				var soft: bool = KeeperGear.save_part(part) == GoalieSaveRules.SavePart.PAD
				assert_gte(_lowest(part), -(PAD_GIVE_M if soft else HARD_GIVE_M),
						"%+.0f tick %d %s" % [target, i, KeeperGear.Part.keys()[part]])
			var lead_skate: int = KeeperGear.Part.SKATE_G + (1 - trail)
			assert_almost_eq(_lowest(lead_skate), 0.0, 0.005, "%+.0f tick %d: the lead skate" % [target, i])
			if _fw.phase == KeeperFootwork.Phase.PUSH:
				assert_almost_eq(_lowest(KeeperGear.Part.SKATE_G + trail), 0.0, 0.005,
						"%+.0f tick %d: the push skate" % [target, i])


func test_nothing_on_him_jumps_between_ticks() -> void:
	_fw.push_to(1.0)
	_solve()
	var was: Array[Vector3] = []
	for b: int in KeeperSkeleton.BONE_COUNT:
		was.append(_skel.xf[b].origin)
	for i: int in 120:
		_fw.step(DT)
		_solve()
		for b: int in KeeperSkeleton.BONE_COUNT:
			var at: Vector3 = _skel.xf[b].origin + Vector3(_fw.x, 0.0, 0.0)
			assert_lt(at.distance_to(was[b]), MAX_BONE_STEP_M, "tick %d bone %d" % [i, b])
			was[b] = at


func test_the_lead_skate_turns_along_the_push_and_squares_to_stop() -> void:
	_fw.push_to(1.0)
	var turned: float = 0.0
	while _fw.phase != KeeperFootwork.Phase.SET:
		_fw.step(DT)
		_fw.pose(_pose)
		turned = maxf(turned, _pose.legs[1].toe.normalized().x)
	assert_gt(turned, 0.95, "the lead toe points along the push")
	_fw.pose(_pose)
	assert_almost_eq(_pose.legs[1].toe, KeeperPoses.ready_toe(1.0), Vector3.ONE * 1e-4,
			"square again once he is on his spot")


func test_set_and_settled_is_the_ready_stance() -> void:
	var ready := KeeperPose.new()
	KeeperPoses.ready(ready)
	_fw.pose(_pose)
	assert_eq(_pose.pelvis, ready.pelvis, "before he moves")
	_run(0.8)
	for i: int in int(KeeperFootwork.SETTLE_S / DT) + 2:
		_fw.step(DT)
	_fw.pose(_pose)
	assert_eq(_pose.pelvis, ready.pelvis)
	assert_eq(_pose.lumbar_rot, ready.lumbar_rot)
	for side: int in 2:
		assert_eq(_pose.legs[side].ankle, ready.legs[side].ankle, "ankle %d" % side)
		assert_eq(_pose.legs[side].toe, ready.legs[side].toe, "toe %d" % side)
