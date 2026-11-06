extends GutTest

# SkaterArmPoses.swivel_bend and elbow_on_circle: of the elbows the two bone
# lengths allow, the arm takes the rest pole's where that clears the torso,
# turns out of the chest where it does not, keeps the upper arm in front of the
# shoulder's extension, moves continuously as the hand does, and holds its
# elbow when two tie. The torso sits at the identity, so its frame is the
# joints'.

const UPPER: float = 0.33
const FOREARM: float = 0.33
# The bottom (left) shoulder of the default skater, in the torso's frame.
const SHOULDER := Vector3(-0.21, 0.16, -0.02)
const POLE := Vector3(-0.55, -1.0, 0.1)
const OUTWARD := Vector3(-1.0, 0.0, 0.0)
const BACK := Vector3(0.0, 0.0, 1.0)
const NO_WRIST := Vector3(deg_to_rad(80.0), deg_to_rad(35.0), deg_to_rad(20.0))


func _bend(hand: Vector3, held: Vector3 = Vector3.ZERO, pole: Vector3 = POLE) -> Vector3:
	return SkaterArmPoses.swivel_bend(SHOULDER, hand, UPPER, FOREARM, pole, held, OUTWARD,
			BACK, Transform3D.IDENTITY, Vector3.ZERO, NO_WRIST)


func _elbow(hand: Vector3, held: Vector3 = Vector3.ZERO) -> Vector3:
	return SkaterArmPoses.elbow_on_circle(SHOULDER, hand, UPPER, FOREARM, _bend(hand, held))


func _sunk(elbow: Vector3, hand: Vector3) -> float:
	return SkaterArmPoses._arm_depth(SHOULDER, elbow, hand, Transform3D.IDENTITY, 1.0)


func test_a_clear_elbow_keeps_the_poles_bend() -> void:
	# A hand hanging out at the side: the pole's elbow is beside the body.
	var hand := Vector3(-0.45, -0.25, -0.15)
	var plain: Vector3 = TwoBoneIK.solve_elbow(SHOULDER, hand, UPPER, FOREARM, POLE)
	assert_lt(_sunk(plain, hand), 0.0, "the case is one the pole clears")
	assert_almost_eq(_elbow(hand).distance_to(plain), 0.0, 0.005)


func test_an_elbow_the_pole_sinks_into_the_chest_turns_out_of_it() -> void:
	# A hand drawn in across the belly: the pole drops the elbow into the chest.
	var hand := Vector3(0.05, -0.12, -0.36)
	var plain: Vector3 = TwoBoneIK.solve_elbow(SHOULDER, hand, UPPER, FOREARM, POLE)
	assert_gt(_sunk(plain, hand), 0.02, "the pole's elbow is in the chest")
	var elbow: Vector3 = _elbow(hand)
	assert_lt(_sunk(elbow, hand), 0.001, "the swivelled one is out of it")
	assert_almost_eq(SHOULDER.distance_to(elbow), UPPER, 0.0005, "the upper arm keeps its length")
	assert_almost_eq(elbow.distance_to(hand), FOREARM, 0.0005, "the forearm keeps its length")


func test_the_elbow_stays_in_front_of_the_shoulders_extension() -> void:
	# A hand hanging out at the side on a bent arm, the rest pole pointed straight
	# back: the pole alone would carry the elbow behind the chest, clear of the
	# jersey, further than a shoulder extends.
	var hand := SHOULDER + Vector3(-0.15, -0.37, 0.0)
	var back_pole := Vector3(0.0, 0.0, 1.0)
	var pole_elbow: Vector3 = TwoBoneIK.solve_elbow(SHOULDER, hand, UPPER, FOREARM, back_pole)
	var limit: float = sin(SkaterArmPoses.SWIVEL_EXTENSION_MAX)
	assert_gt((pole_elbow - SHOULDER).normalized().dot(BACK), limit, "the pole's is past it")
	assert_lt(_sunk(pole_elbow, hand), 0.0, "and out of the jersey")
	var elbow: Vector3 = SkaterArmPoses.elbow_on_circle(SHOULDER, hand, UPPER, FOREARM,
			_bend(hand, Vector3.ZERO, back_pole))
	assert_lt((elbow - SHOULDER).normalized().dot(BACK), limit + 0.02)


func test_the_elbow_moves_with_the_hand_without_a_jump() -> void:
	# The hand swept from the side across the belly and out in front, the bend
	# carried frame to frame: the swivel engages and lets go along the way, and
	# no millimetre of hand moves the elbow more than a few.
	var start := Vector3(-0.45, -0.25, -0.15)
	var held: Vector3 = _bend(start)
	var prev: Vector3 = SkaterArmPoses.elbow_on_circle(SHOULDER, start, UPPER, FOREARM, held)
	var steps: int = 400
	for i: int in range(1, steps + 1):
		var hand: Vector3 = start.lerp(Vector3(0.05, -0.15, -0.36), float(i) / float(steps))
		held = _bend(hand, held)
		var elbow: Vector3 = SkaterArmPoses.elbow_on_circle(SHOULDER, hand, UPPER, FOREARM, held)
		assert_lt(elbow.distance_to(prev), 0.006, "step %d" % i)
		prev = elbow


func test_a_held_elbow_stays_where_two_tie() -> void:
	# A hand straight out in front at the shoulder's height, the pole along the
	# arm: nothing but the jersey and the shoulder tells one bend from another,
	# so the cost has a wide flat floor. The held bend chooses which of the
	# coarse samples' brackets is searched, so the elbow stays within a step and
	# a half of the samples (45°) of where it was held, wherever on the floor.
	var hand := SHOULDER + Vector3(0.0, 0.0, -0.45)
	var along := Vector3(0.0, 0.0, -1.0)
	var reach: float = cos(TAU / SkaterArmPoses.SWIVEL_SAMPLES * 1.5)
	var sides: Array[Vector3] = [Vector3(-1.0, 0.3, 0.0).normalized(),
			Vector3(-0.3, -1.0, 0.0).normalized()]
	var bends: Array[Vector3] = []
	for side: Vector3 in sides:
		var bend: Vector3 = _bend(hand, side, along)
		assert_gt(bend.dot(side), reach, "held %s stays near it" % side)
		bends.append(bend)
	assert_lt(bends[0].dot(bends[1]), bends[0].dot(sides[0]), "and each held a different one")


func test_the_bend_is_square_to_the_arm() -> void:
	var hand := Vector3(0.0, -0.2, -0.3)
	var bend: Vector3 = _bend(hand)
	assert_almost_eq(bend.length(), 1.0, 0.0001)
	assert_almost_eq(bend.dot((hand - SHOULDER).normalized()), 0.0, 0.0001)


func test_a_still_arm_comes_to_rest() -> void:
	# The search re-centres on the bend it held, so a still hand must land on a
	# fixed point — or the drawn elbow creeps and the rebuild gate never rests.
	for hand: Vector3 in [Vector3(-0.45, -0.25, -0.15), Vector3(0.05, -0.12, -0.36),
			Vector3(-0.2, 0.05, -0.4), Vector3(0.1, -0.3, -0.25)]:
		var held: Vector3 = _bend(hand)
		var still: bool = false
		for _i: int in 4:
			var next: Vector3 = _bend(hand, held)
			still = next == held
			held = next
		assert_true(still, "held still at %s" % hand)
