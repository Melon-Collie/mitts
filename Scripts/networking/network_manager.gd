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
signal remote_skater_spawn_requested(peer_id: int, team_slot: int, team_id: int, jersey_color: Color, helmet_color: Color, pants_color: Color, is_left_handed: bool, player_name: String)
signal existing_players_synced(player_data: Array)
signal local_puck_pickup_confirmed
signal local_puck_stolen
signal remote_puck_release_received(direction: Vector3, power: float)
signal carrier_puck_dropped
signal goal_received(scoring_team_id: int, score0: int, score1: int, scorer_name: String)
signal faceoff_positions_received(positions: Array)
signal game_reset_received
signal stats_received(data: Array)

# ── State ─────────────────────────────────────────────────────────────────────
var is_host: bool = false
var game_initiated: bool = false
var local_is_left_handed: bool = true
var local_player_name: String = "Player"
var _local_controller: LocalController = null
var _remote_controllers: Dictionary = {}  # peer_id -> RemoteController
var _peer_handedness: Dictionary = {}     # peer_id -> bool (host only)
var _peer_names: Dictionary = {}          # peer_id -> String (host only)
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
	pass  # All start paths go through MainMenu.

# ── Connection ────────────────────────────────────────────────────────────────
func start_offline() -> void:
	is_host = true
	game_initiated = true
	_peer_handedness[1] = local_is_left_handed
	_peer_names[1] = local_player_name
	print("Offline mode")

func start_host() -> void:
	is_host = true
	game_initiated = true
	_peer_handedness[1] = local_is_left_handed
	_peer_names[1] = local_player_name
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(Constants.PORT, GameRules.MAX_PLAYERS)
	if error != OK:
		push_error("Failed to start server: " + str(error))
		return
	multiplayer.multiplayer_peer = peer
	print("Server started on port ", Constants.PORT)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

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
	print("Connecting to ", ip, ":", Constants.PORT)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

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
	print("Player connected: ", id)
	# Spawn happens when the client sends request_join — not here.

func _on_peer_disconnected(id: int) -> void:
	print("Player disconnected: ", id)
	_peer_handedness.erase(id)
	_peer_names.erase(id)
	peer_disconnected.emit(id)
	# Notify all remaining clients so they remove the stale skater.
	for peer_id in multiplayer.get_peers():
		notify_player_disconnected.rpc_id(peer_id, id)

func _on_connected_to_server() -> void:
	_connect_timer = -1.0
	print("Connected! My ID: ", multiplayer.get_unique_id())
	request_join.rpc_id(1, local_is_left_handed, local_player_name)
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
	for peer_id in multiplayer.get_peers():
		receive_world_state.rpc_id(peer_id, state)

# ── RPCs ──────────────────────────────────────────────────────────────────────
@rpc("any_peer", "reliable")
func request_join(is_left_handed: bool, player_name: String) -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	_peer_handedness[sender_id] = is_left_handed
	_peer_names[sender_id] = player_name.strip_edges().left(16)
	peer_joined.emit(sender_id)

func get_peer_handedness(peer_id: int) -> bool:
	return _peer_handedness.get(peer_id, true)

func get_peer_name(peer_id: int) -> String:
	return _peer_names.get(peer_id, "Player")

@rpc("any_peer", "unreliable_ordered")
func receive_input(data: Array) -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	var state: InputState = InputState.from_array(data)
	if _remote_controllers.has(sender_id):
		_remote_controllers[sender_id].receive_input(state)
	else:
		print("no remote controller for: ", sender_id)

@rpc("authority", "unreliable_ordered")
func receive_world_state(state: Array) -> void:
	if is_host:
		return
	world_state_received.emit(state)

@rpc("authority", "reliable")
func assign_player_slot(team_slot: int, team_id: int, jersey_color: Color, helmet_color: Color, pants_color: Color) -> void:
	slot_assigned.emit(team_slot, team_id, jersey_color, helmet_color, pants_color)

@rpc("authority", "reliable")
func spawn_remote_skater(peer_id: int, team_slot: int, team_id: int, jersey_color: Color, helmet_color: Color, pants_color: Color, is_left_handed: bool, player_name: String) -> void:
	remote_skater_spawn_requested.emit(peer_id, team_slot, team_id, jersey_color, helmet_color, pants_color, is_left_handed, player_name)

@rpc("authority", "reliable")
func sync_existing_players(player_data: Array) -> void:
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

func notify_goal_to_all(scoring_team_id: int, score0: int, score1: int, scorer_name: String) -> void:
	for peer_id in multiplayer.get_peers():
		notify_goal.rpc_id(peer_id, scoring_team_id, score0, score1, scorer_name)

func notify_puck_dropped_to_carrier(carrier_peer_id: int) -> void:
	notify_puck_dropped.rpc_id(carrier_peer_id)

@rpc("authority", "reliable")
func notify_puck_dropped() -> void:
	carrier_puck_dropped.emit()

@rpc("authority", "reliable")
func notify_player_disconnected(peer_id: int) -> void:
	peer_disconnected.emit(peer_id)

@rpc("authority", "reliable")
func notify_goal(scoring_team_id: int, score0: int, score1: int, scorer_name: String) -> void:
	goal_received.emit(scoring_team_id, score0, score1, scorer_name)

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

# ── Sending ───────────────────────────────────────────────────────────────────
func send_slot_assignment(peer_id: int, team_slot: int, team_id: int, jersey_color: Color, helmet_color: Color, pants_color: Color) -> void:
	assign_player_slot.rpc_id(peer_id, team_slot, team_id, jersey_color, helmet_color, pants_color)

func send_spawn_remote_skater(peer_id: int, team_slot: int, team_id: int, jersey_color: Color, helmet_color: Color, pants_color: Color, is_left_handed: bool, player_name: String) -> void:
	spawn_remote_skater.rpc(peer_id, team_slot, team_id, jersey_color, helmet_color, pants_color, is_left_handed, player_name)

func send_sync_existing_players(peer_id: int, player_data: Array) -> void:
	sync_existing_players.rpc_id(peer_id, player_data)

# ── Registration ──────────────────────────────────────────────────────────────
func set_world_state_provider(provider: Callable) -> void:
	_world_state_provider = provider

func register_local_controller(controller: LocalController) -> void:
	_local_controller = controller

func register_remote_controller(peer_id: int, controller: RemoteController) -> void:
	_remote_controllers[peer_id] = controller

func unregister_remote_controller(peer_id: int) -> void:
	_remote_controllers.erase(peer_id)
