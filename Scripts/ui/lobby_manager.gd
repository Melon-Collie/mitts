class_name LobbyManager
extends Node

const _DARK_BG   := Color(0.07, 0.07, 0.09, 0.92)
const _WHITE     := Color(1.00, 1.00, 1.00, 1.00)
const _DIM       := Color(0.62, 0.62, 0.68, 1.00)

# key = team_id * 3 + slot  →  { peer_id, player_name, is_left_handed }
var _lobby_slots: Dictionary = {}

var _slot_grid: SlotGridPanel = null
var _start_btn: Button = null

# Settings (host only)
var _num_periods: int = GameRules.NUM_PERIODS
var _period_duration: float = GameRules.PERIOD_DURATION
var _ot_enabled: bool = GameRules.OT_ENABLED

func _ready() -> void:
	_build_ui()
	NetworkManager.peer_joined.connect(_on_peer_joined)
	NetworkManager.peer_disconnected.connect(_on_peer_disconnected)
	NetworkManager.slot_swap_requested.connect(_on_slot_swap_requested)
	NetworkManager.slot_swap_confirmed.connect(_on_slot_swap_confirmed)
	NetworkManager.lobby_roster_synced.connect(_on_lobby_roster_synced)
	NetworkManager.game_started.connect(_on_game_started)

	if not NetworkManager.pending_lobby_roster.is_empty():
		_on_lobby_roster_synced(NetworkManager.pending_lobby_roster)
		NetworkManager.pending_lobby_roster = []
	elif NetworkManager.is_host:
		_assign_slot(1, 0, 0, NetworkManager.local_player_name, NetworkManager.local_is_left_handed, NetworkManager.local_jersey_number)
		_broadcast_confirm(1, 0, 0)

# ── UI ────────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(root)

	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.04, 0.06, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = _DARK_BG
	panel_style.set_corner_radius_all(6)
	panel_style.set_content_margin_all(32)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", panel_style)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(480, 0)
	root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "LOBBY"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", _WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_slot_grid = SlotGridPanel.new()
	_slot_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slot_grid.slot_selected.connect(_on_slot_selected)
	vbox.add_child(_slot_grid)

	if NetworkManager.is_host:
		vbox.add_child(_build_settings_panel())

	var btn_box := HBoxContainer.new()
	btn_box.add_theme_constant_override("separation", 12)
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_box)

	var back_btn := _btn("Back to Menu")
	back_btn.pressed.connect(_on_back_pressed)
	btn_box.add_child(back_btn)

	if NetworkManager.is_host:
		_start_btn = _btn("Start Game")
		_start_btn.pressed.connect(_on_start_pressed)
		btn_box.add_child(_start_btn)

	_refresh_grid()

func _build_settings_panel() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)

	var sep_style := StyleBoxFlat.new()
	sep_style.bg_color = Color(0.28, 0.28, 0.33, 1.0)
	var sep := HSeparator.new()
	sep.add_theme_stylebox_override("separator", sep_style)
	box.add_child(sep)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(center)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 8)
	center.add_child(grid)

	grid.add_child(_setting_label("Periods"))
	var periods_spin := SpinBox.new()
	periods_spin.min_value = 1
	periods_spin.max_value = 5
	periods_spin.step = 1
	periods_spin.value = _num_periods
	periods_spin.value_changed.connect(func(v: float) -> void: _num_periods = int(v))
	grid.add_child(periods_spin)

	grid.add_child(_setting_label("Period length (min)"))
	var dur_spin := SpinBox.new()
	dur_spin.min_value = 1
	dur_spin.max_value = 10
	dur_spin.step = 1
	dur_spin.value = _period_duration / 60.0
	dur_spin.value_changed.connect(func(v: float) -> void: _period_duration = v * 60.0)
	grid.add_child(dur_spin)

	grid.add_child(_setting_label("Overtime"))
	var ot_check := CheckButton.new()
	ot_check.button_pressed = _ot_enabled
	ot_check.toggled.connect(func(pressed: bool) -> void: _ot_enabled = pressed)
	grid.add_child(ot_check)

	return box

func _setting_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", _DIM)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return lbl

func _btn(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(140, 40)
	return b

# ── Slot management ───────────────────────────────────────────────────────────

func _slot_key(team_id: int, slot: int) -> int:
	return team_id * 3 + slot

func _assign_slot(peer_id: int, team_id: int, slot: int, player_name: String, is_left_handed: bool, jersey_number: int = 10) -> void:
	# Clear any existing slot for this peer first.
	for k: int in _lobby_slots.keys():
		if _lobby_slots[k].peer_id == peer_id:
			_lobby_slots.erase(k)
			break
	_lobby_slots[_slot_key(team_id, slot)] = {
		"peer_id": peer_id,
		"player_name": player_name,
		"is_left_handed": is_left_handed,
		"jersey_number": jersey_number,
	}

func _find_balanced_slot(_peer_id: int) -> Array:
	var team0: int = 0
	var team1: int = 0
	for k: int in _lobby_slots:
		if k < PlayerRules.MAX_PER_TEAM: team0 += 1
		else: team1 += 1
	var preferred_team: int = 0 if team0 <= team1 else 1
	for attempt_team: int in [preferred_team, 1 - preferred_team]:
		for s: int in PlayerRules.MAX_PER_TEAM:
			if not _lobby_slots.has(_slot_key(attempt_team, s)):
				return [attempt_team, s]
	return []

func _build_roster_array() -> Array:
	var result: Array = []
	for k: int in _lobby_slots:
		var team_id: int = k / 3
		var slot: int = k % 3
		var entry: Dictionary = _lobby_slots[k]
		result.append([entry.peer_id, team_id, slot, entry.player_name, entry.is_left_handed, entry.get("jersey_number", 10)])
	return result

func _build_slot_grid_roster() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for k: int in _lobby_slots:
		var team_id: int = k / 3
		var slot: int = k % 3
		var entry: Dictionary = _lobby_slots[k]
		result.append({ "peer_id": entry.peer_id, "team_id": team_id, "slot": slot, "player_name": entry.player_name })
	return result

func _refresh_grid() -> void:
	if _slot_grid == null:
		return
	_slot_grid.refresh(_build_slot_grid_roster(), multiplayer.get_unique_id())

func _broadcast_confirm(peer_id: int, team_id: int, slot: int) -> void:
	var entry: Dictionary = _lobby_slots.get(_slot_key(team_id, slot), {})
	if entry.is_empty():
		return
	var jersey := PlayerRules.generate_jersey_color(team_id)
	var helmet := PlayerRules.generate_helmet_color(team_id)
	var pants  := PlayerRules.generate_pants_color(team_id)
	NetworkManager.send_confirm_slot_swap(peer_id, -1, -1, team_id, slot, jersey, helmet, pants)

# ── Signal handlers ───────────────────────────────────────────────────────────

func _on_peer_joined(peer_id: int) -> void:
	if not NetworkManager.is_host:
		return
	var target: Array = _find_balanced_slot(peer_id)
	if target.is_empty():
		return
	var name_val: String = NetworkManager.get_peer_name(peer_id)
	var is_left: bool = NetworkManager.get_peer_handedness(peer_id)
	var num: int = NetworkManager.get_peer_number(peer_id)
	_assign_slot(peer_id, target[0], target[1], name_val, is_left, num)
	NetworkManager.send_lobby_roster(peer_id, _build_roster_array())
	_broadcast_confirm(peer_id, target[0], target[1])
	_refresh_grid()

func _on_peer_disconnected(peer_id: int) -> void:
	for k: int in _lobby_slots.keys():
		if _lobby_slots[k].peer_id == peer_id:
			_lobby_slots.erase(k)
			break
	_refresh_grid()

func _on_slot_selected(team_id: int, slot: int) -> void:
	NetworkManager.send_request_slot_swap(team_id, slot)

func _find_peer_identity(peer_id: int) -> Dictionary:
	for k: int in _lobby_slots:
		if _lobby_slots[k].peer_id == peer_id:
			var entry: Dictionary = _lobby_slots[k]
			return {
				"player_name": entry.player_name,
				"is_left_handed": entry.is_left_handed,
				"jersey_number": entry.get("jersey_number", 10),
			}
	return { "player_name": "", "is_left_handed": true, "jersey_number": 10 }

func _on_slot_swap_requested(peer_id: int, new_team_id: int, new_slot: int) -> void:
	if not NetworkManager.is_host:
		return
	if _lobby_slots.has(_slot_key(new_team_id, new_slot)):
		return
	var count: int = 0
	for k: int in _lobby_slots:
		if k / 3 == new_team_id:
			count += 1
	if count >= PlayerRules.MAX_PER_TEAM:
		return
	var identity: Dictionary = _find_peer_identity(peer_id)
	_assign_slot(peer_id, new_team_id, new_slot,
			identity.player_name, identity.is_left_handed, identity.jersey_number)
	_broadcast_confirm(peer_id, new_team_id, new_slot)
	_refresh_grid()

func _on_slot_swap_confirmed(peer_id: int, _old_team_id: int, _old_slot: int,
		new_team_id: int, new_slot: int,
		_jersey: Color, _helmet: Color, _pants: Color) -> void:
	var identity: Dictionary = _find_peer_identity(peer_id)
	_assign_slot(peer_id, new_team_id, new_slot,
			identity.player_name, identity.is_left_handed, identity.jersey_number)
	_refresh_grid()

func _on_lobby_roster_synced(roster: Array) -> void:
	_lobby_slots.clear()
	for entry: Array in roster:
		var peer_id: int = entry[0]
		var team_id: int = entry[1]
		var slot: int    = entry[2]
		var p_name: String = entry[3] if entry.size() > 3 else "Player"
		var is_left: bool = entry[4] if entry.size() > 4 else true
		var p_number: int = entry[5] if entry.size() > 5 else 10
		_lobby_slots[_slot_key(team_id, slot)] = {
			"peer_id": peer_id,
			"player_name": p_name,
			"is_left_handed": is_left,
			"jersey_number": p_number,
		}
	_refresh_grid()

func _on_game_started(config: Dictionary) -> void:
	NetworkManager.pending_game_config = config
	NetworkManager.pending_lobby_slots = _build_pending_slots()
	get_tree().change_scene_to_file(Constants.SCENE_HOCKEY)

func _build_pending_slots() -> Dictionary:
	var result: Dictionary = {}
	for k: int in _lobby_slots:
		var team_id: int = k / 3
		var slot: int = k % 3
		var entry: Dictionary = _lobby_slots[k]
		result[entry.peer_id] = {
			"team_id": team_id,
			"team_slot": slot,
			"player_name": entry.player_name,
			"is_left_handed": entry.is_left_handed,
			"jersey_number": entry.get("jersey_number", 10),
		}
	return result

func _on_start_pressed() -> void:
	var config: Dictionary = {
		"num_periods": _num_periods,
		"period_duration": _period_duration,
		"ot_enabled": _ot_enabled,
		"ot_duration": GameRules.OT_DURATION,
	}
	NetworkManager.send_game_start(config)

func _on_back_pressed() -> void:
	GameManager.exit_to_main_menu()
