extends GutTest

# TwoBoneIK.solve_elbow_clear: of the elbows the arm allows, the one nearest the
# pole's that keeps the arm out of the trunk, sliding along the edge of what is
# clear as the hand moves.

const UPPER: float = 0.33
const FORE: float = 0.33
# A trunk 0.46 m wide and 0.39 m deep about the origin, from the belt up to the
# shoulders, in its own unscaled frame.
const KEEP_OUT := Vector4(0.23, 0.195, -0.2, 0.22)
const ROOT_SHARE: float = 0.5
# The bottom arm's shoulder on the left of the chest, its pole down and out.
const SHOULDER := Vector3(-0.22, 0.2, 0.0)
const POLE := Vector3(-0.55, -1.0, 0.1)


func _solve(hand: Vector3, trunk: Transform3D = Transform3D.IDENTITY) -> Vector3:
	return TwoBoneIK.solve_elbow_clear(trunk * SHOULDER, trunk * hand, UPPER, FORE,
			trunk.basis * POLE, trunk, KEEP_OUT, ROOT_SHARE)


func _intrusion(elbow: Vector3, hand: Vector3) -> float:
	return TwoBoneIK._arm_intrusion(SHOULDER, elbow, hand, KEEP_OUT, ROOT_SHARE)


func test_an_elbow_already_clear_is_the_poles() -> void:
	var hand := Vector3(-0.35, -0.2, -0.25)
	var plain: Vector3 = TwoBoneIK.solve_elbow(SHOULDER, hand, UPPER, FORE, POLE)
	assert_eq(_intrusion(plain, hand), 0.0, "out beside the body the pole's elbow is clear")
	assert_eq(_solve(hand), plain)


# The bottom hand on the stick across the front of the belly: the pole puts the
# elbow back into it, and the solve brings it out in front.
func test_an_arm_across_the_front_comes_out_of_the_belly() -> void:
	var hand := Vector3(0.12, -0.15, -0.35)
	var plain: Vector3 = TwoBoneIK.solve_elbow(SHOULDER, hand, UPPER, FORE, POLE)
	assert_gt(_intrusion(plain, hand), 0.05, "the pole's elbow runs the arm into the trunk")
	var elbow: Vector3 = _solve(hand)
	assert_eq(_intrusion(elbow, hand), 0.0, "the solved one does not")
	assert_almost_eq(elbow.distance_to(SHOULDER), UPPER, 0.001, "the upper arm keeps its length")
	assert_almost_eq(elbow.distance_to(hand), FORE, 0.001, "the forearm keeps its length")


func test_the_elbow_slides_as_the_hand_moves() -> void:
	var prev := Vector3.INF
	for i: int in 121:
		var t: float = float(i) / 120.0
		var hand := Vector3(lerpf(-0.4, 0.25, t), lerpf(-0.25, -0.1, t), lerpf(-0.2, -0.32, t))
		var elbow: Vector3 = _solve(hand)
		if prev != Vector3.INF:
			# The hand moves ~6 mm a step; an elbow stepping between samples
			# of its circle would move several centimetres.
			assert_lt(elbow.distance_to(prev), 0.03, "at step %d" % i)
		prev = elbow


func test_the_trunk_is_read_in_its_own_frame() -> void:
	var trunk := Transform3D(Basis(Vector3.UP, 0.7), Vector3(0.4, 1.2, -0.3))
	var hand := Vector3(0.12, -0.15, -0.35)
	assert_almost_eq(_solve(hand, trunk), trunk * _solve(hand), Vector3.ONE * 0.002)
