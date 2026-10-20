class_name GoalGifPicker
extends CanvasLayer

# Post-game "save a goal as a GIF": one row per goal of the match, in scoring
# order. Picking a row closes the picker and hands the index up; the goal then
# airs again behind the game-over screen while it is captured (GameManager.
# save_goal_gif). Opened from GameOverPopup's Save Goal button; Escape closes.

signal goal_picked(index: int)

const _ROW_WIDTH: float = 520.0
# Past this many rows the list scrolls rather than pushing Close off screen.
const _LIST_MAX_HEIGHT: float = 360.0

var _root: Control = null
var _rows: VBoxContainer = null
var _close_btn: Button = null
# Controller focus scope: the game-over popup underneath, walled off while this
# is up. Set by the opener via set_focus_background.
var _focus_background: Control = null
var _focus_restore: Control = null


func _ready() -> void:
	# Over the game-over popup (5), under the pause menu (20) that Escape opens
	# once this has closed.
	layer = 6
	_build_ui()
	visible = false


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var scrim := ColorRect.new()
	scrim.color = MenuStyle.SCRIM
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = MenuStyle.BROADCAST_BG
	style.set_corner_radius_all(8)
	style.set_border_width_all(1)
	style.border_color = MenuStyle.BROADCAST_SEP
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)

	var title := _lbl(tr(&"GOAL_PICKER_TITLE"), 22, MenuStyle.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var hint := _lbl(tr(&"GOAL_PICKER_HINT"), 13, MenuStyle.BROADCAST_DIM)
	hint.add_theme_font_override("font", MenuStyle.UI_FONT)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(_ROW_WIDTH, 0.0)
	col.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)

	_close_btn = MenuStyle.popup_button(tr(&"GOAL_PICKER_CLOSE"))
	_close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_close_btn.pressed.connect(close)
	col.add_child(_close_btn)


# `background` is the screen this covers; focus is walled off there while this
# is up and handed back to whatever held it when this opened.
func set_focus_background(background: Control) -> void:
	_focus_background = background


# `clips` are GoalReplayStore entries in scoring order; a row's index is its
# clip's. `can_save` false lists them without letting one be picked (a save is
# already under way).
func present(clips: Array[Dictionary], can_save: bool) -> void:
	for child: Node in _rows.get_children():
		child.queue_free()
	var first: Button = null
	for i: int in clips.size():
		var row: Button = _build_row(clips[i], i)
		row.disabled = not can_save
		_rows.add_child(row)
		if first == null and can_save:
			first = row
	var scroll := _rows.get_parent() as ScrollContainer
	scroll.custom_minimum_size.y = minf(_LIST_MAX_HEIGHT, clips.size() * 50.0)
	visible = true
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.18)
	_focus_restore = ControllerNav.focus_owner(self)
	ControllerNav.open_modal(_focus_background, self, first if first != null else _close_btn)


func close() -> void:
	if not visible:
		return
	visible = false
	ControllerNav.close_modal(_focus_background, _focus_restore)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# "1ST · SCORER (ASST: A, B)", led by the scoring team's stripe color.
func _build_row(clip: Dictionary, index: int) -> Button:
	var scorer: String = String(clip.get("scorer_name", ""))
	if scorer.is_empty():
		scorer = tr(&"INTERMISSION_GOAL_TAG")
	var assists := PackedStringArray()
	for key: String in ["assist1_name", "assist2_name"]:
		var assist: String = String(clip.get(key, ""))
		if not assist.is_empty():
			assists.append(assist)
	var period: String = HudChrome.period_ordinal(int(clip.get("period", 0)))
	var btn := MenuStyle.popup_button(tr(&"GOAL_PICKER_ROW") % [period, scorer] if assists.is_empty() \
			else tr(&"GOAL_PICKER_ROW_ASSISTS") % [period, scorer, ", ".join(assists)])
	btn.custom_minimum_size = Vector2(_ROW_WIDTH, 44.0)
	btn.add_theme_font_size_override("font_size", 17)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var team_id: int = int(clip.get("scoring_team_id", -1))
	if team_id >= 0:
		btn.add_theme_color_override("font_color", HudChrome.team_stripe(team_id).lightened(0.35))
	btn.pressed.connect(func() -> void: goal_picked.emit(index))
	return btn


func _lbl(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", MenuStyle.DISPLAY_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
