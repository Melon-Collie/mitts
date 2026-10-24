class_name AIGoalieModel

# The keeper the bots plan against where the shot field does not answer: where
# he will be when a carry arrives or a puck is played — his tiered leg read
# (synced from the match's GoalieSkillProfile by set_goalie_profile), the depth
# he gives ground to, his lateral push and the post he holds. Every number is
# the keeper's own, read from his code (Scripts/domain/keeper/), never a copy
# of it: a MIRROR, not a second goalie — see Scripts/domain/ai/CLAUDE.md → "The
# goalie is tiered". A leaf (GameRules, the goalie rules and the keeper only).

# The ice either side of his centre his pads cover standing with NO reaction:
# their outside edge in his ready stance.
static var standing_pad_reach_m: float = _standing_pad_reach()

# Top speed of the react-then-push lateral model (goalie_lateral_reach): he
# ACCELERATES onto it at GOALIE_LATERAL_ACCEL_M_S2, never snapping to it, which
# is what a hard lateral cut in tight beats. His footwork's T-push, untiered.
const GOALIE_MAX_LATERAL_SPEED_MPS: float = GameRules.DEFAULT_GOALIE_T_PUSH_SPEED_M_S
const GOALIE_LATERAL_ACCEL_M_S2: float = GameRules.DEFAULT_GOALIE_LATERAL_ACCEL_M_S2

# ── Difficulty-synced goalie read model ───────────────────────────────────────
# Synced by set_goalie_profile; the default is Hard's, so unwired contexts
# (unit tests, threat surfaces) plan against the ceiling goalie. A static
# because the model threads ~every scoring entry point; set at match config,
# never per tick.
static var goalie_leg_delay_s: float = GameRules.DEFAULT_GOALIE_REACTION_DELAY_S

# His skating, which his depth answers the play from (KeeperPositioning.depth_for).
static var _skates := KeeperFootwork.new()

# Where he stands with the puck in the zone and not coming at him: his skates
# on the top of the crease, straight out (KeeperPositioning.crease_edge).
const GOALIE_RESTING_DEPTH_M: float = CreaseRules.ARC_RADIUS


static func _standing_pad_reach() -> float:
	var pose := KeeperPose.new()
	KeeperPoses.ready(pose)
	var skel := KeeperSkeleton.new()
	skel.pose(pose)
	return 0.5 * (KeeperGear.post_contact(skel, 1.0).x - KeeperGear.post_contact(skel, -1.0).x)


# Sync the goalie read model to the match's difficulty tier. Call with
# GoalieSkillProfile.hard() to restore the baseline (tests must restore).
static func set_goalie_profile(profile: GoalieSkillProfile) -> void:
	goalie_leg_delay_s = profile.reaction_delay_s


# The keeper's depth (metres out from his goal line) when the puck is at
# `puck_pos_at_release`, `time_s` from now, with its carrier closing on the net
# at `closing_speed_m_s`: the depth his own rule takes for that carrier
# (KeeperPositioning.depth_for, from his skating), approached from his current
# depth no faster than his C-cuts.
#
# RETREAT-ONLY: the model may pull the keeper IN but never push him OUT. His
# live depth is replicated truth set by much this planner cannot see (a pass he
# reads, a post he races to, a save), so a static read returns his current
# depth unchanged and only an approach moves him.
static func planned_goalie_depth(
		goalie_now: Vector3,
		attacking_goal: Vector3,
		puck_pos_at_release: Vector3,
		time_s: float,
		closing_speed_m_s: float = 0.0) -> float:
	var now_depth: float = absf(goalie_now.z - attacking_goal.z)
	if time_s <= 0.0:
		return now_depth
	var target: float = keeper_depth(attacking_goal, puck_pos_at_release, closing_speed_m_s)
	if target >= now_depth:
		return now_depth
	return maxf(now_depth - _skates.c_cut_speed * time_s, target)


# How far out from his goal line he stands for a carrier of theirs at `puck`
# coming at the net at `closing_speed_m_s`: his spot's depth on his feet
# (KeeperPositioning._spot) — half the crease out of the zone, in it his own
# rule's depth along the puck's line, no deeper than the back of the paint. A
# puck on or behind the goal line leaves him where the caller has him (INF).
static func keeper_depth(attacking_goal: Vector3, puck: Vector3, closing_speed_m_s: float = 0.0) -> float:
	var forward: float = (puck.z - attacking_goal.z) * -signf(attacking_goal.z)
	if forward < 0.001:
		return INF
	var in_net := Vector2(puck.x - attacking_goal.x, -forward)
	var r: float = in_net.length()
	var out: Vector2 = in_net / r
	var radial: float
	if r > KeeperPositioning.BLUE_LINE_M:
		radial = KeeperPositioning.crease_edge(out) * KeeperPositioning.AWAY_DEPTH_SHARE
	else:
		radial = maxf(KeeperPositioning.depth_for(in_net, -out * closing_speed_m_s, _skates, true),
				minf(KeeperPositioning.DEPTH_FLOOR_M, KeeperPositioning.crease_edge(out)))
	return radial * forward / r


# `goalie_now` relocated to `depth` metres out from the attacked goal line,
# keeping his lateral position. The rink side is the side the goal faces.
static func at_depth(goalie_now: Vector3, attacking_goal: Vector3,
		depth: float) -> Vector3:
	return Vector3(goalie_now.x, goalie_now.y,
			attacking_goal.z - signf(attacking_goal.z) * depth)


# Lateral distance a goalie's save push gets a pad across in `move_time`
# (post-reaction), against a shot already in flight: accelerate, then hold top
# speed — a pad moving through the line stops the puck, so it need not stop.
static func goalie_lateral_reach(move_time: float) -> float:
	return GoaliePushRules.cruise_reach(
			GOALIE_MAX_LATERAL_SPEED_MPS, GOALIE_LATERAL_ACCEL_M_S2, move_time)


# Lateral distance he can re-square across in `move_time` (post-reaction) and be
# SET on — pushed, cruised and stopped, as the live mover does. Positioning
# before a release reads this one. The inverse of _goalie_set_time.
static func _goalie_set_reach(move_time: float) -> float:
	return GoaliePushRules.set_reach(
			GOALIE_MAX_LATERAL_SPEED_MPS, GOALIE_LATERAL_ACCEL_M_S2, move_time)


# How far along a re-square to a spot `need` away he is `move_time` into it
# (post-reaction) — where the live mover, braking into the spot, has put him.
static func goalie_push_progress(need: float, move_time: float) -> float:
	return GoaliePushRules.push_progress(
			need, GOALIE_MAX_LATERAL_SPEED_MPS, GOALIE_LATERAL_ACCEL_M_S2, move_time)


# Time a re-square across `dist` takes, stop included (post-reaction) — the
# inverse of _goalie_set_reach.
static func _goalie_set_time(dist: float) -> float:
	return GoaliePushRules.time_to_set(
			dist, GOALIE_MAX_LATERAL_SPEED_MPS, GOALIE_LATERAL_ACCEL_M_S2)

# How far (m) from the net mouth a keeper still counts as HOME — the crease
# depth plus a stride. Beyond it (pulled, or out playing the puck) the net is
# empty to a shot.
const GOALIE_HOME_M: float = 3.0

# Shadow half-width used by AIShotAim.compute_open_net_aim for the lane-check
# aim point — picks a point past the goalie for the lane segment check.
const GOALIE_SHADOW_HALF_M: float = 0.3

# goalie_unsettled() settle reference: how long (s) the goalie must sit stopped
# at his target before the model treats him as fully re-set.
const GOALIE_SETTLE_REF_S: float = 0.20

# How long (s) he takes to stand back up out of the butterfly (KeeperDrop's
# rise; test_ai_goalie_model_mirrors.gd holds the two together): a shot sooner
# than this from now still finds him in the stance he is in.
const GOALIE_RECOVERY_S: float = 0.35


# ── Predicted post-seal ─────────────────────────────────────────────────────
# The shoot-now eval reads the LIVE goalie's seal state
# (GoalieNetworkState.post_seal_x_sign); a predictive caller (carry candidate,
# pass receiver) has none, and left unsealed a sharp-angle spot scores a
# PHANTOM far-side open net. So the post he WILL hold is predicted from his own
# sharp angle (KeeperPositioning's SHARP zone): below the dots and past this
# bearing off the goal normal he stands on the near post, his pad overlapping
# it, and holds a seal he races a carrier into.
const GOALIE_SEAL_ZONE_POST_Z_M: float = KeeperPositioning.DOT_LINE_M
const GOALIE_SEAL_ANGLE_RAD: float = KeeperPositioning.SHARP_RAD


# Whether a puck at `shooter`, in front of the net at `attacking_goal`, is at
# his sharp angle: where he holds the post, and outside which a keeper still on
# it is leaving it.
static func in_post_seal_zone(shooter: Vector3, attacking_goal: Vector3) -> bool:
	var forward: float = (shooter.z - attacking_goal.z) * -signf(attacking_goal.z)
	if forward < 0.001 or forward > GOALIE_SEAL_ZONE_POST_Z_M:
		return false
	return atan2(absf(shooter.x - attacking_goal.x), maxf(forward, 0.01)) \
			>= GOALIE_SEAL_ANGLE_RAD


# Predicted post-seal x-sign for a shot from `shooter`: the side (relative to goal
# center) a keeper would seal, or 0.0 for the common in-front look where no seal
# applies. Only the IN-FRONT sharp angle is sealed here (tall, on his feet); a release
# behind the goal line is already zeroed by score_shoot_value's forward guard, so it
# needs no seal. Pure float, allocation-free — safe on the per-candidate path.
#
# Two triggers, both grounded in the live keeper:
#  · His sharp angle (in_post_seal_zone) — where he stands on the post.
#  · DEAD-ANGLE ERASURE: outside that zone, a keeper hugging the near post
#    still kills a sharp-angle look. The shot dies when the net's whole
#    angular window from the shooter is no wider than his stance span plus a
#    puck diameter of fit. Pure projection geometry, so it scales with range:
#    the slot and any honest mid look are far wider than a body.
static func derive_post_seal_x_sign(shooter: Vector3, attacking_goal: Vector3) -> float:
	var net_normal_z: float = -signf(attacking_goal.z)
	var forward: float = (shooter.z - attacking_goal.z) * net_normal_z
	if forward < 0.001:
		return 0.0
	var lateral: float = absf(shooter.x - attacking_goal.x)
	# Frontal early-out (hot path — this is on every arc-match): neither
	# trigger can fire at or inside 45° off the normal. His sharp angle needs
	# 60°, and the erasure's window at 45° (≥ 1.83·cos 45° / d) is always
	# wider than the post-body cover (≤ 1.01 / d) at any range.
	if lateral <= forward:
		return 0.0
	var side: float = signf(shooter.x - attacking_goal.x)
	if in_post_seal_zone(shooter, attacking_goal):
		return side
	if side == 0.0:
		return 0.0
	# Dead-angle erasure: net angular window vs the post-hugging keeper's
	# stance span + puck fit, anchored at the near-post sightline.
	var near_x: float = attacking_goal.x + side * GameRules.NET_HALF_WIDTH
	var far_x: float = attacking_goal.x - side * GameRules.NET_HALF_WIDTH
	var dz: float = attacking_goal.z - shooter.z
	var a_near: float = atan2(near_x - shooter.x, dz)
	var a_far: float = atan2(far_x - shooter.x, dz)
	var window: float = absf(a_near - a_far)
	var d_near: float = sqrt(
			(near_x - shooter.x) * (near_x - shooter.x) + dz * dz)
	var cover: float = atan((2.0 * standing_pad_reach_m
			+ 2.0 * GameRules.PUCK_COLLISION_RADIUS) / maxf(d_near, 0.1))
	if window <= cover:
		return side
	return 0.0


# Point-blank jam distance: the closest the puck realistically gets to a set goalie
# before his body/pads stop it. A physical measurement (skate + pad depth), not a
# tuning knob — it just keeps the shooter strictly in FRONT of the keeper so the
# shadow geometry stays well-defined (a shooter coincident with the goalie is a
# degenerate projection).
const GOALIE_JAM_DISTANCE_M: float = 0.4

# Clamps a release so its distance out from the goal is at least the goalie's
# + the jam margin: the puck leaves the blade in FRONT of him, never behind, so
# a projected release in the crease never scores as if the keeper were behind
# the shooter. Only the goalward axis is clamped.
#
# A release on/behind the GOAL LINE is returned unchanged: there is no shot
# from back there, and clamping it would invent a point-blank release in front
# of the keeper.
static func release_ahead_of_goalie(
		release: Vector3, attacking_goal: Vector3, goalie_pos: Vector3) -> Vector3:
	var net_normal_z: float = -signf(attacking_goal.z)
	var release_fwd: float = (release.z - attacking_goal.z) * net_normal_z
	if release_fwd < 0.001:
		return release
	var goalie_fwd: float = (goalie_pos.z - attacking_goal.z) * net_normal_z
	var min_fwd: float = goalie_fwd + GOALIE_JAM_DISTANCE_M
	if release_fwd >= min_fwd:
		return release
	return Vector3(release.x, release.y, attacking_goal.z + min_fwd * net_normal_z)


# The ARC-MATCHING x a properly squared goalie sits at for a puck at
# `puck_pos`: since the goalie sits much closer to the goal than the shooter,
# arc_x = goalie_depth × (puck.x − goal.x) / puck_forward_from_goal. Shared by
# predict_goalie_pos / goalie_unsettled / goalie_squared_pos so all three agree.
static func goalie_arc_match_x(
		goalie_now: Vector3, attacking_goal: Vector3, puck_pos: Vector3) -> float:
	# A POST-SEALED look (derive_post_seal_x_sign) has no arc to square on: the
	# competent keeper's square IS the post. The arc formula would extrapolate
	# past the frame there, reading him as stranded off the post he is sealing
	# and saturating the unsettle credit.
	var seal: float = derive_post_seal_x_sign(puck_pos, attacking_goal)
	if seal != 0.0:
		return attacking_goal.x + seal * GameRules.NET_HALF_WIDTH
	var net_normal_z: float = -signf(attacking_goal.z)
	var puck_forward: float = (puck_pos.z - attacking_goal.z) * net_normal_z
	var goalie_depth: float = (goalie_now.z - attacking_goal.z) * net_normal_z
	# The goalie squares along his ARC — his lateral offset can never exceed his
	# own radial distance from the goal. Unbounded, a near-goal-line puck
	# explodes the arc-x toward the corner boards. Moderate angles are untouched
	# (an out-challenging goalie legitimately squares past the post line).
	var radius: float = Vector3(
			goalie_now.x - attacking_goal.x, 0.0,
			goalie_now.z - attacking_goal.z).length()
	if puck_forward < 0.001 or goalie_depth < 0.001:
		# Degenerate: puck on/behind goal line, or goalie there. Best-effort: the
		# puck's side, bounded to the arc.
		return attacking_goal.x + clampf(
				puck_pos.x - attacking_goal.x, -radius, radius)
	var arc_x: float = goalie_depth * (puck_pos.x - attacking_goal.x) / puck_forward
	return attacking_goal.x + clampf(arc_x, -radius, radius)


# The goalie SQUARED to a puck at `puck_pos` — arc-matched and set, no forced
# motion. The model for a CARRY destination: the keeper tracks the puck
# continuously as the bot skates there, so on arrival he is square. Do not use
# the react-then-push predict_goalie_pos for a carry — it under-tracks him and
# leaks a far side the bot then chases into the crease. The caught-moving
# credit belongs to puck RELOCATIONS (shots/passes).
static func goalie_squared_pos(
		goalie_now: Vector3, attacking_goal: Vector3, puck_pos: Vector3,
		travel_time_s: float = 0.0, closing_speed_m_s: float = 0.0) -> Vector3:
	# DEPTH travels with the puck too (planned_goalie_depth); `travel_time_s` = 0
	# leaves him where he is.
	var based: Vector3 = at_depth(goalie_now, attacking_goal, planned_goalie_depth(
			goalie_now, attacking_goal, puck_pos, travel_time_s, closing_speed_m_s))
	return Vector3(goalie_arc_match_x(based, attacking_goal, puck_pos),
			based.y, based.z)


static func predict_goalie_pos(
		goalie_now: Vector3,
		attacking_goal: Vector3,
		release_time_s: float,
		puck_pos_at_release: Vector3,
		closing_speed_m_s: float = 0.0) -> Vector3:
	# DEPTH first, so the arc match is solved AT the depth he will stand at and
	# position, arc-x and the unsettle read agree.
	var based: Vector3 = at_depth(goalie_now, attacking_goal, planned_goalie_depth(
			goalie_now, attacking_goal, puck_pos_at_release,
			release_time_s, closing_speed_m_s))
	var target_x: float = goalie_arc_match_x(based, attacking_goal, puck_pos_at_release)
	var move_time: float = maxf(0.0, release_time_s - goalie_leg_delay_s)
	var dx: float = target_x - based.x
	if absf(dx) < 0.001 or move_time <= 0.0:
		return based
	return Vector3(based.x + signf(dx) * goalie_push_progress(absf(dx), move_time),
			based.y, based.z)


# Companion to predict_goalie_pos: how UNSETTLED [0, 1] the goalie is AT release.
#   0 = set and square (already at its arc-match target, no forced motion)
#   1 = still sliding (positionally behind) or only just arrived — reading late
# Same react-then-push kinematics as predict_goalie_pos, so the predicted
# position and this motion estimate agree. The carry search prices the keeper
# moving across at this fraction of his lateral speed on the release.
static func goalie_unsettled(
		goalie_now: Vector3,
		attacking_goal: Vector3,
		release_time_s: float,
		puck_pos_at_release: Vector3,
		closing_speed_m_s: float = 0.0) -> float:
	# Same depth the position prediction lands on.
	var based: Vector3 = at_depth(goalie_now, attacking_goal, planned_goalie_depth(
			goalie_now, attacking_goal, puck_pos_at_release,
			release_time_s, closing_speed_m_s))
	var target_x: float = goalie_arc_match_x(based, attacking_goal, puck_pos_at_release)
	var need: float = absf(target_x - goalie_now.x)
	if need < 0.001:
		return 0.0  # already squared — no forced motion, fully set
	var move_time: float = maxf(0.0, release_time_s - goalie_leg_delay_s)
	var max_move: float = _goalie_set_reach(move_time)
	if need >= max_move:
		return 1.0  # still sliding at release (or hasn't even reacted) — caught moving
	# Reached the target with time to spare; ramps back to 0 as it re-sets.
	var slide_time: float = _goalie_set_time(need)
	var settled_for: float = move_time - slide_time
	return clampf(1.0 - settled_for / GOALIE_SETTLE_REF_S, 0.0, 1.0)
