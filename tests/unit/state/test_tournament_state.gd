extends GutTest

# TournamentState — the stored part of a tournament. Its dictionary is the save
# and the wire format, so it has to survive the trip and refuse what is not one.


func _state() -> TournamentState:
	var state := TournamentState.new()
	state.rng_seed = 4242
	state.clubs_by_seed = [5, 2, 9, 0, 11, 7, 3, 1] as Array[int]
	state.player_club = 9
	state.team_size = 5
	state.num_periods = 2
	state.period_duration = 180.0
	state.rule_set = GameRules.RuleSet.NHL
	state.fighting = not GameRules.FIGHTING_ENABLED
	state.bot_difficulty = BotSkillProfile.Difficulty.HARD
	state.goalie_difficulty = GoalieSkillProfile.Difficulty.EASY
	state.set_result(0, 3, 1, false)
	state.set_result(2, 2, 3, true)
	return state


func test_a_new_tournament_has_no_results() -> void:
	var state := TournamentState.new()
	for game: int in range(TournamentState.GAME_COUNT):
		assert_false(state.is_played(game))
		assert_eq(state.home_score(game), TournamentState.UNPLAYED)
		assert_false(state.went_to_overtime(game))


func test_a_game_outside_the_bracket_is_never_played() -> void:
	var state := TournamentState.new()
	state.set_result(TournamentState.GAME_COUNT, 2, 1, false)
	state.set_result(-1, 2, 1, false)
	assert_false(state.is_played(TournamentState.GAME_COUNT))
	assert_false(state.is_played(-1))


func test_round_trip_through_a_dictionary() -> void:
	var state: TournamentState = _state()
	var back: TournamentState = TournamentState.from_variant(state.to_dict())
	assert_not_null(back)
	assert_eq(back.to_dict(), state.to_dict())
	assert_eq(back.clubs_by_seed, state.clubs_by_seed)
	assert_eq(back.player_club, 9)
	assert_eq(back.team_size, 5)
	assert_eq(back.period_duration, 180.0)
	assert_eq(back.bot_difficulty, BotSkillProfile.Difficulty.HARD)
	assert_eq(back.home_score(0), 3)
	assert_eq(back.away_score(2), 3)
	assert_true(back.went_to_overtime(2))
	assert_false(back.is_played(1))


# A prefs file and a JSON body both hand whole numbers back as floats.
func test_numbers_that_arrive_as_floats_are_read() -> void:
	var raw: Dictionary = _state().to_dict()
	raw["version"] = float(TournamentState.VERSION)
	raw["clubs_by_seed"] = [5.0, 2.0, 9.0, 0.0, 11.0, 7.0, 3.0, 1.0]
	raw["results"][0] = [3.0, 1.0, false]
	var back: TournamentState = TournamentState.from_variant(raw)
	assert_not_null(back)
	assert_eq(back.clubs_by_seed, [5, 2, 9, 0, 11, 7, 3, 1] as Array[int])
	assert_eq(back.home_score(0), 3)


func test_another_version_is_refused() -> void:
	var raw: Dictionary = _state().to_dict()
	raw["version"] = TournamentState.VERSION + 1
	assert_null(TournamentState.from_variant(raw))
	raw.erase("version")
	assert_null(TournamentState.from_variant(raw))


func test_a_malformed_dictionary_is_refused() -> void:
	assert_null(TournamentState.from_variant(null))
	assert_null(TournamentState.from_variant("tournament"))
	assert_null(TournamentState.from_variant({}))

	var short_field: Dictionary = _state().to_dict()
	short_field["clubs_by_seed"] = [5, 2, 9]
	assert_null(TournamentState.from_variant(short_field), "seven clubs short of a field")

	var named_club: Dictionary = _state().to_dict()
	named_club["clubs_by_seed"] = ["Lime", 2, 9, 0, 11, 7, 3, 1]
	assert_null(TournamentState.from_variant(named_club))

	var missing_games: Dictionary = _state().to_dict()
	missing_games["results"] = [[], []]
	assert_null(TournamentState.from_variant(missing_games))

	var half_result: Dictionary = _state().to_dict()
	half_result["results"][1] = [2]
	assert_null(TournamentState.from_variant(half_result))
