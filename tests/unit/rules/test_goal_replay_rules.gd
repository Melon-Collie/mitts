extends GutTest

# GoalReplayRules — what a post-goal replay shows, anchored on the goal and the
# last skater touch before it.

const GOAL_TS: float = 100.0
const GOAL_LINE_Z: float = GameRules.GOAL_LINE_Z


func _ev(kind: String, ts: float, x: float = 0.0, team: int = 0) -> Dictionary:
	return {"event": {"kind": kind, "pos": [x, 0.0, 20.0], "speed": 10.0, "team": team},
			"host_ts": ts}


func _events(list: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in list:
		out.append(e)
	return out


# ── Scoring touch ─────────────────────────────────────────────────────────────

func test_scoring_touch_is_the_last_skater_contact_not_the_last_shot() -> void:
	# Shot from down ice, rimmed around, off a skate and in.
	var events := _events([
		_ev("shot", GOAL_TS - 5.0),
		_ev("puck_boards", GOAL_TS - 3.5),
		_ev("puck_body_block", GOAL_TS - 0.4),
		_ev("puck_goal_body", GOAL_TS - 0.1),
	])
	assert_eq(GoalReplayRules.scoring_touch_index(events, GOAL_TS, 0), 2)


func test_scoring_touch_is_the_scoring_teams_not_a_defenders_after_it() -> void:
	# A point shot redirected in off a defender's stick and then his skate.
	var events := _events([
		_ev("shot", GOAL_TS - 0.8, 0.0, 0),
		_ev("puck_deflection", GOAL_TS - 0.4, 0.0, 1),
		_ev("puck_body_block", GOAL_TS - 0.2, 0.0, 1),
	])
	assert_eq(GoalReplayRules.scoring_touch_index(events, GOAL_TS, 0), 0)


func test_an_own_goal_falls_back_to_the_last_touch_of_anyone() -> void:
	var events := _events([
		_ev("puck_pickup", GOAL_TS - 2.0, 0.0, 1),
		_ev("nudge", GOAL_TS - 0.5, 0.0, 1),
	])
	assert_eq(GoalReplayRules.scoring_touch_index(events, GOAL_TS, 0), 1)


func test_goalie_post_and_boards_are_nobodys_touch() -> void:
	var events := _events([
		_ev("shot", GOAL_TS - 0.9),
		_ev("puck_goalie", GOAL_TS - 0.5),
		_ev("puck_post", GOAL_TS - 0.2),
	])
	assert_eq(GoalReplayRules.scoring_touch_index(events, GOAL_TS, 0), 0)


func test_no_touch_on_camera_reads_minus_one() -> void:
	var events := _events([_ev("puck_boards", GOAL_TS - 2.0), _ev("puck_goalie", GOAL_TS - 1.0)])
	assert_eq(GoalReplayRules.scoring_touch_index(events, GOAL_TS, 0), -1)


func test_events_after_the_goal_are_ignored() -> void:
	var events := _events([_ev("shot", GOAL_TS - 1.0), _ev("nudge", GOAL_TS + 0.1)])
	assert_eq(GoalReplayRules.scoring_touch_index(events, GOAL_TS, 0), 0)


# ── Slow motion budget ────────────────────────────────────────────────────────

func test_slowmo_starts_just_before_a_recent_touch() -> void:
	var touch: float = GOAL_TS - 0.6
	assert_almost_eq(GoalReplayRules.slowmo_start_ts(touch, GOAL_TS),
			touch - GoalReplayRules.SLOWMO_LEAD, 0.0001)


func test_slowmo_never_exceeds_its_budget_however_old_the_touch() -> void:
	var start: float = GoalReplayRules.slowmo_start_ts(GOAL_TS - 6.0, GOAL_TS)
	assert_almost_eq(GOAL_TS - start, GoalReplayRules.SLOWMO_MAX_SPAN, 0.0001)


func test_point_blank_tap_still_gets_the_minimum_slowed_beat() -> void:
	var start: float = GoalReplayRules.slowmo_start_ts(GOAL_TS - 0.02, GOAL_TS)
	assert_almost_eq(GOAL_TS - start, GoalReplayRules.SLOWMO_MIN_SPAN, 0.0001)


func test_no_touch_slows_only_the_budget() -> void:
	var start: float = GoalReplayRules.slowmo_start_ts(-1.0, GOAL_TS)
	assert_almost_eq(GOAL_TS - start, GoalReplayRules.SLOWMO_MAX_SPAN, 0.0001)


func test_on_screen_slowmo_is_bounded() -> void:
	# Integrate the playback rate over the worst case to bound real seconds spent slowed.
	var start: float = GoalReplayRules.slowmo_start_ts(GOAL_TS - 6.0, GOAL_TS)
	var clock: float = start
	var real: float = 0.0
	var dt: float = 1.0 / 240.0
	var end: float = GOAL_TS + GoalReplayRules.POST_GOAL_TAIL
	while clock < end:
		clock += dt * GoalReplayRules.playback_speed(clock, start)
		real += dt
	assert_lt(real, (GoalReplayRules.SLOWMO_MAX_SPAN + GoalReplayRules.POST_GOAL_TAIL)
			/ GoalReplayRules.SLOWMO_SPEED + 0.01)


func test_playback_is_full_speed_before_and_slow_after_the_ramp() -> void:
	assert_almost_eq(GoalReplayRules.playback_speed(GOAL_TS - 2.0, GOAL_TS - 1.0), 1.0, 0.0001)
	assert_almost_eq(GoalReplayRules.playback_speed(GOAL_TS - 0.5, GOAL_TS - 1.0),
			GoalReplayRules.SLOWMO_SPEED, 0.0001)


# ── Clip start ────────────────────────────────────────────────────────────────
# Team 0 attacks +z (the goal at +GOAL_LINE_Z).

func _pickup(ts: float, z: float, team: int = 0) -> Dictionary:
	return {"event": {"kind": "puck_pickup", "pos": [0.0, 0.0, z], "speed": 5.0, "team": team},
			"host_ts": ts}


func _start(events: Array[Dictionary], touch_ts: float, touch_z: float = 20.0) -> float:
	return GoalReplayRules.clip_start_ts(events, touch_ts, touch_z, 1.0, 0)


func test_tic_tac_toe_extends_back_through_every_pass() -> void:
	var touch: float = GOAL_TS - 0.3
	var events := _events([
		_pickup(touch - 2.4, 18.0), _pickup(touch - 1.5, 20.0), _pickup(touch - 0.7, 21.0),
		_ev("shot", touch),
	])
	assert_almost_eq(_start(events, touch),
			touch - 2.4 - GoalReplayRules.PRE_PICKUP_BUFFER, 0.0001)


func test_outlet_into_an_odd_man_rush_is_one_play() -> void:
	# D collects in his own end, outlets, the forward carries the length of the
	# neutral zone and feeds across for the finish.
	var touch: float = GOAL_TS - 0.4
	var events := _events([
		_pickup(touch - 7.0, -22.0),
		_pickup(touch - 6.0, -12.0),
		_pickup(touch - 0.8, 19.0),
		_ev("shot", touch),
	])
	assert_almost_eq(_start(events, touch),
			touch - 7.0 - GoalReplayRules.PRE_PICKUP_BUFFER, 0.0001)


func test_a_slow_regroup_is_not_the_play() -> void:
	# Defencemen swapping the puck at their own blue line, then a long pass.
	var touch: float = GOAL_TS - 0.4
	var events := _events([
		_pickup(touch - 9.0, -18.0),
		_pickup(touch - 5.0, -16.0),
		_pickup(touch - 1.2, 18.0),
		_ev("shot", touch),
	])
	# The 3.8 s link from -16 to 18 is a rush and stays; the 4 s regroup before it does not.
	assert_almost_eq(_start(events, touch),
			touch - 5.0 - GoalReplayRules.PRE_PICKUP_BUFFER, 0.0001)


func test_a_turnover_starts_the_play() -> void:
	var touch: float = GOAL_TS - 0.4
	var events := _events([
		_pickup(touch - 3.0, 15.0, 1),
		_pickup(touch - 2.0, 16.0, 0),
		_pickup(touch - 1.0, 18.0, 0),
		_ev("shot", touch),
	])
	assert_almost_eq(_start(events, touch),
			touch - 2.0 - GoalReplayRules.PRE_PICKUP_BUFFER, 0.0001)


func test_the_play_is_the_scoring_teams_even_if_the_other_side_touched_last() -> void:
	# Team 0 passes, the shot is blocked and team 1 picks it up, team 0 strips it back.
	var touch: float = GOAL_TS - 0.3
	var events := _events([
		_pickup(touch - 4.0, 16.0, 0),
		_pickup(touch - 2.5, 18.0, 1),
		_ev("puck_strip", touch - 1.4, 0.0, 0),
		_pickup(touch - 1.2, 19.0, 0),
		_ev("shot", touch),
	])
	assert_almost_eq(_start(events, touch),
			touch - 1.2 - GoalReplayRules.PRE_PICKUP_BUFFER, 0.0001)


func test_coast_to_coast_shows_the_whole_carry() -> void:
	var touch: float = GOAL_TS - 0.3
	var events := _events([_pickup(touch - 5.5, -20.0), _ev("shot", touch)])
	assert_almost_eq(_start(events, touch, 21.0),
			touch - 5.5 - GoalReplayRules.PRE_PICKUP_BUFFER, 0.0001)


func test_a_slow_lone_carry_floors_at_the_long_carry_window() -> void:
	var touch: float = GOAL_TS - 0.5
	var events := _events([_pickup(touch - 5.0, 12.0), _ev("shot", touch)])
	assert_almost_eq(_start(events, touch, 18.0),
			touch - GoalReplayRules.MIN_PRE_TOUCH_LONG_CARRY, 0.0001)


func test_scramble_after_the_possession_cuts_to_the_last_contest() -> void:
	var touch: float = GOAL_TS - 0.3
	var events := _events([
		_pickup(touch - 4.0, 18.0),
		_pickup(touch - 3.0, 20.0),
		_ev("shot", touch - 2.6),
		_ev("stick_lift", touch - 1.5),
		_ev("nudge", touch),
	])
	assert_almost_eq(_start(events, touch),
			touch - 1.5 - GoalReplayRules.PRE_CONTEST_BUFFER, 0.0001)


func test_a_contest_inside_the_play_does_not_cut_it() -> void:
	var touch: float = GOAL_TS - 0.3
	var events := _events([
		_pickup(touch - 3.0, 16.0),
		_ev("body_check", touch - 2.0),
		_pickup(touch - 1.0, 19.0),
		_ev("shot", touch),
	])
	assert_almost_eq(_start(events, touch),
			touch - 3.0 - GoalReplayRules.PRE_PICKUP_BUFFER, 0.0001)


func test_clip_start_is_clamped_to_the_pre_touch_window() -> void:
	var touch: float = GOAL_TS
	var events: Array[Dictionary] = []
	for i: int in 12:  # a pass every second for twelve seconds
		events.append(_pickup(touch - 12.0 + float(i), 10.0))
	var start: float = _start(events, touch)
	assert_almost_eq(start, touch - GoalReplayRules.MAX_PRE_TOUCH, 0.0001)
	var point_blank := _events([_pickup(touch - 0.2, 20.0)])
	assert_almost_eq(_start(point_blank, touch), touch - GoalReplayRules.MIN_PRE_TOUCH, 0.0001)


# ── Net cam ───────────────────────────────────────────────────────────────────

func test_net_cam_sits_inside_the_boards_behind_either_goal() -> void:
	for goal_z: float in [GOAL_LINE_Z, -GOAL_LINE_Z]:
		for touch_x: float in [-12.0, -4.0, 0.0, 4.0, 12.0]:
			var cam: Vector3 = GoalReplayRules.net_cam_position(goal_z, touch_x)
			assert_gte(GameRules.distance_to_rink_inner(Vector2(cam.x, cam.z)),
					GoalReplayRules.NET_CAM_BOARD_MARGIN - 0.001,
					"cam %s for goal %.2f, touch x %.1f" % [cam, goal_z, touch_x])
			assert_gt(absf(cam.z), GOAL_LINE_Z + GameRules.NET_DEPTH, "behind the net")


func test_net_cam_mirrors_the_touch_across_the_net() -> void:
	assert_lt(GoalReplayRules.net_cam_position(GOAL_LINE_Z, 6.0).x, 0.0)
	assert_gt(GoalReplayRules.net_cam_position(-GOAL_LINE_Z, -6.0).x, 0.0)


func test_net_cam_sees_over_the_crossbar_to_the_slot() -> void:
	var cam: Vector3 = GoalReplayRules.net_cam_position(GOAL_LINE_Z, 0.0)
	var slot := Vector3(0.0, 0.0, GOAL_LINE_Z - 6.0)
	var t: float = (cam.z - GOAL_LINE_Z) / (cam.z - slot.z)
	assert_gt(lerpf(cam.y, slot.y, t), GameRules.NET_HEIGHT)


func test_net_cam_look_target_holds_at_the_goal_mouth() -> void:
	for goal_z: float in [GOAL_LINE_Z, -GOAL_LINE_Z]:
		var z_sign: float = signf(goal_z)
		var in_net := Vector3(0.3, 0.1, goal_z + z_sign * 0.5)
		var held: Vector3 = GoalReplayRules.net_cam_look_target(in_net, goal_z)
		assert_almost_eq(held.z, goal_z - z_sign * GoalReplayRules.NET_CAM_MIN_LOOK_DEPTH, 0.0001)
		assert_eq(held.x, in_net.x)
		var in_slot := Vector3(0.0, 0.0, goal_z - z_sign * 8.0)
		assert_eq(GoalReplayRules.net_cam_look_target(in_slot, goal_z), in_slot)
