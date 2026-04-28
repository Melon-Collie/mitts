class_name ReplayBrowserScreen extends Control

# Main-menu overlay listing user://replays/. Rows show date / score / size,
# with Watch + Delete buttons. Watch sets NetworkManager.pending_replay_path
# and changes scene to ReplayViewer. Mirrors the CareerStatsScreen pattern
# (Control overlay, hidden by default, opened via open()).

const _ROW_BG: Color    = Color(0.12, 0.12, 0.15, 1.00)
const _ROW_HOVER: Color = Color(0.18, 0.18, 0.22, 1.00)

var _content: VBoxContainer = null
var _empty_label: Label = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.0, 0.0, 0.0, 0.72)
	add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620.0, 0.0)
	panel.add_theme_stylebox_override("panel", MenuStyle.panel(8, 24))
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)

	var title := Label.new()
	title.text = "Replays"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", MenuStyle.TEXT_TITLE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_btn: Button = MenuStyle.close_button()
	close_btn.pressed.connect(hide)
	header.add_child(close_btn)

	var sep := HSeparator.new()
	sep.add_theme_color_override("color", MenuStyle.TEXT_SEP)
	vbox.add_child(sep)

	_empty_label = Label.new()
	_empty_label.text = "No replays yet. Play a multiplayer game to record one."
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.add_theme_color_override("font_color", MenuStyle.TEXT_DIM)
	_empty_label.visible = false
	vbox.add_child(_empty_label)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, 360.0)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 6)
	scroll.add_child(_content)

	hide()


func open() -> void:
	_refresh()
	show()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		hide()
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	for child in _content.get_children():
		child.queue_free()
	var paths: Array[String] = ReplayFileIndex.list()
	_empty_label.visible = paths.is_empty()
	for path: String in paths:
		var row: Control = _build_row(path)
		if row != null:
			_content.add_child(row)


func _build_row(path: String) -> Control:
	var header_result: Dictionary = ReplayFileReader.read_header_only(path)
	if not header_result.ok:
		return null
	var header: Dictionary = header_result.header
	var home_id: String = header.get("home_color_id", TeamColorRegistry.DEFAULT_HOME_ID)
	var away_id: String = header.get("away_color_id", TeamColorRegistry.DEFAULT_AWAY_ID)
	var home_color: Color = TeamColorRegistry.get_colors(home_id, 0).primary
	var away_color: Color = TeamColorRegistry.get_colors(away_id, 1).primary

	# Score lives in the footer, not the header — for v1 we just show players
	# and date in the list; the viewer reveals the score on play.
	var started_at: float = float(header.get("started_at", 0.0))
	var date_str: String = _format_date(started_at)
	var roster: Array = header.get("roster", [])
	var home_names: Array[String] = []
	var away_names: Array[String] = []
	for entry: Variant in roster:
		var e: Dictionary = entry as Dictionary
		var team_id: int = int(e.get("team_id", 0))
		var name_val: String = e.get("player_name", "?")
		if team_id == 0:
			home_names.append(name_val)
		else:
			away_names.append(name_val)
	var size_kb: int = int(round(FileAccess.get_file_as_bytes(path).size() / 1024.0))

	var row_style := StyleBoxFlat.new()
	row_style.bg_color = _ROW_BG
	row_style.set_corner_radius_all(3)
	row_style.set_content_margin_all(10)

	var row_panel := PanelContainer.new()
	row_panel.add_theme_stylebox_override("panel", row_style)
	row_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var row_hbox := HBoxContainer.new()
	row_hbox.add_theme_constant_override("separation", 12)
	row_panel.add_child(row_hbox)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	row_hbox.add_child(info)

	info.add_child(_label(date_str, 13, MenuStyle.TEXT_BODY))
	var teams_hbox := HBoxContainer.new()
	teams_hbox.add_theme_constant_override("separation", 6)
	info.add_child(teams_hbox)
	teams_hbox.add_child(_team_chip(home_color))
	teams_hbox.add_child(_label(", ".join(home_names) if not home_names.is_empty() else "—", 12, MenuStyle.TEXT_DIM))
	teams_hbox.add_child(_label("vs", 12, MenuStyle.TEXT_DIM))
	teams_hbox.add_child(_team_chip(away_color))
	teams_hbox.add_child(_label(", ".join(away_names) if not away_names.is_empty() else "—", 12, MenuStyle.TEXT_DIM))
	info.add_child(_label("%d KB · %s" % [size_kb, header.get("build_version", "?")], 11, MenuStyle.TEXT_DIM))

	var watch_btn := Button.new()
	watch_btn.text = "Watch"
	watch_btn.custom_minimum_size = Vector2(80, 36)
	watch_btn.pressed.connect(_on_watch_pressed.bind(path))
	row_hbox.add_child(watch_btn)

	var delete_btn := Button.new()
	delete_btn.text = "✕"
	delete_btn.custom_minimum_size = Vector2(36, 36)
	delete_btn.pressed.connect(_on_delete_pressed.bind(path))
	row_hbox.add_child(delete_btn)

	return row_panel


func _on_watch_pressed(path: String) -> void:
	NetworkManager.pending_replay_path = path
	get_tree().change_scene_to_file(Constants.SCENE_REPLAY_VIEWER)


func _on_delete_pressed(path: String) -> void:
	DirAccess.remove_absolute(path)
	_refresh()


# ── Helpers ──────────────────────────────────────────────────────────────────

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _team_chip(color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size = Vector2(14, 14)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return r


func _format_date(unix_ts: float) -> String:
	if unix_ts <= 0.0:
		return "—"
	var dt: Dictionary = Time.get_datetime_dict_from_unix_time(int(unix_ts))
	return "%04d-%02d-%02d %02d:%02d" % [dt.year, dt.month, dt.day, dt.hour, dt.minute]
