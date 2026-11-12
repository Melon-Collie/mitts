class_name TournamentRules
## The bracket's rules over a TournamentState: an eight-club single elimination.
##
## Games are numbered in bracket order: 0-3 the quarterfinals, 4-5 the
## semifinals, 6 the final. Game 4 is fed by games 0 and 1, game 5 by 2 and 3,
## game 6 by 4 and 5. A club is a TeamColorRegistry slot; -1 stands for a club
## not yet decided.

enum Status { IN_PROGRESS, ELIMINATED, CHAMPION }

const ROUND_COUNT: int = 3
const FINAL: int = TournamentState.GAME_COUNT - 1
const NO_CLUB: int = -1
const NO_GAME: int = -1

# Seed indices (0 = first seed) of each quarterfinal's two entrants, flattened.
# 1v8 and 4v5 share the top half, 3v6 and 2v7 the bottom, so the first and
# second seeds can meet only in the final.
const _QUARTERFINAL_SEEDS: Array[int] = [0, 7, 3, 4, 2, 5, 1, 6]
const _QUARTERFINAL_COUNT: int = 4
const _FIRST_GAME_OF_ROUND: Array[int] = [0, 4, 6]
const _GAMES_IN_ROUND: Array[int] = [4, 2, 1]
const _ROUND_NAME_KEYS: Array[String] = [
	"TOURNAMENT_ROUND_QF", "TOURNAMENT_ROUND_SF", "TOURNAMENT_ROUND_FINAL",
]

# How much likelier the better seed is to win a simulated game, per seed of gap:
# 54% for fourth against fifth, 78% for first against eighth.
const SIM_SEED_EDGE: float = 0.04
# One side's scoring rate in a simulated game. A guess until real scores say
# otherwise; it only sizes the scores nobody watched.
const SIM_GOALS_PER_MINUTE: float = 0.25
const SIM_OVERTIME_SHARE: float = 0.2


# The eight clubs in seed order: the player's club and seven of the others,
# shuffled. Empty when the player's club is not in `all_clubs` or there are too
# few clubs to fill a field. `all_clubs` must hold no duplicates.
static func draw(rng_seed: int, player_club: int, all_clubs: Array[int]) -> Array[int]:
	var field: Array[int] = []
	if not all_clubs.has(player_club) or all_clubs.size() < TournamentState.CLUB_COUNT:
		return field
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var others: Array[int] = all_clubs.duplicate()
	others.erase(player_club)
	_shuffle(others, rng)
	field.append(player_club)
	for i: int in range(TournamentState.CLUB_COUNT - 1):
		field.append(others[i])
	_shuffle(field, rng)
	return field


static func round_of(game: int) -> int:
	if game < _FIRST_GAME_OF_ROUND[1]:
		return 0
	return 1 if game < FINAL else 2


# The translation key of a round's name; the caller runs it through tr().
static func round_name_key(round_index: int) -> String:
	if round_index < 0 or round_index >= ROUND_COUNT:
		return ""
	return _ROUND_NAME_KEYS[round_index]


# A club's seed index (0 = first seed), or -1 for a club not in the field.
static func seed_of(state: TournamentState, club: int) -> int:
	return state.clubs_by_seed.find(club)


# The club on one line of a game's bracket slot (`line` 0 = upper, 1 = lower),
# known for a later round as soon as its feeder game is played.
static func entrant(state: TournamentState, game: int, line: int) -> int:
	if game < 0 or game > FINAL:
		return NO_CLUB
	if game < _QUARTERFINAL_COUNT:
		return state.clubs_by_seed[_QUARTERFINAL_SEEDS[game * 2 + line]]
	return winner(state, (game - _QUARTERFINAL_COUNT) * 2 + line)


# The better seed of a game's two clubs: it takes side 0, the home kit and the
# home bench. -1 until both clubs are known.
static func home_club(state: TournamentState, game: int) -> int:
	var upper: int = entrant(state, game, 0)
	var lower: int = entrant(state, game, 1)
	if upper == NO_CLUB or lower == NO_CLUB:
		return NO_CLUB
	return upper if seed_of(state, upper) < seed_of(state, lower) else lower


static func away_club(state: TournamentState, game: int) -> int:
	var home: int = home_club(state, game)
	if home == NO_CLUB:
		return NO_CLUB
	var upper: int = entrant(state, game, 0)
	return entrant(state, game, 1) if home == upper else upper


static func winner(state: TournamentState, game: int) -> int:
	if not state.is_played(game):
		return NO_CLUB
	if state.home_score(game) > state.away_score(game):
		return home_club(state, game)
	return away_club(state, game)


static func champion(state: TournamentState) -> int:
	return winner(state, FINAL)


# The game the player's club plays next, or -1 once it is out or has the cup.
static func player_game(state: TournamentState) -> int:
	for game: int in range(TournamentState.GAME_COUNT):
		if not state.is_played(game) and _has_player(state, game):
			return game
	return NO_GAME


# The latest game the player's club has played, or -1 before its first.
static func last_player_game(state: TournamentState) -> int:
	for game: int in range(FINAL, -1, -1):
		if state.is_played(game) and _has_player(state, game):
			return game
	return NO_GAME


static func status(state: TournamentState) -> Status:
	if player_game(state) != NO_GAME:
		return Status.IN_PROGRESS
	if champion(state) == state.player_club:
		return Status.CHAMPION
	return Status.ELIMINATED


# Writes one game's result. Refused, changing nothing, when the game is already
# played, a club in it is undecided, or the score is level or negative: an
# elimination game has a winner.
static func record(state: TournamentState, game: int, home_score: int, away_score: int,
		overtime: bool) -> bool:
	if game < 0 or game > FINAL or state.is_played(game):
		return false
	if home_club(state, game) == NO_CLUB:
		return false
	if home_score < 0 or away_score < 0 or home_score == away_score:
		return false
	state.set_result(game, home_score, away_score, overtime)
	return true


# Plays out every game of one round that has both clubs and no result, except the
# player's own, which is never simulated.
static func simulate_round(state: TournamentState, round_index: int) -> void:
	if round_index < 0 or round_index >= ROUND_COUNT:
		return
	var first: int = _FIRST_GAME_OF_ROUND[round_index]
	for game: int in range(first, first + _GAMES_IN_ROUND[round_index]):
		if state.is_played(game) or _has_player(state, game):
			continue
		if home_club(state, game) == NO_CLUB:
			continue
		_simulate_game(state, game)


# Plays out everything that can be decided without the player. With the player
# out, that is the rest of the bracket.
static func simulate_to_end(state: TournamentState) -> void:
	for round_index: int in range(ROUND_COUNT):
		simulate_round(state, round_index)


# Whether the bracket `state` describes is a possible one: eight distinct clubs
# with the player's among them, and every result a legal one for a game whose
# feeders were played. A save or a peer's copy that fails this is discarded.
static func is_valid(state: TournamentState) -> bool:
	if state == null or state.clubs_by_seed.size() != TournamentState.CLUB_COUNT:
		return false
	for i: int in range(TournamentState.CLUB_COUNT):
		if state.clubs_by_seed.find(state.clubs_by_seed[i]) != i:
			return false
	if seed_of(state, state.player_club) == -1:
		return false
	for game: int in range(TournamentState.GAME_COUNT):
		if not state.is_played(game):
			continue
		if home_club(state, game) == NO_CLUB:
			return false
		if state.home_score(game) < 0 or state.away_score(game) < 0:
			return false
		if state.home_score(game) == state.away_score(game):
			return false
	return true


static func _has_player(state: TournamentState, game: int) -> bool:
	return entrant(state, game, 0) == state.player_club \
			or entrant(state, game, 1) == state.player_club


# Seeded from the tournament's seed and the game's index alone, so a result
# does not depend on the order games are resolved in.
static func _simulate_game(state: TournamentState, game: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([state.rng_seed, game])
	var home: int = home_club(state, game)
	var seed_gap: int = seed_of(state, away_club(state, game)) - seed_of(state, home)
	var home_wins: bool = rng.randf() < 0.5 + SIM_SEED_EDGE * seed_gap

	var regulation_minutes: float = state.num_periods * state.period_duration / 60.0
	var typical_goals: int = maxi(1, roundi(SIM_GOALS_PER_MINUTE * regulation_minutes))
	var loser_goals: int = rng.randi_range(0, typical_goals)
	var overtime: bool = rng.randf() < SIM_OVERTIME_SHARE
	var margin: int = 1 if overtime else rng.randi_range(1, typical_goals)
	var winner_goals: int = loser_goals + margin
	if home_wins:
		state.set_result(game, winner_goals, loser_goals, overtime)
	else:
		state.set_result(game, loser_goals, winner_goals, overtime)


# Fisher-Yates on the caller's RNG; Array.shuffle draws from the global one and
# would not reproduce.
static func _shuffle(values: Array[int], rng: RandomNumberGenerator) -> void:
	for i: int in range(values.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var held: int = values[i]
		values[i] = values[j]
		values[j] = held
