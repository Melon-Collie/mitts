class_name GaitReadyLayer
extends GaitLayer

# A skater with his stick on the ice: the chest folded over the stick on the
# trunk TEXTURE, never the frame the blade hangs from, by the fold the hands
# are held at (SkaterController.ready_fold), which the tick has eased, so it is
# drawn past the trunk's filter and the shoulders stay over the hands; and
# standing, the knees bent under it, deeper with the puck, so he sits into the
# fold rather than bending over straight legs. Skating, the stride sits him
# down itself, and a floor across the middle of its sit would clip every
# stroke's bottom: the crouch is gone by CROUCH_GONE_SPEED. The layer is quiet
# while what it last drew is still the pose, so a skater settled with his
# stick out holds the pose that has it.

# m/s: from a standstill to a slow glide, where the stride's own sit takes over.
const CROUCH_FULL_SPEED: float = 0.5
const CROUCH_GONE_SPEED: float = 2.5

var _fold: float = 0.0
var _sit: float = 0.0
var _sit_rate: float = 0.0


func stages() -> int:
	return Stage.FLOOR | Stage.TRUNK


func reset() -> void:
	_fold = 0.0
	_sit = 0.0
	_sit_rate = 0.0


func is_quiet() -> bool:
	return absf(_controller.ready_fold() - _fold) < 0.0005 \
			and absf(_controller.ready_sit() - _sit) < 0.001


func advance(delta: float) -> bool:
	_fold = _controller.ready_fold()
	var target: float = _controller.ready_sit()
	var omega: float = _controller.locomotion_blend_speed * EaseRules.OMEGA_PER_RATE
	var x: float = _sit
	_sit = maxf(EaseRules.critical_x(x, _sit_rate, target, omega, delta), 0.0)
	_sit_rate = EaseRules.critical_v(x, _sit_rate, target, omega, delta)
	return _fold > 0.001 or _sit > 0.001


func stance_floor() -> float:
	var speed: float = Vector2(_skater.velocity.x, _skater.velocity.z).length()
	return _sit * (1.0 - smoothstep(CROUCH_FULL_SPEED, CROUCH_GONE_SPEED, speed))


func shape_trunk(p: GaitPose) -> void:
	p.eased_pitch -= _fold
