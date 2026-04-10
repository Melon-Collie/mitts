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
	_ip_field.custom_minimum_size = Vector2(200, 48)
	_ip_field.add_theme_font_size_override("font_size", 18)
	join_row.add_child(_ip_field)

	var join_btn := _make_button("Join")
	join_btn.custom_minimum_size = Vector2(100, 48)
	join_btn.pressed.connect(_on_join_pressed)
	join_row.add_child(join_btn)

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
