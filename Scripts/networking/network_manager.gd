extends Node

# ── Outbound signals (application layer listens) ─────────────────────────────
# NetworkManager observes ENet + RPC traffic; GameManager connects to these in
# _ready and executes the corresponding orchestration work. Keeps the upward
# call discipline — infrastructure never calls into application directly.
signal host_ready
signal client_connected
signal disconnected_from_server
signal peer_joined(peer_id: int)
signal peer_disconnected(peer_id: int)
signal world_state_received(state: Array)
signal slot_assigned(team_slot: int, team_id: int, jersey_color: Color, helmet_color: Color, pants_color: Color)
signal remote_skater_spawn_requested(peer_id: int, team_slot: int, team_id: int, jersey_color: Color, helmet_color: Color, pants_color: Color, is_left_handed: bool, player_name: String, jersey_number: int)
signal existing_players_synced(player_data: Array)
signal local_puck_pickup_confirmed
signal local_puck_stolen
signal remote_puck_release_received(direction: Vector3, power: float)
signal carrier_puck_dropped
signal goal_received(scoring_team_id: int, score0: int, score1: int, scorer_name: String, assist1_name: String, assist2_name: String)
signal faceoff_positions_received(positions: Array)
signal game_reset_received
signal stats_received(data: Array)
signal slot_swap_requested(peer_id: int, new_team_id: int, new_slot: int)
signal slot_swap_confirmed(peer_id: int, old_team_id: int, old_slot: int, new_team_id: int, new_slot: int, jersey: Color, helmet: Color, pants: Color)
signal game_started(config: Dictionary)
signal lobby_roster_synced(roster: Array)
signal return_to_lobby_received(roster: Array)

# ── State ─────────────────────────────────────────────────────────────────────
var is_host: bool = false
var game_initiated: bool = false
var local_is_left_handed: bool = true
var local_player_name: String = "Player"
var local_jersey_number: int = 10
var pending_game_config: Dictionary = {}
var pending_lobby_slots: Dictionary = {}  # peer_id → { team_id, team_slot, player_name, is_left_handed }
var pending_lobby_roster: Array = []
var pending_join_slot: Dictionary = {}   # { team_slot, team_id, jersey_color, helmet_color, pants_color }
var pending_join_players: Array = []     # sync_existing_players data for join-in-progress
var _local_controller: LocalController = null
var _remote_controllers: Dictionary = {}  # peer_id -> RemoteController
var _peer_handedness: Dictionary = {}     # peer_id -> bool (host only)
var _peer_names: Dictionary = {}          # peer_id -> String (host only)
var _peer_numbers: Dictionary = {}        # peer_id -> int (host only)
# Callable () -> Array. Set by GameManager at startup so the broadcast loop
# can pull world state without reaching up into the application layer.
var _world_state_provider: Callable = Callable()

# ── Timers ────────────────────────────────────────────────────────────────────
var pending_error: String = ""

var _input_timer: float = 0.0
var _state_timer: float = 0.0
var _connect_timer: float = -1.0
var input_delta: float = 1.0 / Constants.INPUT_RATE
var state_delta: float = 1.0 / Constants.STATE_RATE
const CONNECT_TIMEOUT: float = 10.0

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

# ── Connection ────────────────────────────────────────────────────────────────
func start_offline() -> void:
	is_host = true
	game_initiated = true
	_peer_handedness[1] = local_is_left_handed
	_peer_names[1] = local_player_name
	_peer_numbers[1] = local_jersey_number


func start_host() -> void:
	is_host = true
	game_initiated = true
	_peer_handedness[1] = local_is_left_handed
	_peer_names[1] = local_player_name
	_peer_numbers[1] = local_jersey_number
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(Constants.PORT, GameRules.MAX_PLAYERS)
	if error != OK:
		push_error("Failed to start server: " + str(error))
		return
	multiplayer.multiplayer_peer = peer

func start_client(ip: String) -> void:
	is_host = false
	game_initiated = true
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(ip, Constants.PORT)
	if error != OK:
		push_error("Failed to connect: " + str(error))
		return
	multiplayer.multiplayer_peer = peer
	_connect_timer = 0.0

func on_game_scene_ready() -> void:
	if is_host:
		host_ready.emit()

# ── Network Signals ───────────────────────────────────────────────────────────
func _on_peer_connected(id: int) -> void:
	# Give peers a generous disconnect window — brief OS freezes (e.g. title bar
	# right-click) block the message pump and silence ENet for several seconds.
	var enet_peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet_peer:
		enet_peer.get_peer(id).set_timeout(0, 10000, 60000)
	# Spawn happens when the client sends request_join — not here.

func _on_peer_disconnected(id: int) -> void:
	_peer_handedness.erase(id)
	_peer_names.erase(id)
	_peer_numbers.erase(id)
	peer_disconnected.emit(id)
	# Notify all remaining clients so they remove the stale skater.
	for peer_id in multiplayer.get_peers():
		notify_player_disconnected.rpc_id(peer_id, id)

func _on_connected_to_server() -> void:
	_connect_timer = -1.0
	request_join.rpc_id(1, local_is_left_handed, local_player_name, local_jersey_number)
	client_connected.emit()

func _on_connection_failed() -> void:
	push_error("Connection failed")
	pending_error = "Connection failed."
	reset()
	get_tree().change_scene_to_file(Constants.SCENE_MAIN_MENU)

func _on_server_disconnected() -> void:
	push_error("Server disconnected")
	pending_error = "Lost connection to server."
	disconnected_from_server.emit()
	reset()
	get_tree().change_scene_to_file(Constants.SCENE_MAIN_MENU)

func _exit_tree() -> void:
	_close()

func _close() -> void:
	if multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
		multiplayer.multiplayer_peer.close()

func reset() -> void:
	_close()
	multiplayer.multiplayer_peer = null
	is_host = false
	game_initiated = false
	_local_controller = null
	_remote_controllers.clear()
	_peer_handedness.clear()
	_peer_names.clear()
	_peer_numbers.clear()
	pending_game_config = {}
	pending_lobby_slots = {}
	pending_lobby_roster = []
	pending_join_slot = {}
	pending_join_players = []
	_input_timer = 0.0
	_state_timer = 0.0
	_connect_timer = -1.0

# ── Process ───────────────────────────────────────────────────────────────────
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		if is_host:
			# Immediately resync clients — they've been without world state for the
			# duration of the OS freeze.
			_broadcast_state()
		else:
			# Reset the input timer so we don't burst-send stale inputs.
			_input_timer = 0.0

func _process(delta: float) -> void:
	# Cap delta to avoid timer bursting on the first frame after an OS freeze
	# (e.g. title bar right-click holding the message pump for several seconds).
	var capped_delta: float = minf(delta, 0.5)
	if _connect_timer >= 0.0:
		_connect_timer += capped_delta
		if _connect_timer >= CONNECT_TIMEOUT:
			push_error("Connection timed out after %ds" % CONNECT_TIMEOUT)
			pending_error = "Connection timed out."
			reset()
			get_tree().change_scene_to_file(Constants.SCENE_MAIN_MENU)

	if not is_host and _local_controller != null:
		_input_timer += capped_delta
		if _input_timer >= input_delta:
			_input_timer -= input_delta
			var state: InputState = _local_controller.get_current_input()
			receive_input.rpc_id(1, state.to_array())

	if is_host:
		_state_timer += capped_delta
		if _state_timer >= state_delta:
			_state_timer -= state_delta
			_broadcast_state()

func _broadcast_state() -> void:
	if not _world_state_provider.is_valid():
		return
	var state: Array = _world_state_provider.call()
	if state.is_empty():
		return
	for peer_id in multiplayer.get_peers():
		receive_world_state.rpc_id(peer_id, state)

# ── RPCs ──────────────────────────────────────────────────────────────────────
@rpc("any_peer", "reliable")
func request_join(is_left_handed: bool, player_name: String, jersey_number: int = 10) -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	_peer_handedness[sender_id] = is_left_handed
	_peer_names[sender_id] = player_name.strip_edges().left(16)
	_peer_numbers[sender_id] = jersey_number
	peer_joined.emit(sender_id)

func get_peer_handedness(peer_id: int) -> bool:
	return _peer_handedness.get(peer_id, true)

func get_peer_name(peer_id: int) -> String:
	return _peer_names.get(peer_id, "Player")

func get_peer_number(peer_id: int) -> int:
	return _peer_numbers.get(peer_id, 10)

@rpc("any_peer", "unreliable_ordered")
func receive_input(data: Array) -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	var state: InputState = InputState.from_array(data)
	if _remote_controllers.has(sender_id):
		_remote_controllers[sender_id].receive_input(state)
	else:
		push_warning("no remote controller for peer %d" % sender_id)

@rpc("authority", "unreliable_ordered")
func receive_world_state(state: Array) -> void:
	if is_host:
		return
	world_state_received.emit(state)

@rpc("authority", "reliable")
func assign_player_slot(team_slot: int, team_id: int, jersey_color: Color, helmet_color: Color, pants_color: Color) -> void:
	var scene := get_tree().current_scene
	if not is_host and (scene == null or scene.scene_file_path != Constants.SCENE_HOCKEY):
		pending_join_slot = { "team_slot": team_slot, "team_id": team_id,
			"jersey_color": jersey_color, "helmet_color": helmet_color, "pants_color": pants_color }
		return
	slot_assigned.emit(team_slot, team_id, jersey_color, helmet_color, pants_color)

@rpc("authority", "reliable")
func spawn_remote_skater(peer_id: int, team_slot: int, team_id: int, jersey_color: Color, helmet_color: Color, pants_color: Color, is_left_handed: bool, player_name: String, jersey_number: int = 10) -> void:
	remote_skater_spawn_requested.emit(peer_id, team_slot, team_id, jersey_color, helmet_color, pants_color, is_left_handed, player_name, jersey_number)

@rpc("authority", "reliable")
func sync_existing_players(player_data: Array) -> void:
	var scene := get_tree().current_scene
	if not is_host and (scene == null or scene.scene_file_path != Constants.SCENE_HOCKEY):
		pending_join_players = player_data
		return
	existing_players_synced.emit(player_data)
	
func send_puck_picked_up(peer_id: int) -> void:
	notify_puck_picked_up.rpc_id(peer_id)

@rpc("authority", "reliable")
func notify_puck_picked_up() -> void:
	local_puck_pickup_confirmed.emit()

func send_puck_stolen(victim_peer_id: int) -> void:
	notify_puck_stolen.rpc_id(victim_peer_id)

@rpc("authority", "reliable")
func notify_puck_stolen() -> void:
	local_puck_stolen.emit()

func send_puck_release(direction: Vector3, power: float) -> void:
	release_puck.rpc_id(1, direction, power)

@rpc("any_peer", "reliable")
func release_puck(direction: Vector3, power: float) -> void:
	remote_puck_release_received.emit(direction, power)

func notify_goal_to_all(scoring_team_id: int, score0: int, score1: int, scorer_name: String, assist1_name: String, assist2_name: String) -> void:
	for peer_id in multiplayer.get_peers():
		notify_goal.rpc_id(peer_id, scoring_team_id, score0, score1, scorer_name, assist1_name, assist2_name)

func notify_puck_dropped_to_carrier(carrier_peer_id: int) -> void:
	notify_puck_dropped.rpc_id(carrier_peer_id)

@rpc("authority", "reliable")
func notify_puck_dropped() -> void:
	carrier_puck_dropped.emit()

@rpc("authority", "reliable")
func notify_player_disconnected(peer_id: int) -> void:
	peer_disconnected.emit(peer_id)

@rpc("authority", "reliable")
func notify_goal(scoring_team_id: int, score0: int, score1: int, scorer_name: String, assist1_name: String, assist2_name: String) -> void:
	goal_received.emit(scoring_team_id, score0, score1, scorer_name, assist1_name, assist2_name)

func send_faceoff_positions(positions: Array) -> void:
	for peer_id in multiplayer.get_peers():
		notify_faceoff_positions.rpc_id(peer_id, positions)

@rpc("authority", "reliable")
func notify_faceoff_positions(positions: Array) -> void:
	faceoff_positions_received.emit(positions)

func notify_reset_to_all() -> void:
	for peer_id in multiplayer.get_peers():
		notify_game_reset.rpc_id(peer_id)

@rpc("authority", "reliable")
func notify_game_reset() -> void:
	game_reset_received.emit()

func send_stats_to_all(data: Array) -> void:
	for peer_id in multiplayer.get_peers():
		receive_stats.rpc_id(peer_id, data)

@rpc("authority", "call_remote", "reliable")
func receive_stats(data: Array) -> void:
	stats_received.emit(data)

@rpc("any_peer", "reliable")
func request_slot_swap(new_team_id: int, new_slot: int) -> void:
	slot_swap_requested.emit(multiplayer.get_remote_sender_id(), new_team_id, new_slot)

@rpc("authority", "reliable")
func confirm_slot_swap(peer_id: int, old_team_id: int, old_slot: int,
		new_team_id: int, new_slot: int,
		jersey: Color, helmet: Color, pants: Color) -> void:
	slot_swap_confirmed.emit(peer_id, old_team_id, old_slot, new_team_id, new_slot, jersey, helmet, pants)

# ── Sending ───────────────────────────────────────────────────────────────────
func send_slot_assignment(peer_id: int, team_slot: int, team_id: int, jersey_color: Color, helmet_color: Color, pants_color: Color) -> void:
	assign_player_slot.rpc_id(peer_id, team_slot, team_id, jersey_color, helmet_color, pants_color)

func send_spawn_remote_skater(peer_id: int, team_slot: int, team_id: int, jersey_color: Color, helmet_color: Color, pants_color: Color, is_left_handed: bool, player_name: String, jersey_number: int = 10) -> void:
	spawn_remote_skater.rpc(peer_id, team_slot, team_id, jersey_color, helmet_color, pants_color, is_left_handed, player_name, jersey_number)

func send_sync_existing_players(peer_id: int, player_data: Array) -> void:
	sync_existing_players.rpc_id(peer_id, player_data)

func send_request_slot_swap(new_team_id: int, new_slot: int) -> void:
	if is_host:
		slot_swap_requested.emit(multiplayer.get_unique_id(), new_team_id, new_slot)
	else:
		request_slot_swap.rpc_id(1, new_team_id, new_slot)

func send_confirm_slot_swap(peer_id: int, old_team_id: int, old_slot: int,
		new_team_id: int, new_slot: int,
		jersey: Color, helmet: Color, pants: Color) -> void:
	for remote_id: int in multiplayer.get_peers():
		confirm_slot_swap.rpc_id(remote_id, peer_id, old_team_id, old_slot,
				new_team_id, new_slot, jersey, helmet, pants)
	slot_swap_confirmed.emit(peer_id, old_team_id, old_slot, new_team_id, new_slot, jersey, helmet, pants)

signal join_in_progress(config: Dictionary)

@rpc("authority", "reliable")
func notify_join_in_progress(p_num_periods: int, p_period_duration: float,
		p_ot_enabled: bool, p_ot_duration: float) -> void:
	join_in_progress.emit({
		"num_periods": p_num_periods,
		"period_duration": p_period_duration,
		"ot_enabled": p_ot_enabled,
		"ot_duration": p_ot_duration,
	})

func send_join_in_progress(peer_id: int, config: Dictionary) -> void:
	notify_join_in_progress.rpc_id(peer_id,
		config.num_periods, config.period_duration,
		config.ot_enabled, config.ot_duration)

@rpc("authority", "reliable")
func notify_game_start(p_num_periods: int, p_period_duration: float,
		p_ot_enabled: bool, p_ot_duration: float) -> void:
	game_started.emit({
		"num_periods": p_num_periods,
		"period_duration": p_period_duration,
		"ot_enabled": p_ot_enabled,
		"ot_duration": p_ot_duration,
	})

@rpc("authority", "reliable")
func sync_lobby_roster(roster: Array) -> void:
	pending_lobby_roster = roster
	lobby_roster_synced.emit(roster)

func send_game_start(config: Dictionary) -> void:
	for peer_id: int in multiplayer.get_peers():
		notify_game_start.rpc_id(peer_id,
			config.num_periods, config.period_duration,
			config.ot_enabled, config.ot_duration)
	game_started.emit(config)

func send_lobby_roster(peer_id: int, roster: Array) -> void:
	sync_lobby_roster.rpc_id(peer_id, roster)

@rpc("authority", "reliable")
func notify_return_to_lobby(roster: Array) -> void:
	pending_lobby_roster = roster
	return_to_lobby_received.emit(roster)

func send_return_to_lobby_to_all(roster: Array) -> void:
	for peer_id: int in multiplayer.get_peers():
		notify_return_to_lobby.rpc_id(peer_id, roster)
	pending_lobby_roster = roster
	return_to_lobby_received.emit(roster)

# ── Registration ──────────────────────────────────────────────────────────────
func set_world_state_provider(provider: Callable) -> void:
	_world_state_provider = provider

func register_local_controller(controller: LocalController) -> void:
	_local_controller = controller

func register_remote_controller(peer_id: int, controller: RemoteController) -> void:
	_remote_controllers[peer_id] = controller

func unregister_remote_controller(peer_id: int) -> void:
	_remote_controllers.erase(peer_id)
