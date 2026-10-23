extends GutTest

# The keeper given where to be (KeeperMotor.go_to / seal, KeeperRoute): from
# every rest to every kind of goal he gets there, every tick unbroken (nothing
# jumping, his gear out of the ice, his arms on the stick), every move he
# makes one he can make, and in the time the route planned, which is what the
# brain will read; the shuffle taken where it is no slower than the T-push, a
# turn before the feet; and a spot or facing moved under a move taken on by it.

const DT: float = 1.0 / 120.0
const PAD_GIVE_M: float = 0.025
const HARD_GIVE_M: float = 0.005
const MAX_BONE_STEP_M: float = 0.1
const GOAL_LINE_Z: float = 0.35
# The planned time against the time taken: the movers' own models are tick
# exact, and a slide's turn as it loads costs a little the model leaves out.
const PLAN_TOLERANCE_S: float = 0.05
const B := KeeperSkeleton.Bone
const R := KeeperRoute.Rest
const DO := KeeperRoute.Do

var _motor: KeeperMotor = null
var _pose := KeeperPose.new()
var _skel := KeeperSkeleton.new()


func before_each() -> void:
	_motor = KeeperMotor.new()


func _iron(post_side: float) -> Vector2:
	return Vector2(post_side * GameRules.NET_HALF_WIDTH, GOAL_LINE_Z)


func _place(rest: int, at: Vector2, turn: float) -> void:
	_motor = KeeperMotor.new()
	if rest == R.POST:
		_motor.x = 0.0
		_motor.z = -0.5
		_motor.seal(_iron(signf(at.x)), signf(at.x))
		_run_checked("onto the post")
		return
	_motor.rest = rest
	_motor.x = at.x
	_motor.z = at.y
	_motor.yaw = turn


func _world(v: Vector3) -> Vector3:
	return Basis(Vector3.UP, _motor.yaw) * v + Vector3(_motor.x, 0.0, _motor.z)


func _bones() -> Array[Vector3]:
	_motor.pose(_pose)
	_skel.pose(_pose)
	var out: Array[Vector3] = []
	for b: int in KeeperSkeleton.BONE_COUNT:
		out.append(_world(_skel.xf[b].origin))
	return out


func _lowest(part: int) -> float:
	var t: Transform3D = KeeperGear.box(_skel, part)
	var h: Vector3 = KeeperGear.half_extents(part)
	return t.origin.y - absf(t.basis.x.y) * h.x - absf(t.basis.y.y) * h.y - absf(t.basis.z.y) * h.z


# Steps until he is where he was asked to be, checking every tick; the time it
# took.
func _run_checked(what: String, limit: float = 6.0) -> float:
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
	assert_true(_motor.is_idle(), "%s: there inside %.0f s" % [what, limit])
	return t


func test_from_every_rest_to_every_goal_he_gets_there_in_the_time_planned() -> void:
	var starts: Array = [
		[R.FEET, Vector2(0.0, -0.6), 0.0], [R.FEET, Vector2(0.5, -0.3), 0.4],
		[R.DOWN, Vector2(-0.3, -0.5), 0.0], [R.POST, Vector2(1.0, 0.0), 0.0],
	]
	# On his feet across, forward, steeper than a diagonal and a short step;
	# down across and near; sealed on either post.
	var goals: Array = [
		[R.FEET, Vector2(-0.8, -0.5), -0.3], [R.FEET, Vector2(0.0, -1.2), 0.0],
		[R.FEET, Vector2(0.4, -1.3), 0.0], [R.FEET, Vector2(0.15, -0.6), 0.0],
		[R.DOWN, Vector2(0.9, -0.4), 0.0], [R.DOWN, Vector2(-0.2, -0.6), 0.0],
		[R.POST, Vector2(1.0, 0.0), 0.0], [R.POST, Vector2(-1.0, 0.0), 0.0],
	]
	for start: Array in starts:
		for goal: Array in goals:
			_place(start[0], start[1], start[2])
			var spot: Vector2 = goal[1]
			var post_side: float = signf(spot.x)
			if goal[0] == R.POST:
				_motor.seal(_iron(post_side), post_side)
			else:
				_motor.go_to(spot, goal[2], goal[0])
			var what: String = "%s %s to %s %s" % [R.keys()[start[0]], start[1], R.keys()[goal[0]], spot]
			var planned: float = _motor.time_to_goal()
			var took: float = _run_checked(what)
			assert_almost_eq(took, planned, PLAN_TOLERANCE_S, "%s: in the time planned" % what)
			assert_eq(_motor.rest, goal[0], "%s: resting as asked" % what)
			assert_eq(_motor.refused, 0, "%s: every move one he could make" % what)
			var at := Vector2(_motor.x, _motor.z)
			if goal[0] == R.POST:
				assert_eq(_motor.post.side, post_side, "%s: on that post" % what)
				assert_almost_eq(at, _motor.post.seal_spot(_iron(post_side), post_side),
						Vector2.ONE * KeeperRoute.THERE_M, "%s: sealed" % what)
			else:
				assert_almost_eq(at, spot, Vector2.ONE * KeeperRoute.THERE_M, "%s: on the spot" % what)
			if goal[0] == R.FEET:
				assert_almost_eq(_motor.yaw, float(goal[2]), KeeperRoute.FACED_RAD, "%s: facing" % what)


# A spot near him he skates to, turning as he goes; one past the glide's reach
# a T-push takes him to, straight or on a diagonal.
func test_a_near_spot_is_skated_to_and_a_far_one_pushed_for() -> void:
	_motor.go_to(Vector2(0.3, 0.0), 0.0)
	_motor.time_to_goal()
	assert_eq(_motor.route.first, DO.GLIDE, "0.3 m across")
	_motor.go_to(Vector2(-0.5, -0.4), 0.3)
	_motor.time_to_goal()
	assert_eq(_motor.route.first, DO.GLIDE, "near, on a diagonal and turned")
	_motor.go_to(Vector2(-1.5, 0.0), 0.0)
	_motor.time_to_goal()
	assert_eq(_motor.route.first, DO.T_PUSH, "1.5 m across")
	_motor.go_to(Vector2(-1.2, -0.9), 0.0)
	_motor.time_to_goal()
	assert_eq(_motor.route.first, DO.T_PUSH, "a far diagonal")


# Past the glide's reach, a turn his trunk can lead is made on the way; a
# bigger one before his feet move.
func test_he_turns_on_the_way_or_before_his_feet_move() -> void:
	var within: float = KeeperMotor.LEAD_MAX_RAD * 0.8
	_motor.go_to(Vector2(1.5, 0.0), within)
	_motor.time_to_goal()
	assert_eq(_motor.route.first, DO.T_PUSH, "a turn within the lead")
	var beyond: float = KeeperMotor.LEAD_MAX_RAD * 1.5
	_motor.go_to(Vector2(1.5, 0.0), beyond)
	_motor.time_to_goal()
	assert_eq(_motor.route.first, DO.FACE, "a turn beyond it")
	assert_eq(_motor.route.first_side, beyond)


func test_down_he_recovers_toward_a_spot_on_his_feet_and_rises_under_one_on_him() -> void:
	for side: float in [1.0, -1.0]:
		_place(R.DOWN, Vector2.ZERO, 0.0)
		_motor.go_to(Vector2(side * 0.8, 0.0), 0.0)
		_motor.time_to_goal()
		assert_eq(_motor.route.first, DO.RECOVER)
		assert_eq(_motor.route.first_side, side, "toward it")
	_motor.go_to(Vector2(0.0, -0.3), 0.0)
	_motor.time_to_goal()
	assert_eq(_motor.route.first, DO.RISE)


func test_square_on_the_overlap_he_drops_into_the_rvh() -> void:
	for side: float in [1.0, -1.0]:
		var overlap: Vector2 = _motor.post.overlap_spot(_iron(side), side)
		_place(R.FEET, overlap, 0.0)
		_motor.seal(_iron(side), side)
		_motor.time_to_goal()
		assert_eq(_motor.route.first, DO.RVH_DROP_IN)


# Turned on the overlap to a puck at a sharp angle, he drops into the RVH from
# there, the drop swinging him square onto the seal at his pivot's rate as the
# knee falls; not turned square and pushed back across first.
func test_turned_on_the_overlap_he_drops_straight_in() -> void:
	for side: float in [1.0, -1.0]:
		var turn: float = -side * 1.2
		_place(R.FEET, _motor.post.overlap_spot(_iron(side), side, turn), turn)
		_motor.seal(_iron(side), side)
		var planned: float = _motor.time_to_goal()
		var what: String = "%+.0f" % side
		assert_eq(_motor.route.first, DO.RVH_DROP_IN, "%s: dropped in from there" % what)
		assert_almost_eq(planned, _motor.post.drop_s + 1.2 / KeeperMotor.PIVOT_RATE_RAD_S, 1e-6,
				"%s: the drop and the swing" % what)
		var took: float = _run_checked("%s turned drop-in" % what)
		assert_almost_eq(took, planned, PLAN_TOLERANCE_S, "%s: as planned" % what)
		assert_eq(_motor.rest, R.POST, "%s: sealed" % what)


# The spot moved further along his line mid-push: he carries on to it, in the
# time one push there takes, not stopping first.
func test_a_spot_moved_along_his_push_is_taken_on_without_stopping() -> void:
	_motor.go_to(Vector2(1.5, 0.0), 0.0)
	var t: float = 0.0
	for i: int in 15:
		_motor.step(DT)
		t += DT
	_motor.go_to(Vector2(2.1, 0.0), 0.0)
	t += _run_checked("on along")
	var push: float = KeeperFootwork.push_time(2.1, _motor.footwork.t_push_speed, _motor.footwork.accel)
	assert_almost_eq(t, push + KeeperFootwork.SETTLE_S, 3.0 * DT, "one push's time")
	assert_almost_eq(_motor.x, 2.1, 1e-4)


func test_a_facing_moved_mid_pivot_is_turned_on_to() -> void:
	_motor.go_to(Vector2.ZERO, 0.8)
	for i: int in 10:
		_motor.step(DT)
	_motor.go_to(Vector2.ZERO, 0.3)
	_run_checked("turned on to")
	assert_eq(_motor.yaw, 0.3)
	assert_eq(_motor.refused, 0)


# The last order wins: a move asked for drops the goal; a goal drops the moves
# still waiting.
func test_the_last_order_wins() -> void:
	_motor.go_to(Vector2(1.0, 0.0), 0.0)
	_motor.push_to(Vector2(-0.5, 0.0))
	_run_checked("asked after the goal")
	assert_almost_eq(_motor.x, -0.5, 1e-4)
	_motor.push_to(Vector2(0.5, 0.0))
	_motor.c_cut_to(Vector2(0.5, -0.5))
	_motor.go_to(Vector2(-0.8, 0.0), 0.0)
	_run_checked("a goal after the asks")
	assert_almost_eq(Vector2(_motor.x, _motor.z), Vector2(-0.8, 0.0), Vector2.ONE * 1e-4)
