extends GutTest

# The low ready laid over his stance (KeeperLowReady, through KeeperMotor): set
# and asked, he sinks into it; a shuffle or skating with the play he makes in
# it, stroking from the wide stance; any other move takes him back out of it as
# it starts;
# every tick of either unbroken, his gear out of the ice and his arms on the
# stick. A drop or a low save from it is the shorter fall: the knees' fall to
# the ice from where it holds them, at the root of the heights.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const PAD_GIVE_M: float = 0.025
const HARD_GIVE_M: float = 0.005
const MAX_BONE_STEP_M: float = 12.0 * DT  # nothing on him moves 12 m/s
const B := KeeperSkeleton.Bone
const R := KeeperMotor.Rest
const Low := KeeperSaveMove.Low

var _motor: KeeperMotor = null
var _pose := KeeperPose.new()
var _skel := KeeperSkeleton.new()
var _was: Array[Vector3] = []


func before_each() -> void:
	_motor = KeeperMotor.new()
	_was = _bones()


func _bones() -> Array[Vector3]:
	_motor.pose(_pose)
	_skel.pose(_pose)
	var out: Array[Vector3] = []
	var to_world := Transform3D(Basis(Vector3.UP, _motor.yaw), Vector3(_motor.x, 0.0, _motor.z))
	for b: int in KeeperSkeleton.BONE_COUNT:
		out.append(to_world * _skel.xf[b].origin)
	return out


func _lowest(part: int) -> float:
	var t: Transform3D = KeeperGear.box(_skel, part)
	var h: Vector3 = KeeperGear.half_extents(part)
	return t.origin.y - absf(t.basis.x.y) * h.x - absf(t.basis.y.y) * h.y - absf(t.basis.z.y) * h.z


# One tick, checked: nothing on him jumps, his gear stays out of the ice and
# his arms on the stick. Only a breach is asserted, so a run of ticks logs
# what went wrong rather than every tick that did not.
func _step_checked(what: String) -> void:
	_motor.step(DT)
	var at: Array[Vector3] = _bones()
	for b: int in KeeperSkeleton.BONE_COUNT:
		var moved: float = at[b].distance_to(_was[b])
		if moved >= MAX_BONE_STEP_M:
			assert_lt(moved, MAX_BONE_STEP_M, "%s bone %d" % [what, b])
	_was = at
	for part: int in KeeperGear.PART_COUNT:
		var soft: bool = KeeperGear.save_part(part) == GoalieSaveRules.SavePart.PAD
		var floor_y: float = -(PAD_GIVE_M if soft else HARD_GIVE_M)
		if _lowest(part) < floor_y:
			assert_gte(_lowest(part), floor_y, "%s %s" % [what, KeeperGear.Part.keys()[part]])
	var glove_wrist: Vector3 = _skel.xf[B.FOREARM_G] * Vector3(0.0, -KeeperAnatomy.FOREARM_M, 0.0)
	var blocker_wrist: Vector3 = _skel.xf[B.FOREARM_B] * Vector3(0.0, -KeeperAnatomy.FOREARM_M, 0.0)
	var glove_gap: float = glove_wrist.distance_to(_skel.xf[B.HAND_G].origin)
	var blocker_gap: float = blocker_wrist.distance_to(_skel.xf[B.HAND_B] * KeeperAnatomy.BLOCKER_WRIST)
	if glove_gap > 0.002:
		assert_almost_eq(glove_gap, 0.0, 0.002, "%s: the glove arm reaches its hand" % what)
	if blocker_gap > 0.002:
		assert_almost_eq(blocker_gap, 0.0, 0.002, "%s: the blocker arm reaches the stick" % what)


func _run_checked(what: String, seconds: float) -> void:
	for i: int in roundi(seconds / DT):
		_step_checked("%s t %.3f" % [what, i * DT])


func _sink() -> void:
	_motor.low_ready.asked = true
	_run_checked("sinking", KeeperLowReady.SINK_S + 0.05)


func _knee_height(pose: KeeperPose) -> float:
	_skel.pose(pose)
	return _skel.xf[KeeperSkeleton.SHIN[0]].origin.y


func test_set_and_asked_he_sinks_into_the_low_ready() -> void:
	_sink()
	assert_eq(_motor.low_ready.share, 1.0, "all the way down into it")
	var low := KeeperPose.new()
	KeeperPoses.low_ready(low)
	_skel.pose(low)
	var knee: Vector3 = _skel.xf[KeeperSkeleton.SHIN[0]].origin
	_motor.pose(_pose)
	_skel.pose(_pose)
	assert_almost_eq(_skel.xf[KeeperSkeleton.SHIN[0]].origin, knee, Vector3.ONE * 1e-4, "the low ready's own knees")
	assert_true(_motor.is_idle(), "sinking is no move")
	_motor.low_ready.asked = false
	_run_checked("rising in place", KeeperLowReady.RISE_S + 0.05)
	assert_eq(_motor.low_ready.share, 0.0, "back up when no longer asked")


func test_a_move_takes_him_out_of_it_as_it_starts() -> void:
	_sink()
	_motor.push_to(Vector2(0.8, 0.0))
	_run_checked("pushing off", KeeperLowReady.RISE_S + 0.02)
	assert_eq(_motor.low_ready.share, 0.0, "up out of it as the push starts")
	_run_checked("the push", 1.5)
	assert_gt(_motor.low_ready.share, 0.0, "set again and still asked, sinking again")


# Backing in with a rush at full depth glide, he stays sunk: the speed that
# takes him out of it is across his line, not in depth.
func test_backing_in_at_full_glide_he_stays_low() -> void:
	_motor.z = -1.8
	_was = _bones()
	_sink()
	var spot := Vector2(0.0, -1.8)
	var v := Vector2(0.0, GameRules.DEFAULT_GOALIE_DEPTH_SPEED_M_S)
	var fastest: float = 0.0
	for i: int in int(0.5 / DT):
		spot += v * DT
		_motor.go_to(spot, 0.0, R.FEET, v)
		_step_checked("backing in t %.3f" % (i * DT))
		fastest = maxf(fastest, absf(_motor.glide.velocity.y))
	assert_gt(fastest, _motor.glide.shuffle_speed, "backing in faster than he shuffles")
	assert_eq(_motor.low_ready.share, 1.0, "still sunk")


# Skating with the play no faster than he shuffles, he stays sunk; skated
# harder, he comes up out of it.
func test_skating_with_the_play_he_stays_low() -> void:
	_motor.z = -1.0
	_was = _bones()
	_motor.low_ready.asked = true
	var spot := Vector2(0.0, -1.0)
	var v := Vector2(1.2, 0.0)
	for i: int in int(0.8 / DT):
		_motor.go_to(spot, 0.0, R.FEET, v)
		_step_checked("tracking t %.3f" % (i * DT))
		spot += v * DT
	assert_gt(_motor.glide.velocity.length(), 1.0, "skating with it")
	assert_eq(_motor.low_ready.share, 1.0, "sunk as he goes")
	v = Vector2(3.5, 0.0)
	for i: int in int(0.6 / DT):
		_motor.go_to(spot, 0.0, R.FEET, v)
		_step_checked("chasing t %.3f" % (i * DT))
		spot += v * DT
	assert_eq(_motor.low_ready.share, 0.0, "up out of it to chase")


# Sunk, he moves across in it by shuffling, as goalies do, rather than sliding
# with his legs still: he stays sunk, and each stroke's trail skate holds its
# place on the ice as he passes over it, then comes back in under him; by the
# glide skating with the play the same.
func test_he_shuffles_across_in_it_still_sunk() -> void:
	for glide: bool in [false, true]:
		_motor = KeeperMotor.new()
		_was = _bones()
		_sink()
		var what: String = "skating with the play" if glide else "shuffling"
		if glide:
			_motor.go_to(Vector2(0.6, 0.0), 0.0, R.FEET, Vector2.ZERO, true)
		else:
			_motor.shuffle_to(Vector2(0.4, 0.0))
		var trail: int = KeeperSkeleton.FOOT[0]
		var out: float = 0.0
		var planted: float = NAN
		while not _motor.is_idle():
			_step_checked(what)
			assert_eq(_motor.low_ready.share, 1.0, "%s: still sunk at x %.3f" % [what, _motor.x])
			var skate: float = _skel.xf[trail].origin.x
			var at: float = _was[trail].x
			out = maxf(out, -skate - KeeperPoses.LOW_READY_SKATE_HALF_SPACING_M)
			if is_nan(planted) and _motor.x > 0.01:
				planted = at
			if not is_nan(planted) and _motor.x < 0.1:
				assert_almost_eq(at, planted, 0.03, "%s at x %.3f: the trail skate holds its place" % [what, _motor.x])
		assert_gt(out, 0.05, "%s: the trail skate strokes out from the stance" % what)
		_motor.pose(_pose)
		_skel.pose(_pose)
		assert_almost_eq(-_skel.xf[trail].origin.x, KeeperPoses.LOW_READY_SKATE_HALF_SPACING_M, 0.02,
				"%s: back in under him once set" % what)


# The drop's time goes as the root of the knees' fall to the ice.
func _drop_time(sunk: bool) -> float:
	_motor = KeeperMotor.new()
	_was = _bones()
	if sunk:
		_sink()
	_motor.drop_down()
	var t: float = 0.0
	while _motor.rest != R.DOWN and t < 1.0:
		_step_checked("dropping")
		t += DT
	assert_eq(_motor.low_ready.share, 0.0, "out of the A as he lands")
	return t


func test_the_drop_from_it_is_the_shorter_fall() -> void:
	var standing := KeeperPose.new()
	var low := KeeperPose.new()
	var down := KeeperPose.new()
	KeeperPoses.ready(standing)
	KeeperPoses.low_ready(low)
	KeeperPoses.butterfly(down)
	var ice: float = _knee_height(down)
	var share: float = sqrt((_knee_height(low) - ice) / (_knee_height(standing) - ice))
	assert_lt(share, 1.0)
	assert_almost_eq(_drop_time(true), _drop_time(false) * share, 2.0 * DT, "the root of the heights")


func test_a_low_save_from_it_is_the_shorter_fall_and_a_kick_is_not() -> void:
	for low: int in [Low.BUTTERFLY, Low.KICK]:
		var times: Array[float] = []
		for sunk: bool in [false, true]:
			_motor = KeeperMotor.new()
			_was = _bones()
			if sunk:
				_sink()
			_motor.save(low, 1.0)
			var t: float = 0.0
			while not _motor.save_move.is_set() and t < 1.0:
				_step_checked("%s save %s t %.3f" % [Low.keys()[low], "sunk" if sunk else "cold", t])
				t += DT
			times.append(t)
		var share: float = KeeperLowReady.fall_share_at(1.0)
		if low == Low.KICK:
			assert_almost_eq(times[1], times[0], DT, "a kick is a push, in the drop's time")
		else:
			assert_almost_eq(times[1], times[0] * share, 2.0 * DT, "the shorter fall")


func test_the_save_prices_the_shorter_fall() -> void:
	var read := KeeperShotRead.new()
	read.start()
	read.age = 1.0
	# Low to his glove-side corner with him off his angle the other way: only a
	# leg out along the ice gets there.
	read.step(0.0, Vector3(0.0, 0.05, -6.0), Vector3(-3.5, 0.98, 30.0))
	var save := KeeperSave.new()
	# Hands there at once, so the save's time is its leg's.
	save.glove_speed_m_s = 1000.0
	save.blocker_speed_m_s = 1000.0
	_motor.x = 0.4
	_motor.z = -1.0
	_was = _bones()
	save.choose(read, _motor, false)
	var cold: float = save.ready_s
	_sink()
	save.choose(read, _motor, false)
	assert_eq(save.low, Low.EXTENSION)
	assert_almost_eq(save.ready_s, cold * KeeperLowReady.fall_share_at(1.0), 1e-4, "down sooner from the A")
