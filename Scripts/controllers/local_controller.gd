class_name LocalController
extends SkaterController

@export var reconcile_position_threshold: float = 0.05
@export var reconcile_velocity_threshold: float = 0.4
@export var correction_frames: float = 48.0

@onready var camera: GameCamera = null
var _gatherer: LocalInputGatherer = null
var _current_input: InputState = InputState.new()
var _input_history: Array[InputState] = []
var _correction_offset: Vector3 = Vector3.ZERO
var _correction_step: Vector3 = Vector3.ZERO
var _team_id: int = -1  # set at setup; needed for client-side offside prediction
var last_reconcile_error: float = 0.0

func setup(assigned_skater: Skater, assigned_puck: Puck, game_state: Node) -> void:
	camera = $Camera3D
	super.setup(assigned_skater, assigned_puck, game_state)
	_gatherer = LocalInputGatherer.new(camera)
	add_child(_gatherer)
	camera.skater = assigned_skater
	camera.puck = assigned_puck
	camera.local_controller = self

# Called after setup() to provide the local player's team — needed for
# client-side offside prediction. Separate from setup() because GDScript
# requires overrides to match the parent signature exactly.
func set_local_team_id(team_id: int) -> void:
	_team_id = team_id

func set_goal_context(goal_0: HockeyGoal, goal_1: HockeyGoal, carrier_team_resolver: Callable) -> void:
	camera.set_goal_context(goal_0, goal_1, carrier_team_resolver)

func get_current_input() -> InputState:
	return _current_input

func teleport_to(pos: Vector3) -> void:
	super.teleport_to(pos)
	_input_history.clear()
	_correction_offset = Vector3.ZERO
	_correction_step = Vector3.ZERO

func _physics_process(delta: float) -> void:
	if skater == null or puck == null or _gatherer == null:
		return
	if _game_state.is_movement_locked():
		# Dead-puck phase: kill velocity and drain history every frame so that
		# move_and_slide() can't drift the skater, and reconcile can't replay stale
		# inputs when the phase lifts — regardless of packet timing.
		skater.velocity = Vector3.ZERO
		_input_history.clear()
		_correction_offset = Vector3.ZERO
		_correction_step = Vector3.ZERO
		return
	if _game_state.is_input_blocked():
		return
	# Predict offsides locally for instant ghost feedback
	_predict_offside()
	if not _correction_offset.is_zero_approx():
		if _correction_step.length() >= _correction_offset.length():
			skater.global_position -= _correction_offset
			_correction_offset = Vector3.ZERO
			_correction_step = Vector3.ZERO
		else:
			skater.global_position -= _correction_step
			_correction_offset -= _correction_step
	_current_input = _gatherer.gather()
	_current_input.delta = delta
	_input_history.append(_current_input)
	# Cap history size to prevent unbounded growth
	if _input_history.size() > 480:  # 2 seconds at 240Hz
		_input_history.pop_front()
	_process_input(_current_input, delta)

func reconcile(server_state: SkaterNetworkState) -> void:
	# Always apply authoritative ghost state from server (covers icing + offsides)
	skater.set_ghost(server_state.is_ghost)
	if _game_state.is_movement_locked():
		# Dead-puck phase: don't reconcile. on_faceoff_positions is the reliable
		# source of truth for teleport positions; world-state snapshots may lag behind
		# and would fight it if applied here.
		return
	_input_history = _input_history.filter(
		func(i: InputState) -> bool: return i.host_timestamp > server_state.last_processed_host_timestamp
	)
	if not ReconciliationRules.skater_needs_reconcile(
			skater.global_position, skater.velocity,
			server_state.position, server_state.velocity,
			reconcile_position_threshold, reconcile_velocity_threshold):
		return
	var pre_snap: Vector3 = skater.global_position
	skater.global_position = server_state.position
	skater.velocity = server_state.velocity
	skater.set_facing(server_state.facing)
	_facing = server_state.facing
	_upper_body_angle = server_state.upper_body_rotation_y
	_lower_body_lag = 0.0
	skater.set_upper_body_rotation(_upper_body_angle)
	skater.set_lower_body_lag(0.0)
	for input in _input_history:
		_process_input(input, input.delta)
	var new_error: Vector3 = pre_snap - skater.global_position
	last_reconcile_error = new_error.length()
	if not new_error.is_zero_approx():
		_correction_offset += new_error
		_correction_step = _correction_offset / correction_frames
		skater.global_position += new_error

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
