extends GutTest

# A glove on the stick holds it across the knuckle roll, index toward the
# blade, and turns the hand square across the shaft, bending at the wrist
# within the wrist's range; a glove off the stick lines up with its forearm
# (SkaterArmPoses.glove_basis). The fist's long axis is local −Y (wrist →
# fingers), its knuckle roll local X (little finger → index).

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


# The index finger points down the shaft to the blade, whichever way the shaft
# runs: turned end for end, the hand turns half round its own long axis.
func test_the_index_points_to_the_blade() -> void:
	var forearm := Vector3(0.2, -0.9, 0.3).normalized()
	var shaft := Vector3(0.6, -0.7, 0.2).normalized()
	var a: Basis = SkaterArmPoses.glove_basis(forearm, shaft, MAX_BEND)
	var b: Basis = SkaterArmPoses.glove_basis(forearm, -shaft, MAX_BEND)
	assert_gt(a.x.dot(shaft), 0.0)
	assert_gt(b.x.dot(-shaft), 0.0)
	assert_almost_eq((a.y - b.y).length(), 0.0, 0.0001, "the same hand axis")
	assert_almost_eq((a.x + b.x).length(), 0.0, 0.0001, "the knuckle roll reversed")
	assert_almost_eq((a.z + b.z).length(), 0.0, 0.0001, "the back of the hand turned over")
