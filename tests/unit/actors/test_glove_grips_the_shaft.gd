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
