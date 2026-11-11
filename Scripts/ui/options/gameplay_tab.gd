class_name OptionsGameplayTab
extends OptionsTab

# Gameplay tab — general/gameplay toggles, plus the "Customization" section
# (editable copies of the team colors and bot roster) and the data-sharing
# "Privacy" section.

var _locale_btn: OptionButton = null
var _attack_up_check: CheckButton = null
var _self_beacon_mode_btn: OptionButton = null
var _carrier_ring_check: CheckButton = null
var _possession_pulse_check: CheckButton = null
var _loose_halo_check: CheckButton = null
var _freeplay_goalie_btn: OptionButton = null
var _share_stats_check: CheckButton = null
var _colors_file: CustomDataFile = null
var _bots_file: CustomDataFile = null

func _build_content() -> void:
	add_child(_section_header("General"))

	# UI language. Index 0 is "System default" (empty stored code → follow the OS
	# language); items 1.. are the shipped locales, each named in itself. Takes
	# effect on Apply; freshly-built UI picks it up on next open — see
	# LocaleManager / PlayerPrefs.apply_locale.
	_locale_btn = OptionButton.new()
	_locale_btn.custom_minimum_size = Vector2(160, 40)
	_locale_btn.add_theme_font_size_override("font_size", 15)
	_locale_btn.add_item("System default")
	for entry: Dictionary in LocaleManager.SUPPORTED:
		_locale_btn.add_item(entry["native_name"])
	_locale_btn.selected = 0 if PlayerPrefs.locale == "" \
		else LocaleManager.index_of(PlayerPrefs.locale) + 1
	SoundManager.wire_button(_locale_btn)
	_locale_btn.item_selected.connect(func(_i: int) -> void: _notify_changed())
	add_child(_field_row("Language", _locale_btn))

	add_child(_section_spacer())
	add_child(_section_header("Gameplay"))

	_attack_up_check = CheckButton.new()
	_attack_up_check.set_pressed_no_signal(PlayerPrefs.attack_up)
	SoundManager.wire_button(_attack_up_check)
	_attack_up_check.toggled.connect(func(_p: bool) -> void: _notify_changed())
	add_child(_field_row("Always Attack Up", _attack_up_check))

	_self_beacon_mode_btn = OptionButton.new()
	_self_beacon_mode_btn.custom_minimum_size = Vector2(160, 40)
	_self_beacon_mode_btn.add_theme_font_size_override("font_size", 15)
	for i: int in PlayerPrefs.BEACON_MODE_LABELS.size():
		_self_beacon_mode_btn.add_item(PlayerPrefs.BEACON_MODE_LABELS[i], i)
	_self_beacon_mode_btn.selected = PlayerPrefs.self_beacon_mode
	_self_beacon_mode_btn.item_selected.connect(func(_i: int) -> void: _notify_changed())
	add_child(_field_row("Self Marker", _self_beacon_mode_btn))

	_carrier_ring_check = _cue_toggle(PlayerPrefs.carrier_ring_cue_enabled,
			tr("OPTIONS_CARRIER_RING"), tr("OPTIONS_CARRIER_RING_NOTE"))
	_possession_pulse_check = _cue_toggle(PlayerPrefs.possession_pulse_enabled,
			tr("OPTIONS_POSSESSION_PULSE"), tr("OPTIONS_POSSESSION_PULSE_NOTE"))
	_loose_halo_check = _cue_toggle(PlayerPrefs.loose_puck_halo_enabled,
			tr("OPTIONS_LOOSE_PUCK_HALO"), tr("OPTIONS_LOOSE_PUCK_HALO_NOTE"))

	# Free-play goalie difficulty — a personal-sandbox knob, separate from the
	# hosted/lobby goalie setting (which lives in the lobby settings panel).
	# Applies live to the running free-play goalies on Apply (no match reload).
	_freeplay_goalie_btn = OptionButton.new()
	_freeplay_goalie_btn.custom_minimum_size = Vector2(160, 40)
	_freeplay_goalie_btn.add_theme_font_size_override("font_size", 15)
	for i: int in PlayerPrefs.GOALIE_DIFFICULTY_LABELS.size():
		_freeplay_goalie_btn.add_item(PlayerPrefs.GOALIE_DIFFICULTY_LABELS[i], i)
	_freeplay_goalie_btn.selected = PlayerPrefs.freeplay_goalie_difficulty
	SoundManager.wire_button(_freeplay_goalie_btn)
	_freeplay_goalie_btn.item_selected.connect(func(_i: int) -> void: _notify_changed())
	add_child(_field_row("Free Play Goalie", _freeplay_goalie_btn))

	add_child(_section_spacer())
	add_child(_section_header(tr("OPTIONS_SECTION_CUSTOMIZATION")))

	_colors_file = CustomDataFile.new(TeamColorRegistry.RES_JSON_PATH,
			TeamColorRegistry.USER_JSON_PATH, TeamColorRegistry.accepts,
			TeamColorRegistry.loaded_path, "teams", "TEAM_COLORS_FILE_OUTDATED")
	add_child(_field_row(tr("OPTIONS_TEAM_COLORS_FILE"), _colors_file.build_buttons(self)))
	add_child(_row_note(tr("OPTIONS_TEAM_COLORS_FILE_NOTE")))
	add_child(_colors_file.build_status())

	_bots_file = CustomDataFile.new(BotIdentityRegistry.RES_JSON_PATH,
			BotIdentityRegistry.USER_JSON_PATH, BotIdentityRegistry.accepts,
			BotIdentityRegistry.loaded_path)
	add_child(_field_row(tr("OPTIONS_BOTS_FILE"), _bots_file.build_buttons(self)))
	add_child(_row_note(tr("OPTIONS_BOTS_FILE_NOTE")))
	add_child(_bots_file.build_status())

	add_child(_section_spacer())
	add_child(_section_header("Privacy"))

	_share_stats_check = CheckButton.new()
	_share_stats_check.set_pressed_no_signal(PlayerPrefs.share_gameplay_stats)
	SoundManager.wire_button(_share_stats_check)
	_share_stats_check.toggled.connect(func(_p: bool) -> void: _notify_changed())
	add_child(_field_row("Share Gameplay Stats", _share_stats_check))

	add_child(_row_note("Uploads match results so you can track your career. "
		+ "With this off, the Career menu and replay playback are unavailable — "
		+ "both are built from your uploaded games."))

# One puck-following cue's row: the toggle, its note beneath.
func _cue_toggle(pressed: bool, label: String, note: String) -> CheckButton:
	var check := CheckButton.new()
	check.set_pressed_no_signal(pressed)
	SoundManager.wire_button(check)
	check.toggled.connect(func(_p: bool) -> void: _notify_changed())
	add_child(_field_row(label, check))
	add_child(_row_note(note))
	return check

# Stored-code form of the language dropdown: "" for "System default" (index 0),
# else the shipped locale's code.
func _selected_locale() -> String:
	if _locale_btn.selected <= 0:
		return ""
	return LocaleManager.SUPPORTED[_locale_btn.selected - 1]["code"]

func read_controls() -> Dictionary:
	return {
		"attack_up": _attack_up_check.button_pressed,
		"self_beacon_mode": _self_beacon_mode_btn.selected,
		"carrier_ring_cue_enabled": _carrier_ring_check.button_pressed,
		"possession_pulse_enabled": _possession_pulse_check.button_pressed,
		"loose_puck_halo_enabled": _loose_halo_check.button_pressed,
		"freeplay_goalie_difficulty": _freeplay_goalie_btn.selected,
		"locale": _selected_locale(),
		"share_gameplay_stats": _share_stats_check.button_pressed,
	}

# The language dropdown is deliberately NOT reverted here: Cancel/Defaults leave
# the visible language selection as the player set it, and the pref itself only
# ever changes on Apply. `locale` is absent from OptionsPanel._defaults() for the
# same reason.
func apply_values(v: Dictionary) -> void:
	_attack_up_check.set_pressed_no_signal(v.attack_up)
	_self_beacon_mode_btn.selected = v.self_beacon_mode
	_carrier_ring_check.set_pressed_no_signal(v.carrier_ring_cue_enabled)
	_possession_pulse_check.set_pressed_no_signal(v.possession_pulse_enabled)
	_loose_halo_check.set_pressed_no_signal(v.loose_puck_halo_enabled)
	_freeplay_goalie_btn.selected = v.freeplay_goalie_difficulty
	_share_stats_check.set_pressed_no_signal(v.share_gameplay_stats)
