extends GutTest

# The keeper's butterfly slide (KeeperSlide), from the butterfly and from his
# feet by the half butterfly: he comes to rest on his spot in
# the time the slide model gives, or at the push's reach; once pushed, the
# pads' friction slows him and then the lead skate's edge stops him, quicker
# than friction alone; the push skate holds its place while it drives; the lead
# pad stays down on the ice the whole way, and both are down through the stop;
# it starts and ends in the butterfly; and every tick keeps his gear out of the
# ice, his arms on the stick and nothing on him jumping. Off the RVH he pushes
# off the post: from the RVH, the skate on the post holding it until the push
# ends, to rest on his spot in the slide's time, never toward the post.

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
		out.append(_world(_skel.xf[b].origin))
	return out


# A point of his own frame on the ice, turned and placed where he is.
func _world(v: Vector3) -> Vector3:
	return Basis(Vector3.UP, _slide.yaw) * v + Vector3(_slide.x, 0.0, _slide.z)


# A slide along his line, to `target` across it.
func _start(target: float, from_feet: bool) -> float:
	var spot := Vector2(target, 0.0)
	return (_slide.slide_from_feet(spot) if from_feet else _slide.slide_to(spot)).x


func _from(from_feet: bool) -> int:
	return KeeperSlide.From.FEET if from_feet else KeeperSlide.From.BUTTERFLY


func _how(from_feet: bool) -> String:
	return "from his feet" if from_feet else "from the butterfly"


func test_he_comes_to_rest_on_his_spot_in_the_slides_time() -> void:
	for from_feet: bool in [false, true]:
		for dist: float in [0.2, 0.6, 1.0, -1.3]:
			_slide = KeeperSlide.new()
			var what: String = "%s %.1f m" % [_how(from_feet), dist]
			assert_almost_eq(_start(dist, from_feet), dist, 1e-6, "%s is within reach" % what)
			var t: float = _run()
			# Each phase ends on a whole tick.
			assert_almost_eq(t, _slide.time_to(absf(dist), INF, _from(from_feet)), 2.5 * DT, what)
			assert_almost_eq(_slide.x, dist, 1e-6, "%s: on the spot" % what)
			assert_eq(_slide.speed, 0.0)


func test_past_the_hardest_push_he_comes_to_rest_at_its_reach() -> void:
	var reach: float = _slide.glide_reach(_slide.push_speed)
	assert_almost_eq(_slide.slide_to(Vector2(3.0, 0.0)).x, reach, 1e-6, "says where he will stop")
	_run()
	assert_almost_eq(_slide.x, reach, 1e-6)


# Once pushed he cannot steer: the pads' friction slows him, and then the lead
# skate's edge stops him, each at its own rate; nothing speeds him up.
func test_once_pushed_friction_then_the_edge_slows_him() -> void:
	_slide.slide_to(Vector2(1.2, 0.0))
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
	assert_eq(_slide.slide_to(Vector2(1.0, 0.0), 2.4).x, 1.0, "still within its reach")
	var top: float = 0.0
	while _slide.phase != KeeperSlide.Phase.DOWN:
		_slide.step(DT)
		top = maxf(top, _slide.speed)
	assert_almost_eq(top, 2.4, 1e-6)
	assert_eq(_slide.x, 1.0)


func test_the_push_skate_holds_its_place_while_it_drives() -> void:
	_slide.slide_to(Vector2(1.0, 0.0))
	var planted: float = NAN
	var ticks: int = 0
	while _slide.phase != KeeperSlide.Phase.GLIDE:
		_slide.step(DT)
		if _slide.phase != KeeperSlide.Phase.PUSH:
			continue
		_solve()
		assert_almost_eq(_lowest(P.SKATE_G), 0.0, 0.005, "its skate is on the ice")
		var at: float = _world(_skel.xf[KeeperSkeleton.FOOT[0]].origin).x
		if is_nan(planted):
			planted = at
		assert_almost_eq(at, planted, 0.001, "at x %.3f it holds" % _slide.x)
		ticks += 1
	assert_gt(ticks, 10, "a push, not a flick")


# From his feet the push skate is where his push comes from from the start:
# it holds its place on the ice from the drop's first frame to the push's last,
# while the lead knee falls; and he starts from the ready stance.
func test_from_his_feet_the_push_skate_never_leaves_its_spot() -> void:
	var ready_pose := KeeperPose.new()
	KeeperPoses.ready(ready_pose)
	var skel := KeeperSkeleton.new()
	skel.pose(ready_pose)
	_slide.slide_from_feet(Vector2(1.0, 0.0))
	_solve()
	for b: int in KeeperSkeleton.BONE_COUNT:
		assert_almost_eq(_skel.xf[b].origin, skel.xf[b].origin, Vector3.ONE * 1e-3, "bone %d starts standing" % b)
	var planted: float = _world(_skel.xf[KeeperSkeleton.FOOT[0]].origin).x
	var ticks: int = 0
	while _slide.phase == KeeperSlide.Phase.DROP or _slide.phase == KeeperSlide.Phase.PUSH:
		_slide.step(DT)
		_solve()
		if _slide.phase == KeeperSlide.Phase.GLIDE:
			break
		assert_almost_eq(_lowest(P.SKATE_G), 0.0, 0.005, "at x %.3f its skate is on the ice" % _slide.x)
		assert_almost_eq(_world(_skel.xf[KeeperSkeleton.FOOT[0]].origin).x, planted, 0.001,
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
	_slide.slide_to(Vector2(0.8, 0.0))
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


# Short slides too: their stop comes while the push leg is still folding down.
func test_every_tick_keeps_his_gear_out_of_the_ice_his_arms_on_the_stick_and_nothing_jumping() -> void:
	for from_feet: bool in [false, true]:
		for target: float in [1.0, -1.6, 0.3, -0.3]:
			_check_every_tick(target, from_feet)
	for target: float in [0.8, -0.8, 0.3, -0.3]:
		_check_every_tick(target, false, true)


func _check_every_tick(target: float, from_feet: bool, off_post: bool = false) -> void:
	_slide = KeeperSlide.new()
	if off_post:
		_push_off(target)
	else:
		_start(target, from_feet)
	_solve()
	var was: Array[Vector3] = _bones()
	while _slide.phase != KeeperSlide.Phase.DOWN:
		_slide.step(DT)
		_solve()
		var when: String = "%s %+.1f %s x %.3f" % ["off the post" if off_post else _how(from_feet), target,
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


# A spot off his line is the same slide, turned: he turns as he loads until his
# lead side faces the spot, then slides straight along his line to it.
func test_a_spot_off_his_line_turns_him_to_it_as_he_loads() -> void:
	for from_feet: bool in [false, true]:
		for spot: Vector2 in [Vector2(1.0, 0.4), Vector2(-0.8, 0.3)]:
			_slide = KeeperSlide.new()
			var what: String = "%s to %s" % [_how(from_feet), spot]
			var land: Vector2 = _slide.slide_from_feet(spot) if from_feet else _slide.slide_to(spot)
			assert_almost_eq(land, spot, Vector2.ONE * 1e-6, "%s: within reach" % what)
			var lead: float = signf(spot.x)
			var turned: float = KeeperSlide.facing(spot.normalized(), lead)
			var across := Vector2(cos(turned), -sin(turned)) * lead
			assert_almost_eq(across, spot.normalized(), Vector2.ONE * 1e-6, "%s: his lead side faces it" % what)
			while _slide.phase != KeeperSlide.Phase.DOWN:
				_slide.step(DT)
				if _slide.phase == KeeperSlide.Phase.PUSH or _slide.phase == KeeperSlide.Phase.GLIDE \
						or _slide.phase == KeeperSlide.Phase.STOP:
					assert_almost_eq(_slide.yaw, turned, 1e-6, "%s: turned by the push" % what)
			assert_almost_eq(Vector2(_slide.x, _slide.z), spot, Vector2.ONE * 1e-6, "%s: on the spot" % what)
	_slide = KeeperSlide.new()
	_slide.slide_to(Vector2(1.0, 0.0))
	_run()
	assert_eq(_slide.yaw, 0.0, "along his line he stays square")


# A slide to a post lands the lead pad's outer end on the post. From the far
# side of the crease, where a play to the other post leaves him, the slide is
# angled back toward the goal line, and leaves him opened toward that post's
# side.
func test_a_slide_to_a_post_lands_the_pad_on_it() -> void:
	var goal_line: float = 0.35
	for from_feet: bool in [false, true]:
		for start: Vector2 in [Vector2(0.6, -0.4), Vector2(0.4, -0.1)]:
			for post_side: float in [1.0, -1.0]:
				start.x = -post_side * absf(start.x)
				_slide = KeeperSlide.new()
				_slide.x = start.x
				_slide.z = start.y
				var post := Vector2(post_side * GameRules.NET_HALF_WIDTH, goal_line)
				var spot: Vector2 = _slide.post_spot(post, start)
				var what: String = "%s from %s to the %+.0f post" % [_how(from_feet), start, post_side]
				var land: Vector2 = _slide.slide_from_feet(spot) if from_feet else _slide.slide_to(spot)
				assert_almost_eq(land, spot, Vector2.ONE * 1e-6, "%s: within reach" % what)
				_run()
				assert_gt(_slide.z, start.y, "%s: angled back" % what)
				_skel.pose(_butterfly())
				var end: Vector3 = _world(KeeperGear.post_pad_contact(_skel, post_side))
				assert_almost_eq(Vector2(end.x, end.z).distance_to(post), GameRules.NET_POST_RADIUS, 0.01,
						"%s: the pad's end is on the post" % what)
				var front: Vector3 = Basis(Vector3.UP, _slide.yaw) * Vector3.FORWARD
				assert_gt(front.x * post_side, 0.0, "%s: opened toward the post's side" % what)


func _butterfly() -> KeeperPose:
	var p := KeeperPose.new()
	KeeperPoses.butterfly(p)
	return p


# Rotation on his knees: from the butterfly he turns to face where he is asked,
# either way, in the rotation's time, staying on his spot, back in the
# butterfly; the skate that drives it on the side he turns away from, planted
# on the ice; and every tick out of the ice, on the stick and without a jump.
func test_he_rotates_on_his_knees_to_a_new_facing() -> void:
	for off: float in [deg_to_rad(40.0), deg_to_rad(-70.0), deg_to_rad(15.0)]:
		_slide = KeeperSlide.new()
		_slide.rotate_to(off)
		var what: String = "%+.0f°" % rad_to_deg(off)
		_solve()
		var was: Array[Vector3] = _bones()
		var t: float = 0.0
		var pushing_skate_low: float = INF
		while _slide.phase != KeeperSlide.Phase.DOWN and t < 2.0:
			_slide.step(DT)
			t += DT
			_solve()
			for part: int in KeeperGear.PART_COUNT:
				var soft: bool = KeeperGear.save_part(part) == GoalieSaveRules.SavePart.PAD
				if _lowest(part) < -(PAD_GIVE_M if soft else HARD_GIVE_M):
					assert_gte(_lowest(part), -(PAD_GIVE_M if soft else HARD_GIVE_M),
							"%s t %.3f %s" % [what, t, KeeperGear.Part.keys()[part]])
			var at: Array[Vector3] = _bones()
			for b: int in KeeperSkeleton.BONE_COUNT:
				if at[b].distance_to(was[b]) >= MAX_BONE_STEP_M:
					assert_lt(at[b].distance_to(was[b]), MAX_BONE_STEP_M, "%s t %.3f bone %d" % [what, t, b])
			was = at
			if _slide.phase == KeeperSlide.Phase.TURN:
				# The push skate is the one on the side he turns away from.
				var away: int = 0 if off < 0.0 else 1
				pushing_skate_low = minf(pushing_skate_low, _lowest(P.SKATE_G + away))
		assert_almost_eq(_slide.yaw, off, 1e-4, "%s: turned to it" % what)
		assert_almost_eq(t, _slide.rotate_time(off), 2.0 * DT, "%s: in the rotation's time" % what)
		assert_almost_eq(Vector2(_slide.x, _slide.z), Vector2.ZERO, Vector2.ONE * 1e-5, "%s: on his spot" % what)
		assert_lt(pushing_skate_low, 0.02, "%s: driven off a skate on the ice" % what)
		assert_true(_slide.is_settled(), "%s: down in the butterfly" % what)


# In the RVH on the post on the far side from `target`, sealed, pushed off it
# `target` across his line; where he set out from.
func _push_off(target: float) -> Vector2:
	var side: float = -signf(target)
	var start: Vector2 = KeeperPost.new().seal_spot(Vector2(side * GameRules.NET_HALF_WIDTH, 0.35), side)
	_slide.x = start.x
	_slide.z = start.y
	_slide.push_off(start + Vector2(target, 0.0), side)
	return start


func test_off_the_rvh_he_pushes_off_the_post_to_rest_on_his_spot_in_its_time() -> void:
	for target: float in [0.3, 0.8, -0.8, -1.3]:
		_slide = KeeperSlide.new()
		var start: Vector2 = _push_off(target)
		assert_eq(_slide.phase, KeeperSlide.Phase.OFF_POST, "%+.1f: off the post" % target)
		var t: float = _run()
		assert_almost_eq(t, _slide.time_to(absf(target), INF, KeeperSlide.From.POST), 2.5 * DT, "%+.1f" % target)
		assert_almost_eq(_slide.x, start.x + target, 1e-6, "%+.1f: on the spot" % target)
		assert_lt(_slide.time_to(absf(target), INF, KeeperSlide.From.POST),
				KeeperPost.OUT_TO_BUTTERFLY_S + _slide.time_to(absf(target)),
				"%+.1f: quicker than folding out of the RVH and sliding" % target)


# He sets out from the RVH as the post holds it, and the boot on the post holds
# its place on the ice until the push has driven him off it.
func test_off_the_rvh_the_skate_on_the_post_holds_it_until_the_push_ends() -> void:
	var post := KeeperPost.new()
	var rvh := KeeperPose.new()
	var skel := KeeperSkeleton.new()
	for target: float in [0.8, -0.8]:
		var side: float = -signf(target)
		_slide = KeeperSlide.new()
		_push_off(target)
		post.side = side
		post.state = KeeperPost.State.SEALED
		post.pose(rvh)
		skel.pose(rvh)
		_solve()
		for b: int in KeeperSkeleton.BONE_COUNT:
			assert_almost_eq(_skel.xf[b].origin, skel.xf[b].origin, Vector3.ONE * 2e-3, "%+.1f: bone %d starts in the RVH" % [target, b])
		var foot: int = KeeperSkeleton.FOOT[0 if side < 0.0 else 1]
		var planted: Vector3 = _world(_skel.xf[foot].origin)
		var ticks: int = 0
		while _slide.phase == KeeperSlide.Phase.OFF_POST or _slide.phase == KeeperSlide.Phase.PUSH:
			_slide.step(DT)
			_solve()
			if _slide.phase == KeeperSlide.Phase.GLIDE:
				break
			var at: Vector3 = _world(_skel.xf[foot].origin)
			assert_almost_eq(at, planted, Vector3.ONE * 0.03, "%+.1f %s at x %.3f: on the post" % [target,
					KeeperSlide.Phase.keys()[_slide.phase], _slide.x])
			ticks += 1
		assert_gt(ticks, 30, "%+.1f: the knee coming up and the push" % target)


func test_off_the_rvh_he_never_pushes_toward_the_post() -> void:
	var start: Vector2 = KeeperPost.new().seal_spot(Vector2(GameRules.NET_HALF_WIDTH, 0.35), 1.0)
	_slide.x = start.x
	_slide.z = start.y
	assert_eq(_slide.push_off(start + Vector2(0.5, 0.0), 1.0), start, "stays")
	assert_eq(_slide.phase, KeeperSlide.Phase.DOWN)
