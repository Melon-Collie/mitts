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
