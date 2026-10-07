class_name GaitFaceoffLayer
extends GaitLayer

# The ready stance at the dot. The skater is at a standstill there, so the
# speed-driven crouch would leave them bolt upright — the layer floors it
# through the countdown instead, eased both ways so it settles in over the prep
# and releases into the draw. The two centres sit far deeper and wider than the
# players lined up behind them (SkaterController.faceoff_center_stance); both
# read the same replicated-by-derivation flag, so a wire-fed remote centre poses
# identically to a locally simulated one.

# Smoothed engagement. Published: the hands take their draw grip on the same
# ease (SkaterIKCoordinator.update_bottom_hand).
var blend: float = 0.0
# The centre's flat-bladed address, 0..1 (Skater.set_faceoff_address).
var address: float = 0.0


func stages() -> int:
	return Stage.FLOOR | Stage.LEGS | Stage.TRUNK


func reset() -> void:
	blend = 0.0
	address = 0.0


func is_quiet() -> bool:
	return not _controller.is_faceoff_ready()


func advance(delta: float) -> bool:
	blend = lerpf(blend, 1.0 if _controller.is_faceoff_ready() else 0.0,
			_controller.stride_intensity_speed * delta)
	address = blend if blend > 0.001 and _skater.is_faceoff_center else 0.0
	return blend > 0.001


func stance_floor() -> float:
	if blend <= 0.001:
		return 0.0
	var floor_stance: float = _controller.faceoff_center_stance if _skater.is_faceoff_center \
			else _controller.faceoff_stance
	return floor_stance * blend


# The stick-side foot drops back, braced for the draw, and the centre splays
# both legs into the wide base he sets over the dot — a sit this deep over feet
# at hip width is a squat, not an address. The splay rotates the whole leg
# chain, so its vertical span is span·cos(splay) and the body pays the deficit
# as extra drop; without it the skates ride up off the ice.
func shape_legs(p: GaitPose) -> void:
	if blend <= 0.001:
		return
	var split_deg: float = _controller.faceoff_center_split_deg if _skater.is_faceoff_center \
			else _controller.faceoff_split_deg
	var split: float = deg_to_rad(split_deg) * blend * (-1.0 if _skater.is_left_handed else 1.0)
	p.l_pitch += split
	p.r_pitch -= split
	if not _skater.is_faceoff_center:
		return
	var splay: float = deg_to_rad(_controller.faceoff_center_width_deg) * blend
	p.l_roll -= splay
	p.r_roll += splay
	p.drop += (p.leg_length() - p.drop) * (1.0 - cos(splay))
	# A sit this deep, over a base this wide, would stand both blades on their
	# heels and outside edges; the ankles give it back (an address is held on
	# flat blades, and a real ankle has the range for it).
	p.foot_flat_l = address
	p.foot_flat_r = address
	# Which changes what the drop owes: a level blade hangs below the FOOT pivot,
	# which swings down as the shin folds (GaitPose.FOOT_FWD), so the hip rides
	# that much higher.
	p.drop -= p.leg_scale * GaitPose.FOOT_FWD * sin(p.stance_shin) * blend


# The centre's fold over the dot. It rides the trunk TEXTURE rather than the
# torso lean the block uses, because the lean rotates the UpperBody node the
# blade markers hang from: the blade-first IK then has to solve a stick onto the
# ice out of a pitched frame, and at any fold worth seeing it gives up and
# stands the shaft on end. The texture is bones only, so the chest reads folded
# while the stick keeps the address the centre actually took.
func shape_trunk(p: GaitPose) -> void:
	if blend > 0.001 and _skater.is_faceoff_center:
		p.trunk_pitch += -deg_to_rad(_controller.faceoff_center_lean_deg) * blend


# How far the centre's address drops his body, in metres — the crouch this
# layer settles at over the dot, derived instead of measured because the
# placement that needs it runs at the whistle, before the pose exists (and on a
# body still carrying whatever depth it was skating at). Full leg length minus
# the vertical span left by the address's hip flex, its knee (the flex that
# keeps the skate under the hip) and the cosine the width splay costs.
# test_faceoff_prep_pose.gd holds this against the settled live crouch.
func address_drop(leg_scale: float) -> float:
	const THIGH: float = GaitPose.THIGH_LEN
	const SHIN: float = GaitPose.SHIN_LEN
	var hip: float = deg_to_rad(_controller.stance_hip_deg * _controller.faceoff_center_stance)
	var knee: float = hip + asin(clampf(THIGH / SHIN * sin(hip), -1.0, 1.0))
	var shin: float = knee - hip
	var span: float = leg_scale * (THIGH * cos(hip) + SHIN * cos(shin)
			+ GaitPose.FOOT_FWD * sin(shin))
	return leg_scale * (THIGH + SHIN) - span * cos(deg_to_rad(_controller.faceoff_center_width_deg))
