class_name LocalController
extends SkaterController

@export var reconcile_position_threshold: float = 0.05
@export var reconcile_velocity_threshold: float = 0.4

@onready var camera: GameCamera = null
var _gatherer: LocalInputGatherer = null
var _current_input: InputState = InputState.new()
var _input_history: Array[InputState] = []
var _team_id: int = -1  # set at setup; needed for client-side offside prediction
var last_reconcile_error: float = 0.0
var _claim_cooldown: float = 0.0
var _last_blade_pos: Vector3 = Vector3.ZERO
var _body_check_impulse: Vector3 = Vector3.ZERO
var _body_check_impulse_timestamp: float = 0.0
const _BLADE_JUMP_THRESHOLD: float = 0.05

const _RECONCILE_VISUAL_ALPHA: float = 0.12  # exponential decay per physics frame

func setup(assigned_skater: Skater, assigned_puck: Puck, game_state: Node) -> void:
	camera = $Camera3D
	super.setup(assigned_skater, assigned_puck, game_state)
	_gatherer = LocalInputGatherer.new(camera)
	add_child(_gatherer)
	camera.skater = assigned_skater
	camera.puck = assigned_puck
	camera.local_controller = self
	skater.body_checked_player.connect(
		func(_v: Skater, _f: float, _d: Vector3) -> void:
			_body_check_impulse = -_d * (_f / skater.weight) * skater.body_check_restitution
			_body_check_impulse_timestamp = _current_input.host_timestamp)

# Called after setup() to provide the local player's team — needed for
# client-side offside prediction. Separate from setup() because GDScript
# requires overrides to match the parent signature exactly.
func set_local_team_id(team_id: int) -> void:
	_team_id = team_id

func set_goal_context(goal_0: HockeyGoal, goal_1: HockeyGoal, carrier_team_getter: Callable) -> void:
	camera.set_goal_context(goal_0, goal_1, carrier_team_getter)

func get_current_input() -> InputState:
	return _current_input

func get_input_batch(frames: int = 12) -> Array[InputState]:
	var start: int = maxi(_input_history.size() - frames, 0)
	return _input_history.slice(start)

func teleport_to(pos: Vector3) -> void:
	super.teleport_to(pos)
	_input_history.clear()
	_last_blade_pos = Vector3.ZERO
	_body_check_impulse = Vector3.ZERO
	_body_check_impulse_timestamp = 0.0
	if skater != null:
		skater.visual_offset = Vector3.ZERO

func _physics_process(delta: float) -> void:
	if skater == null or puck == null or _gatherer == null:
		return
	if not skater.visual_offset.is_zero_approx():
		var new_offset: Vector3 = skater.visual_offset * (1.0 - _RECONCILE_VISUAL_ALPHA)
		skater.visual_offset = new_offset if new_offset.length_squared() > 0.000001 else Vector3.ZERO
	if _game_state.is_movement_locked():
		# Dead-puck phase: kill velocity and drain history every frame so that
		# move_and_slide() can't drift the skater, and reconcile can't replay stale
		# inputs when the phase lifts — regardless of packet timing.
		skater.velocity = Vector3.ZERO
		_input_history.clear()
		return
	if _game_state.is_input_blocked():
		return
	# Predict offsides locally for instant ghost feedback
	_predict_offside()
	_current_input = _gatherer.gather()
	_current_input.delta = delta
	if NetworkManager.is_clock_ready():
		_current_input.host_timestamp = NetworkManager.estimated_host_time()
	_input_history.append(_current_input)
	# Cap history size to prevent unbounded growth
	if _input_history.size() > 480:  # 2 seconds at 240Hz
		_input_history.pop_front()
	_process_input(_current_input, delta)
	var blade_pos: Vector3 = skater.get_blade_contact_global()
	if not _last_blade_pos.is_zero_approx():
		var blade_delta: float = blade_pos.distance_to(_last_blade_pos)
		if blade_delta > _BLADE_JUMP_THRESHOLD:
			NetworkTelemetry.record_blade_jump(blade_delta)
	_last_blade_pos = blade_pos
	_claim_cooldown = maxf(_claim_cooldown - delta, 0.0)
	if not _is_host and _claim_cooldown <= 0.0 and NetworkManager.is_clock_ready():
		if puck.carrier == null and not puck.pickup_locked and not skater.is_ghost:
			var dist: float = puck.global_position.distance_to(skater.get_blade_contact_global())
			if dist <= PuckController.PICKUP_RADIUS:
				_claim_cooldown = 0.3
				NetworkManager.send_pickup_claim(
					NetworkManager.estimated_host_time(),
					NetworkManager.get_latest_rtt_ms(),
					NetworkManager.get_target_interpolation_delay() * 1000.0)

func reconcile(server_state: SkaterNetworkState) -> void:
	var pre_reconcile_blade: Vector3 = skater.get_blade_contact_global()
	var pre_reconcile_visual_pos: Vector3 = skater.global_position + skater.visual_offset
	# Apply authoritative ghost state. Server ghost=true always wins. Server
	# ghost=false is held back if the client is still locally predicting offside —
	# the broadcast was encoded before the host computed the transition and is stale.
	if server_state.is_ghost:
		skater.set_ghost(true)
	elif skater.is_ghost:
		var is_carrier: bool = puck != null and puck.carrier == skater
		var puck_z: float = puck.global_position.z if puck != null else 0.0
		if not InfractionRules.is_offside(skater.global_position.z, _team_id, puck_z, is_carrier):
			skater.set_ghost(false)
	if _game_state.is_movement_locked():
		# Dead-puck phase: don't reconcile. on_faceoff_positions is the reliable
		# source of truth for teleport positions; world-state snapshots may lag behind
		# and would fight it if applied here.
		return
	_input_history = _input_history.filter(
		func(i: InputState) -> bool: return i.host_timestamp > server_state.last_processed_host_timestamp
	)
	# Clear captured body check impulse once the server has processed past it.
	if _body_check_impulse_timestamp > 0.0 and server_state.last_processed_host_timestamp >= _body_check_impulse_timestamp:
		_body_check_impulse = Vector3.ZERO
		_body_check_impulse_timestamp = 0.0
	if not ReconciliationRules.skater_needs_reconcile(
			skater.global_position, skater.velocity,
			server_state.position, server_state.velocity,
			reconcile_position_threshold, reconcile_velocity_threshold):
		return
	# Suppress reconcile jitter while pressing against the boards. Wall contact
	# causes move_and_slide vs. server-physics noise (~3-5 cm each tick) that
	# repeatedly sets small visual_offsets which compound into visible oscillation.
	# Errors above 10 cm are real desync and still fire through.
	if skater.is_on_wall() and skater.global_position.distance_to(server_state.position) < 0.1:
		return
	# Save shot/state-machine state — replay can transition through shoot states
	# (WRISTER_AIM → FOLLOW_THROUGH → SKATING) and leave _state wrong. Restore so
	# the next _process_input runs the correct handler and blade doesn't teleport.
	var pre_state: State = _state
	var pre_follow_through_timer: float = _follow_through_timer
	var pre_follow_through_is_slapper: bool = _follow_through_is_slapper
	var pre_one_timer_window_timer: float = _one_timer_window_timer
	skater.global_position = server_state.position
	skater.velocity = server_state.velocity
	# Snap facing for replay accuracy — facing drives move_and_slide direction,
	# so the replay must start from the server's facing to reproduce the trajectory.
	_facing = server_state.facing
	skater.set_facing(_facing)
	_lower_body_lag = 0.0
	skater.set_lower_body_lag(0.0)
	# Seed mouse pos from the first replayed input so the first frame's
	# direction-variance delta is zero rather than a large garbage value.
	if not _input_history.is_empty():
		_prev_mouse_screen_pos = _input_history[0].mouse_screen_pos
	is_replaying = true
	var _impulse_applied: bool = false
	for input in _input_history:
		_process_input(input, input.delta)
		if not _impulse_applied and _body_check_impulse_timestamp > 0.0 and input.host_timestamp >= _body_check_impulse_timestamp:
			skater.velocity += _body_check_impulse
			_impulse_applied = true
		skater.global_position += skater.velocity * input.delta
		var unclamped_xz := Vector2(skater.global_position.x, skater.global_position.z)
		var clamped_xz := GameRules.clamp_to_rink_inner(unclamped_xz)
		if unclamped_xz.distance_squared_to(clamped_xz) > 1e-6:
			var push := clamped_xz - unclamped_xz
			var n := push.normalized()
			var vel_xz := Vector2(skater.velocity.x, skater.velocity.z)
			var into_wall: float = vel_xz.dot(n)
			if into_wall < 0.0:
				vel_xz -= into_wall * n  # slide along wall, remove inward component
				skater.velocity.x = vel_xz.x
				skater.velocity.z = vel_xz.y
			skater.global_position.x = clamped_xz.x
			skater.global_position.z = clamped_xz.y
	is_replaying = false
	# Restore shot-state fields that replay must not transition past.
	_state = pre_state
	_follow_through_timer = pre_follow_through_timer
	_follow_through_is_slapper = pre_follow_through_is_slapper
	_one_timer_window_timer = pre_one_timer_window_timer
	# Set mouse pos baseline to the end of the replay window so the next real
	# frame's direction-variance delta is correct.
	if not _input_history.is_empty():
		_prev_mouse_screen_pos = _input_history.back().mouse_screen_pos
	# Server authority on shot state: if the server disagrees with the client's
	# pre-replay state, server wins — this corrects charge that was wrong before
	# the reconcile (e.g. from a dropped shoot_pressed input).
	if server_state.shot_state != pre_state:
		_state = server_state.shot_state as State
		_charge_distance = server_state.shot_charge
	skater.set_facing(_facing)
	skater.set_upper_body_rotation(_upper_body_angle)
	skater.set_lower_body_lag(_lower_body_lag)
	last_reconcile_error = (skater.global_position - server_state.position).length()
	# Blade must be re-applied after position is set — upper_body_to_local()
	# uses skater.global_position, so it must reflect the final replayed position.
	_apply_blade_from_mouse(_current_input, 0.0)
	var blade_reconcile_delta: float = skater.get_blade_contact_global().distance_to(pre_reconcile_blade)
	NetworkTelemetry.record_blade_reconcile(blade_reconcile_delta)
	if blade_reconcile_delta > _BLADE_JUMP_THRESHOLD:
		NetworkTelemetry.record_blade_jump(blade_reconcile_delta)
	skater.visual_offset = pre_reconcile_visual_pos - skater.global_position

func on_puck_picked_up_network() -> void:
	super.on_puck_picked_up_network()
	_claim_cooldown = 0.0


func _predict_offside() -> void:
	if _is_host:
		return  # Host computes authoritatively in GameManager
	var is_carrier: bool = puck.carrier == skater
	var offside: bool = InfractionRules.is_offside(
		skater.global_position.z, _team_id, puck.global_position.z, is_carrier)
	# Only predict offside → ghost. Icing ghost comes from server via reconcile.
	if offside and not skater.is_ghost:
		skater.set_ghost(true)
	# If not offside but ghost is set, we don't clear here — could be icing.
	# Server reconcile corrects within one broadcast cycle.
