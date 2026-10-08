class_name GaitStickLiftLayer
extends GaitLayer

# The working posture while jabbing under an opponent's stick: a light coil and
# a slight chest-up pop. Off the replicated blade_up — the skater's own lift or
# a forced pop, either way the body reacts.

var _blend: float = 0.0


func stages() -> int:
	return Stage.FLOOR | Stage.TRUNK


func reset() -> void:
	_blend = 0.0


func is_quiet() -> bool:
	return not _skater.blade_up


func advance(delta: float) -> bool:
	_blend = lerpf(_blend, 1.0 if _skater.blade_up else 0.0,
			minf(_controller.stick_lift_blend_speed * delta, 1.0))
	return _blend > 0.001


func stance_floor() -> float:
	return _controller.stick_lift_stance * _blend


# Positive pitch tips the shoulders back.
func shape_trunk(p: GaitPose) -> void:
	p.trunk_pitch += deg_to_rad(_controller.stick_lift_trunk_deg) * _blend
