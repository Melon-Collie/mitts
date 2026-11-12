class_name PenaltyBoxCamera
extends Camera3D

# The view from a seat in the penalty box: fixed behind the boards at the
# player's own box, turning to follow the play. Mounted for the local player
# while he serves a penalty (GameManager).

# Eye of a seated man: this far behind the boards' centerline and above the ice.
const _EYE_BEHIND_BOARDS_M: float = 0.6
const _EYE_HEIGHT_M: float = 1.6
const _FOV_DEG: float = 62.0
# How fast the head turns to follow the play (1/s, exponential).
const _LOOK_SPEED: float = 5.0

var _target_getter: Callable = Callable()
var _prev_camera: Camera3D = null
var _active: bool = false
var _look_target: Vector3 = Vector3.ZERO


func setup(team_id: int, target_getter: Callable) -> void:
	_target_getter = target_getter
	fov = _FOV_DEG
	# Posed afresh every rendered frame, so it is already continuous — see
	# GameCamera._ready.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var door: Vector3 = PlayerRules.penalty_box_position(team_id)
	global_position = Vector3(-(GameRules.RINK_HALF_WIDTH + _EYE_BEHIND_BOARDS_M),
			_EYE_HEIGHT_M, signf(door.z) * GameRules.PENALTY_BOX_CENTER_Z)


func activate() -> void:
	if _active:
		return
	_active = true
	_prev_camera = get_viewport().get_camera_3d()
	_look_target = _target()
	_face(_look_target)
	make_current()


func deactivate() -> void:
	_active = false
	_yield_view()


func _process(delta: float) -> void:
	if not _active:
		# A camera that cut in over this one (a replay) hands the view back to
		# whoever held it before, which is this one even after the release.
		_yield_view()
		return
	_look_target = _look_target.lerp(_target(), 1.0 - exp(-_LOOK_SPEED * delta))
	_face(_look_target)


func _yield_view() -> void:
	if current and is_instance_valid(_prev_camera):
		_prev_camera.make_current()


func _target() -> Vector3:
	return _target_getter.call() if _target_getter.is_valid() else Vector3.ZERO


func _face(target: Vector3) -> void:
	if global_position.distance_to(target) > 0.1:
		look_at(target, Vector3.UP)
