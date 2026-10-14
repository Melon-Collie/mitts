extends GutTest

# What any honest shot-danger model must do, whatever its calibration: the
# shapes of AIActionScoring.score_shoot / open_net_danger / tip_ev over angle,
# distance, goalie placement, lateness and traffic. The values the current
# calibration gives at the doctrine's reference looks are a reviewed snapshot,
# test_shot_danger_calibration_snapshot.
#
# GOAL at +Z; a lower z is further out.

const Snapshot := preload("res://tests/snapshot.gd")
const SNAPSHOT_PATH := "res://tests/unit/rules/snapshots/shot_danger.txt"
const NET_HW: float = GameRules.NET_HALF_WIDTH
const GOAL := Vector3(0.0, 0.0, 26.65)
const PACE: float = AIBotMechanics.WRISTER_SHOT_SPEED_M_S
# Float noise in a quantity that should be flat; a real rise is far larger.
const SLACK: float = 1e-4
const NO_ONE: Array[Vector3] = []


func _shoot(shooter: Vector3, goalie: Vector3, unsettled: float = 0.0) -> float:
	return AIActionScoring.score_shoot(shooter, GOAL, goalie, NET_HW, NO_ONE, PACE, unsettled)


# Shooter `dist` m from the goal centre, `bearing_deg` off the goal normal.
func _at(dist: float, bearing_deg: float) -> Vector3:
	var b: float = deg_to_rad(bearing_deg)
	return GOAL + Vector3(sin(b), 0.0, -cos(b)) * dist


# A keeper `depth` m out, squared to `shooter` the way the planning model squares.
func _squared(shooter: Vector3, depth: float) -> Vector3:
	return AIGoalieModel.goalie_squared_pos(GOAL - Vector3(0.0, 0.0, depth), GOAL, shooter)


func _assert_nonincreasing(values: Array[float], what: String) -> void:
	for i: int in range(1, values.size()):
		assert_lte(values[i], values[i - 1] + SLACK,
				"%s rises at step %d: %.4f -> %.4f" % [what, i, values[i - 1], values[i]])


func _assert_nondecreasing(values: Array[float], what: String) -> void:
	for i: int in range(1, values.size()):
		assert_gte(values[i], values[i - 1] - SLACK,
				"%s falls at step %d: %.4f -> %.4f" % [what, i, values[i - 1], values[i]])


# A keeper on the bisector of the posts as `shooter` sees them, `depth` m off
# the goal line — the angle a goalie plays, which halves the net either side.
func _on_the_angle(shooter: Vector3, depth: float) -> Vector3:
	var left: Vector3 = (GOAL + Vector3(-NET_HW, 0.0, 0.0) - shooter).normalized()
	var right: Vector3 = (GOAL + Vector3(NET_HW, 0.0, 0.0) - shooter).normalized()
	var ray: Vector3 = (left + right).normalized()
	return shooter + ray * ((GOAL.z - depth - shooter.z) / ray.z)


func test_a_wider_angle_never_scores_higher() -> void:
	for dist: float in [4.0, 7.0, 10.0, 14.0]:
		var row: Array[float] = []
		for bearing: float in range(0, 85, 5):
			var shooter: Vector3 = _at(dist, bearing)
			# Never level with or behind a shooter low on the goal line.
			var depth: float = minf(1.2, 0.5 * (GOAL.z - shooter.z))
			row.append(_shoot(shooter, _on_the_angle(shooter, depth)))
		_assert_nonincreasing(row, "danger over bearing at %.0f m" % dist)


func test_past_the_slot_range_never_scores_higher_against_a_squared_keeper() -> void:
	# A squared, challenged keeper used to leave a sliver past his reach that
	# GREW with distance, so a point shot out-scored working closer.
	for depth: float in [1.0, 1.5, 2.0]:
		var row: Array[float] = []
		for dist: float in range(8, 33):
			row.append(_shoot(_at(dist, 0.0), _at(depth, 0.0)))
		_assert_nonincreasing(row, "danger over range, keeper %.1f m out" % depth)


func test_moving_the_keeper_off_the_line_never_lowers_danger() -> void:
	for shooter: Vector3 in [_at(5.0, 0.0), _at(8.0, 20.0), _at(12.0, -30.0)]:
		var square: Vector3 = _squared(shooter, 1.0)
		var across: Vector3 = (shooter - GOAL).cross(Vector3.UP).normalized()
		var row: Array[float] = []
		for off: float in [0.0, 0.15, 0.3, 0.45, 0.6, 0.75, 0.9]:
			row.append(_shoot(shooter, square + across * off))
		_assert_nondecreasing(row, "danger as the keeper slides off %s" % shooter)


func test_a_keeper_outside_the_shooting_cone_concedes_the_empty_net() -> void:
	# Stranded on the near post, behind the far-post shooter's line to the net.
	var shooter := Vector3(-0.8, 0.0, 25.5)
	var stranded := Vector3(0.85, 0.0, 25.45)
	var absent := Vector3(30.0, 0.0, 0.0)
	assert_almost_eq(_shoot(shooter, stranded), _shoot(shooter, absent), 0.01,
			"the backdoor look is the empty net")


func test_a_late_read_buys_less_the_longer_the_flight() -> void:
	var credit: Array[float] = []
	for dist: float in [6.0, 8.5, 12.0, 16.0]:
		var shooter: Vector3 = _at(dist, 0.0)
		var keeper: Vector3 = _at(1.15, 0.0)
		credit.append(_shoot(shooter, keeper, 1.0) - _shoot(shooter, keeper))
	for c: float in credit:
		assert_gte(c, -SLACK, "an unsettled keeper is never harder to beat")
	_assert_nonincreasing(credit.slice(1), "the unsettled credit over range")


func _screened_point_shot(screen_z: float) -> float:
	var screeners: Array[Vector3] = []
	if not is_nan(screen_z):
		screeners.append(Vector3(0.0, 0.0, screen_z))
	return AIActionScoring.score_shoot(
			Vector3(0.0, 0.0, 10.0), GOAL, Vector3(0.0, 0.0, 25.5), NET_HW, NO_ONE,
			PACE, 0.0, [], -1.0, false, 0.0, false, 0.0, screeners)


func test_a_screen_helps_more_the_closer_it_stands_to_the_keeper() -> void:
	var row: Array[float] = [_screened_point_shot(NAN)]
	for z: float in [12.5, 15.0, 18.0, 21.0, 23.0, 24.0, 24.6]:
		row.append(_screened_point_shot(z))
	_assert_nondecreasing(row, "danger as the screen moves toward the keeper")
	assert_gt(row[-1], row[0], "a screen in the keeper's eyes is worth something")


func test_a_stationed_tip_beats_the_blast_it_redirects() -> void:
	var release := Vector3(0.0, 0.0, 10.0)
	var keeper := Vector3(0.0, 0.0, 25.5)
	var tip: float = AIActionScoring.tip_ev(
			release, Vector3(0.0, 0.0, 24.0), GOAL, keeper, NET_HW, NO_ONE, 33.0)
	assert_gt(tip, _shoot(release, keeper), "the redirect beats the read-all-the-way blast")
	var boxed: Array[Vector3] = [Vector3(0.5, 0.0, 23.5)]
	assert_lt(AIActionScoring.tip_ev(
			release, Vector3(0.0, 0.0, 24.0), GOAL, keeper, NET_HW, boxed, 33.0), tip,
			"a boxed-out tipper's redirect is worth less")


func test_a_lateral_drive_beats_the_squared_read() -> void:
	# The keeper's push is accel-limited: off a 7 m/s drive he arrives short of
	# the arc match the instant-square read assumes, so the shot is worth more.
	var goal := Vector3(0, 0, -26.65)
	var lookahead: float = 0.25
	var release := Vector3(0, 0, -24.05) + Vector3(7, 0, 0) * lookahead
	var goalie_now := Vector3(0, 0, -24.9)
	var set_goalie: Vector3 = AIGoalieModel.goalie_squared_pos(goalie_now, goal, release)
	var flight: float = release.distance_to(goal) / 33.0
	var pushed: Vector3 = AIGoalieModel.predict_goalie_pos(
			goalie_now, goal, lookahead + flight, release)
	assert_lt(pushed.x, set_goalie.x, "the push arrives short of the arc match")
	assert_gt(AIActionScoring.score_shoot(release, goal, pushed, NET_HW, NO_ONE, 33.0),
			AIActionScoring.score_shoot(release, goal, set_goalie, NET_HW, NO_ONE, 33.0),
			"so beating the push is worth more than the squared read leaves")


func test_a_post_seal_leaves_the_far_side_as_it_was() -> void:
	# A keeper parked on the +x post: sealing that post removes near-side holes
	# only, so a look whose best hole is the far side reads the same.
	var goal := Vector3(0, 0, -26.65)
	var shooter := Vector3(-2.0, 0, -22.65)
	var goalie := Vector3(0.85, 0, -26.55)
	var sealed: float = AIActionScoring.open_net_danger(
			shooter, goal, goalie, NET_HW, 33.0, 0.0, -1.0, true, 1.0, true)
	var unsealed: float = AIActionScoring.open_net_danger(
			shooter, goal, goalie, NET_HW, 33.0, 0.0, -1.0, true)
	assert_gt(sealed, 0.0, "the abandoned far side is a look")
	assert_almost_eq(sealed, unsealed, 0.01, "the seal takes nothing from the far side")


const HANDS_READY := Vector4(-0.42, 0.90, 0.44, 0.86)
const HANDS_BUTTERFLY := Vector4(-0.42, 0.44, 0.44, 0.44)


func test_lower_hands_never_shrink_the_high_window() -> void:
	var goalie := Vector3(0.0, 0.0, GOAL.z - 1.2)
	var widened_somewhere: bool = false
	for dist: float in range(4, 18):
		var shooter := Vector3(0.0, 0.0, GOAL.z - dist)
		var ready: float = AIActionScoring._hole_open_angle(
				0, shooter, GOAL, goalie, NET_HW, PACE, 0.0,
				-1.0, false, 0.0, false, 0.0, 0.0, HANDS_READY)
		var low: float = AIActionScoring._hole_open_angle(
				0, shooter, GOAL, goalie, NET_HW, PACE, 0.0,
				-1.0, false, 0.0, false, 0.0, 0.0, HANDS_BUTTERFLY)
		assert_gte(low, ready - SLACK, "low hands shrink the high window at %d m" % dist)
		widened_somewhere = widened_somewhere or low > ready + 0.005
	assert_true(widened_somewhere, "caught hands open the high window at some range")


func test_lane_clear_accurate_never_reads_a_crossing_defender_clearer() -> void:
	# The guided floor: a defender on the lane at any crossing speed reads no
	# clearer than standing still, where the ballistic coast lets a fast one
	# sail through.
	var from := Vector3(0.0, 0.0, 0.0)
	var to := Vector3(0.0, 0.0, 12.0)
	var d: Array[Vector3] = [Vector3(2.0, 0.0, 6.0)]
	var still: float = AIPuckLane.lane_clear(from, to, d, 18.0, [Vector3.ZERO], [], true)
	for vx: float in [-4.0, -10.0, -16.0, -22.0]:
		var v: Array[Vector3] = [Vector3(vx, 0.0, 0.0)]
		var accurate: float = AIPuckLane.lane_clear(from, to, d, 18.0, v, [], true)
		assert_lte(accurate, still + SLACK, "crossing at %.0f reads clearer than standing" % vx)
	var fast: Array[Vector3] = [Vector3(-16.0, 0.0, 0.0)]
	assert_lt(AIPuckLane.lane_clear(from, to, d, 18.0, fast, [], true),
			AIPuckLane.lane_clear(from, to, d, 18.0, fast),
			"the floor is what stops a fast crosser coasting through")


func test_an_open_receiver_out_scores_the_covered_shooter() -> void:
	# Bots never passing side to side: the cross-slot feed is worth more than
	# the shot the keeper is squared to.
	var shooter := Vector3(3.0, 0.0, 21.0)
	var goalie: Vector3 = _squared(shooter, 1.0)
	assert_gt(AIActionScoring.score_pass(shooter, Vector3(-3.0, 0.0, 21.0), GOAL, goalie,
			NET_HW, NO_ONE), _shoot(shooter, goalie))


func test_the_standing_five_hole_rule_is_the_pose_gap() -> void:
	var builder := GoalieBodyConfigBuilder.new()
	var inputs := GoalieBodyConfigBuilder.Inputs.new()
	inputs.state = GoalieStateMachine.State.STANDING
	for openness: float in [0.0, 0.02, 0.1]:
		inputs.five_hole_openness = openness
		var c: GoalieBodyConfig = builder.build(inputs)
		var gap: float = c.right_pad_pos.x - c.left_pad_pos.x - GoalieAnatomy.PAD_BOX_WIDTH_M
		assert_almost_eq(GoalieBehaviorRules.five_hole_gap_m(false, openness), gap, 0.001,
				"standing five-hole at openness %.2f is the built pads' gap" % openness)


# ── The reviewed calibration ─────────────────────────────────────────────────
# One row per doctrine reference look. Rewrite with MITTS_UPDATE_SNAPSHOTS=1
# (tests/snapshot.gd) and review the diff.

const LOFT_NAMES: Array[String] = ["FLAT", "LOW", "MID", "HIGH"]


func _loft(shooter: Vector3, goalie: Vector3, unsettled: float = 0.0,
		five_hole: float = -1.0, down: bool = false, screen_m: float = 0.0) -> String:
	return LOFT_NAMES[AIActionScoring.best_shot_loft(shooter, GOAL, goalie, NET_HW, PACE,
			unsettled, five_hole, down, 0.0, false, 0.0, screen_m)]


func test_shot_danger_calibration_snapshot() -> void:
	var snap := Snapshot.new(SNAPSHOT_PATH)
	var g := Vector3(0, 0, -26.65)
	snap.record("slot 5.6 m, keeper 0.7 m off the line", _shoot(Vector3(0, 0, 21), Vector3(0.7, 0, 26)))
	snap.record("centre 32 m, keeper 0.65 m out", _shoot(Vector3(0, 0, -5), Vector3(0, 0, 26)))
	snap.record("80 deg wall shot", _shoot(Vector3(12, 0, 24.65), Vector3(0, 0, 26)))
	snap.record("59 deg in tight, squared keeper",
			_shoot(Vector3(5, 0, 23.65), Vector3(0.86, 0, 26.34)))
	snap.record("straight on 5.65 m, squared deep keeper",
			_shoot(Vector3(0, 0, 21), Vector3(0, 0, 26.05)))
	snap.record("backdoor tap-in", _shoot(Vector3(-0.8, 0, 25.5), Vector3(0.85, 0, 25.45)))
	snap.record("cross-seam past a frozen keeper", _shoot(Vector3(3, 0, 22), Vector3(0, 0, 25.15)))
	snap.record("slot quick release, set standing keeper",
			_shoot(Vector3(0, 0, 21.65), Vector3(0, 0, 25.05)))
	snap.record("slot 3.5 m over a down keeper, loft",
			_loft(Vector3(0, 0, 23.15), Vector3(0, 0, 25.05), 0.0, 0.0, true))
	snap.record("slot 3.5 m over a down keeper, aim x", AIActionScoring.best_shot_aim(
			Vector3(0, 0, 23.15), GOAL, Vector3(0, 0, 25.05), NET_HW, PACE, 0.0, 0.0, true).x)
	snap.record("point blank into a dropped keeper", AIActionScoring.score_shoot(
			Vector3(0, 0, 24.65), GOAL, Vector3(0, 0, 25.15), NET_HW, NO_ONE, PACE,
			0.0, [], 0.0, true))
	snap.record("ranged 13 m into a set keeper", _shoot(Vector3(0, 0, 13.65), Vector3(0, 0, 25.15)))
	for depth: float in [1.0, 1.5, 2.0]:
		for dist: float in [10.0, 12.0, 14.0, 16.0]:
			snap.record("squared keeper %.1f m out, shot from %.0f m" % [depth, dist],
					_shoot(Vector3(0, 0, GOAL.z - dist), Vector3(0, 0, GOAL.z - depth)))
	var wall := Vector3(7, 0, 24)
	snap.record("70 deg sharp angle into the predicted seal", AIActionScoring.score_shoot(
			wall, GOAL, Vector3(0.9, 0, 25.05), NET_HW, NO_ONE, PACE, 0.0, [], -1.0, false,
			AIGoalieModel.derive_post_seal_x_sign(wall, GOAL), true))
	snap.record("caught-moving keeper in tight, loft",
			_loft(Vector3(0, 0, 24.65), Vector3(0, 0, 25.65), 1.0))
	snap.record("16 m at a caught-moving keeper",
			_shoot(Vector3(0, 0, 10.65), Vector3(0, 0, 25.65), 1.0))
	snap.record("8.5 m, set keeper", _shoot(Vector3(0, 0, 18.15), Vector3(0, 0, 25.5)))
	snap.record("8.5 m, unsettled keeper", _shoot(Vector3(0, 0, 18.15), Vector3(0, 0, 25.5), 1.0))
	snap.record("point blast, clean", _screened_point_shot(NAN))
	snap.record("point blast, screen 2.5 m off the blade", _screened_point_shot(12.5))
	snap.record("point blast, net-front screen", _screened_point_shot(24.0))
	snap.record("point blast, net-front screen, loft",
			_loft(Vector3(0, 0, 10), Vector3(0, 0, 25.5), 0.0, -1.0, false, 14.0))
	var none: Array[Vector3] = []
	snap.record("tip through a stationed net-front blade", AIActionScoring.tip_ev(
			Vector3(0, 0, 10), Vector3(0, 0, 24), GOAL, Vector3(0, 0, 25.5), NET_HW, none, 33.0))
	var boxed: Array[Vector3] = [Vector3(0.5, 0, 23.5)]
	snap.record("tip, boxed out", AIActionScoring.tip_ev(
			Vector3(0, 0, 10), Vector3(0, 0, 24), GOAL, Vector3(0, 0, 25.5), NET_HW, boxed, 33.0))
	snap.record("cross-slot feed past a keeper squared to the shooter", AIActionScoring.score_pass(
			Vector3(3, 0, 21), Vector3(-3, 0, 21), GOAL, _squared(Vector3(3, 0, 21), 1.0),
			NET_HW, none))
	snap.record("far side past a post-sealed keeper", AIActionScoring.open_net_danger(
			Vector3(-2, 0, -22.65), g, Vector3(0.85, 0, -26.55), NET_HW, 33.0,
			0.0, -1.0, true, 1.0, true))
	var drive := Vector3(0, 0, -24.05) + Vector3(7, 0, 0) * 0.25
	var now := Vector3(0, 0, -24.9)
	snap.record("doorstep drive, squared read", AIActionScoring.score_shoot(drive, g,
			AIGoalieModel.goalie_squared_pos(now, g, drive), NET_HW, none, 33.0))
	snap.record("doorstep drive, real push", AIActionScoring.score_shoot(drive, g,
			AIGoalieModel.predict_goalie_pos(now, g, 0.25 + drive.distance_to(g) / 33.0, drive),
			NET_HW, none, 33.0))
	var five_gap: float = GoalieBehaviorRules.five_hole_gap_m(false, 0.02)
	var tight := Vector3(0, 0, -23.65)
	var keeper := Vector3(0, 0, -24.9)
	snap.record("standing five-hole 3 m, stance-free read",
			AIActionScoring.score_shoot(tight, g, keeper, NET_HW, none, 33.0))
	snap.record("standing five-hole 3 m, measured slot", AIActionScoring.score_shoot(
			tight, g, keeper, NET_HW, none, 33.0, 0.0, [], five_gap, false))
	snap.record("standing five-hole 3 m, measured slot, noisy hand", AIActionScoring.score_shoot(
			tight, g, keeper, NET_HW, none, 33.0, 0.0, [], five_gap, false, 0.0, false, 0.08))
	snap.verify(self)
