class_name GoalieNetworkState

var position_x: float = 0.0
var position_z: float = 0.0
var rotation_y: float = 0.0
var state_enum: int = 0
var five_hole_openness: float = 0.0

func to_array() -> Array:
	return [position_x, position_z, rotation_y, state_enum, five_hole_openness]

static func from_array(data: Array) -> GoalieNetworkState:
	var s := GoalieNetworkState.new()
	s.position_x = data[0]
	s.position_z = data[1]
	s.rotation_y = data[2]
	s.state_enum = data[3]
	s.five_hole_openness = data[4]
	return s
