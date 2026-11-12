extends GutTest

# InfractionRules — offside and icing detection.

# ── Offside ──────────────────────────────────────────────────────────────────

const ZONE_EDGE: float = GameRules.BLUE_LINE_ZONE_EDGE_Z
const NEUTRAL_EDGE: float = GameRules.BLUE_LINE_NEUTRAL_EDGE_Z
const R: float = GameRules.PUCK_COLLISION_RADIUS
const BODY: float = GameRules.OFFSIDE_LINE_SLACK

func test_carrier_never_offside() -> void:
	assert_false(InfractionRules.is_offside(-10.0, 0, false, true))
	assert_false(InfractionRules.is_offside(10.0, 1, false, true))

func test_team_0_offside_when_past_blue_line_ahead_of_puck() -> void:
	# Team 0 attacks -Z.
	assert_true(InfractionRules.is_offside(-10.0, 0, false, false))

func test_not_offside_when_puck_in_zone() -> void:
	assert_false(InfractionRules.is_offside(-10.0, 0, true, false))
	assert_false(InfractionRules.is_offside(10.0, 1, true, false))

func test_team_0_not_offside_when_behind_blue_line() -> void:
	assert_false(InfractionRules.is_offside(0.0, 0, false, false))
	assert_false(InfractionRules.is_offside(10.0, 0, false, false))

func test_team_1_offside_when_past_blue_line_ahead_of_puck() -> void:
	# Team 1 attacks +Z.
	assert_true(InfractionRules.is_offside(10.0, 1, false, false))

# ── The puck's zone: the line belongs to the zone the puck is in ─────────────

func test_puck_enters_only_wholly_past_the_zone_side_edge() -> void:
	assert_false(InfractionRules.puck_in_attacking_zone(-(ZONE_EDGE + R - 0.01), 0, false),
			"a puck still touching the line has not entered")
	assert_true(InfractionRules.puck_in_attacking_zone(-(ZONE_EDGE + R + 0.01), 0, false))
	assert_false(InfractionRules.puck_in_attacking_zone(ZONE_EDGE + R - 0.01, 1, false))
	assert_true(InfractionRules.puck_in_attacking_zone(ZONE_EDGE + R + 0.01, 1, false))

func test_puck_on_the_line_stays_in_the_zone() -> void:
	# Held at the point: any part of the puck on the paint keeps it in.
	assert_true(InfractionRules.puck_in_attacking_zone(-GameRules.BLUE_LINE_Z, 0, true))
	assert_true(InfractionRules.puck_in_attacking_zone(-(NEUTRAL_EDGE - R + 0.01), 0, true))
	assert_true(InfractionRules.puck_in_attacking_zone(GameRules.BLUE_LINE_Z, 1, true))

func test_puck_leaves_only_wholly_past_the_neutral_side_edge() -> void:
	assert_false(InfractionRules.puck_in_attacking_zone(-(NEUTRAL_EDGE - R - 0.01), 0, true))
	assert_false(InfractionRules.puck_in_attacking_zone(NEUTRAL_EDGE - R - 0.01, 1, true))

func test_puck_on_the_line_from_the_neutral_zone_is_not_in() -> void:
	assert_false(InfractionRules.puck_in_attacking_zone(-GameRules.BLUE_LINE_Z, 0, false))

# ── Delayed offside / forecheck characterization ──────────────────────────────
# A non-carrier deep in the attacking zone IS offside the moment the puck
# exits, and stays so (sticky, in game_state_machine) until they tag up at the
# blue line — the real cost of an over-committed forecheck.

func test_deep_forechecker_is_offside_when_puck_breaks_out() -> void:
	assert_true(InfractionRules.is_offside(-15.0, 0, false, false),
			"a deep forechecker is offside once the puck breaks out of the zone")

# ── The skater against the line ──────────────────────────────────────────────
# Both skates must be wholly past the zone-side edge; the body's trailing edge
# stands in for the trailing skate.

func test_body_touching_the_zone_side_edge_is_onside() -> void:
	assert_false(InfractionRules.is_offside(-(ZONE_EDGE + BODY - 0.01), 0, false, false))
	assert_false(InfractionRules.is_offside(ZONE_EDGE + BODY - 0.01, 1, false, false))

func test_body_wholly_past_the_zone_side_edge_is_offside() -> void:
	assert_true(InfractionRules.is_offside(-(ZONE_EDGE + BODY + 0.01), 0, false, false))
	assert_true(InfractionRules.is_offside(ZONE_EDGE + BODY + 0.01, 1, false, false))

func test_tag_up_at_the_zone_side_edge() -> void:
	assert_true(InfractionRules.has_tagged_up(-(ZONE_EDGE + BODY - 0.01), 0),
			"back in contact with the line tags up")
	assert_false(InfractionRules.has_tagged_up(-(ZONE_EDGE + BODY + 0.01), 0))
	assert_true(InfractionRules.has_tagged_up(ZONE_EDGE + BODY - 0.01, 1))
	assert_false(InfractionRules.has_tagged_up(ZONE_EDGE + BODY + 0.01, 1))
	assert_true(InfractionRules.has_tagged_up(0.0, 0))
	assert_true(InfractionRules.has_tagged_up(0.0, 1))

# ── Icing ────────────────────────────────────────────────────────────────────

func test_no_icing_without_carrier() -> void:
	assert_eq(InfractionRules.check_icing(-1, 0.0, -30.0), -1)

func test_team_0_icing_from_own_half() -> void:
	# Team 0 released from own half (z > 0), puck now past -GoalLineZ
	assert_eq(InfractionRules.check_icing(0, 5.0, -30.0), 0)

func test_team_0_no_icing_from_attacking_half() -> void:
	# Team 0 released from z < 0 (already in attacking half — legal dump)
	assert_eq(InfractionRules.check_icing(0, -5.0, -30.0), -1)

func test_team_0_no_icing_short_of_goal_line() -> void:
	# Puck didn't actually reach the opponent's goal line
	assert_eq(InfractionRules.check_icing(0, 5.0, -20.0), -1)

func test_team_1_icing_from_own_half() -> void:
	# Team 1 released from own half (z < 0), puck now past +GoalLineZ
	assert_eq(InfractionRules.check_icing(1, -5.0, 30.0), 1)

func test_team_1_no_icing_from_attacking_half() -> void:
	assert_eq(InfractionRules.check_icing(1, 5.0, 30.0), -1)

func test_puck_on_the_red_line_has_gained_the_line() -> void:
	# Any part of the puck on the paint nullifies; wholly behind it does not.
	var touching: float = GameRules.THICK_LINE_WIDTH_M * 0.5 + GameRules.PUCK_COLLISION_RADIUS
	assert_eq(InfractionRules.check_icing(0, touching - 0.01, -30.0), -1)
	assert_eq(InfractionRules.check_icing(0, touching + 0.01, -30.0), 0)
	assert_eq(InfractionRules.check_icing(1, -touching + 0.01, 30.0), -1)
	assert_eq(InfractionRules.check_icing(1, -touching - 0.01, 30.0), 1)

func test_puck_must_wholly_cross_the_goal_line() -> void:
	var clear: float = GameRules.GOAL_LINE_Z + GameRules.GOAL_LINE_WIDTH_M * 0.5 + R
	assert_eq(InfractionRules.check_icing(0, 5.0, -(clear - 0.005)), -1,
			"a puck still touching the goal line's far edge has not crossed")
	assert_eq(InfractionRules.check_icing(0, 5.0, -(clear + 0.005)), 0)
	assert_eq(InfractionRules.check_icing(1, -5.0, clear - 0.005), -1)
	assert_eq(InfractionRules.check_icing(1, -5.0, clear + 0.005), 1)

# ── Hybrid icing race ─────────────────────────────────────────────────────────

func test_skater_at_the_dots_has_arrived() -> void:
	assert_eq(InfractionRules.time_to_icing_dot_line(-GameRules.ICING_FACEOFF_DOT_Z, 0.0, 0), 0.0)
	assert_eq(InfractionRules.time_to_icing_dot_line(GameRules.ICING_FACEOFF_DOT_Z + 1.0, 0.0, 1), 0.0)

func test_eta_is_full_speed_travel_for_a_skater_at_top_speed() -> void:
	var v: float = GameRules.DEFAULT_SKATER_MAX_SPEED_M_S
	assert_almost_eq(InfractionRules.time_to_icing_dot_line(
			-GameRules.ICING_FACEOFF_DOT_Z + 10.0, -v, 0), 10.0 / v, 0.0001)

func test_eta_charges_skating_the_wrong_way() -> void:
	var z: float = -GameRules.ICING_FACEOFF_DOT_Z + 6.0
	var at_rest: float = InfractionRules.time_to_icing_dot_line(z, 0.0, 0)
	var coming: float = InfractionRules.time_to_icing_dot_line(z, -6.0, 0)
	var going_away: float = InfractionRules.time_to_icing_dot_line(z, 6.0, 0)
	assert_lt(coming, at_rest)
	assert_gt(going_away, at_rest, "turning round costs time")

func test_racing_means_at_the_dots_or_skating_at_the_end() -> void:
	var pace: float = GameRules.ICING_RACE_PURSUIT_SPEED_M_S
	assert_true(InfractionRules.is_racing_icing(-10.0, -pace, 0))
	assert_false(InfractionRules.is_racing_icing(-10.0, -pace + 0.5, 0))
	assert_true(InfractionRules.is_racing_icing(-GameRules.ICING_FACEOFF_DOT_Z, 0.0, 0))
	assert_true(InfractionRules.is_racing_icing(10.0, pace, 1))

func test_race_undecided_until_someone_reaches_the_dots() -> void:
	assert_eq(InfractionRules.judge_icing_race(0.5, 0.4), InfractionRules.IcingCall.NONE)

func test_defender_at_the_dots_is_icing() -> void:
	assert_eq(InfractionRules.judge_icing_race(0.3, 0.0), InfractionRules.IcingCall.ICING)

func test_level_at_the_dots_is_icing() -> void:
	assert_eq(InfractionRules.judge_icing_race(0.0, 0.0), InfractionRules.IcingCall.ICING)

func test_attacker_clear_at_the_dots_waves_off() -> void:
	assert_eq(InfractionRules.judge_icing_race(0.0, GameRules.ICING_RACE_CLEAR_MARGIN_S),
			InfractionRules.IcingCall.WAVED_OFF)

func test_attacker_barely_ahead_is_too_close_to_call() -> void:
	assert_eq(InfractionRules.judge_icing_race(0.0, GameRules.ICING_RACE_CLEAR_MARGIN_S - 0.01),
			InfractionRules.IcingCall.ICING)
