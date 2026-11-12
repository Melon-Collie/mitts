extends GutTest

# TournamentRules — the eight-club single-elimination bracket: the draw, who
# meets whom, who is at home, how a result advances a club, and the games
# nobody plays.

const _ALL_CLUBS: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
# Seed index i holds club 10 + i, so a club's seed reads off its number.
const _FIELD: Array[int] = [10, 11, 12, 13, 14, 15, 16, 17]
const _SEEDS_TRIED: int = 200


func _state(player_club: int = 10, rng_seed: int = 1) -> TournamentState:
	var state := TournamentState.new()
	state.rng_seed = rng_seed
	state.clubs_by_seed = _FIELD.duplicate()
	state.player_club = player_club
	return state


# Records a win for `club` in `game`, whichever side it is on.
func _win(state: TournamentState, game: int, club: int) -> bool:
	if TournamentRules.home_club(state, game) == club:
		return TournamentRules.record(state, game, 2, 1, false)
	return TournamentRules.record(state, game, 1, 2, false)


# ── draw ─────────────────────────────────────────────────────────────────────

func test_draw_is_eight_distinct_clubs_with_the_players_among_them() -> void:
	for rng_seed: int in range(_SEEDS_TRIED):
		var field: Array[int] = TournamentRules.draw(rng_seed, 4, _ALL_CLUBS)
		assert_eq(field.size(), TournamentState.CLUB_COUNT)
		assert_true(field.has(4), "the player's club is always in")
		var seen: Dictionary = {}
		for club: int in field:
			assert_true(_ALL_CLUBS.has(club))
			seen[club] = true
		assert_eq(seen.size(), TournamentState.CLUB_COUNT, "no club drawn twice")


func test_draw_repeats_for_a_seed_and_differs_between_seeds() -> void:
	assert_eq(TournamentRules.draw(77, 4, _ALL_CLUBS), TournamentRules.draw(77, 4, _ALL_CLUBS))
	var distinct: Dictionary = {}
	for rng_seed: int in range(_SEEDS_TRIED):
		distinct[TournamentRules.draw(rng_seed, 4, _ALL_CLUBS)] = true
	assert_gt(distinct.size(), _SEEDS_TRIED / 2, "seeds draw different fields")


func test_the_player_can_draw_any_seed() -> void:
	var seeds_drawn: Dictionary = {}
	for rng_seed: int in range(_SEEDS_TRIED):
		seeds_drawn[TournamentRules.draw(rng_seed, 4, _ALL_CLUBS).find(4)] = true
	assert_eq(seeds_drawn.size(), TournamentState.CLUB_COUNT)


func test_draw_refuses_a_field_it_cannot_fill() -> void:
	assert_true(TournamentRules.draw(1, 99, _ALL_CLUBS).is_empty(), "not a club")
	var seven: Array[int] = [0, 1, 2, 3, 4, 5, 6]
	assert_true(TournamentRules.draw(1, 0, seven).is_empty(), "too few clubs")


func test_draw_does_not_touch_the_callers_list() -> void:
	var clubs: Array[int] = _ALL_CLUBS.duplicate()
	TournamentRules.draw(3, 4, clubs)
	assert_eq(clubs, _ALL_CLUBS)


# ── pairing and home ice ─────────────────────────────────────────────────────

func test_quarterfinals_pair_the_seeds_one_against_eight() -> void:
	var state: TournamentState = _state()
	# [game, home seed index, away seed index]
	var expected: Array = [[0, 0, 7], [1, 3, 4], [2, 2, 5], [3, 1, 6]]
	for row: Array in expected:
		assert_eq(TournamentRules.home_club(state, row[0]), _FIELD[row[1]])
		assert_eq(TournamentRules.away_club(state, row[0]), _FIELD[row[2]])


func test_the_top_two_seeds_can_meet_only_in_the_final() -> void:
	var state: TournamentState = _state()
	assert_true(_win(state, 0, _FIELD[0]))
	assert_true(_win(state, 1, _FIELD[3]))
	assert_true(_win(state, 2, _FIELD[2]))
	assert_true(_win(state, 3, _FIELD[1]))
	assert_eq(TournamentRules.home_club(state, 4), _FIELD[0])
	assert_eq(TournamentRules.away_club(state, 4), _FIELD[3])
	assert_eq(TournamentRules.home_club(state, 5), _FIELD[1])
	assert_eq(TournamentRules.away_club(state, 5), _FIELD[2])


func test_a_later_game_has_no_clubs_until_both_feeders_are_played() -> void:
	var state: TournamentState = _state()
	assert_eq(TournamentRules.home_club(state, 4), TournamentRules.NO_CLUB)
	assert_true(_win(state, 0, _FIELD[7]))
	assert_eq(TournamentRules.entrant(state, 4, 0), _FIELD[7], "one line is known")
	assert_eq(TournamentRules.entrant(state, 4, 1), TournamentRules.NO_CLUB)
	assert_eq(TournamentRules.home_club(state, 4), TournamentRules.NO_CLUB)
	assert_eq(TournamentRules.away_club(state, 4), TournamentRules.NO_CLUB)


func test_the_better_seed_is_at_home_whichever_line_it_came_through() -> void:
	var state: TournamentState = _state()
	# The eighth seed upsets the first on the upper line; the fourth holds on
	# the lower, and is the better seed of the semifinal.
	assert_true(_win(state, 0, _FIELD[7]))
	assert_true(_win(state, 1, _FIELD[3]))
	assert_eq(TournamentRules.home_club(state, 4), _FIELD[3])
	assert_eq(TournamentRules.away_club(state, 4), _FIELD[7])


func test_round_of_each_game() -> void:
	var rounds: Array[int] = [0, 0, 0, 0, 1, 1, 2]
	for game: int in range(TournamentState.GAME_COUNT):
		assert_eq(TournamentRules.round_of(game), rounds[game])


# ── results ──────────────────────────────────────────────────────────────────

func test_the_higher_score_wins_from_either_side() -> void:
	var state: TournamentState = _state()
	assert_true(TournamentRules.record(state, 0, 4, 2, false))
	assert_eq(TournamentRules.winner(state, 0), _FIELD[0], "home won")
	assert_true(TournamentRules.record(state, 1, 0, 1, true))
	assert_eq(TournamentRules.winner(state, 1), _FIELD[4], "away won")
	assert_eq(TournamentRules.winner(state, 2), TournamentRules.NO_CLUB, "not played")


func test_record_refuses_a_result_that_cannot_be() -> void:
	var state: TournamentState = _state()
	assert_false(TournamentRules.record(state, 0, 2, 2, false), "level")
	assert_false(TournamentRules.record(state, 0, -1, 2, false), "negative")
	assert_false(TournamentRules.record(state, 4, 2, 1, false), "clubs undecided")
	assert_false(TournamentRules.record(state, 7, 2, 1, false), "no such game")
	assert_false(state.is_played(0))
	assert_true(TournamentRules.record(state, 0, 2, 1, false))
	assert_false(TournamentRules.record(state, 0, 0, 5, false), "already played")
	assert_eq(state.home_score(0), 2, "the first result stands")


func test_seven_results_name_one_champion() -> void:
	var state: TournamentState = _state()
	assert_eq(TournamentRules.champion(state), TournamentRules.NO_CLUB)
	for game: int in range(TournamentState.GAME_COUNT):
		assert_true(_win(state, game, TournamentRules.away_club(state, game)))
	# Every away side won: 8 and 5 meet, then 6 and 7; the worse seed each time.
	assert_eq(TournamentRules.champion(state), _FIELD[7])


# ── the player's path ────────────────────────────────────────────────────────

func test_the_players_game_follows_them_through_the_bracket() -> void:
	var player: int = _FIELD[5]  # sixth seed: quarterfinal 2, on the lower half
	var state: TournamentState = _state(player)
	assert_eq(TournamentRules.player_game(state), 2)
	assert_eq(TournamentRules.status(state), TournamentRules.Status.IN_PROGRESS)
	assert_true(_win(state, 2, player))
	assert_eq(TournamentRules.player_game(state), 5)
	assert_true(_win(state, 3, _FIELD[1]))
	assert_true(_win(state, 5, player))
	assert_eq(TournamentRules.player_game(state), TournamentRules.FINAL)
	assert_true(_win(state, 0, _FIELD[0]))
	assert_true(_win(state, 1, _FIELD[3]))
	assert_true(_win(state, 4, _FIELD[0]))
	assert_true(_win(state, TournamentRules.FINAL, player))
	assert_eq(TournamentRules.player_game(state), TournamentRules.NO_GAME)
	assert_eq(TournamentRules.status(state), TournamentRules.Status.CHAMPION)


func test_a_loss_ends_the_players_run() -> void:
	var state: TournamentState = _state(_FIELD[0])
	assert_true(_win(state, 0, _FIELD[7]))
	assert_eq(TournamentRules.player_game(state), TournamentRules.NO_GAME)
	assert_eq(TournamentRules.status(state), TournamentRules.Status.ELIMINATED)


# ── simulated games ──────────────────────────────────────────────────────────

func test_a_round_is_simulated_around_the_players_game() -> void:
	var state: TournamentState = _state(_FIELD[0])
	TournamentRules.simulate_round(state, 0)
	assert_false(state.is_played(0), "the player's own game is never simulated")
	for game: int in [1, 2, 3]:
		assert_true(state.is_played(game))
	assert_false(state.is_played(5), "the next round waits its turn")


func test_simulating_a_round_leaves_played_games_alone() -> void:
	var state: TournamentState = _state(_FIELD[0])
	assert_true(TournamentRules.record(state, 1, 9, 0, false))
	TournamentRules.simulate_round(state, 0)
	assert_eq(state.home_score(1), 9)
	assert_eq(state.away_score(1), 0)


func test_simulate_to_end_stops_at_the_players_game() -> void:
	var state: TournamentState = _state(_FIELD[0])
	TournamentRules.simulate_to_end(state)
	assert_false(state.is_played(0))
	assert_false(state.is_played(4), "waits on the player's quarterfinal")
	assert_true(state.is_played(5), "the other half plays through")
	assert_false(state.is_played(TournamentRules.FINAL))


func test_simulate_to_end_finishes_the_bracket_once_the_player_is_out() -> void:
	var state: TournamentState = _state(_FIELD[0])
	assert_true(_win(state, 0, _FIELD[7]))
	TournamentRules.simulate_to_end(state)
	for game: int in range(TournamentState.GAME_COUNT):
		assert_true(state.is_played(game))
	assert_ne(TournamentRules.champion(state), TournamentRules.NO_CLUB)
	assert_true(TournamentRules.is_valid(state))


func test_simulated_games_always_have_a_winner() -> void:
	for rng_seed: int in range(_SEEDS_TRIED):
		var state: TournamentState = _state(_FIELD[0], rng_seed)
		assert_true(_win(state, 0, _FIELD[7]))
		TournamentRules.simulate_to_end(state)
		for game: int in range(1, TournamentState.GAME_COUNT):
			assert_ne(state.home_score(game), state.away_score(game))
			assert_gte(mini(state.home_score(game), state.away_score(game)), 0)
			if state.went_to_overtime(game):
				assert_eq(absi(state.home_score(game) - state.away_score(game)), 1,
						"overtime is sudden death")


func test_a_simulated_result_does_not_depend_on_the_order_games_resolve() -> void:
	var by_round: TournamentState = _state(_FIELD[0], 31)
	assert_true(_win(by_round, 0, _FIELD[7]))
	for round_index: int in range(TournamentRules.ROUND_COUNT):
		TournamentRules.simulate_round(by_round, round_index)

	# The same bracket, with the player's loss recorded after the rest of the
	# round was already simulated.
	var player_last: TournamentState = _state(_FIELD[0], 31)
	TournamentRules.simulate_round(player_last, 0)
	assert_true(_win(player_last, 0, _FIELD[7]))
	TournamentRules.simulate_to_end(player_last)

	assert_eq(player_last.to_dict(), by_round.to_dict())


func test_seeds_simulate_different_brackets() -> void:
	var distinct: Dictionary = {}
	for rng_seed: int in range(_SEEDS_TRIED):
		var state: TournamentState = _state(_FIELD[0], rng_seed)
		TournamentRules.simulate_round(state, 0)
		distinct[state.to_dict()["results"]] = true
	assert_gt(distinct.size(), _SEEDS_TRIED / 2)


# The first seed is the player's opponent's line here, so game 0 (1 v 8) is
# simulated: the player is the fourth seed.
func test_the_better_seed_wins_a_simulated_game_more_often_than_not() -> void:
	var favorite_wins: int = 0
	var upsets: int = 0
	for rng_seed: int in range(_SEEDS_TRIED):
		var state: TournamentState = _state(_FIELD[3], rng_seed)
		TournamentRules.simulate_round(state, 0)
		if TournamentRules.winner(state, 0) == _FIELD[0]:
			favorite_wins += 1
		else:
			upsets += 1
	assert_gt(favorite_wins, upsets)
	assert_gt(upsets, 0, "an upset is possible")


# ── validity ─────────────────────────────────────────────────────────────────

func test_a_fresh_and_a_played_bracket_are_valid() -> void:
	var state: TournamentState = _state()
	assert_true(TournamentRules.is_valid(state))
	assert_true(_win(state, 0, _FIELD[0]))
	assert_true(TournamentRules.is_valid(state))


func test_impossible_brackets_are_not_valid() -> void:
	assert_false(TournamentRules.is_valid(null))
	assert_false(TournamentRules.is_valid(TournamentState.new()), "no field drawn")

	var twice: TournamentState = _state()
	twice.clubs_by_seed[3] = twice.clubs_by_seed[0]
	assert_false(TournamentRules.is_valid(twice), "a club drawn twice")

	var outsider: TournamentState = _state(99)
	assert_false(TournamentRules.is_valid(outsider), "the player's club is not in it")

	var level: TournamentState = _state()
	level.set_result(0, 2, 2, false)
	assert_false(TournamentRules.is_valid(level), "a level final score")

	var orphan: TournamentState = _state()
	orphan.set_result(4, 2, 1, false)
	assert_false(TournamentRules.is_valid(orphan), "a semifinal with no quarterfinals")
