class_name Scoreboard
extends CanvasLayer

const _DARK_BG := Color(0.07, 0.07, 0.09, 0.94)
const _WHITE   := Color(1.00, 1.00, 1.00, 1.00)
const _DIM     := Color(0.62, 0.62, 0.68, 1.00)
const _HEADER  := Color(0.55, 0.55, 0.62, 1.00)
const _SEP     := Color(0.28, 0.28, 0.33, 1.00)

var _rows_container: VBoxContainer = null

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

func _refresh() -> void:
	if _rows_container == null:
		return
	for child in _rows_container.get_children():
		child.queue_free()

	var sorted: Array[PlayerRecord] = []
	for pid: int in GameManager.players:
		sorted.append(GameManager.players[pid])
	sorted.sort_custom(func(a: PlayerRecord, b: PlayerRecord) -> bool:
		if a.team.team_id != b.team.team_id:
			return a.team.team_id < b.team.team_id
		return a.slot < b.slot
	)

	for record: PlayerRecord in sorted:
		var row := _make_row()
		_rows_container.add_child(row)
		var s := record.stats
		var pts := s.goals + s.assists
		_fill_row(row,
			["P%d" % (record.slot + 1), str(s.goals), str(s.assists), str(pts), str(s.shots_on_goal), str(s.hits)],
			record.color, false
		)

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
