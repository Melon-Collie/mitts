class_name MainMenu
extends Control

const GAME_SCENE: String = "res://Scenes/Hockey.tscn"

var _ip_field: LineEdit

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.10, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "Hockey Game"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer)

	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override("separation", 12)
	vbox.add_child(name_row)

	var name_label := Label.new()
	name_label.text = "Name:"
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_row.add_child(name_label)

	var name_field := LineEdit.new()
	name_field.placeholder_text = "Player"
	name_field.max_length = 16
	name_field.custom_minimum_size = Vector2(200, 48)
	name_field.add_theme_font_size_override("font_size", 18)
	name_field.text_changed.connect(func(t: String) -> void:
		NetworkManager.local_player_name = t.strip_edges() if not t.strip_edges().is_empty() else "Player")
	name_row.add_child(name_field)

	var hand_row := HBoxContainer.new()
	hand_row.alignment = BoxContainer.ALIGNMENT_CENTER
	hand_row.add_theme_constant_override("separation", 12)
	vbox.add_child(hand_row)

	var hand_label := Label.new()
	hand_label.text = "Shoots:"
	hand_label.add_theme_font_size_override("font_size", 20)
	hand_label.add_theme_color_override("font_color", Color.WHITE)
	hand_row.add_child(hand_label)

	var left_btn := Button.new()
	left_btn.text = "Left"
	left_btn.toggle_mode = true
	left_btn.button_pressed = true
	left_btn.custom_minimum_size = Vector2(90, 48)
	left_btn.add_theme_font_size_override("font_size", 18)
	hand_row.add_child(left_btn)

	var right_btn := Button.new()
	right_btn.text = "Right"
	right_btn.toggle_mode = true
	right_btn.button_pressed = false
	right_btn.custom_minimum_size = Vector2(90, 48)
	right_btn.add_theme_font_size_override("font_size", 18)
	hand_row.add_child(right_btn)

	# Keep the two buttons mutually exclusive
	left_btn.toggled.connect(func(pressed: bool) -> void:
		if not pressed and not right_btn.button_pressed:
			left_btn.button_pressed = true
			return
		right_btn.button_pressed = not pressed
		NetworkManager.local_is_left_handed = pressed)
	right_btn.toggled.connect(func(pressed: bool) -> void:
		if not pressed and not left_btn.button_pressed:
			right_btn.button_pressed = true
			return
		left_btn.button_pressed = not pressed
		NetworkManager.local_is_left_handed = not pressed)

	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(spacer2)

	var offline_btn := _make_button("Play Offline")
	offline_btn.pressed.connect(_on_offline_pressed)
	vbox.add_child(offline_btn)

	var host_btn := _make_button("Host Game")
	host_btn.pressed.connect(_on_host_pressed)
	vbox.add_child(host_btn)

	var join_row := HBoxContainer.new()
	join_row.alignment = BoxContainer.ALIGNMENT_CENTER
	join_row.add_theme_constant_override("separation", 8)
	vbox.add_child(join_row)

	_ip_field = LineEdit.new()
	_ip_field.placeholder_text = "IP Address"
	_ip_field.text = "127.0.0.1"
	_ip_field.custom_minimum_size = Vector2(200, 48)
	_ip_field.add_theme_font_size_override("font_size", 18)
	join_row.add_child(_ip_field)

	var join_btn := _make_button("Join")
	join_btn.custom_minimum_size = Vector2(100, 48)
	join_btn.pressed.connect(_on_join_pressed)
	join_row.add_child(join_btn)

	var spacer3 := Control.new()
	spacer3.custom_minimum_size = Vector2(0, 16)
	vbox.add_child(spacer3)

	var version_label := Label.new()
	version_label.text = "v%s" % BuildInfo.VERSION
	version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version_label.add_theme_font_size_override("font_size", 14)
	version_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.60, 1.0))
	vbox.add_child(version_label)

	var update_checker: UpdateChecker = UpdateChecker.new()
	update_checker.custom_minimum_size = Vector2(380, 0)
	vbox.add_child(update_checker)

func _make_button(label: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(308, 48)
	btn.add_theme_font_size_override("font_size", 20)
	return btn

func _on_offline_pressed() -> void:
	NetworkManager.start_offline()
	get_tree().change_scene_to_file(GAME_SCENE)

func _on_host_pressed() -> void:
	NetworkManager.start_host()
	get_tree().change_scene_to_file(GAME_SCENE)

func _on_join_pressed() -> void:
	var ip: String = _ip_field.text.strip_edges()
	if ip.is_empty():
		return
	NetworkManager.start_client(ip)
	get_tree().change_scene_to_file(GAME_SCENE)
