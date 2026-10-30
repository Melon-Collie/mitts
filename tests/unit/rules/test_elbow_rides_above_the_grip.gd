extends GutTest

# TwoBoneIK.grip_lean / bend_for_grip: a hand on a shaft takes it like a sword, so the elbow
# rides on the knob's side of the hand — a stick held upright in tight puts the
# elbow up and out, never under the fist.

const UPPER: float = 0.33
const FORE: float = 0.33
const MIN_COS: float = 0.25
# The top shoulder on the right, its pole down and out.
const SHOULDER := Vector3(0.22, 0.4, 0.0)
const POLE := Vector3(0.55, -1.0, 0.1)
const DOWN_THE_SHAFT := Vector3(0.0, -1.0, 0.0)


func _elbow(hand: Vector3, grip: Vector3) -> Vector3:
	var share: float = TwoBoneIK.grip_lean(SHOULDER, hand, UPPER, FORE, POLE, grip, MIN_COS)
	var bend: Vector3 = TwoBoneIK.bend_for_grip(SHOULDER, hand, POLE, grip, Vector3.RIGHT, share)
	return TwoBoneIK.solve_elbow(SHOULDER, hand, UPPER, FORE, bend)


func _forearm_cos(hand: Vector3, grip: Vector3) -> float:
	return (hand - _elbow(hand, grip)).normalized().dot(grip)


# In tight: the hand out in front of the chest, the shaft standing straight down.
func test_a_stick_held_upright_lifts_the_elbow_over_the_fist() -> void:
	var hand := Vector3(0.2, 0.3, -0.2)
	var hanging: Vector3 = TwoBoneIK.solve_elbow(SHOULDER, hand, UPPER, FORE, POLE)
	assert_lt((hand - hanging).normalized().dot(DOWN_THE_SHAFT), 0.0,
			"the pole alone hangs the elbow under the fist")
	assert_gt(_forearm_cos(hand, DOWN_THE_SHAFT), 0.0,
			"the forearm comes in level or from above")
	assert_gt(_elbow(hand, DOWN_THE_SHAFT).x, hand.x, "and out, on the pole's side")


func test_an_elbow_already_over_the_shaft_is_the_poles() -> void:
	var hand := Vector3(0.25, -0.1, -0.45)
	var shaft := Vector3(0.0, -0.6, -0.8)
	var plain: Vector3 = TwoBoneIK.solve_elbow(SHOULDER, hand, UPPER, FORE, POLE)
	assert_gt((hand - plain).normalized().dot(shaft), MIN_COS, "a carry's elbow is fine as it is")
	assert_almost_eq(_elbow(hand, shaft), plain, Vector3.ONE * 0.0001)


# Pulled in, the hand rises: the stick held upright from a hand out in front.
func test_the_elbow_rises_as_the_hand_does() -> void:
	var prev := Vector3.INF
	for i: int in 61:
		var hand := Vector3(0.2, lerpf(-0.1, 0.3, float(i) / 60.0), -0.25)
		var elbow: Vector3 = _elbow(hand, DOWN_THE_SHAFT)
		if prev != Vector3.INF:
			assert_lt(elbow.distance_to(prev), 0.03, "at step %d" % i)
		prev = elbow


func test_the_elbow_moves_smoothly_as_the_shaft_stands_up() -> void:
	var hand := Vector3(0.2, 0.2, -0.25)
	var prev := Vector3.INF
	for i: int in 91:
		var a: float = deg_to_rad(float(i))
		var shaft := Vector3(0.0, -sin(a), -cos(a))
		var elbow: Vector3 = _elbow(hand, shaft)
		if prev != Vector3.INF:
			assert_lt(elbow.distance_to(prev), 0.02, "at %d°" % i)
		prev = elbow
