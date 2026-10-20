extends GutTest

const RIM: float = 1.8
const NEAR: float = 0.3
const FAR: float = 1.8
const LOOK: float = 0.35


func _purpose(puck: Vector2, vel: Vector2 = Vector2.ZERO) -> float:
	return ReachPurposeRules.purpose(Vector2.ZERO, RIM, puck, vel, LOOK, NEAR, FAR)


func test_a_puck_inside_the_reach_is_full_purpose() -> void:
	assert_eq(_purpose(Vector2(0.0, -1.2)), 1.0)


func test_a_puck_far_off_is_none() -> void:
	assert_eq(_purpose(Vector2(0.0, -8.0)), 0.0)


func test_purpose_falls_with_distance() -> void:
	var last: float = 1.0
	for i: int in 40:
		var p: float = _purpose(Vector2(0.0, -(RIM + 0.1 * i)))
		assert_true(p <= last, "purpose rose as the puck went farther")
		last = p


# A pass on its way is reached for before it arrives; one going away is not.
func test_a_puck_coming_is_reached_for_sooner_than_one_going() -> void:
	var at := Vector2(0.0, -(RIM + 3.0))
	var coming: float = _purpose(at, Vector2(0.0, 10.0))
	var going: float = _purpose(at, Vector2(0.0, -10.0))
	assert_gt(coming, going)
	assert_eq(going, _purpose(at))


# The path is a segment: a puck that will pass by is measured at its nearest.
func test_a_puck_crossing_in_front_counts_at_its_nearest() -> void:
	var crossing: float = _purpose(Vector2(-3.0, -(RIM + 0.2)), Vector2(10.0, 0.0))
	assert_eq(crossing, 1.0)
