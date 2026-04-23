class_name OptionsPanel
extends VBoxContainer

signal close_requested

var _res_row: HBoxContainer = null

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

	var video_content := _build_video_tab()
	var audio_content := _build_audio_tab()

	add_child(_build_tab_switcher(
		["Video", "Audio"],
		[video_content, audio_content]
	))

	var done_btn := _make_button("Done")
	done_btn.pressed.connect(func() -> void: close_requested.emit())
	add_child(done_btn)

func _build_tab_switcher(tab_names: Array, contents: Array) -> Control:
	var wrapper := VBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 0)
	wrapper.custom_minimum_size = Vector2(340, 0)

	# Tab button row
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 0)
	wrapper.add_child(bar)

	# Separator line between tab bar and content
	var sep := ColorRect.new()
	sep.color = _SEP
	sep.custom_minimum_size = Vector2(0, 1)
	wrapper.add_child(sep)

	# Content area with padding
	var content_margin := MarginContainer.new()
	content_margin.add_theme_constant_override("margin_top", 16)
	content_margin.add_theme_constant_override("margin_bottom", 8)
	content_margin.add_theme_constant_override("margin_left", 0)
	content_margin.add_theme_constant_override("margin_right", 0)
	for c: Control in contents:
		content_margin.add_child(c)
	wrapper.add_child(content_margin)

	# Build tab buttons and wire switching
	var tab_btns: Array[Button] = []
	for i: int in tab_names.size():
		var btn := Button.new()
		btn.text = tab_names[i]
		btn.flat = true
		btn.custom_minimum_size = Vector2(100, 40)
		btn.add_theme_font_size_override("font_size", 18)
		_apply_tab_style(btn, false)
		bar.add_child(btn)
		tab_btns.append(btn)
		SoundManager.wire_button(btn)

	var activate := func(idx: int) -> void:
		for i: int in contents.size():
			(contents[i] as Control).visible = (i == idx)
		for i: int in tab_btns.size():
			_apply_tab_style(tab_btns[i], i == idx)

	activate.call(0)
	for i: int in tab_btns.size():
		var captured_i := i
		tab_btns[i].pressed.connect(func() -> void: activate.call(captured_i))

	return wrapper

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

	var res_btn := OptionButton.new()
	res_btn.custom_minimum_size = Vector2(160, 48)
	res_btn.add_theme_font_size_override("font_size", 18)
	for i: int in PlayerPrefs.RESOLUTIONS.size():
		var r: Vector2i = PlayerPrefs.RESOLUTIONS[i]
		res_btn.add_item("%dx%d" % [r.x, r.y], i)
	res_btn.selected = PlayerPrefs.resolution_index
	res_btn.item_selected.connect(func(idx: int) -> void:
		PlayerPrefs.resolution_index = idx
		PlayerPrefs.apply_video()
		PlayerPrefs.save())
	_res_row.add_child(res_btn)

	var fs_row := HBoxContainer.new()
	fs_row.alignment = BoxContainer.ALIGNMENT_CENTER
	fs_row.add_theme_constant_override("separation", 12)

	var fs_label := Label.new()
	fs_label.text = "Fullscreen:"
	fs_label.add_theme_font_size_override("font_size", 20)
	fs_label.add_theme_color_override("font_color", _WHITE)
	fs_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fs_row.add_child(fs_label)

	var fs_check := CheckButton.new()
	fs_check.button_pressed = PlayerPrefs.is_fullscreen
	fs_check.add_theme_font_size_override("font_size", 18)
	SoundManager.wire_button(fs_check)
	fs_check.toggled.connect(func(pressed: bool) -> void:
		PlayerPrefs.is_fullscreen = pressed
		PlayerPrefs.apply_video()
		PlayerPrefs.save()
		_res_row.visible = not pressed)
	fs_row.add_child(fs_check)

	box.add_child(fs_row)
	_res_row.visible = not PlayerPrefs.is_fullscreen
	box.add_child(_res_row)

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

	var volume_slider := HSlider.new()
	volume_slider.min_value = 0.0
	volume_slider.max_value = 1.0
	volume_slider.step = 0.01
	volume_slider.value = PlayerPrefs.master_volume
	volume_slider.custom_minimum_size = Vector2(200, 32)
	volume_slider.value_changed.connect(func(v: float) -> void:
		PlayerPrefs.master_volume = v
		PlayerPrefs.apply_audio()
		PlayerPrefs.save())
	volume_row.add_child(volume_slider)
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

	var mute_check := CheckButton.new()
	mute_check.button_pressed = PlayerPrefs.master_muted
	mute_check.add_theme_font_size_override("font_size", 18)
	SoundManager.wire_button(mute_check)
	mute_check.toggled.connect(func(pressed: bool) -> void:
		PlayerPrefs.master_muted = pressed
		PlayerPrefs.apply_audio()
		PlayerPrefs.save())
	mute_row.add_child(mute_check)
	box.add_child(mute_row)

	return box

func _make_button(label: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(308, 48)
	btn.add_theme_font_size_override("font_size", 20)
	SoundManager.wire_button(btn)
	return btn
