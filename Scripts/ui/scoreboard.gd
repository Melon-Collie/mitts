class_name Scoreboard
extends CanvasLayer

const _DARK_BG := Color(0.07, 0.07, 0.09, 0.94)
const _WHITE   := Color(1.00, 1.00, 1.00, 1.00)
const _DIM     := Color(0.62, 0.62, 0.68, 1.00)
const _HEADER  := Color(0.55, 0.55, 0.62, 1.00)
const _SEP     := Color(0.28, 0.28, 0.33, 1.00)

var _rows_container: VBoxContainer = null
var _period_score_labels: Array = []  # [team_id][0-2 period, 3 total]

func _ready() -> void:
	layer = 10
	visible = false
	_build_panel()
	GameManager.stats_updated.connect(_refresh)
	GameManager.game_over.connect(_on_game_over)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		visible = not visible
		get_viewport().set_input_as_handled()

func _on_game_over() -> void:
	visible = true
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
	panel_style.set_content_margin_all(20)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", panel_style)
	panel.custom_minimum_size = Vector2(480, 0)
	h_centering.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var title := _lbl("SCOREBOARD", 20, _WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	vbox.add_child(_hsep())
	_build_period_summary(vbox)
	vbox.add_child(_hsep())

	var header_row := _make_row()
	_fill_row(header_row, ["PLAYER", "G", "A", "PTS", "SOG", "HITS"], _HEADER, true)
	vbox.add_child(header_row)

	vbox.add_child(_hsep())

	_rows_container = VBoxContainer.new()
	_rows_container.add_theme_constant_override("separation", 3)
	vbox.add_child(_rows_container)

	vbox.add_child(_hsep())

	var footer := _lbl("TAB to toggle", 11, _DIM)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(footer)

func _build_period_summary(vbox: VBoxContainer) -> void:
	var col_label: int = 64
	var col_num: int = 32

	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 5)

	# Header row: blank | 1 | 2 | 3 | T
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(col_label, 0)
	grid.add_child(spacer)
	for header: String in ["1", "2", "3", "T"]:
		var h := _lbl(header, 12, _HEADER)
		h.custom_minimum_size = Vector2(col_num, 0)
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(h)

	# Away row (team 1) then home row (team 0) — same convention as scorebug
	for team_id: int in [1, 0]:
		var label: String = "AWAY" if team_id == 1 else "HOME"
		grid.add_child(_team_badge(label, PlayerRules.generate_primary_color(team_id), col_label))
		var row_labels: Array[Label] = []
		for _i: int in 4:
			var l := _lbl("0", 13, _WHITE)
			l.custom_minimum_size = Vector2(col_num, 0)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			grid.add_child(l)
			row_labels.append(l)
		_period_score_labels.append(row_labels)

	var h_wrap := HBoxContainer.new()
	h_wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	h_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h_wrap.add_child(grid)
	vbox.add_child(h_wrap)

func _refresh() -> void:
	if _rows_container == null:
		return

	if not _period_score_labels.is_empty():
		var ps: Array = GameManager.get_period_scores()
		# _period_score_labels[0] = away (team 1), [1] = home (team 0)
		for row: int in 2:
			var team_id: int = 1 if row == 0 else 0
			var total: int = 0
			for p: int in 3:
				var goals: int = ps[team_id][p]
				_period_score_labels[row][p].text = str(goals)
				total += goals
			_period_score_labels[row][3].text = str(total)

	for child in _rows_container.get_children():
		child.queue_free()

	var sorted: Array[PlayerRecord] = []
	for pid: int in GameManager.players:
		sorted.append(GameManager.players[pid])
	sorted.sort_custom(func(a: PlayerRecord, b: PlayerRecord) -> bool:
		if a.team.team_id != b.team.team_id:
			return a.team.team_id > b.team.team_id  # team 1 (away) first
		return a.slot < b.slot
	)

	var last_team_id: int = -1
	for record: PlayerRecord in sorted:
		if record.team.team_id != last_team_id:
			last_team_id = record.team.team_id
			_rows_container.add_child(_make_team_header(record.team.team_id))
		var row := _make_row()
		_rows_container.add_child(row)
		var s := record.stats
		var pts := s.goals + s.assists
		_fill_row(row,
			["P%d" % (record.slot + 1), str(s.goals), str(s.assists), str(pts), str(s.shots_on_goal), str(s.hits)],
			record.color, false
		)

func _make_team_header(team_id: int) -> PanelContainer:
	var label: String = "AWAY" if team_id == 1 else "HOME"
	var color: Color = PlayerRules.generate_primary_color(team_id)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.r, color.g, color.b, 0.18)
	style.set_corner_radius_all(3)
	style.set_content_margin(SIDE_LEFT, 8)
	style.set_content_margin(SIDE_RIGHT, 8)
	style.set_content_margin(SIDE_TOP, 4)
	style.set_content_margin(SIDE_BOTTOM, 4)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl := _lbl(label, 12, _WHITE)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(lbl)
	return panel

func _make_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	return row

func _fill_row(row: HBoxContainer, texts: Array, name_color: Color, is_header: bool) -> void:
	var widths := [190, 38, 38, 48, 48, 56]
	var font_size := 13 if is_header else 14
	for i in texts.size():
		var cell := Label.new()
		cell.text = texts[i]
		cell.custom_minimum_size = Vector2(widths[i], 0)
		cell.add_theme_font_size_override("font_size", font_size)
		var col := name_color if (i == 0 or is_header) else _WHITE
		cell.add_theme_color_override("font_color", col)
		cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(cell)

func _team_badge(text: String, color: Color, min_width: int) -> PanelContainer:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(3)
	style.set_content_margin(SIDE_LEFT, 6)
	style.set_content_margin(SIDE_RIGHT, 6)
	style.set_content_margin(SIDE_TOP, 3)
	style.set_content_margin(SIDE_BOTTOM, 3)
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", style)
	badge.custom_minimum_size = Vector2(min_width, 0)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var lum: float = 0.299 * color.r + 0.587 * color.g + 0.114 * color.b
	var text_color: Color = Color(0.06, 0.06, 0.06) if lum > 0.4 else _WHITE
	badge.add_child(_lbl(text, 11, text_color))
	return badge

func _hsep() -> HSeparator:
	var sep := HSeparator.new()
	var style := StyleBoxFlat.new()
	style.bg_color = _SEP
	style.set_content_margin_all(0)
	sep.add_theme_stylebox_override("separator", style)
	return sep

func _lbl(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
