extends Node

# ── State ─────────────────────────────────────────────────────────────────────
var is_host: bool = false
var _local_controller: LocalController = null
var _remote_controllers: Dictionary = {}  # peer_id -> RemoteController

# ── Timers ────────────────────────────────────────────────────────────────────
var _input_timer: float = 0.0
var _state_timer: float = 0.0
var _connect_timer: float = -1.0
const INPUT_DELTA: float = 1.0 / Constants.INPUT_RATE
const STATE_DELTA: float = 1.0 / Constants.STATE_RATE
const CONNECT_TIMEOUT: float = 10.0

func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_args()
	if "--host" in args:
		_start_host()
	elif "--connect" in args:
		var connect_idx: int = args.find("--connect")
		if connect_idx + 1 >= args.size():
			push_error("--connect requires an IP address argument")
			return
		_start_client(args[connect_idx + 1])
	else:
		_start_offline()

# ── Connection ────────────────────────────────────────────────────────────────
func _start_offline() -> void:
	is_host = true
	print("Offline mode")
	GameManager.on_host_started()

func _start_host() -> void:
	is_host = true
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(Constants.PORT, Constants.MAX_PLAYERS)
	if error != OK:
		push_error("Failed to start server: " + str(error))
		return
	multiplayer.multiplayer_peer = peer
	print("Server started on port ", Constants.PORT)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	GameManager.on_host_started()

func _start_client(ip: String) -> void:
	is_host = false
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip, Constants.PORT)
	if error != OK:
		push_error("Failed to connect: " + str(error))
		return
	multiplayer.multiplayer_peer = peer
	_connect_timer = 0.0
	print("Connecting to ", ip, ":", Constants.PORT)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

# ── Network Signals ───────────────────────────────────────────────────────────
func _on_peer_connected(id: int) -> void:
	print("Player connected: ", id)
	GameManager.on_player_connected(id)

func _on_peer_disconnected(id: int) -> void:
	print("Player disconnected: ", id)
	GameManager.on_player_disconnected(id)
	# Notify all remaining clients so they remove the stale skater.
	for peer_id in multiplayer.get_peers():
		notify_player_disconnected.rpc_id(peer_id, id)

func _on_connected_to_server() -> void:
	_connect_timer = -1.0
	print("Connected! My ID: ", multiplayer.get_unique_id())
	GameManager.on_connected_to_server()

func _on_connection_failed() -> void:
	push_error("Connection failed")

func _on_server_disconnected() -> void:
	push_error("Server disconnected")
	_close()

func _exit_tree() -> void:
	_close()

func _close() -> void:
	if multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
		multiplayer.multiplayer_peer.close()

# ── Process ───────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if _connect_timer >= 0.0:
		_connect_timer += delta
		if _connect_timer >= CONNECT_TIMEOUT:
			push_error("Connection timed out after %ds" % CONNECT_TIMEOUT)
			get_tree().quit()

	if not is_host and _local_controller != null:
		_input_timer += delta
		if _input_timer >= INPUT_DELTA:
			_input_timer -= INPUT_DELTA
			var state: InputState = _local_controller.get_current_input()
			receive_input.rpc_id(1, state.to_array())

	if is_host:
		_state_timer += delta
		if _state_timer >= STATE_DELTA:
			_state_timer -= STATE_DELTA
			_broadcast_state()

func _broadcast_state() -> void:
	var state: Array = GameManager.get_world_state()
	for peer_id in multiplayer.get_peers():
		receive_world_state.rpc_id(peer_id, state)

# ── RPCs ──────────────────────────────────────────────────────────────────────
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
	GameManager.apply_world_state(state)

@rpc("authority", "reliable")
func assign_player_slot(slot: int, team_id: int) -> void:
	GameManager.on_slot_assigned(slot, team_id)

@rpc("authority", "reliable")
func spawn_remote_skater(peer_id: int, slot: int, team_id: int) -> void:
	GameManager.spawn_remote_skater(peer_id, slot, team_id)

@rpc("authority", "reliable")
func sync_existing_players(player_data: Array) -> void:
	GameManager.sync_existing_players(player_data)
	
func send_puck_picked_up(peer_id: int) -> void:
	notify_puck_picked_up.rpc_id(peer_id)

@rpc("authority", "reliable")
func notify_puck_picked_up() -> void:
	GameManager.on_local_player_picked_up_puck()

func send_puck_stolen(victim_peer_id: int) -> void:
	notify_puck_stolen.rpc_id(victim_peer_id)

@rpc("authority", "reliable")
func notify_puck_stolen() -> void:
	GameManager.on_local_player_puck_stolen()

func send_puck_release(direction: Vector3, power: float) -> void:
	release_puck.rpc_id(1, direction, power)

@rpc("any_peer", "reliable")
func release_puck(direction: Vector3, power: float) -> void:
	GameManager.puck_controller.puck.release(direction, power)

func notify_goal_to_all(scoring_team_id: int, score0: int, score1: int) -> void:
	for peer_id in multiplayer.get_peers():
		notify_goal.rpc_id(peer_id, scoring_team_id, score0, score1)

@rpc("authority", "reliable")
func notify_player_disconnected(peer_id: int) -> void:
	GameManager.on_player_disconnected(peer_id)

@rpc("authority", "reliable")
func notify_goal(scoring_team_id: int, score0: int, score1: int) -> void:
	GameManager.on_goal_scored(scoring_team_id, score0, score1)

func send_faceoff_positions(positions: Array) -> void:
	for peer_id in multiplayer.get_peers():
		notify_faceoff_positions.rpc_id(peer_id, positions)

@rpc("authority", "reliable")
func notify_faceoff_positions(positions: Array) -> void:
	GameManager.on_faceoff_positions(positions)

# ── Sending ───────────────────────────────────────────────────────────────────
func send_slot_assignment(peer_id: int, slot: int, team_id: int) -> void:
	assign_player_slot.rpc_id(peer_id, slot, team_id)

func send_spawn_remote_skater(peer_id: int, slot: int, team_id: int) -> void:
	spawn_remote_skater.rpc(peer_id, slot, team_id)

func send_sync_existing_players(peer_id: int, player_data: Array) -> void:
	sync_existing_players.rpc_id(peer_id, player_data)

# ── Registration ──────────────────────────────────────────────────────────────
func register_local_controller(controller: LocalController) -> void:
	_local_controller = controller

func register_remote_controller(peer_id: int, controller: RemoteController) -> void:
	_remote_controllers[peer_id] = controller

func unregister_remote_controller(peer_id: int) -> void:
	_remote_controllers.erase(peer_id)
