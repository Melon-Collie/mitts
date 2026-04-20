class_name SkaterNetworkState

var position: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var blade_position: Vector3 = Vector3.ZERO
var top_hand_position: Vector3 = Vector3.ZERO
var upper_body_rotation_y: float = 0.0
var facing: Vector2 = Vector2.ZERO
var last_processed_host_timestamp: float = 0.0
var is_ghost: bool = false
var host_timestamp: float = 0.0  # host-only, not serialized

func to_array() -> Array:
	return [
		position,
		velocity,
		blade_position,
		top_hand_position,
		upper_body_rotation_y,
		facing,
		last_processed_host_timestamp,
		is_ghost,
	]

func copy_from(s: SkaterNetworkState) -> void:
	position = s.position
	velocity = s.velocity
	blade_position = s.blade_position
	top_hand_position = s.top_hand_position
	upper_body_rotation_y = s.upper_body_rotation_y
	facing = s.facing
	last_processed_host_timestamp = s.last_processed_host_timestamp
	is_ghost = s.is_ghost
	host_timestamp = s.host_timestamp

static func from_array(data: Array) -> SkaterNetworkState:
	var state := SkaterNetworkState.new()
	state.position = data[0]
	state.velocity = data[1]
	state.blade_position = data[2]
	state.top_hand_position = data[3]
	state.upper_body_rotation_y = data[4]
	state.facing = data[5]
	state.last_processed_host_timestamp = data[6]
	state.is_ghost = data[7]
	return state
