class_name HUD
extends CanvasLayer

var _period_label: Label
var _clock_label: Label
var _home_score_label: Label
var _away_score_label: Label
var _phase_panel: PanelContainer
var _phase_label: Label
var _assist_label: Label
var _phase_style: StyleBoxFlat
var _elevation_panel: PanelContainer
var _game_over_popup: CanvasLayer = null
var _game_menu: CanvasLayer = null
var _slot_grid: SlotGridPanel = null
var _slot_grid_container: Control = null
var _toast_container: VBoxContainer = null
var _home_sog_label: Label = null
var _away_sog_label: Label = null
var _local_skater: Skater = null
var _score_0: int = 0
var _score_1: int = 0

const _DARK_BG    := Color(0.07, 0.07, 0.09, 0.92)
const _WHITE      := Color(1.00, 1.00, 1.00, 1.00)
const _DIM        := Color(0.62, 0.62, 0.68, 1.00)
const _GOLD       := Color(1.00, 0.85, 0.20, 1.00)
const _SEP_COLOR  := Color(0.28, 0.28, 0.33, 1.00)

func _ready() -> void:
	_build_scorebug()
	_build_phase_banner()
	_build_elevation_indicator()
	_build_version_tag()
	_build_game_over_popup()
	_build_game_menu()
	_build_toast_area()
	_period_label.text = _period_ordinal(1)
	_clock_label.text = _format_clock(GameManager.get_period_duration())
	_home_score_label.text = "0"
	_away_score_label.text = "0"
	_phase_panel.visible = false
	GameManager.score_changed.connect(_on_score_changed)
	GameManager.goal_scored.connect(_on_goal_scored)
	GameManager.phase_changed.connect(_on_phase_changed)
	GameManager.period_changed.connect(_on_period_changed)
	GameManager.clock_updated.connect(_on_clock_updated)
	GameManager.game_over.connect(_on_game_over)
	GameManager.game_reset.connect(_on_game_reset)
	GameManager.shots_on_goal_changed.connect(_on_shots_on_goal_changed)
	GameManager.player_joined.connect(func(n: String, c: Color) -> void: _show_toast(n + " joined", c))
	GameManager.player_left.connect(func(n: String, c: Color) -> void: _show_toast(n + " left", c))
	GameManager.stats_updated.connect(func() -> void:
		if _game_menu != null and _game_menu.visible and _slot_grid != null:
			_slot_grid.refresh(GameManager.get_slot_roster(), multiplayer.get_unique_id()))

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _game_over_popup.visible:
			return
		if _game_menu.visible and _slot_grid_container != null and _slot_grid_container.visible:
			_slot_grid_container.visible = false
		else:
			_set_menu_open(not _game_menu.visible)
		get_viewport().set_input_as_handled()

func _set_menu_open(open: bool) -> void:
	_game_menu.visible = open
	GameManager.set_input_blocked(open)
	if not open and _slot_grid_container != null:
		_slot_grid_container.visible = false

func _process(_delta: float) -> void:
	if _local_skater == null:
		var record: PlayerRecord = GameManager.get_local_player()
		if record:
			_local_skater = record.skater
	if _local_skater != null:
		_elevation_panel.visible = _local_skater.is_elevated

# ---------------------------------------------------------------------------
# Build helpers
# ---------------------------------------------------------------------------

func _build_scorebug() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = _DARK_BG
	panel_style.set_corner_radius_all(3)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", panel_style)
	panel.position = Vector2(8, 8)
	add_child(panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 0)
	panel.add_child(hbox)

	# Teams + Scores column
	var teams_cell := _cell(8, 6)
	hbox.add_child(teams_cell)
	var teams_vbox := VBoxContainer.new()
	teams_vbox.add_theme_constant_override("separation", 5)
	teams_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	teams_cell.add_child(teams_vbox)

	# Away on top, home on bottom (NHL convention)
	var away_row := HBoxContainer.new()
	away_row.add_theme_constant_override("separation", 8)
	away_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	teams_vbox.add_child(away_row)
	away_row.add_child(_team_badge("AWAY", PlayerRules.generate_primary_color(1)))
	_away_score_label = _lbl("0", 20, _WHITE)
	_away_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_away_score_label.custom_minimum_size = Vector2(22, 0)
	_away_score_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	away_row.add_child(_away_score_label)

	var home_row := HBoxContainer.new()
	home_row.add_theme_constant_override("separation", 8)
	home_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	teams_vbox.add_child(home_row)
	home_row.add_child(_team_badge("HOME", PlayerRules.generate_primary_color(0)))
	_home_score_label = _lbl("0", 20, _WHITE)
	_home_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_home_score_label.custom_minimum_size = Vector2(22, 0)
	_home_score_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	home_row.add_child(_home_score_label)

	hbox.add_child(_vsep())

	# Shots on Goal column: "SHOTS" header + per-team numbers
	var shots_cell := _cell(8, 4)
	hbox.add_child(shots_cell)
	var shots_vbox := VBoxContainer.new()
	shots_vbox.add_theme_constant_override("separation", 2)
	shots_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	shots_cell.add_child(shots_vbox)

	# Away shots top, label middle, home shots bottom — mirrors team row order
	_away_sog_label = _lbl("0", 14, _WHITE)
	_away_sog_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_away_sog_label.custom_minimum_size = Vector2(28, 0)
	shots_vbox.add_child(_away_sog_label)

	var shots_header := _lbl("SHOTS", 9, _DIM)
	shots_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shots_vbox.add_child(shots_header)

	_home_sog_label = _lbl("0", 14, _WHITE)
	_home_sog_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_home_sog_label.custom_minimum_size = Vector2(28, 0)
	shots_vbox.add_child(_home_sog_label)

	hbox.add_child(_vsep())

	# Period + Clock column
	var time_cell := _cell(8, 6)
	hbox.add_child(time_cell)
	var time_vbox := VBoxContainer.new()
	time_vbox.add_theme_constant_override("separation", 2)
	time_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	time_cell.add_child(time_vbox)

	_period_label = _lbl("1ST", 12, _DIM)
	_period_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_vbox.add_child(_period_label)

	_clock_label = _lbl("4:00", 22, _WHITE)
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock_label.custom_minimum_size = Vector2(60, 0)
	time_vbox.add_child(_clock_label)

func _build_phase_banner() -> void:
	# Centered below the scorebug
	var root := Control.new()
	root.anchor_right = 1.0
	root.offset_top = 62.0
	root.offset_bottom = 112.0
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var centering := HBoxContainer.new()
	centering.alignment = BoxContainer.ALIGNMENT_CENTER
	centering.anchor_right = 1.0
	centering.offset_bottom = 50.0
	centering.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(centering)

	_phase_style = StyleBoxFlat.new()
	_phase_style.bg_color = Color(0.07, 0.07, 0.09, 0.88)
	_phase_style.set_corner_radius_all(3)
	_phase_style.set_content_margin(SIDE_LEFT, 20)
	_phase_style.set_content_margin(SIDE_RIGHT, 20)
	_phase_style.set_content_margin(SIDE_TOP, 8)
	_phase_style.set_content_margin(SIDE_BOTTOM, 8)

	_phase_panel = PanelContainer.new()
	_phase_panel.add_theme_stylebox_override("panel", _phase_style)
	centering.add_child(_phase_panel)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_phase_panel.add_child(vbox)

	_phase_label = _lbl("", 18, _GOLD)
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_phase_label)

	_assist_label = _lbl("", 13, _DIM)
	_assist_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_assist_label.visible = false
	vbox.add_child(_assist_label)

func _build_elevation_indicator() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = _DARK_BG
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)

	_elevation_panel = PanelContainer.new()
	_elevation_panel.add_theme_stylebox_override("panel", style)
	_elevation_panel.anchor_left = 0.5
	_elevation_panel.anchor_right = 0.5
	_elevation_panel.anchor_top = 1.0
	_elevation_panel.anchor_bottom = 1.0
	_elevation_panel.offset_left = -60.0
	_elevation_panel.offset_right = 60.0
	_elevation_panel.offset_top = -48.0
	_elevation_panel.offset_bottom = -16.0
	_elevation_panel.visible = false
	add_child(_elevation_panel)

	var label := _lbl("\u2191 ELEVATED", 16, Color(0.4, 0.8, 1.0, 1.0))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_elevation_panel.add_child(label)

func _build_game_over_popup() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = _DARK_BG
	panel_style.set_corner_radius_all(6)
	panel_style.set_content_margin_all(32)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", panel_style)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_bottom = -20

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "GAME OVER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", _GOLD)
	vbox.add_child(title)

	_add_host_button(vbox, "Rematch", func() -> void: GameManager.reset_game())
	_add_host_button(vbox, "Return to Lobby", func() -> void: GameManager.return_to_lobby())

	var menu_btn := _popup_button("Disconnect")
	menu_btn.pressed.connect(func() -> void: GameManager.exit_to_main_menu())
	vbox.add_child(menu_btn)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(panel)

	# Layer 5 — below scoreboard (layer 10); no overlap since panel sits at bottom.
	_game_over_popup = CanvasLayer.new()
	_game_over_popup.layer = 5
	_game_over_popup.visible = false
	_game_over_popup.add_child(root)
	add_child(_game_over_popup)

func _build_game_menu() -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = _DARK_BG
	panel_style.set_corner_radius_all(6)
	panel_style.set_content_margin_all(32)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", panel_style)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	var resume_btn := _popup_button("Resume")
	resume_btn.pressed.connect(func() -> void: _set_menu_open(false))
	vbox.add_child(resume_btn)

	var change_pos_btn := _popup_button("Change Position")
	change_pos_btn.pressed.connect(_on_change_position_pressed)
	vbox.add_child(change_pos_btn)

	_add_host_button(vbox, "Rematch", func() -> void:
		_set_menu_open(false)
		GameManager.reset_game())
	_add_host_button(vbox, "Return to Lobby", func() -> void:
		_set_menu_open(false)
		GameManager.return_to_lobby())

	var bug_btn := _popup_button("Report Bug")
	bug_btn.pressed.connect(_on_bug_report_pressed)
	vbox.add_child(bug_btn)

	var quit_btn := _popup_button("Disconnect")
	quit_btn.pressed.connect(func() -> void: GameManager.exit_to_main_menu())
	vbox.add_child(quit_btn)

	var exit_btn := _popup_button("Exit Game")
	exit_btn.pressed.connect(func() -> void:
		GameManager.on_scene_exit()
		NetworkManager.reset()
		get_tree().quit())
	vbox.add_child(exit_btn)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(overlay)
	root.add_child(panel)

	_game_menu = CanvasLayer.new()
	_game_menu.layer = 20
	_game_menu.visible = false
	_game_menu.add_child(root)
	add_child(_game_menu)

	var slot_grid_panel_style := StyleBoxFlat.new()
	slot_grid_panel_style.bg_color = _DARK_BG
	slot_grid_panel_style.set_corner_radius_all(6)
	slot_grid_panel_style.set_content_margin_all(32)

	var slot_panel := PanelContainer.new()
	slot_panel.add_theme_stylebox_override("panel", slot_grid_panel_style)
	slot_panel.set_anchors_preset(Control.PRESET_CENTER)
	slot_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	slot_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	slot_panel.custom_minimum_size = Vector2(360, 120)

	_slot_grid = SlotGridPanel.new()
	_slot_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slot_grid.slot_selected.connect(_on_pause_slot_selected)
	slot_panel.add_child(_slot_grid)

	var slot_grid_root := Control.new()
	slot_grid_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slot_grid_root.add_child(slot_panel)

	_slot_grid_container = slot_grid_root
	_slot_grid_container.visible = false

	var slot_grid_layer := CanvasLayer.new()
	slot_grid_layer.layer = 21
	slot_grid_layer.add_child(slot_grid_root)
	add_child(slot_grid_layer)

func _build_toast_area() -> void:
	_toast_container = VBoxContainer.new()
	_toast_container.anchor_left = 1.0
	_toast_container.anchor_right = 1.0
	_toast_container.offset_left = -220.0
	_toast_container.offset_top = 8.0
	_toast_container.add_theme_constant_override("separation", 4)
	_toast_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast_container)

func _show_toast(text: String, name_color: Color = _WHITE) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = _DARK_BG
	style.set_corner_radius_all(3)
	style.set_content_margin(SIDE_LEFT, 12)
	style.set_content_margin(SIDE_RIGHT, 12)
	style.set_content_margin(SIDE_TOP, 6)
	style.set_content_margin(SIDE_BOTTOM, 6)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_container.add_child(panel)

	var parts := text.split(" ", false, 1)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 5)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_lbl := _lbl(parts[0], 14, name_color)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(name_lbl)
	if parts.size() > 1:
		var action_lbl := _lbl(parts[1], 14, _DIM)
		action_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(action_lbl)
	panel.add_child(hbox)

	var tween := create_tween()
	tween.tween_interval(2.5)
	tween.tween_method(func(a: float) -> void: panel.modulate.a = a, 1.0, 0.0, 0.5)
	tween.tween_callback(panel.queue_free)

func _popup_button(label: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(220, 48)
	btn.add_theme_font_size_override("font_size", 20)
	return btn

func _add_host_button(vbox: VBoxContainer, text: String, handler: Callable) -> void:
	if not NetworkManager.is_host:
		return
	var b := _popup_button(text)
	b.pressed.connect(handler)
	vbox.add_child(b)

func _build_version_tag() -> void:
	var label := _lbl("v%s" % BuildInfo.VERSION, 11, _DIM)
	label.anchor_left = 1.0
	label.anchor_right = 1.0
	label.anchor_top = 1.0
	label.anchor_bottom = 1.0
	label.offset_left = -80.0
	label.offset_right = -8.0
	label.offset_top = -20.0
	label.offset_bottom = -4.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_score_changed(score_0: int, score_1: int) -> void:
	_score_0 = score_0
	_score_1 = score_1
	_home_score_label.text = str(score_0)
	_away_score_label.text = str(score_1)

func _on_goal_scored(scoring_team: Team, scorer_name: String, assist1_name: String, assist2_name: String) -> void:
	var score_label: Label = _away_score_label if scoring_team.team_id == 1 else _home_score_label
	score_label.add_theme_color_override("font_color", _GOLD)
	var tween := create_tween()
	tween.tween_method(
		func(c: Color) -> void: score_label.add_theme_color_override("font_color", c),
		_GOLD, _WHITE, 1.5)
	_phase_label.text = ("GOAL!  %s" % scorer_name) if not scorer_name.is_empty() else "GOAL!"
	_phase_label.add_theme_color_override("font_color", _GOLD)
	var team_color: Color = PlayerRules.generate_primary_color(scoring_team.team_id)
	_phase_style.bg_color = Color(team_color.r * 0.25, team_color.g * 0.25, team_color.b * 0.25, 0.92)
	if not assist1_name.is_empty():
		var assist_text: String = assist1_name
		if not assist2_name.is_empty():
			assist_text += "  /  " + assist2_name
		_assist_label.text = "Assisted by  " + assist_text
		_assist_label.visible = true
	else:
		_assist_label.visible = false

func _on_phase_changed(new_phase: int) -> void:
	match new_phase:
		GamePhase.Phase.PLAYING:
			_phase_panel.visible = false
			_phase_label.add_theme_color_override("font_color", _GOLD)
			_phase_style.bg_color = Color(0.07, 0.07, 0.09, 0.88)
			_assist_label.visible = false
		GamePhase.Phase.GOAL_SCORED:
			_phase_panel.visible = true  # text + color set by _on_goal_scored
		GamePhase.Phase.END_OF_PERIOD:
			_phase_label.text = "END OF PERIOD"
			_phase_label.add_theme_color_override("font_color", _GOLD)
			_phase_panel.visible = true
		GamePhase.Phase.GAME_OVER:
			_phase_panel.visible = true  # text + color set by _on_game_over
		_:
			_phase_label.text = "FACEOFF"
			_phase_label.add_theme_color_override("font_color", _GOLD)
			_phase_style.bg_color = Color(0.07, 0.07, 0.09, 0.88)
			_assist_label.visible = false
			_phase_panel.visible = true

func _on_period_changed(new_period: int) -> void:
	_period_label.text = _period_ordinal(new_period)

func _on_clock_updated(t: float) -> void:
	_clock_label.text = _format_clock(t)
	_clock_label.add_theme_color_override("font_color", _GOLD if t <= 30.0 and t > 0.0 else _WHITE)

func _on_game_over() -> void:
	if _score_0 > _score_1:
		_phase_label.text = "HOME WINS"
		_phase_label.add_theme_color_override("font_color", _GOLD)
	elif _score_1 > _score_0:
		_phase_label.text = "AWAY WINS"
		_phase_label.add_theme_color_override("font_color", Color(0.55, 0.75, 1.0))
	else:
		_phase_label.text = "TIE"
		_phase_label.add_theme_color_override("font_color", _WHITE)
	_phase_panel.visible = true
	_game_over_popup.visible = true

func _on_game_reset() -> void:
	_game_over_popup.visible = false

func _on_change_position_pressed() -> void:
	_slot_grid_container.visible = not _slot_grid_container.visible
	if _slot_grid_container.visible:
		_slot_grid.refresh(GameManager.get_slot_roster(), multiplayer.get_unique_id())

func _on_pause_slot_selected(team_id: int, slot: int) -> void:
	NetworkManager.send_request_slot_swap(team_id, slot)
	_set_menu_open(false)

func _on_bug_report_pressed() -> void:
	var title: String = "[bug] v%s %s - " % [BuildInfo.VERSION, OS.get_name()]
	var body: String = "Version: v%s\nOS: %s\n\nWhat happened:\n\nSteps to reproduce:\n1. \n2. \n3. \n" % [BuildInfo.VERSION, OS.get_name()]
	var url: String = "https://github.com/%s/issues/new?title=%s&body=%s" % [BuildInfo.REPO, title.uri_encode(), body.uri_encode()]
	OS.shell_open(url)

func _on_shots_on_goal_changed(sog_0: int, sog_1: int) -> void:
	if _home_sog_label != null:
		_home_sog_label.text = str(sog_0)
	if _away_sog_label != null:
		_away_sog_label.text = str(sog_1)

# ---------------------------------------------------------------------------
# Utility
# ---------------------------------------------------------------------------

func _cell(h_margin: int, v_margin: int) -> MarginContainer:
	var c := MarginContainer.new()
	c.add_theme_constant_override("margin_left", h_margin)
	c.add_theme_constant_override("margin_right", h_margin)
	c.add_theme_constant_override("margin_top", v_margin)
	c.add_theme_constant_override("margin_bottom", v_margin)
	return c

func _team_badge(text: String, bg_color: Color) -> PanelContainer:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.set_corner_radius_all(3)
	style.set_content_margin(SIDE_LEFT, 6)
	style.set_content_margin(SIDE_RIGHT, 6)
	style.set_content_margin(SIDE_TOP, 3)
	style.set_content_margin(SIDE_BOTTOM, 3)
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", style)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Pick text color by background luminance: dark text on light fills, white on dark.
	var lum: float = 0.299 * bg_color.r + 0.587 * bg_color.g + 0.114 * bg_color.b
	var text_color: Color = Color(0.06, 0.06, 0.06) if lum > 0.4 else _WHITE
	badge.add_child(_lbl(text, 11, text_color))
	return badge

func _vsep() -> VSeparator:
	var sep := VSeparator.new()
	var style := StyleBoxFlat.new()
	style.bg_color = _SEP_COLOR
	style.set_content_margin_all(0)
	sep.add_theme_stylebox_override("separator", style)
	sep.custom_minimum_size = Vector2(1, 0)
	return sep

func _lbl(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _period_ordinal(p: int) -> String:
	var n: int = GameManager.get_num_periods()
	if p > n:
		return "OT%d" % (p - n)
	match p:
		1: return "1ST"
		2: return "2ND"
		3: return "3RD"
		_: return "P%d" % p

func _format_clock(t: float) -> String:
	var secs: int = int(ceil(t))
	return "%d:%02d" % [int(secs / 60.0), secs % 60]
