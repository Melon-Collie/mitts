extends GutTest

# GoaliePassRead: the first opposing stick a loose puck's line reaches.

const REACH: float = 1.5
const MAX_T: float = 1.0

var _out := GoaliePassRead.Reception.new()


func _find(puck: Vector3, vel: Vector3, receivers: Array[Vector3]) -> bool:
	return GoaliePassRead.find_reception(puck, vel,
			PackedVector3Array(receivers), REACH, MAX_T, _out)


func test_a_pass_straight_at_a_stick_is_received_a_reach_short_of_him() -> void:
	assert_true(_find(Vector3.ZERO, Vector3(0, 0, 10), [Vector3(0, 0, 5)]))
	assert_almost_eq(_out.point.z, 5.0 - REACH, 0.001,
			"he can play it as soon as it is inside his stick")
	assert_almost_eq(_out.time, (5.0 - REACH) / 10.0, 0.001)


func test_a_stick_off_the_line_but_within_reach_still_receives() -> void:
	assert_true(_find(Vector3.ZERO, Vector3(0, 0, 10), [Vector3(1.0, 0, 5)]))
	assert_lt(_out.point.z, 5.0, "enters the reach circle before the closest approach")
	assert_almost_eq(_out.point.x, 0.0, 0.001, "the reception is ON the puck's line")


func test_a_line_that_misses_every_stick_is_not_a_pass() -> void:
	assert_false(_find(Vector3.ZERO, Vector3(0, 0, 10), [Vector3(REACH + 0.1, 0, 5)]))
	assert_true(is_inf(_out.time))


func test_a_skater_behind_the_puck_does_not_receive_it() -> void:
	assert_false(_find(Vector3.ZERO, Vector3(0, 0, 10), [Vector3(0, 0, -3)]),
			"the pass is leaving him")


func test_the_first_stick_on_the_line_wins() -> void:
	assert_true(_find(Vector3.ZERO, Vector3(0, 0, 10),
			[Vector3(0, 0, 8), Vector3(0.5, 0, 4)]))
	assert_lt(_out.point.z, 4.0, "the nearer stick intercepts before the farther one")


func test_a_reception_past_the_horizon_is_ignored() -> void:
	assert_false(_find(Vector3.ZERO, Vector3(0, 0, 2), [Vector3(0, 0, 10)]),
			"4.25 s away is not a read he is making yet")


func test_a_stopped_puck_is_not_a_pass() -> void:
	assert_false(_find(Vector3.ZERO, Vector3.ZERO, [Vector3(0, 0, 1)]))


func test_the_reception_names_its_stick_and_when_the_puck_passes_it() -> void:
	assert_true(_find(Vector3.ZERO, Vector3(0, 0, 10),
			[Vector3(5, 0, 0), Vector3(0.5, 0, 6)]))
	assert_eq(_out.receiver, 1, "index into the receivers it was given")
	assert_almost_eq(_out.pass_time, 0.6, 0.001, "closest approach to the blade")
	assert_lt(_out.time, _out.pass_time, "he can play it before it reaches him")


func test_a_miss_names_no_stick() -> void:
	assert_false(_find(Vector3.ZERO, Vector3(0, 0, 10), [Vector3(REACH + 0.1, 0, 5)]))
	assert_eq(_out.receiver, -1)
	assert_true(is_inf(_out.pass_time))


func test_he_waits_on_a_stick_only_while_the_answer_still_lands_after_it() -> void:
	assert_true(GoaliePassRead.can_wait_out(0.45, 0.20, 0.20),
			"a stick in the slot leaves the drop its time")
	assert_false(GoaliePassRead.can_wait_out(0.45, 0.35, 0.20),
			"a net-front stick does not: the shot through it is played as a shot")
