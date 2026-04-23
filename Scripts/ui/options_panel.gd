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

const _WHITE  := Color(1.00, 1.00, 1.00, 1.00)
const _DIM    := Color(0.62, 0.62, 0.68, 1.00)
const _SEP    := Color(0.28, 0.28, 0.33, 1.00)

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

	var done_btn := _make_button("Done")
	done_btn.pressed.connect(_on_done_pressed)
	add_child(done_btn)

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

	return box

# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_fullscreen_toggled(pressed: bool) -> void:
	PlayerPrefs.is_fullscreen = pressed
	PlayerPrefs.apply_video()
	PlayerPrefs.save()
	if _res_row != null:
		_res_row.visible = not pressed

func _on_resolution_selected(idx: int) -> void:
	PlayerPrefs.resolution_index = idx
	PlayerPrefs.apply_video()
	PlayerPrefs.save()

func _on_volume_changed(value: float) -> void:
	PlayerPrefs.master_volume = value
	PlayerPrefs.apply_audio()
	PlayerPrefs.save()

func _on_mute_toggled(pressed: bool) -> void:
	PlayerPrefs.master_muted = pressed
	PlayerPrefs.apply_audio()
	PlayerPrefs.save()

func _on_vsync_toggled(pressed: bool) -> void:
	PlayerPrefs.vsync_enabled = pressed
	PlayerPrefs.apply_video()
	PlayerPrefs.save()

func _on_fps_cap_selected(idx: int) -> void:
	PlayerPrefs.fps_cap_index = idx
	PlayerPrefs.apply_video()
	PlayerPrefs.save()

func _on_brightness_changed(value: float) -> void:
	PlayerPrefs.brightness = value
	PlayerPrefs.apply_video()
	PlayerPrefs.save()

func _on_sensitivity_changed(value: float) -> void:
	PlayerPrefs.mouse_sensitivity = value
	PlayerPrefs.save()
	if _sens_field != null:
		_sens_field.text = "%.2f" % value

func _on_sensitivity_typed(text: String) -> void:
	var value: float = clampf(text.to_float(), 0.5, 3.0)
	if _sens_slider != null:
		_sens_slider.value = value

func _on_done_pressed() -> void:
	close_requested.emit()

func _make_button(label: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(308, 48)
	btn.add_theme_font_size_override("font_size", 20)
	SoundManager.wire_button(btn)
	return btn
