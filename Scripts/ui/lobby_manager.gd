class_name LobbyManager
extends Node

const _WHITE     := MenuStyle.TEXT_BODY
const _DIM       := MenuStyle.TEXT_DIM

# key = team_id * 3 + slot  →  { peer_id, player_name, is_left_handed }
var _lobby_slots: Dictionary = {}

var _slot_grid: SlotGridPanel = null
var _start_btn: Button = null
var _ready_btn: Button = null
var _periods_spin: SpinBox = null
var _dur_spin: SpinBox = null
var _ot_check: CheckButton = null

# key = peer_id → bool; tracks non-host peers only (host uses Start instead)
var _ready_states: Dictionary = {}
var _local_is_ready: bool = false

# Settings (host only editable; all players see them)
var _num_periods: int = GameRules.NUM_PERIODS
var _period_duration: float = GameRules.PERIOD_DURATION
var _ot_enabled: bool = GameRules.OT_ENABLED

# Team color preset selection
var _home_color_id: String = TeamColorRegistry.DEFAULT_HOME_ID
var _away_color_id: String = TeamColorRegistry.DEFAULT_AWAY_ID
var _home_color_btn: OptionButton = null
var _away_color_btn: OptionButton = null

func _ready() -> void:
	_home_color_id = NetworkManager.pending_home_color_id
	_away_color_id = NetworkManager.pending_away_color_id
	_num_periods = NetworkManager.pending_num_periods
	_period_duration = NetworkManager.pending_period_duration
	_ot_enabled = NetworkManager.pending_ot_enabled
	_build_ui()
	NetworkManager.peer_joined.connect(_on_peer_joined)
	NetworkManager.peer_disconnected.connect(_on_peer_disconnected)
	NetworkManager.slot_swap_requested.connect(_on_slot_swap_requested)
	NetworkManager.slot_swap_confirmed.connect(_on_slot_swap_confirmed)
	NetworkManager.lobby_roster_synced.connect(_on_lobby_roster_synced)
	NetworkManager.game_started.connect(_on_game_started)
	NetworkManager.team_colors_synced.connect(_on_team_colors_synced)
	NetworkManager.lobby_settings_synced.connect(_on_lobby_settings_synced)
	NetworkManager.player_ready_changed.connect(_on_player_ready_changed)

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

	var panel_style := MenuStyle.panel()

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", panel_style)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(960, 0)
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
		_start_btn.disabled = true
		_start_btn.modulate = Color(1, 1, 1, 0.5)
		btn_box.add_child(_start_btn)
	else:
		_ready_btn = _btn("Ready")
		_ready_btn.pressed.connect(_on_ready_pressed)
		btn_box.add_child(_ready_btn)

	_refresh_grid()

func _build_settings_panel() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)

	var sep_style := StyleBoxFlat.new()
	sep_style.bg_color = MenuStyle.TEXT_SEP
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

	var is_interactive: bool = NetworkManager.is_host

	grid.add_child(_setting_label("Away Colors"))
	_away_color_btn = _color_option_btn(_away_color_id)
	if is_interactive:
		_away_color_btn.item_selected.connect(func(idx: int) -> void:
			_away_color_id = TeamColorRegistry.get_all_ids()[idx]
			_update_color_exclusion()
			NetworkManager.send_team_colors(_home_color_id, _away_color_id)
			_refresh_grid())
	else:
		_away_color_btn.disabled = true
		_away_color_btn.modulate = Color(1, 1, 1, 0.5)
	grid.add_child(_away_color_btn)

	grid.add_child(_setting_label("Home Colors"))
	_home_color_btn = _color_option_btn(_home_color_id)
	if is_interactive:
		_home_color_btn.item_selected.connect(func(idx: int) -> void:
			_home_color_id = TeamColorRegistry.get_all_ids()[idx]
			_update_color_exclusion()
			NetworkManager.send_team_colors(_home_color_id, _away_color_id)
			_refresh_grid())
	else:
		_home_color_btn.disabled = true
		_home_color_btn.modulate = Color(1, 1, 1, 0.5)
	grid.add_child(_home_color_btn)

	grid.add_child(_setting_label("Periods"))
	_periods_spin = SpinBox.new()
	_periods_spin.min_value = 1
	_periods_spin.max_value = 5
	_periods_spin.step = 1
	_periods_spin.value = _num_periods
	_periods_spin.editable = is_interactive
	if is_interactive:
		_periods_spin.value_changed.connect(func(v: float) -> void:
			_num_periods = int(v)
			NetworkManager.send_lobby_settings(_num_periods, _period_duration, _ot_enabled))
	else:
		_periods_spin.modulate = Color(1, 1, 1, 0.5)
	grid.add_child(_periods_spin)

	grid.add_child(_setting_label("Period length (min)"))
	_dur_spin = SpinBox.new()
	_dur_spin.min_value = 1
	_dur_spin.max_value = 10
	_dur_spin.step = 1
	_dur_spin.value = _period_duration / 60.0
	_dur_spin.editable = is_interactive
	if is_interactive:
		_dur_spin.value_changed.connect(func(v: float) -> void:
			_period_duration = v * 60.0
			NetworkManager.send_lobby_settings(_num_periods, _period_duration, _ot_enabled))
	else:
		_dur_spin.modulate = Color(1, 1, 1, 0.5)
	grid.add_child(_dur_spin)

	grid.add_child(_setting_label("Overtime"))
	_ot_check = CheckButton.new()
	_ot_check.button_pressed = _ot_enabled
	_ot_check.disabled = not is_interactive
	if is_interactive:
		_ot_check.toggled.connect(func(pressed: bool) -> void:
			_ot_enabled = pressed
			NetworkManager.send_lobby_settings(_num_periods, _period_duration, _ot_enabled))
	else:
		_ot_check.modulate = Color(1, 1, 1, 0.5)
	grid.add_child(_ot_check)

	_update_color_exclusion()
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
	MenuStyle.apply_button(b)
	_wire_hover_scale(b)
	SoundManager.wire_button(b)
	return b

func _wire_hover_scale(btn: Button) -> void:
	btn.item_rect_changed.connect(func() -> void: btn.pivot_offset = btn.size / 2.0)
	btn.mouse_entered.connect(func() -> void: _scale_btn(btn, Vector2(1.04, 1.04)))
	btn.mouse_exited.connect(func() -> void: _scale_btn(btn, Vector2.ONE))
	btn.button_down.connect(func() -> void: _scale_btn(btn, Vector2(0.97, 0.97)))
	btn.button_up.connect(func() -> void: _scale_btn(btn, Vector2(1.04, 1.04)))

func _scale_btn(btn: Button, target: Vector2) -> void:
	var t := btn.create_tween()
	t.tween_property(btn, "scale", target, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _color_option_btn(selected_id: String) -> OptionButton:
	var btn := OptionButton.new()
	var ids: Array[String] = TeamColorRegistry.get_all_ids()
	for i: int in ids.size():
		btn.add_item(TeamColorRegistry.get_preset_name(ids[i]), i)
		if ids[i] == selected_id:
			btn.select(i)
	return btn

func _sync_option_btn(btn: OptionButton, id: String) -> void:
	if btn == null:
		return
	var ids: Array[String] = TeamColorRegistry.get_all_ids()
	for i: int in ids.size():
		if ids[i] == id:
			btn.select(i)
			return

# Disables the opposing team's currently selected preset in each dropdown so
# the same colors cannot be chosen for both teams simultaneously.
func _update_color_exclusion() -> void:
	var ids: Array[String] = TeamColorRegistry.get_all_ids()
	if _home_color_btn != null:
		for i: int in ids.size():
			_home_color_btn.set_item_disabled(i, ids[i] == _away_color_id)
	if _away_color_btn != null:
		for i: int in ids.size():
			_away_color_btn.set_item_disabled(i, ids[i] == _home_color_id)

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
		var team_id: int = 1 if k >= PlayerRules.MAX_PER_TEAM else 0
		var slot: int = k % 3
		var entry: Dictionary = _lobby_slots[k]
		var is_ready: bool = _ready_states.get(entry.peer_id, false)
		result.append([entry.peer_id, team_id, slot, entry.player_name, entry.is_left_handed, entry.get("jersey_number", 10), is_ready])
	return result

func _build_slot_grid_roster() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for k: int in _lobby_slots:
		var team_id: int = 1 if k >= PlayerRules.MAX_PER_TEAM else 0
		var slot: int = k % 3
		var entry: Dictionary = _lobby_slots[k]
		result.append({
			"peer_id":        entry.peer_id,
			"team_id":        team_id,
			"slot":           slot,
			"player_name":    entry.player_name,
			"jersey_number":  entry.get("jersey_number", 10),
			"is_left_handed": entry.is_left_handed,
			"is_ready":       _ready_states.get(entry.peer_id, false),
		})
	return result

func _get_team_colors() -> Array[Dictionary]:
	return [
		TeamColorRegistry.get_colors(_home_color_id, 0),
		TeamColorRegistry.get_colors(_away_color_id, 1),
	]

func _refresh_grid() -> void:
	if _slot_grid == null:
		return
	_slot_grid.refresh(_build_slot_grid_roster(), multiplayer.get_unique_id(), _get_team_colors())

func _broadcast_confirm(peer_id: int, team_id: int, slot: int) -> void:
	var entry: Dictionary = _lobby_slots.get(_slot_key(team_id, slot), {})
	if entry.is_empty():
		return
	var color_id: String = _home_color_id if team_id == 0 else _away_color_id
	var colors: Dictionary = TeamColorRegistry.get_colors(color_id, team_id)
	NetworkManager.send_confirm_slot_swap(peer_id, -1, -1, team_id, slot,
			colors.jersey, colors.helmet, colors.pants)

func _update_start_btn() -> void:
	if _start_btn == null:
		return
	var all_ready: bool = not _ready_states.is_empty()
	for v: bool in _ready_states.values():
		if not v:
			all_ready = false
			break
	_start_btn.disabled = not all_ready
	_start_btn.modulate = Color(1, 1, 1, 1.0) if all_ready else Color(1, 1, 1, 0.5)

func _update_ready_btn() -> void:
	if _ready_btn == null:
		return
	_ready_btn.text = "Unready" if _local_is_ready else "Ready"

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
	_ready_states[peer_id] = false
	var roster: Array = _build_roster_array()
	for existing_peer: int in multiplayer.get_peers():
		NetworkManager.send_lobby_roster(existing_peer, roster)
	NetworkManager.send_team_colors_to(peer_id, _home_color_id, _away_color_id)
	NetworkManager.send_lobby_settings_to(peer_id, _num_periods, _period_duration, _ot_enabled)
	_broadcast_confirm(peer_id, target[0], target[1])
	_update_start_btn()
	_refresh_grid()

func _on_peer_disconnected(peer_id: int) -> void:
	for k: int in _lobby_slots.keys():
		if _lobby_slots[k].peer_id == peer_id:
			_lobby_slots.erase(k)
			break
	_ready_states.erase(peer_id)
	_update_start_btn()
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
		if (1 if k >= PlayerRules.MAX_PER_TEAM else 0) == new_team_id:
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
	_ready_states.clear()
	for entry: Array in roster:
		var peer_id: int = entry[0]
		var team_id: int = entry[1]
		var slot: int    = entry[2]
		var p_name: String = entry[3] if entry.size() > 3 else "Player"
		var is_left: bool = entry[4] if entry.size() > 4 else true
		var p_number: int = entry[5] if entry.size() > 5 else 10
		var is_ready: bool = entry[6] if entry.size() > 6 else false
		_lobby_slots[_slot_key(team_id, slot)] = {
			"peer_id": peer_id,
			"player_name": p_name,
			"is_left_handed": is_left,
			"jersey_number": p_number,
		}
		# Host (peer_id 1) doesn't participate in the ready-check.
		if peer_id != 1:
			_ready_states[peer_id] = is_ready
	_update_start_btn()
	_refresh_grid()

func _on_player_ready_changed(peer_id: int, is_ready: bool) -> void:
	# Host doesn't need to be ready — only track non-host peers.
	if peer_id == 1:
		return
	_ready_states[peer_id] = is_ready
	if peer_id == multiplayer.get_unique_id():
		_local_is_ready = is_ready
		_update_ready_btn()
	_update_start_btn()
	_refresh_grid()

func _on_team_colors_synced(home_id: String, away_id: String) -> void:
	_home_color_id = home_id
	_away_color_id = away_id
	_sync_option_btn(_home_color_btn, home_id)
	_sync_option_btn(_away_color_btn, away_id)
	_update_color_exclusion()
	_refresh_grid()

func _on_lobby_settings_synced(num_periods: int, period_duration: float, ot_enabled: bool) -> void:
	_num_periods = num_periods
	_period_duration = period_duration
	_ot_enabled = ot_enabled
	if _periods_spin != null:
		_periods_spin.value = _num_periods
	if _dur_spin != null:
		_dur_spin.value = _period_duration / 60.0
	if _ot_check != null:
		_ot_check.button_pressed = _ot_enabled

func _on_game_started(config: Dictionary) -> void:
	NetworkManager.pending_game_config = config
	NetworkManager.pending_lobby_slots = _build_pending_slots()
	get_tree().change_scene_to_file(Constants.SCENE_HOCKEY)

func _build_pending_slots() -> Dictionary:
	var result: Dictionary = {}
	for k: int in _lobby_slots:
		var team_id: int = 1 if k >= PlayerRules.MAX_PER_TEAM else 0
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

func _on_ready_pressed() -> void:
	_local_is_ready = not _local_is_ready
	_update_ready_btn()
	NetworkManager.send_player_ready(_local_is_ready)

func _on_start_pressed() -> void:
	var config: Dictionary = {
		"num_periods": _num_periods,
		"period_duration": _period_duration,
		"ot_enabled": _ot_enabled,
		"ot_duration": GameRules.OT_DURATION,
		"home_color_id": _home_color_id,
		"away_color_id": _away_color_id,
	}
	NetworkManager.send_game_start(config)

func _on_back_pressed() -> void:
	GameManager.exit_to_main_menu()
