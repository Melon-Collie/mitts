extends GutTest

# ── A PUCK OVER THE FLAT PADS IS THE HANDS' TO TAKE ──────────────────────────
# Anything read under `elevated_threshold` (the top of the butterfly trunk,
# 1.0 m) drops him, and flat the pads are 0.28 m tall — so a corner shot at
# 0.3-0.6 m goes over the pad and wide of the trunk, and only a hand can stop
# it; these hold the live keeper to taking it.
#
# The second half is WHERE the hand goes. The read belief is a goal-line
# crossing, and from an angle he stands well out from that line squared to the
# shooter, so the goal-line x overstates how far wide of him the puck passes:
# aimed there the blocker reaches past the puck and takes the stick with it. The
# hand aims at his own plane, and the wind-up pre-lean drifts it the same way.

const Snapshot := preload("res://tests/snapshot.gd")
const Harness := preload("res://tests/unit/ai/real_goalie_shot_harness.gd")
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const MPH_TO_MS: float = 0.44704
const IN_TIGHT_AIMS: int = 9
const CORNER: float = GameRules.NET_HALF_WIDTH \
		- GameRules.NET_POST_RADIUS - GameRules.PUCK_COLLISION_RADIUS

var _goalie: Node = null
var _puck: Node = null
var _shooter: Skater = null
var _ctrl: GoalieController = null
var _h: RefCounted = null


func before_each() -> void:
	_h = null


# One live rig per test, shared by every measurement in it.
func _live(harness: GDScript) -> RefCounted:
	if _h != null:
		return _h
	_goalie = load("res://Scenes/Goalie.tscn").instantiate()
	_puck = load("res://Scenes/Puck.tscn").instantiate()
	_shooter = load("res://Scenes/Skater.tscn").instantiate() as Skater
	_ctrl = GoalieController.new()
	for n: Node in [_goalie, _puck, _shooter, _ctrl]:
		add_child_autofree(n)
	_h = harness.new()
	_h.setup(_goalie, _puck, _ctrl, _shooter)
	return _h


func _hand_inputs(yaw: float, goalie_xz: Vector2, puck_xz: Vector2,
		impact_x: float) -> GoalieBodyConfigBuilder.Inputs:
	var inputs := GoalieBodyConfigBuilder.Inputs.new()
	inputs.goalie_yaw = yaw
	inputs.current_x = goalie_xz.x
	inputs.goalie_z = goalie_xz.y
	inputs.puck_position = Vector3(puck_xz.x, 0.0, puck_xz.y)
	inputs.shot_impact_x = impact_x
	inputs.goal_line_z = GOAL_Z
	return inputs


# Where the believed line actually crosses his frontal plane, by an
# independent line intersection, in his local frame.
func _oracle_local_x(yaw: float, goalie_xz: Vector2, puck_xz: Vector2,
		impact_x: float) -> float:
	var right := Vector2(cos(yaw), -sin(yaw))
	var hit: Variant = Geometry2D.line_intersects_line(puck_xz,
			Vector2(impact_x, GOAL_Z) - puck_xz, goalie_xz, right)
	return ((hit as Vector2) - goalie_xz).dot(right)


func test_the_hand_aims_where_the_believed_line_crosses_his_plane() -> void:
	# Square to a shooter 12 m out, 5 m wide, standing out on that line.
	var shooter := Vector2(5.0, GOAL_Z + 12.0)
	var to_shooter: Vector2 = (shooter - Vector2(0.0, GOAL_Z)).normalized()
	var goalie: Vector2 = Vector2(0.0, GOAL_Z) + to_shooter * 1.72
	var yaw: float = atan2(-to_shooter.x, -to_shooter.y)
	for impact: float in [-CORNER, 0.0, CORNER]:
		var got: float = GoalieBodyConfigBuilder._local_x_at_body(
				_hand_inputs(yaw, goalie, shooter, impact), impact)
		assert_almost_eq(got, _oracle_local_x(yaw, goalie, shooter, impact), 0.001,
				"impact %+.2f: the hand target is the crossing of his own plane" % impact)
	# The far post is much nearer his body there than at the goal line.
	var far: float = GoalieBodyConfigBuilder._local_x_at_body(
			_hand_inputs(yaw, goalie, shooter, -CORNER), -CORNER)
	assert_lt(absf(far), absf(-CORNER - goalie.x) - 0.3,
			"from an angle the goal-line x overstates the reach by a lot")


func test_the_windup_prelean_drifts_toward_the_same_plane() -> void:
	var shooter := Vector2(5.0, GOAL_Z + 12.0)
	var to_shooter: Vector2 = (shooter - Vector2(0.0, GOAL_Z)).normalized()
	var goalie: Vector2 = Vector2(0.0, GOAL_Z) + to_shooter * 1.72
	var yaw: float = atan2(-to_shooter.x, -to_shooter.y)
	var builder := GoalieBodyConfigBuilder.new()
	for impact: float in [-CORNER, CORNER]:
		var inputs := _hand_inputs(yaw, goalie, shooter, 0.0)
		inputs.state = GoalieStateMachine.State.READY
		inputs.prelean_active = true
		inputs.prelean_directional = true
		inputs.prelean_strength = 1.0
		inputs.prelean_impact_x = impact
		inputs.prelean_impact_y = 0.9
		var cfg: GoalieBodyConfig = builder.build(inputs)
		var want: float = _oracle_local_x(yaw, goalie, shooter, impact)
		var hand_x: float = cfg.glove_pos.x if want <= 0.0 else cfg.blocker_pos.x
		assert_almost_eq(hand_x, want, 0.001,
				"pre-lean toward %+.2f lands the hand on his own plane's crossing" % impact)


const ABOVE_THE_CIRCLES: Array[Vector3] = [Vector3(0.0, 0.0, GOAL_Z + 12.0),
		Vector3(5.0, 0.0, GOAL_Z + 12.0), Vector3(-7.0, 0.0, GOAL_Z + 12.0)]


# [goals, hand saves] over unscreened LOW wristers at 70 mph from 12 m, four aims
# from each spot.
func _over_the_pad_from_range() -> Array[int]:
	var h: RefCounted = _live(Harness)
	var goals: int = 0
	var hand_saves: int = 0
	for spot: Vector3 in ABOVE_THE_CIRCLES:
		for aim_x: float in [-CORNER, -0.6, 0.6, CORNER]:
			h.settle_ready(spot)
			var o: int = h.fire_at(spot, Vector3(aim_x, 0.0, GOAL_Z),
					ShotMechanics.ELEVATION_LOW, 70.0 * MPH_TO_MS, 0.0)
			if o == Harness.GOAL:
				goals += 1
			elif o == Harness.SAVE and (h.last_part == GoalieSaveRules.SavePart.GLOVE
					or h.last_part == GoalieSaveRules.SavePart.BLOCKER):
				hand_saves += 1
	return [goals, hand_saves]


func test_unscreened_wristers_from_above_the_circles_meet_a_hand() -> void:
	assert_gt(_over_the_pad_from_range()[1], 0,
			"a set keeper's hands take some of the 12 m corner shots over his pads")


# The other side of the trade, so the fix cannot quietly become a wall: in
# tight the arm read still loses to the flight, and somewhere across the mouth
# a MID shot from the dot line beats him over the pads. LOW from there crosses
# him at the flat pad top, which the drop seals.
func _over_the_pad_in_tight(mph: float) -> int:
	var h: RefCounted = _live(Harness)
	var spot := Vector3(0.0, 0.0, GOAL_Z + GameRules.GOAL_LINE_Z - GameRules.ICING_FACEOFF_DOT_Z)
	var goals: int = 0
	for i: int in IN_TIGHT_AIMS:
		h.settle_ready(spot)
		var aim := Vector3(lerpf(-CORNER, CORNER, i / float(IN_TIGHT_AIMS - 1)), 0.0, GOAL_Z)
		if h.fire_at(spot, aim, ShotMechanics.ELEVATION_MID, mph * MPH_TO_MS, 0.0) == Harness.GOAL:
			goals += 1
	return goals


func test_in_tight_the_arm_read_still_loses() -> void:
	assert_gt(_over_the_pad_in_tight(70.0) + _over_the_pad_in_tight(80.0), 0,
			"an over-the-pad shot from the dot line still beats the arm read")


# Rewrite with MITTS_UPDATE_SNAPSHOTS=1 (tests/snapshot.gd) and review the diff.
func test_hands_over_the_pad_calibration_snapshot() -> void:
	var snap := Snapshot.new("res://tests/unit/ai/snapshots/goalie_hands_over_the_pad.txt")
	var from_range: Array[int] = _over_the_pad_from_range()
	snap.record("12 m LOW wristers, 12 shots: goals", from_range[0])
	snap.record("12 m LOW wristers, 12 shots: hand saves", from_range[1])
	for mph: float in [70.0, 80.0]:
		snap.record("dot line MID at %.0f mph, %d aims: goals" % [mph, IN_TIGHT_AIMS],
				_over_the_pad_in_tight(mph))
	snap.verify(self)
