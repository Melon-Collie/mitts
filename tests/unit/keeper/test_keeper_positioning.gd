extends GutTest

# The first brain (KeeperPositioning), from the puck alone: in the zone on the
# line from the puck to the net's centre at the top of the crease, square to
# it; out of the zone in the middle of the crease; at a sharp angle below the
# dots on the near post, turned to the puck; below the goal line sealed on the
# post on its side, and behind the net on the post he holds until the puck
# will be out the other side before he could get across; a puck on a boundary
# never flipping him; a puck carried round the zone tracked, every tick
# unbroken, to rest where it stops; and his depth answering the play: the top
# of the crease against a still or slow puck, deeper against one coming at him
# or swinging across him or with an open receiver across the slot, no deeper
# than the floor. A pass he reads he skates to where its stick meets it, set
# there, turned to it.

const DT: float = 1.0 / 120.0
const PLANNER_EVERY: int = 4
const PAD_GIVE_M: float = 0.025
const HARD_GIVE_M: float = 0.005
const MAX_BONE_STEP_M: float = 0.1
const Z := KeeperPositioning.Zone
const R := KeeperRoute.Rest

var _brain: KeeperPositioning = null
var _motor: KeeperMotor = null


func before_each() -> void:
	_brain = KeeperPositioning.new()
	_motor = KeeperMotor.new()


func _forward(turn: float) -> Vector2:
	return Vector2(-sin(turn), -cos(turn))


func _faces(at: Vector2, puck: Vector2, what: String) -> void:
	assert_almost_eq(_forward(_motor.route.facing).dot((puck - at).normalized()), 1.0, 1e-4,
			"%s: square to the puck" % what)


func test_in_the_zone_he_stands_on_the_angle_line_at_the_top_of_the_crease() -> void:
	for puck: Vector2 in [Vector2(0.0, -8.0), Vector2(-4.0, -8.0), Vector2(3.0, -5.0), Vector2(-6.0, -9.0)]:
		_brain.decide(puck, Vector2.ZERO, _motor)
		var what: String = "%s" % puck
		assert_eq(_brain.zone, Z.FRONT, what)
		assert_eq(_motor.route.rest, R.FEET, "%s: on his feet" % what)
		var spot: Vector2 = _motor.route.spot
		assert_almost_eq(spot.normalized().dot(puck.normalized()), 1.0, 1e-5, "%s: on the angle line" % what)
		_faces(spot, puck, what)
		# On the crease's outline: its arc, or one of its sides.
		var on_arc: bool = absf(spot.length() - CreaseRules.ARC_RADIUS) < 1e-4
		var on_side: bool = absf(absf(spot.x) - CreaseRules.HALF_WIDTH) < 1e-4
		assert_true(on_arc or on_side, "%s: at the top of the crease (%s)" % [what, spot])
		assert_lte(spot.length(), CreaseRules.ARC_RADIUS + 1e-4, what)
		assert_lte(absf(spot.x), CreaseRules.HALF_WIDTH + 1e-4, what)


func test_out_of_the_zone_he_waits_in_the_middle_of_the_crease() -> void:
	var puck := Vector2(2.0, -25.0)
	_brain.decide(puck, Vector2.ZERO, _motor)
	assert_eq(_brain.zone, Z.AWAY)
	var spot: Vector2 = _motor.route.spot
	assert_almost_eq(spot.length(), KeeperPositioning.AWAY_DEPTH_SHARE * CreaseRules.ARC_RADIUS, 1e-3)
	_faces(spot, puck, "away")


func test_at_a_sharp_angle_he_stands_on_the_near_post_turned_to_the_puck() -> void:
	for puck: Vector2 in [Vector2(6.0, -2.0), Vector2(-5.0, -1.5)]:
		_brain.decide(puck, Vector2.ZERO, _motor)
		var what: String = "%s" % puck
		assert_eq(_brain.zone, Z.SHARP, what)
		var side: float = signf(puck.x)
		var spot: Vector2 = _motor.route.spot
		_faces(spot, puck, what)
		# His edge on the post's side, turned with him, on the post's face.
		var skel := KeeperSkeleton.new()
		var ready_pose := KeeperPose.new()
		KeeperPoses.ready(ready_pose)
		skel.pose(ready_pose)
		var edge: Vector3 = Basis(Vector3.UP, _motor.route.facing) * KeeperGear.post_contact(skel, side)
		var on := Vector2(spot.x + edge.x, spot.y + edge.z)
		var post := Vector2(side * GameRules.NET_HALF_WIDTH, 0.0)
		assert_almost_eq(on.distance_to(post), GameRules.NET_POST_RADIUS, 0.01, "%s: his edge on the post" % what)


func test_below_the_goal_line_he_seals_the_post_on_its_side() -> void:
	for puck: Vector2 in [Vector2(3.0, 1.0), Vector2(-2.0, 0.5)]:
		_brain = KeeperPositioning.new()
		_brain.decide(puck, Vector2.ZERO, _motor)
		assert_eq(_brain.zone, Z.BELOW)
		assert_eq(_motor.route.rest, R.POST)
		assert_eq(_motor.route.side, signf(puck.x), "%s: the post on its side" % puck)
		assert_eq(_motor.route.iron, Vector2(signf(puck.x) * GameRules.NET_HALF_WIDTH, 0.0))


# Behind the net he holds his post, and goes for the other once the puck's own
# motion carries it out past that post in the time he would take to seal it.
func test_behind_the_net_he_holds_his_post_until_the_puck_will_beat_him_across() -> void:
	_brain.decide(Vector2(3.0, 1.2), Vector2.ZERO, _motor)
	assert_eq(_brain.post_side, 1.0)
	var behind := Vector2(0.2, 1.4)
	var across: float = _motor.time_to_seal(Vector2(-GameRules.NET_HALF_WIDTH, 0.0), -1.0)
	var needed: float = (behind.x + GameRules.NET_HALF_WIDTH) / across
	_brain.decide(behind, Vector2(-0.9 * needed, 0.0), _motor)
	assert_eq(_brain.post_side, 1.0, "slower than he can get across: held")
	assert_eq(_motor.route.side, 1.0)
	_brain.decide(behind, Vector2(-1.1 * needed, 0.0), _motor)
	assert_eq(_brain.post_side, -1.0, "faster: he goes for the other post")
	assert_eq(_motor.route.side, -1.0)


# Into a zone, then back and forth across the line that took him in: he holds
# it.
func test_a_puck_on_a_boundary_does_not_flip_him() -> void:
	var blue: float = KeeperPositioning.BLUE_LINE_M + KeeperPositioning.MARGIN_M
	_check_held(Vector2(0.0, -10.0), [Vector2(0.0, -blue - 0.2), Vector2(0.0, -blue + 0.2)], "the blue line")
	var sharp: float = KeeperPositioning.SHARP_RAD
	var out: float = 3.0
	_check_held(Vector2(0.0, -out), [Vector2(out * tan(sharp + 0.03), -out), Vector2(out * tan(sharp - 0.03), -out)],
			"the sharp angle")
	_check_held(Vector2(3.0, -2.0), [Vector2(3.0, 0.2), Vector2(3.0, -0.2)], "the goal line")


func _check_held(from: Vector2, across: Array[Vector2], what: String) -> void:
	_brain = KeeperPositioning.new()
	_brain.decide(from, Vector2.ZERO, _motor)
	var first: int = _brain.zone
	_brain.decide(across[0], Vector2.ZERO, _motor)
	var entered: int = _brain.zone
	assert_ne(first, entered, "%s: crossing it changes the zone" % what)
	for i: int in 6:
		_brain.decide(across[i % 2], Vector2.ZERO, _motor)
		assert_eq(_brain.zone, entered, "%s: back and forth across it holds" % what)


# A puck carried round the zone: in from beyond the blue line to the slot, out
# wide, down the wall to a sharp angle, below the line, behind the net and out
# the other side, back to the slot.
func test_he_tracks_a_puck_round_the_zone_unbroken() -> void:
	var path: Array[Vector2] = [
		Vector2(-3.0, -22.0), Vector2(0.0, -9.0), Vector2(8.0, -6.0), Vector2(6.0, -1.5), Vector2(3.0, 1.5),
		Vector2(-0.3, 1.8), Vector2(-4.0, 1.2), Vector2(-5.0, -3.0), Vector2(-2.0, -8.0),
	]
	var speed: float = 4.0
	var pose := KeeperPose.new()
	var skel := KeeperSkeleton.new()
	var was: Array[Vector3] = []
	var zones: Dictionary = {}
	var puck: Vector2 = path[0]
	var leg: int = 0
	var t: float = 0.0
	while t < 20.0:
		var velocity := Vector2.ZERO
		if leg < path.size() - 1:
			velocity = (path[leg + 1] - puck).normalized() * speed
			puck = puck.move_toward(path[leg + 1], speed * DT)
			if puck == path[leg + 1]:
				leg += 1
		if roundi(t / DT) % PLANNER_EVERY == 0:
			_brain.decide(puck, velocity, _motor)
			zones[_brain.zone] = true
		_motor.step(DT)
		t += DT
		_motor.pose(pose)
		skel.pose(pose)
		var basis := Basis(Vector3.UP, _motor.yaw)
		var at: Array[Vector3] = []
		for b: int in KeeperSkeleton.BONE_COUNT:
			at.append(basis * skel.xf[b].origin + Vector3(_motor.x, 0.0, _motor.z))
		if not was.is_empty():
			for b: int in KeeperSkeleton.BONE_COUNT:
				assert_lt(at[b].distance_to(was[b]), MAX_BONE_STEP_M, "t %.3f bone %d" % [t, b])
		was = at
		for part: int in KeeperGear.PART_COUNT:
			var box: Transform3D = KeeperGear.box(skel, part)
			var h: Vector3 = KeeperGear.half_extents(part)
			var low: float = box.origin.y - absf(box.basis.x.y) * h.x - absf(box.basis.y.y) * h.y \
					- absf(box.basis.z.y) * h.z
			var soft: bool = KeeperGear.save_part(part) == GoalieSaveRules.SavePart.PAD
			assert_gte(low, -(PAD_GIVE_M if soft else HARD_GIVE_M), "t %.3f %s" % [t, KeeperGear.Part.keys()[part]])
		if leg == path.size() - 1 and _motor.is_idle():
			break
	assert_eq(zones.size(), 4, "every zone on the way")
	assert_true(_motor.is_idle(), "at rest where the puck stopped")
	assert_eq(_motor.refused, 0)
	assert_almost_eq(Vector2(_motor.x, _motor.z), _motor.route.spot, Vector2.ONE * KeeperRoute.THERE_M)


# A carrier in down the middle who cuts across the slot at a skating pace: he
# stays on the line from the puck to the net's centre as it swings, skated
# with it rather than stepped after it.
func test_a_carrier_cutting_across_the_slot_is_tracked_on_the_angle() -> void:
	var path: Array[Vector2] = [Vector2(0.5, -19.0), Vector2(0.0, -7.0), Vector2(-3.5, -3.0)]
	var speed: float = 8.0
	_motor.z = -1.3
	var puck: Vector2 = path[0]
	var leg: int = 0
	var worst: float = 0.0
	var tick: int = 0
	while leg < path.size() - 1:
		var to: Vector2 = path[leg + 1]
		var velocity: Vector2 = (to - puck).normalized() * speed
		puck = puck.move_toward(to, speed * DT)
		if puck == to:
			leg += 1
		if tick % PLANNER_EVERY == 0:
			_brain.decide(puck, velocity, _motor)
		_motor.step(DT)
		tick += 1
		var at := Vector2(_motor.x, _motor.z)
		var line: Vector2 = puck.normalized()
		if tick * DT > 0.5:
			worst = maxf(worst, absf(at.x * line.y - at.y * line.x))
	assert_lt(worst, 0.2, "on the angle line as it swings")


# His depth from his own skating: the top of the crease unless the play asks
# for less; against a puck coming at him, no further out than C-cuts from a
# standstill set him on the floor before it reaches the crease; against one
# swinging across him, no further out than his shuffle keeps on its angle.
func test_his_depth_answers_how_the_puck_moves() -> void:
	var skates := KeeperFootwork.new()
	var top: float = KeeperPositioning.crease_edge(Vector2(0.0, -1.0))
	var floor_m: float = KeeperPositioning.DEPTH_FLOOR_M
	var depth := func(puck: Vector2, v: Vector2) -> float:
		return KeeperPositioning.depth_for(puck, v, skates)
	assert_almost_eq(depth.call(Vector2(0.0, -6.0), Vector2.ZERO), top, 1e-6, "still: the top")
	assert_almost_eq(depth.call(Vector2(0.0, -8.0), Vector2(0.0, 2.0)), top, 1e-6, "a slow carrier: the top")
	assert_almost_eq(depth.call(Vector2(0.0, -6.0), Vector2(0.0, -8.0)), top, 1e-6, "going away: the top")
	var was: float = top
	for r: float in [12.0, 8.0, 6.0, 4.0, 3.0, 2.0, 1.0]:
		var d: float = depth.call(Vector2(0.0, -r), Vector2(0.0, 8.0))
		assert_lte(d, was + 1e-6, "a rush backs him in as it comes (%.0f m)" % r)
		assert_gte(d, floor_m - 1e-6, "never past the floor (%.0f m)" % r)
		var arrives: float = maxf(r - top, 0.0) / 8.0
		assert_lte(d - floor_m, GoaliePushRules.set_reach(skates.c_cut_speed, skates.accel, arrives) + 1e-6,
				"on the floor in time from there (%.0f m)" % r)
		was = d
	assert_lt(was, top - 0.5, "met deep")
	assert_lt(depth.call(Vector2(0.0, -4.0), Vector2(0.0, 12.0)), depth.call(Vector2(0.0, -4.0), Vector2(0.0, 6.0)),
			"a faster rush deeper")
	for lateral: float in [2.0, 5.0, 9.0]:
		var puck := Vector2(1.0, -4.0)
		var v: Vector2 = puck.normalized().orthogonal() * lateral
		var d: float = depth.call(puck, v)
		assert_lte(d * lateral / puck.length(), skates.shuffle_speed + 1e-6,
				"his spot swings no faster than he shuffles (%.0f m/s)" % lateral)
	assert_lt(depth.call(Vector2(1.0, -4.0), Vector2(-9.0, 0.0)), depth.call(Vector2(1.0, -4.0), Vector2(-3.0, 0.0)),
			"a faster swing deeper")


# A rush straight in on him: skated back as it comes, deep and set on the
# floor's side of the crease by the time it is on him, never deeper.
func test_a_rush_straight_in_backs_him_in() -> void:
	var speed: float = 8.0
	var top: float = KeeperPositioning.crease_edge(Vector2(0.0, -1.0))
	_motor.z = -top
	var puck := Vector2(0.0, -16.0)
	var tick: int = 0
	var deepest: float = INF
	while puck.y < -2.5:
		puck.y += speed * DT
		if tick % PLANNER_EVERY == 0:
			_brain.decide(puck, Vector2(0.0, speed), _motor)
		_motor.step(DT)
		tick += 1
		deepest = minf(deepest, -_motor.z)
	assert_lt(-_motor.z, top - 0.6, "backed in as it came")
	assert_gte(deepest, KeeperPositioning.DEPTH_FLOOR_M - 0.02, "no deeper than the floor")


# Against a pass across to an open receiver he stands no further out than the
# push he has time for, once read, sets him on the receiver's angle: deeper
# for a near feed across the slot, nothing for one on his own line or one long
# enough to cross the crease for.
func test_a_receiver_across_the_slot_holds_him_deeper() -> void:
	var skates := KeeperFootwork.new()
	var read_s: float = GoalieSkillProfile.hard().reaction_delay_s
	var top: float = KeeperPositioning.crease_edge(Vector2(0.0, -1.0))
	var puck := Vector2(2.0, -6.0)
	assert_eq(KeeperPositioning.pass_depth(puck, puck * 0.5, skates, read_s), INF, "on his line: nothing")
	var far: float = KeeperPositioning.pass_depth(puck, Vector2(-9.0, -14.0), skates, read_s)
	assert_gt(far, top, "a long pass: nothing")
	var near := Vector2(-4.0, -9.0)
	var cap: float = KeeperPositioning.pass_depth(puck, near, skates, read_s)
	assert_lt(cap, top, "a feed across the slot: deeper")
	var wider: float = KeeperPositioning.pass_depth(puck, Vector2(-2.5, -3.0), skates, read_s)
	assert_lt(wider, cap + 1e-6, "a wider angle no further out")
	# From that depth the receiver's angle is a push he has time for.
	var time: float = puck.distance_to(near) / KeeperPositioning.PASS_M_S - read_s
	var spot: Vector2 = puck.normalized() * cap
	var along: float = maxf(spot.dot(near.normalized()), KeeperPositioning.DEPTH_FLOOR_M)
	assert_almost_eq(spot.distance_to(near.normalized() * along),
			GoaliePushRules.set_reach(skates.t_push_speed, skates.accel, time), 1e-4, "set on it in time")

	_brain.decide(puck, Vector2.ZERO, _motor)
	var alone: float = _motor.route.spot.length()
	_brain.play = KeeperPlayRead.new()
	_brain.play.receivers.append(near)
	_brain.decide(puck, Vector2.ZERO, _motor)
	assert_almost_eq(alone, KeeperPositioning.crease_edge(puck.normalized()), 1e-4, "alone: the top")
	assert_almost_eq(_motor.route.spot.length(), maxf(cap, KeeperPositioning.DEPTH_FLOOR_M), 1e-4,
			"with him open: the pass's depth")


# A shooter coming at him who winds up is a shot to be set for: he holds the
# top of the crease rather than backing in for the approach.
func test_a_shot_wound_up_on_the_rush_is_met_set_at_depth() -> void:
	var puck := Vector2(0.0, -4.0)
	var coming := Vector2(0.0, 8.0)
	_brain.play = KeeperPlayRead.new()
	_brain.decide(puck, coming, _motor)
	var backing: float = _motor.route.spot.length()
	_brain.play.winding_up = true
	_brain.decide(puck, coming, _motor)
	var top: float = KeeperPositioning.crease_edge(Vector2(0.0, -1.0))
	assert_lt(backing, top - 0.1, "the rush alone backs him in")
	assert_almost_eq(_motor.route.spot.length(), top, 1e-4, "wound up, set at the top")


# A pass read to a stick: his goal is set on that stick's angle, turned to it,
# not on the puck crossing; out from behind the net, in front of it, not on a
# post.
func test_a_pass_he_reads_he_plays_from_where_it_is_met() -> void:
	_brain.play = KeeperPlayRead.new()
	var puck := Vector2(3.0, -6.0)
	var meet := Vector2(-2.6, -6.0)
	_brain.play.meets = true
	_brain.play.meet = meet
	_brain.play.meet_s = 2.0
	_brain.decide(puck, Vector2(-15.0, 0.0), _motor)
	var line: Vector2 = meet.normalized()
	assert_almost_eq(_motor.route.spot, line * KeeperPositioning.crease_edge(line), Vector2.ONE * 1e-4,
			"on its angle at the top of the crease")
	_faces(_motor.route.spot, meet, "the pass")
	assert_eq(_motor.route.rest, R.FEET)
	_brain.decide(Vector2(0.5, 1.5), Vector2(0.0, -10.0), _motor)
	assert_eq(_brain.zone, Z.FRONT, "a pass out from behind the net: in front")
	assert_eq(_motor.route.rest, R.FEET)
