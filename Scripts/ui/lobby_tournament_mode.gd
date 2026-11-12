class_name LobbyTournamentMode
extends Node
## What the lobby does differently while the session is a tournament: the
## bracket picks the two clubs and the match settings, humans sit only on the
## player's side, and the opponent is always a full team of bots. LobbyManager
## asks; this never touches the lobby's own state.

var _state: TournamentState = null
# The game this lobby is for: the player's next, or their last once it is over.
var _game: int = TournamentRules.NO_GAME
var _overlay: BracketOverlay = null


# Null outside a tournament.
static func for_session() -> LobbyTournamentMode:
	if not GameManager.tournament.is_active():
		return null
	return for_state(GameManager.tournament.active)


static func for_state(tournament: TournamentState) -> LobbyTournamentMode:
	var mode := LobbyTournamentMode.new()
	mode._state = tournament
	mode._game = TournamentRules.player_game(mode._state)
	if mode._game == TournamentRules.NO_GAME:
		mode._game = TournamentRules.last_player_game(mode._state)
	return mode


func _ready() -> void:
	_overlay = BracketOverlay.new()
	add_child(_overlay)


# No game left to play: the player's club is out or has the cup.
func is_over() -> bool:
	return TournamentRules.player_game(_state) == TournamentRules.NO_GAME


func state() -> TournamentState:
	return _state


func home_club() -> int:
	return TournamentRules.home_club(_state, _game)


func away_club() -> int:
	return TournamentRules.away_club(_state, _game)


# The side the player's club takes: 0 at home, 1 away.
func club_side() -> int:
	return 0 if home_club() == _state.player_club else 1


func may_seat(team_id: int) -> bool:
	return team_id == club_side() or team_id == GameRules.SPECTATOR_TEAM_ID


func header_text() -> String:
	if is_over():
		return tr(&"TOURNAMENT_TITLE")
	return tr(&"TOURNAMENT_LOBBY_TITLE") % TournamentCopy.round_name(TournamentRules.round_of(_game))


func open_bracket(background: Control) -> void:
	_overlay.open(_state, background)


# Overwrites the parts of a game-start config the bracket decides. Overtime is
# forced on: an elimination game has a winner.
func apply_to_config(config: Dictionary) -> void:
	config["home_color_slot"] = home_club()
	config["away_color_slot"] = away_club()
	config["num_periods"] = _state.num_periods
	config["period_duration"] = _state.period_duration
	config["ot_enabled"] = true
	config["rule_set"] = _state.rule_set
	config["team_size"] = _state.team_size
	config["fighting"] = _state.fighting


# Host. The bots seated on the player's side keep their seats, moved to the side
# the club has now, so its line stays together through the cup; every other bot
# seat is emptied for the new opponent. The caller refills the open seats.
func carry_bot_teammates() -> void:
	var coordinator: TournamentCoordinator = GameManager.tournament
	var side: int = club_side()
	var slots: Dictionary[int, bool] = {}
	var identities: Dictionary[int, Dictionary] = {}
	for key: int in NetworkManager.pending_bot_slots:
		if LobbySlotKey.team_id(key) != coordinator.roster_side:
			continue
		var moved: int = LobbySlotKey.encode(side, LobbySlotKey.slot(key))
		slots[moved] = true
		if NetworkManager.pending_bot_identities.has(key):
			identities[moved] = NetworkManager.pending_bot_identities[key]
	NetworkManager.pending_bot_slots = slots
	NetworkManager.pending_bot_identities = identities
	coordinator.roster_side = side


# The lobby tray's first column: who plays whom, and the way to the bracket.
func build_matchup_column(header: Label, background: Control) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(header)
	column.add_child(_club_row(tr(&"TEAM_AWAY"), away_club()))
	column.add_child(_club_row(tr(&"TEAM_HOME"), home_club()))
	var bracket_btn := Button.new()
	bracket_btn.text = tr(&"TOURNAMENT_BRACKET")
	bracket_btn.custom_minimum_size = Vector2(120, 32)
	bracket_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	MenuStyle.wire_hover_scale(bracket_btn)
	SoundManager.wire_button(bracket_btn)
	MenuStyle.apply_focus_ring(bracket_btn)
	bracket_btn.pressed.connect(open_bracket.bind(background))
	column.add_child(bracket_btn)
	return column


func _club_row(side_label: String, club: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var side := Label.new()
	side.text = side_label
	side.add_theme_font_size_override("font_size", 12)
	side.add_theme_color_override("font_color", MenuStyle.TEXT_DIM)
	side.custom_minimum_size = Vector2(72, 0)
	row.add_child(side)
	var bar: ColorRect = BracketPanel.player_bar()
	bar.modulate.a = 1.0 if club == _state.player_club else 0.0
	row.add_child(bar)
	var crest := ClubCrest.new(26.0, club)
	crest.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(crest)
	var seed_label := Label.new()
	seed_label.text = "#%d" % (TournamentRules.seed_of(_state, club) + 1)
	seed_label.add_theme_font_size_override("font_size", 13)
	seed_label.add_theme_color_override("font_color", MenuStyle.TEXT_MUTED)
	row.add_child(seed_label)
	var name_label := Label.new()
	name_label.text = TournamentCopy.club_name(club).to_upper()
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_font_override("font", MenuStyle.NAME_FONT)
	name_label.add_theme_color_override("font_color", MenuStyle.TEXT_BODY)
	row.add_child(name_label)
	return row
