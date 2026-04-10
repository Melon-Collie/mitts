class_name SkaterNetworkState

var position: Vector3 = Vector3.ZERO
var rotation: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var blade_position: Vector3 = Vector3.ZERO
var upper_body_rotation_y: float = 0.0
var facing: Vector2 = Vector2.ZERO
var last_processed_sequence: int = 0

func to_array() -> Array:
	return [
		position,
		rotation,
		velocity,
		blade_position,
		upper_body_rotation_y,
		facing,
		last_processed_sequence	]

static func from_array(data: Array) -> SkaterNetworkState:
	var state = SkaterNetworkState.new()
	state.position = data[0]
	state.rotation = data[1]
	state.velocity = data[2]
	state.blade_position = data[3]
	state.upper_body_rotation_y = data[4]
	state.facing = data[5]
	state.last_processed_sequence = data[6]
	return state
