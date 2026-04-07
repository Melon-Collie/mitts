class_name LocalInputGatherer
extends Node

var _camera: Camera3D

func _init(camera: Camera3D) -> void:
	_camera = camera

func gather() -> InputState:
	var state = InputState.new()
	
	state.move_vector = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	state.shoot_held = Input.is_action_pressed("shoot")
	state.shoot_pressed = Input.is_action_just_pressed("shoot")
	state.reset = Input.is_action_just_pressed("reset")
	state.self_pass = Input.is_action_just_pressed("self_pass")
	state.self_shot = Input.is_action_just_pressed("self_shot")
	state.shot_cancel = Input.is_action_pressed("shot_cancel")
	state.brake = Input.is_action_pressed("brake")
	state.slap_held = Input.is_action_pressed("slapshot")
	state.slap_pressed = Input.is_action_just_pressed("slapshot")
	state.facing_pressed = Input.is_action_just_pressed("facing")
	state.facing_held = Input.is_action_pressed("facing")
	state.elevation_down = Input.is_action_pressed("elevation_down")
	state.elevation_up = Input.is_action_pressed("elevation_up")
	state.mouse_world_pos = _get_mouse_world_pos(_camera)
	return state


# In LocalInputGatherer or wherever you want to compute it:
func _get_mouse_world_pos(camera: Camera3D) -> Vector3:
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var ray_origin: Vector3 = camera.project_ray_origin(mouse_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(mouse_pos)
	var t: float = -ray_origin.y / ray_dir.y
	return ray_origin + ray_dir * t
