class_name AIActionScoring

# Pure-function scoring for on-puck actions: the shot and pass reads on the value
# seam (AIShotValue — the odds against today's goalie), the xG stat, position
# value, the turnover and counter-rush costs, and the loose-puck race. See
# Scripts/domain/ai/CLAUDE.md → "Where an evaluator goes".

# Shared read-only empty arrays, so the leaf scorers don't allocate an empty
# array per call. Two traps. They are for ARGUMENT sites only: a shared empty
# used as a *parameter default* trips a Godot type-binding error at call time,
# so the `= []` defaults below stay literals. And EMPTY_VEC3 must be a `static var`,
# not a `const`: a typed-`const` array loses its element type when passed as a
# typed-array argument (Godot rejects it — "does not have the same element
# type"), whereas a typed static var keeps it. EMPTY_CAPS is untyped, so a
# read-only `const` is fine there.
static var EMPTY_VEC3: Array[Vector3] = []
const EMPTY_CAPS: Array = []

static func _static_init() -> void:
	EMPTY_VEC3.make_read_only()

# ── The delay discount ───────────────────────────────────────────────────────
# A future action (a carry that arrives in `t` s, a pass in flight, a spot whose
# shot must still be skated to) is worth less than the same value NOW, because
# the read it was scored against decays: the survival function of a
# CONSTANT-HAZARD process, exp(-t / τ). The one free parameter is τ, the mean
# time (s) a tactical read stays roughly valid — an honest aggregate (physical
# decorrelation times span ~0.4 s to several seconds) and the one "how much do
# I trust the near future" feel dial. Raise it for more patient play.
#
# Bounds: the unit suite guards the IMPATIENT edge (developing feeds and
# walkouts fail below τ ≈ 2.8 s); test_delay_discount_bounds_patience the
# PATIENT one (τ < ~6.3 s).
const READ_VALIDITY_TAU_S: float = 6.0
# Once a fire intent is set, its (positive) score is scaled by (1 + this) when
# re-scored, so a challenger must beat it by 15% — damping flicker between two
# close fire options during pre-aim. PROPORTIONAL, not additive, because scores
# span ~0.02 (deep-DZ escapes) to ~0.7 (slot chances): a flat margin sane in the
# OZ exceeds the whole gap between options in the DZ. Applied only to positive
# scores and only to fire intents (shoot, pass, a rim).
const ACTION_HYSTERESIS_MARGIN_FRAC: float = 0.15


# Value multiplier for a play `delay_s` seconds in the future,
# exp(-delay_s / READ_VALIDITY_TAU_S). Every future-action scorer routes through
# here.
static func delay_discount(delay_s: float) -> float:
	return exp(-maxf(delay_s, 0.0) / READ_VALIDITY_TAU_S)


# ── Expected goals (xG) — the analytics stat ─────────────────────────────────
# The odds the shot went in against the keeper as he stood at release, read from
# the measured shot field (AIShotValue.now_at_spread) at the shot's CONTEXT
# spread — never the shooter's skill: a weaker player drawing lower xG on an
# identical chance would make goals-above-expected circular. Passes are excluded
# upstream — expected_goals only ever sees a shot the resolution gate counted.
#
#   xG = P(first contact beats him) + P(it does not) × XG_COVERED_LEAK
#
# Release scatter (radians, 1σ) for a reference shooter taking a SETTLED shot.
# Calibrated against the observed on-net fraction: every missed shot is direct
# evidence about this number, and a game has far more misses than goals.
const XG_BASE_SPREAD_RAD: float = 0.12
# A backhand is materially harder to place than a forehand.
const XG_BACKHAND_SPREAD_MULT: float = 1.6
# Shooting on the move — across the body, in transition, out of a deke — widens
# the release, scaled by speed against a reference clip.
const XG_MOTION_SPREAD_GAIN: float = 0.6
const XG_MOTION_REFERENCE_M_S: float = 8.0
# The field measures first contact only, so a shot he gets to still goes in
# sometimes — off traffic, a rebound he can't smother. Without this term the
# stat floors at exactly zero for every point shot at a set keeper.
const XG_COVERED_LEAK: float = 0.04
# Nothing is a certain goal — you can still fan on it or ring it off the iron
# with the net empty. Mirrors the leak at the other end of the range.
const XG_MAX: float = 0.95


# Release scatter for a shot's CONTEXT (which hand, how fast the shooter moves).
static func xg_release_spread(is_backhand: bool, skater_speed_m_s: float) -> float:
	var spread: float = XG_BASE_SPREAD_RAD
	if is_backhand:
		spread *= XG_BACKHAND_SPREAD_MULT
	spread *= 1.0 + XG_MOTION_SPREAD_GAIN \
			* clampf(skater_speed_m_s / XG_MOTION_REFERENCE_M_S, 0.0, 2.0)
	return spread


# `keeper_stance` is an AIShotOdds.Stance.
static func expected_goals(shooter: Vector3, attacking_goal: Vector3,
		goalie_pos: Vector3, release_spread_rad: float = XG_BASE_SPREAD_RAD,
		keeper_stance: int = AIShotOdds.Stance.UPRIGHT,
		query: AIShotOdds.Query = null) -> float:
	var beaten: float = AIShotValue.now_at_spread(shooter, attacking_goal, goalie_pos,
			0.0, keeper_stance, release_spread_rad, NAN, query)
	return minf(XG_MAX, beaten + (1.0 - beaten) * XG_COVERED_LEAK)


# ── Shoot-for-tip EV ──────────────────────────────────────────────────────────
# The value of ripping a shot AT THE NET through a net-front teammate's blade.
# Above the deflect threshold the puck redirects off his angled blade at
# near-full pace (PuckCollisionRules.deflect_velocity; the finisher's reactive
# TIP mode steps onto the shot path), so the outcome is a NEW release from the
# tip point. Three independent events compose:
#   P(rip reaches the tipper)   — lane_clear over release→tip vs the DEFENDERS
# × P(blade contacts the puck)  — the same reach/reaction race a lane defender
#                                 runs (_lane_block_at)
# × the redirect (AIShotValue.deflection): a one-timer off the rip whose line
#                                 is not picked, the keeper as he reads now.
# max() against the direct read at the call site, never additive — the two are
# different aims of the same rip.

# Puck.deflect_min_speed (test_bot_mirrors.gd), the receiver-relative pace above
# which a blade deflects instead of catching: a rip below it lands on the
# tape as a pass — no tip outcome exists.
const TIP_DEFLECT_MIN_SPEED_M_S: float = 22.0
# A tip point closer to the release than this is still on the shooter's own
# handle, not a mid-flight contact.
const TIP_MIN_ALONG_M: float = 0.6


static func tip_ev(
		release: Vector3,
		tip_man: Vector3,
		attacking_goal: Vector3,
		goalie_pos: Vector3,
		opponents: Array[Vector3],
		shot_speed_m_s: float,
		opponent_caps: Array = [],
		tip_caps: AISkaterCaps = null) -> float:
	if shot_speed_m_s < TIP_DEFLECT_MIN_SPEED_M_S:
		return 0.0
	# Shot line: release → net centre (the reactive tip steps ONTO this line,
	# so planning against it is self-consistent with the execution).
	var dx: float = attacking_goal.x - release.x
	var dz: float = attacking_goal.z - release.z
	var line_len: float = sqrt(dx * dx + dz * dz)
	if line_len < 0.001:
		return 0.0
	var hx: float = dx / line_len
	var hz: float = dz / line_len
	# Tip point: the tipper's foot on the line — where blade meets puck. Must
	# be a real mid-flight contact: past the shooter's own handle, short of
	# the goal mouth.
	var relx: float = tip_man.x - release.x
	var relz: float = tip_man.z - release.z
	var along: float = relx * hx + relz * hz
	if along <= TIP_MIN_ALONG_M or along >= line_len - 0.3:
		return 0.0
	var tip_pt := Vector3(release.x + hx * along, 0.0, release.z + hz * along)
	# P(blade contacts): the tipper's real stick reach + lateral close.
	var stick: float = AIPuckLane.LANE_DEFENDER_REACH_M
	var close: float = AIPuckLane.LANE_DEFENDER_CLOSE_SPEED_M_S
	if tip_caps != null:
		stick = tip_caps.stick_reach
		close = AIPuckLane.LANE_LATERAL_FRACTION * tip_caps.max_speed
	var speed: float = maxf(shot_speed_m_s, 1.0)
	var p_contact: float = AIPuckLane.lane_block_at(
			release.x, release.z, hx * speed, hz * speed, along / speed,
			tip_man.x, tip_man.z, 0.0, 0.0, stick, close)
	if p_contact <= 0.0:
		return 0.0
	# P(rip reaches him): the defenders' lane over the release→tip segment.
	var lane: float = AIPuckLane.lane_clear(release, tip_pt, opponents, speed, EMPTY_VEC3, opponent_caps)
	if lane <= 0.0:
		return 0.0
	# The redirect: a new release at the tip point holding the incoming pace (a
	# tip keeps the along-face glance), its line not picked.
	var redirect: float = AIShotValue.deflection(release, tip_pt, speed, attacking_goal,
			goalie_pos)
	if redirect <= 0.0:
		return 0.0
	return p_contact * lane * redirect * _shot_defender_terms(tip_pt, attacking_goal,
			goalie_pos if goalie_pos.is_finite() else attacking_goal, opponents, speed,
			opponent_caps)


# ── The shot, priced on the field ────────────────────────────────────────────
# AIShotValue supplies the shot's odds against today's goalie; the lane and the
# release contest are facts about DEFENDERS, not the goalie, so they are priced
# here.
#
# The keeper is at `keeper_pos` moving across at `keeper_vel_x` in `stance`, an
# AIShotOdds.Stance, facing `keeper_yaw` (AIShotValue.now); `keeper_pos` INF
# means square and set on the release (AIShotValue.set_keeper).
# `precomputed_quality` (>= 0) hands in the shot_quality a caller already has
# for these arguments.
static func score_shoot_value(
		shooter: Vector3,
		attacking_goal: Vector3,
		keeper_pos: Vector3,
		opponents: Array[Vector3],
		keeper_vel_x: float = 0.0,
		stance: int = AIShotOdds.Stance.UPRIGHT,
		shot_speed_m_s: float = AIBotMechanics.WRISTER_SHOT_SPEED_M_S,
		opponent_caps: Array = [],
		precomputed_quality: float = -1.0,
		keeper_yaw: float = NAN) -> float:
	if (shooter.z - attacking_goal.z) * -signf(attacking_goal.z) < 0.001:
		return 0.0
	var quality: float = precomputed_quality
	var keeper: Vector3 = keeper_pos
	if keeper.is_finite():
		shooter = AIGoalieModel.release_ahead_of_goalie(shooter, attacking_goal, keeper)
		if quality < 0.0:
			quality = AIShotValue.now(shooter, attacking_goal, keeper, keeper_vel_x, stance,
					keeper_yaw)
	else:
		if quality < 0.0:
			quality = AIShotValue.set_keeper(shooter, attacking_goal)
		keeper = AIGoalieModel.goalie_squared_pos(
				attacking_goal - Vector3(0.0, 0.0, signf(attacking_goal.z)
						* AIGoalieModel.GOALIE_RESTING_DEPTH_M), attacking_goal, shooter)
	if quality <= 0.0:
		return 0.0
	return quality * _shot_defender_terms(shooter, attacking_goal, keeper, opponents,
			shot_speed_m_s, opponent_caps)


# score_shoot_value's goalie half: the odds the shot beats the keeper, before
# any defender. Reads no defender, so one spot's is good against any defence
# (test_shot_quality_is_the_seams_goalie_half).
static func shot_quality(shooter: Vector3, attacking_goal: Vector3, keeper_pos: Vector3,
		keeper_vel_x: float = 0.0, stance: int = AIShotOdds.Stance.UPRIGHT) -> float:
	if keeper_pos.is_finite():
		return AIShotValue.now(
				AIGoalieModel.release_ahead_of_goalie(shooter, attacking_goal, keeper_pos),
				attacking_goal, keeper_pos, keeper_vel_x, stance)
	return AIShotValue.set_keeper(shooter, attacking_goal)


# The defenders' share of a shot from `shooter`: its lane past them to the open
# side of `keeper`, times the release contest on the wind-up.
static func _shot_defender_terms(shooter: Vector3, attacking_goal: Vector3,
		keeper: Vector3, opponents: Array[Vector3], shot_speed_m_s: float,
		opponent_caps: Array) -> float:
	var aim: Vector3 = AIShotAim.compute_open_net_aim(
			shooter, keeper, attacking_goal.z,
			GameRules.NET_HALF_WIDTH, AIGoalieModel.GOALIE_SHADOW_HALF_M)
	var lane: float = AIPuckLane.lane_clear(shooter, aim, opponents, shot_speed_m_s,
			EMPTY_VEC3, opponent_caps)
	if lane <= 0.0:
		return 0.0
	return lane * AIPuckLane.release_contest_clean(
			AIPuckLane.release_point_toward(shooter, attacking_goal), opponents, opponent_caps)


# A pass on the seam: its lane × the receiver's odds off the feed (the keeper at
# `keeper_pos` square on the passer as it leaves; INF, none replicated) × his
# shot's own lane and release contest. Every read of a pass prices it here —
# the carrier's, a defender's, a support or finisher spot — so offence and
# defence agree on what a feed is worth. `precomputed_lane` (>= 0) hands in the
# identical pass lane_clear a caller already ran; `precomputed_odds` (>= 0) the
# AIShotValue.feed it already has for these arguments.
static func score_pass_value(
		shooter: Vector3,
		receiver: Vector3,
		attacking_goal: Vector3,
		keeper_pos: Vector3,
		opponents: Array[Vector3],
		pass_speed_m_s: float = AIPuckLane.PASS_SPEED_M_S,
		opponent_caps: Array = EMPTY_CAPS,
		one_timer: bool = false,
		precomputed_lane: float = -1.0,
		precomputed_odds: float = -1.0) -> float:
	if _is_past_goal_line(receiver, attacking_goal):
		return 0.0
	if AINetObstacle.pass_lane_blocked_by_net(shooter, receiver):
		return 0.0
	var lane: float = precomputed_lane if precomputed_lane >= 0.0 \
			else AIPuckLane.lane_clear(shooter, receiver, opponents, pass_speed_m_s,
					EMPTY_VEC3, opponent_caps)
	if lane <= 0.0:
		return 0.0
	var odds: float = precomputed_odds if precomputed_odds >= 0.0 \
			else AIShotValue.feed(shooter, receiver, pass_speed_m_s, attacking_goal,
					keeper_pos, one_timer)
	if odds <= 0.0:
		return 0.0
	var keeper: Vector3 = keeper_pos if keeper_pos.is_finite() else attacking_goal
	return lane * odds * _shot_defender_terms(receiver, attacking_goal, keeper, opponents,
			AIBotMechanics.WRISTER_SHOT_SPEED_M_S, opponent_caps)


# ── Helpers ──────────────────────────────────────────────────────────────────


# True if `pos` is past the attacking goal line in the direction the
# attacking team is going (i.e. "behind the net" relative to the
# shooter). For Team 0 attacking -Z (attacking_goal.z = -26.65),
# "past" means z < -26.65; for Team 1 attacking +Z, z > +26.65.
static func _is_past_goal_line(pos: Vector3, attacking_goal: Vector3) -> bool:
	return (pos.z - attacking_goal.z) * signf(attacking_goal.z) > 0.0


# True when `pos` is on the attacking side of the attacking blue line — the
# offensive zone. Sign-folded for either attacking direction.
# `buffer` demands the position sit that much DEEPER than the line — the
# carrier's blue-line keep-out bands (retreat / reception) use it so "in the
# zone" can mean "in the zone with margin for the stick's reach".
static func in_offensive_zone(pos: Vector3, attacking_goal: Vector3,
		buffer: float = 0.0) -> bool:
	return pos.z * signf(attacking_goal.z) > GameRules.BLUE_LINE_Z + buffer


# ── Loose-puck races ─────────────────────────────────────────────────────────
# The head-start that turns a 50/50 loose-puck race into a near-sure recovery:
# a stride, expressed as the TIME a stride buys at reference pace, because the
# race below is run in time. A metre band saturates to 0 or 1 over a long chase.
const CHASE_CONTEST_MARGIN_M: float = 2.0
const CHASE_CONTEST_MARGIN_S: float = CHASE_CONTEST_MARGIN_M / AIArrival.SKATER_REF_SPEED_M_S


# Probability our team wins the race to a loose puck at `target` when our first
# man gets there at `our_t`: an ARRIVAL race against their first body there,
# with a contest band around a tie (CHASE_CONTEST_MARGIN_S). 1.0 uncontested.
#
# Momentum-honest, through time_to_arrive: nearest by ETA, never by metres — a
# body two metres nearer but skating the other way loses this race. Keep
# `our_t` on the same arrival model.
#
# `opp_vels` is index-matched to `opp_chasers`; omit it and every chaser races
# from rest, at the league reference build.
# `clock_error`: widen the contest band by the arrival clock's own error over
# the longer trip (AIArrival.ERROR_FRAC), for a race decided seconds from now.
static func arrival_race(target: Vector3, our_t: float, opp_chasers: Array[Vector3],
		opp_vels: Array[Vector3] = EMPTY_VEC3, clock_error: bool = false) -> float:
	if opp_chasers.is_empty():
		return 1.0
	var opp_t: float = first_arrival(target, opp_chasers, opp_vels)
	var band: float = CHASE_CONTEST_MARGIN_S
	if clock_error:
		band += AIArrival.ERROR_FRAC * minf(maxf(our_t, opp_t), 1e6)
	return clampf(0.5 + (opp_t - our_t) / (2.0 * band), 0.0, 1.0)


# Soonest any of `chasers` reaches `target`. `vels` is used only when it is
# index-matched to `chasers`, so callers that hold no velocities pass EMPTY_VEC3
# and every body races from rest.
#
# Exact prune: time_to_arrive only ever ADDS time to `straight_line_distance /
# cap`, so a chaser whose bound is already beaten cannot win. It matters
# because the possession read races every entry it prices.
static func first_arrival(target: Vector3, chasers: Array[Vector3],
		vels: Array[Vector3]) -> float:
	var has_vels: bool = vels.size() == chasers.size()
	var vmax: float = maxf(AIArrival.SKATER_REF_SPEED_M_S, AIArrival.MIN_TRAVEL_SPEED_M_S)
	var best: float = INF
	for i: int in chasers.size():
		if chasers[i].distance_to(target) >= best * vmax:
			continue
		best = minf(best, AIArrival.time_to_arrive(chasers[i], target,
				vels[i] if has_vels else Vector3.ZERO))
	return best


# How far (m) from the net mouth the goalie still counts as HOME for the shot
# skips its readers make outside the zone; beyond it a direct shot must be
# priced from anywhere on the rink.
const THREAT_GOALIE_HOME_M: float = AIGoalieModel.GOALIE_HOME_M

# ── Transition-exposure: the counter-rush cost (5v5-gated at the caller) ─────
# The turnover cost prices possession AT the loss point
# (AICarrierField.turnover_cost), so a loss deep in the O-zone
# reads ~0 there while the true cost is the counter-rush into the ice the carrier
# vacated. This is the additive second half:
#   loss_prob × shot(counter_point | covering set) × delay_discount(t_counter)
# counter_point is our slot (where a rush shoots from); t_counter the fastest
# opponent's collect-and-carry there at his real Speed cap; the covering set
# every teammate, and the carrier recovering from the candidate, who beats him
# home, standing at the goal-side cover anchor (AIThreatAssignment.cover_anchor).
# Teammates race at the league reference speed (their caps are not in scope).
# One-up-one-back falls out with no pairing rule: a partner holding the point
# beats any counter home.

# Scratch for the covering-defender positions (caller-owned pattern; this
# is per-candidate hot-ish path at the AI dispatch cadence).
static var _scratch_counter_cover: Array[Vector3] = []


# The counter point a rush shoots from, and each teammate's standing-start
# ETA to it — candidate-invariant inputs the carrier precomputes once per
# compete (fill_counter_cover_etas) instead of re-racing per candidate.
static func counter_point_for(our_net: Vector3) -> Vector3:
	var own_dir: float = signf(our_net.z)
	return Vector3(0.0, 0.0, our_net.z - own_dir * GameRules.SLOT_DIST_M)


# A body covers a counter when he beats it home WITH TIME TO SET — the same
# brake-to-arrive margin AIRoleSlots5.assign charges our line's post deadlines
# (stride-for-stride beside the rush is chasing, not covering). League-paced,
# like the mate ETAs it pads.
const COUNTER_SET_MARGIN_S: float = GameRules.DEFAULT_SKATER_MAX_SPEED_M_S \
		/ AISteering.ARRIVAL_BRAKE_DECEL_M_S2


# Whether a teammate (fill_counter_cover_etas' `mate_etas`) already covers a
# counter reaching the counter point at `t_counter`.
static func counter_covered(t_counter: float, mate_etas: Array[float]) -> bool:
	for eta: float in mate_etas:
		if eta + COUNTER_SET_MARGIN_S <= t_counter:
			return true
	return false


static func fill_counter_cover_etas(our_net: Vector3,
		teammates: Array[Vector3], out_etas: Array[float]) -> void:
	var cp: Vector3 = counter_point_for(our_net)
	out_etas.clear()
	for tm: Vector3 in teammates:
		out_etas.append(tm.distance_to(cp) / AIArrival.SKATER_REF_SPEED_M_S)


# Each opponent's carry home to the counter point from rest, at his Speed cap:
# what the pass-forward leg races, and the same for every loss point, so a
# compete fills it once (counter_time's `opp_home`).
static func fill_counter_opp_home(our_net: Vector3, opponents: Array[Vector3],
		opponent_caps: Array, out_home: Array[float]) -> void:
	var cp: Vector3 = counter_point_for(our_net)
	var has_caps: bool = opponent_caps.size() == opponents.size()
	out_home.clear()
	for j: int in opponents.size():
		out_home.append(AIArrival.time_to_arrive(opponents[j], cp, Vector3.ZERO,
				_opponent_speed(opponent_caps, j, has_caps)))


static func counter_rush_cost(
		loss_point: Vector3,
		loss_prob: float,
		our_net: Vector3,
		our_goalie_pos: Vector3,
		teammates: Array[Vector3],
		self_recover_pos: Vector3,
		self_max_speed: float,
		opponents: Array[Vector3],
		opponent_vels: Array[Vector3],
		opponent_caps: Array,
		mate_etas: Array[float] = [],
		threat_by_cover: Array[float] = [],
		in_xg: bool = false,
		opp_home: Array[float] = []) -> float:
	if not loss_point.is_finite() or loss_prob <= 0.0 or opponents.is_empty():
		return 0.0
	return counter_rush_cost_at(
			counter_time(loss_point, our_net, opponents, opponent_vels, opponent_caps,
					opp_home),
			loss_prob, our_net, our_goalie_pos, teammates, self_recover_pos,
			self_max_speed, mate_etas, threat_by_cover, in_xg)


# When the fastest counter off a loss at `loss_point` reaches the counter point:
# collect and carry, or collect and feed an outlet already ahead. INF when no
# opponent can. `opp_home` is fill_counter_opp_home's, or empty to race it here.
static func counter_time(loss_point: Vector3, our_net: Vector3,
		opponents: Array[Vector3], opponent_vels: Array[Vector3],
		opponent_caps: Array, opp_home: Array[float] = []) -> float:
	var counter_point: Vector3 = counter_point_for(our_net)

	# Fastest opponent: collect the loss, then carry to the counter point at
	# his top speed.
	var carry_dist: float = loss_point.distance_to(counter_point)
	var t_counter: float = INF
	var t_collect_best: float = INF
	var has_vels: bool = opponent_vels.size() == opponents.size()
	var has_caps: bool = opponent_caps.size() == opponents.size()
	for i: int in opponents.size():
		var speed: float = _opponent_speed(opponent_caps, i, has_caps)
		var vel: Vector3 = opponent_vels[i] if has_vels else Vector3.ZERO
		var t_collect: float = AIArrival.time_to_arrive(opponents[i], loss_point, vel, speed)
		if t_collect < t_collect_best:
			t_collect_best = t_collect
		var t: float = t_collect + carry_dist / maxf(speed, 0.001)
		if t < t_counter:
			t_counter = t
	if t_counter == INF:
		return INF
	# PASS-FORWARD leg: the counter can hit an outlet already AHEAD. From the
	# fastest collect, price the hardest feed to each other opponent and HIS
	# carry home from rest, and let the min compete with the lone-carrier time.
	var has_home: bool = opp_home.size() == opponents.size()
	for j: int in opponents.size():
		# The feed only helps when the outlet is genuinely AHEAD of the
		# lug — skip receivers whose own carry isn't shorter.
		if opponents[j].distance_to(counter_point) >= carry_dist:
			continue
		var home: float = opp_home[j] if has_home else AIArrival.time_to_arrive(
				opponents[j], counter_point, Vector3.ZERO,
				_opponent_speed(opponent_caps, j, has_caps))
		var t_pf: float = t_collect_best \
				+ loss_point.distance_to(opponents[j]) \
						/ GameRules.DEFAULT_WRISTER_POWER_MAX_M_S \
				+ home
		if t_pf < t_counter:
			t_counter = t_pf
	return t_counter


static func _opponent_speed(opponent_caps: Array, i: int, has_caps: bool) -> float:
	if has_caps:
		var caps: AISkaterCaps = opponent_caps[i]
		if caps != null:
			return caps.max_speed
	return AIArrival.SKATER_REF_SPEED_M_S


# counter_rush_cost once the counter's time `t_counter` is known: who beats it
# home, and what the shot from the counter point is worth past them.
static func counter_rush_cost_at(
		t_counter: float,
		loss_prob: float,
		our_net: Vector3,
		our_goalie_pos: Vector3,
		teammates: Array[Vector3],
		self_recover_pos: Vector3,
		self_max_speed: float,
		mate_etas: Array[float] = [],
		threat_by_cover: Array[float] = [],
		in_xg: bool = false) -> float:
	if t_counter == INF or loss_prob <= 0.0:
		return 0.0
	var counter_point: Vector3 = counter_point_for(our_net)
	var setup_margin: float = COUNTER_SET_MARGIN_S
	var cover_anchor: Vector3 = AIThreatAssignment.cover_anchor(
			counter_point, our_net)
	_scratch_counter_cover.clear()
	if mate_etas.size() == teammates.size():
		# Precomputed teammate races (fill_counter_cover_etas) — the hot
		# per-candidate path.
		for eta: float in mate_etas:
			if eta + setup_margin <= t_counter:
				_scratch_counter_cover.append(cover_anchor)
	else:
		for tm: Vector3 in teammates:
			if tm.distance_to(counter_point) / AIArrival.SKATER_REF_SPEED_M_S \
					+ setup_margin <= t_counter:
				_scratch_counter_cover.append(cover_anchor)
	if self_recover_pos.is_finite() \
			and self_recover_pos.distance_to(counter_point) \
					/ maxf(self_max_speed, 0.001) + setup_margin <= t_counter:
		_scratch_counter_cover.append(cover_anchor)

	# score_shoot_value directly, not a possession read: the counter point IS a shot
	# location (the slot), and the covered-vs-open signal this term exists to
	# read is the covering set's block on that shot.
	#
	# Memo by cover count: within one compete the only thing a candidate
	# changes here is HOW MANY bodies stand at the anchor, so the caller may
	# pass a -1-seeded scratch (`threat_by_cover`, indexed by cover count,
	# reset each compete).
	#
	# `in_xg` is the carrier's unit: the shot against a keeper set and square,
	# as AIPossessionValue prices every shot. A memo must only ever hold one.
	var cover_count: int = _scratch_counter_cover.size()
	var threat: float = -1.0
	if cover_count < threat_by_cover.size():
		threat = threat_by_cover[cover_count]
	if threat < 0.0:
		if in_xg:
			threat = score_shoot_value(
					counter_point, our_net, Vector3.INF, _scratch_counter_cover)
		else:
			threat = score_shoot_value(
					counter_point, our_net, our_goalie_pos, _scratch_counter_cover)
		if cover_count < threat_by_cover.size():
			threat_by_cover[cover_count] = threat
	return loss_prob * threat * delay_discount(t_counter)


