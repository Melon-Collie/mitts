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


func test_a_stick_on_the_path_takes_it_at_the_dead_on_odds() -> void:
	var on: Array[Vector3] = [Vector3(0, 0, -6)]
	assert_almost_eq(_keep(on, _still, Vector3.ZERO, Vector3(0, 0, -6), 1.0),
			1.0 - AIStripOdds.DEAD_ON_STRIP, 1e-6)


func test_the_further_off_his_line_the_safer_and_out_of_his_reach_none() -> void:
	var him: Array[Vector3] = [Vector3(0, 0, -4)]
	var prev: float = -1.0
	for x: float in [0.0, 0.5, 1.0, 2.0, 3.0, 4.0]:
		var k: float = _keep(him, _still, Vector3(x, 0, 0), Vector3(x, 0, -8), 1.0)
		assert_gte(k, prev - 1e-6, "%.1f m off him" % x)
		prev = k
	assert_gt(_keep(him, _still, Vector3(3, 0, 0), Vector3(3, 0, -8), 1.0),
			_keep(him, _still, Vector3.ZERO, Vector3(0, 0, -8), 1.0))
	assert_eq(_keep(him, _still, Vector3(8, 0, 0), Vector3(8, 0, -8), 1.0), 1.0,
			"out of his reach")


func test_the_odds_climb_with_how_deep_in_his_reach_the_escape_is() -> void:
	var set_m: float = AIStripOdds.ESCAPE_SET_M
	var band: float = AIStripOdds.ESCAPE_BAND_M
	assert_almost_eq(AIStripOdds.strip_odds(set_m), 0.5 * AIStripOdds.DEAD_ON_STRIP, 1e-6)
	assert_eq(AIStripOdds.strip_odds(set_m - band), 0.0)
	assert_eq(AIStripOdds.strip_odds(-INF), 0.0)
	assert_almost_eq(AIStripOdds.strip_odds(set_m + band), AIStripOdds.DEAD_ON_STRIP, 1e-6)
	var prev: float = -1.0
	for m: float in [-3.0, -1.0, 0.0, 0.5, 1.0, 2.0, 3.0]:
		assert_gte(AIStripOdds.strip_odds(m), prev)
		prev = AIStripOdds.strip_odds(m)


func test_a_plan_that_stands_gives_him_nowhere_to_dodge() -> void:
	# A man 3 m off his shoulder: skating on, the carrier slides away from him;
	# holding the spot, he waits for him.
	var him: Array[Vector3] = [Vector3(3, 0, 0)]
	var skating: float = AIStripOdds.escape_margin(Vector3.ZERO, Vector3(0, 0, -8), 0.5, him,
			_still)
	var holding: float = AIStripOdds.escape_margin(Vector3.ZERO, Vector3.ZERO, 0.5, him, _still)
	assert_lt(skating, holding)


func test_a_man_behind_who_is_quicker_runs_him_down() -> void:
	var behind: Array[Vector3] = [Vector3(0, 0, 3)]
	var quicker: Array[Vector3] = [Vector3(0, 0, -8)]
	var level: Array[Vector3] = [Vector3(0, 0, -4)]
	var quick: float = _keep(behind, quicker, Vector3.ZERO, Vector3(0, 0, -4), 1.0)
	assert_lt(quick, 1.0 - 0.5 * AIStripOdds.DEAD_ON_STRIP, "he gets to him")
	assert_lt(quick, _keep(behind, level, Vector3.ZERO, Vector3(0, 0, -4), 1.0),
			"and a man only as quick does not as surely")


func test_a_man_each_side_shuts_the_dodge() -> void:
	# Alone, the carrier slides away from him; with his mirror image there too,
	# sliding away from one is sliding into the other.
	var one: Array[Vector3] = [Vector3(3, 0, -5)]
	var two: Array[Vector3] = [Vector3(3, 0, -5), Vector3(-3, 0, -5)]
	var stills: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	var alone: float = _keep(one, _still, Vector3.ZERO, Vector3(0, 0, -8), 1.0)
	assert_lt(_keep(two, stills, Vector3.ZERO, Vector3(0, 0, -8), 1.0), alone * alone)


func test_another_man_never_makes_it_safer() -> void:
	var one: Array[Vector3] = [Vector3(2, 0, -5)]
	var stills: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	var alone: float = _keep(one, _still, Vector3.ZERO, Vector3(0, 0, -8), 1.0)
	for x: float in [-6.0, -3.0, 0.0, 3.0, 6.0]:
		var two: Array[Vector3] = [Vector3(2, 0, -5), Vector3(x, 0, -9)]
		assert_lte(_keep(two, stills, Vector3.ZERO, Vector3(0, 0, -8), 1.0), alone + 1e-6,
				"a second man at x %.0f" % x)


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


func test_setting_off_later_never_thins_the_defence() -> void:
	# The same carry, started later: the defence has longer to get to it, and the
	# carrier no longer to dodge once he is on it.
	for him: Vector3 in [Vector3(3, 0, -5), Vector3(0, 0, -12), Vector3(6, 0, 2)]:
		var defs: Array[Vector3] = [him]
		var prev: float = 2.0
		for start: float in [0.0, 0.5, 1.0, 2.0, 3.0]:
			var k: float = AIStripOdds.carry_keep(Vector3.ZERO, Vector3(0, 0, -8), 1.0, defs,
					_still, [], 0.0, start)
			assert_lte(k, prev + 1e-6, "him at %s, setting off at %.1f s" % [him, start])
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


func test_a_man_gets_one_chance_however_long_the_puck_is_in_his_reach() -> void:
	# Skating straight through him slowly or quickly, he has the one chance.
	var him: Array[Vector3] = [Vector3(0, 0, -4)]
	var slow: float = _keep(him, _still, Vector3.ZERO, Vector3(0, 0, -5), 1.0)
	var fast: float = _keep(him, _still, Vector3.ZERO, Vector3(0, 0, -8), 1.0)
	assert_almost_eq(slow, fast, 1e-6)
	assert_almost_eq(slow, 1.0 - AIStripOdds.DEAD_ON_STRIP, 1e-6)


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
