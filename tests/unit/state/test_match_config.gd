extends GutTest

# MatchConfig: what a dedicated server is started with.


func test_an_empty_config_is_the_lobbys_defaults() -> void:
	var c: MatchConfig = MatchConfig.from_dict({})
	assert_eq(c.problem(), "")
	assert_eq(c.team_size, GameRules.DEFAULT_TEAM_SIZE)
	assert_eq(c.rule_set, GameRules.DEFAULT_RULE_SET)
	assert_eq(c.num_periods, GameRules.NUM_PERIODS)
	assert_eq(c.period_duration, GameRules.PERIOD_DURATION)
	assert_eq(c.ot_enabled, GameRules.OT_ENABLED)
	assert_eq(c.fighting, GameRules.FIGHTING_ENABLED)
	assert_eq(c.bot_difficulty, BotSkillProfile.Difficulty.NORMAL)
	assert_eq(c.goalie_difficulty, GoalieSkillProfile.Difficulty.NORMAL)
	assert_eq(c.seats.size(), 0, "no seat is filled unless the config says so")


func test_enums_are_read_by_name() -> void:
	var c: MatchConfig = MatchConfig.from_dict({
		"rule_set": "NHL", "bot_difficulty": "hard", "goalie_difficulty": "Easy",
	})
	assert_eq(c.problem(), "")
	assert_eq(c.rule_set, GameRules.RuleSet.NHL)
	assert_eq(c.bot_difficulty, BotSkillProfile.Difficulty.HARD)
	assert_eq(c.goalie_difficulty, GoalieSkillProfile.Difficulty.EASY)


func test_every_rule_set_has_a_name() -> void:
	for value: int in GameRules.RuleSet.values():
		var by_name: String = GameRules.RULE_SET_NAMES[value]
		var c: MatchConfig = MatchConfig.from_dict({"rule_set": by_name})
		assert_eq(c.problem(), "", "rule set %s" % by_name)
		assert_eq(c.rule_set, value)


# One name table serves both, so the two enums must agree value for value.
func test_bot_and_goalie_difficulties_share_their_values() -> void:
	assert_eq(BotSkillProfile.Difficulty.keys(), GoalieSkillProfile.Difficulty.keys())
	assert_eq(BotSkillProfile.Difficulty.values(), GoalieSkillProfile.Difficulty.values())
	for key: String in BotSkillProfile.Difficulty.keys():
		var c: MatchConfig = MatchConfig.from_dict({"bot_difficulty": key})
		assert_eq(c.problem(), "", "difficulty %s" % key)
		assert_eq(c.bot_difficulty, BotSkillProfile.Difficulty[key])


func test_a_steam_id_survives_as_a_string() -> void:
	# Past 2^53, where a JSON number has already lost its last digits.
	var c: MatchConfig = MatchConfig.from_json(
			'{"seats": [{"team": 1, "slot": 2, "steam_id": "76561198012345679"}]}')
	assert_eq(c.problem(), "")
	assert_eq(c.human_seats().size(), 1)
	assert_eq(c.human_seats()[0].steam_id, 76561198012345679)
	assert_eq(c.human_seats()[0].team_id, 1)
	assert_eq(c.human_seats()[0].team_slot, 2)
	assert_eq(c.bot_seats().size(), 0)


func test_fill_bots_takes_every_seat_nobody_holds() -> void:
	var c: MatchConfig = MatchConfig.from_dict({
		"team_size": 5, "fill_bots": true,
		"seats": [{"team": 0, "slot": 0, "steam_id": "76561198000000001"}],
	})
	assert_eq(c.problem(), "")
	assert_eq(c.seats.size(), 10)
	assert_eq(c.human_seats().size(), 1)
	assert_eq(c.bot_seats().size(), 9)
	for seat: MatchConfig.Seat in c.bot_seats():
		assert_false(seat.team_id == 0 and seat.team_slot == 0, "the human's seat stays his")


func test_without_fill_bots_an_unlisted_seat_stays_empty() -> void:
	var c: MatchConfig = MatchConfig.from_dict({
		"team_size": 3, "seats": [{"team": 0, "slot": 1, "bot": true}],
	})
	assert_eq(c.problem(), "")
	assert_eq(c.seats.size(), 1)
	assert_true(c.seats[0].is_bot())
	assert_eq(c.seats[0].slot_key(), LobbySlotKey.encode(0, 1))


func test_the_game_start_carries_the_rules() -> void:
	var c: MatchConfig = MatchConfig.from_dict({
		"game_id": "abc", "team_size": 5, "rule_set": "nhl", "num_periods": 2,
		"period_duration": 90.0, "ot_enabled": false, "fighting": false,
	})
	var start: Dictionary = c.to_game_start()
	assert_eq(start.game_id, "abc")
	assert_eq(start.team_size, 5)
	assert_eq(start.rule_set, GameRules.RuleSet.NHL)
	assert_eq(start.num_periods, 2)
	assert_eq(start.period_duration, 90.0)
	assert_false(start.ot_enabled)
	assert_false(start.fighting)
	assert_has(start, "ot_duration")
	assert_has(start, "home_color_slot")
	assert_has(start, "away_color_slot")


func test_a_wrong_value_is_a_problem_not_a_default() -> void:
	var cases: Dictionary[String, Dictionary] = {
		"an unknown rule set": {"rule_set": "beer league"},
		"an unknown difficulty": {"bot_difficulty": "impossible"},
		"a team size nobody plays": {"team_size": 4},
		"no periods": {"num_periods": 0},
		"a period of no length": {"period_duration": 0.0},
		"a seat off the sheet": {"team_size": 3, "seats": [{"team": 0, "slot": 3, "bot": true}]},
		"a third team": {"seats": [{"team": 2, "slot": 0, "bot": true}]},
		"a seat listed twice": {"seats": [
			{"team": 0, "slot": 0, "bot": true}, {"team": 0, "slot": 0, "bot": true}]},
		"a player in two seats": {"seats": [
			{"team": 0, "slot": 0, "steam_id": "76561198000000001"},
			{"team": 1, "slot": 0, "steam_id": "76561198000000001"}]},
		"a seat that is nobody": {"seats": [{"team": 0, "slot": 0}]},
		"a seat with no slot": {"seats": [{"team": 0, "bot": true}]},
		"seats that are not a list": {"seats": "all of them"},
	}
	for what: String in cases:
		assert_ne(MatchConfig.from_dict(cases[what]).problem(), "", what)


func test_text_that_is_not_an_object_is_a_problem() -> void:
	assert_ne(MatchConfig.from_json("").problem(), "")
	assert_ne(MatchConfig.from_json("[1, 2]").problem(), "")
	assert_ne(MatchConfig.from_json("{not json").problem(), "")


func test_an_unusable_config_says_why() -> void:
	assert_eq(MatchConfig.unusable("no file at x").problem(), "no file at x")
