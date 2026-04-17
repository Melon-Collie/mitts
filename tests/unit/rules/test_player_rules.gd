extends GutTest

# PlayerRules — team balancing, color generation, faceoff position lookup.

# ── assign_team ──────────────────────────────────────────────────────────────

func test_tied_counts_pick_either_team() -> void:
	# Tiebreak is randomised; verify only that a valid team id comes back.
	var t: int = PlayerRules.assign_team(0, 0)
	assert_true(t == 0 or t == 1, "tiebreak must return 0 or 1, got %d" % t)

func test_smaller_team_gets_next_player() -> void:
	assert_eq(PlayerRules.assign_team(1, 0), 1)
	assert_eq(PlayerRules.assign_team(0, 1), 0)

func test_lopsided_filled_to_smaller() -> void:
	assert_eq(PlayerRules.assign_team(3, 1), 1)

# ── generate_primary_color ───────────────────────────────────────────────────

func test_team_0_primary_is_gold() -> void:
	var c: Color = PlayerRules.generate_primary_color(0)
	assert_true(c.r > 0.8 and c.g > 0.5 and c.b < 0.3, "home primary should be Penguins gold, got r=%f g=%f b=%f" % [c.r, c.g, c.b])

func test_team_1_primary_is_blue() -> void:
	var c: Color = PlayerRules.generate_primary_color(1)
	assert_true(c.b > c.r and c.b > c.g, "away primary should be Leafs blue-dominant, got r=%f g=%f b=%f" % [c.r, c.g, c.b])

func test_team_0_primary_is_deterministic() -> void:
	assert_eq(PlayerRules.generate_primary_color(0), PlayerRules.generate_primary_color(0))

func test_team_1_primary_is_deterministic() -> void:
	assert_eq(PlayerRules.generate_primary_color(1), PlayerRules.generate_primary_color(1))

# ── faceoff_position ─────────────────────────────────────────────────────────

func test_team_0_faceoff_positions_are_on_positive_z_side() -> void:
	assert_gt(PlayerRules.faceoff_position(0, 0).z, 0.0)
	assert_gt(PlayerRules.faceoff_position(0, 1).z, 0.0)
	assert_gt(PlayerRules.faceoff_position(0, 2).z, 0.0)

func test_team_1_faceoff_positions_are_on_negative_z_side() -> void:
	assert_lt(PlayerRules.faceoff_position(1, 0).z, 0.0)
	assert_lt(PlayerRules.faceoff_position(1, 1).z, 0.0)
	assert_lt(PlayerRules.faceoff_position(1, 2).z, 0.0)
