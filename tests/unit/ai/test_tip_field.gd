extends GutTest

# AITipField reads the generated tip field (properties of the reader; the
# numbers are the goalie's, held to him by test_tip_field_is_current.gd).

const NET := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z)
const LEVELS: Array[int] = [ShotMechanics.ELEVATION_FLAT, ShotMechanics.ELEVATION_LOW,
		ShotMechanics.ELEVATION_MID, ShotMechanics.ELEVATION_HIGH]


# The share of a cell's tips that scored, straight off its row.
func _row_odds(x: float, fwd: float, along: float, level: int) -> float:
	for r: String in AITipFieldData.ROWS:
		var f: PackedStringArray = r.split("\t")
		if is_equal_approx(float(f[1]), x) and is_equal_approx(float(f[2]), fwd) \
				and is_equal_approx(float(f[3]), along) and int(f[4]) == level:
			var tips: int = f[5].length() - f[5].count("-") - f[5].count("x")
			return float(f[5].count("G")) / float(tips)
	return NAN


func _release(x: float, fwd: float, net: Vector3 = NET) -> Vector3:
	return Vector3(x, 0.0, net.z - signf(net.z) * fwd)


func _tip(release: Vector3, along: float, net: Vector3 = NET) -> Vector3:
	return net + (release - net).normalized() * along


func test_a_measured_cell_reads_its_own_row() -> void:
	for x: float in [-8.0, 0.0, 4.0]:
		for fwd: float in [9.5, 19.5]:
			for along: float in AITipFieldData.TIP_ALONG_M:
				for level: int in LEVELS:
					var r: Vector3 = _release(x, fwd)
					assert_almost_eq(AITipField.odds(r, NET, _tip(r, along), level),
							_row_odds(x, fwd, along, level), 1e-5,
							"x %.1f, %.1f out, tipped %.1f out at %d" % [x, fwd, along, level])


func test_either_net_reads_the_same() -> void:
	var far := Vector3(0.0, 0.0, GameRules.GOAL_LINE_Z)
	var near: Vector3 = _release(4.0, 15.0)
	var away: Vector3 = _release(4.0, 15.0, far)
	for level: int in LEVELS:
		assert_almost_eq(AITipField.odds(away, far, _tip(away, 3.5, far), level),
				AITipField.odds(near, NET, _tip(near, 3.5), level), 1e-6)


func test_between_spots_it_reads_between_them() -> void:
	var a: Vector3 = _release(0.0, 15.0)
	var b: Vector3 = _release(4.0, 15.0)
	var mid: Vector3 = _release(2.0, 15.0)
	for level: int in LEVELS:
		var lo: float = minf(AITipField.odds(a, NET, _tip(a, 2.5), level),
				AITipField.odds(b, NET, _tip(b, 2.5), level))
		var hi: float = maxf(AITipField.odds(a, NET, _tip(a, 2.5), level),
				AITipField.odds(b, NET, _tip(b, 2.5), level))
		var v: float = AITipField.odds(mid, NET, _tip(mid, 2.5), level)
		assert_between(v, lo - 1e-6, hi + 1e-6)


func test_the_best_level_scores_at_least_as_often_as_any() -> void:
	for x: float in [-6.0, 0.0, 3.0]:
		for fwd: float in [8.0, 12.0, 18.0]:
			var r: Vector3 = _release(x, fwd)
			var t: Vector3 = _tip(r, 3.0)
			var best: float = AITipField.best_odds(r, NET, t)
			assert_eq(best, AITipField.odds(r, NET, t, AITipField.best_level(r, NET, t)))
			for level: int in LEVELS:
				assert_true(AITipField.odds(r, NET, t, level) <= best + 1e-6)
			assert_between(best, 0.0, 1.0)


func test_a_tipper_the_generator_left_out_reads_the_nearest_measured() -> void:
	# From 6 m out, a tipper 5 m out stands within a metre of the shooter: not
	# measured, so the 3.5 m row stands in.
	var r: Vector3 = _release(-4.0, 6.0)
	for level: int in LEVELS:
		assert_true(is_nan(_row_odds(-4.0, 6.0, 5.0, level)), "not measured")
		assert_almost_eq(AITipField.odds(r, NET, _tip(r, 5.0), level),
				_row_odds(-4.0, 6.0, 3.5, level), 1e-5)
