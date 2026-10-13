extends GutTest

# AIPinThreatRead: when a committed checker reaches a carrier on the boards,
# and how long the carrier takes to get out of his line along them.


func test_contact_time_is_the_gap_over_the_closing_speed() -> void:
	var me := Vector3(10.0, 0.0, 0.0)
	var t: float = AIPinThreatRead.time_to_contact(me, Vector3.ZERO,
			Vector3(8.0, 0.0, 0.0), Vector3(4.0, 0.0, 0.0))
	assert_almost_eq(t, (2.0 - AIPinThreatRead.TOUCHING_M) / 4.0, 1e-5)
	assert_eq(AIPinThreatRead.time_to_contact(me, Vector3.ZERO, Vector3(9.5, 0.0, 0.0),
			Vector3.ZERO), 0.0, "already touching")
	assert_eq(AIPinThreatRead.time_to_contact(me, Vector3(4.0, 0.0, 0.0),
			Vector3(8.0, 0.0, 0.0), Vector3(4.0, 0.0, 0.0)), INF, "matched, not closing")


func test_past_the_escape_offset_his_hit_is_no_longer_square() -> void:
	var along: float = AIPinThreatRead.escape_along_m()
	var into_wall: float = sqrt(AIPinThreatRead.TOUCHING_M * AIPinThreatRead.TOUCHING_M
			- along * along) / AIPinThreatRead.TOUCHING_M
	assert_almost_eq(into_wall, BoardPinRules.BACKSTOP_MIN_INTO_WALL, 1e-5)


func test_escape_from_rest_is_the_offset_under_full_acceleration() -> void:
	var need: float = AIPinThreatRead.escape_along_m()
	assert_almost_eq(AIPinThreatRead.escape_time(0.0, 0.0, 10.0, 1.0), sqrt(2.0 * need / 10.0),
			1e-5)
	assert_lt(AIPinThreatRead.escape_time(0.0, 3.0, 10.0, 1.0),
			AIPinThreatRead.escape_time(0.0, 0.0, 10.0, 1.0), "already moving that way")
	assert_eq(AIPinThreatRead.escape_time(need + 0.1, 0.0, 10.0, 1.0), 0.0, "already out")


func test_escape_goes_the_way_he_is_moving_else_the_side_he_is_on() -> void:
	assert_eq(AIPinThreatRead.escape_sign(0.2, -2.0), -1.0)
	assert_eq(AIPinThreatRead.escape_sign(-0.2, 0.0), -1.0)
	assert_eq(AIPinThreatRead.escape_sign(0.0, 0.0), 1.0)


func test_escape_wins_only_when_it_beats_the_contact() -> void:
	assert_eq(AIPinThreatRead.answer(0.4, 0.3), AIPinThreatRead.Answer.ESCAPE)
	assert_eq(AIPinThreatRead.answer(0.2, 0.3), AIPinThreatRead.Answer.BRACE)
