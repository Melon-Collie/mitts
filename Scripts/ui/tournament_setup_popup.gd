class_name TournamentSetupPopup
extends Control
## Where a tournament is set up: the player picks a club and the match settings
## every game of it will use. Start hands back a draft TournamentState holding
## those; drawing the bracket is the caller's.

signal start_pressed(draft: TournamentState)

const _CLUB_COLUMNS: int = 4
const _CLUB_BUTTON_SIZE: Vector2 = Vector2(150.0, 44.0)
const _CLUB_CREST_PX: float = 30.0

var _draft: TournamentState = null
var _panel: PanelContainer = null
var _club_buttons: Dictionary[int, Button] = {}
var _club_styles: Dictionary[int, StyleBoxFlat] = {}
var _settings_box: VBoxContainer = null
var _start_btn: Button = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	visible = false


# Opens on the player's favorite club and the settings a new lobby would have.
func open() -> void:
	_draft = TournamentState.new()
	_draft.player_club = _favorite_club()
	_draft.team_size = PlayerPrefs.preferred_team_size
	_draft.bot_difficulty = PlayerPrefs.bot_difficulty
	_draft.goalie_difficulty = PlayerPrefs.goalie_difficulty
	_rebuild_settings()
	_refresh_clubs()
	visible = true
	ControllerNav.focus_first(self)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		visible = false
		get_viewport().set_input_as_handled()


func _favorite_club() -> int:
	var clubs: Array[int] = TeamColorRegistry.get_all_slots()
	if clubs.has(PlayerPrefs.preferred_color_slot):
		return PlayerPrefs.preferred_color_slot
	return TeamColorRegistry.DEFAULT_HOME_SLOT


func _build() -> void:
	var scrim := ColorRect.new()
	scrim.color = MenuStyle.SCRIM
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", MenuStyle.panel())
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	_panel.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)
	var title := Label.new()
	title.text = tr(&"TOURNAMENT_NEW")
	MenuStyle.apply_heading(title)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_btn := MenuStyle.close_button()
	close_btn.pressed.connect(func() -> void: visible = false)
	SoundManager.wire_button(close_btn)
	header.add_child(close_btn)

	var note := Label.new()
	note.text = tr(&"TOURNAMENT_SETUP_NOTE")
	note.add_theme_font_size_override("font_size", 14)
	note.add_theme_color_override("font_color", MenuStyle.TEXT_DIM)
	vbox.add_child(note)

	vbox.add_child(_section_header(tr(&"TOURNAMENT_SETUP_CLUB")))
	var grid := GridContainer.new()
	grid.columns = _CLUB_COLUMNS
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(grid)
	for club: int in TeamColorRegistry.get_all_slots():
		grid.add_child(_build_club_button(club))

	vbox.add_child(_section_header(tr(&"TOURNAMENT_SETUP_SETTINGS")))
	_settings_box = VBoxContainer.new()
	vbox.add_child(_settings_box)

	_start_btn = MenuStyle.popup_button(tr(&"TOURNAMENT_SETUP_START"))
	MenuStyle.apply_primary_cta(_start_btn)
	_start_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_start_btn.pressed.connect(_on_start_pressed)
	vbox.add_child(_start_btn)


func _section_header(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", MenuStyle.TEXT_DIM)
	return label


func _build_club_button(club: int) -> Button:
	var style := StyleBoxFlat.new()
	style.bg_color = MenuStyle.SURFACE_ELEV
	style.set_corner_radius_all(4)
	style.set_border_width_all(2)
	style.set_content_margin_all(6)

	var btn := Button.new()
	btn.custom_minimum_size = _CLUB_BUTTON_SIZE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)
	MenuStyle.apply_focus_ring(btn)
	SoundManager.wire_button(btn)
	btn.pressed.connect(_on_club_pressed.bind(club))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(row)
	var crest := ClubCrest.new(_CLUB_CREST_PX, club)
	crest.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(crest)
	var name_label := Label.new()
	name_label.text = TournamentCopy.club_name(club)
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_font_override("font", MenuStyle.NAME_FONT)
	name_label.add_theme_color_override("font_color", MenuStyle.TEXT_BODY)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_label)

	_club_buttons[club] = btn
	_club_styles[club] = style
	return btn


func _refresh_clubs() -> void:
	for club: int in _club_styles:
		_club_styles[club].border_color = MenuStyle.TEAL if club == _draft.player_club \
				else MenuStyle.SURFACE_ELEV


# The panel is rebuilt per open so its controls start from this draft.
func _rebuild_settings() -> void:
	for child: Node in _settings_box.get_children():
		child.queue_free()
	var settings := LobbySettingsPanel.new(_draft.num_periods, _draft.period_duration, true,
			_draft.rule_set, true, _draft.team_size, _draft.bot_difficulty,
			_draft.goalie_difficulty, _draft.fighting, true)
	settings.settings_changed.connect(_on_settings_changed)
	_settings_box.add_child(settings)


func _on_club_pressed(club: int) -> void:
	_draft.player_club = club
	_refresh_clubs()


func _on_settings_changed(num_periods: int, period_duration: float, _ot_enabled: bool,
		rule_set: int, team_size: int, bot_difficulty: int, goalie_difficulty: int,
		fighting: bool) -> void:
	_draft.num_periods = num_periods
	_draft.period_duration = period_duration
	_draft.rule_set = rule_set
	_draft.team_size = team_size
	_draft.bot_difficulty = bot_difficulty
	_draft.goalie_difficulty = goalie_difficulty
	_draft.fighting = fighting


func _on_start_pressed() -> void:
	visible = false
	start_pressed.emit(_draft)
