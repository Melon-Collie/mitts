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


func test_a_fight_costs_a_minor_only_where_a_foul_is_one() -> void:
	assert_true(PenaltyRules.penalizes_fights(GameRules.RuleSet.NHL, 5, false))
	assert_false(PenaltyRules.penalizes_fights(GameRules.RuleSet.NHL, 3, false),
			"3v3 does not sit two men for a fight")
	assert_false(PenaltyRules.penalizes_fights(GameRules.RuleSet.ARCADE, 5, false))
	assert_false(PenaltyRules.penalizes_fights(GameRules.RuleSet.NHL, 5, true), "practice")


func test_a_goal_ends_a_minor_for_a_foul_but_not_for_a_fight() -> void:
	assert_true(PenaltyRules.ends_on_a_goal(PenaltyRules.Foul.BOARDING))
	assert_true(PenaltyRules.ends_on_a_goal(PenaltyRules.Foul.INTERFERENCE))
	assert_false(PenaltyRules.ends_on_a_goal(PenaltyRules.Foul.FIGHTING))


func test_a_goal_reads_who_was_short_as_it_went_in() -> void:
	var gs := PenaltyRules.GoalSituation
	assert_eq(PenaltyRules.goal_situation(0, -1, false), gs.EVEN)
	assert_eq(PenaltyRules.goal_situation(0, 1, false), gs.POWER_PLAY,
			"the other team is the one short")
	assert_eq(PenaltyRules.goal_situation(0, 0, false), gs.SHORT_HANDED)
	assert_eq(PenaltyRules.goal_situation(0, 1, true), gs.PENALTY_SHOT,
			"a penalty shot is its own situation")


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

func test_nobody_is_playing_a_puck_that_is_not_in_play() -> void:
	assert_false(PenaltyRules.is_eligible_to_be_hit(false, INF, false, 0.5))


func test_contact_is_judged_while_the_puck_is_in_play() -> void:
	assert_true(PenaltyRules.judges_contact(GamePhase.Phase.PLAYING, 0.0))
	assert_true(PenaltyRules.judges_contact(GamePhase.Phase.FACEOFF, 0.0),
			"the puck is dropped: a check away from it is interference")


func test_a_check_already_under_way_at_a_goal_is_let_go() -> void:
	assert_false(PenaltyRules.judges_contact(GamePhase.Phase.GOAL_CELEBRATION, 0.0))
	assert_false(PenaltyRules.judges_contact(GamePhase.Phase.GOAL_CELEBRATION,
			PenaltyRules.WHISTLE_GRACE_S - 0.01))


func test_a_check_thrown_in_the_celebration_is_judged() -> void:
	assert_true(PenaltyRules.judges_contact(GamePhase.Phase.GOAL_CELEBRATION,
			PenaltyRules.WHISTLE_GRACE_S))


func test_no_contact_is_judged_in_a_stoppage_that_holds_the_skaters() -> void:
	for phase: int in [GamePhase.Phase.FACEOFF_PREP, GamePhase.Phase.GOAL_SCORED,
			GamePhase.Phase.END_OF_PERIOD, GamePhase.Phase.GAME_OVER, GamePhase.Phase.FIGHT]:
		assert_false(PenaltyRules.judges_contact(phase, 10.0), GamePhase.Phase.keys()[phase])


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
