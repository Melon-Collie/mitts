class_name AIShotValue

# THE SEAM. Everything the bots rank — carry candidates, pass receivers, off-puck
# seams, the shoot/don't gate — asks "how good is a shot from here" through
# `for_release`, so the model behind it can be replaced in this file alone. That
# narrowness is deliberate insurance: the model is knowingly an APPROXIMATION,
# adopted while the live goalie is being retuned.
#
# ── The model ────────────────────────────────────────────────────────────────
# XGBaseline's public form — a logistic in log-distance and angle — plus two
# features: how far the keeper has been displaced off the square he needs, and
# how much of the mouth his body fills from in tight.
#
#   logit = XGBaseline.logit_for_shot(...) + DISPLACEMENT_LOGIT_PER_M · deficit
#           + body_logit(...)
#
# It literally extends the baseline's logit rather than re-deriving it, so at
# zero displacement, from anywhere his body fills no more of the mouth than it
# does from the slot, the two are the same number by construction (asserted in
# tests/unit/ai/test_shot_value.gd).
#
# ── Why the public form is the right base ────────────────────────────────────
# The target is an NHL-quality keeper. Against one, an NHL-calibrated model is
# correct BY CONSTRUCTION — its apparent miscalibration against the current
# goalie (predicting ~0.09 where the grid measures 0.438) is a statement about
# him, not about the form. And it has the property the five-hole geometry never
# had: it is smooth and monotone, so the DIFFERENCE between two nearby spots is
# meaningful. That is the only quantity a carry beam consumes, and a surface
# built from a max over five holes with structural cliffs cannot supply it.
#
# ── Why displacement is the one feature that must be added ───────────────────
# The public form marginalises the goalie away. That is right for a season-long
# stat and fatal for a decision: two spots two metres apart score identically,
# so moving the keeper buys nothing and the argmax falls through to whatever
# tie-breakers are left. Displacement is what makes "make him move" scoreable,
# and it is measurable rather than assumed — see displacement_deficit_m.
#
# ── Why the body is the second ───────────────────────────────────────────────
# The public form is fitted on shots whose doorstep share is mostly rebounds and
# displaced keepers, so its point-blank value is mostly those: it reads ~0.6 from
# 2 m whoever is in the net. Against a set, square keeper the open mouth from
# there is nearly nil (the live keeper stops all of it), and the bot drove into
# his pads for it. body_logit is that missing perception, in the same
# ln(available width) currency as POST_SEAL_LOGIT.
#
# Deliberately NOT modelled: the DOWN (butterfly) state and screens. Both are
# whole-goalie states rather than body parts, so they fit this model's grain and
# drop in as further logit terms when something measures them.
#
# Pure/static and engine-free, like every other domain evaluator.

# Log-odds added per metre the keeper is displaced off his square.
#
# Provenance, to the same standard as XGBaseline's own coefficients: solved to
# reproduce a known public aggregate rather than picked. The public proxies for
# "the keeper is not set" are the rebound and cross-ice-pass (royal road)
# features, which carry roughly a 3x odds multiplier in fitted models. A keeper
# displaced by his own cover half-width (~0.85 m) is beaten to that side, which
# is the situation those features describe — so ln(3) / 0.85 ≈ 1.3 per metre.
const DISPLACEMENT_LOGIT_PER_M: float = 1.3

# Displacement stops buying anything once he is off the near post: past that
# the side is simply open, and the net's own width bounds how much more the
# geometry can give. Clamped rather than allowed to run, so a wildly displaced
# keeper reads as "beaten" and not as a certainty the finite mouth cannot
# actually deliver.
const MAX_USEFUL_DISPLACEMENT_M: float = GameRules.NET_HALF_WIDTH

# A post seal (RVH/VH) walls the NEAR half of the mouth: the keeper is already
# deployed against the post the shot has to beat, with no reaction left to
# race. Only the far half is a target.
#
# The coefficient is ln(2) and it is geometry rather than a tunable: to a first
# approximation a shot's chance scales with the target width available to it,
# so removing half the mouth halves the odds, and halved odds is exactly
# -ln(2) of logit. No fitting, nothing to tune.
#
# v1 does not distinguish VH from RVH. VH stands the near column ice-to-
# shoulder while RVH stays compressed and concedes the short-side high — so
# the true RVH penalty is smaller than a full halving. Treating both as half
# the mouth is a known over-penalty on RVH, deferred rather than guessed,
# because splitting them needs the band structure this model deliberately
# does not carry.
const POST_SEAL_LOGIT: float = -0.6931472

# Heights the keeper's silhouette is read at across the mouth.
const _BODY_SAMPLES: int = 6
# The open mouth is floored at one puck's face of it: ln needs a finite
# argument, and a covered net is shut, not certain to be.
const _OPEN_FLOOR: float = (GameRules.PUCK_COLLISION_RADIUS * GameRules.PUCK_COLLISION_HALF_HEIGHT * 4.0) \
		/ (GameRules.NET_HALF_WIDTH * 2.0 * GameRules.NET_HEIGHT)
# Open mouth a set keeper leaves from the slot distance, by whole degree of
# bearing off the goal normal (_build_reference).
static var _open_ref := PackedFloat32Array()
# The set keeper's silhouette, piecewise in height: how far he covers to his
# glove side and his blocker side up to each top (_build_silhouette).
static var _cover_top := PackedFloat32Array()
static var _cover_glove := PackedFloat32Array()
static var _cover_blocker := PackedFloat32Array()


# THE ENTRY POINT. Probability that a shot released at `release` toward
# `attacking_goal` beats a keeper displaced `displacement_m` off his square.
# Shot type is the same enum XGBaseline takes, so a one-timer or a tip carries
# its bump here too.
static func for_release(release: Vector3, attacking_goal: Vector3,
		displacement_m: float,
		shot_type: int = ShotEvent.ShotType.SHOT,
		into_post_seal: bool = false, keeper_depth_m: float = -1.0) -> float:
	# No shot exists from on or behind the goal line — the mouth faces away, and
	# every downstream consumer relies on this being hard zero rather than a
	# small number the argmax can be lured by.
	if (release.z - attacking_goal.z) * -signf(attacking_goal.z) < 0.001:
		return 0.0
	var team_id: int = 1 if attacking_goal.z > 0.0 else 0
	var logit: float = XGBaseline.logit_for_shot(
			release.x, release.z, team_id, shot_type)
	logit += DISPLACEMENT_LOGIT_PER_M * clampf(
			displacement_m, 0.0, MAX_USEFUL_DISPLACEMENT_M)
	if into_post_seal:
		logit += POST_SEAL_LOGIT
	logit += body_logit(release, attacking_goal, displacement_m, keeper_depth_m)
	return XGBaseline.sigmoid(logit)


# Log-odds off the public form for how much more of the mouth the keeper's body
# fills from `release` than from the slot distance on the same bearing:
# ln(open / open there), never positive. The public form's angle term already
# prices how much more of an oblique mouth he covers; this is only the closing
# in. He is the keeper the displacement term reads, off his square by
# `displacement_m`, `keeper_depth_m` out from the goal centre where the caller
# knows it, else at the depth a set keeper holds for this puck. On a
# post-sealed look it prices his body on the shot line and POST_SEAL_LOGIT the
# near half he walls; in tight the body alone already shuts it.
static func body_logit(release: Vector3, attacking_goal: Vector3,
		displacement_m: float, keeper_depth_m: float = -1.0) -> float:
	if _open_ref.is_empty():
		_build_reference(attacking_goal)
	var open: float = maxf(open_mouth_fraction(release, attacking_goal, displacement_m,
			keeper_depth_m), _OPEN_FLOOR)
	var bearing: float = rad_to_deg(absf(atan2(release.x - attacking_goal.x,
			absf(release.z - attacking_goal.z))))
	var i: int = mini(int(bearing), _open_ref.size() - 2)
	var ref: float = lerpf(_open_ref[i], _open_ref[i + 1], bearing - float(i))
	return minf(0.0, log(open / maxf(ref, _OPEN_FLOOR)))


# Share of the goal mouth a set keeper's body leaves open from `release`, the
# keeper `offset_m` off the shot line and `keeper_depth_m` out (body_logit). His structural silhouette (GoalieAnatomy)
# is projected from the puck onto the goal line at _BODY_SAMPLES heights: from
# in tight he is close to the eye and the mouth is far, so his pads alone fill
# it. Each height is covered by the stance that covers it better, as the live
# keeper drops for the low shot and stands for the high one, and a height the
# league's steepest loft rung cannot reach from here is not open. Which way he
# is off his square is not known, so both mirror images are averaged.
static func open_mouth_fraction(release: Vector3, attacking_goal: Vector3,
		offset_m: float, keeper_depth_m: float = -1.0) -> float:
	var to_goal := Vector2(attacking_goal.x - release.x, attacking_goal.z - release.z)
	var l_net: float = to_goal.length()
	if l_net < 0.001:
		return 1.0
	var depth: float = keeper_depth_m if keeper_depth_m >= 0.0 \
			else AIActionScoring.set_goalie_depth(l_net)
	if depth >= l_net:
		return 1.0   # not between the puck and the net: pulled, or beaten past
	var l_keeper: float = maxf(l_net - depth, 0.05)
	var scale: float = l_net / l_keeper
	# A width across the shot line lands this much wider on the goal line.
	var oblique: float = scale / maxf(absf(to_goal.y) / l_net, 0.1)
	if _cover_top.is_empty():
		_build_silhouette()
	var reach: float = AIActionScoring.DEFAULT_LOFT_TANS.z * l_net
	var open: float = _open_across(scale, oblique, offset_m, reach)
	if absf(offset_m) > 0.001:
		open = 0.5 * (open + _open_across(scale, oblique, -offset_m, reach))
	return open / (2.0 * GameRules.NET_HALF_WIDTH * float(_BODY_SAMPLES))


# Open width summed over the sampled heights, the keeper `offset_m` toward his
# blocker side.
static func _open_across(scale: float, oblique: float, offset_m: float,
		reach: float) -> float:
	var half: float = GameRules.NET_HALF_WIDTH
	var open: float = 0.0
	for j: int in _BODY_SAMPLES:
		var y_net: float = GameRules.NET_HEIGHT * (float(j) + 0.5) / float(_BODY_SAMPLES)
		if y_net > reach:
			break
		var y_keeper: float = y_net / scale
		var glove: float = 0.0
		var blocker: float = 0.0
		for k: int in _cover_top.size():
			if y_keeper <= _cover_top[k]:
				glove = _cover_glove[k]
				blocker = _cover_blocker[k]
				break
		var lo: float = maxf((offset_m - glove) * oblique, -half)
		var hi: float = minf((offset_m + blocker) * oblique, half)
		open += 2.0 * half - maxf(hi - lo, 0.0)
	return open


# How far the keeper will be from the square he NEEDS, at the moment the shot
# is released — the physical quantity the displacement feature reads.
#
#   deficit = |where he must be − where he is| − |how far he can push by then|
#
# Both halves are measured, not fitted. The demand is the arc-match square for
# the release point (AIActionScoring.goalie_arc_match_x, the same solve the
# live keeper skates); the supply is his real accel-limited T-push over the
# time he has after his reaction delay (goalie_lateral_reach). Floored at zero:
# a keeper who can comfortably get there is simply set, and there is no such
# thing as negative displacement.
#
# This is also why the model survives the goalie being retuned. It reads his
# KINEMATICS — push speed, accel ramp, reaction delay, all published in
# GameRules — and never his anatomy, which is the part under repair.
static func displacement_deficit_m(keeper_pos: Vector3,
		attacking_goal: Vector3, release: Vector3,
		time_to_release_s: float) -> float:
	var need: float = absf(AIActionScoring.goalie_arc_match_x(
			keeper_pos, attacking_goal, release) - keeper_pos.x)
	var move_time: float = maxf(
			0.0, time_to_release_s - AIActionScoring.goalie_leg_delay_s)
	return maxf(0.0, need - AIActionScoring.goalie_lateral_reach(move_time))


# The better of his two stances' structural cover at each height, plus each
# READY hand at rest across its own box's height, as a table of tops between the
# parts' edges. The gap between his trunk or pads and either hand is narrower
# than a puck, so a hand covers from the midline out. Built from the ice up, so
# a puck under the pads' bottom edge reads the pads.
static func _build_silhouette() -> void:
	var hand: float = GoalieAnatomy.hand_vertical_half_extent()
	var glove_span := Vector2(GoalieAnatomy.GLOVE_REST_Y_M - hand,
			GoalieAnatomy.GLOVE_REST_Y_M + hand)
	var blocker_y: float = GoalieStickRules.upright_wrist_y()
	var blocker_span := Vector2(blocker_y - hand, blocker_y + hand)
	var glove_reach: float = GoalieAnatomy.GLOVE_REST_X_M + hand
	var blocker_reach: float = GoalieAnatomy.BLOCKER_REST_X_M + hand
	var edges: Array[float] = [glove_span.x, glove_span.y, blocker_span.x, blocker_span.y]
	for down: bool in [false, true]:
		for span: Vector2 in [GoalieAnatomy.pad_span(down), GoalieAnatomy.torso_span(down),
				GoalieAnatomy.head_span(down)]:
			edges.append(span.x)
			edges.append(span.y)
	edges.sort()
	var tops := PackedFloat32Array()
	var gloves := PackedFloat32Array()
	var blockers := PackedFloat32Array()
	var bottom: float = 0.0
	for top: float in edges:
		if top <= bottom:
			continue
		var mid: float = maxf((bottom + top) * 0.5, GoalieAnatomy.pad_span(false).x)
		var body: float = maxf(GoalieAnatomy.structural_cover_half_width_at(mid, false),
				GoalieAnatomy.structural_cover_half_width_at(mid, true))
		tops.append(top)
		gloves.append(maxf(body, glove_reach) if mid >= glove_span.x and mid <= glove_span.y
				else body)
		blockers.append(maxf(body, blocker_reach)
				if mid >= blocker_span.x and mid <= blocker_span.y else body)
		bottom = top
	_cover_glove = gloves
	_cover_blocker = blockers
	_cover_top = tops


static func _build_reference(attacking_goal: Vector3) -> void:
	var slot: float = AIActionScoring.slot_reference_release(attacking_goal) \
			.distance_to(attacking_goal)
	var out_z: float = -signf(attacking_goal.z)
	var table := PackedFloat32Array()
	for deg: int in 91:
		var a: float = deg_to_rad(float(deg))
		table.append(open_mouth_fraction(attacking_goal
				+ Vector3(sin(a), 0.0, cos(a) * out_z) * slot, attacking_goal, 0.0))
	_open_ref = table
