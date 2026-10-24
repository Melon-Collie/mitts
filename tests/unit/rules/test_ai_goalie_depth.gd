extends GutTest

# AIGoalieModel.planned_goalie_depth — the planning keeper's depth: his own rule
# for a carrier coming at him (KeeperPositioning.depth_for, held against his
# brain by test_ai_goalie_model_mirrors.gd), taken retreat-only, at his C-cuts'
# pace. The depths at the reference drives are the snapshot,
# test_goalie_depth_calibration_snapshot.

const Snapshot := preload("res://tests/snapshot.gd")
const SNAPSHOT_PATH := "res://tests/unit/rules/snapshots/goalie_depth.txt"
const GOAL := Vector3(0, 0, -GameRules.GOAL_LINE_Z)
# Where the fixtures start him: his skates on the top of the crease.
const TOP: float = CreaseRules.ARC_RADIUS
const RUSH_CLOSING_M_S: float = 6.0


func _keeper_at(depth: float) -> Vector3:
	return Vector3(0.0, 0.0, GOAL.z + depth)


func _puck_out(dist: float) -> Vector3:
	return Vector3(0.0, 0.0, GOAL.z + dist)


func _rush_depth(dist: float, window_s: float, closing: float = RUSH_CLOSING_M_S) -> float:
	return AIGoalieModel.planned_goalie_depth(_keeper_at(TOP), GOAL, _puck_out(dist), window_s, closing)


func test_the_planner_never_challenges_the_keeper_further_out() -> void:
	# His live depth is replicated truth, set by a lot the planner cannot see,
	# so a keeper sitting deep is never pushed out to where his rule would stand.
	var d: float = AIGoalieModel.planned_goalie_depth(_keeper_at(0.2), GOAL, _puck_out(6.0), 1.0, 8.0)
	assert_almost_eq(d, 0.2, 0.0001, "retreat-only: depth is never pushed out")


func test_no_time_leaves_him_where_he_is() -> void:
	assert_almost_eq(_rush_depth(2.0, 0.0), TOP, 0.0001)


func test_a_carrier_nearer_backs_him_in_further() -> void:
	var prev: float = INF
	for dist: float in [7.0, 5.0, 4.0, 3.0, 2.0]:
		var d: float = _rush_depth(dist, 1.0)
		assert_lte(d, prev, "a nearer carrier never leaves him further out (dist %.1f)" % dist)
		prev = d
	assert_lt(prev, TOP, "a carrier in tight backs him off the top of the crease")


func test_a_carrier_coming_faster_backs_him_in_no_less() -> void:
	for dist: float in [6.0, 4.0, 3.0]:
		assert_lte(_rush_depth(dist, 1.0, 9.0), _rush_depth(dist, 1.0, 0.0) + 1e-6,
				"coming at him faster backs him in at least as far (dist %.1f)" % dist)


func test_the_retreat_is_rate_bounded() -> void:
	# He skates the retreat on his C-cuts; a short window cannot teleport him in.
	var c_cuts: float = KeeperFootwork.new().c_cut_speed
	for window: float in [0.02, 0.05, 0.1, 0.2]:
		var given: float = TOP - _rush_depth(2.0, window)
		assert_gt(given, 0.0, "the rush moves him even over %.2f s" % window)
		assert_lte(given, c_cuts * window + 1e-4,
				"over %.2f s he gives at most his C-cuts' depth" % window)


func test_out_of_the_zone_he_waits_in_the_middle_of_the_crease() -> void:
	assert_almost_eq(AIGoalieModel.keeper_depth(GOAL, _puck_out(KeeperPositioning.BLUE_LINE_M + 5.0)),
			TOP * KeeperPositioning.AWAY_DEPTH_SHARE, 1e-6)


func test_goalie_depth_calibration_snapshot() -> void:
	var snap := Snapshot.new(SNAPSHOT_PATH)
	snap.record("rush to 3 m over 1 s, planned depth", _rush_depth(3.0, 1.0))
	snap.record("rush to 2 m over 20 ms, planned depth", _rush_depth(2.0, 0.02))
	snap.verify(self)
