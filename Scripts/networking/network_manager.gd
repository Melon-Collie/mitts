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
signal world_state_received(data: PackedByteArray)
signal slot_assigned(team_slot: int, team_id: int, jersey_color: Color, helmet_color: Color, pants_color: Color)
signal remote_skater_spawn_requested(peer_id: int, team_slot: int, team_id: int, jersey_color: Color, helmet_color: Color, pants_color: Color, is_left_handed: bool, player_name: String, jersey_number: int)
signal existing_players_synced(player_data: Array)
signal local_puck_pickup_confirmed
signal local_puck_stolen
signal remote_puck_release_received(direction: Vector3, power: float, is_slapper: bool, shooter_peer_id: int, host_timestamp: float, rtt_ms: float)
signal carrier_puck_dropped
signal remote_carrier_changed(new_carrier_peer_id: int)
signal ghost_state_received(peer_id: int, is_ghost: bool)
signal goal_received(scoring_team_id: int, score0: int, score1: int, scorer_name: String, assist1_name: String, assist2_name: String)
signal faceoff_positions_received(positions: Array)
signal game_reset_received
signal stats_received(data: Array)
signal slot_swap_requested(peer_id: int, new_team_id: int, new_slot: int)
signal slot_swap_confirmed(peer_id: int, old_team_id: int, old_slot: int, new_team_id: int, new_slot: int, jersey: Color, helmet: Color, pants: Color)
signal game_started(config: Dictionary)
signal lobby_roster_synced(roster: Array)
signal team_colors_synced(home_color_id: String, away_color_id: String)
signal return_to_lobby_received(roster: Array)
signal player_ready_changed(peer_id: int, is_ready: bool)
signal rematch_vote_changed(peer_id: int, vote: bool)
signal clock_ready
signal pickup_claim_received(peer_id: int, host_timestamp: float, rtt_ms: float, interp_delay_ms: float)
signal hit_claim_received(hitter_peer_id: int, victim_peer_id: int, host_timestamp: float, rtt_ms: float)
signal goalie_state_transition_received(team_id: int, new_state: int)
signal goalie_shot_reaction_received(team_id: int, impact_x: float, impact_y: float, is_elevated: bool)

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
var pending_home_color_id: String = TeamColorRegistry.DEFAULT_HOME_ID
var pending_away_color_id: String  = TeamColorRegistry.DEFAULT_AWAY_ID
var pending_join_players: Array = []     # sync_existing_players data for join-in-progress
var _local_controller: LocalController = null
var _remote_controllers: Dictionary = {}  # peer_id -> RemoteController
var _peer_handedness: Dictionary = {}     # peer_id -> bool (host only)
var _peer_names: Dictionary = {}          # peer_id -> String (host only)
var _peer_numbers: Dictionary = {}        # peer_id -> int (host only)
var _peer_ping_ms: Dictionary[int, int] = {}  # peer_id -> latest RTT in ms (all peers)
# Callable () -> Array. Set by GameManager at startup so the broadcast loop
# can pull world state without reaching up into the application layer.
var _world_state_provider: Callable = Callable()
var _clock_sync: RefCounted = null  # ClockSync instance, client only
var _session_start_ms: int = 0

# ── Packet-loss tracking ──────────────────────────────────────────────────────
# Client-side: gap detection from received WS sequence numbers.
var _last_ws_seq_received: int = -1
var _ws_drop_window: int = 0
var _ws_recv_window: int = 0
var _ws_loss_window_timer: float = 0.0
var packet_loss_pct: float = 0.0
# Host-side: per-peer loss via echoed sequence numbers in input batches.
var _peer_last_echoed: Dictionary = {}
var _peer_echo_drop_window: Dictionary = {}
var _peer_echo_recv_window: Dictionary = {}
var _peer_loss_rates: Dictionary = {}
var _peer_loss_timer: float = 0.0
# Jitter measurement (client side)
var _jitter_samples: Array[float] = []
var _last_ws_arrival_time: float = -1.0

# ── Timers ────────────────────────────────────────────────────────────────────
var pending_error: String = ""

var _input_timer: float = 0.0
var _state_timer: float = 0.0
var _ping_timer: float = 0.0
const _PING_INTERVAL: float = 2.0
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


func local_time() -> float:
	return (Time.get_ticks_msec() - _session_start_ms) / 1000.0

func start_host() -> void:
	_session_start_ms = Time.get_ticks_msec()
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
func _on_peer_connected(_id: int) -> void:
	pass

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
	_session_start_ms = Time.get_ticks_msec()
	_clock_sync = load("res://Scripts/networking/clock_sync.gd").new()
	_clock_sync.init_session(_session_start_ms)
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
	pending_home_color_id = TeamColorRegistry.DEFAULT_HOME_ID
	pending_away_color_id = TeamColorRegistry.DEFAULT_AWAY_ID
	_input_timer = 0.0
	_state_timer = 0.0
	state_delta = 1.0 / Constants.STATE_RATE
	_connect_timer = -1.0
	_clock_sync = null
	_session_start_ms = 0
	_last_ws_seq_received = -1
	_ws_drop_window = 0
	_ws_recv_window = 0
	_ws_loss_window_timer = 0.0
	packet_loss_pct = 0.0
	_peer_last_echoed.clear()
	_peer_echo_drop_window.clear()
	_peer_echo_recv_window.clear()
	_peer_loss_rates.clear()
	_peer_loss_timer = 0.0
	_jitter_samples.clear()
	_last_ws_arrival_time = -1.0
	NetworkSimManager._pending.clear()

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

	if not is_host and _clock_sync != null:
		if _clock_sync.tick(capped_delta):
			send_ping.rpc_id(1, local_time())

	_ping_timer += capped_delta
	if _ping_timer >= _PING_INTERVAL:
		_ping_timer = 0.0
		if is_host:
			_broadcast_all_pings()
		elif _clock_sync != null and _clock_sync.is_ready:
			report_ping.rpc_id(1, int(get_rtt_ms()))

	if not is_host and _local_controller != null:
		_input_timer += capped_delta
		if _input_timer >= input_delta:
			_input_timer -= input_delta
			var batch_frames: int = 24 if get_peer_loss_rate() > 10.0 else 12
			var batch: Array[InputState] = _local_controller.get_input_batch(batch_frames)
			var buf := PackedByteArray(); buf.resize(3)
			# u16 echo (0xFFFF = no world state received yet), u8 count
			buf.encode_u16(0, _last_ws_seq_received if _last_ws_seq_received >= 0 else 0xFFFF)
			buf.encode_u8(2, batch.size())
			for s: InputState in batch:
				buf.append_array(s.to_bytes())
			NetworkTelemetry.record_input_sent()
			receive_input_batch.rpc_id(1, buf)

	if not is_host:
		_ws_loss_window_timer += capped_delta
		if _ws_loss_window_timer >= 1.0:
			var total: int = _ws_recv_window + _ws_drop_window
			var measured: float = (float(_ws_drop_window) / float(total) * 100.0) if total > 0 else 0.0
			# EMA smoothing (α=0.3, ~3s memory) prevents a single bad second
			# from swinging the batch-size threshold.
			packet_loss_pct = lerpf(packet_loss_pct, measured, 0.3)
			NetworkTelemetry.record_packet_loss(packet_loss_pct)
			_ws_drop_window = 0
			_ws_recv_window = 0
			_ws_loss_window_timer = 0.0

	if is_host:
		_state_timer += capped_delta
		if _state_timer >= state_delta:
			_state_timer -= state_delta
			_broadcast_state()
		_peer_loss_timer += capped_delta
		if _peer_loss_timer >= 1.0:
			for pid: int in _peer_echo_recv_window:
				var recvd: int = _peer_echo_recv_window[pid]
				var dropped: int = _peer_echo_drop_window.get(pid, 0)
				var total: int = recvd + dropped
				_peer_loss_rates[pid] = (float(dropped) / float(total) * 100.0) if total > 0 else 0.0
				_peer_echo_drop_window[pid] = 0
				_peer_echo_recv_window[pid] = 0
			_peer_loss_timer = 0.0

func set_broadcast_rate(hz: float) -> void:
	state_delta = 1.0 / maxf(hz, 1.0)

func _broadcast_state() -> void:
	if not _world_state_provider.is_valid():
		return
	var state: PackedByteArray = _world_state_provider.call()
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
	# Set a generous disconnect window here rather than in _on_peer_connected —
	# peer_connected fires before ENet registers the peer, so get_peer() asserts.
	# By the time any RPC arrives the peer is guaranteed to be in the table.
	var enet_peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet_peer:
		var peer := enet_peer.get_peer(sender_id)
		if peer:
			peer.set_timeout(0, 10000, 60000)
	peer_joined.emit(sender_id)

func get_peer_handedness(peer_id: int) -> bool:
	return _peer_handedness.get(peer_id, true)

func get_peer_name(peer_id: int) -> String:
	return _peer_names.get(peer_id, "Player")

func get_peer_number(peer_id: int) -> int:
	return _peer_numbers.get(peer_id, 10)

@rpc("any_peer", "unreliable_ordered")
func receive_input_batch(data: PackedByteArray) -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	NetworkSimManager.send(
		func(d: PackedByteArray, sid: int) -> void:
			if not _remote_controllers.has(sid):
				push_warning("no remote controller for peer %d" % sid)
				return
			if not is_instance_valid(_remote_controllers[sid]):
				return
			if d.size() < 3:
				return
			var echo_raw: int = d.decode_u16(0)
			_update_peer_echo(sid, -1 if echo_raw == 0xFFFF else echo_raw)
			var count: int = d.decode_u8(2)
			var inputs: Array[InputState] = []
			for i: int in count:
				var off: int = 3 + i * InputState.BYTES_SIZE
				if off + InputState.BYTES_SIZE > d.size():
					break
				inputs.append(InputState.from_bytes(d, off))
			_remote_controllers[sid].receive_input_batch(inputs),
		[data, sender_id], false)

@rpc("authority", "unreliable_ordered")
func receive_world_state(data: PackedByteArray) -> void:
	if is_host:
		return
	NetworkSimManager.send(
		func(s: PackedByteArray) -> void:
			var now: float = local_time()
			if _last_ws_arrival_time > 0.0:
				const EXPECTED_INTERVAL: float = 1.0 / Constants.STATE_RATE
				var jitter: float = absf((now - _last_ws_arrival_time) - EXPECTED_INTERVAL)
				_jitter_samples.append(jitter)
				if _jitter_samples.size() > 40:
					_jitter_samples.pop_front()
				NetworkTelemetry.record_jitter_p95(get_jitter_p95() * 1000.0)
			_last_ws_arrival_time = now
			if s.size() >= 2:
				_on_ws_sequence_received(s.decode_u16(0))
			NetworkTelemetry.record_world_state()
			world_state_received.emit(s),
		[data], false)

# ── Clock Sync ────────────────────────────────────────────────────────────────
@rpc("any_peer", "reliable")
func send_ping(client_send_time: float) -> void:
	if not is_host:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	NetworkSimManager.send(
		func(cst: float, pid: int) -> void:
			receive_pong.rpc_id(pid, cst, local_time()),
		[client_send_time, peer_id], true)

@rpc("authority", "reliable")
func receive_pong(client_send_time: float, host_time: float) -> void:
	if is_host or _clock_sync == null:
		return
	NetworkSimManager.send(
		func(cst: float, ht: float) -> void:
			var was_ready: bool = _clock_sync.is_ready
			_clock_sync.record_pong(cst, ht, local_time())
			if not was_ready and _clock_sync.is_ready:
				clock_ready.emit(),
		[client_send_time, host_time], true)

func send_pickup_claim(host_timestamp: float, rtt_ms: float, interp_delay_ms: float) -> void:
	NetworkSimManager.send(
		func(ts: float, rtt: float, idms: float) -> void:
			receive_pickup_claim.rpc_id(1, ts, rtt, idms),
		[host_timestamp, rtt_ms, interp_delay_ms], true)

@rpc("any_peer", "reliable")
func receive_pickup_claim(host_timestamp: float, rtt_ms: float, interp_delay_ms: float) -> void:
	if not is_host:
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	pickup_claim_received.emit(peer_id, host_timestamp, rtt_ms, interp_delay_ms)

func send_hit_claim(victim_peer_id: int, host_timestamp: float, rtt_ms: float) -> void:
	NetworkSimManager.send(
		func(vpid: int, ts: float, rtt: float) -> void:
			receive_hit_claim.rpc_id(1, vpid, ts, rtt),
		[victim_peer_id, host_timestamp, rtt_ms], true)

@rpc("any_peer", "reliable")
func receive_hit_claim(victim_peer_id: int, host_timestamp: float, rtt_ms: float) -> void:
	if not is_host:
		return
	var hitter_peer_id: int = multiplayer.get_remote_sender_id()
	hit_claim_received.emit(hitter_peer_id, victim_peer_id, host_timestamp, rtt_ms)

func estimated_host_time() -> float:
	if is_host:
		return local_time()
	if _clock_sync == null or not _clock_sync.is_ready:
		return 0.0
	return _clock_sync.estimated_host_time()
	
func is_clock_ready() -> bool:
	return is_host or (_clock_sync != null and _clock_sync.is_ready)

func get_rtt_ms() -> float:
	if _clock_sync == null:
		return 0.0
	return _clock_sync.rtt_ms

func get_latest_rtt_ms() -> float:
	if _clock_sync == null:
		return 0.0
	return _clock_sync.latest_rtt_ms

func get_peer_ping_ms(peer_id: int) -> int:
	return _peer_ping_ms.get(peer_id, 0)

func get_clock_offset_ms() -> float:
	if _clock_sync == null:
		return 0.0
	return _clock_sync._offset * 1000.0

@rpc("any_peer", "unreliable")
func report_ping(rtt_ms: int) -> void:
	_peer_ping_ms[multiplayer.get_remote_sender_id()] = rtt_ms

func _broadcast_all_pings() -> void:
	var pings: Dictionary[int, int] = {}
	for pid: int in _peer_ping_ms:
		pings[pid] = _peer_ping_ms[pid]
	for peer_id: int in multiplayer.get_peers():
		receive_all_pings.rpc_id(peer_id, pings)

@rpc("authority", "unreliable")
func receive_all_pings(pings: Dictionary) -> void:
	for pid: int in pings:
		_peer_ping_ms[pid] = pings[pid]

func on_queue_depth_received(depth: int) -> void:
	if is_host:
		return
	NetworkTelemetry.record_queue_depth(depth)

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
	NetworkSimManager.send(func() -> void: local_puck_pickup_confirmed.emit(), [], true)

func send_ghost_state_to_all(peer_id: int, is_ghost: bool) -> void:
	for remote_id: int in multiplayer.get_peers():
		notify_ghost_state.rpc_id(remote_id, peer_id, is_ghost)

@rpc("authority", "reliable")
func notify_ghost_state(peer_id: int, is_ghost: bool) -> void:
	NetworkSimManager.send(
		func(pid: int, g: bool) -> void: ghost_state_received.emit(pid, g),
		[peer_id, is_ghost], true)

func send_goalie_shot_reaction_to_all(team_id: int, impact_x: float, impact_y: float, is_elevated: bool) -> void:
	for peer_id: int in multiplayer.get_peers():
		notify_goalie_shot_reaction.rpc_id(peer_id, team_id, impact_x, impact_y, is_elevated)

@rpc("authority", "reliable")
func notify_goalie_shot_reaction(team_id: int, impact_x: float, impact_y: float, is_elevated: bool) -> void:
	NetworkSimManager.send(
		func(tid: int, ix: float, iy: float, elev: bool) -> void:
			goalie_shot_reaction_received.emit(tid, ix, iy, elev),
		[team_id, impact_x, impact_y, is_elevated], true)

func send_goalie_state_transition_to_all(team_id: int, new_state: int) -> void:
	for peer_id: int in multiplayer.get_peers():
		notify_goalie_state_transition.rpc_id(peer_id, team_id, new_state)

@rpc("authority", "reliable")
func notify_goalie_state_transition(team_id: int, new_state: int) -> void:
	NetworkSimManager.send(
		func(tid: int, ns: int) -> void: goalie_state_transition_received.emit(tid, ns),
		[team_id, new_state], true)

func send_carrier_changed_to_all(new_carrier_peer_id: int) -> void:
	for peer_id: int in multiplayer.get_peers():
		notify_carrier_changed.rpc_id(peer_id, new_carrier_peer_id)
	remote_carrier_changed.emit(new_carrier_peer_id)

@rpc("authority", "reliable")
func notify_carrier_changed(new_carrier_peer_id: int) -> void:
	NetworkSimManager.send(func(id: int) -> void: remote_carrier_changed.emit(id), [new_carrier_peer_id], true)

func send_puck_stolen(victim_peer_id: int) -> void:
	notify_puck_stolen.rpc_id(victim_peer_id)

@rpc("authority", "reliable")
func notify_puck_stolen() -> void:
	NetworkSimManager.send(func() -> void: local_puck_stolen.emit(), [], true)

func send_puck_release(direction: Vector3, power: float, is_slapper: bool) -> void:
	release_puck.rpc_id(1, direction, power, is_slapper, estimated_host_time(), get_latest_rtt_ms())

@rpc("any_peer", "reliable")
func release_puck(direction: Vector3, power: float, is_slapper: bool, host_timestamp: float, rtt_ms: float) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	NetworkSimManager.send(
		func(d: Vector3, p: float, slap: bool, ts: float, rtt: float, sid: int) -> void:
			remote_puck_release_received.emit(d, p, slap, sid, ts, rtt),
		[direction, power, is_slapper, host_timestamp, rtt_ms, sender], true)

func notify_goal_to_all(scoring_team_id: int, score0: int, score1: int, scorer_name: String, assist1_name: String, assist2_name: String) -> void:
	for peer_id in multiplayer.get_peers():
		notify_goal.rpc_id(peer_id, scoring_team_id, score0, score1, scorer_name, assist1_name, assist2_name)

func notify_puck_dropped_to_carrier(carrier_peer_id: int) -> void:
	notify_puck_dropped.rpc_id(carrier_peer_id)

@rpc("authority", "reliable")
func notify_puck_dropped() -> void:
	NetworkSimManager.send(func() -> void: carrier_puck_dropped.emit(), [], true)

@rpc("authority", "reliable")
func notify_player_disconnected(peer_id: int) -> void:
	peer_disconnected.emit(peer_id)

@rpc("authority", "reliable")
func notify_goal(scoring_team_id: int, score0: int, score1: int, scorer_name: String, assist1_name: String, assist2_name: String) -> void:
	NetworkSimManager.send(
		func(tid: int, s0: int, s1: int, sn: String, a1: String, a2: String) -> void:
			goal_received.emit(tid, s0, s1, sn, a1, a2),
		[scoring_team_id, score0, score1, scorer_name, assist1_name, assist2_name], true)

func send_faceoff_positions(positions: Array) -> void:
	for peer_id in multiplayer.get_peers():
		notify_faceoff_positions.rpc_id(peer_id, positions)

@rpc("authority", "reliable")
func notify_faceoff_positions(positions: Array) -> void:
	NetworkSimManager.send(func(p: Array) -> void: faceoff_positions_received.emit(p), [positions], true)

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

@rpc("any_peer", "reliable")
func request_player_ready(is_ready: bool) -> void:
	var peer_id: int = multiplayer.get_remote_sender_id()
	for remote_id: int in multiplayer.get_peers():
		notify_player_ready.rpc_id(remote_id, peer_id, is_ready)
	player_ready_changed.emit(peer_id, is_ready)

@rpc("authority", "reliable")
func notify_player_ready(peer_id: int, is_ready: bool) -> void:
	player_ready_changed.emit(peer_id, is_ready)

func send_player_ready(is_ready: bool) -> void:
	if is_host:
		player_ready_changed.emit(multiplayer.get_unique_id(), is_ready)
	else:
		request_player_ready.rpc_id(1, is_ready)

@rpc("any_peer", "reliable")
func request_rematch_vote(vote: bool) -> void:
	var peer_id: int = multiplayer.get_remote_sender_id()
	for remote_id: int in multiplayer.get_peers():
		notify_rematch_vote.rpc_id(remote_id, peer_id, vote)
	rematch_vote_changed.emit(peer_id, vote)

@rpc("authority", "reliable")
func notify_rematch_vote(peer_id: int, vote: bool) -> void:
	rematch_vote_changed.emit(peer_id, vote)

func send_rematch_vote(vote: bool) -> void:
	if is_host:
		rematch_vote_changed.emit(multiplayer.get_unique_id(), vote)
	else:
		request_rematch_vote.rpc_id(1, vote)

signal join_in_progress(config: Dictionary)

@rpc("authority", "reliable")
func notify_join_in_progress(p_num_periods: int, p_period_duration: float,
		p_ot_enabled: bool, p_ot_duration: float,
		p_home_color_id: String = TeamColorRegistry.DEFAULT_HOME_ID,
		p_away_color_id: String = TeamColorRegistry.DEFAULT_AWAY_ID) -> void:
	pending_home_color_id = p_home_color_id
	pending_away_color_id = p_away_color_id
	join_in_progress.emit({
		"num_periods": p_num_periods,
		"period_duration": p_period_duration,
		"ot_enabled": p_ot_enabled,
		"ot_duration": p_ot_duration,
		"home_color_id": p_home_color_id,
		"away_color_id": p_away_color_id,
	})

func send_join_in_progress(peer_id: int, config: Dictionary) -> void:
	var hid: String = config.get("home_color_id", pending_home_color_id)
	var aid: String = config.get("away_color_id", pending_away_color_id)
	notify_join_in_progress.rpc_id(peer_id,
		config.num_periods, config.period_duration,
		config.ot_enabled, config.ot_duration, hid, aid)

@rpc("authority", "reliable")
func notify_game_start(p_num_periods: int, p_period_duration: float,
		p_ot_enabled: bool, p_ot_duration: float,
		p_home_color_id: String = TeamColorRegistry.DEFAULT_HOME_ID,
		p_away_color_id: String = TeamColorRegistry.DEFAULT_AWAY_ID) -> void:
	pending_home_color_id = p_home_color_id
	pending_away_color_id = p_away_color_id
	game_started.emit({
		"num_periods": p_num_periods,
		"period_duration": p_period_duration,
		"ot_enabled": p_ot_enabled,
		"ot_duration": p_ot_duration,
		"home_color_id": p_home_color_id,
		"away_color_id": p_away_color_id,
	})

@rpc("authority", "reliable")
func sync_lobby_roster(roster: Array) -> void:
	pending_lobby_roster = roster
	lobby_roster_synced.emit(roster)

func send_game_start(config: Dictionary) -> void:
	var hid: String = config.get("home_color_id", TeamColorRegistry.DEFAULT_HOME_ID)
	var aid: String = config.get("away_color_id", TeamColorRegistry.DEFAULT_AWAY_ID)
	pending_home_color_id = hid
	pending_away_color_id = aid
	for peer_id: int in multiplayer.get_peers():
		notify_game_start.rpc_id(peer_id,
			config.num_periods, config.period_duration,
			config.ot_enabled, config.ot_duration, hid, aid)
	game_started.emit(config)

func send_lobby_roster(peer_id: int, roster: Array) -> void:
	sync_lobby_roster.rpc_id(peer_id, roster)

@rpc("authority", "reliable")
func notify_team_colors(home_color_id: String, away_color_id: String) -> void:
	pending_home_color_id = home_color_id
	pending_away_color_id = away_color_id
	team_colors_synced.emit(home_color_id, away_color_id)

func send_team_colors(home_id: String, away_id: String) -> void:
	pending_home_color_id = home_id
	pending_away_color_id = away_id
	for peer_id: int in multiplayer.get_peers():
		notify_team_colors.rpc_id(peer_id, home_id, away_id)

func send_team_colors_to(peer_id: int, home_id: String, away_id: String) -> void:
	notify_team_colors.rpc_id(peer_id, home_id, away_id)

@rpc("authority", "reliable")
func notify_return_to_lobby(roster: Array) -> void:
	pending_lobby_roster = roster
	return_to_lobby_received.emit(roster)

func send_return_to_lobby_to_all(roster: Array) -> void:
	for peer_id: int in multiplayer.get_peers():
		notify_return_to_lobby.rpc_id(peer_id, roster)
	pending_lobby_roster = roster
	return_to_lobby_received.emit(roster)

func get_jitter_p95() -> float:
	if _jitter_samples.is_empty():
		return 0.0
	var sorted: Array = _jitter_samples.duplicate()
	sorted.sort()
	return sorted[mini(int(sorted.size() * 0.95), sorted.size() - 1)]

func get_target_interpolation_delay() -> float:
	if not is_clock_ready():
		return Constants.NETWORK_INTERPOLATION_DELAY
	var rtt: float = get_rtt_ms() / 1000.0
	var rtt_half: float = rtt / 2.0
	var broadcast_interval: float = 1.0 / Constants.STATE_RATE
	# Minimum is RTT/2 + one full broadcast interval so render_time always has
	# a buffered state ahead of it between packet arrivals. Jitter margin on top.
	var target: float = rtt_half + broadcast_interval + get_jitter_p95() * 1.5
	return clampf(target, maxf(rtt_half + broadcast_interval, 0.016), 0.200)

func adapt_interpolation_delay(current: float) -> float:
	var target: float = get_target_interpolation_delay()
	var change: float = lerpf(current, target, 0.15) - current
	return current + clampf(change, -0.001, 0.005)

func get_peer_loss_rate(peer_id: int = -1) -> float:
	if is_host:
		return _peer_loss_rates.get(peer_id, 0.0)
	return packet_loss_pct

func _on_ws_sequence_received(seq: int) -> void:
	if _last_ws_seq_received >= 0:
		var gap: int = (seq - _last_ws_seq_received - 1 + 65536) % 65536
		_ws_drop_window += gap
	_ws_recv_window += 1
	_last_ws_seq_received = seq

func _update_peer_echo(peer_id: int, echoed_seq: int) -> void:
	if echoed_seq < 0:
		return
	if not _peer_last_echoed.has(peer_id):
		_peer_last_echoed[peer_id] = echoed_seq
		_peer_echo_drop_window[peer_id] = 0
		_peer_echo_recv_window[peer_id] = 0
		return
	var prev: int = _peer_last_echoed[peer_id]
	if echoed_seq == prev:
		return  # duplicate echo between WS ticks
	var gap: int = (echoed_seq - prev - 1 + 65536) % 65536
	_peer_echo_drop_window[peer_id] += gap
	_peer_echo_recv_window[peer_id] += 1
	_peer_last_echoed[peer_id] = echoed_seq

# ── Registration ──────────────────────────────────────────────────────────────
func set_world_state_provider(provider: Callable) -> void:
	_world_state_provider = provider

func register_local_controller(controller: LocalController) -> void:
	_local_controller = controller

func register_remote_controller(peer_id: int, controller: RemoteController) -> void:
	_remote_controllers[peer_id] = controller

func unregister_remote_controller(peer_id: int) -> void:
	_remote_controllers.erase(peer_id)
