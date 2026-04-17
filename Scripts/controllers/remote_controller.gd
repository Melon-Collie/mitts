class_name RemoteController
extends SkaterController

@export var interpolation_delay: float = Constants.NETWORK_INTERPOLATION_DELAY

var _latest_input: InputState = InputState.new()
var _state_buffer: Array[BufferedSkaterState] = []
var _current_time: float = 0.0

func _physics_process(delta: float) -> void:
	if skater == null:
		return
	if _is_host:
		_drive_from_input(delta)
	else:
		_current_time += delta
		_interpolate()
		skater.update_stick_mesh()

func receive_input(state: InputState) -> void:
	_latest_input = state

func _drive_from_input(delta: float) -> void:
	# Always advance sequence so the client's reconcile filter stays current,
	# but don't process movement during dead-puck phases — stale input would
	# contaminate server state and cause a velocity burst when the phase lifts.
	# Writes SkaterController.last_processed_sequence (the field serialized into
	# SkaterNetworkState); the client's LocalController.reconcile reads it to
	# drop confirmed inputs from its replay history.
	last_processed_sequence = _latest_input.sequence
	if _game_state.is_movement_locked():
		skater.velocity = Vector3.ZERO
		return
	_process_input(_latest_input, delta)

func apply_network_state(state: SkaterNetworkState) -> void:
	if _is_host:
		return
	var buffered := BufferedSkaterState.new()
	buffered.timestamp = _current_time
	buffered.state = state
	_state_buffer.append(buffered)
	if _state_buffer.size() > 10:
		_state_buffer.pop_front()

func _interpolate() -> void:
	var render_time: float = _current_time - interpolation_delay
	var bracket: BufferedStateInterpolator.BracketResult = BufferedStateInterpolator.find_bracket(
			_state_buffer, render_time)
	if bracket == null:
		return
	var from_state: SkaterNetworkState = bracket.from_state
	var to_state: SkaterNetworkState = bracket.to_state
	var t: float = bracket.t
	var interpolated := SkaterNetworkState.new()
	interpolated.position = from_state.position.lerp(to_state.position, t)
	interpolated.rotation = from_state.rotation.lerp(to_state.rotation, t)
	interpolated.velocity = from_state.velocity.lerp(to_state.velocity, t)
	interpolated.blade_position = from_state.blade_position.lerp(to_state.blade_position, t)
	interpolated.top_hand_position = from_state.top_hand_position.lerp(to_state.top_hand_position, t)
	interpolated.upper_body_rotation_y = lerpf(from_state.upper_body_rotation_y, to_state.upper_body_rotation_y, t)
	interpolated.facing = from_state.facing.lerp(to_state.facing, t).normalized()
	# Boolean fields can't be lerped; take the freshest value so ghost-mode
	# toggles flow through to remote skaters without a one-broadcast delay.
	interpolated.is_ghost = to_state.is_ghost
	_apply_state_to_skater(interpolated)
	BufferedStateInterpolator.drop_stale(_state_buffer, render_time)

func _apply_state_to_skater(state: SkaterNetworkState) -> void:
	skater.global_position = state.position
	skater.global_rotation = state.rotation
	skater.velocity = state.velocity
	# Set top_hand first so set_blade_position can compute the shaft rotation
	# using the correct hand pivot.
	skater.set_top_hand_position(state.top_hand_position)
	skater.set_blade_position(state.blade_position)
	skater.set_upper_body_rotation(state.upper_body_rotation_y)
	skater.set_facing(state.facing)
	skater.set_ghost(state.is_ghost)
	# Arms are derived from shoulder + hand each frame; update after both are set.
	skater.update_arm_mesh()
	# Bottom hand is purely reactive to top_hand + blade (both already set
	# above) and needs no network state of its own.
	_update_bottom_hand()
	skater.update_bottom_arm_mesh()
