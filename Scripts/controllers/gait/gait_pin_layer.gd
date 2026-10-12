class_name GaitPinLayer
extends GaitLayer

# Both sides of a board pin, off the replicated pin_role: the pair sit low and
# set their feet, and lean their trunks into the boards they are locked against —
# the pinned skater pressed into the glass, the pinner driving a shoulder in
# behind him. The facing is the player's own (the gait never turns the body), so
# the lean is laid along the wall's normal in body space, the same directional
# decomposition the check's drive uses.

var _blend: float = 0.0
var _role: int = BoardPinRules.Role.NONE


func stages() -> int:
	return Stage.HOLD | Stage.FLOOR | Stage.TRUNK


func reset() -> void:
	_blend = 0.0
	_role = BoardPinRules.Role.NONE


func is_quiet() -> bool:
	return _skater.pin_role == BoardPinRules.Role.NONE


func advance(delta: float) -> bool:
	if _skater.pin_role != BoardPinRules.Role.NONE:
		_role = _skater.pin_role
	_blend = move_toward(_blend, 0.0 if is_quiet() else 1.0, _controller.pin_pose_speed * delta)
	return _blend > 0.001


# A locked body has its feet set; what moves it along the wall is the lock.
func stride_hold() -> float:
	return _blend


func stance_floor() -> float:
	return _controller.pin_stance * _blend


func shape_trunk(p: GaitPose) -> void:
	var out: Vector2 = BoardPinRules.locked_wall_normal(_skater.global_position,
			_skater.collision_radius(), _role)
	if out == Vector2.ZERO:
		return
	var lean_deg: float = _controller.pin_drive_lean_deg if _role == BoardPinRules.Role.PINNER \
			else _controller.pin_pressed_lean_deg
	var local: Vector3 = _skater.global_transform.basis.inverse() * Vector3(out.x, 0.0, out.y)
	var mag: float = deg_to_rad(lean_deg) * _blend
	p.trunk_pitch += mag * local.z
	p.trunk_roll += -mag * local.x
