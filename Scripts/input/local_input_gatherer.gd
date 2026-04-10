class_name LocalInputGatherer
extends Node

var _camera: Camera3D
var _pending_shoot_pressed: bool = false
var _pending_slap_pressed: bool = false
var _pending_elevation_up: bool = false
var _pending_elevation_down: bool = false

func _init(camera: Camera3D) -> void:
	_camera = camera

func _process(_delta: float) -> void:
	# Accumulate just_pressed events every frame
	if Input.is_action_just_pressed("shoot"):
		_pending_shoot_pressed = true
	if Input.is_action_just_pressed("slapshot"):
		_pending_slap_pressed = true
	if Input.is_action_just_pressed("elevation_up"):
		_pending_elevation_up = true
	if Input.is_action_just_pressed("elevation_down"):
		_pending_elevation_down = true

func gather() -> InputState:
	var state = InputState.new()
	state.move_vector = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	state.shoot_held = Input.is_action_pressed("shoot")
	state.shoot_pressed = _pending_shoot_pressed
	state.slap_held = Input.is_action_pressed("slapshot")
	state.slap_pressed = _pending_slap_pressed
	state.facing_held = Input.is_action_pressed("facing")
	state.brake = Input.is_action_pressed("brake")
	state.elevation_up = _pending_elevation_up
	state.elevation_down = _pending_elevation_down
	state.mouse_world_pos = _get_mouse_world_pos(_camera)
	# Clear pending flags after gather
	_pending_shoot_pressed = false
	_pending_slap_pressed = false
	_pending_elevation_up = false
	_pending_elevation_down = false
	return state

func _get_mouse_world_pos(camera: Camera3D) -> Vector3:
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var ray_origin: Vector3 = camera.project_ray_origin(mouse_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(mouse_pos)
	var t: float = -ray_origin.y / ray_dir.y
	return ray_origin + ray_dir * t
