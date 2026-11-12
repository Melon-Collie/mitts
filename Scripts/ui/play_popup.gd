class_name PlayPopup
extends Control

# The single entry point for playing a match: Start Game opens the unified
# lobby (offline until the host flips its visibility selector to Friends /
# Public), and the browser below joins someone else's open game. Start Game
# never needs Steam — with Steam down, only browsing/joining is unavailable.

# Start Game pressed — the menu tears down the current session and enters the
# lobby scene as an offline host.
signal start_pressed
# Emitted with the Steam lobby id of the game the player chose to join.
signal join_pressed(lobby_id: int)
# The saved tournament's next game, and the setup for a new one.
signal tournament_continue_pressed
signal tournament_new_pressed

var _list_box: VBoxContainer = null
var _status_label: Label = null
var _refresh_btn: Button = null
var _steam_status_label: Label = null
var _tournament_btn: Button = null
var _tournament_new_btn: Button = null
var _tournament_note: Label = null
var _tournament_in_progress: bool = false

const _STEAM_OK_COLOR: Color = Color(0.45, 0.85, 0.55, 1.0)
const _STEAM_OFF_COLOR: Color = Color(0.85, 0.5, 0.45, 1.0)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	# Persistent: the autoload outlives this popup, so connect once.
	SteamManager.lobby_list_received.connect(_on_lobby_list)
	visible = false


func _build() -> void:
	var overlay := ColorRect.new()
	overlay.color = MenuStyle.SCRIM
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_overlay_clicked)
	add_child(overlay)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", MenuStyle.panel())
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	var close_row := HBoxContainer.new()
	var close_spacer := Control.new()
	close_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_row.add_child(close_spacer)
	var close_btn := MenuStyle.close_button()
	close_btn.pressed.connect(func() -> void: visible = false)
	SoundManager.wire_button(close_btn)
	close_row.add_child(close_btn)
	vbox.add_child(close_row)

	var title := Label.new()
	title.text = "Play"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MenuStyle.apply_heading(title)
	vbox.add_child(title)

	# At-a-glance Steam init check: green "connected as <name>" or a red hint.
	_steam_status_label = Label.new()
	_steam_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_steam_status_label.add_theme_font_size_override("font_size", 15)
	vbox.add_child(_steam_status_label)

	var start_btn := _menu_button("Start Game")
	start_btn.pressed.connect(func() -> void:
		visible = false
		start_pressed.emit())
	vbox.add_child(start_btn)

	_build_tournament_rows(vbox)

	# ── Public lobby browser ──────────────────────────────────────────────
	var browse_row := HBoxContainer.new()
	browse_row.custom_minimum_size = Vector2(308, 0)
	var browse_label := Label.new()
	browse_label.text = "Open Games"
	browse_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	browse_label.add_theme_font_size_override("font_size", 18)
	browse_label.add_theme_color_override("font_color", MenuStyle.TEXT_TITLE)
	browse_row.add_child(browse_label)
	_refresh_btn = Button.new()
	_refresh_btn.text = "Refresh"
	_refresh_btn.add_theme_font_size_override("font_size", 16)
	_refresh_btn.pressed.connect(_refresh_lobbies)
	MenuStyle.wire_hover_scale(_refresh_btn)
	SoundManager.wire_button(_refresh_btn)
	browse_row.add_child(_refresh_btn)
	vbox.add_child(browse_row)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(308, 220)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_list_box)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 16)
	_status_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65, 1.0))
	vbox.add_child(_status_label)


# The Tournament button continues the saved tournament when one is in progress
# and sets up a new one otherwise; the note under it says where the save stands.
func _build_tournament_rows(vbox: VBoxContainer) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	vbox.add_child(box)

	_tournament_btn = _menu_button(tr(&"TOURNAMENT_TITLE"))
	_tournament_btn.pressed.connect(_on_tournament_pressed)
	box.add_child(_tournament_btn)

	_tournament_note = Label.new()
	_tournament_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tournament_note.add_theme_font_size_override("font_size", 14)
	_tournament_note.add_theme_color_override("font_color", MenuStyle.TEXT_DIM)
	box.add_child(_tournament_note)

	_tournament_new_btn = Button.new()
	_tournament_new_btn.text = tr(&"TOURNAMENT_NEW")
	_tournament_new_btn.add_theme_font_size_override("font_size", 14)
	_tournament_new_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	MenuStyle.wire_hover_scale(_tournament_new_btn)
	SoundManager.wire_button(_tournament_new_btn)
	_tournament_new_btn.pressed.connect(func() -> void:
		visible = false
		tournament_new_pressed.emit())
	box.add_child(_tournament_new_btn)


func _refresh_tournament() -> void:
	var saved: TournamentState = GameManager.tournament.saved()
	_tournament_in_progress = saved != null \
			and TournamentRules.status(saved) == TournamentRules.Status.IN_PROGRESS
	_tournament_btn.text = tr(&"TOURNAMENT_CONTINUE") if _tournament_in_progress \
			else tr(&"TOURNAMENT_TITLE")
	_tournament_new_btn.visible = _tournament_in_progress
	_tournament_note.visible = saved != null
	if saved != null:
		_tournament_note.text = TournamentCopy.status_line(saved)


func _on_tournament_pressed() -> void:
	visible = false
	if _tournament_in_progress:
		tournament_continue_pressed.emit()
	else:
		tournament_new_pressed.emit()


func _refresh_steam_status() -> void:
	if SteamManager.is_available:
		_steam_status_label.text = "Steam: connected as %s" % SteamManager.persona_name
		_steam_status_label.add_theme_color_override("font_color", _STEAM_OK_COLOR)
	else:
		_steam_status_label.text = "Steam: not running"
		_steam_status_label.add_theme_color_override("font_color", _STEAM_OFF_COLOR)


func _menu_button(label: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(308, 48)
	btn.add_theme_font_size_override("font_size", 20)
	MenuStyle.wire_hover_scale(btn)
	SoundManager.wire_button(btn)
	return btn


func _refresh_lobbies() -> void:
	if not SteamManager.is_available:
		_set_status("Steam isn't running.")
		return
	_clear_list()
	_set_status("Searching for games…")
	SteamManager.request_lobby_list()


func _on_lobby_list(lobbies: Array) -> void:
	if not visible:
		return
	_clear_list()
	if lobbies.is_empty():
		_set_status("No open games found.")
		return
	_set_status("")
	for lobby: Dictionary in lobbies:
		_list_box.add_child(_lobby_row(lobby))


func _lobby_row(lobby: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 40)
	var name_label := Label.new()
	var lobby_name: String = lobby.get("name", "")
	if lobby_name.is_empty():
		lobby_name = "Game"
	name_label.text = "%s  (%d/%d)" % [lobby_name, int(lobby.get("members", 0)), int(lobby.get("max", 0))]
	name_label.add_theme_font_size_override("font_size", 16)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_child(name_label)
	var round_tag: String = lobby.get("tournament_round", "")
	if round_tag.is_valid_int():
		var tournament_label := Label.new()
		tournament_label.text = tr(&"TOURNAMENT_LOBBY_TITLE") \
				% TournamentCopy.round_name(round_tag.to_int())
		tournament_label.add_theme_font_size_override("font_size", 12)
		tournament_label.add_theme_color_override("font_color", MenuStyle.TEXT_DIM)
		titles.add_child(tournament_label)
	row.add_child(titles)
	var join_btn := Button.new()
	join_btn.text = "Join"
	join_btn.add_theme_font_size_override("font_size", 16)
	var lobby_id: int = int(lobby.get("lobby_id", 0))
	join_btn.pressed.connect(func() -> void:
		visible = false
		join_pressed.emit(lobby_id))
	MenuStyle.wire_hover_scale(join_btn)
	SoundManager.wire_button(join_btn)
	row.add_child(join_btn)
	return row


func _clear_list() -> void:
	for child in _list_box.get_children():
		child.queue_free()


func _set_status(text: String) -> void:
	_status_label.text = text
	_status_label.visible = not text.is_empty()


func _on_overlay_clicked(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		visible = false


func open() -> void:
	visible = true
	_refresh_steam_status()
	_refresh_tournament()
	if SteamManager.is_available:
		_refresh_lobbies()
	else:
		# Start Game still works (offline lobby vs bots) — only browsing and
		# joining need Steam.
		_clear_list()
		_set_status("Steam isn't running — joining online\ngames is unavailable. Start Game still works.")
	ControllerNav.focus_first(self)  # controller: take focus off the Side Menu behind


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		visible = false
		get_viewport().set_input_as_handled()
