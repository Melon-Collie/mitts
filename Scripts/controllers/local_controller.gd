class_name LocalController
extends SkaterController

@export var reconcile_position_threshold: float = 0.05
@export var reconcile_velocity_threshold: float = 0.1

@onready var camera: GameCamera = null
var _gatherer: LocalInputGatherer = null
var _current_input: InputState = InputState.new()
var _input_history: Array[InputState] = []
var _team_id: int = -1  # set at setup; needed for client-side offside prediction

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

func get_current_input() -> InputState:
	return _current_input

func teleport_to(pos: Vector3) -> void:
	super.teleport_to(pos)
	_input_history.clear()

func _physics_process(delta: float) -> void:
	if skater == null or puck == null or _gatherer == null:
		return
	if _game_state.is_movement_locked():
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
	if _game_state.is_movement_locked():
		# Dead-puck phase: don't reconcile. on_faceoff_positions is the reliable
		# source of truth for teleport positions; world-state snapshots may lag behind
		# and would fight it if applied here.
		return
	_input_history = _input_history.filter(
		func(i: InputState): return i.sequence > server_state.last_processed_sequence
	)
	if not ReconciliationRules.skater_needs_reconcile(
			skater.global_position, skater.velocity,
			server_state.position, server_state.velocity,
			reconcile_position_threshold, reconcile_velocity_threshold):
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
