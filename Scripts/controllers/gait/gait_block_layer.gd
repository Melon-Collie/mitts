class_name GaitBlockLayer
extends GaitLayer

# The one-knee shot block. The STICK-SIDE knee sinks toward the ice with the
# shin folded back along it; the far leg extends out to the other side, shin low
# and skate on the ice. Body and stick then seal opposite halves of the lane —
# the blade lies flat on the stick side
# (SkaterShotPoseCoordinator.apply_block_blade_position), the extended pad
# covers the other, which is why the block's reach is wider than the torso.
#
# Geometry, not authored numbers: the kneeling hip height falls out of the down
# leg's thigh/shin angles AND the boot's forward offset under them, and the
# extended leg's abduction is SOLVED from that same height (its vertical span is
# exactly leg·cos(roll), since the knee folds in the rolled leg's own sagittal
# plane), so its skate lands on the ice instead of floating above it or
# scissoring through it.
#
# Keyed off the REPLICATED shot state, not the state machine — a wire-fed
# remote's state machine is never ticked, so it would never see the block.

const State = SkaterStateMachine.State

# The legs are planted: the stride stops while the block holds them.
var planted: bool = false
var _blend: float = 0.0


func stages() -> int:
	return Stage.OVERRIDE


func reset() -> void:
	planted = false
	_blend = 0.0


func is_quiet() -> bool:
	return _skater.current_shot_state != State.SHOT_BLOCKING


# Fast into the committed plant, eased back out on release so the knee drop
# doesn't pop back to a stride.
func advance(delta: float) -> bool:
	planted = _skater.current_shot_state == State.SHOT_BLOCKING
	_blend = lerpf(_blend, 1.0 if planted else 0.0,
			minf(_controller.block_pose_blend_speed * delta, 1.0))
	return _blend > 0.001


func override(p: GaitPose) -> void:
	if _blend <= 0.001:
		return
	# A held pose: the block's stick is solved in a frame that has gone down
	# with the body (GaitPose.frame_share).
	p.frame_share = maxf(p.frame_share, _blend)
	const THIGH: float = GaitPose.THIGH_LEN
	const SHIN: float = GaitPose.SHIN_LEN
	const FOOT: float = GaitPose.FOOT_FWD
	var kneel_hip: float = deg_to_rad(_controller.block_kneel_hip_deg)
	var kneel_shin: float = deg_to_rad(_controller.block_kneel_shin_deg)
	var hip_h: float = p.leg_scale * (THIGH * cos(kneel_hip)
			+ SHIN * cos(kneel_shin) + FOOT * sin(kneel_shin))
	var ext_knee: float = deg_to_rad(_controller.block_extend_knee_deg)
	var ext_len: float = p.leg_scale * (THIGH + SHIN * cos(ext_knee) + FOOT * sin(ext_knee))
	var ext_roll: float = acos(clampf(hip_h / maxf(ext_len, 0.001), -1.0, 1.0))
	var down_knee: float = -(kneel_hip + kneel_shin)
	# The extended leg rolls AWAY from the body (left toward −X, right toward
	# +X), and its ankle gives back what that leg took, so its blade lies flat
	# instead of swinging up onto an edge under a leg splayed 60° out of
	# vertical. The kneeling leg keeps its fold — that skate is up on its toe by
	# design, so it is not planted; the extended one is solved onto the ice.
	if p.stick_side > 0.0:
		p.plant_r = lerpf(p.plant_r, 0.0, _blend)
		p.foot_flat_l = _blend
		p.foot_flat_r = 0.0
		p.r_pitch = lerpf(p.r_pitch, kneel_hip, _blend)
		p.r_roll = lerpf(p.r_roll, 0.0, _blend)
		p.r_knee = lerpf(p.r_knee, down_knee, _blend)
		p.l_pitch = lerpf(p.l_pitch, 0.0, _blend)
		p.l_roll = lerpf(p.l_roll, -ext_roll, _blend)
		p.l_knee = lerpf(p.l_knee, -ext_knee, _blend)
	else:
		p.plant_l = lerpf(p.plant_l, 0.0, _blend)
		p.foot_flat_r = _blend
		p.foot_flat_l = 0.0
		p.l_pitch = lerpf(p.l_pitch, kneel_hip, _blend)
		p.l_roll = lerpf(p.l_roll, 0.0, _blend)
		p.l_knee = lerpf(p.l_knee, down_knee, _blend)
		p.r_pitch = lerpf(p.r_pitch, 0.0, _blend)
		p.r_roll = lerpf(p.r_roll, ext_roll, _blend)
		p.r_knee = lerpf(p.r_knee, -ext_knee, _blend)
	p.drop = lerpf(p.drop, p.leg_length() - hip_h, _blend)
