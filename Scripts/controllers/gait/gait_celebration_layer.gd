class_name GaitCelebrationLayer
extends GaitLayer

# The celly's legs and trunk (CellyPoseRules.body): the crouch it sits at, the
# lean of its trunk, and the knee slide's kneel — the stick-side knee down on
# the ice, the other skate planted out in front, in the knockdown get-up's
# kneel. That kneel is solved onto the ice, so it hands the blade seat back by
# its weight as the get-up does: the seat swapping its support foot mid-ease
# kicks the whole body. A held pose, so the frame goes down with the body
# (GaitPose.frame_share): the arms the celly poses hang from it. Gated to plain
# skating like the arms (SkaterController's celebration block) so it never
# fights a follow-through kick, and eased in and out with them.
#
# This pass runs at render rate and is visibility-gated, so the layer only
# READS the window: the callers age the timer at physics rate
# (SkaterController._process_input / RemoteController._physics_process), which
# keeps it deterministic and never frozen off-screen.

const State = SkaterStateMachine.State

var _body := CellyPoseRules.Body.new()
var _weight: float = 0.0


func stages() -> int:
	return Stage.FLOOR | Stage.TRUNK | Stage.OVERRIDE


func reset() -> void:
	_weight = 0.0


func is_quiet() -> bool:
	return _controller.celebration_progress() <= 0.0


func advance(_delta: float) -> bool:
	_weight = 0.0
	var progress: float = _controller.celebration_progress()
	var state: int = _skater.current_shot_state
	if progress <= 0.0 or (state != State.SKATING_WITH_PUCK
			and state != State.SKATING_WITHOUT_PUCK):
		return false
	var ease_s: float = SkaterShotPoseCoordinator.CELEBRATION_EASE_S
	_weight = smoothstep(0.0, ease_s, _controller.celebration_elapsed()) \
			* smoothstep(0.0, ease_s, _controller.celebration_left())
	CellyPoseRules.body(_controller.celebration_celly(), progress,
			_controller.celebration_elapsed(), _body)
	return _weight > 0.001


func stance_floor() -> float:
	return lerpf(_controller.rest_stance, maxf(_body.crouch, _controller.rest_stance), _weight)


func shape_trunk(p: GaitPose) -> void:
	var free_side: float = signf(_skater.bottom_shoulder.position.x)
	p.trunk_pitch += _body.pitch * _weight
	p.trunk_roll += -_body.lean_to_free * free_side * _weight


func override(p: GaitPose) -> void:
	p.frame_share = maxf(p.frame_share, _weight)
	var w: float = _weight * _body.kneel
	if w <= 0.001:
		return
	var kneel_hip: float = deg_to_rad(GaitKnockdownLayer.KNEEL_HIP_DEG)
	var kneel_shin: float = deg_to_rad(GaitKnockdownLayer.KNEEL_SHIN_DEG)
	var kneel_h: float = p.leg_scale * GaitPose.THIGH_LEN * cos(kneel_hip) \
			+ GaitKnockdownLayer.KNEE_PAD_M
	var down_knee: float = -(kneel_hip + kneel_shin)
	var lead_shin: float = deg_to_rad(GaitKnockdownLayer.STEP_SHIN_DEG)
	var lead_hip: float = p.thigh_for(kneel_h, lead_shin, SkaterMeshBuilder.BLADE_ICE_Z)
	var lead_knee: float = -(lead_hip + lead_shin)
	p.plant = lerpf(p.plant, 0.0, w)
	p.plant_l = lerpf(p.plant_l, 0.0, w)
	p.plant_r = lerpf(p.plant_r, 0.0, w)
	# The kneeling skate rests on its toe; the planted one's ankle gives its
	# fold back so the blade lies flat.
	if p.stick_side > 0.0:
		p.r_pitch = lerpf(p.r_pitch, kneel_hip, w)
		p.r_knee = lerpf(p.r_knee, down_knee, w)
		p.l_pitch = lerpf(p.l_pitch, lead_hip, w)
		p.l_knee = lerpf(p.l_knee, lead_knee, w)
		p.foot_flat_r = lerpf(p.foot_flat_r, 0.0, w)
		p.foot_flat_l = lerpf(p.foot_flat_l, 1.0, w)
	else:
		p.l_pitch = lerpf(p.l_pitch, kneel_hip, w)
		p.l_knee = lerpf(p.l_knee, down_knee, w)
		p.r_pitch = lerpf(p.r_pitch, lead_hip, w)
		p.r_knee = lerpf(p.r_knee, lead_knee, w)
		p.foot_flat_l = lerpf(p.foot_flat_l, 0.0, w)
		p.foot_flat_r = lerpf(p.foot_flat_r, 1.0, w)
	p.l_roll = lerpf(p.l_roll, 0.0, w)
	p.r_roll = lerpf(p.r_roll, 0.0, w)
	p.l_yaw = lerpf(p.l_yaw, 0.0, w)
	p.r_yaw = lerpf(p.r_yaw, 0.0, w)
	p.edge_l = lerpf(p.edge_l, 0.0, w)
	p.edge_r = lerpf(p.edge_r, 0.0, w)
	p.drop = lerpf(p.drop, p.leg_length() + SkaterMeshBuilder.BLADE_ICE_Z - kneel_h, w)
