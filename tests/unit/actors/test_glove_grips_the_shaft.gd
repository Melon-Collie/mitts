extends GutTest

# A glove on the stick holds it across the knuckle roll and turns the hand
# square across the shaft, bending at the wrist within the wrist's range;
# a glove off the stick lines up with its forearm (SkaterArmPoses.glove_basis).
# The fist's long axis is local −Y (wrist → fingers), its knuckle roll local X.

const MAX_BEND: float = deg_to_rad(25.0)


func _hand_axis(b: Basis) -> Vector3:
	return -b.y.normalized()


func test_off_the_stick_the_fist_follows_the_forearm() -> void:
	var forearm := Vector3(0.3, -0.8, 0.5).normalized()
	var b: Basis = SkaterArmPoses.glove_basis(forearm, Vector3.ZERO, MAX_BEND)
	assert_almost_eq(_hand_axis(b).angle_to(forearm), 0.0, 0.0001)


func test_a_shaft_across_the_forearm_needs_no_bend() -> void:
	var forearm := Vector3(0.0, -1.0, 0.0)
	var shaft := Vector3(1.0, 0.0, 0.0)
	var b: Basis = SkaterArmPoses.glove_basis(forearm, shaft, MAX_BEND)
	assert_almost_eq(_hand_axis(b).angle_to(forearm), 0.0, 0.0001)
	assert_almost_eq(absf(b.x.normalized().dot(shaft)), 1.0, 0.0001,
			"the knuckle roll lies along the shaft")


func test_the_wrist_breaks_toward_square_within_its_range() -> void:
	var forearm := Vector3(0.0, -1.0, 0.0)
	for deg: float in [5.0, 15.0, 40.0, 70.0]:
		# A shaft tipped `deg` off square to the forearm.
		var shaft := Vector3(cos(deg_to_rad(deg)), -sin(deg_to_rad(deg)), 0.0)
		var b: Basis = SkaterArmPoses.glove_basis(forearm, shaft, MAX_BEND)
		var hand: Vector3 = _hand_axis(b)
		var bend: float = hand.angle_to(forearm)
		assert_almost_eq(bend, minf(deg_to_rad(deg), MAX_BEND), 0.0001,
				"%.0f° off square bends the wrist by as much, up to its range" % deg)
		assert_almost_eq(rad_to_deg(hand.angle_to(shaft)), 90.0 - deg + rad_to_deg(bend), 0.01,
				"toward square across the shaft")
		assert_almost_eq(b.x.normalized().dot(hand), 0.0, 0.0001)
		assert_gt(b.determinant(), 0.0, "never mirrored")


func test_which_end_of_the_shaft_is_up_does_not_matter() -> void:
	var forearm := Vector3(0.2, -0.9, 0.3).normalized()
	var shaft := Vector3(0.6, -0.7, 0.2).normalized()
	var a: Basis = SkaterArmPoses.glove_basis(forearm, shaft, MAX_BEND)
	var b: Basis = SkaterArmPoses.glove_basis(forearm, -shaft, MAX_BEND)
	for axis: int in 3:
		assert_almost_eq((a[axis] - b[axis]).length(), 0.0, 0.0001)
