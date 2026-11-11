class_name GaitCarryLayer
extends GaitLayer

# The chest over the stick (CarryPostureRules): folded on the trunk TEXTURE,
# never the frame the blade hangs from, by the fold the carry is drawn at
# (SkaterController.drawn_chest_fold), which follows the blade as the hand
# solve's own does, eased on a spring: the drawn hands hang from the shoulders
# as drawn (SkaterIKCoordinator._hold_offset), so they come with it. Standing,
# he sits under it for as long as he carries, wherever the blade is: the fold
# comes off a puck pulled in tight or round beside him and the knees stay bent.
# Skating, the stride sits him down itself, and a floor across the middle of
# its sit would clip every stroke's bottom: the crouch is gone by
# CROUCH_GONE_SPEED. The layer is quiet while what it last drew is still the
# pose, so a skater settled with his stick out holds the pose that has it.

# m/s: from a standstill to a slow glide, where the stride's own sit takes over.
const CROUCH_FULL_SPEED: float = 0.5
const CROUCH_GONE_SPEED: float = 2.5
# The fold's spring (rad/s): a trunk settling over the stick in about half a
# second, as a body's weight comes forward, not at the legs' pace.
const FOLD_OMEGA: float = 8.0

var _fold: float = 0.0
var _fold_rate: float = 0.0
var _sit: float = 0.0
var _sit_rate: float = 0.0


func stages() -> int:
	return Stage.FLOOR | Stage.TRUNK


func reset() -> void:
	_fold = 0.0
	_fold_rate = 0.0
	_sit = 0.0
	_sit_rate = 0.0


func is_quiet() -> bool:
	return absf(_controller.drawn_chest_fold() - _fold) < 0.0005 \
			and absf((1.0 if _controller.carrying() else 0.0) - _sit) < 0.001


func advance(delta: float) -> bool:
	var omega: float = _controller.locomotion_blend_speed * EaseRules.OMEGA_PER_RATE
	var fold_to: float = _controller.drawn_chest_fold()
	var fold: float = _fold
	_fold = maxf(EaseRules.critical_x(fold, _fold_rate, fold_to, FOLD_OMEGA, delta), 0.0)
	_fold_rate = EaseRules.critical_v(fold, _fold_rate, fold_to, FOLD_OMEGA, delta)
	var target: float = 1.0 if _controller.carrying() else 0.0
	var x: float = _sit
	_sit = clampf(EaseRules.critical_x(x, _sit_rate, target, omega, delta), 0.0, 1.0)
	_sit_rate = EaseRules.critical_v(x, _sit_rate, target, omega, delta)
	return _fold > 0.001 or _sit > 0.001


func stance_floor() -> float:
	var speed: float = Vector2(_skater.velocity.x, _skater.velocity.z).length()
	return _controller.carry_crouch * _sit \
			* (1.0 - smoothstep(CROUCH_FULL_SPEED, CROUCH_GONE_SPEED, speed))


func shape_trunk(p: GaitPose) -> void:
	p.trunk_pitch -= _fold
