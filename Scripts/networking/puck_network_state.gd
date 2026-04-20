class_name PuckNetworkState

var position: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var carrier_peer_id: int = -1
var host_timestamp: float = 0.0  # host-only, not serialized

func to_array() -> Array:
	return [
		position,
		velocity,
		carrier_peer_id
	]

func copy_from(s: PuckNetworkState) -> void:
	position = s.position
	velocity = s.velocity
	carrier_peer_id = s.carrier_peer_id
	host_timestamp = s.host_timestamp

static func from_array(data: Array) -> PuckNetworkState:
	var state := PuckNetworkState.new()
	state.position = data[0]
	state.velocity = data[1]
	state.carrier_peer_id = data[2]
	return state
