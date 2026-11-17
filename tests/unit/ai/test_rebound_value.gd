extends GutTest

# AIReboundValue: the rebound's second chance, raced. Properties only; what the
# field measures is the goalie's (test_rebound_field_is_current.gd).

const GOAL := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z)
const RELEASE := Vector3(2.0, 0.0, -GameRules.GOAL_LINE_Z + 15.0)
var _none: Array[Vector3] = []


func _credit(ours: Array[Vector3], theirs: Array[Vector3]) -> float:
	var ov: Array[Vector3] = []
	for _p: Vector3 in ours:
		ov.append(Vector3.ZERO)
	var tv: Array[Vector3] = []
	for _p: Vector3 in theirs:
		tv.append(Vector3.ZERO)
	return AIReboundValue.credit(RELEASE, GOAL, ours, ov, theirs, tv)


func test_the_late_chance_is_measured_where_the_value_reads_it() -> void:
	assert_eq(AIReboundValue.LATE_SAMPLES,
			preload("res://tests/unit/ai/rebound_shot_harness.gd").LATE_SAMPLES)


func test_nobody_of_ours_wins_no_rebound() -> void:
	assert_eq(_credit(_none, [Vector3(0.0, 0.0, GOAL.z + 3.0)] as Array[Vector3]), 0.0)


func test_a_man_at_the_net_is_worth_more_than_one_at_the_line() -> void:
	# Their D a stride off the crease: our man beside the net beats him to the
	# rebound, one at the line never does.
	var d: Array[Vector3] = [Vector3(-1.5, 0.0, GOAL.z + 4.5)]
	var at_net: float = _credit([RELEASE, Vector3(0.5, 0.0, GOAL.z + 3.0)] as Array[Vector3], d)
	var at_line: float = _credit([RELEASE, Vector3(0.0, 0.0, GOAL.z + 19.0)] as Array[Vector3], d)
	assert_gt(at_net, at_line, "the net-front man gets there first")
	assert_gt(at_net, 0.0)


func test_their_man_at_the_net_takes_it_away() -> void:
	var ours: Array[Vector3] = [RELEASE, Vector3(0.5, 0.0, GOAL.z + 5.0)]
	var free: float = _credit(ours, _none)
	var boxed: float = _credit(ours, [Vector3(0.0, 0.0, GOAL.z + 2.5),
			Vector3(-1.5, 0.0, GOAL.z + 2.5), Vector3(1.5, 0.0, GOAL.z + 2.5)] as Array[Vector3])
	assert_lt(boxed, free, "defenders in front of him win the rebounds he would")


func test_never_more_than_a_goal() -> void:
	var v: float = _credit([Vector3(0.0, 0.0, GOAL.z + 2.0), Vector3(-2.0, 0.0, GOAL.z + 3.0),
			Vector3(2.0, 0.0, GOAL.z + 3.0)] as Array[Vector3], _none)
	assert_between(v, 0.0, 1.0)


# A man added at a station (value_with) is priced as credit prices him among
# ours, so a station's share of a rebound is the credit's own.
func test_a_man_added_at_a_station_is_priced_as_one_of_ours() -> void:
	var d: Array[Vector3] = [Vector3(-1.5, 0.0, GOAL.z + 4.5)]
	var dv: Array[Vector3] = [Vector3.ZERO]
	var ours: Array[Vector3] = [RELEASE]
	var ov: Array[Vector3] = [Vector3.ZERO]
	var race := AIReboundValue.new()
	race.fill(RELEASE, GOAL, ours, ov, d, dv)
	assert_almost_eq(race.value_with(Vector3.INF), _credit(ours, d), 1e-6, "nobody added")
	for at: Vector3 in [Vector3(0.5, 0.0, GOAL.z + 3.0), Vector3(-3.0, 0.0, GOAL.z + 8.0)]:
		assert_almost_eq(race.value_with(at), _credit([RELEASE, at] as Array[Vector3], d), 1e-6,
				"a man at %s" % at)
