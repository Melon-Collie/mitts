extends GutTest

# The keeper's moves strung together (KeeperMotor): a whole sequence across the
# crease and back, every hand-off from one move to the next leaving nothing on
# him jumping and his gear out of the ice; the pivot turning him at its rate and
# stopping on its facing; footwork going in his turned frame; a move asked
# for from the wrong rest refused; asked down while he skates, down at once
# carrying his speed, the slide ridden to a goal behind him and let go for one
# across; down pushes one after another, the next going as soon as the last
# stops; and a goal within his knees' reach scooted to and followed.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const PAD_GIVE_M: float = 0.025
const HARD_GIVE_M: float = 0.005
const MAX_BONE_STEP_M: float = 12.0 * DT  # nothing on him moves 12 m/s
const GOAL_LINE_Z: float = 0.35
const B := KeeperSkeleton.Bone
const R := KeeperMotor.Rest

var _motor: KeeperMotor = null
var _pose := KeeperPose.new()
var _skel := KeeperSkeleton.new()


func before_each() -> void:
	_motor = KeeperMotor.new()


func _world(v: Vector3) -> Vector3:
	return Basis(Vector3.UP, _motor.yaw) * v + Vector3(_motor.x, 0.0, _motor.z)


func _solve() -> void:
	_motor.pose(_pose)
	_skel.pose(_pose)


func _bones() -> Array[Vector3]:
	_solve()
	var out: Array[Vector3] = []
	for b: int in KeeperSkeleton.BONE_COUNT:
		out.append(_world(_skel.xf[b].origin))
	return out


func _lowest(part: int) -> float:
	var t: Transform3D = KeeperGear.box(_skel, part)
	var h: Vector3 = KeeperGear.half_extents(part)
	return t.origin.y - absf(t.basis.x.y) * h.x - absf(t.basis.y.y) * h.y - absf(t.basis.z.y) * h.z


# Steps until every move asked for is done, checking every tick: nothing on him
# jumps, his gear stays out of the ice and his arms on the stick. The time it
# took.
func _run_checked(what: String, limit: float = 10.0) -> float:
	var was: Array[Vector3] = _bones()
	var t: float = 0.0
	while not _motor.is_idle() and t < limit:
		_motor.step(DT)
		t += DT
		var at: Array[Vector3] = _bones()
		var when: String = "%s t %.3f" % [what, t]
		for b: int in KeeperSkeleton.BONE_COUNT:
			assert_lt(at[b].distance_to(was[b]), MAX_BONE_STEP_M, "%s bone %d" % [when, b])
		was = at
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
	assert_true(_motor.is_idle(), "%s: done inside %.0f s" % [what, limit])
	return t


# Across the crease and back: turned to the puck, a T-push, down, a slide to the
# post, up into the RVH, back down, recovered toward the middle, a shuffle out,
# and a C-cut back to depth.
func test_a_whole_sequence_hands_each_move_to_the_next_unbroken() -> void:
	var iron := Vector2(GameRules.NET_HALF_WIDTH, GOAL_LINE_Z)
	_motor.x = -0.3
	_motor.z = -0.6
	_motor.face(-0.25)
	_motor.push_to(Vector2(-0.8, -0.6))
	_motor.drop_down()
	_motor.slide_to(_motor.slide.post_spot(iron, Vector2(-0.8, -0.6)))
	_run_checked("to the post")
	assert_eq(_motor.rest, R.DOWN)
	_motor.rvh_slide_in(iron, 1.0)
	_motor.rvh_fold_out()
	_motor.recover(-1.0)
	_motor.face(0.0)
	_motor.shuffle_to(Vector2(0.0, 0.0))
	_motor.c_cut_to(Vector2(0.0, -0.6))
	_run_checked("and back out")
	assert_eq(_motor.rest, R.FEET)
	assert_eq(_motor.refused, 0, "every move asked for from the rest it starts from")


# On his feet to the overlap at the glove post, down into the RVH there, back up
# out of it and a T-push off it toward the middle.
func test_a_drop_in_at_the_post_and_out_again() -> void:
	var iron := Vector2(-GameRules.NET_HALF_WIDTH, GOAL_LINE_Z)
	var overlap: Vector2 = _motor.post.overlap_spot(iron, -1.0)
	_motor.x = overlap.x + 0.6
	_motor.z = overlap.y
	_motor.push_to(overlap)
	_motor.rvh_drop_in(iron, -1.0)
	_run_checked("into the RVH")
	assert_eq(_motor.rest, R.POST)
	_motor.rvh_rise_out()
	_motor.push_to(overlap + Vector2(0.5, 0.0))
	_run_checked("out of it")
	assert_eq(_motor.rest, R.FEET)
	assert_almost_eq(_motor.x, overlap.x + 0.5, 1e-4)
	assert_eq(_motor.refused, 0)


func test_the_pivot_turns_him_at_its_rate_and_stops_on_its_facing() -> void:
	for turn: float in [0.6, -1.2]:
		_motor = KeeperMotor.new()
		_motor.face(turn)
		var was: float = 0.0
		var top: float = 0.0
		var t: float = _run_checked("to %.1f" % turn)
		_motor = KeeperMotor.new()
		_motor.face(turn)
		while not _motor.is_idle():
			_motor.step(DT)
			top = maxf(top, absf(_motor.yaw - was) / DT)
			was = _motor.yaw
		assert_eq(_motor.yaw, turn, "stops on its facing")
		assert_lte(top, KeeperMotor.PIVOT_RATE_RAD_S + 1e-4, "at its rate")
		var least: float = absf(turn) / KeeperMotor.PIVOT_RATE_RAD_S
		assert_between(t, least, least + 2.0 * KeeperMotor.PIVOT_RATE_RAD_S / KeeperMotor.PIVOT_ACCEL_RAD_S2 + DT,
				"%.1f: in the time its rate and its edges give" % turn)


# Turned, a T-push goes straight to a spot off his line, and a shuffle to
# where the spot falls on it.
func test_footwork_goes_in_his_turned_frame() -> void:
	var turn: float = 0.4
	var line := Vector2(cos(turn), -sin(turn))
	var spot: Vector2 = line * 1.0 + Vector2(-sin(turn), -cos(turn)) * 0.3
	for shuffle: bool in [false, true]:
		_motor = KeeperMotor.new()
		_motor.face(turn)
		_run_checked("turning")
		var to: Vector2 = line * 1.0 if shuffle else spot
		if shuffle:
			_motor.shuffle_to(spot)
		else:
			_motor.push_to(spot)
		var way: Vector2 = to.normalized()
		var off: float = 0.0
		while not _motor.is_idle():
			_motor.step(DT)
			off = maxf(off, absf(Vector2(_motor.x, _motor.z).cross(way)))
		var what: String = "shuffle" if shuffle else "T-push"
		assert_lt(off, 1e-5, "%s: straight there" % what)
		assert_almost_eq(Vector2(_motor.x, _motor.z), to, Vector2.ONE * 1e-4, "%s: there" % what)
		assert_eq(_motor.yaw, turn, "%s: still turned" % what)


func test_a_move_from_the_wrong_rest_is_refused() -> void:
	_motor.slide_to(Vector2(1.0, 0.0))
	_motor.rise()
	_motor.rvh_fold_out()
	_motor.push_to(Vector2(0.5, 0.0))
	_run_checked("refusals then a push")
	assert_eq(_motor.refused, 3, "a slide, a rise and a fold out, on his feet")
	assert_almost_eq(_motor.x, 0.5, 1e-4, "the push he could make")
	_motor.drop_down()
	_motor.push_to(Vector2(0.0, 0.0))
	_run_checked("down, then a push")
	assert_eq(_motor.refused, 4, "a push, down")
	assert_eq(_motor.rest, R.DOWN)


# Skating across with a spot that moves, then asked down there: he drops at
# once, without stopping first, and carries his speed on his pads; every tick
# unbroken.
func test_asked_down_while_skating_he_drops_carrying_his_speed() -> void:
	_motor = KeeperMotor.new()
	_motor.z = -1.0
	var spot := Vector2(0.0, -1.0)
	var v := Vector2(1.5, 0.0)
	for i: int in int(0.6 / DT):
		spot += v * DT
		_motor.go_to(spot, 0.0, R.FEET, v)
		_motor.step(DT)
	var moving: float = _motor.glide.velocity.length()
	assert_gt(moving, 1.0, "skating with it")
	var was: float = _motor.x
	_motor.go_to(spot + v * 0.3, 0.0, R.DOWN)
	_solve()
	var goal: Vector2 = _motor.route.spot
	var bones: Array[Vector3] = _bones()
	var t: float = 0.0
	var landed: float = NAN
	while _motor.rest != R.DOWN and t < 1.0:
		_motor.step(DT)
		t += DT
		if is_nan(landed) and _motor.save_move.is_set():
			landed = t
			assert_true(_motor.carries(), "landed, the slide still carrying him toward his goal")
		_solve()
		var now: Array[Vector3] = _bones()
		for b: int in KeeperSkeleton.BONE_COUNT:
			assert_lt(now[b].distance_to(bones[b]), MAX_BONE_STEP_M, "t %.3f bone %d" % [t, b])
		bones = now
	assert_eq(_motor.rest, R.DOWN, "down")
	assert_lte(landed, _motor.save_move.drop_s + 2.0 * DT, "in the butterfly in the drop's time, no stop first")
	assert_gt(_motor.x - was, 0.5 * moving * landed, "his speed carried on")
	assert_false(_motor.carries(), "the slide let go")
	assert_lt(_motor.x - goal.x, moving * 2.0 * DT, "not on by his goal")
	var scoot: float = KeeperSlide.KNEE_SHUFFLE_M_S
	assert_lt(goal.x - _motor.x, scoot * scoot / (2.0 * _motor.save_move.pad_friction) + moving * 2.0 * DT,
			"short of it by no more than a slide slowed to a scoot leaves his knees")


# Down, a push across and another the moment it stops: the second sets out as
# soon as the first has stopped and the push leg is back down, the lean back
# against its stop easing out through it; every tick unbroken.
func test_down_pushes_follow_one_another() -> void:
	_motor = KeeperMotor.new()
	_motor.z = -1.0
	_motor.go_to(Vector2(0.0, -1.0), 0.0, R.DOWN)
	_run_checked("down")
	_motor.go_to(Vector2(0.4, -1.0), 0.0, R.DOWN)
	_run_checked("first push")
	assert_gt(_motor.slide._stop, 0.0, "still leaning back against the stop")
	_motor.go_to(Vector2(0.0, -1.0), 0.0, R.DOWN)
	_motor.step(DT)
	assert_eq(_motor._mover, KeeperMotor.Mover.SLIDE, "the next push under way at once")
	_run_checked("second push")


# Down, a goal within his knees' reach he scoots to in the butterfly, no faster
# than his knees shuffle and with nothing committed: a goal that moves he
# follows, a low save can cut in, and one moved past his reach he pushes for.
func test_down_he_scoots_on_his_knees_and_follows_his_goal() -> void:
	_motor.z = -1.0
	_motor.go_to(Vector2(0.0, -1.0), 0.0, R.DOWN)
	_run_checked("down")
	var butterfly := KeeperPose.new()
	KeeperPoses.butterfly(butterfly)
	_motor.go_to(Vector2(0.25, -1.0), 0.0, R.DOWN)
	var was := Vector2(_motor.x, _motor.z)
	for i: int in 8:
		_motor.step(DT)
		assert_eq(_motor._mover, KeeperMotor.Mover.KNEES, "scooting, tick %d" % i)
		assert_true(_motor.can_save(true), "a save can cut in, tick %d" % i)
		var at := Vector2(_motor.x, _motor.z)
		assert_almost_eq(at.distance_to(was), KeeperSlide.KNEE_SHUFFLE_M_S * DT, 1e-6, "at his knees' pace, tick %d" % i)
		was = at
		_motor.pose(_pose)
		for leg: int in 2:
			assert_almost_eq(_pose.legs[leg].knee, butterfly.legs[leg].knee, Vector3.ONE * 1e-6,
					"both pads down, tick %d" % i)
	_motor.go_to(Vector2(-0.1, -0.9), 0.0, R.DOWN)
	_motor.step(DT)
	assert_eq(_motor._mover, KeeperMotor.Mover.KNEES, "a goal moved the other way followed without stopping")
	assert_lt(Vector2(_motor.x, _motor.z).distance_to(Vector2(-0.1, -0.9)), was.distance_to(Vector2(-0.1, -0.9)), "toward it")
	_run_checked("to the moved goal")
	assert_almost_eq(Vector2(_motor.x, _motor.z), Vector2(-0.1, -0.9), Vector2.ONE * KeeperRoute.THERE_M, "there")
	assert_eq(_motor.rest, R.DOWN)
	_motor.go_to(Vector2(0.8, -0.9), 0.0, R.DOWN)
	_motor.step(DT)
	_motor.step(DT)
	assert_eq(_motor._mover, KeeperMotor.Mover.SLIDE, "past his knees' reach he pushes")
	assert_true(_motor.slides())


# Skating across with the play, asked down where he already is: his edges take
# the speed off as he drops, and he is down there, not slid on past it.
func test_dropped_where_he_already_is_he_does_not_slide_on() -> void:
	_motor.z = -1.0
	var spot := Vector2(0.0, -1.0)
	var v := Vector2(2.0, 0.0)
	for i: int in int(0.6 / DT):
		spot += v * DT
		_motor.go_to(spot, 0.0, R.FEET, v)
		_motor.step(DT)
	var moving: float = _motor.glide.velocity.length()
	assert_gt(moving, 1.5, "skating with it")
	var at := Vector2(_motor.x, _motor.z)
	_motor.go_to(at, 0.0, R.DOWN)
	var t: float = 0.0
	while _motor.rest != R.DOWN and t < 1.0:
		_motor.step(DT)
		t += DT
	assert_eq(_motor.rest, R.DOWN, "down")
	var stop: float = moving * moving / (2.0 * _motor.save_move.edge_decel)
	assert_lt(Vector2(_motor.x, _motor.z).distance_to(at), stop + moving * 2.0 * DT,
			"no further on than his edges take to stop him")
	assert_lt(Vector2(_motor.x, _motor.z).distance_to(at), 0.25 * moving * moving / (2.0 * _motor.save_move.pad_friction),
			"a fraction of what his pads' friction alone would slide him")


# Down and turning on his knees to a new facing, a goal he has to push for
# stops the turn: the push starts sooner than the turn would have ended.
func test_a_turn_on_his_knees_gives_way_to_a_push() -> void:
	var started: Array[float] = []
	for gives_way: bool in [false, true]:
		_motor = KeeperMotor.new()
		_motor.rest = R.DOWN
		_motor.z = -1.0
		_motor.go_to(Vector2(0.0, -1.0), deg_to_rad(80.0), R.DOWN)
		var t: float = 0.0
		while not _motor.slide.turns() and t < 1.0:
			_motor.step(DT)
			t += DT
		assert_true(_motor.slide.turns(), "turning on his knees")
		for i: int in 3:
			_motor.step(DT)
		if gives_way:
			_motor.go_to(Vector2(-1.0, -1.0), 0.0, R.DOWN)
		t = 0.0
		while t < 2.0 and not (_motor.slides() and not _motor.slide.turns() and _motor.slide.phase != KeeperSlide.Phase.TURN \
				and Vector2(_motor.x, _motor.z).distance_to(Vector2(0.0, -1.0)) > 0.05):
			if not gives_way and _motor.is_idle():
				_motor.go_to(Vector2(-1.0, -1.0), 0.0, R.DOWN)
			_motor.step(DT)
			t += DT
			assert_eq(_motor.rest, R.DOWN, "on his knees throughout")
		started.append(t)
	assert_lt(started[1], started[0] - 2.0 * DT, "pushing sooner for having stopped the turn")


# Dropped while he skates back, a goal across him rather than behind is a push
# from where he lands: his edges take off the speed that was carrying him back
# as he drops, and the push goes as he lands.
func test_a_goal_across_him_ends_the_slide_he_dropped_with() -> void:
	_motor.z = -1.6
	var spot := Vector2(0.0, -1.6)
	var back := Vector2(0.0, 1.8)
	for i: int in int(0.5 / DT):
		spot += back * DT
		_motor.go_to(spot, 0.0, R.FEET, back)
		_motor.step(DT)
	var backing: float = _motor.glide.velocity.y
	assert_gt(backing, 1.0, "backing in")
	var from_z: float = _motor.z
	_motor.go_to(Vector2(0.9, _motor.z + 0.2), 0.0, R.DOWN)
	var t: float = 0.0
	while not _motor.slides() and t < 1.0:
		_motor.step(DT)
		t += DT
	assert_true(_motor.slides(), "the push for it under way")
	assert_lt(t, 2.0 * _motor.save_move.drop_s, "as he lands")
	assert_false(_motor.carries(), "the slide he dropped with let go")
	assert_lt(_motor.z - from_z, 0.5 * backing * backing / (2.0 * _motor.save_move.pad_friction),
			"not carried on back by the speed he dropped with")


# Down, a pad asked out goes out at rest, stays out through a scoot and a
# slide it leads, and is brought back under him before a slide the other way,
# a rotation or getting up starts; a save takes it into the pose it cuts in
# from. Every tick unbroken.
func test_a_pad_out_rides_what_it_can_and_comes_in_for_what_needs_the_leg() -> void:
	_motor.z = -1.1
	_motor.go_to(Vector2(0.0, -1.1), 0.0, R.DOWN)
	_run_checked("down")
	_motor.pad_out.asked = 1.0
	_motor.go_to(Vector2(0.0, -1.1), 0.0, R.DOWN)
	var was: Array[Vector3] = _bones()
	for i: int in int(0.3 / DT):
		_motor.step(DT)
		var at: Array[Vector3] = _bones()
		for b: int in KeeperSkeleton.BONE_COUNT:
			assert_lt(at[b].distance_to(was[b]), MAX_BONE_STEP_M, "going out, tick %d bone %d" % [i, b])
		was = at
	assert_eq(_motor.pad_out.share, 1.0, "out at rest")
	# Facing as the slide leaves him, so no rotation follows it.
	var turned: float = KeeperSlide.facing((Vector2(0.8, -0.9) - Vector2(0.0, -1.1)).normalized(), 1.0)
	_motor.go_to(Vector2(0.8, -0.9), turned, R.DOWN)
	_motor.step(DT)
	_motor.step(DT)
	assert_true(_motor.slides(), "a slide it leads starts at once")
	_run_checked("the slide it leads")
	assert_eq(_motor.pad_out.share, 1.0, "out the whole way")
	_motor.go_to(Vector2(0.95, -0.85), turned, R.DOWN)
	_run_checked("a scoot")
	assert_eq(_motor.pad_out.share, 1.0, "out through a scoot")
	_motor.go_to(Vector2(0.0, -1.0), turned, R.DOWN)
	_motor.step(DT)
	_motor.step(DT)
	assert_false(_motor.slides(), "the other way: not yet")
	assert_lt(_motor.pad_out.share, 1.0, "the pad coming back under him first")
	var waited: float = 0.0
	while not _motor.slides() and waited < 1.0:
		_motor.step(DT)
		waited += DT
	assert_eq(_motor.pad_out.share, 0.0, "in before he pushes off that leg")
	assert_almost_eq(waited, _motor.pad_out.out_s, 3.0 * DT, "the leg's time")
	_run_checked("the slide the other way")
	_motor.pad_out.asked = -1.0
	for i: int in int(0.3 / DT):
		_motor.step(DT)
	assert_eq(_motor.pad_out.share, 1.0, "out the other side")
	_motor.go_to(Vector2(0.0, -1.0), 0.0, R.FEET)
	_motor.step(DT)
	assert_eq(_motor.rest, R.DOWN)
	assert_eq(_motor._mover, KeeperMotor.Mover.NONE, "up: not before the pad is in")
	_run_checked("up")
	assert_eq(_motor.rest, R.FEET)
	assert_eq(_motor.pad_out.share, 0.0)
	assert_eq(_motor.refused, 0)


func test_a_save_takes_the_pad_out_into_the_pose_it_cuts_in_from() -> void:
	_motor.z = -1.1
	_motor.go_to(Vector2(0.0, -1.1), 0.0, R.DOWN)
	_run_checked("down")
	_motor.pad_out.asked = 1.0
	for i: int in int(0.3 / DT):
		_motor.step(DT)
	var was: Array[Vector3] = _bones()
	_motor.save(KeeperSaveMove.Low.BUTTERFLY, 1.0)
	assert_eq(_motor.pad_out.share, 0.0, "the save's now")
	var t: float = 0.0
	while t < 0.5:
		_motor.step(DT)
		t += DT
		var at: Array[Vector3] = _bones()
		for b: int in KeeperSkeleton.BONE_COUNT:
			assert_lt(at[b].distance_to(was[b]), MAX_BONE_STEP_M, "t %.3f bone %d" % [t, b])
		was = at

