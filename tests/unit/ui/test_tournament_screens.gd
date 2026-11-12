extends GutTest

# The tournament's screens are built in code, so only running them proves they
# are wired to the bracket: that the panel draws the state it is given, that the
# lobby's tournament mode hands the match the bracket's clubs and settings, that
# the game-over screen drops the rematch, and that setting a tournament up
# leaves the player's own lobby preferences alone.

# Seed index i holds club i, so a club's seed reads off its number.
const _FIELD: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7]
const _PLAYER_CLUB: int = 5  # sixth seed: away to the third in the quarterfinal

var _saved_bot_slots: Dictionary[int, bool] = {}
var _saved_bot_identities: Dictionary[int, Dictionary] = {}
var _saved_roster_side: int = -1
var _saved_roster_game: int = TournamentRules.NO_GAME


func before_each() -> void:
	_saved_bot_slots = NetworkManager.pending_bot_slots
	_saved_bot_identities = NetworkManager.pending_bot_identities
	_saved_roster_side = GameManager.tournament.roster_side
	_saved_roster_game = GameManager.tournament.roster_game
	GameManager.tournament.roster_game = TournamentRules.NO_GAME


func after_each() -> void:
	NetworkManager.pending_bot_slots = _saved_bot_slots
	NetworkManager.pending_bot_identities = _saved_bot_identities
	GameManager.tournament.roster_side = _saved_roster_side
	GameManager.tournament.roster_game = _saved_roster_game


func _state() -> TournamentState:
	var state := TournamentState.new()
	state.rng_seed = 3
	state.clubs_by_seed = _FIELD.duplicate()
	state.player_club = _PLAYER_CLUB
	return state


func _win(state: TournamentState, game: int, club: int) -> void:
	if TournamentRules.home_club(state, game) == club:
		assert_true(TournamentRules.record(state, game, 2, 1, false))
	else:
		assert_true(TournamentRules.record(state, game, 1, 2, false))


# The player's club wins its quarterfinal; the rest of the round is simulated.
func _after_a_win() -> TournamentState:
	var state: TournamentState = _state()
	_win(state, TournamentRules.player_game(state), _PLAYER_CLUB)
	TournamentRules.simulate_round(state, 0)
	return state


func _labels(root: Node) -> Array[String]:
	var texts: Array[String] = []
	for node: Node in root.find_children("*", "Label", true, false):
		texts.append((node as Label).text)
	return texts


# ── BracketPanel ─────────────────────────────────────────────────────────────

func test_the_bracket_names_every_club_of_the_draw() -> void:
	var panel := BracketPanel.new()
	add_child_autofree(panel)
	panel.show_state(_state())
	var texts: Array[String] = _labels(panel)
	for club: int in _FIELD:
		assert_has(texts, TournamentCopy.club_name(club))


func test_the_bracket_names_the_champion_once_there_is_one() -> void:
	var state: TournamentState = _state()
	var panel := BracketPanel.new()
	add_child_autofree(panel)
	panel.show_state(state)
	var champion_label: Label = panel.get("_champion_name") as Label
	assert_eq(champion_label.text, "—")
	_win(state, TournamentRules.player_game(state), _FIELD[2])
	TournamentRules.simulate_to_end(state)
	panel.show_state(state)
	assert_eq(champion_label.text,
			TournamentCopy.club_name(TournamentRules.champion(state)).to_upper())


func test_the_bracket_marks_the_players_club_and_no_other() -> void:
	var state: TournamentState = _after_a_win()
	var panel := BracketPanel.new()
	add_child_autofree(panel)
	panel.show_state(state)
	var lines: Array = panel.get("_lines")
	var marked: int = 0
	for game: int in range(TournamentState.GAME_COUNT):
		for line: int in 2:
			var bar: ColorRect = lines[game * 2 + line].player_bar
			var is_player: bool = TournamentRules.entrant(state, game, line) == _PLAYER_CLUB
			assert_eq(bar.modulate.a, 1.0 if is_player else 0.0)
			marked += 1 if is_player else 0
	assert_eq(marked, 2, "its quarterfinal and the semifinal it reached")


func test_the_bracket_shows_an_overtime_win() -> void:
	var state: TournamentState = _state()
	assert_true(TournamentRules.record(state, 0, 4, 3, true))
	var panel := BracketPanel.new()
	add_child_autofree(panel)
	panel.show_state(state)
	assert_has(_labels(panel), TournamentCopy.t(&"TOURNAMENT_SCORE_OT") % 4)


# ── TournamentCopy ───────────────────────────────────────────────────────────

func test_the_status_line_follows_the_players_tournament() -> void:
	var state: TournamentState = _state()
	var next_game: String = TournamentCopy.status_line(state)
	assert_string_contains(next_game, TournamentCopy.club_name(_FIELD[2]),
			"names the opponent")
	assert_string_contains(next_game, TournamentCopy.round_name(0))
	_win(state, TournamentRules.player_game(state), _FIELD[2])
	assert_string_contains(TournamentCopy.status_line(state),
			TournamentCopy.club_name(_PLAYER_CLUB))
	assert_ne(TournamentCopy.status_line(state), next_game)


func test_the_outcome_line_waits_for_the_result() -> void:
	var state: TournamentState = _state()
	var quarterfinal: int = TournamentRules.player_game(state)
	assert_eq(TournamentCopy.outcome_line(state, quarterfinal), "", "not played yet")
	assert_eq(TournamentCopy.outcome_line(state, TournamentRules.NO_GAME), "")
	_win(state, quarterfinal, _PLAYER_CLUB)
	assert_eq(TournamentCopy.outcome_line(state, quarterfinal),
			TournamentCopy.t(&"TOURNAMENT_ADVANCE") % TournamentCopy.round_name(1))


func test_the_outcome_line_of_a_loss_and_of_the_final() -> void:
	var lost: TournamentState = _state()
	var quarterfinal: int = TournamentRules.player_game(lost)
	_win(lost, quarterfinal, _FIELD[2])
	assert_eq(TournamentCopy.outcome_line(lost, quarterfinal),
			TournamentCopy.t(&"TOURNAMENT_ELIMINATED"))

	var won: TournamentState = _state()
	for game: int in range(TournamentState.GAME_COUNT):
		var player_in_it: bool = TournamentRules.player_game(won) == game
		_win(won, game, _PLAYER_CLUB if player_in_it else TournamentRules.home_club(won, game))
	assert_eq(TournamentRules.status(won), TournamentRules.Status.CHAMPION)
	assert_eq(TournamentCopy.outcome_line(won, TournamentRules.FINAL),
			TournamentCopy.t(&"TOURNAMENT_CHAMPIONS"))


# ── LobbyTournamentMode ──────────────────────────────────────────────────────

func test_the_lower_seed_takes_the_away_side() -> void:
	var mode: LobbyTournamentMode = LobbyTournamentMode.for_state(_state())
	add_child_autofree(mode)
	assert_eq(mode.home_club(), _FIELD[2])
	assert_eq(mode.away_club(), _PLAYER_CLUB)
	assert_eq(mode.club_side(), 1)
	assert_true(mode.may_seat(1))
	assert_true(mode.may_seat(GameRules.SPECTATOR_TEAM_ID))
	assert_false(mode.may_seat(0), "no human sits with the opponent")
	assert_false(mode.is_over())


func test_the_bracket_decides_the_match_config() -> void:
	var state: TournamentState = _state()
	state.team_size = 5
	state.num_periods = 2
	state.period_duration = 120.0
	state.rule_set = GameRules.RuleSet.NHL
	state.fighting = not GameRules.FIGHTING_ENABLED
	var mode: LobbyTournamentMode = LobbyTournamentMode.for_state(state)
	add_child_autofree(mode)
	var config: Dictionary = {"ot_enabled": false, "home_color_slot": 11, "game_id": "kept"}
	mode.apply_to_config(config)
	assert_eq(config["home_color_slot"], _FIELD[2])
	assert_eq(config["away_color_slot"], _PLAYER_CLUB)
	assert_eq(config["team_size"], 5)
	assert_eq(config["num_periods"], 2)
	assert_eq(config["period_duration"], 120.0)
	assert_eq(config["rule_set"], GameRules.RuleSet.NHL)
	assert_eq(config["fighting"], not GameRules.FIGHTING_ENABLED)
	assert_true(config["ot_enabled"], "an elimination game has a winner")
	assert_eq(config["game_id"], "kept")


func test_a_finished_tournament_keeps_showing_its_last_game() -> void:
	var state: TournamentState = _state()
	_win(state, TournamentRules.player_game(state), _FIELD[2])
	var mode: LobbyTournamentMode = LobbyTournamentMode.for_state(state)
	add_child_autofree(mode)
	assert_true(mode.is_over())
	assert_eq(mode.home_club(), _FIELD[2])
	assert_eq(mode.away_club(), _PLAYER_CLUB)


func test_the_clubs_bots_follow_it_to_its_new_side() -> void:
	# Last game the club was on side 0 with bots in slots 1 and 2; an opponent
	# bot sat in side 1's slot 0. This game the club is away, on side 1.
	var teammate_a: int = LobbySlotKey.encode(0, 1)
	var teammate_b: int = LobbySlotKey.encode(0, 2)
	var opponent: int = LobbySlotKey.encode(1, 0)
	NetworkManager.pending_bot_slots = {teammate_a: true, teammate_b: true, opponent: true}
	NetworkManager.pending_bot_identities = {
		teammate_a: {"name": "Dahl"}, teammate_b: {"name": "Pohl"}, opponent: {"name": "Vogel"},
	}
	GameManager.tournament.roster_side = 0
	var mode: LobbyTournamentMode = LobbyTournamentMode.for_state(_state())
	add_child_autofree(mode)
	mode.carry_bot_teammates()
	var moved_a: int = LobbySlotKey.encode(1, 1)
	var moved_b: int = LobbySlotKey.encode(1, 2)
	assert_eq(NetworkManager.pending_bot_slots.size(), 2, "the old opponent is gone")
	assert_true(NetworkManager.pending_bot_slots.get(moved_a, false))
	assert_eq(NetworkManager.pending_bot_identities[moved_a]["name"], "Dahl")
	assert_eq(NetworkManager.pending_bot_identities[moved_b]["name"], "Pohl")
	assert_eq(GameManager.tournament.roster_side, 1)


func test_a_lobby_reopened_on_the_same_game_keeps_every_bot() -> void:
	var teammate: int = LobbySlotKey.encode(1, 1)
	var opponent: int = LobbySlotKey.encode(0, 0)
	NetworkManager.pending_bot_slots = {teammate: true, opponent: true}
	NetworkManager.pending_bot_identities = {teammate: {"name": "Dahl"}, opponent: {"name": "Vogel"}}
	var state: TournamentState = _state()
	GameManager.tournament.roster_side = 1
	GameManager.tournament.roster_game = TournamentRules.player_game(state)
	var mode: LobbyTournamentMode = LobbyTournamentMode.for_state(state)
	add_child_autofree(mode)
	mode.carry_bot_teammates()
	assert_eq(NetworkManager.pending_bot_slots.size(), 2)
	assert_eq(NetworkManager.pending_bot_identities[opponent]["name"], "Vogel",
			"the same opponent keeps its players")


func test_a_sessions_first_lobby_carries_no_bots() -> void:
	NetworkManager.pending_bot_slots = {LobbySlotKey.encode(0, 1): true}
	NetworkManager.pending_bot_identities = {LobbySlotKey.encode(0, 1): {"name": "Dahl"}}
	GameManager.tournament.roster_side = -1
	var mode: LobbyTournamentMode = LobbyTournamentMode.for_state(_state())
	add_child_autofree(mode)
	mode.carry_bot_teammates()
	assert_true(NetworkManager.pending_bot_slots.is_empty())
	assert_true(NetworkManager.pending_bot_identities.is_empty())


# ── GameOverPopup ────────────────────────────────────────────────────────────

func test_a_tournament_game_has_no_rematch() -> void:
	var popup := GameOverPopup.new()
	add_child_autofree(popup)
	var rematch: Button = popup.get("_rematch_btn") as Button
	var lobby: Button = popup.get("_lobby_btn") as Button
	var outcome: Label = popup.get("_tournament_label") as Label
	var outcome_row: Control = popup.get("_tournament_row") as Control
	assert_true(rematch.visible)
	assert_false(outcome_row.visible)

	popup.set_tournament(true, "")
	assert_false(rematch.visible, "no rematch even before the result is in")
	assert_false(outcome_row.visible)

	popup.set_tournament(true, "Advance to the Semifinal")
	assert_false(rematch.visible)
	assert_true(outcome_row.visible)
	assert_eq(outcome.text, "Advance to the Semifinal")
	assert_false((popup.get("_cup_crest") as Control).visible, "an ordinary round has no crest")
	assert_eq(lobby.text, tr(&"GAME_OVER_CONTINUE"))
	var votes: Dictionary[int, int] = {}
	popup.update_votes(votes, 1, RematchVoteRules.Choice.NONE)
	assert_eq(lobby.text, tr(&"GAME_OVER_CONTINUE"), "a tally refresh keeps the wording")

	popup.set_tournament(false, "")
	assert_true(rematch.visible, "the next ordinary game gets its rematch back")
	assert_false(outcome_row.visible)
	assert_eq(lobby.text, tr(&"GAME_OVER_RETURN_LOBBY"))


func test_winning_the_cup_shows_the_clubs_crest_in_gold() -> void:
	var popup := GameOverPopup.new()
	add_child_autofree(popup)
	var crest: ClubCrest = popup.get("_cup_crest") as ClubCrest
	var outcome: Label = popup.get("_tournament_label") as Label
	popup.set_tournament(true, "Champions", _PLAYER_CLUB)
	assert_true(crest.visible)
	assert_eq(outcome.text, "CHAMPIONS", "lettered like the headline it sits under")
	assert_eq(crest.get("_club"), _PLAYER_CLUB)
	assert_eq(outcome.get_theme_color("font_color"), MenuStyle.GOLD)
	popup.set_tournament(true, "Eliminated")
	assert_false(crest.visible, "the next tournament game starts plain")
	assert_ne(outcome.get_theme_color("font_color"), MenuStyle.GOLD)


func test_the_matchup_intro_names_the_round_and_the_clubs() -> void:
	var overlay := MatchupIntroOverlay.new()
	add_child_autofree(overlay)
	var no_one: Array[PlayerRecord] = []
	var state: TournamentState = _state()
	var game: int = TournamentRules.player_game(state)
	overlay.present(no_one, no_one, Color.RED, Color.BLUE, TournamentCopy.intro_title(game),
			TournamentCopy.seeded_club(state, _FIELD[2]),
			TournamentCopy.seeded_club(state, _PLAYER_CLUB))
	var texts: Array[String] = _labels(overlay)
	assert_has(texts, TournamentCopy.t(&"TOURNAMENT_INTRO_TITLE")
			% TournamentCopy.round_name(0).to_upper())
	assert_has(texts, "#3 " + TournamentCopy.club_name(_FIELD[2]).to_upper())
	assert_has(texts, "#6 " + TournamentCopy.club_name(_PLAYER_CLUB).to_upper())

	overlay.present(no_one, no_one, Color.RED, Color.BLUE)
	texts = _labels(overlay)
	assert_has(texts, tr(&"MATCHUP_TITLE"), "an ordinary game gets the ordinary title back")
	assert_has(texts, tr(&"TEAM_HOME"))
	assert_has(texts, tr(&"TEAM_AWAY"))


func test_a_spectator_of_a_tournament_game_still_has_no_vote() -> void:
	var popup := GameOverPopup.new()
	add_child_autofree(popup)
	popup.set_tournament(true, "Eliminated")
	popup.set_spectator(true)
	assert_false((popup.get("_rematch_btn") as Button).visible)
	assert_false((popup.get("_lobby_btn") as Button).visible)
	popup.set_spectator(false)
	assert_false((popup.get("_rematch_btn") as Button).visible)
	assert_true((popup.get("_lobby_btn") as Button).visible)


# ── Setting one up ───────────────────────────────────────────────────────────

func test_setup_hands_back_the_club_and_settings_picked() -> void:
	var popup := TournamentSetupPopup.new()
	add_child_autofree(popup)
	popup.open()
	assert_true(popup.visible)
	watch_signals(popup)
	var clubs: Dictionary = popup.get("_club_buttons")
	(clubs[7] as Button).pressed.emit()
	var settings: LobbySettingsPanel = (popup.get("_settings_box") as Node).get_child(0)
	settings.call("_on_bot_difficulty_selected", BotSkillProfile.Difficulty.HARD)
	(popup.get("_start_btn") as Button).pressed.emit()
	assert_false(popup.visible)
	assert_signal_emitted(popup, "start_pressed")
	var draft: TournamentState = get_signal_parameters(popup, "start_pressed")[0]
	assert_eq(draft.player_club, 7)
	assert_eq(draft.bot_difficulty, BotSkillProfile.Difficulty.HARD)
	assert_eq(draft.team_size, PlayerPrefs.preferred_team_size)


func test_a_tournaments_difficulty_leaves_the_lobby_preference_alone() -> void:
	var before: int = PlayerPrefs.bot_difficulty
	var pick: int = (before + 1) % PlayerPrefs.BOT_DIFFICULTY_LABELS.size()
	var panel := LobbySettingsPanel.new(3, 240.0, true, GameRules.DEFAULT_RULE_SET, true,
			GameRules.DEFAULT_TEAM_SIZE, before, PlayerPrefs.goalie_difficulty,
			GameRules.FIGHTING_ENABLED, true)
	add_child_autofree(panel)
	watch_signals(panel)
	panel.call("_on_bot_difficulty_selected", pick)
	assert_eq(PlayerPrefs.bot_difficulty, before)
	assert_signal_emitted(panel, "settings_changed")
	assert_eq(get_signal_parameters(panel, "settings_changed")[5], pick)


func test_a_tournament_offers_no_overtime_switch() -> void:
	var panel := LobbySettingsPanel.new(3, 240.0, true, GameRules.DEFAULT_RULE_SET, true,
			GameRules.DEFAULT_TEAM_SIZE, 0, 0, GameRules.FIGHTING_ENABLED, true)
	add_child_autofree(panel)
	var overtime: CheckButton = panel.get("_ot_check") as CheckButton
	assert_false(overtime.is_visible_in_tree())
