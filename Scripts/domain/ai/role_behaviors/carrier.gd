class_name AIRoleCarrier
extends RefCounted

const _PhysicsConstants: GDScript = preload("res://Scripts/game/constants.gd")

# CARRIER role behavior: the puck-carrying utility AI. Scores SHOOT (wrister),
# PASS (AICarrierPassSearch) and CARRY (AICarrierCarrySearch) on one scale every
# PICK_ACTION_PERIOD_TICKS ticks. The searches all read this carrier's
# AICarrierField; this file owns the compete — the shot sweep, the
# protect / evade reads, the bars, the argmax and its commitment.
# Hysteresis on the current fire intent stops flicker during pre-aim; CARRY gets
# none, because stand-still's shot branch IS the shoot-now score and fire must
# win that tie.
#
# Stateful: SkaterAgentStateMachine owns one instance per agent, calls
# decide(ctx) every CARRY-state tick, then reads the public fields below
# (intended_action and the per-intent targets) and maps intended_action onto
# its own State enum.

# ── Intent enum ──────────────────────────────────────────────────────────────
# Plain ints, not the state machine's State values (its match on
# intended_action maps them), so this file unit-tests without it.
const INTENT_CARRY: int = 0
const INTENT_SHOOT: int = 1
const INTENT_PASS: int = 3
# The rim PASS's release — fire the puck to a location (no receiver). The state
# machine maps it onto a PASS_PRESSED release aimed at `dump_target`.
const INTENT_DUMP: int = 5
# How far down the rim's bearing its aim point is placed. The charged release
# converges its blade's side offset onto this point, so a far point keeps the
# puck parallel to the searched bearing.
const RIM_AIM_STANDOFF_M: float = 20.0

# ── Giveaway floors: least value worth releasing the puck for ────────────────
# In the seam's xG currency; see Scripts/domain/ai/CLAUDE.md → "One currency
# across the carrier's compete".
#
# A SHOT hands the puck over unless it goes in, so it must out-value the
# possession. A clear-lane shot straight on reaches 0.05 at about 14 m: nothing
# from beyond the top of the circles unless a displaced keeper lifts it (the
# seam does not model screens).
const SHOT_MIN_VALUE: float = 0.05
# A PASS that connects keeps possession, and its odds of not connecting are
# already priced by the lane term, so it is held only to rejecting a release
# into nothing — a numerical residual on a dead lane. (A receiver at centre ice
# is worth ~0.017 as a shooter and is still the right play.)
const PASS_MIN_VALUE: float = 0.02

# ── Settle doubt ─────────────────────────────────────────────────────────────
# The fraction by which a fresh carrier raises every ACTIVE option's giveaway
# bar (ctx.settle_penalty_frac = 0.5 doubles it), decaying as exp(-t/τ) over the
# possession. See Scripts/domain/ai/CLAUDE.md → "Hesitation is a raised bar".
# The decay never reaches exactly zero: harmless against an absolute bar, but it
# would not be inside the fire-vs-carry compete, where stand-still ties fire
# exactly and any residual penalty would suppress firing forever.
func _settle_penalty(ctx: RoleContext) -> float:
	if ctx.settle_penalty_frac <= 0.0:
		return 0.0
	return ctx.settle_penalty_frac * exp(
			-_settle_elapsed_s / maxf(ctx.settle_penalty_tau_s, 0.001))


# Move `value` away from being chosen by `penalty` of its own magnitude: a
# positive score shrinks toward zero, a negative one deepens. Higher is better
# everywhere this is read, so the one form handicaps both signs.
static func _settle_handicap(value: float, penalty: float) -> float:
	return value - penalty * absf(value)

# Minimum forward distance (m) the PUCK must sit in front of the goal-line plane
# for a direct shot to be scored at all — on/behind the line the mouth faces
# away and the only play is a wrap/walk-out carry. Feel gate; a walk-out shooter
# is well past this by release.
const SHOT_MIN_FORWARD_OF_LINE_M: float = 0.3


# ── Where the shot is held (shoot-now eval) ──────────────────────────────────
# The share of pace the winning hold's load gives the committed shot.
var _shot_sample_share: float = 1.0
# True when the winning shoot read is the TIP rip (AIActionScoring.tip_ev):
# fired flat at full pace THROUGH the net-front teammate's blade at the net
# centre — the commit path aims it there instead of at a direct-model hole.
var _shot_sample_is_tip: bool = false
# The puck's spot off the body (world XZ) the last shoot-now sweep's winner
# fires from. Fresh every eval, so the state machine's fire-tracking carry
# holds the puck there while a shot look is live; ZERO until a sweep scores.
var shoot_now_hold: Vector3 = Vector3.ZERO
# ── Smart-ping obedience ─────────────────────────────────────────────────────
# EV multipliers a live human ping applies inside the normal compete — a
# tactical ORDER, not an evaluation curve. A bias rather than a force: the
# giveaway floors still veto a hopeless order (a zero shot stays zero, a dead
# lane stays dead), but any reasonable read wins, so the bot visibly obeys.
const PING_SHOOT_EV_MULT: float = 3.0
# ── Scoring constants ────────────────────────────────────────────────────────
# Re-evaluation cadence. CARRY runs every physics tick, but the compete is far
# too costly to run that often; ~30 Hz is plenty — pre-aim convergence gates the
# actual transition, and humans react in 250 ms+.
const PICK_ACTION_PERIOD_TICKS: int = _PhysicsConstants.PHYSICS_TICK / 30   # ~30 Hz re-eval
# Open-ice LOD (see _arm_pick_cooldown): with no opponent inside this radius and
# the committed answer CARRY, the compete re-arms at PERIOD × MULT (~10 Hz). The
# radius is a closing-speed margin: two skaters closing head-on cover ~18 m/s,
# so a threat first appearing here is ~0.36 s from a stick on the puck —
# several extended periods away.
const OPEN_ICE_LOD_RADIUS_M: float = 8.0
const OPEN_ICE_LOD_PERIOD_MULT: int = 3



# ── Puck-protect directionality (see _fill_protect_opponents) ────────────────
# A defender projected (at the evasion horizon) more than this far behind the
# carrier along the netward line is already screened by the carrier's body and
# drops out of the protect read, so the carrier squares to the net the instant it
# beats its man instead of shielding a trailing checker. Body-scale slack: a
# defender even with or beside the carrier still earns the shield.
const PROTECT_SCREEN_BEHIND_M: float = 0.75


# ── Persistent decision state ────────────────────────────────────────────────
# What the carrier currently wants to do. CARRY = no fire intent;
# fire intents persist across cooldown ticks so pre-aim keeps
# driving toward the chosen action.
var intended_action: int = INTENT_CARRY

# Seconds we've been HOLDING the puck for a developing feed (see
# _pick_commit_phase). Feeds the delay discount so a wait that never pays off
# self-extinguishes, with no fixed timeout.
var _hold_elapsed_s: float = 0.0

# Seconds since this possession began — the clock the settle doubt decays on
# (see _settle_penalty). Armed to 0 on the first decide() after reset(), which
# marks a possession loss (or spawn). clear_intent() does NOT re-arm it: a
# press-state bail back to CARRY is the same possession.
var _settle_arm_pending: bool = true
var _settle_elapsed_s: float = 0.0

# Set when intent commits to PASS (or to a rim, released as a DUMP). Consumed by
# the state machine entering PASS_PRESSED. -1 = no current pass target.
var pass_target_peer_id: int = -1

# LAUNCH speed for the chosen PASS (AIPuckLane.pass_launch_speed): set so
# the puck arrives on the teammate's tape at the magnet pace, friction-compensated
# by distance. The state machine maps this to the wrister charge fraction it winds
# up to, and leads the pass at this speed.
var pass_target_speed: float = AIPuckLane.PASS_SPEED_M_S

# Set alongside pass_target_peer_id when the chosen PASS is the LOW-loft saucer
# variant (see AICarrierPassSearch). The state machine reads it entering
# PASS_PRESSED to set the release loft; pass_target_speed carries the saucer's
# (possibly reduced) launch pace.
var pass_should_saucer: bool = false

# Set when intent commits to SHOOT: the loft rung (ShotMechanics.ELEVATION_*) of
# the shot the field picked (AIShotOdds.pick_shot_now).
# Read by the state machine's press-state handlers to drive the release loft.
var shot_loft_level: int = ShotMechanics.ELEVATION_FLAT

# Set alongside shot_loft_level: the world aim POINT of that same shot (on the
# net plane). INF until a SHOOT commit picks one.
var shot_aim_point: Vector3 = Vector3.INF

# Set alongside shot_loft_level: the release power fraction (0..1 over this
# bot's wrister band). Always full power — the contact-point solve adapts the
# launch angle, not the pace, and the load caps what full power carries.
var shot_power_t: float = 1.0

# Set alongside shot_loft_level: where the puck sits off the body (world XZ) at
# the press of the winning hold, and the share of pace the load gives it there.
# The state machine carries the puck to it and presses once the load is there.
var shot_hold_offset: Vector3 = Vector3.ZERO
var shot_hold_share: float = 1.0

# Cached carry destination from the most recent re-eval. Read by the
# state machine to drive steering during CARRY.
var last_carry_anchor: Vector3 = Vector3.ZERO
# The rolled near move that carry is (AICarryRollout.Move; -1 when the carry is
# steered to last_carry_anchor instead): the stick and the brake to hold until
# the next re-eval.
var carry_move: int = -1
var carry_stick: Vector2 = Vector2.ZERO
var carry_brake: bool = false

# Set when intent commits to DUMP: the world spot to fire the rim PASS
# (AIRimPass) at. A rim is chosen as a pass and released as a dump, because its
# aim is a bearing into the boards rather than the receiver. Read by the state
# machine's dump release.
var dump_target: Vector3 = Vector3.INF
# Launch pace (m/s) the rim fires at: its searched pace.
var dump_launch_speed: float = AIPuckLane.PASS_SPEED_M_S

# ── Puck-protect mirror (read by the state machine's carry blade aim) ────────
# Where in the blade's handling envelope the puck is safest right now, as an
# OFFSET from the body (the state machine re-applies it to the live body
# position each tick), and the shield WEIGHT — how far the blade should swing
# from the presented-forward carry toward that seam (0 = keep the forward carry;
# 1 = pull the puck fully to the seam). The weight is the safety the shield
# buys: the seam's clearance less the forward spot's, so it is nonzero only when
# the forward puck is covered AND a safer seam exists. Zeroed while
# ctx.protects_the_puck is false and on possession loss. Refreshed every re-eval;
# staleness between re-evals is absorbed by the body-relative offset and the
# mouse motion smoothing.
var protect_offset: Vector3 = Vector3.ZERO
var protect_gain: float = 0.0
# Metres of room the PRESENTED-FORWARD puck has from every un-beaten defender's
# momentum-projected stick over the evasion horizon — negative when somebody can
# get a blade on it. Published because it is also the state machine's
# square-to-net facing read (is there still a man to beat?), so unlike the
# shield it is NOT gated on ctx.protects_the_puck: facing is a posture every
# tier holds. EVADE_SAFE_MARGIN_M (what reach_clearance reports against nobody)
# until first computed, so a fresh carrier squares up.
var forward_puck_clearance: float = AICarrySpace.EVADE_SAFE_MARGIN_M

# ── Throttle ─────────────────────────────────────────────────────────────────
var _pick_action_cooldown: int = 0
# Physics ticks elapsed since the last re-eval (accumulated per decide() call by
# ctx.dispatch_period_ticks), so the hold clock advances in real time at every
# dispatch cadence. Reset when a commit runs.
var _ticks_since_pick: int = 0

# ── Compete time-slice ───────────────────────────────────────────────────────
# The full re-eval is the host's worst per-tick AI spike, so steady-state
# re-evals split across two consecutive dispatches: the FIRE phase
# (_pick_fire_phase) at cooldown expiry, the COMMIT phase (_pick_commit_phase)
# on the NEXT dispatch against a fresh snapshot. The cost is staleness, not
# cadence: at commit the fire scores are one dispatch old — well inside the
# ~135 ms windup the fired-puck lanes are already priced across — and the
# post-commit cooldown is shortened by the dispatch the commit consumed.
# Single-call full evals still run for:
#   - the first eval of a possession (reset()) and the first after a
#     press-state bail (clear_intent()): no plan exists yet, and that contested
#     moment is where a dispatch of commit latency would show;
#   - tiers whose dispatch span already covers the eval period (slicing
#     would halve their decision cadence).
var _commit_phase_pending: bool = false
var _full_eval_pending: bool = true
# Fire-phase products consumed by the commit phase (instance fields so a
# sliced eval hands them across the dispatch boundary):
var _phase_current_safety: float = 0.0
var _phase_shoot_score: float = -1.0
var _phase_best_pass_peer: int = -1
var _phase_best_pass_score: float = -1.0
var _phase_best_pass_saucer: bool = false
var _phase_best_pass_frac: float = 1.0
# The winning pass's rim launch bearing, ZERO when it is a straight feed.
var _phase_best_pass_rim_dir: Vector3 = Vector3.ZERO
# The winning pass's rim pace, carried to the release with its bearing.
var _phase_best_pass_rim_pace: float = 0.0
# The field's shot from this eval's base release (_pick_fire_phase): the holds
# are solved toward its aim, and a committed SHOOT fires it.
var _shot_pick := AIShotOdds.Pick.new()

# What the carrier sees this phase (AICarrierField), refilled at each phase's
# head, and the searches that read it.
var _field := AICarrierField.new()
var _pass := AICarrierPassSearch.new(_field)
var _carry := AICarrierCarrySearch.new(_field)

# Directional-filtered opponents for the puck-protect read: the full opponent
# set minus defenders the carrier's body already screens (see
# PROTECT_SCREEN_BEHIND_M). Kept separate from _field.opponents so the shot /
# pass / carry lanes still see every defender. Index-matched triple, refilled
# every re-eval by _fill_protect_opponents.
var _scratch_protect_opponents: Array[Vector3] = []
var _scratch_protect_vels: Array[Vector3] = []
var _scratch_protect_caps: Array[AISkaterCaps] = []
# Reused decision object returned by decide(), so the per-dispatch call doesn't
# allocate a RefCounted.
var _decision: RoleDecision = RoleDecision.new()

# ── Debug readout ────────────────────────────────────────────────────────────
# Populated every re-eval; the state machine forwards these to its own debug_*
# fields for the floating label.
var debug_shoot_score: float = 0.0
var debug_pass_score: float = 0.0
var debug_pass_peer_id: int = 0
var debug_carry_score: float = 0.0
var debug_carry_pos: Vector3 = Vector3.ZERO


# ── Public API ───────────────────────────────────────────────────────────────

# Top-level entry, called once per AI dispatch and re-evaluating at most once per
# PICK_ACTION_PERIOD_TICKS. Updates the public fields the state machine reads.
# The return is the reused `_decision` with only target_position
# (= last_carry_anchor) filled; the state machine's live path discards it.
func decide(ctx: RoleContext) -> RoleDecision:
	# Each call spans this many physics ticks; draining the cooldown by the real
	# span keeps the re-eval cadence in wall time at every difficulty tier.
	var step_ticks: int = maxi(1, ctx.dispatch_period_ticks)
	if _settle_arm_pending:
		_settle_arm_pending = false
		_settle_elapsed_s = 0.0
	else:
		_settle_elapsed_s += float(step_ticks) / float(_PhysicsConstants.PHYSICS_TICK)
	_ticks_since_pick += step_ticks
	if _commit_phase_pending:
		# Second dispatch of a sliced re-eval (see _commit_phase_pending). The
		# cooldown is shortened by the dispatch this phase consumed, so commits
		# land at the single-call cadence.
		_commit_phase_pending = false
		_pick_commit_phase(ctx, true)
		_arm_pick_cooldown(ctx, maxi(PICK_ACTION_PERIOD_TICKS - step_ticks, 0))
		_ticks_since_pick = 0
	elif _pick_action_cooldown <= 0:
		if _full_eval_pending or step_ticks >= PICK_ACTION_PERIOD_TICKS:
			# reads _ticks_since_pick for the hold-clock advance
			_full_eval_pending = false
			_pick_action(ctx)
			_arm_pick_cooldown(ctx, PICK_ACTION_PERIOD_TICKS)
			_ticks_since_pick = 0
		else:
			_pick_fire_phase(ctx)
			_commit_phase_pending = true
	else:
		_pick_action_cooldown -= step_ticks

	_decision.target_position = last_carry_anchor
	return _decision


# Post-commit cooldown from `base_ticks` (the eval period, less any dispatch a
# sliced eval's commit phase already consumed), extended by the open-ice LOD
# (see OPEN_ICE_LOD_RADIUS_M) when the argmax answered CARRY with nobody near.
# Fire/pass intents keep the full cadence — their follow-through is
# timing-critical.
func _arm_pick_cooldown(ctx: RoleContext, base_ticks: int) -> void:
	_pick_action_cooldown = base_ticks
	if intended_action != INTENT_CARRY:
		return
	var lod_sq: float = OPEN_ICE_LOD_RADIUS_M * OPEN_ICE_LOD_RADIUS_M
	for opp: Vector3 in _field.opponents:
		if opp.distance_squared_to(ctx.self_pos) < lod_sq:
			return
	_pick_action_cooldown = base_ticks \
			+ PICK_ACTION_PERIOD_TICKS * (OPEN_ICE_LOD_PERIOD_MULT - 1)


# Clear all carrier state. Called by the state machine when leaving
# CARRY for OFF_PUCK / CHASE_PUCK (puck lost). Forces a fresh re-eval
# next time the bot enters CARRY.
func reset() -> void:
	intended_action = INTENT_CARRY
	pass_target_peer_id = -1
	pass_target_speed = AIPuckLane.PASS_SPEED_M_S
	pass_should_saucer = false
	shot_loft_level = ShotMechanics.ELEVATION_FLAT
	shot_aim_point = Vector3.INF
	shot_power_t = 1.0
	shot_hold_offset = Vector3.ZERO
	shot_hold_share = 1.0
	shoot_now_hold = Vector3.ZERO
	last_carry_anchor = Vector3.ZERO
	carry_move = -1
	dump_target = Vector3.INF
	dump_launch_speed = AIPuckLane.PASS_SPEED_M_S
	protect_offset = Vector3.ZERO
	protect_gain = 0.0
	forward_puck_clearance = AICarrySpace.EVADE_SAFE_MARGIN_M
	_hold_elapsed_s = 0.0
	_pick_action_cooldown = 0
	_ticks_since_pick = 0
	# A half-finished sliced eval priced a puck we no longer hold.
	_commit_phase_pending = false
	_full_eval_pending = true
	_settle_arm_pending = true
	_settle_elapsed_s = 0.0
	_carry.reset()


# Clear just the persistent intent (not last_carry_anchor / debug). Called by
# the state machine when committing to a press state, so the next CARRY entry
# re-evaluates from scratch. Does NOT re-arm the settle clock — a press bail
# back to CARRY is the same possession.
func clear_intent() -> void:
	intended_action = INTENT_CARRY
	pass_target_peer_id = -1
	pass_target_speed = AIPuckLane.PASS_SPEED_M_S
	pass_should_saucer = false
	dump_target = Vector3.INF
	dump_launch_speed = AIPuckLane.PASS_SPEED_M_S
	_pick_action_cooldown = 0
	_ticks_since_pick = 0
	# The next decide() answers in one call: a press bail is a timing-critical
	# seam with no live intent.
	_commit_phase_pending = false
	_full_eval_pending = true


# ── Implementation ──────────────────────────────────────────────────────────

# The whole compete in one call: both phases back-to-back (see
# _commit_phase_pending for when decide() slices them instead).
func _pick_action(ctx: RoleContext) -> void:
	_pick_fire_phase(ctx)
	_pick_commit_phase(ctx, false)


# FIRE phase of the compete: opponent lists, the evasion / protect reads, the pass-option cache, and the SHOOT + PASS scoring. Leaves
# its products in the _phase_* / _shot_sample_* fields (plus the
# _scratch_* buffers) for _pick_commit_phase.
func _pick_fire_phase(ctx: RoleContext) -> void:
	var snapshot: WorldSnapshot = ctx.snapshot
	var self_pos: Vector3 = ctx.self_pos
	var attacking_goal: Vector3 = ctx.attacking_goal_pos

	_field.fill(ctx)

	# Our current possession safety, read as EVADABILITY — the clearance at the
	# best seam we could handle the puck into — so pressure we can dance out of
	# doesn't read as danger while a stick on the puck does. Feeds the hold's
	# keep-probability in the commit phase.
	var cur_puck_pos: Vector3 = AICarrierField.puck_pos_at(self_pos, attacking_goal)
	var evade_seam: Vector3 = AICarrySpace.best_evade_point(
			cur_puck_pos, ctx.self_velocity, _field.opponents, _field.opponent_vels,
			ctx.self_handle_reach, _field.opponent_caps)
	_phase_current_safety = AICarrySpace.clearance_to_safety(
			AICarrySpace.reach_clearance(evade_seam, AICarrySpace.EVADE_HORIZON_S,
					_field.opponents, _field.opponent_vels, _field.opponent_caps))

	# Puck-protect read (see protect_offset / protect_gain) against the
	# directional opponent set (see PROTECT_SCREEN_BEHIND_M). Pure stick work:
	# steering and the carry destination are untouched. The forward-puck
	# clearance runs for EVERY tier (see forward_puck_clearance); only the seam
	# work below is gated.
	_fill_protect_opponents(ctx)
	var horizon: float = AICarrySpace.EVADE_HORIZON_S
	var fwd_spot: Vector3 = AICarrierField.puck_pos_at(
			self_pos + ctx.self_velocity * horizon, attacking_goal)
	forward_puck_clearance = AICarrySpace.reach_clearance(fwd_spot, horizon,
			_scratch_protect_opponents, _scratch_protect_vels,
			_scratch_protect_caps)
	if ctx.protects_the_puck:
		var fwd_safety: float = AICarrySpace.clearance_to_safety(
				forward_puck_clearance)
		# HOW MUCH to shield and WHERE to put the puck are answered by two seams
		# (see best_handle_protect_point). The WEIGHT reads the MAX-clearance
		# seam — the safety the best available shield buys.
		var max_seam: Vector3 = AICarrySpace.best_handle_protect_point(
				self_pos, ctx.self_velocity, _scratch_protect_opponents,
				_scratch_protect_vels, ctx.self_handle_reach, _scratch_protect_caps)
		# best_handle_protect_point projects the body to the same horizon, so
		# proj + offset is the seam's world point.
		var seam_world: Vector3 = self_pos + ctx.self_velocity * horizon + max_seam
		var seam_safety: float = AICarrySpace.clearance_to_safety(
				AICarrySpace.reach_clearance(seam_world, horizon,
						_scratch_protect_opponents, _scratch_protect_vels,
						_scratch_protect_caps))
		protect_gain = clampf(seam_safety - fwd_safety, 0.0, 1.0)
		# …and the DIRECTION is the least-committal seam that is still safe,
		# directed at the presented-forward spot, so the blade goes no further off
		# the play line than the safety requires.
		protect_offset = AICarrySpace.best_handle_protect_point(
				self_pos, ctx.self_velocity, _scratch_protect_opponents,
				_scratch_protect_vels, ctx.self_handle_reach,
				_scratch_protect_caps, fwd_spot)
	else:
		protect_gain = 0.0
		protect_offset = Vector3.ZERO

	_field.fill_receivers(ctx, cur_puck_pos)

	# SHOOT is scored at the projected RELEASE: the puck leaves the blade a
	# wind-up after the intent commits, so a bot rushing into the slot scores
	# the spot it will release from — which also lets it start the wind-up early.
	var self_velocity: Vector3 = ctx.self_velocity
	var horizontal_velocity: Vector3 = Vector3(self_velocity.x, 0.0, self_velocity.z)
	# Where the goalie actually is: a body the release can't cross.
	var goalie_now: Vector3 = AICarrierField.goalie_now(ctx)
	# The release ref is the PUCK's current spot (up to a stick's reach off the
	# body) led by our body velocity — in tight, a real angle change around the
	# goalie. Using it as the keeper's tracking target too is slightly generous
	# to him (his smoothing rides the body line), the safe side of that asymmetry.
	var puck_now: Vector3 = self_pos
	if ctx.snapshot.puck_state != null:
		puck_now = Vector3(
				ctx.snapshot.puck_state.position.x, 0.0,
				ctx.snapshot.puck_state.position.z)
	var wrister_base_release: Vector3 = puck_now \
			+ horizontal_velocity * AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S
	# No shot when the PUCK ITSELF is on/behind the goal line. Gate on the real
	# puck, not the projection: score_shoot clamps a behind-the-goalie release to
	# a jam point in FRONT of him, so a projected blade landing a hair in front
	# scores a phantom point-blank open net.
	var puck_forward_of_line: float = (puck_now.z - attacking_goal.z) \
			* -signf(attacking_goal.z)
	var shot_from_behind_line: bool = puck_forward_of_line <= SHOT_MIN_FORWARD_OF_LINE_M

	# ...and no shot at all from OUTSIDE the attacking zone while the keeper is
	# HOME: at that range he is square long before the puck arrives, so the shot
	# is dead by score_shoot's own coverage math (the same proof
	# AIPossessionValue.threat_of_carrier and value_at run). Gating it, rather than leaving it
	# to SHOT_MIN_VALUE, guarantees the fire hysteresis and the ping SHOOT bias
	# have no score to lift. A DISPLACED or PULLED keeper voids the proof — an
	# empty net genuinely scores from centre ice — so this is not a blanket zone
	# gate.
	var shot_unavailable: bool = shot_from_behind_line \
			or (not AIActionScoring.in_offensive_zone(self_pos, attacking_goal)
					and goalie_now.distance_to(attacking_goal)
							< AIActionScoring.THREAT_GOALIE_HOME_M)

	# Top-level SHOOT: the hold sweep over AIShotHolds (the puck where it is, the
	# loaded pocket, a reach to either side of the shot line). Each hold prices
	# its release at the pace its load allows, its pull's time in the goalie's
	# budget, at the odds the puck survives the pull and the charge
	# (price_keep). The as-is hold is scored first and the compare is strictly
	# greater, so a tie keeps the release that needs no pull.
	# The shot is the field's pick (AIShotOdds) from the base release, so the
	# hold, its load share, the aim and the loft all describe one shot: a hold
	# solved toward the net centre for an aim elsewhere prices a load the press
	# then waits on and never sees.
	_shot_pick.aim = Vector3.INF
	var opp_keeper: GoalieNetworkState = snapshot.goalie_states.get(1 - ctx.team_id)
	var keeper_now: Vector3 = Vector3.INF
	var keeper_vel_x: float = 0.0
	var keeper_stance: int = AIShotOdds.Stance.UPRIGHT
	var keeper_yaw: float = NAN
	if opp_keeper != null:
		keeper_now = Vector3(opp_keeper.position_x, 0.0, opp_keeper.position_z)
		keeper_vel_x = opp_keeper.velocity_x if ctx.reads_goalie_motion else 0.0
		keeper_stance = AIShotOdds.stance_of(opp_keeper, attacking_goal)
		keeper_yaw = opp_keeper.rotation_y
		if not shot_unavailable:
			AIShotOdds.pick_shot_now(wrister_base_release, attacking_goal, keeper_now,
					keeper_vel_x, keeper_stance, _shot_pick, keeper_yaw)
	var shot_target: Vector3 = _shot_pick.aim if _shot_pick.aim.is_finite() else attacking_goal
	var shot_dir: Vector3 = shot_target - wrister_base_release
	shot_dir.y = 0.0
	shot_dir = shot_dir.normalized() if shot_dir.length_squared() > 0.0001 \
			else Vector3(0.0, 0.0, -signf(attacking_goal.z))
	if not shot_unavailable:
		_field.holds.configure_from(ctx)
		_field.holds.solve_shot(Vector2(shot_dir.x, shot_dir.z),
				Vector2(puck_now.x - self_pos.x, puck_now.z - self_pos.z),
				Vector2(horizontal_velocity.x, horizontal_velocity.z),
				snapshot.skater_states[ctx.peer_id].facing)
		_field.holds.price_keep(self_pos, Vector2(horizontal_velocity.x, horizontal_velocity.z),
				snapshot.skater_states[ctx.peer_id].facing,
				AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S, _field.opponents,
				_field.opponent_vels, _field.opponent_caps)
	_phase_shoot_score = -1.0
	for k: int in _field.holds.count:
		if shot_unavailable:
			break
		var hold := Vector3(_field.holds.offset[k].x, 0.0, _field.holds.offset[k].y)
		var share: float = _field.holds.share[k]
		var pull_s: float = _field.holds.pull_s[k]
		var sample_speed: float = ctx.self_wrister_shot_speed * share
		var release: Vector3 = AIGoalieModel.release_ahead_of_goalie(
				self_pos + hold + horizontal_velocity
						* (AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S + pull_s),
				attacking_goal, goalie_now)
		# Priced through the seam like the carry and pass legs, against the
		# keeper as he reads now: the field prices what he does over the wind-up
		# and flight. With no keeper replicated he is taken
		# square and set.
		var s: float = AIActionScoring.score_shoot_value(
				release, attacking_goal, keeper_now, _field.opponents_release,
				keeper_vel_x, keeper_stance, sample_speed,
				_field.opponent_caps, -1.0, keeper_yaw) * _field.holds.keep[k]
		if s > _phase_shoot_score:
			_phase_shoot_score = s
			_shot_sample_share = share
			shoot_now_hold = hold

	# Shoot-for-tip: the same rip can score by DEFLECTION off a net-front
	# teammate. An alternative AIM of the same fire action, so it competes with
	# the direct read by max(), never additively. Scored against the in-zone
	# teammates gathered for the pass options, with the goalie taken set at his
	# current spot (conservative). Fired from the faster hold.
	_shot_sample_is_tip = false
	if not shot_unavailable and not _field.receiver_pos.is_empty():
		var tip_k: int = 1 if _field.holds.share[1] > _field.holds.share[0] else 0
		var tip_hold := Vector3(_field.holds.offset[tip_k].x, 0.0, _field.holds.offset[tip_k].y)
		var tip_share: float = _field.holds.share[tip_k]
		var tip_pull_s: float = _field.holds.pull_s[tip_k]
		var tip_release: Vector3 = AIGoalieModel.release_ahead_of_goalie(
				self_pos + tip_hold + horizontal_velocity
						* (AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S + tip_pull_s),
				attacking_goal, goalie_now)
		var tip_speed: float = ctx.self_wrister_shot_speed * tip_share
		for tip_man: Vector3 in _field.receiver_pos:
			var tip_s: float = AIActionScoring.tip_ev(
					tip_release, tip_man, attacking_goal, goalie_now,
					_field.opponents_release,
					tip_speed, _field.opponent_caps) * _field.holds.keep[tip_k]
			if tip_s > _phase_shoot_score:
				_phase_shoot_score = tip_s
				_shot_sample_share = tip_share
				shoot_now_hold = tip_hold
				_shot_sample_is_tip = true

	var self_state: SkaterNetworkState = snapshot.skater_states[ctx.peer_id]
	_pass.search(ctx, self_state.facing, _field.teammate_ids)
	_phase_best_pass_peer = _pass.best_peer
	_phase_best_pass_score = _pass.best_score
	_phase_best_pass_saucer = _pass.best_is_saucer
	_phase_best_pass_rim_dir = _pass.best_rim_dir
	_phase_best_pass_rim_pace = _pass.best_rim_pace
	_phase_best_pass_frac = _pass.best_pace_frac


# COMMIT phase of the compete: the CARRY candidate argmax, and the
# fire-vs-carry-vs-hold compete that commits the intent. Consumes the fire
# phase's _phase_* / _shot_sample_* products. `rebuild_lists` is
# true on the second dispatch of a SLICED eval, where the opponent lists are one
# dispatch old: the carry scoring rebuilds them, while the fire SCORES stay
# the older reads.
func _pick_commit_phase(ctx: RoleContext, rebuild_lists: bool) -> void:
	var snapshot: WorldSnapshot = ctx.snapshot
	var self_pos: Vector3 = ctx.self_pos
	var attacking_goal: Vector3 = ctx.attacking_goal_pos
	if rebuild_lists:
		_field.fill(ctx)
	var puck_now: Vector3 = self_pos
	if snapshot.puck_state != null:
		puck_now = Vector3(
				snapshot.puck_state.position.x, 0.0,
				snapshot.puck_state.position.z)
	var current_safety: float = _phase_current_safety
	var shoot_score: float = _phase_shoot_score
	var best_pass_peer: int = _phase_best_pass_peer
	var best_pass_score: float = _phase_best_pass_score
	var best_pass_saucer: bool = _phase_best_pass_saucer
	var best_pass_rim_dir: Vector3 = _phase_best_pass_rim_dir

	# Stand-still's shot branch shares the raw shoot-now score (see AICarrierCarrySearch.search),
	# captured before the ping bias: an ordered "shoot!" must not make holding
	# look better too.
	var raw_shoot_score: float = shoot_score
	if ctx.ping_shoot_active and shoot_score > 0.0:
		shoot_score *= PING_SHOOT_EV_MULT

	_carry.search(ctx, raw_shoot_score)
	var carry_score: float = _carry.value
	last_carry_anchor = _carry.anchor
	carry_move = _carry.move
	if carry_move >= 0:
		carry_stick = _carry.rollout.stick[carry_move]
		carry_brake = _carry.rollout.brake[carry_move]
	var raw_carry_score: float = _carry.raw_value
	# The carry is floored by the same drive-in credit the pass search gives a
	# receiver, at our own velocity as his is at his, so neither of two
	# equally-covered wingers rates the other's drive above his own. When the
	# floor wins, the carry is that drive.
	var drive_in_value: float = _field.receiver_drive_in_value(
			ctx, self_pos, ctx.caps_by_peer.get(ctx.peer_id), ctx.self_velocity,
			Vector3.INF, 0.0, true)
	if drive_in_value > carry_score:
		carry_score = drive_in_value
		last_carry_anchor = _field.drive_in_reached
		carry_move = -1

	# Hysteresis on FIRE intents only, proportional (positive scores only) so
	# stickiness scales with the score instead of swamping the small-score
	# defensive-zone regime. Never give CARRY a bonus: stand-still's shot branch
	# IS the raw shoot-now score, so a bonus would lift it above fire on every
	# re-eval and the bot would never fire.
	if intended_action == INTENT_SHOOT and shoot_score > 0.0:
		shoot_score *= 1.0 + AIActionScoring.ACTION_HYSTERESIS_MARGIN_FRAC
	elif (intended_action == INTENT_PASS or intended_action == INTENT_DUMP) \
			and best_pass_score > 0.0:
		best_pass_score *= 1.0 + AIActionScoring.ACTION_HYSTERESIS_MARGIN_FRAC

	debug_shoot_score = shoot_score
	debug_pass_score = best_pass_score
	debug_pass_peer_id = best_pass_peer
	debug_carry_score = carry_score
	debug_carry_pos = last_carry_anchor

	# The wrister is the only shot type: a paced release covers everything from a
	# soft in-tight roof to a full-power rip.
	var best_shot_score: float = shoot_score
	var best_shot_intent: int = INTENT_SHOOT

	var settle_penalty: float = _settle_penalty(ctx)

	# Best fire option — the best of those that clear their OWN giveaway bar.
	# Qualify each option before the max, never after: taking the max first lets
	# a mediocre shot mask a legal outlet pass, so raising the shot's bar would
	# silently suppress passing too. Nothing qualifying leaves fire at -INF, which
	# loses every compete below.
	#
	# The bar is cleared by the DOUBTED value, the compete is entered at the
	# HONEST one: the doubt says whether this option is worth the puck yet, not
	# what it is worth (see _settle_penalty).
	var fire_score: float = -INF
	var fire_intent: int = best_shot_intent
	if _settle_handicap(best_shot_score, settle_penalty) > SHOT_MIN_VALUE:
		fire_score = best_shot_score
	if _settle_handicap(best_pass_score, settle_penalty) > PASS_MIN_VALUE \
			and best_pass_score > fire_score:
		fire_score = best_pass_score
		fire_intent = INTENT_PASS

	# Fire vs carry: FIRE WINS TIES (stand-still's shot branch is the shoot-now
	# score itself), so carry wins only on a STRICTLY better future-action value.
	# A staggered or still-settling bot does not START a fire — a stagger flails
	# the release, a settle only queues the press — but carry computes normally.
	var staggered: bool = ctx.self_stagger_timer > 0.0 or ctx.self_settle_s > 0.0

	# Opportunity cost of firing NOW: the value of keeping the puck for a feed a
	# teammate is still creating (AICarrierPassSearch.developing_feed_value), × the odds we keep the
	# puck that long (our current evadability), × the delay discount on how long
	# we've already held — so a wait that never materialises self-extinguishes.
	# When the play arrives the live pass scoring converges on it and fire wins
	# the tie.
	var keep_prob: float = current_safety
	var hold_value: float = (_pass.developing_feed_value(ctx)
			* keep_prob * AIActionScoring.delay_discount(_hold_elapsed_s))

	var new_intent: int
	# Retention is hopeless only when BOTH reads of keeping the puck fail, because each is blind
	# where the other sees: the raw carry is one beat ahead and cannot see the
	# entry a carrier skates into by beating his man; the drive-in sees that but
	# is one straight line, blind to the carry's other routes. In our own zone the
	# drive-in gets no vote: it is positive for any carrier with a sliver of a lane,
	# and would keep a doomed carrier from moving the puck in front of his own net.
	var in_own_zone: bool = AIActionScoring.in_offensive_zone(
			self_pos, ctx.defending_goal_pos)
	var retention_hopeless: bool = raw_carry_score <= 0.0 \
			and (in_own_zone or drive_in_value <= 0.0)
	# Fire if it beats retention (carrying, or holding for the developing play) —
	# or, when retention is hopeless, at all: there is nothing to compare it with,
	# and an unqualified fire arrives as -INF and loses both.
	if ((fire_score >= carry_score and fire_score >= hold_value)
			or (retention_hopeless and fire_score > -INF)) \
			and not staggered:
		_hold_elapsed_s = 0.0
		new_intent = fire_intent
		if new_intent == INTENT_PASS and best_pass_rim_dir != Vector3.ZERO:
			# The rim: chosen as a pass, released as a FLAT charged dump along
			# its bearing at its searched pace (the aim is the boards, not the
			# receiver).
			new_intent = INTENT_DUMP
			pass_target_peer_id = best_pass_peer
			dump_target = puck_now + best_pass_rim_dir * RIM_AIM_STANDOFF_M
			dump_launch_speed = _phase_best_pass_rim_pace
		elif new_intent == INTENT_PASS:
			pass_target_peer_id = best_pass_peer
			# Every pass is a paced wrister: distance-adaptive launch speed, soft for
			# a close feed and harder (still catchable) for a long one, capped at
			# what its load can carry.
			var receiver: SkaterNetworkState = ctx.snapshot.skater_states.get(best_pass_peer)
			if receiver != null:
				# Receiver-relative launch at the pace the search priced: harder onto
				# a streaking receiver, softer to one curling back. Distance and
				# direction from the PUCK (the real release point).
				var to_receiver: Vector3 = receiver.position - puck_now
				to_receiver.y = 0.0
				var pass_dir: Vector3 = to_receiver.normalized()
				pass_target_speed = AIPuckLane.pass_launch_speed(
						puck_now.distance_to(receiver.position),
						_field.pass_launch_cap(ctx, pass_dir,
								ctx.snapshot.skater_states[ctx.peer_id].facing),
						ctx.pass_speed_scale * _phase_best_pass_frac, receiver.velocity, pass_dir)
			else:
				pass_target_speed = AIPuckLane.PASS_SPEED_M_S * ctx.pass_speed_scale
			# A saucer's launch is capped at the receivability bound for the
			# distance — a flip still airborne at the tape flies over the
			# receiver's grounded blade — even after the receiver-relative solve.
			pass_should_saucer = best_pass_saucer
			if best_pass_saucer and receiver != null:
				pass_target_speed = clampf(
						AIPuckLane.saucer_max_launch_speed(
								puck_now.distance_to(receiver.position)),
						AIPuckLane.SOFTEST_FEED_M_S,
						pass_target_speed)
		elif new_intent == INTENT_SHOOT and _shot_sample_is_tip:
			# TIP rip at the net centre — the line the tipper's reactive mode
			# steps onto (AIRoleFinisher._try_reactive_decision). Flat keeps the
			# puck on the blade plane; full pace keeps the arrival above the
			# deflect threshold so contact redirects instead of catching.
			shot_loft_level = ShotMechanics.ELEVATION_FLAT
			shot_aim_point = Vector3(
					attacking_goal.x, 0.0, attacking_goal.z)
			shot_power_t = 1.0
			shot_hold_offset = shoot_now_hold
			shot_hold_share = _shot_sample_share
		elif new_intent == INTENT_SHOOT:
			# Aim and loft are the shot field's pick the holds were solved toward
			# (_pick_fire_phase); at a net with no keeper replicated, flat at the
			# middle.
			shot_aim_point = _shot_pick.aim if _shot_pick.aim.is_finite() \
					else Vector3(attacking_goal.x, 0.0, attacking_goal.z)
			shot_loft_level = _shot_pick.loft if _shot_pick.aim.is_finite() \
					else ShotMechanics.ELEVATION_FLAT
			# Full power (see shot_power_t).
			shot_power_t = 1.0
			shot_hold_offset = shoot_now_hold
			shot_hold_share = _shot_sample_share
	elif retention_hopeless and not staggered:
		# Nothing to fire and nothing worth holding for: keep the puck, and the next
		# re-eval looks again.
		_hold_elapsed_s = 0.0
		new_intent = INTENT_CARRY
	else:
		# Not firing. Advance the hold clock only while the developing play is the
		# reason (it out-scores plain carrying); a normal carry resets it so the
		# next genuine hold starts fresh at full value.
		if hold_value > carry_score and hold_value > 0.0:
			_hold_elapsed_s += float(_ticks_since_pick) / float(_PhysicsConstants.PHYSICS_TICK)
		else:
			_hold_elapsed_s = 0.0
		new_intent = INTENT_CARRY

	intended_action = new_intent


# Refills the directional protect-opponent triple from the full opponent lists,
# dropping every defender projected more than PROTECT_SCREEN_BEHIND_M behind the
# carrier along the body→attacking-goal line. Both bodies are projected to the
# SAME instant (the evasion horizon) so a fast back-checker who'll pull even by
# then still counts. With no netward direction (carrier on the goal), no
# defender is dropped.
func _fill_protect_opponents(ctx: RoleContext) -> void:
	_scratch_protect_opponents.clear()
	_scratch_protect_vels.clear()
	_scratch_protect_caps.clear()
	var horizon: float = AICarrySpace.EVADE_HORIZON_S
	var to_goal: Vector3 = ctx.attacking_goal_pos - ctx.self_pos
	var len_sq: float = to_goal.x * to_goal.x + to_goal.z * to_goal.z
	var have_dir: bool = len_sq > 0.0001
	var nx: float = 0.0
	var nz: float = 0.0
	if have_dir:
		var inv: float = 1.0 / sqrt(len_sq)
		nx = to_goal.x * inv
		nz = to_goal.z * inv
	var self_proj_x: float = ctx.self_pos.x + ctx.self_velocity.x * horizon
	var self_proj_z: float = ctx.self_pos.z + ctx.self_velocity.z * horizon
	for i: int in _field.opponents.size():
		if have_dir:
			var opp_proj_x: float = _field.opponents[i].x \
					+ _field.opponent_vels[i].x * horizon
			var opp_proj_z: float = _field.opponents[i].z \
					+ _field.opponent_vels[i].z * horizon
			var ahead: float = (opp_proj_x - self_proj_x) * nx \
					+ (opp_proj_z - self_proj_z) * nz
			if ahead < -PROTECT_SCREEN_BEHIND_M:
				continue   # beaten — the body screens the forward puck for free
		_scratch_protect_opponents.append(_field.opponents[i])
		_scratch_protect_vels.append(_field.opponent_vels[i])
		_scratch_protect_caps.append(_field.opponent_caps[i])

