class_name SlotGridPanel
extends VBoxContainer

signal slot_selected(team_id: int, slot: int)

const _WHITE    := Color(1.00, 1.00, 1.00, 1.00)
const _DIM      := Color(0.62, 0.62, 0.68, 1.00)
const _FALLBACK := Color(0.12, 0.12, 0.15, 1.00)

# Column display order: Left Wing (slot 1), Center (slot 0), Right Wing (slot 2)
const _DISPLAY_ORDER   := [1, 0, 2]
const _POSITION_LABEL  := ["C", "L", "R"]   # indexed by slot
const _POSITION_HEADER := ["L", "C", "R"]   # matches _DISPLAY_ORDER

# _buttons[team_id][slot] -> Button
var _buttons: Array = [[], []]
# parallel label arrays, same [team_id][slot] key structure
var _num_labels:  Array = [[], []]
var _name_labels: Array = [[], []]
var _hand_labels: Array = [[], []]

var _team_colors: Array[Dictionary] = []

func _init() -> void:
	_build_grid()

func _build_grid() -> void:
	add_theme_constant_override("separation", 4)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Header row: blank spacer + L / C / R column labels
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(header)

	var spacer := Label.new()
	spacer.custom_minimum_size = Vector2(44, 0)
	header.add_child(spacer)

	for col: int in _DISPLAY_ORDER.size():
		var lbl := Label.new()
		lbl.text = _POSITION_HEADER[col]
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", _DIM)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		header.add_child(lbl)

	# Away on top (team 1), Home on bottom (team 0) — matches rink perspective.
	for team_id: int in [1, 0]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_child(row)

		var label := Label.new()
		label.text = "AWAY" if team_id == 1 else "HOME"
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", _DIM)
		label.custom_minimum_size = Vector2(44, 0)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(label)

		# Pad button arrays to slot count so index assignment works by slot.
		_buttons[team_id].resize(PlayerRules.MAX_PER_TEAM)
		_num_labels[team_id].resize(PlayerRules.MAX_PER_TEAM)
		_name_labels[team_id].resize(PlayerRules.MAX_PER_TEAM)
		_hand_labels[team_id].resize(PlayerRules.MAX_PER_TEAM)

		for col: int in _DISPLAY_ORDER.size():
			var s: int = _DISPLAY_ORDER[col]

			var btn := Button.new()
			btn.custom_minimum_size = Vector2(0, 44)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.clip_contents = true
			btn.text = ""
			btn.pressed.connect(_on_button_pressed.bind(team_id, s))
			row.add_child(btn)
			_buttons[team_id][s] = btn

			var hbox := HBoxContainer.new()
			hbox.add_theme_constant_override("separation", 6)
			hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hbox.size_flags_vertical   = Control.SIZE_EXPAND_FILL
			hbox.alignment = BoxContainer.ALIGNMENT_CENTER
			btn.add_child(hbox)

			var num_lbl := Label.new()
			num_lbl.add_theme_font_size_override("font_size", 22)
			num_lbl.add_theme_constant_override("outline_size", 3)
			num_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			num_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
			num_lbl.custom_minimum_size = Vector2(38, 0)
			hbox.add_child(num_lbl)
			_num_labels[team_id][s] = num_lbl

			var name_lbl := Label.new()
			name_lbl.add_theme_font_size_override("font_size", 13)
			name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
			name_lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
			name_lbl.clip_text = true
			hbox.add_child(name_lbl)
			_name_labels[team_id][s] = name_lbl

			var hand_lbl := Label.new()
			hand_lbl.add_theme_font_size_override("font_size", 12)
			hand_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			hand_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
			hand_lbl.custom_minimum_size = Vector2(30, 0)
			hbox.add_child(hand_lbl)
			_hand_labels[team_id][s] = hand_lbl

# roster: Array of { team_id, slot, peer_id, player_name, jersey_number, is_left_handed }
# local_peer_id: this client's peer ID
# team_colors: Array[Dictionary] indexed by team_id, each with jersey/text/text_outline fields
func refresh(roster: Array[Dictionary], local_peer_id: int, team_colors: Array[Dictionary] = []) -> void:
	_team_colors = team_colors

	# Build lookup: (team_id * 3 + slot) -> entry
	var by_slot: Dictionary = {}
	for entry: Dictionary in roster:
		by_slot[entry.team_id * 3 + entry.slot] = entry

	for team_id: int in 2:
		for s: int in PlayerRules.MAX_PER_TEAM:
			var key: int = team_id * 3 + s
			var entry = by_slot.get(key, null)
			var is_local: bool = entry != null and entry.peer_id == local_peer_id
			_update_card(team_id, s, entry, is_local)

func _update_card(team_id: int, slot: int, entry, is_local: bool) -> void:
	var btn:       Button = _buttons[team_id][slot]
	var num_lbl:   Label  = _num_labels[team_id][slot]
	var name_lbl:  Label  = _name_labels[team_id][slot]
	var hand_lbl:  Label  = _hand_labels[team_id][slot]

	var jersey_c:  Color = _FALLBACK
	var text_c:    Color = _WHITE
	var outline_c: Color = Color(0, 0, 0, 1)

	if _team_colors.size() > team_id:
		var tc: Dictionary = _team_colors[team_id]
		jersey_c  = tc.get("jersey",       _FALLBACK)
		text_c    = tc.get("text",         _WHITE)
		outline_c = tc.get("text_outline", Color(0, 0, 0, 1))

	var pos_str: String = _POSITION_LABEL[slot]

	if entry == null:
		# Empty slot — clickable, dimmed jersey background.
		_apply_style(btn, Color(jersey_c.r, jersey_c.g, jersey_c.b, 0.35),
				Color(jersey_c.r, jersey_c.g, jersey_c.b, 0.50), false)
		btn.disabled = false
		btn.modulate = _WHITE
		_set_num(num_lbl, "--", Color(text_c.r, text_c.g, text_c.b, 0.45), Color(0, 0, 0, 0), 0)
		name_lbl.text = ""
		name_lbl.add_theme_color_override("font_color", Color(text_c.r, text_c.g, text_c.b, 0.45))
		hand_lbl.text = pos_str
		hand_lbl.add_theme_color_override("font_color", Color(text_c.r, text_c.g, text_c.b, 0.45))
	elif is_local:
		# Local player's slot — full color, disabled (can't switch to own slot).
		_apply_style(btn, Color(jersey_c.r, jersey_c.g, jersey_c.b, 0.80),
				Color(jersey_c.r, jersey_c.g, jersey_c.b, 0.80), true)
		btn.disabled = true
		btn.modulate = Color(1, 1, 1, 0.85)
		_set_num(num_lbl, "%d" % entry.get("jersey_number", 10), text_c, outline_c, 3)
		name_lbl.text = "You"
		name_lbl.add_theme_color_override("font_color", text_c)
		hand_lbl.text = _hand_str(slot, entry.get("is_left_handed", true))
		hand_lbl.add_theme_color_override("font_color", text_c)
	else:
		# Another player's slot — full color, disabled.
		_apply_style(btn, Color(jersey_c.r, jersey_c.g, jersey_c.b, 1.0),
				Color(jersey_c.r, jersey_c.g, jersey_c.b, 1.0), true)
		btn.disabled = true
		btn.modulate = Color(1, 1, 1, 0.70)
		_set_num(num_lbl, "%d" % entry.get("jersey_number", 10), text_c, outline_c, 3)
		name_lbl.text = entry.get("player_name", "Player") if not entry.get("player_name", "").is_empty() else "Player"
		name_lbl.add_theme_color_override("font_color", text_c)
		hand_lbl.text = _hand_str(slot, entry.get("is_left_handed", true))
		hand_lbl.add_theme_color_override("font_color", text_c)

func _set_num(lbl: Label, text: String, color: Color, outline_color: Color, outline_size: int) -> void:
	lbl.text = text
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", outline_color)
	lbl.add_theme_constant_override("outline_size", outline_size)

func _apply_style(btn: Button, normal_color: Color, disabled_color: Color, is_occupied: bool) -> void:
	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = normal_color
	style_normal.set_corner_radius_all(4)
	style_normal.set_content_margin_all(4)
	btn.add_theme_stylebox_override("normal", style_normal)

	var style_hover := StyleBoxFlat.new()
	style_hover.bg_color = normal_color.lightened(0.12)
	style_hover.set_corner_radius_all(4)
	style_hover.set_content_margin_all(4)
	btn.add_theme_stylebox_override("hover", style_hover)

	var style_pressed := StyleBoxFlat.new()
	style_pressed.bg_color = normal_color.darkened(0.10)
	style_pressed.set_corner_radius_all(4)
	style_pressed.set_content_margin_all(4)
	btn.add_theme_stylebox_override("pressed", style_pressed)

	var style_disabled := StyleBoxFlat.new()
	style_disabled.bg_color = disabled_color
	style_disabled.set_corner_radius_all(4)
	style_disabled.set_content_margin_all(4)
	btn.add_theme_stylebox_override("disabled", style_disabled)

	if is_occupied:
		btn.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 1))

func _hand_str(slot: int, is_left_handed: bool) -> String:
	var pos: String = _POSITION_LABEL[slot]
	return ("<" + pos) if is_left_handed else (pos + ">")

func _on_button_pressed(team_id: int, slot: int) -> void:
	slot_selected.emit(team_id, slot)
