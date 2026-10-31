extends GutTest

# CarryPostureRules: the chest folds over a stick held out in front, comes up
# out of it as the blade goes round beside the skater or is pulled in tight,
# and tops up the posture's own fold rather than adding to it; a carried puck
# comes no closer in than a floor off his centre. The facing frame has −y ahead.

const FOLD: float = deg_to_rad(22.0)


func _at(bearing_deg: float, out_m: float) -> Vector2:
	var a: float = deg_to_rad(bearing_deg)
	return Vector2(sin(a), -cos(a)) * out_m


func test_a_stick_out_in_front_folds_the_chest_fully() -> void:
	for bearing: float in [0.0, 20.0, -20.0, 35.0, -35.0]:
		assert_almost_eq(CarryPostureRules.fold(_at(bearing, 1.2), 0.0, FOLD), FOLD, 0.0001,
				"%.0f° off the facing" % bearing)


func test_round_beside_or_behind_him_the_chest_stands_up() -> void:
	for bearing: float in [80.0, -80.0, 120.0, 180.0]:
		assert_eq(CarryPostureRules.fold(_at(bearing, 1.2), 0.0, FOLD), 0.0,
				"%.0f° off the facing" % bearing)


func test_pulled_in_tight_the_chest_stands_up() -> void:
	assert_eq(CarryPostureRules.fold(_at(0.0, 0.5), 0.0, FOLD), 0.0)
	assert_lt(CarryPostureRules.fold(_at(0.0, 0.75), 0.0, FOLD), FOLD)
	assert_almost_eq(CarryPostureRules.fold(_at(0.0, 1.0), 0.0, FOLD), FOLD, 0.0001)


func test_the_fold_moves_without_a_jump_as_the_blade_goes_round() -> void:
	var prev: float = CarryPostureRules.fold(_at(0.0, 1.2), 0.0, FOLD)
	for i: int in range(1, 181):
		var now: float = CarryPostureRules.fold(_at(float(i), 1.2), 0.0, FOLD)
		assert_lt(absf(now - prev), deg_to_rad(1.0), "at %d°" % i)
		assert_lte(now, prev + 0.000001, "it only comes up as the blade goes round")
		prev = now


func test_it_tops_up_a_skating_fold_and_never_adds_to_one() -> void:
	var ahead: Vector2 = _at(0.0, 1.2)
	assert_almost_eq(CarryPostureRules.fold(ahead, -deg_to_rad(16.0), FOLD), deg_to_rad(6.0),
			0.0001, "a 16° skating fold takes 6° more")
	assert_eq(CarryPostureRules.fold(ahead, -deg_to_rad(25.0), FOLD), 0.0,
			"a skating fold deeper than the carry's takes none")
	assert_almost_eq(CarryPostureRules.fold(ahead, deg_to_rad(6.0), FOLD), FOLD, 0.0001,
			"sitting back while skating backward does not take any away")


func test_the_folded_shoulder_comes_forward_and_down() -> void:
	var marker := Vector3(0.22, 0.4, 0.0)
	var folded: Vector3 = CarryPostureRules.folded_shoulder(marker, FOLD)
	assert_lt(folded.z, -0.1, "forward (−z) of the hips")
	assert_lt(folded.y, marker.y, "and lower")
	assert_almost_eq(folded.x, marker.x, 0.0001, "on its own side")
	assert_eq(CarryPostureRules.folded_shoulder(marker, 0.0), marker)


func test_a_cursor_in_close_is_held_out_along_its_bearing_from_his_centre() -> void:
	for bearing: float in [0.0, 50.0, -45.0, 120.0, 180.0]:
		for out_m: float in [0.05, 0.4, 0.79]:
			var held: Vector2 = CarryPostureRules.held_out(_at(bearing, out_m), 0.8)
			assert_almost_eq(held.length(), 0.8, 0.0001, "%.0f° %.2f m" % [bearing, out_m])
			assert_almost_eq(held.angle_to(_at(bearing, 1.0)), 0.0, 0.0001, "on its bearing")
	assert_eq(CarryPostureRules.held_out(_at(30.0, 1.2), 0.8), _at(30.0, 1.2), "out past it, untouched")
	assert_eq(CarryPostureRules.held_out(Vector2.ZERO, 0.8), Vector2(0.0, -0.8),
			"on his centre, straight ahead")
