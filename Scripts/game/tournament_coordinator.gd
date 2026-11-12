class_name TournamentCoordinator
extends RefCounted
## The tournament a session is playing, and the one save behind it.
##
## `active` is non-null from the moment a tournament's lobby opens until the
## session ends (GameManager ends it on every NetworkManager reset), so any
## match played while it is set is the player's next tournament game. The save
## outlives the session and is what `resume` picks up.
##
## The host owns both. A client's `active` is a mirror of the host's
## (`adopt_remote`), never stored and never recorded into.

signal changed

var active: TournamentState = null

# The side (0 or 1) the player's club holds in the lobby roster as it stands,
# -1 before the session's first lobby has seated anyone. The club changes sides
# between games, and the lobby reads this to know which seats were its own.
var roster_side: int = -1
# The game that roster was seated for, so a lobby reopened on the same game
# (one abandoned, or the last of a finished tournament) keeps its bots.
var roster_game: int = TournamentRules.NO_GAME

var _load_save: Callable   # () -> Variant, the dictionary last stored
var _store_save: Callable  # (Dictionary) -> void
# Set when the lobby starts a game and cleared when its result is recorded, so
# one start records one result however many times a game-over is reported.
var _awaiting_result: bool = false


func _init(load_save: Callable, store_save: Callable) -> void:
	_load_save = load_save
	_store_save = store_save


func is_active() -> bool:
	return active != null


# The stored tournament, in progress or finished, or null when there is none or
# what is stored is not a possible bracket.
func saved() -> TournamentState:
	var state: TournamentState = TournamentState.from_variant(_load_save.call())
	return state if TournamentRules.is_valid(state) else null


# Draws a bracket for `draft` (its player_club and match settings are the
# caller's), stores it over any earlier save and makes it the session's.
func begin_new(draft: TournamentState, rng_seed: int, all_clubs: Array[int]) -> bool:
	draft.rng_seed = rng_seed
	draft.clubs_by_seed = TournamentRules.draw(rng_seed, draft.player_club, all_clubs)
	if not TournamentRules.is_valid(draft):
		return false
	_set_active(draft)
	_store()
	return true


# Makes the stored tournament the session's. False when there is none, or it is
# already over.
func resume() -> bool:
	var state: TournamentState = saved()
	if state == null or TournamentRules.status(state) != TournamentRules.Status.IN_PROGRESS:
		return false
	_set_active(state)
	return true


# Leaves the tournament without touching its save.
func end_session() -> void:
	if active == null:
		return
	_set_active(null)


# Client: takes the host's copy as the session's tournament. Anything that is
# not a possible bracket, the empty dictionary included, means there is none.
func adopt_remote(data: Variant) -> void:
	var state: TournamentState = TournamentState.from_variant(data)
	active = state if TournamentRules.is_valid(state) else null
	changed.emit()


# Whether a human may take a seat on `team_id`. In a tournament the humans all
# sit on the player's side; anywhere else, and before a lobby has seated
# anyone, every seat is open.
func may_seat(team_id: int) -> bool:
	if active == null or roster_side == -1:
		return true
	return team_id == roster_side or team_id == GameRules.SPECTATOR_TEAM_ID


# The lobby is starting the player's next game. False when there is none to play.
func begin_match() -> bool:
	_awaiting_result = active != null \
			and TournamentRules.player_game(active) != TournamentRules.NO_GAME
	return _awaiting_result


# The final score of the game `begin_match` started, home being side 0. Plays
# out the rest of the round, and the rest of the bracket once the player's club
# is out, then stores the lot.
func record_result(home_score: int, away_score: int, overtime: bool) -> bool:
	if active == null or not _awaiting_result:
		return false
	var game: int = TournamentRules.player_game(active)
	if not TournamentRules.record(active, game, home_score, away_score, overtime):
		return false
	_awaiting_result = false
	TournamentRules.simulate_round(active, TournamentRules.round_of(game))
	if TournamentRules.status(active) == TournamentRules.Status.ELIMINATED:
		TournamentRules.simulate_to_end(active)
	_store()
	changed.emit()
	return true


func _set_active(state: TournamentState) -> void:
	active = state
	roster_side = -1
	roster_game = TournamentRules.NO_GAME
	_awaiting_result = false
	changed.emit()


func _store() -> void:
	_store_save.call(active.to_dict())
