class_name SkaterNetworkState

var position: Vector3 = Vector3.ZERO
var rotation: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var blade_position: Vector3 = Vector3.ZERO
var top_hand_position: Vector3 = Vector3.ZERO
var upper_body_rotation_y: float = 0.0
var facing: Vector2 = Vector2.ZERO
var last_processed_sequence: int = 0
var is_ghost: bool = false

func to_array() -> Array:
	return [
		position,
		rotation,
		velocity,
		blade_position,
		top_hand_position,
		upper_body_rotation_y,
		facing,
		last_processed_sequence,
		is_ghost	]

static func from_array(data: Array) -> SkaterNetworkState:
	var state = SkaterNetworkState.new()
	state.position = data[0]
	state.rotation = data[1]
	state.velocity = data[2]
	state.blade_position = data[3]
	state.top_hand_position = data[4]
	state.upper_body_rotation_y = data[5]
	state.facing = data[6]
	state.last_processed_sequence = data[7]
	state.is_ghost = data[8]
	return state
