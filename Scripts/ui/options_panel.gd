class_name OptionsPanel
extends VBoxContainer

signal close_requested

var _res_row: HBoxContainer = null
var _fs_check: CheckButton = null
var _mute_check: CheckButton = null
var _volume_slider: HSlider = null
var _res_btn: OptionButton = null
var _tab_contents: Array[Control] = []
var _tab_btns: Array[Button] = []
var _vsync_check: CheckButton = null
var _fps_btn: OptionButton = null
var _brightness_slider: HSlider = null
var _sens_slider: HSlider = null
var _sens_field: LineEdit = null
var _apply_btn: Button = null
var _original: Dictionary = {}
var _listening_action: String = ""
var _pending_bindings: Dictionary = {}
var _binding_btns: Dictionary = {}
var _conflict_label: Label = null

const _WHITE  := Color(1.00, 1.00, 1.00, 1.00)
const _DIM    := Color(0.62, 0.62, 0.68, 1.00)
const _SEP    := Color(0.28, 0.28, 0.33, 1.00)
const _REBINDABLE_ACTIONS: Array = [
	{"action": "move_up",        "label": "Move Up"},
	{"action": "move_down",      "label": "Move Down"},
	{"action": "move_left",      "label": "Move Left"},
	{"action": "move_right",     "label": "Move Right"},
	{"action": "brake",          "label": "Brake"},
	{"action": "shoot",          "label": "Shoot"},
	{"action": "slapshot",       "label": "Slapshot"},
	{"action": "self_pass",      "label": "Self Pass"},
	{"action": "self_shot",      "label": "Self Shot"},
	{"action": "block",          "label": "Block"},
	{"action": "elevation_up",   "label": "Elevation Up"},
	{"action": "elevation_down", "label": "Elevation Down"},
	{"action": "reset",          "label": "Reset"},
]

func _ready() -> void:
	add_theme_constant_override("separation", 16)
	alignment = BoxContainer.ALIGNMENT_CENTER

	var title := Label.new()
	title.text = "Options"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", _WHITE)
	add_child(title)

	add_child(_build_tab_switcher())

	_original = _snapshot()

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	add_child(btn_row)

	_apply_btn = _make_small_button("Apply")
	_apply_btn.pressed.connect(_on_apply_pressed)
	_apply_btn.disabled = true
	btn_row.add_child(_apply_btn)

	var cancel_btn := _make_small_button("Cancel")
	cancel_btn.pressed.connect(_on_cancel_pressed)
	btn_row.add_child(cancel_btn)

func _snapshot() -> Dictionary:
	return {
		"fullscreen": PlayerPrefs.is_fullscreen,
		"resolution_index": PlayerPrefs.resolution_index,
		"vsync_enabled": PlayerPrefs.vsync_enabled,
		"fps_cap_index": PlayerPrefs.fps_cap_index,
		"brightness": PlayerPrefs.brightness,
		"master_volume": PlayerPrefs.master_volume,
		"master_muted": PlayerPrefs.master_muted,
		"mouse_sensitivity": PlayerPrefs.mouse_sensitivity,
		"bindings": PlayerPrefs.bindings.duplicate(true),
	}

func _read_controls() -> Dictionary:
	return {
		"fullscreen": _fs_check.button_pressed,
		"resolution_index": _res_btn.selected,
		"vsync_enabled": _vsync_check.button_pressed,
		"fps_cap_index": _fps_btn.selected,
		"brightness": _brightness_slider.value,
		"master_volume": _volume_slider.value,
		"master_muted": _mute_check.button_pressed,
		"mouse_sensitivity": _sens_slider.value,
		"bindings": _pending_bindings.duplicate(true),
	}

func _update_apply_state() -> void:
	if _apply_btn != null:
		var changed: bool = _read_controls() != _original
		_apply_btn.disabled = not changed or _has_conflicts()

func _build_tab_switcher() -> Control:
	var wrapper := VBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 0)
	wrapper.custom_minimum_size = Vector2(340, 0)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 0)
	wrapper.add_child(bar)

	var sep := ColorRect.new()
	sep.color = _SEP
	sep.custom_minimum_size = Vector2(0, 1)
	wrapper.add_child(sep)

	var content_margin := MarginContainer.new()
	content_margin.add_theme_constant_override("margin_top", 16)
	content_margin.add_theme_constant_override("margin_bottom", 8)
	content_margin.add_theme_constant_override("margin_left", 0)
	content_margin.add_theme_constant_override("margin_right", 0)
	wrapper.add_child(content_margin)

	var video_tab := _build_video_tab()
	var audio_tab := _build_audio_tab()
	var input_tab := _build_input_tab()
	_tab_contents = [video_tab, audio_tab, input_tab]
	content_margin.add_child(video_tab)
	content_margin.add_child(audio_tab)
	content_margin.add_child(input_tab)

	for i: int in ["Video", "Audio", "Input"].size():
		var btn := Button.new()
		btn.text = ["Video", "Audio", "Input"][i]
		btn.flat = true
		btn.custom_minimum_size = Vector2(100, 40)
		btn.add_theme_font_size_override("font_size", 18)
		bar.add_child(btn)
		_tab_btns.append(btn)
		SoundManager.wire_button(btn)
		btn.pressed.connect(_activate_tab.bind(i))

	_activate_tab(0)
	return wrapper

func _activate_tab(idx: int) -> void:
	if idx != 2 and not _listening_action.is_empty():
		_listening_action = ""
		_update_binding_btns()
	for i: int in _tab_contents.size():
		_tab_contents[i].visible = (i == idx)
	for i: int in _tab_btns.size():
		_apply_tab_style(_tab_btns[i], i == idx)

func _apply_tab_style(btn: Button, active: bool) -> void:
	var s := StyleBoxFlat.new()
	s.set_corner_radius_all(0)
	s.set_content_margin(SIDE_LEFT, 16)
	s.set_content_margin(SIDE_RIGHT, 16)
	s.set_content_margin(SIDE_TOP, 8)
	s.set_content_margin(SIDE_BOTTOM, 8)
	s.bg_color = Color(0.14, 0.14, 0.17, 1.0) if active else Color(0.0, 0.0, 0.0, 0.0)
	for state: StringName in [&"normal", &"hover", &"pressed", &"focus"]:
		btn.add_theme_stylebox_override(state, s)
	btn.add_theme_color_override("font_color", _WHITE if active else _DIM)

func _build_video_tab() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.alignment = BoxContainer.ALIGNMENT_CENTER

	_res_row = HBoxContainer.new()
	_res_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_res_row.add_theme_constant_override("separation", 12)

	var res_label := Label.new()
	res_label.text = "Resolution:"
	res_label.add_theme_font_size_override("font_size", 20)
	res_label.add_theme_color_override("font_color", _WHITE)
	res_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_res_row.add_child(res_label)

	_res_btn = OptionButton.new()
	_res_btn.custom_minimum_size = Vector2(160, 48)
	_res_btn.add_theme_font_size_override("font_size", 18)
	for i: int in PlayerPrefs.RESOLUTIONS.size():
		var r: Vector2i = PlayerPrefs.RESOLUTIONS[i]
		_res_btn.add_item("%dx%d" % [r.x, r.y], i)
	_res_btn.selected = PlayerPrefs.resolution_index
	_res_btn.item_selected.connect(_on_resolution_selected)
	_res_row.add_child(_res_btn)

	var fs_row := HBoxContainer.new()
	fs_row.alignment = BoxContainer.ALIGNMENT_CENTER
	fs_row.add_theme_constant_override("separation", 12)

	var fs_label := Label.new()
	fs_label.text = "Fullscreen:"
	fs_label.add_theme_font_size_override("font_size", 20)
	fs_label.add_theme_color_override("font_color", _WHITE)
	fs_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fs_row.add_child(fs_label)

	_fs_check = CheckButton.new()
	_fs_check.set_pressed_no_signal(PlayerPrefs.is_fullscreen)
	_fs_check.add_theme_font_size_override("font_size", 18)
	SoundManager.wire_button(_fs_check)
	_fs_check.toggled.connect(_on_fullscreen_toggled)
	fs_row.add_child(_fs_check)

	box.add_child(fs_row)
	_res_row.visible = not PlayerPrefs.is_fullscreen
	box.add_child(_res_row)

	var vsync_row := HBoxContainer.new()
	vsync_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vsync_row.add_theme_constant_override("separation", 12)
	var vsync_label := Label.new()
	vsync_label.text = "VSync:"
	vsync_label.add_theme_font_size_override("font_size", 20)
	vsync_label.add_theme_color_override("font_color", _WHITE)
	vsync_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vsync_row.add_child(vsync_label)
	_vsync_check = CheckButton.new()
	_vsync_check.set_pressed_no_signal(PlayerPrefs.vsync_enabled)
	_vsync_check.add_theme_font_size_override("font_size", 18)
	SoundManager.wire_button(_vsync_check)
	_vsync_check.toggled.connect(_on_vsync_toggled)
	vsync_row.add_child(_vsync_check)
	box.add_child(vsync_row)

	var fps_row := HBoxContainer.new()
	fps_row.alignment = BoxContainer.ALIGNMENT_CENTER
	fps_row.add_theme_constant_override("separation", 12)
	var fps_label := Label.new()
	fps_label.text = "FPS Cap:"
	fps_label.add_theme_font_size_override("font_size", 20)
	fps_label.add_theme_color_override("font_color", _WHITE)
	fps_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fps_row.add_child(fps_label)
	_fps_btn = OptionButton.new()
	_fps_btn.custom_minimum_size = Vector2(140, 48)
	_fps_btn.add_theme_font_size_override("font_size", 18)
	for label: String in ["30", "60", "120", "144", "240", "Unlimited"]:
		_fps_btn.add_item(label)
	_fps_btn.selected = PlayerPrefs.fps_cap_index
	_fps_btn.item_selected.connect(_on_fps_cap_selected)
	fps_row.add_child(_fps_btn)
	box.add_child(fps_row)

	var bright_row := HBoxContainer.new()
	bright_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bright_row.add_theme_constant_override("separation", 12)
	var bright_label := Label.new()
	bright_label.text = "Brightness:"
	bright_label.add_theme_font_size_override("font_size", 20)
	bright_label.add_theme_color_override("font_color", _WHITE)
	bright_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bright_row.add_child(bright_label)
	_brightness_slider = HSlider.new()
	_brightness_slider.min_value = 0.5
	_brightness_slider.max_value = 1.5
	_brightness_slider.step = 0.05
	_brightness_slider.value = PlayerPrefs.brightness
	_brightness_slider.custom_minimum_size = Vector2(200, 32)
	_brightness_slider.value_changed.connect(_on_brightness_changed)
	bright_row.add_child(_brightness_slider)
	box.add_child(bright_row)

	return box

func _build_audio_tab() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.alignment = BoxContainer.ALIGNMENT_CENTER

	var volume_row := HBoxContainer.new()
	volume_row.alignment = BoxContainer.ALIGNMENT_CENTER
	volume_row.add_theme_constant_override("separation", 12)

	var volume_label := Label.new()
	volume_label.text = "Volume:"
	volume_label.add_theme_font_size_override("font_size", 20)
	volume_label.add_theme_color_override("font_color", _WHITE)
	volume_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	volume_row.add_child(volume_label)

	_volume_slider = HSlider.new()
	_volume_slider.min_value = 0.0
	_volume_slider.max_value = 1.0
	_volume_slider.step = 0.01
	_volume_slider.value = PlayerPrefs.master_volume
	_volume_slider.custom_minimum_size = Vector2(200, 32)
	_volume_slider.value_changed.connect(_on_volume_changed)
	volume_row.add_child(_volume_slider)
	box.add_child(volume_row)

	var mute_row := HBoxContainer.new()
	mute_row.alignment = BoxContainer.ALIGNMENT_CENTER
	mute_row.add_theme_constant_override("separation", 12)

	var mute_label := Label.new()
	mute_label.text = "Mute:"
	mute_label.add_theme_font_size_override("font_size", 20)
	mute_label.add_theme_color_override("font_color", _WHITE)
	mute_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mute_row.add_child(mute_label)

	_mute_check = CheckButton.new()
	_mute_check.set_pressed_no_signal(PlayerPrefs.master_muted)
	_mute_check.add_theme_font_size_override("font_size", 18)
	SoundManager.wire_button(_mute_check)
	_mute_check.toggled.connect(_on_mute_toggled)
	mute_row.add_child(_mute_check)
	box.add_child(mute_row)

	return box

func _build_input_tab() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.alignment = BoxContainer.ALIGNMENT_CENTER

	var sens_row := HBoxContainer.new()
	sens_row.alignment = BoxContainer.ALIGNMENT_CENTER
	sens_row.add_theme_constant_override("separation", 12)
	var sens_label := Label.new()
	sens_label.text = "Mouse Sensitivity:"
	sens_label.add_theme_font_size_override("font_size", 20)
	sens_label.add_theme_color_override("font_color", _WHITE)
	sens_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sens_row.add_child(sens_label)
	_sens_slider = HSlider.new()
	_sens_slider.min_value = 0.5
	_sens_slider.max_value = 3.0
	_sens_slider.step = 0.05
	_sens_slider.value = PlayerPrefs.mouse_sensitivity
	_sens_slider.custom_minimum_size = Vector2(160, 32)
	_sens_slider.value_changed.connect(_on_sensitivity_changed)
	sens_row.add_child(_sens_slider)
	_sens_field = LineEdit.new()
	_sens_field.text = "%.2f" % PlayerPrefs.mouse_sensitivity
	_sens_field.custom_minimum_size = Vector2(64, 32)
	_sens_field.add_theme_font_size_override("font_size", 18)
	_sens_field.text_submitted.connect(_on_sensitivity_typed)
	_sens_field.focus_exited.connect(func() -> void: _on_sensitivity_typed(_sens_field.text))
	sens_row.add_child(_sens_field)
	box.add_child(sens_row)

	var bind_lbl := Label.new()
	bind_lbl.text = "Key Bindings"
	bind_lbl.add_theme_font_size_override("font_size", 16)
	bind_lbl.add_theme_color_override("font_color", _DIM)
	bind_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(bind_lbl)

	_pending_bindings = PlayerPrefs.bindings.duplicate(true)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(320, 240)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)

	var grid := VBoxContainer.new()
	grid.add_theme_constant_override("separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)

	for entry: Dictionary in _REBINDABLE_ACTIONS:
		var action: String = entry.action
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(row)

		var lbl := Label.new()
		lbl.text = entry.label
		lbl.custom_minimum_size = Vector2(140, 0)
		lbl.add_theme_font_size_override("font_size", 16)
		lbl.add_theme_color_override("font_color", _WHITE)
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(130, 32)
		btn.add_theme_font_size_override("font_size", 15)
		btn.text = _binding_display(_pending_bindings.get(action, {}))
		btn.pressed.connect(_on_bind_btn_pressed.bind(action))
		SoundManager.wire_button(btn)
		row.add_child(btn)
		_binding_btns[action] = btn

	_conflict_label = Label.new()
	_conflict_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_conflict_label.add_theme_font_size_override("font_size", 14)
	_conflict_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3, 1.0))
	_conflict_label.text = ""
	box.add_child(_conflict_label)

	return box

# ---------------------------------------------------------------------------
# Signal handlers — controls only; no PlayerPrefs writes until Apply
# ---------------------------------------------------------------------------

func _on_fullscreen_toggled(_pressed: bool) -> void:
	if _res_row != null:
		_res_row.visible = not _fs_check.button_pressed
	_update_apply_state()

func _on_resolution_selected(_idx: int) -> void:
	_update_apply_state()

func _on_volume_changed(_value: float) -> void:
	_update_apply_state()

func _on_mute_toggled(_pressed: bool) -> void:
	_update_apply_state()

func _on_vsync_toggled(_pressed: bool) -> void:
	_update_apply_state()

func _on_fps_cap_selected(_idx: int) -> void:
	_update_apply_state()

func _on_brightness_changed(_value: float) -> void:
	_update_apply_state()

func _on_sensitivity_changed(value: float) -> void:
	if _sens_field != null:
		_sens_field.text = "%.2f" % value
	_update_apply_state()

func _on_sensitivity_typed(text: String) -> void:
	var value: float = clampf(text.to_float(), 0.5, 3.0)
	if _sens_slider != null:
		_sens_slider.value = value

func _on_bind_btn_pressed(action: String) -> void:
	_listening_action = action
	_update_binding_btns()

func _input(event: InputEvent) -> void:
	if _listening_action.is_empty():
		return
	if event is InputEventKey:
		if not (event as InputEventKey).pressed:
			return
		if (event as InputEventKey).physical_keycode == KEY_ESCAPE:
			_listening_action = ""
			_update_binding_btns()
			get_viewport().set_input_as_handled()
			return
		_pending_bindings[_listening_action] = {
			"type": "key",
			"physical_keycode": int((event as InputEventKey).physical_keycode),
		}
		_listening_action = ""
		_update_binding_btns()
		_update_conflict_label()
		_update_apply_state()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		if not (event as InputEventMouseButton).pressed:
			return
		_pending_bindings[_listening_action] = {
			"type": "mouse",
			"button_index": int((event as InputEventMouseButton).button_index),
		}
		_listening_action = ""
		_update_binding_btns()
		_update_conflict_label()
		_update_apply_state()
		get_viewport().set_input_as_handled()

func _update_binding_btns() -> void:
	for action: String in _binding_btns:
		var btn: Button = _binding_btns[action]
		if action == _listening_action:
			btn.text = "..."
		else:
			btn.text = _binding_display(_pending_bindings.get(action, {}))

func _update_conflict_label() -> void:
	if _conflict_label == null:
		return
	_conflict_label.text = "Conflicting bindings — cannot apply" if _has_conflicts() else ""

func _has_conflicts() -> bool:
	var seen: Dictionary = {}
	for action: String in _pending_bindings:
		var fp: String = _binding_fingerprint(_pending_bindings[action])
		if fp.is_empty():
			continue
		if seen.has(fp):
			return true
		seen[fp] = true
	return false

func _binding_fingerprint(b: Dictionary) -> String:
	if b.get("type") == "key":
		return "k:%d" % b.physical_keycode
	elif b.get("type") == "mouse":
		return "m:%d" % b.button_index
	return ""

func _binding_display(b: Dictionary) -> String:
	if b.is_empty():
		return "—"
	if b.get("type") == "key":
		return OS.get_keycode_string(b.physical_keycode as Key)
	elif b.get("type") == "mouse":
		match int(b.button_index):
			MOUSE_BUTTON_LEFT:       return "LMB"
			MOUSE_BUTTON_RIGHT:      return "RMB"
			MOUSE_BUTTON_MIDDLE:     return "MMB"
			MOUSE_BUTTON_WHEEL_UP:   return "Scroll Up"
			MOUSE_BUTTON_WHEEL_DOWN: return "Scroll Down"
			_: return "Mouse %d" % b.button_index
	return "—"

# ---------------------------------------------------------------------------
# Apply / Cancel
# ---------------------------------------------------------------------------

func _on_apply_pressed() -> void:
	var c: Dictionary = _read_controls()
	PlayerPrefs.is_fullscreen = c.fullscreen
	PlayerPrefs.resolution_index = c.resolution_index
	PlayerPrefs.vsync_enabled = c.vsync_enabled
	PlayerPrefs.fps_cap_index = c.fps_cap_index
	PlayerPrefs.brightness = c.brightness
	PlayerPrefs.master_volume = c.master_volume
	PlayerPrefs.master_muted = c.master_muted
	PlayerPrefs.mouse_sensitivity = c.mouse_sensitivity
	PlayerPrefs.bindings = (_pending_bindings as Dictionary).duplicate(true)
	PlayerPrefs.apply_audio()
	PlayerPrefs.apply_video()
	PlayerPrefs.apply_bindings()
	PlayerPrefs.save()
	_original = _snapshot()
	_apply_btn.disabled = true
	close_requested.emit()

func _on_cancel_pressed() -> void:
	_fs_check.set_pressed_no_signal(_original.fullscreen)
	if _res_row != null:
		_res_row.visible = not _original.fullscreen
	_res_btn.selected = _original.resolution_index
	_vsync_check.set_pressed_no_signal(_original.vsync_enabled)
	_fps_btn.selected = _original.fps_cap_index
	_brightness_slider.value = _original.brightness
	_volume_slider.value = _original.master_volume
	_mute_check.set_pressed_no_signal(_original.master_muted)
	_sens_slider.value = _original.mouse_sensitivity
	_listening_action = ""
	_pending_bindings = (_original.get("bindings", {}) as Dictionary).duplicate(true)
	_update_binding_btns()
	if _conflict_label != null:
		_conflict_label.text = ""
	close_requested.emit()

func _make_button(label: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(308, 48)
	btn.add_theme_font_size_override("font_size", 20)
	SoundManager.wire_button(btn)
	return btn

func _make_small_button(label: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(148, 48)
	btn.add_theme_font_size_override("font_size", 20)
	SoundManager.wire_button(btn)
	return btn
