extends GutTest

# ── A PUCK OVER THE FLAT PADS IS THE HANDS' TO TAKE ──────────────────────────
# Anything read under `elevated_threshold` (the top of the butterfly trunk,
# 1.0 m) drops him, and flat the pads are 0.28 m tall — so a corner shot at
# 0.3-0.6 m goes over the pad and wide of the trunk, and only a hand can stop
# it. Measured before the hands answered such a shot, a set Hard goalie with
# the whole wrister space fired at him (aim every 7 cm, FLAT/LOW/HIGH, 60/70/80
# mph, perfect execution) conceded, all of them LOW-row corner shots:
#
#     9 m centre    14/216      12 m centre      5/216
#    15 m centre    11/216      12 m, 5 m wide   8/216
#
# and every one of them crossed with his hands still at rest. The bots' shot
# model already assumed the hands take that band (AIActionScoring
# ._delay_at_height); the live keeper was the half that didn't.
#
# The second half is WHERE the hand goes. The read belief is a goal-line
# crossing, and from an angle he stands well out from that line squared to the
# shooter, so the goal-line x overstates how far wide of him the puck passes.
# Aimed there the blocker reaches past the puck and takes the stick with it —
# from 12 m and 5 m wide that cost 17/216 once the hands did answer, against
# 0/216 aimed at his own plane.

const Harness := preload("res://tests/unit/ai/real_goalie_shot_harness.gd")
const WrapHarness := preload("res://tests/unit/ai/human_wraparound_harness.gd")
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const MPH_TO_MS: float = 0.44704
const CORNER: float = GameRules.NET_HALF_WIDTH \
		- GameRules.NET_POST_RADIUS - GameRules.PUCK_COLLISION_RADIUS

var _goalie: Node = null
var _puck: Node = null
var _shooter: Skater = null
var _ctrl: GoalieController = null


func _live(harness: GDScript) -> RefCounted:
	_goalie = load("res://Scenes/Goalie.tscn").instantiate()
	_puck = load("res://Scenes/Puck.tscn").instantiate()
	_shooter = load("res://Scenes/Skater.tscn").instantiate() as Skater
	_ctrl = GoalieController.new()
	for n: Node in [_goalie, _puck, _shooter, _ctrl]:
		add_child_autofree(n)
	var h: RefCounted = harness.new()
	h.setup(_goalie, _puck, _ctrl, _shooter)
	return h


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
		var got: float = GoalieBodyConfigBuilder._believed_local_x_at_body(
				_hand_inputs(yaw, goalie, shooter, impact))
		assert_almost_eq(got, _oracle_local_x(yaw, goalie, shooter, impact), 0.001,
				"impact %+.2f: the hand target is the crossing of his own plane" % impact)
	# The far post is much nearer his body there than at the goal line.
	var far: float = GoalieBodyConfigBuilder._believed_local_x_at_body(
			_hand_inputs(yaw, goalie, shooter, -CORNER))
	assert_lt(absf(far), absf(-CORNER - goalie.x) - 0.3,
			"from an angle the goal-line x overstates the reach by a lot")


func test_unscreened_wristers_from_above_the_circles_meet_a_hand() -> void:
	var h: RefCounted = _live(Harness)
	var goals: int = 0
	var hand_saves: int = 0
	for spot: Vector3 in [Vector3(0.0, 0.0, GOAL_Z + 12.0),
			Vector3(5.0, 0.0, GOAL_Z + 12.0), Vector3(-7.0, 0.0, GOAL_Z + 12.0)]:
		for aim_x: float in [-CORNER, -0.6, 0.6, CORNER]:
			h.settle_ready(spot)
			var o: int = h.fire_at(spot, Vector3(aim_x, 0.0, GOAL_Z),
					ShotMechanics.ELEVATION_LOW, 70.0 * MPH_TO_MS, 0.0)
			if o == Harness.GOAL:
				goals += 1
				gut.p("GOAL from (%.1f, %.1f) at %+.2f, crossing y %.2f" % [
						spot.x, spot.z - GOAL_Z, aim_x, h.last_cross.y])
			elif o == Harness.SAVE and (h.last_part == GoalieSaveRules.SavePart.GLOVE
					or h.last_part == GoalieSaveRules.SavePart.BLOCKER):
				hand_saves += 1
	assert_eq(goals, 0, "a set Hard keeper takes a clean 12 m corner shot over his pads")
	assert_gt(hand_saves, 0, "and it is the hands that take some of them")


# The other side of the trade, so the fix cannot quietly become a wall: in
# tight the arm read still loses to the flight, and the over-the-pad corner
# keeps scoring.
func test_in_tight_the_arm_read_still_loses() -> void:
	var h: RefCounted = _live(Harness)
	var spot := Vector3(0.0, 0.0, GOAL_Z + GameRules.GOAL_LINE_Z - GameRules.ICING_FACEOFF_DOT_Z)
	var goals: int = 0
	for shot: Vector2 in [Vector2(-CORNER, 80.0), Vector2(-0.05, 70.0), Vector2(0.02, 80.0)]:
		h.settle_ready(spot)
		if h.fire_at(spot, Vector3(shot.x, 0.0, GOAL_Z), ShotMechanics.ELEVATION_LOW,
				shot.y * MPH_TO_MS, 0.0) == Harness.GOAL:
			goals += 1
	assert_gt(goals, 0, "an over-the-pad shot from the dot line still beats the arm read")


# ── A CUT ACROSS THE CREASE IS NOT A STALL ───────────────────────────────────
# The rush backflow used to switch off once the carrier's CLOSING speed fell
# under `rush_min_closing_speed`, and a walkaround turns closing speed into
# lateral speed. Depth then fell back to the standoff — 0.6 m off the puck — and
# he skated OUT at a man going round him: measured on a rush cut across from
# 2.5 m, his radius climbed 0.75 -> 1.37 m and he committed the seal from there.
func test_a_carrier_cutting_across_does_not_draw_him_out() -> void:
	var h: RefCounted = _live(WrapHarness)
	h.settle_ready(Vector3(0.0, 0.0, GOAL_Z + 10.0))
	h.begin_trial()
	h.bait_commit(0.0, 10.0, 2.5, 7.0)
	assert_true(_ctrl._sm.is_upright(), "precondition: the straight drive keeps him up")
	var start_r: float = _ctrl.challenge_radius()
	h.trace_enabled = true
	h.wrap_around(-1.6, 0.5, 1.5)
	var max_r: float = start_r
	for row: Array in h.trace:
		var st: int = row[1]
		if st == GoalieStateMachine.State.READY or st == GoalieStateMachine.State.STANDING:
			max_r = maxf(max_r, row[3])
	gut.p("cut from radius %.2f, furthest-out upright radius %.2f" % [start_r, max_r])
	assert_lt(max_r, start_r + 0.05, "he does not step out toward a carrier crossing him")
