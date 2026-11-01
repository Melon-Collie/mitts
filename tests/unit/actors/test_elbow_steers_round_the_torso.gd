extends GutTest

# SkaterArmPoses.steer_turn and turned_elbow: the elbow keeps the pole's bend where that clears
# the torso, turns outward round the shoulder→hand line only as far as it must
# where it does not, and moves continuously as the hand does. The torso sits at
# the identity, so its frame is the joints'.

const UPPER: float = 0.33
const FOREARM: float = 0.33
# The bottom (left) shoulder of the default skater, in the torso's frame.
const SHOULDER := Vector3(-0.21, 0.16, -0.02)
const POLE := Vector3(-0.55, -1.0, 0.1)
const OUTWARD := Vector3(-1.0, 0.0, 0.0)


func _steer(hand: Vector3) -> Vector3:
	return SkaterArmPoses.turned_elbow(SHOULDER, hand, UPPER, FOREARM, POLE,
			SkaterArmPoses.steer_turn(SHOULDER, hand, UPPER, FOREARM, POLE, OUTWARD,
			Transform3D.IDENTITY))


func _sunk(shoulder: Vector3, elbow: Vector3, hand: Vector3) -> float:
	var worst: float = 0.0
	for p: Vector3 in [elbow, (shoulder + elbow) * 0.5, elbow.lerp(hand, 0.4)]:
		worst = maxf(worst, SkaterMeshBuilder.SLEEVE_RADIUS_M - SkaterArmPoses.STEER_CONTACT_M
				- SkaterMeshBuilder.torso_clearance(p))
	return worst


func test_a_clear_elbow_keeps_the_poles_bend() -> void:
	# A hand hanging out at the side: the pole's elbow is beside the body.
	var hand := Vector3(-0.45, -0.25, -0.15)
	var plain: Vector3 = TwoBoneIK.solve_elbow(SHOULDER, hand, UPPER, FOREARM, POLE)
	assert_eq(_sunk(SHOULDER, plain, hand), 0.0, "the case is one the pole clears")
	assert_almost_eq((_steer(hand) - plain).length(), 0.0, 0.0001)


func test_an_elbow_the_pole_sinks_into_the_chest_turns_out_of_it() -> void:
	# A hand drawn in across the belly: the pole drops the elbow into the chest.
	var hand := Vector3(-0.02, -0.12, -0.36)
	var plain: Vector3 = TwoBoneIK.solve_elbow(SHOULDER, hand, UPPER, FOREARM, POLE)
	assert_gt(_sunk(SHOULDER, plain, hand), 0.02, "the pole's elbow is in the chest")
	var elbow: Vector3 = _steer(hand)
	assert_lt(_sunk(SHOULDER, elbow, hand), 0.001, "the steered one is out of it")
	assert_almost_eq(SHOULDER.distance_to(elbow), UPPER, 0.0005, "the upper arm keeps its length")
	assert_almost_eq(elbow.distance_to(hand), FOREARM, 0.0005, "the forearm keeps its length")


func test_the_elbow_moves_with_the_hand_without_a_jump() -> void:
	# The hand swept from the side across the belly and out in front: the steer
	# engages and lets go along the way, and no millimetre of hand moves the
	# elbow more than a few.
	var prev: Vector3 = _steer(Vector3(-0.45, -0.25, -0.15))
	var steps: int = 400
	for i: int in range(1, steps + 1):
		var t: float = float(i) / float(steps)
		var hand: Vector3 = Vector3(-0.45, -0.25, -0.15).lerp(Vector3(0.05, -0.15, -0.36), t)
		var elbow: Vector3 = _steer(hand)
		assert_lt(elbow.distance_to(prev), 0.006, "step %d" % i)
		prev = elbow
