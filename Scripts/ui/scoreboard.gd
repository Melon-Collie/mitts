class_name Scoreboard
extends CanvasLayer

const _DARK_BG := MenuStyle.BROADCAST_BG
const _WHITE   := MenuStyle.BROADCAST_CREAM
const _DIM     := MenuStyle.BROADCAST_DIM
const _HEADER  := MenuStyle.BROADCAST_DIM
const _SEP     := MenuStyle.BROADCAST_SEP
# Team badges (TeamBadge), in the period summary and on each team's section of
# the table: the crest about twice the row's height, so the row crops it.
const _SUMMARY_BADGE_WIDTH: float = 64.0
const _SUMMARY_CREST_PX: float = 62.0
const _SUMMARY_ROW_HEIGHT: float = 30.0
const _SUMMARY_ABBR_INSET: float = 12.0
const _SECTION_CREST_PX: float = 66.0
const _SECTION_HEIGHT: float = 32.0
const _SECTION_NAME_INSET: float = 22.0

# Column headers, tr()'d where the header row is built. The order is the
# left-to-right order _fill_row lays a row out in, and every data row passes
# its cells in the same order.
const _COLUMN_KEYS: Array[StringName] = [
	&"COL_PING", &"COL_NUMBER", &"COL_POS", &"COL_PLAYER", &"COL_GOALS",
	&"COL_ASSISTS", &"COL_POINTS", &"COL_SOG", &"COL_HITS", &"COL_BLOCKS",
]

var _rows_container: VBoxContainer = null
var _period_score_labels: Array = []  # [team_id][period_index, then total]
var _period_summary_grid: GridContainer = null

# Replay mode: when configured(), an external owner (the replay HUD) drives
# visibility and supplies replay-derived data through these providers instead
# of the live GameManager / NetworkManager autoloads.
var _external_control: bool = false
var _players_provider: Callable = Callable()
var _period_scores_provider: Callable = Callable()
var _color_slots: Array[int] = [
	TeamColorRegistry.DEFAULT_HOME_SLOT, TeamColorRegistry.DEFAULT_AWAY_SLOT]
var _num_periods_override: int = -1

func _ready() -> void:
	# Replay mode renders above the replay HUD chrome (its CanvasLayer is also
	# layer 10) but below the pause menu (layer 20/21). Live mode keeps 10.
	layer = 15 if _external_control else 10
	visible = false
	if not _external_control:
		GameManager.stats_updated.connect(_refresh)
		GameManager.game_reset.connect(_on_game_reset)
		GameManager.team_colors_ready.connect(_on_team_colors_ready)
		var ping_timer := Timer.new()
		ping_timer.wait_time = 2.0
		ping_timer.autostart = true
		ping_timer.timeout.connect(_refresh)
		add_child(ping_timer)
	_build_panel()

# Replay entry point. Call before add_child so _ready() skips the live
# GameManager wiring and self-Tab handling. The replay HUD owns Tab/Escape and
# pushes replay data through the providers. team_id 0 = home, 1 = away.
func configure(home_slot: int, away_slot: int, num_periods: int,
		players_provider: Callable, period_scores_provider: Callable) -> void:
	_external_control = true
	_color_slots = [home_slot, away_slot]
	_num_periods_override = num_periods
	_players_provider = players_provider
	_period_scores_provider = period_scores_provider

func _input(event: InputEvent) -> void:
	if _external_control:
		return  # replay HUD owns Tab/Escape for this board
	var toggled: bool = (event is InputEventKey and event.pressed \
			and (event as InputEventKey).keycode == KEY_TAB) \
			or (event is InputEventJoypadButton and event.pressed \
			and (event as InputEventJoypadButton).button_index == JOY_BUTTON_BACK)
	if toggled:
		visible = not visible
		if visible:
			_refresh()
		get_viewport().set_input_as_handled()

# Visibility control for externally-driven (replay) mode.
func show_board() -> void:
	_refresh()
	visible = true

func hide_board() -> void:
	visible = false

func toggle_board() -> void:
	if visible:
		hide_board()
	else:
		show_board()

# No auto-show at game over: the GameOverPopup end-of-game screen owns that
# moment now, with a "TAB · BOX SCORE" hint. This board renders on a higher
# layer, so Tab still brings the full numbers up over it.

# A new game/rematch auto-closes the end-of-game box score. The player can
# still re-open it with Tab during play.
func _on_game_reset() -> void:
	visible = false

# Period-summary stripe color for a team, matching the scorebug's rule so the
# two surfaces agree: always the team's own primary.
func _period_stripe(team_id: int) -> Color:
	var pair: Dictionary = TeamColorRegistry.get_score_stripe_pair(
			_team_color_slot(0), _team_color_slot(1))
	return pair.home if team_id == 0 else pair.away

# The teams' stripes, crests and names are all built from the clubs, so a
# change of clubs rebuilds the summary; the sections rebuild on every refresh.
func _on_team_colors_ready(_home_primary: Color, _home_secondary: Color, _away_primary: Color, _away_secondary: Color) -> void:
	if _period_summary_grid != null:
		_rebuild_period_grid(_data_period_scores()[0].size())
	_refresh()

func _build_panel() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var centering := VBoxContainer.new()
	centering.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centering.alignment = BoxContainer.ALIGNMENT_CENTER
	centering.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(centering)

	var h_centering := HBoxContainer.new()
	h_centering.alignment = BoxContainer.ALIGNMENT_CENTER
	h_centering.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centering.add_child(h_centering)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = _DARK_BG
	panel_style.set_corner_radius_all(4)
	# Single thin TEAL_DIM border around the whole popup, matching the
	# side menu's player card treatment.
	panel_style.border_color = MenuStyle.TEAL_DIM
	panel_style.set_border_width_all(1)
	panel_style.set_content_margin_all(0)  # inner sections handle their own padding

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", panel_style)
	panel.custom_minimum_size = Vector2(610, 0)
	h_centering.add_child(MenuStyle.wrap_drop_shadow(panel, Vector2(5, 5)))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	panel.add_child(vbox)

	# === Title strip ===
	# No contrasted background — the outer TEAL_DIM border handles the
	# panel framing, the title is just a label with margins so it reads
	# as a heading without becoming a separate visual block.
	var title_style := StyleBoxFlat.new()
	title_style.bg_color = Color(0, 0, 0, 0)
	title_style.set_content_margin(SIDE_TOP, 8)
	title_style.set_content_margin(SIDE_BOTTOM, 8)
	title_style.set_content_margin(SIDE_LEFT, 18)
	title_style.set_content_margin(SIDE_RIGHT, 18)
	var title_panel := PanelContainer.new()
	title_panel.add_theme_stylebox_override("panel", title_style)
	var title_label := _lbl(tr(&"BOX_SCORE_TITLE"), 16, _WHITE)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_panel.add_child(title_label)
	vbox.add_child(title_panel)

	# === Period summary ===
	var periods_outer := MarginContainer.new()
	periods_outer.add_theme_constant_override("margin_top", 12)
	periods_outer.add_theme_constant_override("margin_bottom", 4)
	periods_outer.add_theme_constant_override("margin_left", 22)
	periods_outer.add_theme_constant_override("margin_right", 22)
	vbox.add_child(periods_outer)
	var periods_vbox := VBoxContainer.new()
	periods_outer.add_child(periods_vbox)
	_build_period_summary(periods_vbox)

	# === Stats table strip ===
	var table_outer := MarginContainer.new()
	table_outer.add_theme_constant_override("margin_top", 12)
	table_outer.add_theme_constant_override("margin_bottom", 14)
	table_outer.add_theme_constant_override("margin_left", 18)
	table_outer.add_theme_constant_override("margin_right", 18)
	vbox.add_child(table_outer)
	var table_vbox := VBoxContainer.new()
	table_vbox.add_theme_constant_override("separation", 6)
	table_outer.add_child(table_vbox)

	var header_row := _make_row()
	var headers: Array = []
	for key: StringName in _COLUMN_KEYS:
		headers.append(tr(key))
	_fill_row(header_row, headers, _HEADER, true)
	table_vbox.add_child(header_row)

	_rows_container = VBoxContainer.new()
	_rows_container.add_theme_constant_override("separation", 3)
	table_vbox.add_child(_rows_container)

	# === Footer strip ===
	# Transparent — same reasoning as the title strip. The "PRESS TAB TO
	# TOGGLE" hint sits inside the panel border, not on its own block.
	var footer_style := StyleBoxFlat.new()
	footer_style.bg_color = Color(0, 0, 0, 0)
	footer_style.set_content_margin(SIDE_TOP, 6)
	footer_style.set_content_margin(SIDE_BOTTOM, 6)
	var footer_panel := PanelContainer.new()
	footer_panel.add_theme_stylebox_override("panel", footer_style)
	var footer := _lbl(tr(&"HINT_PRESS_TAB"), 11, _DIM)
	footer.add_theme_font_override("font", MenuStyle.UI_FONT)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer_panel.add_child(footer)
	vbox.add_child(footer_panel)

func _build_period_summary(vbox: VBoxContainer) -> void:
	var h_wrap := HBoxContainer.new()
	h_wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	h_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(h_wrap)

	_period_summary_grid = GridContainer.new()
	_period_summary_grid.add_theme_constant_override("h_separation", 0)
	_period_summary_grid.add_theme_constant_override("v_separation", 5)
	h_wrap.add_child(_period_summary_grid)

	_rebuild_period_grid(_data_period_scores()[0].size())

func _rebuild_period_grid(num_periods: int) -> void:
	for child in _period_summary_grid.get_children():
		child.free()
	_period_score_labels.clear()

	var col_num: int = 40
	_period_summary_grid.columns = 2 + num_periods  # badge + periods + total

	_period_summary_grid.add_child(Control.new())
	for p: int in num_periods:
		var period_num: int = p + 1
		var reg_periods: int = _data_num_periods()
		var header_text: String = tr(&"PERIOD_ORD_OT_N") % (period_num - reg_periods) \
				if period_num > reg_periods else str(period_num)
		var h := _lbl(header_text, 12, _HEADER)
		h.custom_minimum_size = Vector2(col_num, 0)
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_period_summary_grid.add_child(h)
	var t_header := _lbl(tr(&"COL_TOTAL"), 12, _HEADER)
	t_header.custom_minimum_size = Vector2(col_num, 0)
	t_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_period_summary_grid.add_child(t_header)

	for team_id: int in [1, 0]:
		_period_summary_grid.add_child(_summary_team_cell(team_id))
		var row_labels: Array[Label] = []
		for _i: int in num_periods + 1:  # periods + total
			var l := _lbl("0", 18, _WHITE)
			l.custom_minimum_size = Vector2(col_num, 0)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_period_summary_grid.add_child(l)
			row_labels.append(l)
		_period_score_labels.append(row_labels)

func _refresh() -> void:
	if _rows_container == null:
		return

	if not _period_score_labels.is_empty():
		var ps: Array = _data_period_scores()
		var num_periods: int = ps[0].size()
		# Rebuild the grid if OT added a period
		if _period_score_labels[0].size() != num_periods + 1:
			_rebuild_period_grid(num_periods)
		# _period_score_labels[0] = away (team 1), [1] = home (team 0)
		for row: int in 2:
			var team_id: int = 1 if row == 0 else 0
			var total: int = 0
			for p: int in num_periods:
				var goals: int = ps[team_id][p]
				_period_score_labels[row][p].text = str(goals)
				total += goals
			_period_score_labels[row][num_periods].text = str(total)

	for child in _rows_container.get_children():
		child.queue_free()

	var sorted: Array[PlayerRecord] = []
	var all_players: Dictionary = _data_players()
	for pid: int in all_players:
		sorted.append(all_players[pid] as PlayerRecord)
	sorted.sort_custom(func(a: PlayerRecord, b: PlayerRecord) -> bool:
		if a.team.team_id != b.team.team_id:
			return a.team.team_id > b.team.team_id  # team 1 (away) first
		return a.team_slot < b.team_slot
	)

	# Position labels depend on team size (5v5 has a real forward/defense
	# split, so wingers read LW/RW there instead of 3v3's plain L/R) — count
	# each team's roster rather than reaching for a team-size provider, so
	# this works identically in live and replay (external_control) mode.
	var team_counts: Dictionary = {}
	for record: PlayerRecord in sorted:
		team_counts[record.team.team_id] = team_counts.get(record.team.team_id, 0) + 1

	var last_team_id: int = -1
	for record: PlayerRecord in sorted:
		if record.team.team_id != last_team_id:
			last_team_id = record.team.team_id
			_rows_container.add_child(_make_team_header(record.team.team_id))
		var row := _make_row()
		_rows_container.add_child(row)
		var s := record.stats
		var pts := s.goals + s.assists
		var display_name: String = record.display_name()
		if Titles.is_known(record.title_id):
			display_name = tr(&"SCOREBOARD_NAME_TITLE") % [display_name,
					TrophyCopy.title_name(record.title_id)]
		var ping_str: String = _ping_label(record.peer_id)
		var is_5v5: bool = int(team_counts.get(record.team.team_id, 0)) >= 5
		var pos_str: String = tr(PositionLabels.badge_key(record.team_slot, is_5v5))
		var num_str: String = str(record.jersey_number)
		_fill_row(row,
			[ping_str, num_str, pos_str, display_name, str(s.goals), str(s.assists), str(pts), str(s.shots_on_goal), str(s.hits), str(s.shots_blocked)],
			_WHITE, false
		)

# A team's section of the table: its stripe, then its crest and full name on a
# raised band, the same for both teams.
func _make_team_header(team_id: int) -> HBoxContainer:
	var club: int = _team_color_slot(team_id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Two panels stitched together so the outside reads as one 4px-rounded
	# shape with a hard seam between the stripe and the band, as the lobby
	# cards are: a single rounded panel bends its stripe round the corner.
	var stripe_style := StyleBoxFlat.new()
	stripe_style.bg_color = _period_stripe(team_id)
	stripe_style.corner_radius_top_left = 4
	stripe_style.corner_radius_bottom_left = 4
	var stripe := PanelContainer.new()
	stripe.add_theme_stylebox_override("panel", stripe_style)
	stripe.custom_minimum_size = Vector2(6, 0)
	row.add_child(stripe)

	var band_style := StyleBoxFlat.new()
	band_style.bg_color = MenuStyle.SURFACE_ELEV
	band_style.corner_radius_top_right = 4
	band_style.corner_radius_bottom_right = 4
	var band := PanelContainer.new()
	band.add_theme_stylebox_override("panel", band_style)
	band.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	band.clip_contents = true
	var badge := TeamBadge.new(0.0, _SECTION_CREST_PX, 17, _SECTION_NAME_INSET,
			HORIZONTAL_ALIGNMENT_LEFT)
	badge.custom_minimum_size.y = _SECTION_HEIGHT
	badge.set_team(club, TeamColorRegistry.get_preset_name(club).to_upper())
	band.add_child(badge)
	row.add_child(band)
	return row


# A team in the period summary: its stripe and its badge, as on the scorebug.
func _summary_team_cell(team_id: int) -> HBoxContainer:
	var club: int = _team_color_slot(team_id)
	var cell := HBoxContainer.new()
	cell.add_theme_constant_override("separation", 0)
	var stripe := ColorRect.new()
	stripe.color = _period_stripe(team_id)
	stripe.custom_minimum_size = Vector2(5, 0)
	cell.add_child(stripe)
	var badge := TeamBadge.new(_SUMMARY_BADGE_WIDTH, _SUMMARY_CREST_PX, 17, _SUMMARY_ABBR_INSET)
	badge.custom_minimum_size.y = _SUMMARY_ROW_HEIGHT
	badge.set_team(club, TeamColorRegistry.get_preset_abbr(club))
	cell.add_child(badge)
	return cell


func _make_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	return row

# ── Data accessors (live GameManager / NetworkManager, or replay providers) ──

func _data_players() -> Dictionary:
	if _players_provider.is_valid():
		return _players_provider.call() as Dictionary
	return GameManager.get_players()

func _data_period_scores() -> Array:
	if _period_scores_provider.is_valid():
		return _period_scores_provider.call() as Array
	return GameManager.get_period_scores()

func _data_num_periods() -> int:
	if _num_periods_override >= 0:
		return _num_periods_override
	return GameManager.get_num_periods()

func _team_color_slot(team_id: int) -> int:
	if _external_control:
		return _color_slots[clampi(team_id, 0, 1)]
	if GameManager.teams.size() > team_id:
		return GameManager.teams[team_id].color_slot
	return _color_slots[clampi(team_id, 0, 1)]

func _ping_label(peer_id: int) -> String:
	if _external_control:
		return "—"  # ping is meaningless for an offline file replay
	var local_id: int = NetworkManager.local_peer_id()
	if peer_id == local_id:
		return "—" if NetworkManager.is_host else tr(&"PING_MS") % int(NetworkManager.get_rtt_ms())
	var p: int = NetworkManager.get_peer_ping_ms(peer_id)
	return tr(&"PING_MS") % p if p > 0 else "—"

func _fill_row(row: HBoxContainer, texts: Array, name_color: Color, is_header: bool) -> void:
	var widths := [52, 36, 36, 150, 38, 38, 48, 48, 56, 48]
	var font_size := 13 if is_header else 14
	for i in texts.size():
		var cell := Label.new()
		cell.text = texts[i]
		cell.custom_minimum_size = Vector2(widths[i], 0)
		cell.add_theme_font_override("font", MenuStyle.UI_FONT)
		cell.add_theme_font_size_override("font_size", font_size)
		var col := name_color if (i > 0 and i < 4 or is_header) else _WHITE
		cell.add_theme_color_override("font_color", col)
		cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if i == 3 else HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(cell)

func _lbl(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", MenuStyle.DISPLAY_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
