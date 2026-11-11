class_name GaitFightLayer
extends GaitLayer

# A fighter's stance, off the replicated fight role (FightRules.Role.FIGHTING):
# knees bent on a base wider than skating's, the chest a little over them and
# the chin down behind the fists (FightGuardRules). Lower and narrower than the
# loaded stance (Shift), which is a skater's, not a boxer's.

var _blend: float = 0.0


func stages() -> int:
	return Stage.FLOOR | Stage.TRUNK


func reset() -> void:
	_blend = 0.0


func is_quiet() -> bool:
	return _skater.fight_role != FightRules.Role.FIGHTING


func advance(delta: float) -> bool:
	_blend = move_toward(_blend, 0.0 if is_quiet() else 1.0,
			delta / FightGuardRules.EASE_S)
	return _blend > 0.001


func stance_floor() -> float:
	return _controller.fight_stance_crouch * _blend


func stance_width() -> float:
	return _controller.fight_stance_width_m * _blend


func shape_trunk(p: GaitPose) -> void:
	p.trunk_pitch += -deg_to_rad(_controller.fight_chest_deg) * _blend
