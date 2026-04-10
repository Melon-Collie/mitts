class_name InputState

var sequence: int = 0
var delta: float = 1.0 / 60.0
var move_vector: Vector2 = Vector2.ZERO
var mouse_world_pos: Vector3 = Vector3.ZERO
var shoot_pressed: bool = false
var shoot_held: bool = false
var slap_pressed: bool = false
var slap_held: bool = false
var facing_held: bool = false
var brake: bool = false
var elevation_up: bool = false
var elevation_down: bool = false

func to_array() -> Array:
	return [
		sequence,
		delta,
		move_vector.x,
		move_vector.y,
		mouse_world_pos.x,
		mouse_world_pos.y,
		mouse_world_pos.z,
		shoot_pressed,
		shoot_held,
		slap_pressed,
		slap_held,
		facing_held,
		brake,
		elevation_up,
		elevation_down,
	]

static func from_array(data: Array) -> InputState:
	var state = InputState.new()
	state.sequence = data[0]
	state.delta = data[1]
	state.move_vector = Vector2(data[2], data[3])
	state.mouse_world_pos = Vector3(data[4], data[5], data[6])
	state.shoot_pressed = data[7]
	state.shoot_held = data[8]
	state.slap_pressed = data[9]
	state.slap_held = data[10]
	state.facing_held = data[11]
	state.brake = data[12]
	state.elevation_up = data[13]
	state.elevation_down = data[14]
	return state
