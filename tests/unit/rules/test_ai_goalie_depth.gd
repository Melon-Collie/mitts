extends GutTest

# AIGoalieModel.planned_goalie_depth — the planning keeper's radial depth: the
# rush backflow pulls him in, retreat-only, at a skating rate. The depths the
# current chart gives at the reference drives are the snapshot,
# test_goalie_depth_calibration_snapshot.

const Snapshot := preload("res://tests/snapshot.gd")
const SNAPSHOT_PATH := "res://tests/unit/rules/snapshots/goalie_depth.txt"
const GOAL := Vector3(0, 0, -GameRules.GOAL_LINE_Z)
# Challenge depth the rush fixtures start the keeper at (the Hard tier's).
const CHALLENGE_DEPTH: float = 1.75
const RUSH_CLOSING_M_S: float = 6.0


func _keeper_at(depth: float) -> Vector3:
	return Vector3(0.0, 0.0, GOAL.z + depth)


func _puck_out(dist: float) -> Vector3:
	return Vector3(0.0, 0.0, GOAL.z + dist)


func _rush_depth(dist: float, window_s: float) -> float:
	return AIGoalieModel.planned_goalie_depth(
			_keeper_at(CHALLENGE_DEPTH), GOAL, _puck_out(dist), window_s, RUSH_CLOSING_M_S)


func _shoot_at_depth(release: Vector3, depth: float) -> float:
	var opps: Array[Vector3] = []
	return AIActionScoring.score_shoot(release, GOAL, _keeper_at(depth),
			GameRules.NET_HALF_WIDTH, opps, AIBotMechanics.WRISTER_SHOT_SPEED_M_S)


func before_each() -> void:
	AIGoalieModel.set_goalie_profile(GoalieSkillProfile.hard())


# ── Retreat-only ────────────────────────────────────────────────────────────

func test_a_settled_read_leaves_the_keeper_exactly_where_he_is() -> void:
	# His live depth is replicated truth and is set by a lot the planner cannot
	# see (post seals, backdoor caps, recoveries). Nothing about a static puck
	# may move him, in either direction.
	for depth: float in [0.1, 0.6, 1.2, 1.75]:
		var d: float = AIGoalieModel.planned_goalie_depth(
				_keeper_at(depth), GOAL, _puck_out(6.6), 0.3, 0.0)
		assert_almost_eq(d, depth, 0.0001,
				"a static read never moves the keeper's depth")


func test_the_planner_never_challenges_the_keeper_further_out() -> void:
	# A keeper sitting deep in his crease with the puck at chart-challenge range
	# must not be pushed out to the chart station — that would invent an
	# aggressive challenge the real keeper may already have declined.
	var d: float = AIGoalieModel.planned_goalie_depth(
			_keeper_at(0.2), GOAL, _puck_out(6.0), 1.0, 8.0)
	assert_almost_eq(d, 0.2, 0.0001, "retreat-only: depth is never pushed out")


# ── The rush backflow ───────────────────────────────────────────────────────

func test_a_closing_carrier_backs_the_keeper_in() -> void:
	# A rush inside the engage range backs him off his challenge, never through
	# his own goal line, and a longer window only lets him retreat further.
	for dist: float in [6.0, 4.0, 3.0, 2.0]:
		var prev: float = CHALLENGE_DEPTH
		for window: float in [0.25, 0.5, 1.0, 2.0]:
			var d: float = _rush_depth(dist, window)
			assert_lt(d, CHALLENGE_DEPTH,
					"a closing rush backs the keeper off his challenge (%.0f m, %.2f s)"
					% [dist, window])
			assert_gt(d, 0.0, "…but not through his own goal line")
			assert_lte(d, prev, "a longer window never leaves him further out")
			prev = d


func test_the_backflow_is_monotone_in_how_far_the_rush_has_come() -> void:
	var prev: float = INF
	for dist: float in [7.0, 5.0, 4.0, 3.0, 2.0]:
		var d: float = _rush_depth(dist, 1.0)
		assert_lt(d, prev, "deeper drive → deeper keeper (dist %.1f)" % dist)
		prev = d


func test_a_stalled_carrier_does_not_move_him() -> void:
	# Below the live keeper's rush_min_closing_speed he keeps the challenge and
	# makes the attacker come to him — a walk-in is not a rush.
	var d: float = AIGoalieModel.planned_goalie_depth(
			_keeper_at(CHALLENGE_DEPTH), GOAL, _puck_out(3.0), 1.0,
			AIGoalieModel.GOALIE_RUSH_MIN_CLOSING_M_S * 0.5)
	assert_almost_eq(d, CHALLENGE_DEPTH, 0.0001, "a stalled attacker earns no backflow")


func test_the_retreat_is_rate_bounded() -> void:
	# He skates the retreat; a short window cannot teleport him in. The backflow
	# is speed-matched to the carrier, so he gives depth no faster than the crease
	# skating rate or the attacker's closing speed, whichever is higher.
	var max_rate: float = maxf(AIGoalieModel.GOALIE_DEPTH_MAX_SPEED_M_S, RUSH_CLOSING_M_S)
	for window: float in [0.02, 0.05, 0.1, 0.2]:
		var given: float = CHALLENGE_DEPTH - _rush_depth(2.0, window)
		assert_gt(given, 0.0, "the rush moves him even over %.2f s" % window)
		assert_lte(given, max_rate * window + 1e-4,
				"over %.2f s he gives at most a skating rate's depth" % window)


# ── What it buys the shooter ────────────────────────────────────────────────

func test_the_doorstep_drive_stops_reading_as_a_covered_net() -> void:
	# A keeper held frozen at challenge depth stands a quarter-metre off a 2 m
	# release and his tangent cone swallows the net; the retreat he actually
	# makes on the drive opens it.
	var release: Vector3 = _puck_out(2.0)
	var frozen: float = _shoot_at_depth(release, CHALLENGE_DEPTH)
	var retreated: float = _shoot_at_depth(release, _rush_depth(2.0, 0.9))
	assert_gt(retreated, frozen,
			"the retreating keeper concedes more than the frozen one; frozen %.3f retreated %.3f"
			% [frozen, retreated])


func test_goalie_depth_calibration_snapshot() -> void:
	var snap := Snapshot.new(SNAPSHOT_PATH)
	snap.record("rush to 3 m over 1 s, planned depth", _rush_depth(3.0, 1.0))
	snap.record("rush to 2 m over 20 ms, planned depth", _rush_depth(2.0, 0.02))
	snap.record("doorstep 2 m, keeper frozen at challenge depth",
			_shoot_at_depth(_puck_out(2.0), CHALLENGE_DEPTH))
	snap.record("doorstep 2 m, keeper retreated over 0.9 s",
			_shoot_at_depth(_puck_out(2.0), _rush_depth(2.0, 0.9)))
	snap.verify(self)
