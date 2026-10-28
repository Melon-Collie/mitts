extends GutTest

# PuckZoneTracker — on the blue line the puck is in the zone it was last in.

const BLUE: float = GameRules.BLUE_LINE_Z


func test_starts_out_of_both_zones() -> void:
	var t := PuckZoneTracker.new()
	assert_false(t.in_attacking_zone(0))
	assert_false(t.in_attacking_zone(1))


func test_puck_held_on_the_line_at_the_point_stays_in() -> void:
	var t := PuckZoneTracker.new()
	t.update(-15.0)
	assert_true(t.in_attacking_zone(0))
	t.update(-BLUE)
	assert_true(t.in_attacking_zone(0), "on the line after being in: still in")
	t.update(-3.0)
	assert_false(t.in_attacking_zone(0), "wholly out into the neutral zone")


func test_puck_carried_onto_the_line_is_not_yet_in() -> void:
	var t := PuckZoneTracker.new()
	t.update(-3.0)
	t.update(BLUE)
	assert_false(t.in_attacking_zone(1), "on the line from the neutral zone: not in")
	t.update(15.0)
	assert_true(t.in_attacking_zone(1))


func test_unknown_team_is_never_in() -> void:
	var t := PuckZoneTracker.new()
	t.update(-15.0)
	assert_false(t.in_attacking_zone(-1))
