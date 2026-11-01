extends GutTest

# A glove on the stick holds it like a sword (SkaterArmPoses.glove_basis): the
# shaft runs across the palm at the grip's angle to the hand's long axis and
# leaves past the thumb toward the blade, and the wrist deviates within its
# range to keep it there — toward the thumb (radial) to open the angle, toward
# the little finger (ulnar) to close it. Past the range the shaft slips off the
# diagonal instead. A glove off the stick lines up with its forearm.
#
# The fist's long axis is local −Y (wrist → fingers), its knuckle roll local X
# with +X the thumb's side.

const GRIP: float = deg_to_rad(65.0)
const ULNAR: float = deg_to_rad(35.0)
const RADIAL: float = deg_to_rad(20.0)


func _hand_axis(b: Basis) -> Vector3:
	return -b.y.normalized()


func _basis(forearm: Vector3, shaft: Vector3) -> Basis:
	return SkaterArmPoses.glove_basis(forearm, shaft, GRIP, ULNAR, RADIAL)


# A shaft `deg` off the forearm, toward the blade, in the forearm's XY plane.
func _shaft_off(deg: float) -> Vector3:
	return Vector3(sin(deg_to_rad(deg)), -cos(deg_to_rad(deg)), 0.0)


func test_off_the_stick_the_fist_follows_the_forearm() -> void:
	var forearm := Vector3(0.3, -0.8, 0.5).normalized()
	var b: Basis = _basis(forearm, Vector3.ZERO)
	assert_almost_eq(_hand_axis(b).angle_to(forearm), 0.0, 0.0001)


func test_at_the_grip_angle_the_wrist_is_straight() -> void:
	var forearm := Vector3(0.0, -1.0, 0.0)
	var b: Basis = _basis(forearm, _shaft_off(65.0))
	assert_almost_eq(_hand_axis(b).angle_to(forearm), 0.0, 0.0001)


func test_within_its_range_the_wrist_keeps_the_shaft_on_the_grip() -> void:
	var forearm := Vector3(0.0, -1.0, 0.0)
	for deg: float in [35.0, 50.0, 65.0, 75.0, 84.0]:
		var shaft: Vector3 = _shaft_off(deg)
		var b: Basis = _basis(forearm, shaft)
		assert_almost_eq(rad_to_deg(_hand_axis(b).angle_to(shaft)), 65.0, 0.01,
				"a shaft %.0f° off the forearm lies on the grip" % deg)
		assert_almost_eq(rad_to_deg(_hand_axis(b).angle_to(forearm)), absf(deg - 65.0), 0.01,
				"by deviating the wrist %.0f°" % absf(deg - 65.0))


func test_past_its_range_the_wrist_stops_and_the_shaft_slips() -> void:
	var forearm := Vector3(0.0, -1.0, 0.0)
	for deg: float in [5.0, 20.0, 100.0, 140.0]:
		var b: Basis = _basis(forearm, _shaft_off(deg))
		var limit: float = 35.0 if deg < 65.0 else 20.0
		assert_almost_eq(rad_to_deg(_hand_axis(b).angle_to(forearm)), limit, 0.01,
				"a shaft %.0f° off the forearm deviates the wrist to its limit" % deg)


func test_the_shaft_leaves_past_the_thumb_toward_the_blade() -> void:
	for f: Vector3 in [Vector3(0.0, -1.0, 0.0), Vector3(0.2, -0.9, 0.3).normalized()]:
		for shaft: Vector3 in [_shaft_off(40.0), _shaft_off(80.0),
				Vector3(0.6, -0.7, 0.2).normalized(), Vector3(-0.3, -0.5, 0.8).normalized()]:
			var b: Basis = _basis(f, shaft)
			assert_gt(b.x.normalized().dot(shaft), 0.0, "the thumb's side is the blade's")
			var flipped: Basis = _basis(f, -shaft)
			assert_lt(flipped.x.normalized().dot(shaft), 0.0, "and turns with it")


func test_the_hand_is_a_proper_frame_with_the_shaft_across_its_palm() -> void:
	var forearm := Vector3(0.2, -0.9, 0.3).normalized()
	var shaft := Vector3(0.6, -0.7, 0.2).normalized()
	var b: Basis = _basis(forearm, shaft)
	assert_gt(b.determinant(), 0.0, "never mirrored")
	assert_almost_eq(b.x.normalized().dot(_hand_axis(b)), 0.0, 0.0001,
			"the knuckle roll is square to the hand")
	assert_almost_eq(b.z.normalized().dot(shaft), 0.0, 0.0001,
			"the shaft lies in the knuckle roll's plane with the hand")


# The wrist's flexion rolls the fist round the shaft (SkaterArmPoses.grip_roll):
# none while the forearm's twist is in its range, else as far as brings it there,
# never past the flexion, and the shaft stays across the palm at the grip.
const TWIST_MAX: float = deg_to_rad(80.0)
const FLEX_MAX: float = deg_to_rad(70.0)


func _roll(forearm: Vector3, shaft: Vector3, neutral: Vector3) -> float:
	return SkaterArmPoses.grip_roll(forearm, shaft, GRIP, ULNAR, RADIAL, neutral, TWIST_MAX,
			FLEX_MAX)


func test_a_forearm_in_its_range_leaves_the_fist_unrolled() -> void:
	var forearm := Vector3(0.0, -1.0, 0.0)
	var shaft: Vector3 = _shaft_off(65.0)
	var thumb: Vector3 = _basis(forearm, shaft).x
	assert_eq(_roll(forearm, shaft, thumb), 0.0, "the forearm untwisted")
	assert_eq(_roll(forearm, shaft, thumb.rotated(forearm, deg_to_rad(60.0))), 0.0,
			"twisted inside its range")


func test_a_twisted_forearm_rolls_the_fist_back_into_its_range() -> void:
	var forearm := Vector3(0.0, -1.0, 0.0)
	var shaft: Vector3 = _shaft_off(65.0)
	var thumb: Vector3 = _basis(forearm, shaft).x
	for twist_deg: float in [100.0, 130.0, 170.0]:
		var neutral: Vector3 = thumb.rotated(forearm, deg_to_rad(twist_deg))
		var roll: float = _roll(forearm, shaft, neutral)
		var b: Basis = SkaterArmPoses.glove_basis(forearm, shaft, GRIP, ULNAR, RADIAL, roll)
		var after: float = SkaterArmPoses.forearm_twist(forearm, b.x, neutral)
		assert_lt(after, deg_to_rad(twist_deg) - 0.01, "%.0f°: it untwists" % twist_deg)
		assert_gte(after, TWIST_MAX - 0.01, "%.0f°: and no further than its range" % twist_deg)
		var flex: float = asin(absf(_hand_axis(b).dot(forearm.cross(shaft).normalized())))
		assert_lte(flex, FLEX_MAX + 0.001, "%.0f°: within the wrist's flexion" % twist_deg)
		assert_almost_eq(_hand_axis(b).angle_to(shaft), _hand_axis(_basis(forearm, shaft))
				.angle_to(shaft), 0.0001, "%.0f°: the shaft still across the palm" % twist_deg)


func test_a_fist_given_its_way_never_rolls_the_other() -> void:
	var forearm := Vector3(0.0, -1.0, 0.0)
	var shaft: Vector3 = _shaft_off(65.0)
	var thumb: Vector3 = _basis(forearm, shaft).x
	for twist_deg: float in [100.0, 150.0, 179.0, -179.0, -150.0, -100.0]:
		var neutral: Vector3 = thumb.rotated(forearm, deg_to_rad(twist_deg))
		for way: float in [1.0, -1.0]:
			var roll: float = SkaterArmPoses.grip_roll(forearm, shaft, GRIP, ULNAR, RADIAL,
					neutral, TWIST_MAX, FLEX_MAX, way)
			assert_true(roll * way >= 0.0, "%.0f°, way %+.0f: rolled %+.1f°" % [
					twist_deg, way, rad_to_deg(roll)])
