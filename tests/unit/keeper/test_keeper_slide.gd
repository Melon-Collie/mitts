extends GutTest

# The keeper's butterfly slide (KeeperSlide), from the butterfly and from his
# feet by the half butterfly: he comes to rest on his spot in
# the time the slide model gives, or at the push's reach; once pushed, the
# pads' friction slows him and then the lead skate's edge stops him, quicker
# than friction alone; the push skate holds its place while it drives; the lead
# pad stays down on the ice the whole way, and both are down through the stop;
# it starts and ends in the butterfly; and every tick keeps his gear out of the
# ice, his arms on the stick and nothing on him jumping.

const DT: float = 1.0 / 120.0
const PAD_GIVE_M: float = 0.025
const HARD_GIVE_M: float = 0.005
const MAX_BONE_STEP_M: float = 0.1
const B := KeeperSkeleton.Bone
const P := KeeperGear.Part

var _slide: KeeperSlide = null
var _pose := KeeperPose.new()
var _skel := KeeperSkeleton.new()


func before_each() -> void:
	_slide = KeeperSlide.new()


func _lowest(part: int) -> float:
	var t: Transform3D = KeeperGear.box(_skel, part)
	var h: Vector3 = KeeperGear.half_extents(part)
	return t.origin.y - absf(t.basis.x.y) * h.x - absf(t.basis.y.y) * h.y - absf(t.basis.z.y) * h.z


func _solve() -> void:
	_slide.pose(_pose)
	_skel.pose(_pose)


# Steps until he is down and at rest, at most `limit` seconds; the time it took.
func _run(limit: float = 3.0) -> float:
	var t: float = 0.0
	while t < limit:
		_slide.step(DT)
		t += DT
		if _slide.phase == KeeperSlide.Phase.DOWN:
			break
	return t


func _bones() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for b: int in KeeperSkeleton.BONE_COUNT:
		out.append(_skel.xf[b].origin + Vector3(_slide.x, 0.0, 0.0))
	return out


func _start(target: float, from_feet: bool) -> float:
	return _slide.slide_from_feet(target) if from_feet else _slide.slide_to(target)


func _how(from_feet: bool) -> String:
	return "from his feet" if from_feet else "from the butterfly"


func test_he_comes_to_rest_on_his_spot_in_the_slides_time() -> void:
	for from_feet: bool in [false, true]:
		for dist: float in [0.2, 0.6, 1.0, -1.3]:
			_slide = KeeperSlide.new()
			var what: String = "%s %.1f m" % [_how(from_feet), dist]
			assert_eq(_start(dist, from_feet), dist, "%s is within reach" % what)
			var t: float = _run()
			# Each phase ends on a whole tick.
			assert_almost_eq(t, _slide.time_to(absf(dist), INF, from_feet), 2.5 * DT, what)
			assert_eq(_slide.x, dist, "%s: on the spot" % what)
			assert_eq(_slide.speed, 0.0)


func test_past_the_hardest_push_he_comes_to_rest_at_its_reach() -> void:
	var reach: float = _slide.glide_reach(_slide.push_speed)
	assert_almost_eq(_slide.slide_to(3.0), reach, 1e-6, "says where he will stop")
	_run()
	assert_almost_eq(_slide.x, reach, 1e-6)


# Once pushed he cannot steer: the pads' friction slows him, and then the lead
# skate's edge stops him, each at its own rate; nothing speeds him up.
func test_once_pushed_friction_then_the_edge_slows_him() -> void:
	_slide.slide_to(1.2)
	var top: float = 0.0
	var was: float = 0.0
	var was_phase: int = _slide.phase
	var glided: int = 0
	var stopped: int = 0
	while _slide.phase != KeeperSlide.Phase.DOWN:
		_slide.step(DT)
		top = maxf(top, _slide.speed)
		if was_phase == _slide.phase and was > 0.2 and _slide.speed > 0.2:
			var decel: float = (was - _slide.speed) / DT
			if _slide.phase == KeeperSlide.Phase.GLIDE:
				assert_almost_eq(decel, _slide.friction, _slide.friction * 0.05, "gliding at x %.3f" % _slide.x)
				glided += 1
			elif _slide.phase == KeeperSlide.Phase.STOP:
				var brake: float = _slide.friction + _slide.edge_brake
				assert_almost_eq(decel, brake, brake * 0.05, "stopping at x %.3f" % _slide.x)
				stopped += 1
		was_phase = _slide.phase
		was = _slide.speed
	assert_gt(glided, 10, "a glide")
	assert_gt(stopped, 10, "a stop")
	assert_lte(top, _slide.push_speed + 1e-6)


# The edge stop is what makes a slide a push and a stop: to the same spot,
# quicker than the softer push friction alone would stop on it.
func test_the_edge_stop_beats_coasting_to_the_spot() -> void:
	for dist: float in [0.5, 1.0, 1.5]:
		var coast := KeeperSlide.new()
		coast.edge_brake = 0.0
		assert_lt(_slide.time_to(dist), coast.time_to(dist) - 0.1, "%.1f m" % dist)


func test_a_softer_push_is_a_slower_slide() -> void:
	assert_gt(_slide.time_to(1.0, 2.4), _slide.time_to(1.0), "pushing at 2.4 m/s")
	assert_eq(_slide.slide_to(1.0, 2.4), 1.0, "still within its reach")
	var top: float = 0.0
	while _slide.phase != KeeperSlide.Phase.DOWN:
		_slide.step(DT)
		top = maxf(top, _slide.speed)
	assert_almost_eq(top, 2.4, 1e-6)
	assert_eq(_slide.x, 1.0)


func test_the_push_skate_holds_its_place_while_it_drives() -> void:
	_slide.slide_to(1.0)
	var planted: float = NAN
	var ticks: int = 0
	while _slide.phase != KeeperSlide.Phase.GLIDE:
		_slide.step(DT)
		if _slide.phase != KeeperSlide.Phase.PUSH:
			continue
		_solve()
		assert_almost_eq(_lowest(P.SKATE_G), 0.0, 0.005, "its skate is on the ice")
		var at: float = _skel.xf[KeeperSkeleton.FOOT[0]].origin.x + _slide.x
		if is_nan(planted):
			planted = at
		assert_almost_eq(at, planted, 0.001, "at x %.3f it holds" % _slide.x)
		ticks += 1
	assert_gt(ticks, 10, "a push, not a flick")


# From his feet the push skate is where his push comes from from the start:
# it holds its place on the ice from the drop's first frame to the push's last,
# while the lead knee falls; and he starts from the ready stance.
func test_from_his_feet_the_push_skate_never_leaves_its_spot() -> void:
	var ready := KeeperPose.new()
	KeeperPoses.ready(ready)
	var skel := KeeperSkeleton.new()
	skel.pose(ready)
	_slide.slide_from_feet(1.0)
	_solve()
	for b: int in KeeperSkeleton.BONE_COUNT:
		assert_almost_eq(_skel.xf[b].origin, skel.xf[b].origin, Vector3.ONE * 1e-3, "bone %d starts standing" % b)
	var planted: float = _skel.xf[KeeperSkeleton.FOOT[0]].origin.x
	var ticks: int = 0
	while _slide.phase == KeeperSlide.Phase.DROP or _slide.phase == KeeperSlide.Phase.PUSH:
		_slide.step(DT)
		_solve()
		if _slide.phase == KeeperSlide.Phase.GLIDE:
			break
		assert_almost_eq(_lowest(P.SKATE_G), 0.0, 0.005, "at x %.3f its skate is on the ice" % _slide.x)
		assert_almost_eq(_skel.xf[KeeperSkeleton.FOOT[0]].origin.x + _slide.x, planted, 0.001,
				"%s at x %.3f it holds" % [KeeperSlide.Phase.keys()[_slide.phase], _slide.x])
		ticks += 1
	assert_gt(ticks, 30, "the drop and the push")


# The lead pad seals the ice it slides along: down on it every tick, from the
# moment its knee lands.
func test_the_lead_pad_stays_down_on_the_ice() -> void:
	for from_feet: bool in [false, true]:
		for target: float in [1.0, -1.0]:
			_slide = KeeperSlide.new()
			_start(target, from_feet)
			var lead: int = P.PAD_B if target > 0.0 else P.PAD_G
			var push: int = P.PAD_G if target > 0.0 else P.PAD_B
			var what: String = "%s %+.0f" % [_how(from_feet), target]
			while _slide.phase != KeeperSlide.Phase.DOWN:
				_slide.step(DT)
				_solve()
				if _slide.phase == KeeperSlide.Phase.DROP:
					continue
				assert_between(_lowest(lead), -PAD_GIVE_M, 0.01,
						"%s at x %.3f: the lead pad is on the ice" % [what, _slide.x])
				if _slide.phase == KeeperSlide.Phase.STOP and _slide.speed < 1.0:
					assert_between(_lowest(push), -PAD_GIVE_M, 0.01,
							"%s at x %.3f: the push pad is back down, sealing" % [what, _slide.x])


func test_it_starts_and_ends_in_the_butterfly() -> void:
	var fly := KeeperPose.new()
	KeeperPoses.butterfly(fly)
	var skel := KeeperSkeleton.new()
	skel.pose(fly)
	_slide.slide_to(0.8)
	_slide.step(1e-6)
	_solve()
	for b: int in KeeperSkeleton.BONE_COUNT:
		assert_almost_eq(_skel.xf[b].origin, skel.xf[b].origin, Vector3.ONE * 1e-3, "bone %d starts down" % b)
	_run()
	for i: int in int(KeeperSlide.SETTLE_S / DT) + 2:
		_slide.step(DT)
	_solve()
	for b: int in KeeperSkeleton.BONE_COUNT:
		assert_almost_eq(_skel.xf[b].origin, skel.xf[b].origin, Vector3.ONE * 1e-6, "bone %d ends down" % b)


func test_every_tick_keeps_his_gear_out_of_the_ice_his_arms_on_the_stick_and_nothing_jumping() -> void:
	for from_feet: bool in [false, true]:
		for target: float in [1.0, -1.6]:
			_check_every_tick(target, from_feet)


func _check_every_tick(target: float, from_feet: bool) -> void:
	_slide = KeeperSlide.new()
	_start(target, from_feet)
	_solve()
	var was: Array[Vector3] = _bones()
	while _slide.phase != KeeperSlide.Phase.DOWN:
		_slide.step(DT)
		_solve()
		var when: String = "%s %+.1f %s x %.3f" % [_how(from_feet), target,
				KeeperSlide.Phase.keys()[_slide.phase], _slide.x]
		for part: int in KeeperGear.PART_COUNT:
			var soft: bool = KeeperGear.save_part(part) == GoalieSaveRules.SavePart.PAD
			assert_gte(_lowest(part), -(PAD_GIVE_M if soft else HARD_GIVE_M),
					"%s %s" % [when, KeeperGear.Part.keys()[part]])
		var glove_wrist: Vector3 = _skel.xf[B.FOREARM_G] * Vector3(0.0, -KeeperAnatomy.FOREARM_M, 0.0)
		var blocker_wrist: Vector3 = _skel.xf[B.FOREARM_B] * Vector3(0.0, -KeeperAnatomy.FOREARM_M, 0.0)
		assert_almost_eq(glove_wrist.distance_to(_skel.xf[B.HAND_G].origin), 0.0, 0.002,
				"%s: the glove arm reaches its hand" % when)
		assert_almost_eq(blocker_wrist.distance_to(_skel.xf[B.HAND_B] * KeeperAnatomy.BLOCKER_WRIST),
				0.0, 0.002, "%s: the blocker arm reaches the stick" % when)
		var at: Array[Vector3] = _bones()
		for b: int in KeeperSkeleton.BONE_COUNT:
			assert_lt(at[b].distance_to(was[b]), MAX_BONE_STEP_M, "%s bone %d" % [when, b])
		was = at
