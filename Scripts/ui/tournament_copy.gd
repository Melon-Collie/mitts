class_name TournamentCopy
## The words for a tournament, shared by the Play popup, the lobby, the bracket
## and the game-over screen. Static, so it translates through TranslationServer
## rather than tr().


static func t(key: StringName) -> String:
	return String(TranslationServer.translate(key))


static func round_name(round_index: int) -> String:
	return t(TournamentRules.round_name_key(round_index))


static func club_name(club: int) -> String:
	return TeamColorRegistry.get_preset_name(club)


# Where the player's tournament stands: the game they play next, or how it ended.
static func status_line(state: TournamentState) -> String:
	var player: String = club_name(state.player_club)
	match TournamentRules.status(state):
		TournamentRules.Status.CHAMPION:
			return t(&"TOURNAMENT_WON") % player
		TournamentRules.Status.ELIMINATED:
			var exit_round: int = TournamentRules.round_of(TournamentRules.last_player_game(state))
			return t(&"TOURNAMENT_LOST") % [player, round_name(exit_round)]
	var game: int = TournamentRules.player_game(state)
	var opponent: int = TournamentRules.away_club(state, game) \
			if TournamentRules.home_club(state, game) == state.player_club \
			else TournamentRules.home_club(state, game)
	return t(&"TOURNAMENT_NEXT_GAME") % [round_name(TournamentRules.round_of(game)),
			club_name(opponent)]


# What `game`'s result did to the player's tournament. Empty until that result
# is in the bracket, which on a client is when the host's copy arrives.
static func outcome_line(state: TournamentState, game: int) -> String:
	if not state.is_played(game):
		return ""
	if TournamentRules.winner(state, game) != state.player_club:
		return t(&"TOURNAMENT_ELIMINATED")
	if game == TournamentRules.FINAL:
		return t(&"TOURNAMENT_CHAMPIONS")
	return t(&"TOURNAMENT_ADVANCE") % round_name(TournamentRules.round_of(game) + 1)
