class_name AIGoalieModel

# The keeper the bots plan against where the shot field does not answer: where
# he will be when a carry arrives or a puck is played — his difficulty-tiered
# reads (synced from the match's GoalieSkillProfile by set_goalie_profile), the
# depth he gives ground to, his lateral push and the post he seals. A MIRROR of
# the live GoalieController, not a second tier — see Scripts/domain/ai/CLAUDE.md
# → "The goalie is tiered". A leaf (GameRules and the goalie rule classes only).

# The pad column a standing goalie covers with NO reaction — stance pad centre +
# half a pad box (GoalieBehaviorRules).
const LOW_CORE_STANDING_M: float = (
		GoalieBehaviorRules.STANDING_PAD_CENTER_X_M
		+ GoalieBehaviorRules.PAD_BOX_WIDTH_M * 0.5)

# Top speed of the react-then-push lateral model (goalie_lateral_reach): he
# ACCELERATES onto it at goalie_lateral_accel_m_s2, never snapping to it, which
# is what a hard lateral cut in tight beats. A const because no tier varies
# GoalieController.t_push_speed.
const GOALIE_MAX_LATERAL_SPEED_MPS: float = GameRules.DEFAULT_GOALIE_T_PUSH_SPEED_M_S

# ── Difficulty-synced goalie read model ───────────────────────────────────────
# See Scripts/domain/ai/CLAUDE.md → "The goalie is tiered". Synced by
# set_goalie_profile; defaults are the Hard/authored baselines, so unwired
# contexts (unit tests, threat surfaces) score the ceiling goalie. Statics
# because the model threads ~every scoring entry point; set at match config,
# never per tick.
static var goalie_leg_delay_s: float = GameRules.DEFAULT_GOALIE_REACTION_DELAY_S
static var goalie_lateral_accel_m_s2: float = GameRules.DEFAULT_GOALIE_LATERAL_ACCEL_M_S2
# The tier's puck-play GO margin (INF = he never leaves the net for a rim).
static var goalie_puck_play_go_margin_s: float = 0.9

# ── Planning keeper DEPTH: the challenge chart + the rush backflow ───────────
# The live keeper's depth model (GoalieDepthSolver chart + the speed-matched
# rush backflow), read RETREAT-ONLY by planned_goalie_depth. Never hold his
# depth frozen while the shooter closes: coverage is a tangent cone off his
# body, so a keeper pinned out at challenge depth appears to GROW as the
# shooter approaches and the doorstep reads as a covered net.
#
# Values mirror GoalieController's field defaults (cited per field;
# test_ai_goalie_model_mirrors.gd holds them); the two
# tier-varied depths ride set_goalie_profile.
static var _depth_cfg_planning: GoalieDepthSolver.Constraints = _build_planning_depth_cfg()
# The tier's challenge ceiling, held separately because the reused Constraints has
# its `ceiling_radius` overwritten per call by the in-zone gate.
static var _planning_ceiling: float = 1.75
static var _rush_cfg_planning: GoalieBehaviorRules.RushRetreatConfig = _build_planning_rush_cfg()
# Closing speed below which the live keeper keeps his challenge instead of
# backing in (`rush_min_closing_speed` field default) — a stalled carrier does
# not retreat him. The live keeper also holds the backflow for a carrier CROSSING
# him, and for the one who backed him in once he stops inside the hash marks; the
# planner sees neither, but both keep him near the depth the drive left him at,
# which is what this retreat-only read holds when closing is low.
const GOALIE_RUSH_MIN_CLOSING_M_S: float = 1.5
# Skating speed in and out of the crease (`depth_max_speed` field default) —
# the rate cap on ordinary chart depth changes. A genuine rush retreat is
# speed-matched instead (rush_retreat_rate), which can legitimately exceed it.
const GOALIE_DEPTH_MAX_SPEED_M_S: float = 2.2


# The planner's copy of the live keeper's depth CONSTRAINTS. Reused in place (this
# is read from the per-tick planning path), and fed to the same
# GoalieDepthSolver.solve_target the live GoalieController integrates toward — so
# the planner cannot drift from the keeper it is predicting.
static func _build_planning_depth_cfg() -> GoalieDepthSolver.Constraints:
	var cfg := GoalieDepthSolver.Constraints.new()
	cfg.ceiling_radius = 1.75         # depth_aggressive field default (tier-varied)
	cfg.floor_radius = 0.10           # depth_defensive
	return cfg


# Resting depth (BPS "C", middle of the paint) held while the play has not entered
# the zone — `depth_conservative` field default.
const GOALIE_RESTING_DEPTH_M: float = 0.70
# Gap the keeper keeps between himself and the threat while challenging —
# `challenge_standoff` field default. Physical (body depth + stick clearance).
const GOALIE_CHALLENGE_STANDOFF_M: float = 0.60
# Depth of the offensive zone; beyond it the play has not entered and the keeper
# rests instead of challenging (GoalieController._threat_is_in_zone).
const GOALIE_ZONE_DEPTH_M: float = GameRules.GOAL_LINE_Z - GameRules.BLUE_LINE_Z


static func _build_planning_rush_cfg() -> GoalieBehaviorRules.RushRetreatConfig:
	var cfg := GoalieBehaviorRules.RushRetreatConfig.new()
	cfg.engage_distance = 8.0    # rush_engage_distance field default
	cfg.mid_distance = 4.5       # rush_mid_distance
	cfg.arrive_distance = 1.5    # rush_arrive_distance
	cfg.depth_engage = 1.75      # = depth_aggressive
	cfg.depth_mid = 1.30         # = depth_base
	cfg.depth_arrive = 0.40      # rush_arrive_depth field default
	return cfg


# Sync the goalie read model to the match's difficulty tier. Call with
# GoalieSkillProfile.hard() to restore the baseline (tests must restore).
static func set_goalie_profile(profile: GoalieSkillProfile) -> void:
	goalie_leg_delay_s = profile.reaction_delay_s
	goalie_lateral_accel_m_s2 = profile.lateral_accel_mps2
	goalie_puck_play_go_margin_s = profile.puck_play_go_margin_s
	# Depth chart + backflow anchors — the tier's challenge depth (the live
	# controller feeds these same two profile fields into its own configs).
	_planning_ceiling = profile.depth_aggressive_m
	_rush_cfg_planning.depth_engage = profile.depth_aggressive_m
	_rush_cfg_planning.depth_mid = profile.depth_base_m


# The keeper's radial depth (metres out from his goal line) when the puck is at
# `puck_pos_at_release`, `time_s` from now, with the shooter closing on the net
# at `closing_speed_m_s`. The chart target, pulled further IN by the rush
# backflow while a genuinely closing attacker is inside the engage range,
# approached from his current depth at the rate the budget allows — ordinary
# crease skating, or the speed-matched retreat rate when the backflow binds.
#
# RETREAT-ONLY: the model may pull the keeper IN but never push him OUT. His
# live depth is replicated truth set by much this planner cannot see (post
# seals, backdoor caps, lateral-pressure pull, recoveries), so a static read
# returns his current depth unchanged and only an approach moves him.
static func planned_goalie_depth(
		goalie_now: Vector3,
		attacking_goal: Vector3,
		puck_pos_at_release: Vector3,
		time_s: float,
		closing_speed_m_s: float = 0.0) -> float:
	var now_depth: float = absf(goalie_now.z - attacking_goal.z)
	if time_s <= 0.0:
		return now_depth
	var dx: float = puck_pos_at_release.x - attacking_goal.x
	var dz: float = puck_pos_at_release.z - attacking_goal.z
	var dist: float = sqrt(dx * dx + dz * dz)
	# Same model the live keeper solves — ceiling gated on the play being
	# in-zone, floored, and bounded by the physical standoff. The caps the
	# planner cannot see (lateral tracking, backdoor re-square, screen room, a
	# net-front tip) only ever pull him DEEPER, so with the retreat-only `minf`
	# omitting them stays conservative.
	var c := _depth_cfg_planning
	c.ceiling_radius = _planning_ceiling if dist <= GOALIE_ZONE_DEPTH_M \
			else GOALIE_RESTING_DEPTH_M
	c.standoff_cap = dist - GOALIE_CHALLENGE_STANDOFF_M
	var target: float = minf(now_depth, GoalieDepthSolver.solve_target(c))
	var rate: float = GOALIE_DEPTH_MAX_SPEED_M_S
	if dist < _rush_cfg_planning.engage_distance \
			and closing_speed_m_s >= GOALIE_RUSH_MIN_CLOSING_M_S:
		var rush_target: float = GoalieBehaviorRules.rush_retreat_depth(
				dist, _rush_cfg_planning)
		if rush_target < target:
			target = rush_target
			# While the backflow retreats him it OWNS the motion and bypasses
			# the ordinary rate cap (GoalieDepthSolver.solve), so the rate is
			# the backflow's own — never the max of the two. Zero means the
			# curve is flat here, where the live solve falls back to the settle.
			var rush_rate: float = GoalieBehaviorRules.rush_retreat_rate(
					dist, closing_speed_m_s, _rush_cfg_planning)
			if rush_rate > 0.0:
				rate = rush_rate
	if target >= now_depth:
		return now_depth
	return maxf(now_depth - rate * time_s, target)


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
			GOALIE_MAX_LATERAL_SPEED_MPS, goalie_lateral_accel_m_s2, move_time)


# Lateral distance he can re-square across in `move_time` (post-reaction) and be
# SET on — pushed, cruised and stopped, as the live mover does. Positioning
# before a release reads this one. The inverse of _goalie_set_time.
static func _goalie_set_reach(move_time: float) -> float:
	return GoaliePushRules.set_reach(
			GOALIE_MAX_LATERAL_SPEED_MPS, goalie_lateral_accel_m_s2, move_time)


# How far along a re-square to a spot `need` away he is `move_time` into it
# (post-reaction) — where the live mover, braking into the spot, has put him.
static func goalie_push_progress(need: float, move_time: float) -> float:
	return GoaliePushRules.push_progress(
			need, GOALIE_MAX_LATERAL_SPEED_MPS, goalie_lateral_accel_m_s2, move_time)


# Time a re-square across `dist` takes, stop included (post-reaction) — the
# inverse of _goalie_set_reach.
static func _goalie_set_time(dist: float) -> float:
	return GoaliePushRules.time_to_set(
			dist, GOALIE_MAX_LATERAL_SPEED_MPS, goalie_lateral_accel_m_s2)

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

# How long (s) a goalie down in his stance takes to stand back up
# (GoalieController.recovery_duration): a shot sooner than this from now still
# finds him in the stance he is in.
const GOALIE_RECOVERY_S: float = 0.35


# ── Predicted post-seal (RVH/VH) ────────────────────────────────────────────
# The shoot-now eval reads the LIVE goalie's seal state
# (GoalieNetworkState.post_seal_x_sign); a predictive caller (carry candidate,
# pass receiver) has none, and left unsealed a sharp-angle spot scores a
# PHANTOM far-side open net. So the seal a competent keeper WILL adopt is
# predicted from the trigger the live goalie uses
# (GoalieBehaviorRules.is_puck_in_defensive_zone).
#
# GoalieController.zone_post_z / rvh_early_angle (test_ai_goalie_model_mirrors.gd
# holds them): within this depth of
# the goal line AND past this bearing off the goal normal, the keeper is
# post-sealed — only the wraparound/extreme-corner region.
const GOALIE_SEAL_ZONE_POST_Z_M: float = 2.0
const GOALIE_SEAL_ANGLE_RAD: float = deg_to_rad(77.0)


# Whether a puck at `shooter`, in front of the net at `attacking_goal`, is inside
# the live keeper's RVH/VH trigger zone: where he takes the post, and outside which
# a keeper still on it is leaving it.
static func in_post_seal_zone(shooter: Vector3, attacking_goal: Vector3) -> bool:
	var forward: float = (shooter.z - attacking_goal.z) * -signf(attacking_goal.z)
	if forward < 0.001 or forward > GOALIE_SEAL_ZONE_POST_Z_M:
		return false
	return atan2(absf(shooter.x - attacking_goal.x), maxf(forward, 0.01)) \
			>= GOALIE_SEAL_ANGLE_RAD


# Predicted post-seal x-sign for a shot from `shooter`: the side (relative to goal
# center) a keeper would seal, or 0.0 for the common in-front look where no seal
# applies. Only the IN-FRONT sharp angle is sealed here (VH — tall); a release
# behind the goal line is already zeroed by score_shoot_value's forward guard, so it
# needs no seal. Pure float, allocation-free — safe on the per-candidate path.
#
# Two triggers, both grounded in the live keeper:
#  · The RVH/VH zone (2 m, 77°) — the live controller's own stance trigger.
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
	# trigger can fire at or inside 45° off the normal. The RVH/VH zone needs
	# 77°, and the erasure's window at 45° (≥ 1.83·cos 45° / d) is always
	# wider than the post-body cover (≤ 0.80 / d) at any range.
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
	var cover: float = atan((2.0 * LOW_CORE_STANDING_M
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


# Keeper puck-play travel build — GoalieController's `puck_play_skate_speed` /
# `puck_play_skate_accel` field defaults, and `puck_play_capture_radius` (the
# paddle trap reach at the spot he stops on). UNTIERED: what a resting puck's
# ownership turns on is how far a keeper can skate, which no difficulty knob
# changes.
const GOALIE_PUCK_PLAY_SPEED_M_S: float = 4.2
const GOALIE_PUCK_PLAY_ACCEL_M_S2: float = 8.0
const GOALIE_PUCK_PLAY_REACH_M: float = 1.0
