extends GutTest

# GoalieTipDepth.tip_cap — r · sin θ <= cover, for a stick he cannot react to.

const COVER: float = 0.84
const MAX_TIP: float = 4.3
const PACE: float = 33.0
const SHOOTER := Vector3(-5.0, 0.0, 16.0)


func _cap(tipper: Vector3, defender_arrival: float = INF) -> float:
	return GoalieTipDepth.tip_cap(SHOOTER, tipper, 0.0, 0.0, 1, COVER, MAX_TIP,
			PACE, defender_arrival)


func test_a_stick_off_the_shooters_line_pulls_him_in() -> void:
	var tipper := Vector3(2.5, 0.0, 3.0)
	var sin_theta: float = absf(SHOOTER.normalized().cross(tipper.normalized()).y)
	assert_almost_eq(_cap(tipper), COVER / sin_theta, 0.001)
	assert_lt(_cap(tipper), 1.75, "binds below the challenge ceiling")


func test_a_wider_stick_pulls_him_in_further() -> void:
	assert_lt(_cap(Vector3(2.5, 0.0, 3.0)), _cap(Vector3(1.0, 0.0, 3.5)))


func test_a_stick_on_the_shooters_line_is_covered_by_challenging() -> void:
	var on_line: Vector3 = SHOOTER.normalized() * 3.0
	assert_true(is_inf(_cap(on_line)))


func test_a_stick_he_could_react_to_does_not_bind() -> void:
	assert_true(is_inf(_cap(Vector3(1.0, 0.0, 5.5))), "past the unreactable distance")


func test_his_defenceman_on_the_stick_frees_him() -> void:
	assert_true(is_inf(_cap(Vector3(2.5, 0.0, 3.0), 0.0)))
	assert_false(is_inf(_cap(Vector3(2.5, 0.0, 3.0), 5.0)), "a late defender does not")


func test_behind_the_line_or_behind_the_shooter_is_not_a_tip() -> void:
	assert_true(is_inf(_cap(Vector3(1.0, 0.0, -0.5))))
	assert_true(is_inf(GoalieTipDepth.tip_cap(Vector3(0.0, 0.0, 3.0), Vector3(2.0, 0.0, 3.0),
			0.0, 0.0, 1, COVER, MAX_TIP, PACE, INF)), "the shooter is no further out")
