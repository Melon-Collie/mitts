extends Node

# ── Scenes ────────────────────────────────────────────────────────────────────
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const GOALIE_SCENE: PackedScene = preload("res://Scenes/Goalie.tscn")
const LOCAL_CONTROLLER_SCENE: PackedScene = preload("res://Scenes/LocalController.tscn")
const REMOTE_CONTROLLER_SCENE: PackedScene = preload("res://Scenes/RemoteController.tscn")

# ── Game State ────────────────────────────────────────────────────────────────
var puck: Puck = null
var goalies: Array = []
var players: Dictionary = {}  # peer_id -> PlayerRecord
var _next_slot: int = 1       # host is always slot 0

var puck_controller: PuckController = null

func _ready() -> void:
	pass

# ── Network Callbacks ─────────────────────────────────────────────────────────
func on_host_started() -> void:
	_spawn_world()
	_spawn_local_player(1, 0)

func on_connected_to_server() -> void:
	pass

func on_slot_assigned(slot: int) -> void:
	_spawn_world()
	_spawn_local_player(multiplayer.get_unique_id(), slot)

func on_player_connected(peer_id: int) -> void:
	if not NetworkManager.is_host:
		return
	var slot: int = _next_slot
	_next_slot += 1

	NetworkManager.send_slot_assignment(peer_id, slot)

	var existing: Array = []
	for existing_peer_id in players:
		existing.append([existing_peer_id, players[existing_peer_id].slot])
	NetworkManager.send_sync_existing_players(peer_id, existing)

	NetworkManager.send_spawn_remote_skater(peer_id, slot)

	_spawn_remote_player(peer_id, slot)

func on_player_disconnected(peer_id: int) -> void:
	if not players.has(peer_id):
		return
	var record: PlayerRecord = players[peer_id]
	if record.controller:
		record.controller.queue_free()
	if record.skater:
		record.skater.queue_free()
	players.erase(peer_id)

func sync_existing_players(player_data: Array) -> void:
	for entry in player_data:
		var peer_id: int = entry[0]
		var slot: int = entry[1]
		_spawn_remote_player(peer_id, slot)

func spawn_remote_skater(peer_id: int, slot: int) -> void:
	if peer_id == multiplayer.get_unique_id():
		return
	_spawn_remote_player(peer_id, slot)

# ── Spawning ──────────────────────────────────────────────────────────────────
func _spawn_world() -> void:
	_spawn_puck()
	_spawn_goalies()

func _spawn_puck() -> void:
	puck = PUCK_SCENE.instantiate()
	puck.position = Constants.PUCK_START_POS
	get_tree().current_scene.add_child(puck)
	puck_controller = PuckController.new()
	get_tree().current_scene.add_child(puck_controller)
	puck_controller.setup(puck, NetworkManager.is_host)

func _spawn_goalies() -> void:
	var top: Goalie = GOALIE_SCENE.instantiate()
	var bottom: Goalie = GOALIE_SCENE.instantiate()
	get_tree().current_scene.add_child(top)
	get_tree().current_scene.add_child(bottom)

	var top_controller := GoalieController.new()
	var bottom_controller := GoalieController.new()
	get_tree().current_scene.add_child(top_controller)
	get_tree().current_scene.add_child(bottom_controller)
	top_controller.setup(top, puck, -Constants.GOAL_LINE_Z)
	bottom_controller.setup(bottom, puck, Constants.GOAL_LINE_Z)

	goalies.append(top)
	goalies.append(bottom)

func _spawn_local_player(peer_id: int, slot: int) -> void:
	var record := PlayerRecord.new(peer_id, slot, true)

	var skater: Skater = SKATER_SCENE.instantiate()
	skater.position = Constants.SKATER_START_POSITIONS[slot]
	get_tree().current_scene.add_child(skater)
	record.skater = skater

	var controller: LocalController = LOCAL_CONTROLLER_SCENE.instantiate()
	get_tree().current_scene.add_child(controller)
	controller.setup(skater, puck)
	record.controller = controller
	
	controller.puck_release_requested.connect(_on_puck_release_requested)

	players[peer_id] = record
	NetworkManager.register_local_controller(controller)

func _spawn_remote_player(peer_id: int, slot: int) -> void:
	var record := PlayerRecord.new(peer_id, slot, false)

	var skater: Skater = SKATER_SCENE.instantiate()
	skater.position = Constants.SKATER_START_POSITIONS[slot]
	get_tree().current_scene.add_child(skater)
	record.skater = skater

	var controller: RemoteController = REMOTE_CONTROLLER_SCENE.instantiate()
	get_tree().current_scene.add_child(controller)
	controller.setup(skater, puck)
	record.controller = controller

	players[peer_id] = record
	NetworkManager.register_remote_controller(peer_id, controller)

# ── World State ───────────────────────────────────────────────────────────────
func get_world_state() -> Array:
	var state: Array = []
	for peer_id in players:
		var record: PlayerRecord = players[peer_id]
		state.append(peer_id)
		state.append(record.controller.get_network_state())
	state.append_array(puck_controller.get_state())
	return state

func apply_world_state(state: Array) -> void:
	var i: int = 0
	while i < state.size() - 3:
		var peer_id: int = state[i]
		var skater_state: Array = state[i + 1]
		i += 2
		if not players.has(peer_id):
			continue
		var record: PlayerRecord = players[peer_id]
		var skater_network_state := SkaterNetworkState.from_array(skater_state)
		if record.is_local:
			(record.controller as LocalController).reconcile(skater_network_state)
			continue
		record.controller.apply_network_state(skater_network_state)

	# Puck state
	if puck_controller == null:
		return
	var puck_state := PuckNetworkState.from_array([state[i], state[i + 1], state[i + 2]])
	puck_controller.apply_state(puck_state)

# ── Accessors ─────────────────────────────────────────────────────────────────
func get_puck() -> Puck:
	return puck

func get_local_player() -> PlayerRecord:
	for peer_id in players:
		if players[peer_id].is_local:
			return players[peer_id]
	return null
	
func on_local_player_picked_up_puck() -> void:
	var record := get_local_player()
	if record != null:
		record.controller.on_puck_picked_up_network()
	puck_controller.notify_local_pickup()

func _on_puck_release_requested(direction: Vector3, power: float) -> void:
	if NetworkManager.is_host:
		puck.release(direction, power)
	else:
		var record := get_local_player()
		if record != null:
			record.controller.on_puck_released_network()
		puck_controller.notify_local_release(direction, power)
		NetworkManager.send_puck_release(direction, power)
