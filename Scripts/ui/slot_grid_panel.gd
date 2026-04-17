class_name SlotGridPanel
extends Control

signal slot_selected(team_id: int, slot: int)

const _WHITE    := Color(1.00, 1.00, 1.00, 1.00)
const _DIM      := Color(0.62, 0.62, 0.68, 1.00)

# _buttons[team_id][slot] -> Button
var _buttons: Array = [[], []]

func _init() -> void:
	_build_grid()

func _build_grid() -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(vbox)

	# Away on top (team 1), Home on bottom (team 0) — matches rink perspective.
	for team_id: int in [1, 0]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_child(row)

		var label := Label.new()
		label.text = "AWAY" if team_id == 1 else "HOME"
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", _DIM)
		label.custom_minimum_size = Vector2(44, 0)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(label)

		for s: int in PlayerRules.MAX_PER_TEAM:
			var btn := Button.new()
			btn.custom_minimum_size = Vector2(0, 36)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.add_theme_font_size_override("font_size", 13)
			btn.add_theme_color_override("font_color", PlayerRules.slot_color(team_id, s))
			btn.pressed.connect(_on_button_pressed.bind(team_id, s))
			row.add_child(btn)
			_buttons[team_id].append(btn)

# roster: Array of { team_id, slot, peer_id, player_name }
# local_peer_id: this client's peer ID
func refresh(roster: Array[Dictionary], local_peer_id: int) -> void:
	for team_id: int in 2:
		for s: int in PlayerRules.MAX_PER_TEAM:
			var btn: Button = _buttons[team_id][s]
			btn.text = "%d" % (s + 1)
			btn.disabled = false
			btn.modulate = _WHITE

	for entry: Dictionary in roster:
		var btn: Button = _buttons[entry.team_id][entry.slot]
		if entry.peer_id == local_peer_id:
			btn.text = "You"
			btn.disabled = true
			btn.modulate = Color(1, 1, 1, 0.6)
		else:
			btn.text = entry.player_name if not entry.player_name.is_empty() else "Player"
			btn.disabled = true
			btn.modulate = Color(1, 1, 1, 0.5)

func _on_button_pressed(team_id: int, slot: int) -> void:
	slot_selected.emit(team_id, slot)
