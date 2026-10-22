class_name GaitPressLayer
extends GaitLayer

# Both sides of a press (PressRules), off replicated state alone, so a remote
# reads the same pose: touching another body, the one committed and skating into
# him drives — feet set split, the back leg pushing, low, the trunk into him —
# and the one braking digs in — sat deep and wide on the stop's edges, his trunk
# into the push. The lean is laid along the line to the other body in body space,
# the same decomposition the check's drive and the pin use. The facing is the
# player's own.

enum Role { NONE, DRIVE, ANCHOR }

var _blend: float = 0.0
var _blend_rate: float = 0.0
var _role: int = Role.NONE
var _toward: Vector3 = Vector3.ZERO   # world XZ, unit, toward the other body


func stages() -> int:
	return Stage.HOLD | Stage.FLOOR | Stage.LEGS | Stage.TRUNK


func reset() -> void:
	_blend = 0.0
	_blend_rate = 0.0
	_role = Role.NONE
	_toward = Vector3.ZERO


func is_quiet() -> bool:
	return _read_role() == Role.NONE


func advance(delta: float) -> bool:
	var role: int = _read_role()
	if role != Role.NONE:
		_role = role
	var target: float = 0.0 if role == Role.NONE else 1.0
	var omega: float = _controller.press_pose_speed * EaseRules.OMEGA_PER_RATE
	var x: float = _blend
	_blend = clampf(EaseRules.critical_x(x, _blend_rate, target, omega, delta), 0.0, 1.0)
	_blend_rate = EaseRules.critical_v(x, _blend_rate, target, omega, delta)
	return _blend > 0.001


# The role this body plays against the nearest body it touches, and the line to
# him (into _toward).
func _read_role() -> int:
	if _skater.is_knocked_down or _skater.pin_role != BoardPinRules.Role.NONE:
		return Role.NONE
	var driving: bool = _skater.hit_committed and not _skater.brake_intent \
			and _skater.move_intent.length_squared() > 0.01
	var braking: bool = _skater.brake_intent \
			and Vector2(_skater.velocity.x, _skater.velocity.z).length() <= SkaterMovementRules.SHUFFLE_MAX_SPEED
	if not driving and not braking:
		return Role.NONE
	var my_pos: Vector3 = _skater.global_position
	var my_radius: float = _skater.collision_radius()
	var best_gap: float = PressRules.CONTACT_SLACK_M
	var toward := Vector3.ZERO
	for other: Skater in _skater.contact_others():
		if other == null or other == _skater or other.is_ghost:
			continue
		var d: Vector3 = other.global_position - my_pos
		d.y = 0.0
		var dist: float = d.length()
		var gap: float = dist - my_radius - other.collision_radius()
		if gap < best_gap and dist > 0.0001:
			best_gap = gap
			toward = d / dist
	if toward == Vector3.ZERO:
		return Role.NONE
	if driving and _skater.move_intent.normalized().dot(Vector2(toward.x, toward.z)) <= 0.5:
		return Role.NONE
	_toward = toward
	return Role.DRIVE if driving else Role.ANCHOR


# How much of the legs are dug in on the stop's edges against a press, 0..1:
# a stop for the scrape it makes once he is shoved along them.
func dig() -> float:
	return _blend if _role == Role.ANCHOR else 0.0


# The feet are set: what moves the pair is the press.
func stride_hold() -> float:
	return _blend


func stance_floor() -> float:
	var depth: float = _controller.press_drive_stance if _role == Role.DRIVE \
			else _controller.press_anchor_stance
	return depth * _blend


func stance_width() -> float:
	return _controller.press_anchor_width_m * _blend if _role == Role.ANCHOR else 0.0


# The driver's lunge: the stick-side foot back, pushing.
func shape_legs(p: GaitPose) -> void:
	if _role != Role.DRIVE:
		return
	var split: float = deg_to_rad(_controller.press_drive_split_deg) * _blend \
			* (-1.0 if _skater.is_left_handed else 1.0)
	p.l_pitch += split
	p.r_pitch -= split


func shape_trunk(p: GaitPose) -> void:
	if _toward == Vector3.ZERO:
		return
	var lean_deg: float = _controller.press_drive_lean_deg if _role == Role.DRIVE \
			else _controller.press_anchor_lean_deg
	var local: Vector3 = _skater.global_transform.basis.inverse() * _toward
	var mag: float = deg_to_rad(lean_deg) * _blend
	p.trunk_pitch += mag * local.z
	p.trunk_roll += -mag * local.x
