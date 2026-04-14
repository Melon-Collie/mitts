extends GutTest

# PlayerRules — team balancing, color generation, faceoff position lookup.

# ── assign_team ──────────────────────────────────────────────────────────────

func test_first_player_assigned_to_team_0() -> void:
	assert_eq(PlayerRules.assign_team(0, 0), 0, "tie goes to team 0")

func test_smaller_team_gets_next_player() -> void:
	assert_eq(PlayerRules.assign_team(1, 0), 1)
	assert_eq(PlayerRules.assign_team(0, 1), 0)

func test_balanced_counts_prefer_team_0() -> void:
	assert_eq(PlayerRules.assign_team(2, 2), 0)

func test_lopsided_filled_to_smaller() -> void:
	assert_eq(PlayerRules.assign_team(3, 1), 1)

# ── generate_player_color ────────────────────────────────────────────────────

func test_team_0_color_in_warm_range() -> void:
	# Team 0 hue 340-380° → normalized 0.944-1.056 (wraps to 0.056).
	# With jitter=0 and existing=0, center is 340 + (0.5 * 40/3) = 346.66°
	# → hue ≈ 0.963
	var c: Color = PlayerRules.generate_player_color(0, 0, 0.0)
	# Red-dominant — either hue near 1.0 (red) or wrapping into 0.0
	assert_true(c.r > 0.5, "red channel should be dominant, got r=%f" % c.r)

func test_team_1_color_in_cool_range() -> void:
	# Team 1 hue 200-260° → normalized 0.556-0.722. Blue/cyan-dominant.
	var c: Color = PlayerRules.generate_player_color(1, 0, 0.0)
	assert_true(c.b > c.r, "blue should exceed red for cool color, got r=%f b=%f" % [c.r, c.b])

func test_zero_jitter_is_deterministic() -> void:
	var a: Color = PlayerRules.generate_player_color(0, 1, 0.0)
	var b: Color = PlayerRules.generate_player_color(0, 1, 0.0)
	assert_eq(a, b, "same inputs should give same output with no jitter")

func test_different_slots_give_different_hues() -> void:
	var c0: Color = PlayerRules.generate_player_color(0, 0, 0.0)
	var c1: Color = PlayerRules.generate_player_color(0, 1, 0.0)
	assert_ne(c0.h, c1.h, "different slots should have distinct hues")

func test_jitter_shifts_hue_within_slot() -> void:
	var center: Color = PlayerRules.generate_player_color(1, 0, 0.0)
	var jittered: Color = PlayerRules.generate_player_color(1, 0, 1.0)
	assert_ne(center.h, jittered.h, "jitter=1.0 should move hue off center")

# ── faceoff_position_for_slot ────────────────────────────────────────────────

func test_faceoff_positions_even_slots_are_team_0_side() -> void:
	# Even slots are team 0, on +Z side
	assert_gt(PlayerRules.faceoff_position_for_slot(0).z, 0.0)
	assert_gt(PlayerRules.faceoff_position_for_slot(2).z, 0.0)
	assert_gt(PlayerRules.faceoff_position_for_slot(4).z, 0.0)

func test_faceoff_positions_odd_slots_are_team_1_side() -> void:
	assert_lt(PlayerRules.faceoff_position_for_slot(1).z, 0.0)
	assert_lt(PlayerRules.faceoff_position_for_slot(3).z, 0.0)
	assert_lt(PlayerRules.faceoff_position_for_slot(5).z, 0.0)
