extends GutTest

# TournamentCoordinator — the tournament a session is playing and the one save
# behind it: what is stored and when, what a session can resume, and that one
# started game records exactly one result.

const _ALL_CLUBS: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
const _PLAYER_CLUB: int = 4

var _stored: Variant = null
var _store_count: int = 0


func before_each() -> void:
	_stored = null
	_store_count = 0


func _coordinator() -> TournamentCoordinator:
	return TournamentCoordinator.new(
			func() -> Variant: return _stored,
			func(save: Dictionary) -> void:
				_stored = save
				_store_count += 1)


func _draft() -> TournamentState:
	var draft := TournamentState.new()
	draft.player_club = _PLAYER_CLUB
	draft.bot_difficulty = BotSkillProfile.Difficulty.HARD
	return draft


# A coordinator with a fresh tournament drawn and its first game started.
func _started(rng_seed: int = 9) -> TournamentCoordinator:
	var coordinator: TournamentCoordinator = _coordinator()
	assert_true(coordinator.begin_new(_draft(), rng_seed, _ALL_CLUBS))
	assert_true(coordinator.begin_match())
	return coordinator


# Records the score that has the player's club win or lose its next game.
func _play(coordinator: TournamentCoordinator, player_wins: bool) -> bool:
	var state: TournamentState = coordinator.active
	var at_home: bool = TournamentRules.home_club(state, TournamentRules.player_game(state)) \
			== state.player_club
	if at_home == player_wins:
		return coordinator.record_result(3, 1, false)
	return coordinator.record_result(1, 3, false)


func test_nothing_is_saved_or_active_to_begin_with() -> void:
	var coordinator: TournamentCoordinator = _coordinator()
	assert_false(coordinator.is_active())
	assert_null(coordinator.saved())
	assert_false(coordinator.resume())


func test_a_new_tournament_is_drawn_stored_and_active() -> void:
	var coordinator: TournamentCoordinator = _coordinator()
	assert_true(coordinator.begin_new(_draft(), 9, _ALL_CLUBS))
	assert_true(coordinator.is_active())
	assert_true(TournamentRules.is_valid(coordinator.active))
	assert_eq(coordinator.active.rng_seed, 9)
	assert_eq(coordinator.active.bot_difficulty, BotSkillProfile.Difficulty.HARD,
			"the draft's settings are the tournament's")
	assert_eq(_store_count, 1)
	assert_eq(coordinator.saved().to_dict(), coordinator.active.to_dict())


func test_a_club_outside_the_league_draws_nothing() -> void:
	var coordinator: TournamentCoordinator = _coordinator()
	var draft: TournamentState = _draft()
	draft.player_club = 99
	assert_false(coordinator.begin_new(draft, 9, _ALL_CLUBS))
	assert_false(coordinator.is_active())
	assert_eq(_store_count, 0)


func test_ending_the_session_keeps_the_save() -> void:
	var coordinator: TournamentCoordinator = _started()
	coordinator.end_session()
	assert_false(coordinator.is_active())
	assert_not_null(coordinator.saved())
	assert_true(coordinator.resume())
	assert_eq(coordinator.active.to_dict(), _stored)


func test_a_win_plays_out_the_rest_of_the_round_and_stores_it() -> void:
	var coordinator: TournamentCoordinator = _started()
	assert_true(_play(coordinator, true))
	var state: TournamentState = coordinator.active
	for game: int in range(4):
		assert_true(state.is_played(game), "every quarterfinal is decided")
	assert_false(state.is_played(4))
	assert_false(state.is_played(5), "the next round waits for the player")
	assert_eq(TournamentRules.status(state), TournamentRules.Status.IN_PROGRESS)
	assert_eq(TournamentRules.round_of(TournamentRules.player_game(state)), 1)
	assert_eq(_stored, state.to_dict())


func test_a_loss_plays_out_the_whole_bracket() -> void:
	var coordinator: TournamentCoordinator = _started()
	assert_true(_play(coordinator, false))
	var state: TournamentState = coordinator.active
	assert_eq(TournamentRules.status(state), TournamentRules.Status.ELIMINATED)
	assert_ne(TournamentRules.champion(state), TournamentRules.NO_CLUB)
	assert_ne(TournamentRules.champion(state), _PLAYER_CLUB)
	assert_eq(_stored, state.to_dict())


func test_three_wins_take_the_cup() -> void:
	var coordinator: TournamentCoordinator = _started()
	assert_true(_play(coordinator, true))
	assert_true(coordinator.begin_match())
	assert_true(_play(coordinator, true))
	assert_true(coordinator.begin_match())
	assert_true(_play(coordinator, true))
	assert_eq(TournamentRules.status(coordinator.active), TournamentRules.Status.CHAMPION)
	assert_false(coordinator.begin_match(), "no game left to start")


func test_one_started_game_records_one_result() -> void:
	var coordinator: TournamentCoordinator = _started()
	assert_true(_play(coordinator, true))
	var after_first: Dictionary = coordinator.active.to_dict()
	assert_false(_play(coordinator, true), "a second game-over for the same game")
	assert_eq(coordinator.active.to_dict(), after_first)


func test_a_result_with_no_game_started_is_ignored() -> void:
	var coordinator: TournamentCoordinator = _coordinator()
	assert_false(coordinator.record_result(3, 1, false), "no tournament")
	assert_true(coordinator.begin_new(_draft(), 9, _ALL_CLUBS))
	assert_false(coordinator.record_result(3, 1, false), "the lobby never started it")
	assert_eq(_store_count, 1, "only the draw was stored")


func test_a_level_score_leaves_the_game_to_be_played() -> void:
	var coordinator: TournamentCoordinator = _started()
	assert_false(coordinator.record_result(2, 2, false))
	assert_false(coordinator.active.is_played(TournamentRules.player_game(coordinator.active)))
	assert_true(_play(coordinator, true), "still awaiting its result")


func test_a_finished_tournament_is_saved_but_not_resumed() -> void:
	var coordinator: TournamentCoordinator = _started()
	assert_true(_play(coordinator, false))
	coordinator.end_session()
	assert_not_null(coordinator.saved(), "the menu can still say how it ended")
	assert_false(coordinator.resume())
	assert_false(coordinator.is_active())


func test_a_save_that_is_not_a_possible_bracket_reads_as_none() -> void:
	var coordinator: TournamentCoordinator = _started()
	coordinator.end_session()
	var broken: Dictionary = (_stored as Dictionary).duplicate(true)
	broken["player_club"] = 99
	_stored = broken
	assert_null(coordinator.saved())
	assert_false(coordinator.resume())
	_stored = "not a tournament"
	assert_null(coordinator.saved())


func test_the_roster_side_is_forgotten_with_the_session() -> void:
	var coordinator: TournamentCoordinator = _started()
	coordinator.roster_side = 1
	coordinator.end_session()
	assert_true(coordinator.resume())
	assert_eq(coordinator.roster_side, -1)


func test_changed_fires_when_a_result_lands() -> void:
	var coordinator: TournamentCoordinator = _started()
	watch_signals(coordinator)
	assert_true(_play(coordinator, true))
	assert_signal_emitted(coordinator, "changed")
