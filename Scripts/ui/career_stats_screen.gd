class_name CareerStatsScreen extends Control

var _reporter := CareerStatsReporter.new()
var _content: VBoxContainer
var _status: Label


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
	panel.custom_minimum_size = Vector2(520.0, 0.0)
	panel.add_theme_stylebox_override("panel", MenuStyle.panel(8, 32))
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	# Header
	var header := HBoxContainer.new()
	vbox.add_child(header)

	var title := Label.new()
	title.text = "Career Stats"
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

	_status = Label.new()
	_status.text = "Loading..."
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", MenuStyle.TEXT_DIM)
	vbox.add_child(_status)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 6)
	vbox.add_child(_content)

	hide()


func open() -> void:
	_clear_content()
	_status.text = "Loading..."
	_status.visible = true
	show()
	_reporter.fetch_totals(_on_totals_received)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		hide()
		get_viewport().set_input_as_handled()


func _on_totals_received(totals: Dictionary) -> void:
	_status.visible = false
	if totals.is_empty():
		_status.text = "No games recorded yet."
		_status.visible = true
		return
	_clear_content()
	_add_row("Games Played",  str(totals.get("games_played", 0)))
	_add_row("Record (W-L)",  "%d-%d" % [totals.get("wins", 0), totals.get("losses", 0)])
	_add_separator()
	_add_row("Goals",         str(totals.get("goals", 0)))
	_add_row("Assists",       str(totals.get("assists", 0)))
	_add_row("Points",        str(totals.get("points", 0)))
	_add_row("Shots on Goal", str(totals.get("shots_on_goal", 0)))
	_add_row("Hits",          str(totals.get("hits", 0)))
	_add_row("Shots Blocked", str(totals.get("shots_blocked", 0)))
	_add_separator()
	_add_row("+/-",           "%+d" % [totals.get("plus_minus", 0)])
	_add_row("Goals For",     str(totals.get("goals_for", 0)))
	_add_row("Goals Against", str(totals.get("goals_against", 0)))
	_add_separator()
	_add_row("Time on Ice",   _format_toi(totals.get("toi_seconds", 0)))
	_add_row("G/60",          str(totals.get("goals_per_60", 0.0)))
	_add_row("A/60",          str(totals.get("assists_per_60", 0.0)))
	_add_row("P/60",          str(totals.get("points_per_60", 0.0)))


func _add_row(label_text: String, value_text: String) -> void:
	var row := HBoxContainer.new()
	_content.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_color_override("font_color", MenuStyle.TEXT_DIM)
	row.add_child(lbl)

	var val := Label.new()
	val.text = value_text
	val.add_theme_color_override("font_color", MenuStyle.TEXT_BODY)
	row.add_child(val)


func _add_separator() -> void:
	var sep := HSeparator.new()
	sep.add_theme_color_override("color", MenuStyle.TEXT_SEP)
	_content.add_child(sep)


func _clear_content() -> void:
	for child: Node in _content.get_children():
		child.queue_free()


static func _format_toi(seconds: Variant) -> String:
	var s: int = int(seconds)
	return "%d:%02d" % [s / 60, s % 60]
