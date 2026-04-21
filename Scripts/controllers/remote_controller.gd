class_name RemoteController
extends SkaterController

@export var interpolation_delay: float = Constants.NETWORK_INTERPOLATION_DELAY
@export var extrapolation_max_ms: float = 50.0
@export var rejoin_blend_duration: float = 0.075

var _input_queue: Array[InputState] = []
var _fallback_input: InputState = InputState.new()
var _state_buffer: Array[BufferedSkaterState] = []
var _current_time: float = 0.0
var is_extrapolating: bool = false

var _rejoin_blend_start_time: float = -1.0
var _rejoin_blend_from_pos: Vector3 = Vector3.ZERO
var _rejoin_blend_from_blade: Vector3 = Vector3.ZERO
var _rejoin_blend_from_hand: Vector3 = Vector3.ZERO

func get_buffer_depth() -> int:
	return _state_buffer.size()

func get_queue_depth() -> int:
	return _input_queue.size()

func apply_ghost_rpc(is_ghost: bool) -> void:
	if skater != null:
		skater.set_ghost(is_ghost)

func _physics_process(delta: float) -> void:
	if skater == null:
		return
	if _is_host:
		_drive_from_input(delta)
	else:
		_current_time += delta
		_interpolate()
		skater.update_stick_mesh()

func receive_input_batch(batch: Array[InputState]) -> void:
	var existing_timestamps: Dictionary = {}
	for queued: InputState in _input_queue:
		existing_timestamps[queued.host_timestamp] = true
	for state: InputState in batch:
		if state.host_timestamp > last_processed_host_timestamp and not existing_timestamps.has(state.host_timestamp):
			_input_queue.append(state)
			existing_timestamps[state.host_timestamp] = true
	_input_queue.sort_custom(func(a: InputState, b: InputState) -> bool:
		return a.host_timestamp < b.host_timestamp)
	const MAX_QUEUE_DEPTH: int = 120  # 0.5s at 240 Hz
	while _input_queue.size() > MAX_QUEUE_DEPTH:
		_input_queue.pop_front()

func _drive_from_input(delta: float) -> void:
	# Pop one input per physics tick so every client input gets simulated on the
	# host in order. last_processed_host_timestamp advances only for inputs that
	# were actually simulated — the client's reconcile filter drops confirmed inputs
	# from its replay history based on this value.
	# During locked phases drain the queue (advancing the ack) but don't apply
	# movement — stale input would contaminate server state and cause a velocity
	# burst when the phase lifts.
	if _input_queue.size() > 0:
		var input: InputState = _input_queue.pop_front()
		last_processed_host_timestamp = input.host_timestamp
		if not _game_state.is_movement_locked():
			_process_input(input, delta)
		else:
			skater.velocity = Vector3.ZERO
		# Clear just_pressed flags before saving as fallback so they don't
		# re-fire on subsequent ticks while the queue is empty.
		input.shoot_pressed = false
		input.slap_pressed = false
		input.elevation_up = false
		input.elevation_down = false
		_fallback_input = input
	else:
		if _game_state.is_movement_locked():
			skater.velocity = Vector3.ZERO
			return
		_process_input(_fallback_input, delta)

func apply_network_state(state: SkaterNetworkState) -> void:
	if _is_host:
		return
	if not _state_buffer.is_empty() and _current_time <= _state_buffer.back().timestamp:
		return
	var buffered := BufferedSkaterState.new()
	buffered.timestamp = _current_time
	buffered.state = state
	_state_buffer.append(buffered)
	if _state_buffer.size() > 30:
		_state_buffer.pop_front()
	_adapt_interpolation_delay()

func _interpolate() -> void:
	var render_time: float = _current_time - interpolation_delay
	var bracket: BufferedStateInterpolator.BracketResult = BufferedStateInterpolator.find_bracket(
			_state_buffer, render_time)
	var prev_extrapolating: bool = is_extrapolating
	is_extrapolating = bracket != null and bracket.is_extrapolating
	if bracket == null:
		return
	var interpolated := SkaterNetworkState.new()
	if bracket.is_extrapolating:
		var dt: float = minf(bracket.extrapolation_dt, extrapolation_max_ms / 1000.0)
		var newest: SkaterNetworkState = bracket.to_state
		interpolated.position = newest.position + newest.velocity * dt
		interpolated.velocity = newest.velocity
		interpolated.blade_position = newest.blade_position + newest.velocity * dt
		interpolated.top_hand_position = newest.top_hand_position + newest.velocity * dt
		interpolated.upper_body_rotation_y = newest.upper_body_rotation_y
		interpolated.facing = newest.facing
		interpolated.is_ghost = newest.is_ghost
	else:
		var from_state: SkaterNetworkState = bracket.from_state
		var to_state: SkaterNetworkState = bracket.to_state
		var t: float = bracket.t
		var dt: float = bracket.bracket_dt
		interpolated.position = BufferedStateInterpolator.hermite(from_state.position, from_state.velocity,
				to_state.position, to_state.velocity, t, dt)
		interpolated.velocity = from_state.velocity.lerp(to_state.velocity, t)
		interpolated.blade_position = from_state.blade_position.lerp(to_state.blade_position, t)
		interpolated.top_hand_position = from_state.top_hand_position.lerp(to_state.top_hand_position, t)
		interpolated.upper_body_rotation_y = lerpf(from_state.upper_body_rotation_y, to_state.upper_body_rotation_y, t)
		interpolated.facing = from_state.facing.lerp(to_state.facing, t).normalized()
		# Boolean fields can't be lerped; take the freshest value so ghost-mode
		# toggles flow through to remote skaters without a one-broadcast delay.
		interpolated.is_ghost = to_state.is_ghost
		# Push position forward from render_time to present using the interpolated
		# velocity. Capped at extrapolation_max_ms so a large interpolation buffer
		# on a rough connection doesn't over-predict on direction changes.
		var forward_dt: float = minf(interpolation_delay, extrapolation_max_ms / 1000.0)
		interpolated.position += interpolated.velocity * forward_dt
		interpolated.blade_position += interpolated.velocity * forward_dt
		interpolated.top_hand_position += interpolated.velocity * forward_dt
	if prev_extrapolating and not is_extrapolating and skater != null:
		_rejoin_blend_from_pos = skater.global_position
		_rejoin_blend_from_blade = skater.get_blade_position()
		_rejoin_blend_from_hand = skater.top_hand.position
		_rejoin_blend_start_time = _current_time
	if _rejoin_blend_start_time >= 0.0:
		var ease_t: float = clampf(
				(_current_time - _rejoin_blend_start_time) / rejoin_blend_duration, 0.0, 1.0)
		interpolated.position = _rejoin_blend_from_pos.lerp(interpolated.position, ease_t)
		interpolated.blade_position = _rejoin_blend_from_blade.lerp(interpolated.blade_position, ease_t)
		interpolated.top_hand_position = _rejoin_blend_from_hand.lerp(interpolated.top_hand_position, ease_t)
		if ease_t >= 1.0:
			_rejoin_blend_start_time = -1.0
	_apply_state_to_skater(interpolated)
	BufferedStateInterpolator.drop_stale(_state_buffer, render_time)

func _adapt_interpolation_delay() -> void:
	var target: float = NetworkManager.get_target_interpolation_delay()
	var change: float = lerpf(interpolation_delay, target, 0.15) - interpolation_delay
	interpolation_delay += clampf(change, -0.001, 0.005)

func _apply_state_to_skater(state: SkaterNetworkState) -> void:
	skater.global_position = state.position
	skater.velocity = state.velocity
	# Facing and upper-body rotation must be set before blade so the shaft mesh
	# orients against the correct body transform, not the previous tick's.
	skater.set_facing(state.facing)
	skater.set_upper_body_rotation(state.upper_body_rotation_y)
	# Top hand before blade so set_blade_position has the correct hand pivot.
	skater.set_top_hand_position(state.top_hand_position)
	skater.set_blade_position(state.blade_position)
	skater.set_ghost(state.is_ghost)
	# Arms are derived from shoulder + hand each frame; update after both are set.
	skater.update_arm_mesh()
	# Bottom hand is purely reactive to top_hand + blade (both already set
	# above) and needs no network state of its own.
	_update_bottom_hand()
	skater.update_bottom_arm_mesh()
