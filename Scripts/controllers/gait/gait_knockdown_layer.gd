class_name GaitKnockdownLayer
extends GaitLayer

# The knockdown crumple: the body sinks toward the ice and everything the gait
# drives goes limp — the stroke, the mohawk, the edges, the trunk texture and
# the stumble — so a downed body doesn't keep skating while it slides. The torso
# fall itself is SkaterPoseCoordinator._apply_lean's (the recoil channel) and
# the sprawl SkaterController._apply_knockdown_fall's; this is the gait's share.
#
# The get-up is this layer's too (KnockdownFallRules.lie_share and siblings): as
# the sprawl lets go it takes the legs onto both knees, steps the free leg up
# onto its skate, and hands back to the live pose as he stands off the knee.
#
# Derived FROM the replicated knockdown_timer, so it renders identically
# everywhere and through reconcile.

# The get-up's kneel: each kneeling thigh forward of vertical, the knee pivot
# riding a pad's radius over the ice and the shin rising behind it so the skate
# rests on its toe; the stepping leg's shin, forward of vertical (the skate
# ahead of the knee), its thigh solved to the kneeling hip height. The chest
# leans forward over the knees, pushing up.
const KNEEL_HIP_DEG: float = 10.0
const KNEEL_SHIN_DEG: float = 110.0
const KNEE_PAD_M: float = 0.09
const STEP_SHIN_DEG: float = -30.0
const STEP_CLEAR_M: float = 0.08  # the stepping foot's lift at mid-swing
const GETUP_LEAN_DEG: float = 22.0
# The down pose's share under which the ice stops holding the blend's skates up.
const HOLD_FADE: float = 0.3

# SkaterController.knockdown_pose_weight: the sprawl's buckle is solved from the
# same share of the drop, so the two must not be computed apart.
var weight: float = 0.0


func stages() -> int:
	return Stage.OVERRIDE


func reset() -> void:
	weight = 0.0


func is_quiet() -> bool:
	return _controller.knockdown_timer <= 0.0


func advance(_delta: float) -> bool:
	weight = _controller.knockdown_pose_weight()
	return weight > 0.0


func override(p: GaitPose) -> void:
	if weight <= 0.0:
		return
	# A held pose: the brace is posed in a frame that has gone down with the
	# body (GaitPose.frame_share).
	p.frame_share = maxf(p.frame_share, weight)
	# The body lies on the ice, then kneels on it, not on its blades; the sprawl
	# seats the lying legs.
	p.plant = lerpf(p.plant, 0.0, weight)
	p.plant_l = lerpf(p.plant_l, 0.0, weight)
	p.plant_r = lerpf(p.plant_r, 0.0, weight)
	var kd_t: float = _controller.knockdown_getup_left()
	var up: float = 1.0 - KnockdownFallRules.lie_share(kd_t)
	var step: float = KnockdownFallRules.step_share(kd_t)
	var kneel_hip: float = deg_to_rad(KNEEL_HIP_DEG)
	var kneel_shin: float = deg_to_rad(KNEEL_SHIN_DEG)
	var kneel_knee: float = -(kneel_hip + kneel_shin)
	# Hip pivot over the ice: kneeling, a thigh over the knee pad; standing, a
	# leg over the foot pivot, which the boot holds BLADE_ICE_Z up.
	var kneel_h: float = p.leg_scale * GaitPose.THIGH_LEN * cos(kneel_hip) + KNEE_PAD_M
	var kneel_drop: float = p.leg_length() + SkaterMeshBuilder.BLADE_ICE_Z - kneel_h
	# The free leg steps up: the one the sprawl left on top
	# (KnockdownFallRules.sprawl_into), while the leg the body fell onto stays
	# down. Its shin swings from the kneel to the lunge, and the thigh carries
	# the foot pivot from where the kneel left it to its standing height in front
	# of him, the knee lifting it clear of the ice on the way through.
	var step_shin: float = lerpf(kneel_shin, deg_to_rad(STEP_SHIN_DEG), step)
	var step_foot: float = lerpf(p.foot_height(kneel_h, kneel_hip, kneel_shin),
			SkaterMeshBuilder.BLADE_ICE_Z, step) + STEP_CLEAR_M * sin(PI * step)
	var step_hip: float = p.thigh_for(kneel_h, step_shin, step_foot)
	var lead_pitch: float = up * lerpf(kneel_hip, step_hip, step)
	var lead_knee: float = up * lerpf(kneel_knee, -(step_hip + step_shin), step)
	var left_leads: bool = _controller.stagger_recoil_dir.x > 0.0
	p.l_pitch = lerpf(p.l_pitch, lead_pitch if left_leads else up * kneel_hip, weight)
	p.r_pitch = lerpf(p.r_pitch, up * kneel_hip if left_leads else lead_pitch, weight)
	p.l_knee = lerpf(p.l_knee, lead_knee if left_leads else up * kneel_knee, weight)
	p.r_knee = lerpf(p.r_knee, up * kneel_knee if left_leads else lead_knee, weight)
	p.drop = lerpf(p.drop, lerpf(_controller.knockdown_drop_m(), kneel_drop, up), weight)
	# Standing up off the knee, the ice holds both skates up: a thigh whose foot
	# pivot the blend would put below its standing height comes forward instead.
	# Lying, the tipped body's legs are the sprawl's to rest on the ice, so the
	# hold comes in with the rise; and the live pose the blend hands back to is
	# the seat's to stand, so it lets go again before this layer does.
	var hold: float = up * smoothstep(0.0, HOLD_FADE, weight)
	if hold > 0.0:
		var hip_h: float = p.leg_length() + SkaterMeshBuilder.BLADE_ICE_Z - p.drop
		var floor_h: float = SkaterMeshBuilder.BLADE_ICE_Z * up
		var shin_l: float = -p.l_knee - p.l_pitch
		var shin_r: float = -p.r_knee - p.r_pitch
		if p.foot_height(hip_h, p.l_pitch, shin_l) < floor_h:
			p.l_pitch = lerpf(p.l_pitch, p.thigh_for(hip_h, shin_l, floor_h), hold)
			p.l_knee = -(p.l_pitch + shin_l)
		if p.foot_height(hip_h, p.r_pitch, shin_r) < floor_h:
			p.r_pitch = lerpf(p.r_pitch, p.thigh_for(hip_h, shin_r, floor_h), hold)
			p.r_knee = -(p.r_pitch + shin_r)
	# The planted skate's ankle gives its fold back so the blade lies flat; a
	# kneeling skate rests on its toe, as the block's does.
	if left_leads:
		p.foot_flat_l = lerpf(p.foot_flat_l, step, weight)
		p.foot_flat_r = lerpf(p.foot_flat_r, 0.0, weight)
	else:
		p.foot_flat_r = lerpf(p.foot_flat_r, step, weight)
		p.foot_flat_l = lerpf(p.foot_flat_l, 0.0, weight)
	p.l_roll = lerpf(p.l_roll, 0.0, weight)
	p.r_roll = lerpf(p.r_roll, 0.0, weight)
	p.l_yaw = lerpf(p.l_yaw, 0.0, weight)
	p.r_yaw = lerpf(p.r_yaw, 0.0, weight)
	p.edge_l = lerpf(p.edge_l, 0.0, weight)
	p.edge_r = lerpf(p.edge_r, 0.0, weight)
	p.trunk_pitch = lerpf(p.trunk_pitch,
			-deg_to_rad(GETUP_LEAN_DEG) * up, weight)
	p.trunk_roll = lerpf(p.trunk_roll, 0.0, weight)
	p.wobble_pitch = lerpf(p.wobble_pitch, 0.0, weight)
	p.wobble_roll = lerpf(p.wobble_roll, 0.0, weight)
