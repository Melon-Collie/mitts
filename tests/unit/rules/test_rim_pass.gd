extends GutTest

# AIRimPass — the rim's path half: which launches are rims, where each goes,
# and who reaches it first. Team 0 defends +Z.

const OUR_GOAL_Z: float = 26.65
const PACE: float = GameRules.DEFAULT_WRISTER_POWER_MAX_M_S
var NONE: Array[Vector3] = []
var NO_CAPS: Array[AISkaterCaps] = []

var _saved_margin: float


func before_each() -> void:
	_saved_margin = AIActionScoring.goalie_puck_play_go_margin_s


func after_each() -> void:
	AIActionScoring.goalie_puck_play_go_margin_s = _saved_margin


func _build(from: Vector3, opps: Array[Vector3] = [],
		keeper: Vector3 = Vector3.INF, ours: Array[Vector3] = []) -> int:
	var vels: Array[Vector3] = []
	for _o: Vector3 in opps:
		vels.append(Vector3.ZERO)
	return AIRimPass.build(from, PACE, OUR_GOAL_Z, opps, vels, NO_CAPS, keeper, ours)


func test_the_keeper_mirror_matches_the_live_goalie() -> void:
	var gc: GoalieController = autofree(GoalieController.new())
	assert_eq(AIRimPass.KEEPER_RIM_MIN_SPEED_M_S, gc.puck_play_min_puck_speed)
	assert_eq(AIRimPass.KEEPER_RIM_MAX_SPEED_M_S, gc.puck_play_max_puck_speed)
	assert_eq(AIRimPass.KEEPER_SET_BEAT_S, gc.puck_play_set_beat)
	assert_eq(AIRimPass.KEEPER_STOP_BEAT_S, gc.puck_play_stop_beat)
	assert_eq(AIRimPass.KEEPER_PRESSURE_SPEED_M_S, gc.puck_play_opponent_speed)
	assert_eq(AIActionScoring.GOALIE_PUCK_PLAY_SPEED_M_S, gc.puck_play_skate_speed)
	assert_eq(AIActionScoring.GOALIE_PUCK_PLAY_ACCEL_M_S2, gc.puck_play_skate_accel)
	assert_eq(AIActionScoring.GOALIE_PUCK_PLAY_REACH_M, gc.puck_play_capture_radius)


func test_the_go_margin_follows_the_goalie_tier() -> void:
	AIActionScoring.set_goalie_profile(GoalieSkillProfile.normal())
	var normal: float = AIActionScoring.goalie_puck_play_go_margin_s
	AIActionScoring.set_goalie_profile(GoalieSkillProfile.hard())
	assert_eq(AIActionScoring.goalie_puck_play_go_margin_s,
			GoalieSkillProfile.hard().puck_play_go_margin_s)
	assert_eq(normal, GoalieSkillProfile.normal().puck_play_go_margin_s)


func test_no_rims_from_centre_ice() -> void:
	assert_eq(_build(Vector3(0.0, 0.0, 0.0)), 0, "nowhere near the boards")


func test_a_corner_rim_runs_up_the_wall() -> void:
	# From behind our own net, out toward the strong corner: some launch must
	# come round the corner and run up the boards past the hash marks.
	var n: int = _build(Vector3(3.0, 0.0, 28.0))
	assert_gt(n, 0)
	var up_the_wall: bool = false
	for k: int in n:
		var path: Array[Vector3] = AIRimPass.paths[k]
		for p: Vector3 in path:
			if absf(p.x) > 10.5 and p.z < 18.0:
				up_the_wall = true
	assert_true(up_the_wall, "a rim is carried up the side wall by the boards")


func test_no_rim_leg_runs_through_a_net() -> void:
	var n: int = _build(Vector3(-2.0, 0.0, 28.5))
	for k: int in n:
		var path: Array[Vector3] = AIRimPass.paths[k]
		var prev: Vector3 = AIRimPass.origin
		for p: Vector3 in path:
			assert_false(AIActionScoring.pass_lane_blocked_by_net(prev, p),
					"launch %d crosses the cage" % k)
			prev = p


func test_a_defender_on_the_wall_wins_the_race() -> void:
	var from := Vector3(3.0, 0.0, 28.0)
	var clear: int = _build(from)
	var clear_t: Array[float] = []
	for k: int in clear:
		clear_t.append(AIRimPass.opp_time(k))
	var on_wall: Array[Vector3] = [Vector3(12.0, 0.0, 20.0)]
	var n: int = _build(from, on_wall)
	assert_eq(n, clear)
	var beaten: int = 0
	for k: int in n:
		assert_eq(clear_t[k], INF, "nobody races an empty rink")
		if AIRimPass.opp_time(k) < INF:
			beaten += 1
	assert_gt(beaten, 0, "the man on the wall reaches the rims up it")


func test_a_receiver_up_the_wall_meets_the_rim() -> void:
	var n: int = _build(Vector3(3.0, 0.0, 28.0))
	var best_t: float = INF
	for k: int in n:
		best_t = minf(best_t, AIRimPass.meet_time(k, Vector3(11.5, 0.0, 14.0),
				Vector3.ZERO, AIActionScoring.SKATER_REF_SPEED_M_S))
	assert_lt(best_t, INF, "the half-wall winger can meet a rim")


func _keeper_stops(margin: float) -> int:
	# OUR rim around THEIR end boards (team 0 attacks -Z) from the far corner.
	AIActionScoring.goalie_puck_play_go_margin_s = margin
	var n: int = _build(Vector3(-11.5, 0.0, -24.0), [], Vector3(0.0, 0.0, -25.8))
	var stopped: int = 0
	for k: int in n:
		if AIRimPass.opp_time(k) < INF:
			stopped += 1
	return stopped


func test_the_keeper_stays_home_with_the_rimmer_on_top_of_him() -> void:
	# The live trip needs the whole out-stop-back inside his GO margin of the
	# nearest of us, and the rimmer himself is metres away: even the Hard keeper
	# lets a rim from his own corner go by.
	assert_eq(_keeper_stops(GoalieSkillProfile.hard().puck_play_go_margin_s), 0)


func test_the_keeper_race_is_the_trip_and_the_tier() -> void:
	# Trip gate waived: the keeper can be set on the rim behind his net. A tier
	# that never plays the puck takes none however much time he has.
	assert_gt(_keeper_stops(-10.0), 0, "set in time, he stops it")
	assert_eq(_keeper_stops(INF), 0, "a keeper who never leaves stops none")
