extends GutTest

# Properties of the one-chance strip read (AIStripOdds): what any calibration of
# it does.

var _still: Array[Vector3] = [Vector3.ZERO]


func _keep(defs: Array[Vector3], vels: Array[Vector3], from: Vector3, to: Vector3,
		t: float) -> float:
	return AIStripOdds.carry_keep(from, to, t, defs, vels)


func test_a_man_who_cannot_get_there_first_takes_nothing() -> void:
	var far: Array[Vector3] = [Vector3(0, 0, 25)]
	assert_eq(_keep(far, _still, Vector3.ZERO, Vector3(0, 0, -6), 1.0), 1.0)


func test_a_set_stick_on_the_path_takes_it_at_the_set_odds() -> void:
	var on: Array[Vector3] = [Vector3(0, 0, -6)]
	assert_almost_eq(_keep(on, _still, Vector3.ZERO, Vector3(0, 0, -6), 1.0),
			1.0 - AIStripOdds.SET_STRIP, 1e-6)


func test_a_stick_arriving_just_in_time_takes_nothing() -> void:
	# His stick reaches the point the instant the puck does: no time to set.
	var reach: float = AISkaterCaps.LEAGUE_MAX_BLADE_REACH_M
	var him := Vector3(0, 0, -reach - 4.0)
	var point := Vector3(0, 0, -reach)
	var arrive: float = AIArrival.time_to_arrive_caps(him, Vector3(0, 0, -2.0 * reach), Vector3.ZERO,
			null)
	assert_eq(AIStripOdds.chance_at(him, Vector3.ZERO, null, point, arrive), 0.0)
	assert_gt(AIStripOdds.chance_at(him, Vector3.ZERO, null, point, arrive + 1.0), 0.9,
			"and given a second to set, he has it")


func test_the_further_he_has_to_go_the_safer() -> void:
	var prev: float = -1.0
	for d: float in [3.0, 5.0, 7.0, 9.0, 12.0]:
		var him: Array[Vector3] = [Vector3(d, 0, -5)]
		var k: float = _keep(him, _still, Vector3.ZERO, Vector3(0, 0, -8), 1.0)
		assert_gte(k, prev - 1e-6, "%.0f m off it" % d)
		prev = k


func test_his_momentum_is_his_head_start() -> void:
	var him: Array[Vector3] = [Vector3(5, 0, -5)]
	var toward: Array[Vector3] = [Vector3(-6, 0, 0)]
	var away: Array[Vector3] = [Vector3(6, 0, 0)]
	assert_lt(_keep(him, toward, Vector3.ZERO, Vector3(0, 0, -8), 1.0),
			_keep(him, away, Vector3.ZERO, Vector3(0, 0, -8), 1.0))


func test_waiting_never_thins_the_defence() -> void:
	# Holding the puck longer only gives a defender more time to get to it.
	var him: Array[Vector3] = [Vector3(6, 0, 0)]
	var prev: float = 2.0
	for t: float in [0.3, 0.6, 1.0, 1.5, 2.0, 3.0]:
		var k: float = _keep(him, _still, Vector3.ZERO, Vector3.ZERO, t)
		assert_lte(k, prev + 1e-6, "held %.1f s" % t)
		prev = k


func test_a_man_who_can_only_get_to_the_middle_after_the_window_is_a_later_decision() -> void:
	# The path passes him only after its first COMMIT_S, and ends where he cannot
	# get to.
	var him: Array[Vector3] = [Vector3(0, 0, -15)]
	var points: Array[Vector3] = [Vector3(0, 0, -2), Vector3(0, 0, -4), Vector3(0, 0, -15),
			Vector3(0, 0, 25)]
	var times: Array[float] = [0.5, 1.0, 1.5, 1.6]
	assert_eq(AIStripOdds.path_keep(points, times, him, _still), 1.0)
	assert_lt(AIStripOdds.path_keep(points, times, him, _still, [], 0.0, INF), 1.0,
			"read the whole way, he takes it")


func test_where_the_carry_is_going_is_read_past_the_window() -> void:
	# A man waiting where a 3 s carry ends: the place it is going is his.
	var him: Array[Vector3] = [Vector3(0, 0, -24)]
	assert_almost_eq(_keep(him, _still, Vector3.ZERO, Vector3(0, 0, -24), 3.0),
			1.0 - AIStripOdds.SET_STRIP, 1e-6)


func test_defenders_are_separate_chances() -> void:
	var one: Array[Vector3] = [Vector3(3, 0, -5)]
	var two: Array[Vector3] = [Vector3(3, 0, -5), Vector3(-3, 0, -5)]
	var stills: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	var alone: float = _keep(one, _still, Vector3.ZERO, Vector3(0, 0, -8), 1.0)
	assert_lt(alone, 1.0)
	assert_almost_eq(_keep(two, stills, Vector3.ZERO, Vector3(0, 0, -8), 1.0), alone * alone, 1e-6,
			"a mirror image of him is another chance as good")


func test_a_man_gets_one_chance_however_long_the_puck_is_in_his_reach() -> void:
	# Skating past him or straight through him, he has the one chance.
	var him: Array[Vector3] = [Vector3(0, 0, -5)]
	var through: float = _keep(him, _still, Vector3.ZERO, Vector3(0, 0, -10), 1.5)
	var past: float = _keep(him, _still, Vector3(1, 0, 0), Vector3(1, 0, -10), 1.5)
	assert_almost_eq(through, past, 1e-6)
	assert_almost_eq(through, 1.0 - AIStripOdds.SET_STRIP, 1e-6)


func test_the_path_keep_reads_as_the_carry_keep() -> void:
	var him: Array[Vector3] = [Vector3(4, 0, -6)]
	var vel: Array[Vector3] = [Vector3(-2, 0, 1)]
	var points: Array[Vector3] = []
	var times: Array[float] = []
	for k: int in 10:
		points.append(Vector3(0, 0, -0.8 * (k + 1)))
		times.append(0.1 * (k + 1))
	assert_almost_eq(AIStripOdds.path_keep(points, times, him, vel),
			AIStripOdds.carry_keep(Vector3.ZERO, Vector3(0, 0, -8), 1.0, him, vel), 1e-6)
