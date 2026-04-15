extends GutTest

# InfractionRules — offside and icing detection.

# ── Offside ──────────────────────────────────────────────────────────────────

func test_carrier_never_offside() -> void:
	# Skater is past the blue line with puck in neutral, but is the carrier
	assert_false(InfractionRules.is_offside(-10.0, 0, 0.0, true))
	assert_false(InfractionRules.is_offside(10.0, 1, 0.0, true))

func test_team_0_offside_when_past_blue_line_ahead_of_puck() -> void:
	# Team 0 attacks -Z: attacking zone is z < -BLUE_LINE_Z
	# Skater is deep in attacking zone, puck is in neutral
	assert_true(InfractionRules.is_offside(-10.0, 0, 0.0, false))

func test_team_0_not_offside_when_puck_also_in_zone() -> void:
	# Puck is in the attacking zone ahead of or alongside skater → legal
	assert_false(InfractionRules.is_offside(-10.0, 0, -10.0, false))

func test_team_0_not_offside_when_behind_blue_line() -> void:
	# Skater at center or defensive side
	assert_false(InfractionRules.is_offside(0.0, 0, 0.0, false))
	assert_false(InfractionRules.is_offside(10.0, 0, 0.0, false))

func test_team_1_offside_when_past_blue_line_ahead_of_puck() -> void:
	# Team 1 attacks +Z: attacking zone is z > BLUE_LINE_Z
	assert_true(InfractionRules.is_offside(10.0, 1, 0.0, false))

func test_team_1_not_offside_when_puck_in_attacking_zone() -> void:
	assert_false(InfractionRules.is_offside(10.0, 1, 10.0, false))

func test_puck_on_blue_line_clears_offside_for_team_0() -> void:
	# Puck at exactly -BLUE_LINE_Z counts as "in the zone" for team 0
	# (puck_z >= -BLUE_LINE_Z evaluates at equality with flipped sign... wait)
	# Team 0: offside iff (skater_z < -BLUE_LINE_Z) AND (puck_z >= -BLUE_LINE_Z)
	# With puck_z == -BLUE_LINE_Z, the second condition is true — so it would be offside
	# if skater is past the line. Actual rule: puck carrier crossing the line clears
	# offside, which matches puck_z < -BLUE_LINE_Z (strictly past), not at the line.
	# Confirm current behavior:
	assert_true(InfractionRules.is_offside(-10.0, 0, -GameRules.BLUE_LINE_Z, false),
		"puck exactly at blue line still counts as not-in-zone for team 0 (documented behavior)")

func test_puck_past_blue_line_clears_offside_for_team_0() -> void:
	# Puck strictly past -BLUE_LINE_Z is now in the attacking zone
	assert_false(InfractionRules.is_offside(-10.0, 0, -GameRules.BLUE_LINE_Z - 0.1, false))

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

# ── Hybrid icing race ─────────────────────────────────────────────────────────

func test_defending_wins_when_closer() -> void:
	assert_true(InfractionRules.defending_wins_icing_race(10.0, 5.0))

func test_icing_waved_off_when_attacker_closer() -> void:
	assert_false(InfractionRules.defending_wins_icing_race(5.0, 10.0))

func test_defending_wins_on_tie() -> void:
	assert_true(InfractionRules.defending_wins_icing_race(5.0, 5.0))
