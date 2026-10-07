class_name GaitKnockdownLayer
extends GaitLayer

# The knockdown crumple: the body sinks toward the ice and everything the gait
# drives goes limp — the stroke, the mohawk, the edges, the trunk texture and
# the stumble — so a downed body doesn't keep skating while it slides. The torso
# fall itself is SkaterPoseCoordinator._apply_lean's (the recoil channel) and
# the sprawl SkaterController._apply_knockdown_fall's; this is the gait's share.
#
# Derived FROM the replicated knockdown_timer, so it renders identically
# everywhere and through reconcile.

# 0..1: full while more than knockdown_getup_seconds remains on the timer, then
# easing to 0 over that tail (the get-up); the entry is ramped over the buckle
# window (the smoothstep of KnockdownFallRules.entry_ramp) so the crumple
# doesn't land in one frame.
var weight: float = 0.0


func stages() -> int:
	return Stage.OVERRIDE


func reset() -> void:
	weight = 0.0


func is_quiet() -> bool:
	return _controller.knockdown_timer <= 0.0


func advance(_delta: float) -> bool:
	weight = clampf(_controller.knockdown_timer
			/ maxf(_controller.knockdown_getup_seconds, 0.001), 0.0, 1.0)
	if weight > 0.0:
		var buckle: float = clampf(_controller.knockdown_elapsed()
				/ maxf(_controller.knockdown_fall_buckle_seconds, 0.001), 0.0, 1.0)
		weight *= buckle * buckle * (3.0 - 2.0 * buckle)
	return weight > 0.0


func override(p: GaitPose) -> void:
	if weight <= 0.0:
		return
	# A held pose: the brace is posed in a frame that has gone down with the
	# body (GaitPose.frame_share).
	p.frame_share = maxf(p.frame_share, weight)
	p.drop = lerpf(p.drop, _controller.knockdown_pose_drop_m, weight)
	p.l_pitch = lerpf(p.l_pitch, 0.0, weight)
	p.r_pitch = lerpf(p.r_pitch, 0.0, weight)
	p.l_roll = lerpf(p.l_roll, 0.0, weight)
	p.r_roll = lerpf(p.r_roll, 0.0, weight)
	p.l_knee = lerpf(p.l_knee, 0.0, weight)
	p.r_knee = lerpf(p.r_knee, 0.0, weight)
	p.l_yaw = lerpf(p.l_yaw, 0.0, weight)
	p.r_yaw = lerpf(p.r_yaw, 0.0, weight)
	p.edge_l = lerpf(p.edge_l, 0.0, weight)
	p.edge_r = lerpf(p.edge_r, 0.0, weight)
	p.trunk_pitch = lerpf(p.trunk_pitch, 0.0, weight)
	p.trunk_roll = lerpf(p.trunk_roll, 0.0, weight)
	p.wobble_pitch = lerpf(p.wobble_pitch, 0.0, weight)
	p.wobble_roll = lerpf(p.wobble_roll, 0.0, weight)
