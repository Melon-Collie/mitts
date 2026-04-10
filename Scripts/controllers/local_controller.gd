class_name LocalController
extends SkaterController

@export var reconcile_position_threshold: float = 0.05
@export var reconcile_velocity_threshold: float = 0.1

@onready var camera: GameCamera = null
var _gatherer: LocalInputGatherer = null
var _current_input: InputState = InputState.new()
var _input_history: Array[InputState] = []

func setup(assigned_skater: Skater, assigned_puck: Puck) -> void:
	camera = $Camera3D
	super.setup(assigned_skater, assigned_puck)
	_gatherer = LocalInputGatherer.new(camera)
	add_child(_gatherer)
	camera.skater = assigned_skater
	camera.puck = assigned_puck
	camera.local_controller = self

func get_current_input() -> InputState:
	return _current_input

func teleport_to(pos: Vector3) -> void:
	super.teleport_to(pos)
	_input_history.clear()

func _physics_process(delta: float) -> void:
	if skater == null or puck == null or _gatherer == null:
		return
	if GameManager.movement_locked():
		# Dead-puck phase: kill velocity and drain history every frame so that
		# move_and_slide() can't drift the skater, and reconcile can't replay stale
		# inputs when the phase lifts — regardless of packet timing.
		skater.velocity = Vector3.ZERO
		_input_history.clear()
		return
	# Predict offsides locally for instant ghost feedback
	_predict_offside()
	_current_input = _gatherer.gather()
	_input_history.append(_current_input)
	# Cap history size to prevent unbounded growth
	if _input_history.size() > 120:  # 2 seconds at 60Hz
		_input_history.pop_front()
	_process_input(_current_input, delta)
	
func reconcile(server_state: SkaterNetworkState) -> void:
	# Always apply authoritative ghost state from server (covers icing + offsides)
	skater.set_ghost(server_state.is_ghost)
	if GameManager.movement_locked():
		# Dead-puck phase: don't reconcile. on_faceoff_positions is the reliable
		# source of truth for teleport positions; world-state snapshots may lag behind
		# and would fight it if applied here.
		return
	_input_history = _input_history.filter(
		func(i: InputState): return i.sequence > server_state.last_processed_sequence
	)
	var position_error := skater.global_position.distance_to(server_state.position)
	var velocity_error := skater.velocity.distance_to(server_state.velocity)
	if position_error < reconcile_position_threshold and velocity_error < reconcile_velocity_threshold:
		return
	skater.global_position = server_state.position
	skater.velocity = server_state.velocity
	skater.set_facing(server_state.facing)
	_facing = server_state.facing
	_upper_body_angle = server_state.upper_body_rotation_y
	skater.set_upper_body_rotation(_upper_body_angle)
	for input in _input_history:
		_process_input(input, input.delta)

func _predict_offside() -> void:
	if NetworkManager.is_host:
		return  # Host computes authoritatively in GameManager
	var record: PlayerRecord = GameManager.get_local_player()
	if record == null:
		return
	var offside: bool = GameManager.check_offside(skater, record.team, puck)
	# Only predict offside→ghost. Icing ghost comes from server via reconcile.
	if offside and not skater.is_ghost:
		skater.set_ghost(true)
	elif not offside and skater.is_ghost:
		# Don't clear ghost if server says ghost (could be icing).
		# Server reconcile will correct within one broadcast cycle.
		pass
