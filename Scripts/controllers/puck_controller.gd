class_name PuckController
extends Node

const PICKUP_RADIUS: float = 0.5
const POKE_RADIUS: float = 0.5

@export var interpolation_delay: float = Constants.NETWORK_INTERPOLATION_DELAY
@export var extrapolation_max_ms: float = 50.0
@export var prediction_reconcile_threshold: float = 3.0
@export var position_correction_blend: float = 0.3
@export var velocity_correction_blend: float = 0.5

var puck: Puck = null
var is_server: bool = false

# ── State ─────────────────────────────────────────────────────────────────────
var _carrier_peer_id: int = -1            # server-side authoritative carrier
var _local_carrier_skater: Skater = null  # client-side: local skater while carrying
var _current_time: float = 0.0
var _prev_puck_pos: Vector3 = Vector3.ZERO
var _state_buffer: Array[BufferedPuckState] = []
var _predicting_trajectory: bool = false
var is_extrapolating: bool = false

func get_buffer_depth() -> int:
	return _state_buffer.size()

# Callable (Skater) -> int peer_id, or -1 if not registered.
var _peer_id_resolver: Callable = Callable()
# Callable () -> Array[Skater] of all active skaters. Host-only interaction detection.
var _skater_getter: Callable = Callable()
# Callable (Skater) -> int team_id. Used by poke-check eligibility.
var _team_id_resolver: Callable = Callable()

# ── Signals (server-side puck events, GameManager listens) ───────────────────
signal puck_picked_up_by(peer_id: int)
signal puck_released_by_carrier(peer_id: int)
signal puck_stripped_from(peer_id: int)
signal puck_touched_while_loose(peer_id: int)  # deflection or body block — peer who touched
signal puck_touched_by_goalie(goalie: Goalie)  # puck contacted a goalie body while a shot was in flight

# ── Setup ─────────────────────────────────────────────────────────────────────
func setup(assigned_puck: Puck, assigned_is_server: bool) -> void:
	puck = assigned_puck
	is_server = assigned_is_server
	puck.set_server_mode(is_server)
	process_physics_priority = 1  # Run after Skater.move_and_slide so blade world pos is current
	if is_server:
		puck.puck_released.connect(_on_puck_released)
		puck.puck_stripped.connect(_on_puck_stripped)
		puck.puck_touched_loose.connect(func(s: Skater) -> void: puck_touched_while_loose.emit(_peer_id_resolver.call(s)))
		puck.puck_touched_goalie.connect(func(g: Goalie) -> void: puck_touched_by_goalie.emit(g))

func set_peer_id_resolver(resolver: Callable) -> void:
	_peer_id_resolver = resolver

func set_skater_getter(getter: Callable) -> void:
	_skater_getter = getter

func set_team_id_resolver(resolver: Callable) -> void:
	_team_id_resolver = resolver

func _physics_process(delta: float) -> void:
	if puck == null:
		return
	if is_server:
		_check_interactions()
		_prev_puck_pos = puck.get_puck_position()
		return
	_current_time += delta
	if _local_carrier_skater != null:
		_apply_local_carrier_position()
	elif not _predicting_trajectory:
		_interpolate()
	# During prediction, Jolt runs freely — no manual stepping needed

# ── Server Interaction Detection ─────────────────────────────────────────────
func _check_interactions() -> void:
	if not _skater_getter.is_valid():
		return
	var puck_curr: Vector3 = puck.get_puck_position()
	var skaters: Array = _skater_getter.call()

	if puck.carrier != null:
		if not puck.pickup_locked:
			for skater: Skater in skaters:
				if skater == puck.carrier or skater.is_ghost:
					continue
				var carrier_team: int = _team_id_resolver.call(puck.carrier)
				var checker_team: int = _team_id_resolver.call(skater)
				if not PuckCollisionRules.can_poke_check(carrier_team, checker_team):
					continue
				if PuckInteractionRules.check_poke(_prev_puck_pos, puck_curr,
						skater.get_blade_contact_global(), POKE_RADIUS):
					puck.apply_poke_check(skater)
					break
	else:
		if not puck.pickup_locked:
			for skater: Skater in skaters:
				if skater.is_ghost or puck.is_on_cooldown(skater):
					continue
				if not PuckInteractionRules.check_pickup(_prev_puck_pos, puck_curr,
						skater.get_blade_contact_global(), PICKUP_RADIUS):
					continue
				var puck_speed: float = puck.get_puck_velocity().length()
				var rel_speed: float = (puck.get_puck_velocity() - skater.blade_world_velocity).length()
				if puck_speed <= puck.pickup_max_speed or rel_speed < puck.deflect_min_speed:
					puck.set_carrier(skater)
					_on_puck_picked_up(skater)
				else:
					puck.apply_blade_deflect(skater)
				break


# ── Local Prediction ──────────────────────────────────────────────────────────
func notify_local_pickup(local_skater: Skater) -> void:
	_local_carrier_skater = local_skater
	_predicting_trajectory = false
	puck.set_client_prediction_mode(false)
	_state_buffer.clear()

func notify_local_release(direction: Vector3, power: float) -> void:
	_local_carrier_skater = null
	_predicting_trajectory = true
	puck.set_client_prediction_mode(true)
	puck.set_puck_velocity(direction * power)
	_state_buffer.clear()

func notify_remote_carrier_changed(new_carrier_peer_id: int) -> void:
	# Guard: don't kill our own trajectory prediction — we initiated the release
	# locally and are soft-reconciling via world state.
	if new_carrier_peer_id == -1 and _predicting_trajectory:
		return
	_predicting_trajectory = false
	puck.set_client_prediction_mode(false)

# Called when the server forcibly ends a carry (e.g. goal scored).
# Does not start trajectory prediction — just drops back to interpolation.
func notify_local_puck_dropped() -> void:
	_local_carrier_skater = null
	_predicting_trajectory = false
	puck.set_client_prediction_mode(false)
	_state_buffer.clear()

func _apply_local_carrier_position() -> void:
	# Pin puck at the blade contact point (mid-blade), not the heel (Marker3D).
	var contact: Vector3 = _local_carrier_skater.get_blade_contact_global()
	contact.y = puck.ice_height
	puck.set_puck_position(contact)

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
# Run on host only (connected in setup() when is_server). Each resolves the
# affected peer_id via the injected resolver and emits a signal upward — the
# three variants below differ only in how peer_id is sourced (resolve from
# the skater argument vs. read the cached carrier) and which signal fires.
# GameManager listens and does the player-registry / RPC work.
func _on_puck_picked_up(carrier: Skater) -> void:
	var peer_id: int = _resolve_peer_id(carrier)
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
	var peer_id: int = _resolve_peer_id(ex_carrier)
	if peer_id == -1:
		return
	puck_stripped_from.emit(peer_id)

func _resolve_peer_id(skater: Skater) -> int:
	if skater == null or not _peer_id_resolver.is_valid():
		return -1
	return _peer_id_resolver.call(skater)

# ── State Serialization ───────────────────────────────────────────────────────
# Returns the typed network state object. Flattening to Array happens at the
# RPC boundary (GameManager.get_world_state), not here.
func get_state() -> PuckNetworkState:
	var state := PuckNetworkState.new()
	state.position = puck.get_puck_position()
	state.velocity = puck.get_puck_velocity()
	state.carrier_peer_id = _carrier_peer_id
	return state

func apply_state(state: PuckNetworkState) -> void:
	if is_server:
		return
	if _local_carrier_skater != null:
		return  # Puck is pinned to local blade; interpolation isn't running
	if _predicting_trajectory:
		if state.carrier_peer_id != -1:
			# Someone picked it up — hand back to buffered interpolation
			_predicting_trajectory = false
			puck.set_client_prediction_mode(false)
		else:
			_reconcile(state)
			return  # Don't buffer during prediction; interpolation isn't running
	var buffered := BufferedPuckState.new()
	buffered.timestamp = _current_time
	buffered.state = state
	_state_buffer.append(buffered)
	if _state_buffer.size() > 10:
		_state_buffer.pop_front()

func _interpolate() -> void:
	var render_time: float = _current_time - interpolation_delay
	var bracket: BufferedStateInterpolator.BracketResult = BufferedStateInterpolator.find_bracket(
			_state_buffer, render_time)
	is_extrapolating = bracket != null and bracket.is_extrapolating
	if bracket == null:
		return
	var interpolated := PuckNetworkState.new()
	if bracket.is_extrapolating:
		var dt: float = minf(bracket.extrapolation_dt, extrapolation_max_ms / 1000.0)
		var newest: PuckNetworkState = bracket.to_state
		interpolated.position = newest.position + newest.velocity * dt
		interpolated.velocity = newest.velocity
	else:
		interpolated.position = bracket.from_state.position.lerp(bracket.to_state.position, bracket.t)
		interpolated.velocity = bracket.from_state.velocity.lerp(bracket.to_state.velocity, bracket.t)
	_apply_state_to_puck(interpolated)
	BufferedStateInterpolator.drop_stale(_state_buffer, render_time)

func _apply_state_to_puck(state: PuckNetworkState) -> void:
	# Position only — puck is frozen during interpolation, Jolt ignores velocity.
	puck.set_puck_position(state.position)
