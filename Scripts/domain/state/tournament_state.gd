class_name TournamentState
extends RefCounted
## One tournament's stored facts: the draw, the match settings latched when it
## was created, and the score of every game played. Who advanced, the current
## round and the champion are read off the results by TournamentRules and never
## stored. `to_dict` is both the save format and the wire format.

const VERSION: int = 1
const CLUB_COUNT: int = 8
const GAME_COUNT: int = 7
const UNPLAYED: int = -1

# Drew the field and the seeds, and seeds every simulated game.
var rng_seed: int = 0
# Club slot (TeamColorRegistry) per seed, index 0 = first seed.
var clubs_by_seed: Array[int] = []
var player_club: int = -1

var team_size: int = GameRules.DEFAULT_TEAM_SIZE
var num_periods: int = GameRules.NUM_PERIODS
var period_duration: float = GameRules.PERIOD_DURATION  # seconds
var rule_set: int = GameRules.DEFAULT_RULE_SET
var fighting: bool = GameRules.FIGHTING_ENABLED
var bot_difficulty: int = BotSkillProfile.Difficulty.NORMAL
var goalie_difficulty: int = GoalieSkillProfile.Difficulty.NORMAL

# Indexed by game in bracket order (TournamentRules). Home and away are the
# game's clubs as TournamentRules.home_club / away_club name them.
var _home_scores: Array[int] = []
var _away_scores: Array[int] = []
var _overtime: Array[bool] = []


func _init() -> void:
	for _game: int in range(GAME_COUNT):
		_home_scores.append(UNPLAYED)
		_away_scores.append(UNPLAYED)
		_overtime.append(false)


func is_played(game: int) -> bool:
	return game >= 0 and game < GAME_COUNT and _home_scores[game] != UNPLAYED


func home_score(game: int) -> int:
	return _home_scores[game] if is_played(game) else UNPLAYED


func away_score(game: int) -> int:
	return _away_scores[game] if is_played(game) else UNPLAYED


func went_to_overtime(game: int) -> bool:
	return is_played(game) and _overtime[game]


# A raw write: whether the result is a legal one for this bracket is
# TournamentRules.record's question.
func set_result(game: int, home: int, away: int, overtime: bool) -> void:
	if game < 0 or game >= GAME_COUNT:
		return
	_home_scores[game] = home
	_away_scores[game] = away
	_overtime[game] = overtime


func to_dict() -> Dictionary:
	var results: Array = []
	for game: int in range(GAME_COUNT):
		if is_played(game):
			results.append([_home_scores[game], _away_scores[game], _overtime[game]])
		else:
			results.append([])
	return {
		"version": VERSION,
		"rng_seed": rng_seed,
		"clubs_by_seed": clubs_by_seed.duplicate(),
		"player_club": player_club,
		"team_size": team_size,
		"num_periods": num_periods,
		"period_duration": period_duration,
		"rule_set": rule_set,
		"fighting": fighting,
		"bot_difficulty": bot_difficulty,
		"goalie_difficulty": goalie_difficulty,
		"results": results,
	}


# Reads what a prefs file or a peer sent. Returns null for anything that is not
# a tournament of this version and shape; whether the bracket it describes is a
# possible one is TournamentRules.is_valid's question.
static func from_variant(value: Variant) -> TournamentState:
	if not value is Dictionary:
		return null
	var raw: Dictionary = value
	if not _is_number(raw.get("version")) or int(raw["version"]) != VERSION:
		return null
	var clubs: Variant = raw.get("clubs_by_seed")
	var results: Variant = raw.get("results")
	if not clubs is Array or (clubs as Array).size() != CLUB_COUNT:
		return null
	if not results is Array or (results as Array).size() != GAME_COUNT:
		return null

	var state := TournamentState.new()
	for club: Variant in (clubs as Array):
		if not _is_number(club):
			return null
		state.clubs_by_seed.append(int(club))
	for game: int in range(GAME_COUNT):
		var entry: Variant = (results as Array)[game]
		if not entry is Array:
			return null
		var result: Array = entry
		if result.is_empty():
			continue
		if result.size() != 3 or not _is_number(result[0]) or not _is_number(result[1]):
			return null
		state.set_result(game, int(result[0]), int(result[1]), bool(result[2]))

	state.rng_seed = int(raw.get("rng_seed", 0))
	state.player_club = int(raw.get("player_club", -1))
	state.team_size = int(raw.get("team_size", state.team_size))
	state.num_periods = int(raw.get("num_periods", state.num_periods))
	state.period_duration = float(raw.get("period_duration", state.period_duration))
	state.rule_set = int(raw.get("rule_set", state.rule_set))
	state.fighting = bool(raw.get("fighting", state.fighting))
	state.bot_difficulty = int(raw.get("bot_difficulty", state.bot_difficulty))
	state.goalie_difficulty = int(raw.get("goalie_difficulty", state.goalie_difficulty))
	return state


static func _is_number(value: Variant) -> bool:
	return value is int or value is float
