extends GutTest

# The keeper's moves strung together (KeeperMotor): a whole sequence across the
# crease and back, every hand-off from one move to the next leaving nothing on
# him jumping and his gear out of the ice; the pivot turning him at its rate and
# stopping on its facing; footwork going in his turned frame; and a move asked
# for from the wrong rest refused.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const PAD_GIVE_M: float = 0.025
const HARD_GIVE_M: float = 0.005
const MAX_BONE_STEP_M: float = 0.1
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
