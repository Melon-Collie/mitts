class_name BracketOverlay
extends CanvasLayer
## A modal showing a tournament's bracket with one line under it saying where
## the player stands. Closes on its × and on ui_cancel.

var _root: Control = null
var _bracket: BracketPanel = null
var _status: Label = null
var _close_btn: Button = null
var _focus_background: Control = null
var _focus_restore: Control = null


func _ready() -> void:
	layer = 20
	_build()
	visible = false


# `background` is the menu this covers, walled off from the pad while it is up.
func open(state: TournamentState, background: Control = null) -> void:
	_bracket.show_state(state)
	_status.text = TournamentCopy.status_line(state)
	_focus_background = background
	_focus_restore = ControllerNav.focus_owner(self)
	visible = true
	ControllerNav.open_modal(_focus_background, self, _close_btn)


func close() -> void:
	if not visible:
		return
	visible = false
	ControllerNav.close_modal(_focus_background, _focus_restore)
	_focus_background = null
	_focus_restore = null


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var scrim := ColorRect.new()
	scrim.color = MenuStyle.SCRIM
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(scrim)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", MenuStyle.panel())
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	panel.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)
	var title := Label.new()
	title.text = tr(&"TOURNAMENT_BRACKET")
	MenuStyle.apply_heading(title)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_close_btn = MenuStyle.close_button()
	_close_btn.pressed.connect(close)
	SoundManager.wire_button(_close_btn)
	header.add_child(_close_btn)

	_bracket = BracketPanel.new()
	vbox.add_child(_bracket)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 18)
	_status.add_theme_color_override("font_color", MenuStyle.TEXT_DIM)
	vbox.add_child(_status)
