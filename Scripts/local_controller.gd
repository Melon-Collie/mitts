class_name LocalController
extends SkaterController

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

func _physics_process(delta: float) -> void:
	if skater == null or puck == null or _gatherer == null:
		return
	_current_input = _gatherer.gather()
	_input_history.append(_current_input)
	# Cap history size to prevent unbounded growth
	if _input_history.size() > 120:  # 2 seconds at 60Hz
		_input_history.pop_front()
	_process_input(_current_input, delta)
	
func reconcile(server_state: SkaterNetworkState) -> void:
	# Discard confirmed inputs
	_input_history = _input_history.filter(
		func(i: InputState): return i.sequence > server_state.last_processed_sequence
	)
	# Reset to server state
	skater.global_position = server_state.position
	skater.velocity = server_state.velocity
	skater.set_facing(server_state.facing)
	# Replay unconfirmed inputs
	for input in _input_history:
		_process_input(input, input.delta)
