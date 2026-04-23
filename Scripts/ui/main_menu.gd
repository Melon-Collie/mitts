class_name MainMenu
extends Control

var _ip_field: LineEdit
var _error_label: Label = null
var _player_popup: Control = null
var _options_popup: Control = null
var _connecting_popup: Control = null

func _ready() -> void:
	TeamColorRegistry.ensure_loaded()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	if not NetworkManager.pending_error.is_empty():
		_error_label.text = NetworkManager.pending_error
		_error_label.visible = true
		NetworkManager.pending_error = ""

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.10, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# ── Center stack ──────────────────────────────────────────────────────────
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "Mitts"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer)

	var offline_btn := _make_button("Play Offline")
	offline_btn.pressed.connect(_on_offline_pressed)
	vbox.add_child(offline_btn)

	var host_btn := _make_button("Host Game")
	host_btn.pressed.connect(_on_host_pressed)
	vbox.add_child(host_btn)

	var join_row := HBoxContainer.new()
	join_row.custom_minimum_size = Vector2(308, 48)
	join_row.add_theme_constant_override("separation", 8)
	vbox.add_child(join_row)

	_ip_field = LineEdit.new()
	_ip_field.placeholder_text = "IP Address"
	_ip_field.text = PlayerPrefs.last_ip
	_ip_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ip_field.add_theme_font_size_override("font_size", 18)
	join_row.add_child(_ip_field)

	var join_btn := Button.new()
	join_btn.text = "Join Game"
	join_btn.custom_minimum_size = Vector2(120, 48)
	join_btn.add_theme_font_size_override("font_size", 20)
	join_btn.pressed.connect(_on_join_pressed)
	_wire_hover_scale(join_btn)
	SoundManager.wire_button(join_btn)
	join_row.add_child(join_btn)

	var player_btn := _make_button("Player")
	player_btn.pressed.connect(_on_player_pressed)
	vbox.add_child(player_btn)

	var options_btn := _make_button("Options")
	options_btn.pressed.connect(_on_options_pressed)
	vbox.add_child(options_btn)

	var exit_btn := _make_button("Exit Game")
	exit_btn.pressed.connect(func() -> void: get_tree().quit())
	vbox.add_child(exit_btn)

	_error_label = Label.new()
	_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error_label.add_theme_font_size_override("font_size", 16)
	_error_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45, 1.0))
	_error_label.visible = false
	vbox.add_child(_error_label)

	var version_label := Label.new()
	version_label.text = "v%s" % BuildInfo.VERSION
	version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version_label.add_theme_font_size_override("font_size", 14)
	version_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.60, 1.0))
	vbox.add_child(version_label)

	var update_checker: UpdateChecker = UpdateChecker.new()
	update_checker.custom_minimum_size = Vector2(380, 0)
	vbox.add_child(update_checker)

	_build_player_popup()
	_build_options_popup()
	_build_connecting_popup()

func _build_player_popup() -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.6)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			_player_popup.visible = false)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.07, 0.07, 0.09, 0.96)
	panel_style.set_corner_radius_all(6)
	panel_style.set_content_margin_all(32)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", panel_style)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Player"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(title)

	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override("separation", 12)
	vbox.add_child(name_row)

	var name_label := Label.new()
	name_label.text = "Name:"
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_row.add_child(name_label)

	var name_field := LineEdit.new()
	name_field.placeholder_text = "Player"
	name_field.max_length = 10
	name_field.custom_minimum_size = Vector2(200, 48)
	name_field.add_theme_font_size_override("font_size", 18)
	name_field.text = PlayerPrefs.player_name
	NetworkManager.local_player_name = PlayerPrefs.player_name
	name_field.text_changed.connect(func(t: String) -> void:
		var trimmed: String = t.strip_edges() if not t.strip_edges().is_empty() else "Player"
		NetworkManager.local_player_name = trimmed
		PlayerPrefs.player_name = trimmed
		PlayerPrefs.save())
	name_row.add_child(name_field)

	var number_row := HBoxContainer.new()
	number_row.alignment = BoxContainer.ALIGNMENT_CENTER
	number_row.add_theme_constant_override("separation", 12)
	vbox.add_child(number_row)

	var number_label := Label.new()
	number_label.text = "Number:"
	number_label.add_theme_font_size_override("font_size", 20)
	number_label.add_theme_color_override("font_color", Color.WHITE)
	number_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	number_row.add_child(number_label)

	var number_field := LineEdit.new()
	number_field.placeholder_text = "10"
	number_field.max_length = 2
	number_field.custom_minimum_size = Vector2(80, 48)
	number_field.add_theme_font_size_override("font_size", 18)
	number_field.text = str(PlayerPrefs.jersey_number)
	NetworkManager.local_jersey_number = PlayerPrefs.jersey_number
	number_field.text_changed.connect(func(t: String) -> void:
		var n: int = t.to_int() if t.is_valid_int() else PlayerPrefs.jersey_number
		n = clamp(n, 0, 99)
		NetworkManager.local_jersey_number = n
		PlayerPrefs.jersey_number = n
		PlayerPrefs.save())
	number_row.add_child(number_field)

	var hand_row := HBoxContainer.new()
	hand_row.alignment = BoxContainer.ALIGNMENT_CENTER
	hand_row.add_theme_constant_override("separation", 12)
	vbox.add_child(hand_row)

	var hand_label := Label.new()
	hand_label.text = "Shoots:"
	hand_label.add_theme_font_size_override("font_size", 20)
	hand_label.add_theme_color_override("font_color", Color.WHITE)
	hand_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hand_row.add_child(hand_label)

	var left_btn := Button.new()
	left_btn.text = "Left"
	left_btn.toggle_mode = true
	left_btn.button_pressed = PlayerPrefs.is_left_handed
	left_btn.custom_minimum_size = Vector2(90, 48)
	left_btn.add_theme_font_size_override("font_size", 18)
	_wire_hover_scale(left_btn)
	SoundManager.wire_button(left_btn)
	hand_row.add_child(left_btn)

	var right_btn := Button.new()
	right_btn.text = "Right"
	right_btn.toggle_mode = true
	right_btn.button_pressed = not PlayerPrefs.is_left_handed
	right_btn.custom_minimum_size = Vector2(90, 48)
	right_btn.add_theme_font_size_override("font_size", 18)
	_wire_hover_scale(right_btn)
	SoundManager.wire_button(right_btn)
	hand_row.add_child(right_btn)

	NetworkManager.local_is_left_handed = PlayerPrefs.is_left_handed

	left_btn.toggled.connect(func(pressed: bool) -> void:
		if not pressed and not right_btn.button_pressed:
			left_btn.button_pressed = true
			return
		right_btn.button_pressed = not pressed
		NetworkManager.local_is_left_handed = pressed
		PlayerPrefs.is_left_handed = pressed
		PlayerPrefs.save())
	right_btn.toggled.connect(func(pressed: bool) -> void:
		if not pressed and not left_btn.button_pressed:
			right_btn.button_pressed = true
			return
		left_btn.button_pressed = not pressed
		NetworkManager.local_is_left_handed = not pressed
		PlayerPrefs.is_left_handed = not pressed
		PlayerPrefs.save())

	var done_btn := _make_button("Done")
	done_btn.pressed.connect(func() -> void: _player_popup.visible = false)
	vbox.add_child(done_btn)

	_player_popup = Control.new()
	_player_popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_player_popup.visible = false
	_player_popup.add_child(overlay)
	_player_popup.add_child(panel)
	add_child(_player_popup)

func _build_options_popup() -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.6)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			_options_popup.visible = false)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.07, 0.07, 0.09, 0.96)
	panel_style.set_corner_radius_all(6)
	panel_style.set_content_margin_all(32)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", panel_style)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH

	var options := OptionsPanel.new()
	options.close_requested.connect(func() -> void: _options_popup.visible = false)
	panel.add_child(options)

	_options_popup = Control.new()
	_options_popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_options_popup.visible = false
	_options_popup.add_child(overlay)
	_options_popup.add_child(panel)
	add_child(_options_popup)

func _build_connecting_popup() -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.65)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.07, 0.07, 0.09, 0.96)
	panel_style.set_corner_radius_all(6)
	panel_style.set_content_margin_all(36)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", panel_style)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	panel.add_child(vbox)

	var status_label := Label.new()
	status_label.name = "StatusLabel"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 22)
	status_label.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(status_label)

	var cancel_btn := _make_button("Cancel")
	cancel_btn.pressed.connect(_on_join_cancelled)
	vbox.add_child(cancel_btn)

	_connecting_popup = Control.new()
	_connecting_popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_connecting_popup.visible = false
	_connecting_popup.add_child(overlay)
	_connecting_popup.add_child(panel)
	add_child(_connecting_popup)

func _show_connecting(ip: String) -> void:
	var label := _connecting_popup.find_child("StatusLabel", true, false) as Label
	if label:
		label.text = "Connecting to %s..." % ip
	_connecting_popup.visible = true

func _on_join_cancelled() -> void:
	_disconnect_join_signals()
	NetworkManager.reset()
	_connecting_popup.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _connecting_popup.visible:
			_on_join_cancelled()
			get_viewport().set_input_as_handled()
		elif _player_popup.visible:
			_player_popup.visible = false
			get_viewport().set_input_as_handled()
		elif _options_popup.visible:
			_options_popup.visible = false
			get_viewport().set_input_as_handled()

func _on_player_pressed() -> void:
	_player_popup.visible = true

func _on_options_pressed() -> void:
	_options_popup.visible = true

func _make_button(label: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(308, 48)
	btn.add_theme_font_size_override("font_size", 20)
	_wire_hover_scale(btn)
	SoundManager.wire_button(btn)
	return btn

func _wire_hover_scale(btn: Button) -> void:
	btn.item_rect_changed.connect(func() -> void: btn.pivot_offset = btn.size / 2.0)
	btn.mouse_entered.connect(func() -> void: _scale_btn(btn, Vector2(1.04, 1.04)))
	btn.mouse_exited.connect(func() -> void: _scale_btn(btn, Vector2.ONE))
	btn.button_down.connect(func() -> void: _scale_btn(btn, Vector2(0.97, 0.97)))
	btn.button_up.connect(func() -> void: _scale_btn(btn, Vector2(1.04, 1.04)))

func _scale_btn(btn: Button, target: Vector2) -> void:
	var t := btn.create_tween()
	t.tween_property(btn, "scale", target, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _on_offline_pressed() -> void:
	NetworkManager.start_offline()
	get_tree().change_scene_to_file(Constants.SCENE_HOCKEY)

func _on_host_pressed() -> void:
	NetworkManager.start_host()
	get_tree().change_scene_to_file(Constants.SCENE_LOBBY)

func _on_join_pressed() -> void:
	var ip: String = _ip_field.text.strip_edges()
	if ip.is_empty():
		return
	PlayerPrefs.last_ip = ip
	PlayerPrefs.save()
	_disconnect_join_signals()
	NetworkManager.start_client(ip)
	_show_connecting(ip)
	NetworkManager.lobby_roster_synced.connect(_on_join_got_lobby, CONNECT_ONE_SHOT)
	NetworkManager.join_in_progress.connect(_on_join_got_game, CONNECT_ONE_SHOT)

func _disconnect_join_signals() -> void:
	if NetworkManager.lobby_roster_synced.is_connected(_on_join_got_lobby):
		NetworkManager.lobby_roster_synced.disconnect(_on_join_got_lobby)
	if NetworkManager.join_in_progress.is_connected(_on_join_got_game):
		NetworkManager.join_in_progress.disconnect(_on_join_got_game)

func _on_join_got_lobby(_roster: Array) -> void:
	if NetworkManager.join_in_progress.is_connected(_on_join_got_game):
		NetworkManager.join_in_progress.disconnect(_on_join_got_game)
	get_tree().change_scene_to_file(Constants.SCENE_LOBBY)

func _on_join_got_game(config: Dictionary) -> void:
	if NetworkManager.lobby_roster_synced.is_connected(_on_join_got_lobby):
		NetworkManager.lobby_roster_synced.disconnect(_on_join_got_lobby)
	NetworkManager.pending_game_config = config
	get_tree().change_scene_to_file(Constants.SCENE_HOCKEY)
