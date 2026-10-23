extends GutTest

# The keeper's footwork (KeeperFootwork), the T-push, the shuffle and the
# C-cuts: he gets to his spot in the time GoaliePushRules gives the move's push
# and stop, stopped on it, a T-push straight there on a diagonal; a pushing
# skate holds its place while it pushes and never slides back against the push;
# his skates stay on the ice and his gear out of it at every tick; nothing on
# him jumps between ticks; and once the stop has settled out of him he is in
# the ready stance.

const DT: float = 1.0 / 120.0
const PAD_GIVE_M: float = 0.025
const HARD_GIVE_M: float = 0.005
# A bone's travel in a tick, past which it has jumped: the recovering leg is
# the fastest thing on him, about 7 m/s at its peak.
const MAX_BONE_STEP_M: float = 0.1
const T_PUSH := KeeperFootwork.Move.T_PUSH
const SHUFFLE := KeeperFootwork.Move.SHUFFLE
const C_CUT := KeeperFootwork.Move.C_CUT
const MOVES: Array[int] = [T_PUSH, SHUFFLE, C_CUT]
# T-pushes off his line, forward (−z) and back, both ways, out to near the
# steepest he takes.
const DIAGONALS: Array[Vector2] = [
	Vector2(1.0, -0.35), Vector2(1.0, 0.35), Vector2(-1.0, -0.8), Vector2(-1.0, 0.8),
	Vector2(0.5, -0.45), Vector2(-1.4, 1.3),
]

var _fw: KeeperFootwork = null
var _pose := KeeperPose.new()
var _skel := KeeperSkeleton.new()


func before_each() -> void:
	_fw = KeeperFootwork.new()


func _go(kind: int, target: float) -> void:
	match kind:
		T_PUSH:
			_fw.push_to(Vector2(target, 0.0))
		SHUFFLE:
			_fw.shuffle_to(target)
		C_CUT:
			_fw.c_cut_to(target)


# Where he is along the move's axis.
func _at(kind: int) -> float:
	return _fw.z if kind == C_CUT else _fw.x


func _where() -> Vector3:
	return Vector3(_fw.x, 0.0, _fw.z)


func _name(kind: int, target: float) -> String:
	return "%s %+.2f" % [KeeperFootwork.Move.keys()[kind], target]


func _solve() -> void:
	_fw.pose(_pose)
	_skel.pose(_pose)


func _lowest(part: int) -> float:
	var t: Transform3D = KeeperGear.box(_skel, part)
	var h: Vector3 = KeeperGear.half_extents(part)
	return t.origin.y - absf(t.basis.x.y) * h.x - absf(t.basis.y.y) * h.y - absf(t.basis.z.y) * h.z


# A skate's place on the ice, in the world.
func _skate(leg: int) -> Vector3:
	return _skel.xf[KeeperSkeleton.FOOT[leg]].origin + _where()


# Steps him until he is set, at most `limit` seconds; the time it took.
func _run(limit: float = 3.0) -> float:
	var t: float = 0.0
	while _fw.phase != KeeperFootwork.Phase.SET and t < limit:
		_fw.step(DT)
		t += DT
	return t


func test_he_is_set_on_his_spot_in_the_push_rules_time() -> void:
	for kind: int in MOVES:
		for dist: float in [0.1, 0.4, 1.0, 1.8, -0.6]:
			_fw = KeeperFootwork.new()
			_go(kind, dist)
			var t: float = _run()
			var rules: float = GoaliePushRules.time_to_set(absf(dist), _fw.top_speed(), _fw.accel)
			assert_almost_eq(t, rules, 2.5 * DT, _name(kind, dist))
			# A T-push's spot comes as a Vector2, in single precision.
			assert_almost_eq(_at(kind), dist, 1e-6, "%s: on the spot" % _name(kind, dist))
			assert_eq(_fw.speed, 0.0, "%s: stopped" % _name(kind, dist))


func test_he_never_goes_past_his_top_speed_or_his_spot() -> void:
	for kind: int in MOVES:
		_fw = KeeperFootwork.new()
		_go(kind, 1.2)
		var top: float = _fw.top_speed()
		while _fw.phase != KeeperFootwork.Phase.SET:
			_fw.step(DT)
			assert_lte(_fw.speed, top + 1e-6)
			assert_lte(_at(kind), 1.2 + 1e-6)
	var fw := KeeperFootwork.new()
	assert_lt(fw.shuffle_speed, fw.t_push_speed, "a shuffle is slower than a T-push")
	assert_lt(fw.c_cut_speed, fw.t_push_speed, "C-cuts are slower than a T-push")


func test_a_spot_the_other_way_mid_move_is_reached() -> void:
	for kind: int in MOVES:
		_fw = KeeperFootwork.new()
		_go(kind, 1.0)
		for i: int in 30:
			_fw.step(DT)
		_go(kind, -0.5)
		assert_lt(_run(), 3.0, "%s: he gets there" % _name(kind, -0.5))
		assert_eq(_at(kind), -0.5)
		assert_eq(_fw.speed, 0.0)


# A T-push off his line goes straight to its spot, in the time its distance
# takes at the T-push's kinematics.
func test_a_diagonal_t_push_goes_straight_to_its_spot() -> void:
	for spot: Vector2 in DIAGONALS:
		_fw = KeeperFootwork.new()
		_fw.push_to(spot)
		var way: Vector2 = spot.normalized()
		var t: float = 0.0
		var off_line: float = 0.0
		while _fw.phase != KeeperFootwork.Phase.SET and t < 3.0:
			_fw.step(DT)
			t += DT
			off_line = maxf(off_line, absf(Vector2(_fw.x, _fw.z).cross(way)))
			assert_lte(_fw.speed, _fw.t_push_speed + 1e-6)
		var rules: float = GoaliePushRules.time_to_set(spot.length(), _fw.t_push_speed, _fw.accel)
		assert_almost_eq(t, rules, 2.5 * DT, "%s: in its time" % spot)
		assert_lt(off_line, 1e-5, "%s: never off the straight line to it" % spot)
		assert_eq(Vector2(_fw.x, _fw.z), spot, "%s: on the spot" % spot)


func test_a_spot_further_off_his_line_is_pushed_to_where_it_falls_on_it() -> void:
	var steep: float = tan(KeeperFootwork.DIAGONAL_MAX_RAD) + 0.1
	for spot: Vector2 in [Vector2(0.8, steep * 0.8), Vector2(-0.8, -steep * 0.8)]:
		_fw = KeeperFootwork.new()
		_fw.push_to(spot)
		_run()
		assert_eq(Vector2(_fw.x, _fw.z), Vector2(spot.x, 0.0), "%s" % spot)


# A move goes along one axis: a spot on the other waits until he is set.
func test_a_spot_on_the_other_axis_waits_until_he_is_set() -> void:
	_fw.push_to(Vector2(1.0, 0.0))
	_fw.step(DT)
	_fw.c_cut_to(0.5)
	_run()
	assert_eq(_fw.x, 1.0, "the push he was making")
	assert_eq(_fw.z, 0.0, "no depth taken mid-push")
	_fw.c_cut_to(0.5)
	_run()
	assert_eq(_fw.z, 0.5, "taken once he is set")


# The T-push skate is where his push comes from: it does not move on the ice
# until the leg driving off it is out as far as it goes.
func test_the_t_push_skate_stays_on_its_plant_until_the_leg_is_out() -> void:
	var reach: float = KeeperFootwork.TRAIL_REACH * (KeeperAnatomy.THIGH_M + KeeperAnatomy.SHIN_M)
	for spot: Vector2 in [Vector2(1.0, 0.0)] + DIAGONALS:
		_fw = KeeperFootwork.new()
		_fw.push_to(spot)
		var trail: int = 0 if spot.x > 0.0 else 1
		var plant := Vector2(-signf(spot.x) * KeeperPoses.READY_SKATE_HALF_SPACING_M, 0.0)
		var planted_ticks: int = 0
		while true:
			_fw.step(DT)
			if _fw.phase != KeeperFootwork.Phase.PUSH:
				break
			_solve()
			var hip: Vector3 = _skel.xf[KeeperSkeleton.THIGH[trail]].origin
			var ankle: Vector3 = _skel.xf[KeeperSkeleton.FOOT[trail]].origin
			if Vector2(ankle.x + _fw.x, ankle.z + _fw.z).distance_to(plant) < 0.001:
				planted_ticks += 1
			else:
				assert_almost_eq(hip.distance_to(ankle), reach, 0.01,
						"%s: off its plant at %.3f, %.3f only with the leg out" % [spot, _fw.x, _fw.z])
		assert_gt(planted_ticks, 15, "%s: it is planted for most of the push" % spot)


# The shuffle and the C-cuts are strokes: in each a skate holds its place along
# the travel while the body passes over it, then comes back in under him. No
# skate slides back against the push; a C-cut's skates take turns.
func test_a_stroke_skate_holds_its_place_and_never_slides_back() -> void:
	for kind: int in [SHUFFLE, C_CUT]:
		for target: float in [1.4, -1.4]:
			_fw = KeeperFootwork.new()
			_go(kind, target)
			var axis: int = 2 if kind == C_CUT else 0
			var s: float = signf(target)
			_fw.step(DT)
			_solve()
			var was: Array[float] = [_skate(0)[axis], _skate(1)[axis]]
			var hold_from: Array[float] = [_at(kind), _at(kind)]
			var held: Array[int] = [0, 0]
			# A forward C-cut holds only briefly: behind the stance the pad's toe
			# meets the ice.
			var min_hold: float = 0.03 if kind == C_CUT and target < 0.0 else 0.1
			while _fw.phase == KeeperFootwork.Phase.PUSH:
				_fw.step(DT)
				_solve()
				for leg: int in 2:
					var at: float = _skate(leg)[axis]
					assert_gte((at - was[leg]) * s, -1e-5,
							"%s at %.3f: skate %d never slides back" % [_name(kind, target), _at(kind), leg])
					if absf(at - was[leg]) > 1e-5:
						if (_at(kind) - hold_from[leg]) * s > min_hold:
							held[leg] += 1
						hold_from[leg] = _at(kind)
					was[leg] = at
			var what: String = _name(kind, target)
			if kind == SHUFFLE:
				var trail: int = 0 if target > 0.0 else 1
				assert_gte(held[trail], 2, "%s: the trail skate holds for each stroke" % what)
			else:
				assert_gte(held[0], 1, "%s: the glove skate cuts" % what)
				assert_gte(held[1], 1, "%s: the blocker skate cuts" % what)


func test_the_shuffle_stays_square() -> void:
	_fw.shuffle_to(1.0)
	while _fw.phase != KeeperFootwork.Phase.SET:
		_fw.step(DT)
		_fw.pose(_pose)
		for side: int in 2:
			assert_almost_eq(_pose.legs[side].toe, KeeperPoses.ready_toe(-1.0 if side == 0 else 1.0),
					Vector3.ONE * 1e-4, "skate %d stays toed out as in the stance" % side)


# A C-cut's heel turns out as it carves: going back its toe turns in past
# square, going forward it turns further out.
func test_a_c_cut_turns_its_heel_out() -> void:
	for target: float in [1.0, -1.0]:
		_fw = KeeperFootwork.new()
		_fw.c_cut_to(target)
		var most_in: float = INF
		var most_out: float = -INF
		while _fw.phase != KeeperFootwork.Phase.SET:
			_fw.step(DT)
			_fw.pose(_pose)
			for leg: int in 2:
				var out: float = _pose.legs[leg].toe.x * (-1.0 if leg == 0 else 1.0)
				most_in = minf(most_in, out)
				most_out = maxf(most_out, out)
		if target > 0.0:
			assert_lt(most_in, 0.0, "going back, a toe turns in past square")
		else:
			assert_gt(most_out, sin(KeeperPoses.READY_TOE_OUT_RAD) + 0.2,
					"going forward, a toe turns well out")


func test_his_skates_stay_on_the_ice_his_gear_out_of_it_and_his_stick_in_hand() -> void:
	var runs: Array = []
	for kind: int in MOVES:
		for target: float in [1.0, -1.0]:
			runs.append([kind, Vector2(target, 0.0)])
	for spot: Vector2 in DIAGONALS:
		runs.append([T_PUSH, spot])
	for run: Array in runs:
		var kind: int = run[0]
		var spot: Vector2 = run[1]
		_fw = KeeperFootwork.new()
		if kind == T_PUSH:
			_fw.push_to(spot)
		else:
			_go(kind, spot.x)
		var trail: int = 0 if spot.x > 0.0 else 1
		var what: String = "%s %s" % [KeeperFootwork.Move.keys()[kind], spot]
		for i: int in 120:
			_fw.step(DT)
			_solve()
			for part: int in KeeperGear.PART_COUNT:
				var soft: bool = KeeperGear.save_part(part) == GoalieSaveRules.SavePart.PAD
				assert_gte(_lowest(part), -(PAD_GIVE_M if soft else HARD_GIVE_M),
						"%s tick %d %s" % [what, i, KeeperGear.Part.keys()[part]])
			var low: Array[float] = [_lowest(KeeperGear.Part.SKATE_G), _lowest(KeeperGear.Part.SKATE_B)]
			for leg: int in 2:
				assert_between(low[leg], -0.005, KeeperFootwork.RECOVER_LIFT_M + 0.005,
						"%s tick %d: skate %d is never more than lifted clear" % [what, i, leg])
			assert_lt(minf(absf(low[0]), absf(low[1])), 0.005,
					"%s tick %d: a skate is on the ice" % [what, i])
			if kind != C_CUT:
				assert_almost_eq(low[1 - trail], 0.0, 0.005, "%s tick %d: the lead skate" % [what, i])
			if kind == T_PUSH and _fw.phase == KeeperFootwork.Phase.PUSH:
				assert_almost_eq(low[trail], 0.0, 0.005, "%s tick %d: the push skate" % [what, i])
			var blocker_wrist: Vector3 = _skel.xf[KeeperSkeleton.Bone.FOREARM_B] \
					* Vector3(0.0, -KeeperAnatomy.FOREARM_M, 0.0)
			assert_almost_eq(blocker_wrist.distance_to(_skel.xf[KeeperSkeleton.Bone.HAND_B]
					* KeeperAnatomy.BLOCKER_WRIST), 0.0, 0.002, "%s tick %d: the blocker arm on the stick" % [what, i])


func test_nothing_on_him_jumps_between_ticks() -> void:
	for run: int in MOVES.size() + DIAGONALS.size():
		var kind: int = MOVES[run] if run < MOVES.size() else T_PUSH
		var spot: Vector2 = Vector2(1.0, 0.0) if run < MOVES.size() else DIAGONALS[run - MOVES.size()]
		_fw = KeeperFootwork.new()
		if run < MOVES.size():
			_go(kind, spot.x)
		else:
			_fw.push_to(spot)
		_solve()
		var was: Array[Vector3] = []
		for b: int in KeeperSkeleton.BONE_COUNT:
			was.append(_skel.xf[b].origin)
		for i: int in 120:
			_fw.step(DT)
			_solve()
			for b: int in KeeperSkeleton.BONE_COUNT:
				var at: Vector3 = _skel.xf[b].origin + _where()
				assert_lt(at.distance_to(was[b]), MAX_BONE_STEP_M,
						"%s %s tick %d bone %d" % [KeeperFootwork.Move.keys()[kind], spot, i, b])
				was[b] = at


func test_the_t_push_lead_skate_turns_along_the_push_and_squares_to_stop() -> void:
	for spot: Vector2 in [Vector2(1.0, 0.0)] + DIAGONALS:
		_fw = KeeperFootwork.new()
		_fw.push_to(spot)
		var lead: int = 1 if spot.x > 0.0 else 0
		var way := Vector3(spot.x, 0.0, spot.y).normalized()
		var turned: float = 0.0
		while _fw.phase != KeeperFootwork.Phase.SET:
			_fw.step(DT)
			_fw.pose(_pose)
			turned = maxf(turned, _pose.legs[lead].toe.normalized().dot(way))
		assert_gt(turned, 0.95, "%s: the lead toe points along the push" % spot)
		for i: int in int(KeeperFootwork.SETTLE_S / DT) + 2:
			_fw.step(DT)
		_fw.pose(_pose)
		assert_almost_eq(_pose.legs[lead].toe, KeeperPoses.ready_toe(signf(spot.x)), Vector3.ONE * 1e-4,
				"%s: square again once settled on his spot" % spot)


# The stop shows as much as the speed it stops: a shuffle's is softer than a
# T-push's.
func test_a_slower_stop_leans_back_less() -> void:
	var ready_pose := KeeperPose.new()
	KeeperPoses.ready(ready_pose)
	var lean: Array[float] = []
	for kind: int in [T_PUSH, SHUFFLE]:
		_fw = KeeperFootwork.new()
		_go(kind, 1.5)
		_run()
		_fw.pose(_pose)
		lean.append(absf(_pose.lumbar_rot.z - ready_pose.lumbar_rot.z))
	assert_gt(lean[0], lean[1], "the T-push stops harder than the shuffle")
	assert_gt(lean[1], 0.01, "the shuffle's stop still shows")


func test_set_and_settled_is_the_ready_stance() -> void:
	var ready_pose := KeeperPose.new()
	KeeperPoses.ready(ready_pose)
	for kind: int in MOVES:
		_fw = KeeperFootwork.new()
		_fw.pose(_pose)
		assert_eq(_pose.pelvis, ready_pose.pelvis, "before he moves")
		_go(kind, 0.8)
		_run()
		for i: int in int(KeeperFootwork.SETTLE_S / DT) + 2:
			_fw.step(DT)
		_fw.pose(_pose)
		var what: String = KeeperFootwork.Move.keys()[kind]
		assert_eq(_pose.pelvis, ready_pose.pelvis, what)
		assert_eq(_pose.lumbar_rot, ready_pose.lumbar_rot, what)
		for side: int in 2:
			assert_eq(_pose.legs[side].ankle, ready_pose.legs[side].ankle, "%s ankle %d" % [what, side])
			assert_eq(_pose.legs[side].toe, ready_pose.legs[side].toe, "%s toe %d" % [what, side])
