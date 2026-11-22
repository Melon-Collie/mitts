class_name MatchConfig
extends RefCounted

# What a dedicated server is started with: one match's rules and who sits where
# (docs/dedicated-server-plan.md). Read from JSON a backend wrote, so enums go
# by name and a SteamID goes as a string: a SteamID64 is past the 2^53 a JSON
# number holds exactly.

class Seat extends RefCounted:
	var team_id: int = 0
	var team_slot: int = 0
	# 0 for a bot.
	var steam_id: int = 0

	func is_bot() -> bool:
		return steam_id == 0

	func slot_key() -> int:
		return LobbySlotKey.encode(team_id, team_slot)


const _RULE_SETS: Dictionary[String, int] = {
	"off": GameRules.RuleSet.OFF,
	"arcade": GameRules.RuleSet.ARCADE,
	"nhl": GameRules.RuleSet.NHL,
}
# Bots and goalies share the three names; their enums are held equal by
# test_match_config.gd.
const _DIFFICULTIES: Dictionary[String, int] = {
	"easy": BotSkillProfile.Difficulty.EASY,
	"normal": BotSkillProfile.Difficulty.NORMAL,
	"hard": BotSkillProfile.Difficulty.HARD,
}

# Empty until the server mints one.
var game_id: String = ""
var team_size: int = GameRules.DEFAULT_TEAM_SIZE
var rule_set: int = GameRules.DEFAULT_RULE_SET
var num_periods: int = GameRules.NUM_PERIODS
var period_duration: float = GameRules.PERIOD_DURATION
var ot_enabled: bool = GameRules.OT_ENABLED
var ot_duration: float = GameRules.OT_DURATION
var fighting: bool = GameRules.FIGHTING_ENABLED
var bot_difficulty: int = BotSkillProfile.Difficulty.NORMAL
var goalie_difficulty: int = GoalieSkillProfile.Difficulty.NORMAL
var home_color_slot: int = TeamColorRegistry.DEFAULT_HOME_SLOT
var away_color_slot: int = TeamColorRegistry.DEFAULT_AWAY_SLOT
var seats: Array[Seat] = []

# What is wrong with the source this was read from; "" when nothing is.
var _problem: String = ""


# Reads a config, taking the default for any key that is absent. A key that is
# present and wrong is a problem(), never a silent default: a server that
# started the wrong match would report nothing.
static func from_dict(d: Dictionary) -> MatchConfig:
	var c := MatchConfig.new()
	c.game_id = str(d.get("game_id", ""))
	c.team_size = int(d.get("team_size", c.team_size))
	c.num_periods = int(d.get("num_periods", c.num_periods))
	c.period_duration = float(d.get("period_duration", c.period_duration))
	c.ot_enabled = bool(d.get("ot_enabled", c.ot_enabled))
	c.ot_duration = float(d.get("ot_duration", c.ot_duration))
	c.fighting = bool(d.get("fighting", c.fighting))
	c.home_color_slot = int(d.get("home_color_slot", c.home_color_slot))
	c.away_color_slot = int(d.get("away_color_slot", c.away_color_slot))
	c.rule_set = c._named(d, "rule_set", _RULE_SETS, c.rule_set)
	c.bot_difficulty = c._named(d, "bot_difficulty", _DIFFICULTIES, c.bot_difficulty)
	c.goalie_difficulty = c._named(d, "goalie_difficulty", _DIFFICULTIES, c.goalie_difficulty)
	var listed: Variant = d.get("seats", [])
	if listed is Array:
		for entry: Variant in listed as Array:
			c._read_seat(entry)
	else:
		c._note("seats is not a list")
	if bool(d.get("fill_bots", false)):
		c._fill_open_seats_with_bots()
	c._check()
	return c


static func from_json(text: String) -> MatchConfig:
	# The instance parser returns its error; JSON.parse_string logs one.
	var json := JSON.new()
	if json.parse(text) == OK and json.data is Dictionary:
		return from_dict(json.data as Dictionary)
	return unusable("the config is not a JSON object")


# A config that could not be read at all, carrying why.
static func unusable(why: String) -> MatchConfig:
	var c := MatchConfig.new()
	c._note(why)
	return c


func problem() -> String:
	return _problem


func bot_seats() -> Array[Seat]:
	var out: Array[Seat] = []
	for seat: Seat in seats:
		if seat.is_bot():
			out.append(seat)
	return out


func human_seats() -> Array[Seat]:
	var out: Array[Seat] = []
	for seat: Seat in seats:
		if not seat.is_bot():
			out.append(seat)
	return out


# The dictionary a match start carries (NetworkManager.send_game_start).
func to_game_start() -> Dictionary:
	return {
		"num_periods": num_periods,
		"period_duration": period_duration,
		"ot_enabled": ot_enabled,
		"ot_duration": ot_duration,
		"home_color_slot": home_color_slot,
		"away_color_slot": away_color_slot,
		"rule_set": rule_set,
		"team_size": team_size,
		"fighting": fighting,
		"game_id": game_id,
	}


func _named(d: Dictionary, key: String, names: Dictionary[String, int], fallback: int) -> int:
	if not d.has(key):
		return fallback
	var given: String = str(d[key]).to_lower()
	if names.has(given):
		return names[given]
	_note("%s '%s' is not one of %s" % [key, d[key], ", ".join(names.keys())])
	return fallback


func _read_seat(entry: Variant) -> void:
	if not entry is Dictionary:
		_note("a seat is not an object")
		return
	var e: Dictionary = entry
	if not e.has("team") or not e.has("slot"):
		_note("a seat names no team or no slot")
		return
	var seat := Seat.new()
	seat.team_id = int(e.team)
	seat.team_slot = int(e.slot)
	var is_bot: bool = bool(e.get("bot", false))
	if not is_bot:
		# to_int reads the digits; int() of a String would go through a float.
		seat.steam_id = str(e.get("steam_id", "")).to_int()
		if seat.steam_id <= 0:
			_note("seat %d/%d is neither a bot nor a SteamID" % [seat.team_id, seat.team_slot])
			return
	seats.append(seat)


func _fill_open_seats_with_bots() -> void:
	var taken: Dictionary[int, bool] = {}
	for seat: Seat in seats:
		taken[seat.slot_key()] = true
	for team_id: int in 2:
		for team_slot: int in clampi(team_size, 0, PlayerRules.MAX_PER_TEAM):
			if taken.has(LobbySlotKey.encode(team_id, team_slot)):
				continue
			var seat := Seat.new()
			seat.team_id = team_id
			seat.team_slot = team_slot
			seats.append(seat)


func _check() -> void:
	if not team_size in GameRules.TEAM_SIZE_OPTIONS:
		_note("team_size %d is not one of %s" % [team_size, GameRules.TEAM_SIZE_OPTIONS])
	if num_periods < 1:
		_note("num_periods is below 1")
	if period_duration <= 0.0:
		_note("period_duration is not positive")
	if ot_enabled and ot_duration <= 0.0:
		_note("ot_duration is not positive")
	var seen_seats: Dictionary[int, bool] = {}
	var seen_players: Dictionary[int, bool] = {}
	for seat: Seat in seats:
		if seat.team_id < 0 or seat.team_id > 1 or seat.team_slot < 0 \
				or seat.team_slot >= team_size:
			_note("seat %d/%d is not on a %dv%d sheet" % [
					seat.team_id, seat.team_slot, team_size, team_size])
			continue
		if seen_seats.has(seat.slot_key()):
			_note("seat %d/%d is listed twice" % [seat.team_id, seat.team_slot])
		seen_seats[seat.slot_key()] = true
		if seat.is_bot():
			continue
		if seen_players.has(seat.steam_id):
			_note("SteamID %d holds two seats" % seat.steam_id)
		seen_players[seat.steam_id] = true


# Keeps the first problem: the later ones usually follow from it.
func _note(what: String) -> void:
	if _problem.is_empty():
		_problem = what
