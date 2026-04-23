class_name OptionsPanel
extends VBoxContainer

signal close_requested

func _ready() -> void:
	add_theme_constant_override("separation", 16)
	alignment = BoxContainer.ALIGNMENT_CENTER

	var title := Label.new()
	title.text = "Options"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color.WHITE)
	add_child(title)

	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(340, 0)
	add_child(tabs)

	var video_tab := _build_video_tab()
	video_tab.name = "Video"
	tabs.add_child(video_tab)

	var audio_tab := _build_audio_tab()
	audio_tab.name = "Audio"
	tabs.add_child(audio_tab)

	var done_btn := _make_button("Done")
	done_btn.pressed.connect(func() -> void: close_requested.emit())
	add_child(done_btn)

func _build_video_tab() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.alignment = BoxContainer.ALIGNMENT_CENTER

	var res_row := HBoxContainer.new()
	res_row.alignment = BoxContainer.ALIGNMENT_CENTER
	res_row.add_theme_constant_override("separation", 12)

	var res_label := Label.new()
	res_label.text = "Resolution:"
	res_label.add_theme_font_size_override("font_size", 20)
	res_label.add_theme_color_override("font_color", Color.WHITE)
	res_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	res_row.add_child(res_label)

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
	res_row.add_child(res_btn)

	var fs_row := HBoxContainer.new()
	fs_row.alignment = BoxContainer.ALIGNMENT_CENTER
	fs_row.add_theme_constant_override("separation", 12)

	var fs_label := Label.new()
	fs_label.text = "Fullscreen:"
	fs_label.add_theme_font_size_override("font_size", 20)
	fs_label.add_theme_color_override("font_color", Color.WHITE)
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
		res_row.visible = not pressed)
	fs_row.add_child(fs_check)

	box.add_child(fs_row)
	res_row.visible = not PlayerPrefs.is_fullscreen
	box.add_child(res_row)

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
	volume_label.add_theme_color_override("font_color", Color.WHITE)
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
	mute_label.add_theme_color_override("font_color", Color.WHITE)
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
