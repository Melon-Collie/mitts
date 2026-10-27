extends GutTest

# Properties of the strip odds (AIStripOdds): what any calibration of it does.

var _none: Array[Vector3] = []


func test_a_defender_on_the_puck_now_is_within_his_stick() -> void:
	assert_eq(AIStripOdds.odds_within(Vector3.ZERO, Vector3.ZERO, null, Vector3(1.0, 0, 0), 0.0),
			1.0)
	assert_eq(AIStripOdds.odds_within(Vector3.ZERO, Vector3.ZERO, null, Vector3(3.0, 0, 0), 0.0),
			0.0, "and one out of reach now is not")


func test_the_further_off_his_line_the_less_likely() -> void:
	var prev: float = 2.0
	for d: float in [0.0, 1.0, 2.0, 3.0, 5.0, 8.0]:
		var p: float = AIStripOdds.odds_within(Vector3.ZERO, Vector3(0, 0, -4.0), null,
				Vector3(d, 0, -4.0), 1.0)
		assert_lte(p, prev + 1e-6, "%.0f m off it" % d)
		prev = p


func test_his_momentum_carries_his_threat() -> void:
	var ahead: float = AIStripOdds.odds_within(Vector3.ZERO, Vector3(0, 0, -6.0), null,
			Vector3(0, 0, -6.0), 1.0)
	var behind: float = AIStripOdds.odds_within(Vector3.ZERO, Vector3(0, 0, -6.0), null,
			Vector3(0, 0, 6.0), 1.0)
	assert_gt(ahead, behind, "where he is going, not where he was")


func test_the_spread_grows_with_time() -> void:
	var point := Vector3(4.0, 0, 0)
	var soon: float = AIStripOdds.odds_within(Vector3.ZERO, Vector3.ZERO, null, point, 0.3)
	var later: float = AIStripOdds.odds_within(Vector3.ZERO, Vector3.ZERO, null, point, 1.5)
	assert_lt(soon, later, "a spot 4 m off is his only given time")


func test_the_table_matches_the_integral() -> void:
	# The fan's odds over the disc by brute force, against the table's.
	for c: Vector2 in [Vector2(0.0, 0.5), Vector2(1.5, 0.3), Vector2(2.5, 1.2), Vector2(0.7, 3.0)]:
		var d: float = c.x
		var l: float = c.y
		var brute: float = 0.0
		var n: int = 200
		for a: int in n:
			for b: int in n:
				var x: float = -1.0 + 2.0 * (a + 0.5) / n
				var z: float = -1.0 + 2.0 * (b + 0.5) / n
				if x * x + z * z > 1.0:
					continue
				var r: float = Vector2(x + d, z).length()
				brute += exp(-r / l) / (TAU * l * l) * (4.0 / (n * n))
		assert_almost_eq(AIStripOdds._within(d, l), brute, 0.02, "d %.1f, l %.1f" % [d, l])


func test_defenders_add() -> void:
	var points: Array[Vector3] = [Vector3(0, 0, -2), Vector3(0, 0, -4), Vector3(0, 0, -6)]
	var times: Array[float] = [0.3, 0.6, 0.9]
	var one: Array[Vector3] = [Vector3(2.5, 0, -5)]
	var still: Array[Vector3] = [Vector3.ZERO]
	var alone: float = AIStripOdds.path_strips(Vector3.ZERO, points, times, one, still)
	assert_gt(alone, 0.0)
	var two: Array[Vector3] = [one[0], Vector3(-2.5, 0, -5)]
	var stills: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	assert_almost_eq(AIStripOdds.path_strips(Vector3.ZERO, points, times, two, stills),
			2.0 * alone, 1e-5, "a mirror image of him costs as much again")
	assert_eq(AIStripOdds.path_strips(Vector3.ZERO, points, times, _none, []), 0.0)


func test_a_man_far_from_the_path_costs_nothing() -> void:
	var points: Array[Vector3] = [Vector3(0, 0, -2)]
	var times: Array[float] = [0.3]
	var far: Array[Vector3] = [Vector3(0, 0, 25)]
	var still: Array[Vector3] = [Vector3.ZERO]
	assert_almost_eq(AIStripOdds.path_strips(Vector3.ZERO, points, times, far, still), 0.0, 1e-6)


func test_a_held_puck_in_his_reach_is_stripped_at_the_standing_rate() -> void:
	var him: Array[Vector3] = [Vector3(1.0, 0, 0)]
	var still: Array[Vector3] = [Vector3.ZERO]
	assert_almost_eq(AIStripOdds.dwell_strips(Vector3.ZERO, 0.0, 0.1, him, still),
			0.1 * AIStripOdds.STANDING_STRIP_RATE, 0.02)
	assert_almost_eq(AIStripOdds.keep(0.0), 1.0, 1e-9)
