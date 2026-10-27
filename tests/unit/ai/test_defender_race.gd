extends GutTest

# Properties of the defender race (AIDefenderRace): what any calibration of it
# does.


func test_a_stick_already_on_the_point_contests_it() -> void:
	var t: float = AIDefenderRace.stick_time(Vector3.ZERO, Vector3.ZERO, null, Vector3(0.5, 0, 0))
	assert_eq(t, 0.0)
	assert_lte(AIDefenderRace.keep(t, 0.0), 0.5, "a puck there now is at best even")
	assert_lt(AIDefenderRace.keep(t, 0.5), AIDefenderRace.keep(t, 0.0),
			"and is his more surely the longer it stays")


func test_further_is_later() -> void:
	var prev: float = -1.0
	for d: float in [3.0, 6.0, 10.0, 15.0]:
		var t: float = AIDefenderRace.stick_time(Vector3.ZERO, Vector3.ZERO, null,
				Vector3(d, 0, 0))
		assert_gt(t, prev, "%.0f m" % d)
		prev = t


func test_momentum_toward_the_point_gets_there_sooner() -> void:
	var point := Vector3(8.0, 0, 0)
	var still: float = AIDefenderRace.stick_time(Vector3.ZERO, Vector3.ZERO, null, point)
	assert_lt(AIDefenderRace.stick_time(Vector3.ZERO, Vector3(5, 0, 0), null, point), still)
	assert_gt(AIDefenderRace.stick_time(Vector3.ZERO, Vector3(-5, 0, 0), null, point), still)


func test_the_keep_grows_with_his_lateness_and_ties_are_even() -> void:
	assert_almost_eq(AIDefenderRace.keep(1.0, 1.0), 0.5, 1e-6)
	var prev: float = -1.0
	for late: float in [-1.0, -0.2, 0.0, 0.2, 1.0]:
		var k: float = AIDefenderRace.keep(1.0 + late, 1.0)
		assert_gte(k, prev)
		prev = k


func test_the_same_margin_is_surer_closer_in() -> void:
	# A defender 0.3 s late to a point 0.5 s out is beaten more surely than one
	# 0.3 s late to a point 3 s out: there is less time for him to do otherwise.
	assert_gt(AIDefenderRace.keep(0.8, 0.5), AIDefenderRace.keep(3.3, 3.0))


func test_a_path_keeps_against_each_man_at_his_best_point_and_men_multiply() -> void:
	var points: Array[Vector3] = [Vector3(0, 0, -2), Vector3(0, 0, -4), Vector3(0, 0, -6)]
	var times: Array[float] = [0.3, 0.6, 0.9]
	var one: Array[Vector3] = [Vector3(3.0, 0, -6)]
	var vel: Array[Vector3] = [Vector3.ZERO]
	var alone: float = AIDefenderRace.path_keep(points, times, one, vel, [])
	var worst: float = 1.0
	for k: int in points.size():
		worst = minf(worst, AIDefenderRace.keep(AIDefenderRace.stick_time(one[0], vel[0], null,
				points[k]), times[k]))
	assert_almost_eq(alone, worst, 1e-6)
	var two: Array[Vector3] = [one[0], Vector3(-3.0, 0, -6)]
	var vels: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	var both: float = AIDefenderRace.path_keep(points, times, two, vels, [])
	assert_almost_eq(both, alone * alone, 1e-6, "a mirror image of him costs as much again")
	var swapped: Array[Vector3] = [two[1], two[0]]
	assert_almost_eq(AIDefenderRace.path_keep(points, times, swapped, vels, []), both, 1e-6)


func test_a_man_out_of_reach_of_every_point_costs_nothing() -> void:
	var points: Array[Vector3] = [Vector3(0, 0, -2)]
	var times: Array[float] = [0.3]
	var far: Array[Vector3] = [Vector3(0, 0, 25)]
	var vel: Array[Vector3] = [Vector3.ZERO]
	assert_eq(AIDefenderRace.path_keep(points, times, far, vel, []), 1.0)
