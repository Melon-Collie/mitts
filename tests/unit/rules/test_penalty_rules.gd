extends GutTest

# PenaltyRules — which body checks are fouls, and how long a minor is.

const FULL: float = HitRules.FULL_CHECK_IMPULSE
const INTO_WALL := Vector2(1.0, 0.0)
const WALL_OUT := Vector2(1.0, 0.0)


func _judge(impulse: float, eligible: bool, into_boards: bool, from_behind: bool,
		committed: bool = true, attacker_has_puck: bool = false) -> PenaltyRules.Foul:
	return PenaltyRules.judge(impulse, committed, attacker_has_puck, eligible,
			into_boards, from_behind)


# ── Where fouls are called ───────────────────────────────────────────────────

func test_fouls_are_called_only_under_nhl_rules() -> void:
	assert_true(PenaltyRules.calls_fouls(GameRules.RuleSet.NHL, false))
	assert_false(PenaltyRules.calls_fouls(GameRules.RuleSet.ARCADE, false))
	assert_false(PenaltyRules.calls_fouls(GameRules.RuleSet.OFF, false))
	assert_false(PenaltyRules.calls_fouls(GameRules.RuleSet.NHL, true), "practice")


func test_a_foul_is_a_minor_in_5v5_and_a_penalty_shot_in_3v3() -> void:
	assert_false(PenaltyRules.awards_penalty_shot(5))
	assert_true(PenaltyRules.awards_penalty_shot(3))


# ── The clean hit ────────────────────────────────────────────────────────────

func test_a_full_check_on_the_carrier_in_open_ice_is_clean() -> void:
	assert_eq(_judge(FULL * 2.0, true, false, false), PenaltyRules.Foul.NONE)


func test_a_carrier_angled_into_the_boards_from_the_side_is_clean() -> void:
	assert_eq(_judge(FULL * 2.0, true, true, false), PenaltyRules.Foul.NONE)


func test_a_hit_from_behind_in_open_ice_is_clean() -> void:
	assert_eq(_judge(FULL * 2.0, true, false, true), PenaltyRules.Foul.NONE)


func test_nothing_under_a_full_check_is_a_foul() -> void:
	var bump: float = FULL - 0.01
	assert_eq(_judge(bump, false, true, true), PenaltyRules.Foul.NONE,
			"a bump, a lean and the press never reach a full check")


func test_an_uncommitted_body_and_a_carrier_foul_nobody() -> void:
	assert_eq(_judge(FULL * 2.0, false, true, true, false), PenaltyRules.Foul.NONE)
	assert_eq(_judge(FULL * 2.0, false, true, true, true, true), PenaltyRules.Foul.NONE)


# ── The fouls ────────────────────────────────────────────────────────────────

func test_a_full_check_from_behind_into_the_boards_is_boarding() -> void:
	assert_eq(_judge(FULL, true, true, true), PenaltyRules.Foul.BOARDING,
			"the carrier is not fair game from behind on the wall")


func test_a_full_check_on_a_man_away_from_the_puck_is_interference() -> void:
	assert_eq(_judge(FULL, false, false, false), PenaltyRules.Foul.INTERFERENCE)


func test_boarding_outranks_interference() -> void:
	assert_eq(_judge(FULL, false, true, true), PenaltyRules.Foul.BOARDING)


# ── Who may be hit ───────────────────────────────────────────────────────────

func test_the_carrier_may_be_hit() -> void:
	assert_true(PenaltyRules.is_eligible_to_be_hit(true, INF, false, 30.0))


func test_a_man_who_just_released_the_puck_may_be_hit() -> void:
	var grace: float = HitRules.JUST_RELEASED_GRACE_S
	assert_true(PenaltyRules.is_eligible_to_be_hit(false, grace, false, 30.0))
	assert_false(PenaltyRules.is_eligible_to_be_hit(false, grace + 0.01, false, 30.0))


func test_a_man_playing_a_loose_puck_may_be_hit() -> void:
	var reach: float = PenaltyRules.INTERFERENCE_PUCK_REACH_M
	assert_true(PenaltyRules.is_eligible_to_be_hit(false, INF, true, reach))
	assert_false(PenaltyRules.is_eligible_to_be_hit(false, INF, true, reach + 0.01),
			"too far from it to be playing it")
	assert_false(PenaltyRules.is_eligible_to_be_hit(false, INF, false, 0.5),
			"standing by a puck someone else carries is not playing it")


# ── Boarding's geometry ──────────────────────────────────────────────────────

func test_a_hit_drives_into_the_boards_within_45_degrees_of_square() -> void:
	assert_true(PenaltyRules.is_driven_into_boards(INTO_WALL, WALL_OUT))
	assert_true(PenaltyRules.is_driven_into_boards(Vector2(1.0, 0.9).normalized(), WALL_OUT))
	assert_false(PenaltyRules.is_driven_into_boards(Vector2(1.0, 1.1).normalized(), WALL_OUT),
			"along the wall, not into it")
	assert_false(PenaltyRules.is_driven_into_boards(-INTO_WALL, WALL_OUT), "off the wall")
	assert_false(PenaltyRules.is_driven_into_boards(INTO_WALL, Vector2.ZERO), "open ice")


func test_the_hitter_is_behind_a_man_facing_the_way_he_is_driven() -> void:
	assert_true(PenaltyRules.is_hit_from_behind(Vector2(1.0, 0.0), INTO_WALL))
	assert_false(PenaltyRules.is_hit_from_behind(Vector2(0.0, 1.0), INTO_WALL),
			"side on: he sees it coming")
	assert_false(PenaltyRules.is_hit_from_behind(Vector2(-1.0, 0.0), INTO_WALL),
			"face to face")


# ── The minor ────────────────────────────────────────────────────────────────

func test_a_minor_is_a_tenth_of_the_period() -> void:
	assert_almost_eq(PenaltyRules.minor_seconds(240.0), 24.0, 0.0001)
	assert_almost_eq(PenaltyRules.minor_seconds(600.0), 60.0, 0.0001)


func test_a_short_period_still_has_a_minor_worth_killing() -> void:
	assert_eq(PenaltyRules.minor_seconds(60.0), PenaltyRules.MINOR_MIN_S)


func test_a_team_is_never_put_below_three_skaters() -> void:
	assert_eq(PenaltyRules.max_serving(5), 2)
	assert_eq(PenaltyRules.max_serving(3), 0)


func test_every_foul_has_a_name() -> void:
	for foul: int in PenaltyRules.Foul.values():
		if foul != PenaltyRules.Foul.NONE:
			assert_ne(PenaltyRules.name_key(foul), "", "foul %d" % foul)
