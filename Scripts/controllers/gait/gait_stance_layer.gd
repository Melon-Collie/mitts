class_name GaitStanceLayer
extends GaitLayer

# The loaded stance (Shift): low hips, a wide base, the chest over the knees.
# From the top-down game camera knee bend barely registers, so the base WIDTH is
# what carries the read — an opponent has to see the stance to stay square to
# it. Eased from the replicated stance_active, so a wire-fed remote poses the
# same as a locally simulated skater. The stance's turning legs (the tight state)
# and its choppy stride are the locomotion's; this layer is the posture over
# them.

var _blend: float = 0.0


func stages() -> int:
	return Stage.FLOOR | Stage.LEGS | Stage.TRUNK


func reset() -> void:
	_blend = 0.0


func is_quiet() -> bool:
	return not _controller.stance_active


func advance(delta: float) -> bool:
	_blend = lerpf(_blend, 1.0 if _controller.stance_active else 0.0,
			_controller.locomotion_blend_speed * delta)
	return _blend > 0.001


func stance_floor() -> float:
	return _controller.stance_crouch * _blend


# Both legs splay into the wide base. The splay rotates the whole leg chain, so
# its vertical span is span·cos(splay) and the body pays the deficit as extra
# drop, or the skates ride up off the ice.
func shape_legs(p: GaitPose) -> void:
	if _blend <= 0.001:
		return
	var splay: float = deg_to_rad(_controller.stance_width_deg) * _blend
	p.l_roll -= splay
	p.r_roll += splay
	p.drop += (p.leg_length() - p.drop) * (1.0 - cos(splay))


# The chest folds over the knees on the trunk TEXTURE, not the torso lean: the
# lean rotates the UpperBody node the blade markers hang from, and the stance
# must not move the blade.
func shape_trunk(p: GaitPose) -> void:
	if _blend > 0.001:
		p.trunk_pitch += -deg_to_rad(_controller.stance_chest_deg) * _blend
