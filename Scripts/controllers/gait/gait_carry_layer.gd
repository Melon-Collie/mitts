class_name GaitCarryLayer
extends GaitLayer

# The chest over the stick (CarryPostureRules): folded on the trunk TEXTURE,
# never the frame the blade hangs from, by exactly the fold the hand solve
# measures the shoulders at (SkaterController.chest_fold) — eased behind it, the
# drawn shoulders lag the solved hands and the bottom one lets go of the shaft —
# and, standing, the knees bent under it, so he sits into the fold rather than
# bending over straight legs. Skating, the stride sits him down itself, and a
# floor across the middle of its sit would clip every stroke's bottom: the
# crouch is gone by CROUCH_GONE_SPEED. The derived carry (ArmEnvelope) lays
# its own stance on top: the chest leaned on past the fold and, standing, the
# hips sunk past the crouch, as the pose that holds the blade there has them.
# The layer is quiet while the fold and the stance it last drew are still
# theirs, so a skater settled with his stick out holds the pose that has it.

# m/s: from a standstill to a slow glide, where the stride's own sit takes over.
const CROUCH_FULL_SPEED: float = 0.5
const CROUCH_GONE_SPEED: float = 2.5

var _fold: float = 0.0
var _lean := Vector2.ZERO


func stages() -> int:
	return Stage.FLOOR | Stage.TRUNK


func reset() -> void:
	_fold = 0.0
	_lean = Vector2.ZERO


func is_quiet() -> bool:
	return absf(_controller.chest_fold() - _fold) < 0.0005 \
			and _controller.carry_lean().distance_to(_lean) < 0.0005


func advance(_delta: float) -> bool:
	_fold = _controller.chest_fold()
	_lean = _controller.carry_lean()
	return _fold > 0.001 or _lean != Vector2.ZERO


func stance_floor() -> float:
	if _controller.carry_fold_deg <= 0.0:
		return 0.0
	var speed: float = Vector2(_skater.velocity.x, _skater.velocity.z).length()
	return _controller.carry_crouch_floor(_controller.carry_crouch * _fold
			/ deg_to_rad(_controller.carry_fold_deg)) \
			* (1.0 - smoothstep(CROUCH_FULL_SPEED, CROUCH_GONE_SPEED, speed))


func shape_trunk(p: GaitPose) -> void:
	p.trunk_pitch -= _fold + _lean.x
	p.trunk_roll -= _lean.y
