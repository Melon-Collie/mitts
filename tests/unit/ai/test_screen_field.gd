extends GutTest

# AIScreenField reads the generated screen field (properties of the reader; the
# numbers are the goalie's, held to him by test_screen_field_is_current.gd).

const NET := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z)
var _cfg := GoalieScreenRules.ScreenConfig.new()


func _keeper() -> Vector3:
	return NET + Vector3(0.0, 0.0, 0.6)


func test_a_body_on_the_line_screens_a_slot_shot_and_one_off_it_does_not() -> void:
	var release := Vector3(0.0, 0.0, NET.z + 9.5)
	var along: float = AIScreenField.best_station_along(release, NET)
	assert_true(is_finite(along), "a screen was measured worth something from the slot's top")
	var on_line := Vector3(0.0, 0.0, NET.z + along)
	assert_gt(AIScreenField.uplift(release, NET, _keeper(), on_line, _cfg), 0.0)
	var off := Vector3(1.5, 0.0, NET.z + along)
	assert_eq(AIScreenField.uplift(release, NET, _keeper(), off, _cfg), 0.0,
			"a body that hides nothing screens nothing")


func test_nothing_behind_the_keeper_or_beyond_the_shooter_screens() -> void:
	var release := Vector3(0.0, 0.0, NET.z + 9.5)
	assert_eq(AIScreenField.uplift(release, NET, _keeper(), NET + Vector3(0.0, 0.0, 0.2), _cfg),
			0.0, "behind him")
	assert_eq(AIScreenField.uplift(release, NET, _keeper(), release + Vector3(0.0, 0.0, 1.0),
			_cfg), 0.0, "behind the shooter")


func test_the_best_of_several_bodies_counts_once() -> void:
	var release := Vector3(0.0, 0.0, NET.z + 9.5)
	var along: float = AIScreenField.best_station_along(release, NET)
	var one := Vector3(0.0, 0.0, NET.z + along)
	var single: float = AIScreenField.uplift(release, NET, _keeper(), one, _cfg)
	var two: Array[Vector3] = [one, one + Vector3(0.0, 0.0, 0.5)]
	assert_almost_eq(AIScreenField.best_uplift(release, NET, _keeper(), two, _cfg), single, 1e-6)


# A body on the release is the shooter's, not a screen: the keeper's own test
# (GoalieScreenRules' min_along) sees past it, from every spot.
func test_a_body_on_the_release_is_no_screen() -> void:
	for out: float in [3.0, 4.0, 5.5]:
		var release := Vector3(0.0, 0.0, NET.z + out)
		var body: Vector3 = release + Vector3(0.0, 0.0, -0.5)
		assert_eq(AIScreenField.uplift(release, NET, _keeper(), body, _cfg), 0.0,
				"%.1f m out" % out)


# Read between the measured spots, the screen moves with the release: a
# release half a centimetre either side of the boundary between two spots
# reads within a hair of the same.
func test_the_screen_does_not_snap_between_spots() -> void:
	var mid_out: float = 0.5 * (AIScreenFieldData.SPOT_FWD[0] + AIScreenFieldData.SPOT_FWD[1])
	var a := Vector3(0.0, 0.0, NET.z + mid_out - 0.005)
	var b := Vector3(0.0, 0.0, NET.z + mid_out + 0.005)
	assert_almost_eq(AIScreenField.best_station_along(a, NET),
			AIScreenField.best_station_along(b, NET), 0.01)
	var body := Vector3(0.0, 0.0, NET.z + 3.5)
	assert_almost_eq(AIScreenField.uplift(a, NET, _keeper(), body, _cfg),
			AIScreenField.uplift(b, NET, _keeper(), body, _cfg), 0.01)


# The fit gives back the measured screened goals at every level of each of its
# factors (how far out the release is, how far out the body stands): the
# fixed point iterative proportional fitting converges to.
func test_the_fit_scores_what_was_measured_at_each_level() -> void:
	AIScreenField.uplift(Vector3(0.0, 0.0, NET.z + 9.5), NET, _keeper(), NET, _cfg)
	var xs: Array[float] = AIScreenFieldData.SPOT_X
	var alongs: Array[float] = AIScreenFieldData.STATION_ALONG_M
	var by_out_measured: Dictionary = {}
	var by_out_fitted: Dictionary = {}
	var by_along_measured: Dictionary = {}
	var by_along_fitted: Dictionary = {}
	for r: String in AIScreenFieldData.ROWS:
		var f: PackedStringArray = r.split("\t")
		if float(f[3]) < 0.0 or absf(float(f[4])) > 0.01:
			continue
		var o: int = AIScreenFieldData.SPOT_FWD.find(float(f[2]))
		var a: int = alongs.find(float(f[3]))
		var spot: int = o * xs.size() + xs.find(float(f[1]))
		var fitted: float = AIScreenField._station[spot * alongs.size() + a] * float(f[6])
		by_out_measured[o] = by_out_measured.get(o, 0.0) + float(f[5])
		by_out_fitted[o] = by_out_fitted.get(o, 0.0) + fitted
		by_along_measured[a] = by_along_measured.get(a, 0.0) + float(f[5])
		by_along_fitted[a] = by_along_fitted.get(a, 0.0) + fitted
	for o: int in by_out_measured:
		assert_almost_eq(by_out_fitted[o], by_out_measured[o], 0.05, "%.1f m out" % AIScreenFieldData.SPOT_FWD[o])
	for a: int in by_along_measured:
		assert_almost_eq(by_along_fitted[a], by_along_measured[a], 0.05, "the body %.1f m out" % alongs[a])
