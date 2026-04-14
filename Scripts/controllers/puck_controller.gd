class_name PuckController
extends Node

@export var interpolation_delay: float = 0.1
@export var prediction_reconcile_threshold: float = 3.0
@export var position_correction_blend: float = 0.3
@export var velocity_correction_blend: float = 0.5

var puck: Puck = null
var is_server: bool = false

# ── State ─────────────────────────────────────────────────────────────────────
var _carrier_peer_id: int = -1            # server-side authoritative carrier
var _local_carrier_skater: Skater = null  # client-side: local skater while carrying
var _current_time: float = 0.0
var _state_buffer: Array[BufferedPuckState] = []
var _predicting_trajectory: bool = false

# Callable (Skater) -> int peer_id, or -1 if not registered. Set by GameManager
# at spawn time so PuckController doesn't reach into GameManager.players.
var _peer_id_resolver: Callable = Callable()

# ── Signals (server-side puck events, GameManager listens) ───────────────────
signal puck_picked_up_by(peer_id: int)
signal puck_released_by_carrier(peer_id: int)
signal puck_stripped_from(peer_id: int)

# ── Setup ─────────────────────────────────────────────────────────────────────
func setup(assigned_puck: Puck, assigned_is_server: bool) -> void:
	puck = assigned_puck
	is_server = assigned_is_server
	puck.set_server_mode(is_server)
	process_physics_priority = 1  # Run after Skater.move_and_slide so blade world pos is current
	if is_server:
		puck.puck_picked_up.connect(_on_puck_picked_up)
		puck.puck_released.connect(_on_puck_released)
		puck.puck_stripped.connect(_on_puck_stripped)

func set_peer_id_resolver(resolver: Callable) -> void:
	_peer_id_resolver = resolver

func _physics_process(delta: float) -> void:
	if puck == null or is_server:
		return
	_current_time += delta
	if _local_carrier_skater != null:
		_apply_local_carrier_position()
	elif not _predicting_trajectory:
		_interpolate()
	# During prediction, Jolt runs freely — no manual stepping needed

# ── Local Prediction ──────────────────────────────────────────────────────────
func notify_local_pickup(local_skater: Skater) -> void:
	_local_carrier_skater = local_skater
	_predicting_trajectory = false
	puck.set_client_prediction_mode(false)

func notify_local_release(direction: Vector3, power: float) -> void:
	_local_carrier_skater = null
	_predicting_trajectory = true
	puck.set_client_prediction_mode(true)
	puck.set_puck_velocity(direction * power)
	_state_buffer.clear()

# Called when the server forcibly ends a carry (e.g. goal scored).
# Does not start trajectory prediction — just drops back to interpolation.
func notify_local_puck_dropped() -> void:
	_local_carrier_skater = null
	_predicting_trajectory = false
	puck.set_client_prediction_mode(false)
	_state_buffer.clear()

func _apply_local_carrier_position() -> void:
	var blade_world: Vector3 = _local_carrier_skater.upper_body_to_global(
			_local_carrier_skater.get_blade_position())
	blade_world.y = puck.ice_height
	puck.set_puck_position(blade_world)

# ── Reconciliation ────────────────────────────────────────────────────────────
# Mirrors LocalController.reconcile — nudges Jolt state toward server truth each
# broadcast. Hard-snaps only on extreme divergence (teleport, physics glitch).
func _reconcile(state: PuckNetworkState) -> void:
	if ReconciliationRules.puck_needs_hard_snap(
			puck.get_puck_position(), state.position, prediction_reconcile_threshold):
		puck.set_puck_position(state.position)
		puck.set_puck_velocity(state.velocity)
		_state_buffer.clear()
		return
	var current_vel := puck.get_puck_velocity()
	var pos_error := state.position - puck.get_puck_position()
	puck.set_puck_velocity(current_vel.lerp(state.velocity, velocity_correction_blend))
	# Only nudge position when velocities agree — avoids fighting Jolt during
	# bounces where velocities are briefly opposing.
	if current_vel.dot(state.velocity) > 0.0:
		puck.set_puck_position(puck.get_puck_position() + pos_error * position_correction_blend)

# ── Server Signals ────────────────────────────────────────────────────────────
# These run on host only (connected in setup() when is_server). Each resolves
# the affected peer_id via the injected resolver and emits a signal upward.
# GameManager listens and does the player-registry / RPC work.
func _on_puck_picked_up(carrier: Skater) -> void:
	if not _peer_id_resolver.is_valid():
		return
	var peer_id: int = _peer_id_resolver.call(carrier)
	if peer_id == -1:
		return
	_carrier_peer_id = peer_id
	puck_picked_up_by.emit(peer_id)

func _on_puck_released() -> void:
	var peer_id: int = _carrier_peer_id
	_carrier_peer_id = -1
	if peer_id != -1:
		puck_released_by_carrier.emit(peer_id)

func _on_puck_stripped(ex_carrier: Skater) -> void:
	if ex_carrier == null:
		return
	if not _peer_id_resolver.is_valid():
		return
	var peer_id: int = _peer_id_resolver.call(ex_carrier)
	if peer_id == -1:
		return
	puck_stripped_from.emit(peer_id)

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
		if state.carrier_peer_id != -1:
			# Someone picked it up — hand back to buffered interpolation
			_predicting_trajectory = false
			puck.set_client_prediction_mode(false)
		else:
			_reconcile(state)
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
	# Position only — puck is frozen during interpolation, Jolt ignores velocity.
	puck.set_puck_position(state.position)
