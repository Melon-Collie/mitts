class_name PuckController
extends Node

@export var interpolation_delay: float = 0.1
@export var prediction_reconcile_threshold: float = 1.0

var puck: Puck = null
var is_server: bool = false

# ── State ─────────────────────────────────────────────────────────────────────
var _carrier_peer_id: int = -1
var _current_time: float = 0.0
var _state_buffer: Array[BufferedPuckState] = []
var _predicting_trajectory: bool = false
var _predicted_velocity: Vector3 = Vector3.ZERO

# ── Setup ─────────────────────────────────────────────────────────────────────
func setup(assigned_puck: Puck, assigned_is_server: bool) -> void:
	puck = assigned_puck
	is_server = assigned_is_server
	puck.set_server_mode(is_server)
	if is_server:
		puck.puck_picked_up.connect(_on_puck_picked_up)
		puck.puck_released.connect(_on_puck_released)

func _physics_process(delta: float) -> void:
	if puck == null or is_server:
		return
	_current_time += delta
	if _carrier_peer_id == multiplayer.get_unique_id():
		_apply_local_carrier_position()
	elif _predicting_trajectory:
		_step_prediction(delta)
	else:
		_interpolate()

# ── Local Prediction ──────────────────────────────────────────────────────────
func notify_local_pickup() -> void:
	_carrier_peer_id = multiplayer.get_unique_id()
	_predicting_trajectory = false

func notify_local_release(direction: Vector3, power: float) -> void:
	_carrier_peer_id = -1
	_predicting_trajectory = true
	_predicted_velocity = direction * power
	_state_buffer.clear()

# Called when the server forcibly ends a carry (e.g. goal scored).
# Does not start trajectory prediction — just drops back to interpolation.
func notify_local_puck_dropped() -> void:
	_carrier_peer_id = -1
	_predicting_trajectory = false
	_state_buffer.clear()

func _apply_local_carrier_position() -> void:
	var record := GameManager.get_local_player()
	if record == null:
		return
	var blade_world := record.skater.upper_body_to_global(record.skater.get_blade_position())
	blade_world.y = puck.ice_height
	puck.set_puck_position(blade_world)

func _step_prediction(delta: float) -> void:
	_predicted_velocity.x *= (1.0 - Constants.ICE_FRICTION * delta)
	_predicted_velocity.z *= (1.0 - Constants.ICE_FRICTION * delta)
	puck.set_puck_position(puck.get_puck_position() + _predicted_velocity * delta)

# ── Server Signals ────────────────────────────────────────────────────────────
func _on_puck_picked_up(carrier: Skater) -> void:
	for peer_id in GameManager.players:
		var record: PlayerRecord = GameManager.players[peer_id]
		if record.skater == carrier:
			_carrier_peer_id = peer_id
			record.controller.on_puck_picked_up_network()
			if not record.is_local:
				NetworkManager.send_puck_picked_up(peer_id)
			return

func _on_puck_released() -> void:
	if _carrier_peer_id != -1 and GameManager.players.has(_carrier_peer_id):
		GameManager.players[_carrier_peer_id].controller.on_puck_released_network()
	_carrier_peer_id = -1

# ── State Serialization ───────────────────────────────────────────────────────
func get_state() -> Array:
	var state := PuckNetworkState.new()
	state.position = puck.get_puck_position()
	state.velocity = puck.get_puck_velocity()
	state.carrier_peer_id = _carrier_peer_id
	return state.to_array()

func apply_state(state: PuckNetworkState) -> void:
	if is_server:
		return
	if _predicting_trajectory:
		var error := puck.get_puck_position().distance_to(state.position)
		if error > prediction_reconcile_threshold:
			_predicting_trajectory = false
			puck.set_puck_position(state.position)
			_state_buffer.clear()
		elif _state_buffer.size() >= 2:
			_predicting_trajectory = false
	var buffered := BufferedPuckState.new()
	buffered.timestamp = _current_time
	buffered.state = state
	_state_buffer.append(buffered)
	if _state_buffer.size() > 10:
		_state_buffer.pop_front()

func _interpolate() -> void:
	var render_time: float = _current_time - interpolation_delay
	if _state_buffer.size() < 2:
		return
	var from_state: BufferedPuckState = null
	var to_state: BufferedPuckState = null
	for i in range(_state_buffer.size() - 1):
		var a: BufferedPuckState = _state_buffer[i]
		var b: BufferedPuckState = _state_buffer[i + 1]
		if a.timestamp <= render_time and render_time <= b.timestamp:
			from_state = a
			to_state = b
			break
	if from_state == null or to_state == null:
		_apply_state_to_puck(_state_buffer.back().state)
		return
	var t: float = clampf((render_time - from_state.timestamp) / (to_state.timestamp - from_state.timestamp), 0.0, 1.0)
	var interpolated := PuckNetworkState.new()
	interpolated.position = from_state.state.position.lerp(to_state.state.position, t)
	interpolated.velocity = from_state.state.velocity.lerp(to_state.state.velocity, t)
	_apply_state_to_puck(interpolated)
	while _state_buffer.size() > 2 and _state_buffer[1].timestamp < render_time:
		_state_buffer.pop_front()

func _apply_state_to_puck(state: PuckNetworkState) -> void:
	puck.set_puck_position(state.position)
	puck.set_puck_velocity(state.velocity)
