extends GutTest

# The keeper's footwork (KeeperFootwork), the T-push and the shuffle: he gets
# to his spot in the time GoaliePushRules gives the move's push and stop,
# stopped on it; the push skate holds its place while it pushes; his skates
# stay on the ice and his gear out of it at every tick; nothing on him jumps
# between ticks; and once the stop has settled out of him he is in the ready
# stance.

const DT: float = 1.0 / 120.0
const PAD_GIVE_M: float = 0.025
const HARD_GIVE_M: float = 0.005
# A bone's travel in a tick, past which it has jumped: the recovering leg is
# the fastest thing on him, about 7 m/s at its peak.
const MAX_BONE_STEP_M: float = 0.1
const T_PUSH := KeeperFootwork.Move.T_PUSH
const SHUFFLE := KeeperFootwork.Move.SHUFFLE

var _fw: KeeperFootwork = null
var _pose := KeeperPose.new()
var _skel := KeeperSkeleton.new()


func before_each() -> void:
	_fw = KeeperFootwork.new()


func _go(kind: int, target: float) -> void:
	if kind == T_PUSH:
		_fw.push_to(target)
	else:
		_fw.shuffle_to(target)


func _solve() -> void:
	_fw.pose(_pose)
	_skel.pose(_pose)


func _lowest(part: int) -> float:
	var t: Transform3D = KeeperGear.box(_skel, part)
	var h: Vector3 = KeeperGear.half_extents(part)
	return t.origin.y - absf(t.basis.x.y) * h.x - absf(t.basis.y.y) * h.y - absf(t.basis.z.y) * h.z


# Steps him until he is set, at most `limit` seconds; the time it took.
func _run(limit: float = 3.0) -> float:
	var t: float = 0.0
	while _fw.phase != KeeperFootwork.Phase.SET and t < limit:
		_fw.step(DT)
		t += DT
	return t


func test_he_is_set_on_his_spot_in_the_push_rules_time() -> void:
	for kind: int in [T_PUSH, SHUFFLE]:
		for dist: float in [0.1, 0.4, 1.0, 1.8, -0.6]:
			_fw = KeeperFootwork.new()
			_go(kind, dist)
			var t: float = _run()
			var rules: float = GoaliePushRules.time_to_set(absf(dist), _fw.top_speed(), _fw.accel)
			var what: String = "%s %.2f m" % [KeeperFootwork.Move.keys()[kind], dist]
			assert_almost_eq(t, rules, 2.5 * DT, what)
			assert_eq(_fw.x, dist, "%s: on the spot" % what)
			assert_eq(_fw.speed, 0.0, "%s: stopped" % what)


func test_he_never_goes_past_his_top_speed_or_his_spot() -> void:
	for kind: int in [T_PUSH, SHUFFLE]:
		_fw = KeeperFootwork.new()
		_go(kind, 1.2)
		var top: float = _fw.top_speed()
		while _fw.phase != KeeperFootwork.Phase.SET:
			_fw.step(DT)
			assert_lte(_fw.speed, top + 1e-6)
			assert_lte(_fw.x, 1.2)
	assert_lt(KeeperFootwork.new().shuffle_speed, KeeperFootwork.new().t_push_speed,
			"a shuffle is the slower move")


func test_a_spot_the_other_way_mid_move_is_reached() -> void:
	for kind: int in [T_PUSH, SHUFFLE]:
		_fw = KeeperFootwork.new()
		_go(kind, 1.0)
		for i: int in 30:
			_fw.step(DT)
		_go(kind, -0.5)
		assert_lt(_run(), 3.0, "he gets there")
		assert_eq(_fw.x, -0.5)
		assert_eq(_fw.speed, 0.0)


# The T-push skate is where his push comes from: it does not move on the ice
# until the leg driving off it is out as far as it goes.
func test_the_t_push_skate_stays_on_its_plant_until_the_leg_is_out() -> void:
	_fw.push_to(1.0)
	var plant: float = -KeeperPoses.READY_SKATE_HALF_SPACING_M
	var reach: float = KeeperFootwork.TRAIL_REACH * (KeeperAnatomy.THIGH_M + KeeperAnatomy.SHIN_M)
	var planted_ticks: int = 0
	while true:
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


# A shuffle is strokes: in each the trail skate holds its place on the ice
# while the body passes over it, then slides back in under him. It never slides
# back against the push.
func test_the_shuffle_skate_holds_its_place_for_each_stroke() -> void:
	_fw.shuffle_to(1.2)
	_fw.step(DT)
	_solve()
	var was: float = _skel.xf[KeeperSkeleton.FOOT[0]].origin.x + _fw.x
	var hold_from: float = _fw.x
	var held_strokes: int = 0
	while _fw.phase == KeeperFootwork.Phase.PUSH:
		_fw.step(DT)
		_solve()
		var skate: float = _skel.xf[KeeperSkeleton.FOOT[0]].origin.x + _fw.x
		assert_gte(skate - was, -1e-5, "at x %.3f it never slides back" % _fw.x)
		if absf(skate - was) > 1e-5:
			if _fw.x - hold_from > 0.1:
				held_strokes += 1
			hold_from = _fw.x
		was = skate
	assert_gte(held_strokes, 2, "a 1.2 m shuffle is strokes, each held while he passes over it")


func test_the_shuffle_stays_square() -> void:
	_fw.shuffle_to(1.0)
	while _fw.phase != KeeperFootwork.Phase.SET:
		_fw.step(DT)
		_fw.pose(_pose)
		for side: int in 2:
			assert_almost_eq(_pose.legs[side].toe, KeeperPoses.ready_toe(-1.0 if side == 0 else 1.0),
					Vector3.ONE * 1e-4, "skate %d stays toed out as in the stance" % side)


func test_his_skates_stay_on_the_ice_and_his_gear_out_of_it() -> void:
	for kind: int in [T_PUSH, SHUFFLE]:
		for target: float in [1.0, -1.0]:
			_fw = KeeperFootwork.new()
			_go(kind, target)
			var trail: int = 0 if target > 0.0 else 1
			var what: String = "%s %+.0f" % [KeeperFootwork.Move.keys()[kind], target]
			for i: int in 120:
				_fw.step(DT)
				_solve()
				for part: int in KeeperGear.PART_COUNT:
					var soft: bool = KeeperGear.save_part(part) == GoalieSaveRules.SavePart.PAD
					assert_gte(_lowest(part), -(PAD_GIVE_M if soft else HARD_GIVE_M),
							"%s tick %d %s" % [what, i, KeeperGear.Part.keys()[part]])
				var lead_skate: int = KeeperGear.Part.SKATE_G + (1 - trail)
				assert_almost_eq(_lowest(lead_skate), 0.0, 0.005, "%s tick %d: the lead skate" % [what, i])
				var trail_lift: float = _lowest(KeeperGear.Part.SKATE_G + trail)
				assert_between(trail_lift, -0.005, KeeperFootwork.RECOVER_LIFT_M + 0.005,
						"%s tick %d: the trail skate is never more than lifted clear" % [what, i])
				if kind == T_PUSH and _fw.phase == KeeperFootwork.Phase.PUSH:
					assert_almost_eq(trail_lift, 0.0, 0.005, "%s tick %d: the push skate" % [what, i])


func test_nothing_on_him_jumps_between_ticks() -> void:
	for kind: int in [T_PUSH, SHUFFLE]:
		_fw = KeeperFootwork.new()
		_go(kind, 1.0)
		_solve()
		var was: Array[Vector3] = []
		for b: int in KeeperSkeleton.BONE_COUNT:
			was.append(_skel.xf[b].origin)
		for i: int in 120:
			_fw.step(DT)
			_solve()
			for b: int in KeeperSkeleton.BONE_COUNT:
				var at: Vector3 = _skel.xf[b].origin + Vector3(_fw.x, 0.0, 0.0)
				assert_lt(at.distance_to(was[b]), MAX_BONE_STEP_M,
						"%s tick %d bone %d" % [KeeperFootwork.Move.keys()[kind], i, b])
				was[b] = at


func test_the_t_push_lead_skate_turns_along_the_push_and_squares_to_stop() -> void:
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


# The stop shows as much as the speed it stops: a shuffle's is softer than a
# T-push's.
func test_a_slower_stop_leans_back_less() -> void:
	var ready := KeeperPose.new()
	KeeperPoses.ready(ready)
	var lean: Array[float] = []
	for kind: int in [T_PUSH, SHUFFLE]:
		_fw = KeeperFootwork.new()
		_go(kind, 1.5)
		_run()
		_fw.pose(_pose)
		lean.append(absf(_pose.lumbar_rot.z - ready.lumbar_rot.z))
	assert_gt(lean[0], lean[1], "the T-push stops harder than the shuffle")
	assert_gt(lean[1], 0.01, "the shuffle's stop still shows")


func test_set_and_settled_is_the_ready_stance() -> void:
	var ready := KeeperPose.new()
	KeeperPoses.ready(ready)
	for kind: int in [T_PUSH, SHUFFLE]:
		_fw = KeeperFootwork.new()
		_fw.pose(_pose)
		assert_eq(_pose.pelvis, ready.pelvis, "before he moves")
		_go(kind, 0.8)
		_run()
		for i: int in int(KeeperFootwork.SETTLE_S / DT) + 2:
			_fw.step(DT)
		_fw.pose(_pose)
		assert_eq(_pose.pelvis, ready.pelvis)
		assert_eq(_pose.lumbar_rot, ready.lumbar_rot)
		for side: int in 2:
			assert_eq(_pose.legs[side].ankle, ready.legs[side].ankle, "ankle %d" % side)
			assert_eq(_pose.legs[side].toe, ready.legs[side].toe, "toe %d" % side)
