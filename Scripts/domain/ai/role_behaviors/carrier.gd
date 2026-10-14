class_name AIRoleCarrier
extends RefCounted

const _PhysicsConstants: GDScript = preload("res://Scripts/game/constants.gd")

# CARRIER role behavior: the puck-carrying utility AI. Scores SHOOT (wrister),
# PASS (per teammate) and CARRY (the candidate set _best_carry builds) on one
# scale every PICK_ACTION_PERIOD_TICKS ticks, with DUMP as the residual when
# none of them is worth anything. Hysteresis on the current fire intent stops
# flicker during pre-aim; CARRY gets none, because stand-still's shot branch IS
# the shoot-now score and fire must win that tie.
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
# Last-resort DUMP — fire the puck to a location (no receiver). The state machine
# maps it onto a PASS_PRESSED release aimed at `dump_target`.
const INTENT_DUMP: int = 5

# ── Giveaway floors: least value worth releasing the puck for ────────────────
# In the seam's xG currency; see Scripts/domain/ai/CLAUDE.md → "One currency
# across the carrier's compete". There is no third bar for the DUMP: it is a
# residual (see _pick_commit_phase), not a release chosen on merits.
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
# Winning hold from the last shoot-now sweep: the release/goalie/pace the
# SHOOT commit's loft/aim must be computed against (so the executed shot is the
# one that won the compete), and the share of pace the load gives it.
var _shot_sample_release: Vector3 = Vector3.ZERO
var _shot_sample_goalie: Vector3 = Vector3.ZERO
var _shot_sample_speed: float = GameRules.DEFAULT_WRISTER_POWER_MAX_M_S
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

# ── Attacking blue-line keep-out bands ──────────────────────────────────────
# Physical measurements of how far play around the carried puck extends past
# the body: the offside puck-line is the TRUE blue line, while these decisions
# are made in body positions.
#
# RETREAT: how close to the line the OZ one-way valve lets a carry candidate
# sit (see _score_move_candidate_base). The charged pass windup sweeps the
# carried puck up to a stick's reach back from the body, and the ~135 ms charge
# drifts a still-retreating body further (~7 m/s × 0.135 s); parked closer, the
# puck crosses the line mid-pass and the pass lands the whole team offside.
const OZ_RETREAT_LINE_BUFFER_M: float = GameRules.DEFAULT_STICK_LENGTH_M + 1.0

# The local step a carry candidate is never placed inside: the floor on the
# beat-scaled forward radii, and the horizon the space fan is sampled over.
const CARRY_SEARCH_STEP_M: float = 3.0

# Post-walkout candidates — one just outside each post, a step onto the rink
# side of the goal line, generated only while the carrier is behind a goal line,
# where every other route out front crosses the cage and prunes. The lateral
# clearance is physical: post half-span + a carried body's half-width + blade
# slop.
const WALKOUT_POST_CLEARANCE_M: float = 0.9
const WALKOUT_FRONT_M: float = 0.7

# The WHEEL (5v5 only — breakout plan §B): from behind our own goal line, the
# carry around the BACK of the cage and out the far half-wall — the escape when
# the retriever has a step on the chaser. Priced as a two-leg carry through the
# behind-net apex (_score_wheel_candidate). Exit depth = the top of the low
# battle ice (the value of AIZoneCoverage.LOW_ZONE_DEPTH_M); apex = the middle
# of the behind-net alley (cage back + half the gap to the boards).
const WHEEL_EXIT_UP_ICE_M: float = 8.0
const WHEEL_APEX_CLEARANCE_M: float = 0.75

# Zone-exit wall routes — a long-range carry candidate up each boards lane to
# just past our own blue line, generated only in our defensive zone. The slot
# anchor, the only other long-range candidate, runs through center ice where a
# forecheck sets up, so without these a deep carrier with a clogged middle has
# only short steps and the backpass. The NZ lead puts the destination across
# the blue line — a completed exit.
const CARRY_EXIT_WALL_INSET_M: float = 2.0
const CARRY_EXIT_NZ_LEAD_M: float = 3.0

# REAR/LATERAL ring angles, relative to the carry direction — the half of the
# bearing circle the space fan does not span (it looks only ±70°, where the
# carrier is trying to GO). Each bearing is taken at two fractions of its own
# beat reach, so the near one is the local reposition and the far one the
# committed peel-out; at a fixed 3 m, straight back would be a shuffle inside
# the defender's re-close radius.
const _REAR_ANGLES: Array[float] = [
		PI * 0.5, PI * 0.75, PI, -PI * 0.75, -PI * 0.5,
]

# A rear candidate below this displacement is not a distinct plan: inside one
# stick length, "skate there" and "stand still and reach" are the same play,
# and stand-still and the directed evasion seam are always in the compete.
const CARRY_REAR_MIN_STEP_M: float = AICarrySpace.EVADE_STICK_REACH_M

# FIELD-DERIVED FORWARD CANDIDATES (see the generator in _best_carry).
# BEARINGS: how many of the space fan's 7 bearings become carry candidates,
# ranked by control × forward projection.
# RADII: fractions of the planning beat. Two of them, so the near gradient a
# standstill carrier steers on survives when the beat stretches out at speed.
# PLAN_BEAT_S: the horizon a carry candidate is a PLAN over rather than a
# steering nudge — one second of travel, which reduces to a 3 m local step at a
# standstill and reaches ~9 m at a full stride.
const CARRY_FIELD_BEARINGS: int = 3
const CARRY_FIELD_RADII: Array[float] = [0.5, 1.0]
const CARRY_PLAN_BEAT_S: float = 1.0
# Deke engagement gates, the cheap pre-filters before AICarrySpace.deke_cut_side.
# ENGAGE_RANGE: close enough that the duel is live but the fake still has room to
# develop — a step beyond the poke trigger's reach. MAX_CLOSING: the deke answers
# PATIENT containment; above this relative closing speed the pressure is
# committed and the brake check / seam cut own the moment.
const DEKE_ENGAGE_RANGE_M: float = 3.5
const DEKE_CONTAIN_MAX_CLOSING_M_S: float = 2.0


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

# Set true with every PASS commit — every bot pass is a charged wrister. The
# state machine reads it entering PASS_PRESSED to charge rather than fire on the
# first tick.
var pass_should_charge: bool = false

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
# the goalie hole the shot is aimed at (see AIActionScoring.best_shot_loft).
# Read by the state machine's press-state handlers to drive the release loft.
var shot_loft_level: int = ShotMechanics.ELEVATION_FLAT

# Set alongside shot_loft_level: the world aim POINT of that same hole (on the
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

# Set when intent commits to DUMP: the world spot to fire the puck at, and the
# delivery kind — a soft flip (the dump-in), a FLAT rim (the rim PASS, see
# AIRimPass), or the HIGH chip clear (neither flag). A rim is chosen as a pass
# and released as a dump, because its aim is a bearing into the boards rather
# than the receiver. Read by the state machine's dump release.
var dump_target: Vector3 = Vector3.INF
var dump_is_soft: bool = false
var dump_is_rim: bool = false
# Launch pace (m/s) a charged dump fires at: the dump-in's winning pace from
# solve_dump_in's ladder, or the rim's searched pace. The clear is a fixed-pace
# one-tick release and ignores it.
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
# The OBJECTIVE-DIRECTED evasion seam from the same re-eval (world point,
# AICarrySpace.best_evade_point_toward): the safe spot with the most progress
# toward the live carry anchor, falling back to max clearance when nothing is
# safe. Vector3.INF until first computed.
var evade_seam_world: Vector3 = Vector3.INF
# Whether a brake check currently beats the seam cut against the live pressure
# (AICarrySpace.prefers_brake_check). Latched by the state machine's poke-evade
# trigger to pick the maneuver; protect-tier only.
var brake_check_favored: bool = false
# Fake-then-cut deke read (AICarrySpace.deke_cut_side): true when faking one way
# manufactures a safe cut past the containing defender that doesn't exist right
# now. The dirs are world-XZ units for the two committed phases, latched by the
# state machine's trigger. Protect-tier only; refreshed every re-eval.
var deke_go: bool = false
var deke_fake_dir: Vector2 = Vector2.ZERO
var deke_cut_dir: Vector2 = Vector2.ZERO

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
# The winning pass's rim launch bearing, ZERO when it is a straight feed.
var _phase_best_pass_rim_dir: Vector3 = Vector3.ZERO
# The winning pass's rim pace, carried to the release with its bearing.
var _phase_best_pass_rim_pace: float = 0.0
# Opposing-goalie env captured alongside the winning shot sample, so the
# commit's loft/aim/power solve reads the same goalie the score saw:
var _shot_env_unsettled: float = 0.0
var _shot_env_five_hole: float = -1.0
var _shot_env_goalie_down: bool = false
var _shot_env_seal_x: float = 0.0
var _shot_env_seal_tall: bool = false
var _shot_env_hands: Vector4 = Vector4.INF
var _shot_env_pads: Vector4 = Vector4.INF

# What the carrier sees this phase (AICarrierField), refilled at each phase's
# head, and the searches that read it.
var _field := AICarrierField.new()
var _dump := AICarrierDumpSearch.new()
var _pass := AICarrierPassSearch.new(_field)

# ── Scratch buffers (reused across ticks, refilled per call) ────────────────
# Opponents projected to a carry candidate's arrival.
var _scratch_opponents_path: Array[Vector3] = []
# Two-leg (wheel/apex) projections: filled at the apex arrival time for the
# second leg's reach read, then refilled at destination arrival for that
# leg's lane/pressure read.
var _scratch_opponents_cont: Array[Vector3] = []
# Per-bearing control from the carrier's own forward-space read, filled every
# re-eval by _carrier_forward_clearance and consumed by _best_carry's candidate
# generator, which overwrites entries as it takes them.
var _scratch_bearing_control: Array[float] = []
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

# ── Carry-candidate beam (two-ply search budget) ─────────────────────────────
# The two-ply pass-OPTION read is ~90% of a carry candidate's cost, and the
# exact incumbent-bound prunes lose their teeth in open ice, where safety/lane
# ≈ 1 for every spot. So pass 1 (_score_move_candidate_base) scores every
# candidate ONE-PLY — a strict LOWER bound on its full value, since the two-ply
# reads only ever RAISE a spot — and pass 2 (_upgrade_candidate_two_ply)
# completes the two-ply reads for the CARRY_BEAM_WIDTH best one-ply rows only,
# best-first, under the exact incumbent-bound prunes. The argmax is therefore
# approximate (a spot whose whole winning margin lives in the second ply can
# miss the beam) — a search-budget policy, not an evaluation-model change.
# Candidates outside the beam keep their one-ply totals, which can never win.
const CARRY_BEAM_WIDTH: int = 5
# Beam rows — one entry per base-scored candidate this re-eval, index-matched
# (cleared per _best_carry; clear() keeps capacity, so steady state allocates
# nothing).
var _beam_pos: Array[Vector3] = []
var _beam_total: Array[float] = []
var _beam_dest: Array[float] = []
var _beam_lane: Array[float] = []
var _beam_decay: Array[float] = []
var _beam_safety: Array[float] = []
var _beam_cost: Array[float] = []
# Pass-1 running prune bound: stand-still's secured total, tightened to the
# BEST one-ply total seen so far. Exact for the argmax even though it can prune
# candidates out of the beam: a candidate whose ceiling ≤ the best one-ply row
# can never out-upgrade that row, since upgrades only raise values. Reset per
# _best_carry.
var _beam_prune_bound: float = -INF

# ── Debug readout ────────────────────────────────────────────────────────────
# Populated every re-eval; the state machine forwards these to its own debug_*
# fields for the floating label.
var debug_shoot_score: float = 0.0
var debug_pass_score: float = 0.0
var debug_pass_peer_id: int = 0
var debug_carry_score: float = 0.0
var debug_carry_pos: Vector3 = Vector3.ZERO
var debug_dump_score: float = 0.0


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
	pass_should_charge = false
	pass_target_speed = AIPuckLane.PASS_SPEED_M_S
	pass_should_saucer = false
	shot_loft_level = ShotMechanics.ELEVATION_FLAT
	shot_aim_point = Vector3.INF
	shot_power_t = 1.0
	shot_hold_offset = Vector3.ZERO
	shot_hold_share = 1.0
	shoot_now_hold = Vector3.ZERO
	last_carry_anchor = Vector3.ZERO
	dump_target = Vector3.INF
	dump_is_soft = false
	dump_is_rim = false
	dump_launch_speed = AIPuckLane.PASS_SPEED_M_S
	protect_offset = Vector3.ZERO
	protect_gain = 0.0
	forward_puck_clearance = AICarrySpace.EVADE_SAFE_MARGIN_M
	evade_seam_world = Vector3.INF
	brake_check_favored = false
	deke_go = false
	deke_fake_dir = Vector2.ZERO
	deke_cut_dir = Vector2.ZERO
	_hold_elapsed_s = 0.0
	_pick_action_cooldown = 0
	_ticks_since_pick = 0
	# A half-finished sliced eval priced a puck we no longer hold.
	_commit_phase_pending = false
	_full_eval_pending = true
	_settle_arm_pending = true
	_settle_elapsed_s = 0.0


# Clear just the persistent intent (not last_carry_anchor / debug). Called by
# the state machine when committing to a press state, so the next CARRY entry
# re-evaluates from scratch. Does NOT re-arm the settle clock — a press bail
# back to CARRY is the same possession.
func clear_intent() -> void:
	intended_action = INTENT_CARRY
	pass_target_peer_id = -1
	pass_should_charge = false
	pass_target_speed = AIPuckLane.PASS_SPEED_M_S
	pass_should_saucer = false
	dump_target = Vector3.INF
	dump_is_soft = false
	dump_is_rim = false
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


# FIRE phase of the compete: opponent lists, the evasion / brake-check / deke /
# protect reads, the pass-option cache, and the SHOOT + PASS scoring. Leaves
# its products in the _phase_* / _shot_env_* / _shot_sample_* fields (plus the
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
	# The DIRECTED seam — where to put the puck to get PAST the pressure toward
	# the live carry anchor (the attacking goal until the first re-eval picks
	# one). The state machine latches it as the deke direction and _best_carry
	# scores it as a candidate. The anchor is ≤ one re-eval stale, which is fine
	# for a body-scale step.
	var seam_objective: Vector3 = last_carry_anchor
	if seam_objective == Vector3.ZERO:
		seam_objective = attacking_goal
	var directed_seam: Vector3 = AICarrySpace.best_evade_point_toward(
			cur_puck_pos, ctx.self_velocity, seam_objective,
			_field.opponents, _field.opponent_vels,
			ctx.self_handle_reach, _field.opponent_caps)
	evade_seam_world = directed_seam
	# Gated with the other protect-tier reads: the brake check is taught puck
	# skill.
	brake_check_favored = ctx.protects_the_puck \
			and AICarrySpace.prefers_brake_check(
					cur_puck_pos, ctx.self_velocity, directed_seam,
					_field.opponents, _field.opponent_vels, _field.opponent_caps)

	# Fake-then-cut deke read: find the PATIENT container — the nearest opponent
	# inside the duel range, ahead on the objective line, with small relative
	# closing — and ask whether faking one way buys a safe cut past him. The
	# axis frame (puck → his projected spot, plus its perpendicular) is built
	# HERE and the returned side is converted with the same frame, so the eval
	# and the executed gesture agree by construction.
	deke_go = false
	deke_fake_dir = Vector2.ZERO
	deke_cut_dir = Vector2.ZERO
	if ctx.protects_the_puck:
		var obj_dir: Vector3 = seam_objective - cur_puck_pos
		obj_dir.y = 0.0
		if obj_dir.length_squared() > 0.0001:
			obj_dir = obj_dir.normalized()
			var deked_idx: int = -1
			var deked_dist: float = DEKE_ENGAGE_RANGE_M
			for i: int in _field.opponents.size():
				var to_opp: Vector3 = _field.opponents[i] - cur_puck_pos
				to_opp.y = 0.0
				var d: float = to_opp.length()
				if d >= deked_dist or d < 0.001:
					continue
				if to_opp.dot(obj_dir) <= 0.0:
					continue   # behind the play — not the man to beat
				var closing: float = (ctx.self_velocity - _field.opponent_vels[i]) \
						.dot(to_opp / d)
				if absf(closing) > DEKE_CONTAIN_MAX_CLOSING_M_S:
					continue   # committed pressure — other maneuvers own it
				deked_dist = d
				deked_idx = i
			if deked_idx != -1:
				var d_proj: Vector3 = _field.opponents[deked_idx] \
						+ _field.opponent_vels[deked_idx] \
								* (AICarrySpace.DEKE_FAKE_S + AICarrySpace.DEKE_CUT_S)
				var axis: Vector3 = d_proj - cur_puck_pos
				axis.y = 0.0
				if axis.length_squared() > 0.0001:
					axis = axis.normalized()
					var perp := Vector3(axis.z, 0.0, -axis.x)
					var side: int = AICarrySpace.deke_cut_side(
							cur_puck_pos, ctx.self_velocity, ctx.self_handle_reach,
							axis, perp, deked_idx,
							_field.opponents, _field.opponent_vels,
							_field.opponent_caps)
					if side != 0:
						var cut3: Vector3 = (axis + perp * float(side)).normalized()
						deke_go = true
						deke_cut_dir = Vector2(cut3.x, cut3.z)
						deke_fake_dir = Vector2(-perp.x * float(side), -perp.z * float(side))

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
	# threat_surface_shoot and value_at run). Gating it, rather than leaving it
	# to SHOT_MIN_VALUE, guarantees the fire hysteresis and the ping SHOOT bias
	# have no score to lift. A DISPLACED or PULLED keeper voids the proof — an
	# empty net genuinely scores from centre ice — so this is not a blanket zone
	# gate.
	var shot_unavailable: bool = shot_from_behind_line \
			or (not AIActionScoring.in_offensive_zone(self_pos, attacking_goal)
					and goalie_now.distance_to(attacking_goal)
							< AIActionScoring.THREAT_GOALIE_HOME_M)

	# The goalie env from the replicated pose, kept in _shot_env_* so the commit
	# phase's loft/aim/power solve reads the same goalie. The five-hole is the
	# real ~0.20 m slot standing, the residual leak down.
	_shot_env_unsettled = 0.0
	_shot_env_five_hole = -1.0
	_shot_env_goalie_down = false
	_shot_env_seal_x = 0.0
	_shot_env_seal_tall = false
	_shot_env_hands = Vector4.INF
	_shot_env_pads = Vector4.INF
	var opp_goalie_state: GoalieNetworkState = ctx.snapshot.goalie_states.get(1 - ctx.team_id)
	if opp_goalie_state != null and not shot_unavailable:
		_shot_env_goalie_down = opp_goalie_state.is_down()
		# The HIGH cover races from where the glove/blocker actually are, the
		# LOW cover from the measured pad edges.
		_shot_env_hands = opp_goalie_state.hands_read(ctx.attacking_goal_pos.z)
		_shot_env_pads = opp_goalie_state.pads_read(ctx.attacking_goal_pos.z)
		_shot_env_five_hole = GoalieBehaviorRules.five_hole_gap_m(
				_shot_env_goalie_down, opp_goalie_state.five_hole_openness)
		# Post-seal stance (VH/RVH): the pose IS the coverage, and he holds the
		# post rather than re-squaring, so the shot is scored against where he's
		# parked (see sample_goalie below), not an arc-squared keeper.
		_shot_env_seal_x = opp_goalie_state.post_seal_x_sign(attacking_goal.z)
		_shot_env_seal_tall = opp_goalie_state.is_post_seal_tall()

	# Top-level SHOOT: the hold sweep over AIShotHolds (the puck where it is, the
	# loaded pocket, a reach to either side of the shot line). Each hold prices
	# its release at the pace its load allows, its pull's time in the goalie's
	# budget, at the odds the puck survives the pull and the charge
	# (price_keep). The as-is hold is scored first and the compare is strictly
	# greater, so a tie keeps the release that needs no pull. The goalie at puck
	# ARRIVAL is react-then-slide from where he actually is toward the release's
	# arc-square, over the pull, the charge and the flight; the caught-moving
	# effect is priced as his displacement shortfall (shot_disp).
	var shot_dir: Vector3 = attacking_goal - wrister_base_release
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
		var flight_s: float = release.distance_to(attacking_goal) \
				/ maxf(sample_speed, 1.0)
		# The goalie's tracking budget includes this bot's EXPECTED release
		# lateness — the mean of the uniform [0, max] hold the execution samples
		# (ctx.shot_timing_error_s × 0.5) — so the score is the median outcome of
		# the release the hand will actually produce, and the sampled delay then
		# decides a razor lateral window.
		# The shooter's own netward pace backs the keeper in over the wind-up +
		# flight (the planning depth model).
		var shot_closing: float = AIGoalieModel.closing_toward(
				ctx.self_pos, ctx.self_velocity, attacking_goal)
		var sample_goalie: Vector3 = goalie_now if _shot_env_seal_x != 0.0 \
				else AIGoalieModel.predict_goalie_pos(
						goalie_now, attacking_goal,
						AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S + pull_s
								+ flight_s + ctx.shot_timing_error_s * 0.5,
						release, shot_closing)
		# Priced through the seam, like the carry and pass legs (see
		# Scripts/domain/ai/CLAUDE.md → "One currency across the carrier's
		# compete"); the replicated pose (_shot_env_*) only picks aim / loft /
		# power once SHOOT has won.
		var shot_disp: float = AIShotValue.displacement_deficit_m(
				goalie_now, attacking_goal, release,
				AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S + pull_s
						+ flight_s + ctx.shot_timing_error_s * 0.5)
		var s: float = AIActionScoring.score_shoot_value(
				release, attacking_goal, sample_goalie, shot_disp,
				GameRules.NET_HALF_WIDTH, _field.opponents_release,
				sample_speed, _field.opponent_caps, ShotEvent.ShotType.SHOT,
				ctx.self_loft_tans.z) * _field.holds.keep[k]
		if s > _phase_shoot_score:
			_phase_shoot_score = s
			_shot_sample_release = release
			_shot_sample_goalie = sample_goalie
			_shot_sample_speed = sample_speed
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
					GameRules.NET_HALF_WIDTH, _field.opponents_release,
					tip_speed, _field.opponent_caps) * _field.holds.keep[tip_k]
			if tip_s > _phase_shoot_score:
				_phase_shoot_score = tip_s
				_shot_sample_release = tip_release
				_shot_sample_goalie = goalie_now
				_shot_sample_speed = tip_speed
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


# COMMIT phase of the compete: the CARRY candidate argmax, the DUMP read, and
# the fire-vs-carry-vs-hold compete that commits the intent. Consumes the fire
# phase's _phase_* / _shot_env_* / _shot_sample_* products. `rebuild_lists` is
# true on the second dispatch of a SLICED eval, where the opponent lists are one
# dispatch old: the carry/dump scoring rebuilds them, while the fire SCORES stay
# the older reads.
func _pick_commit_phase(ctx: RoleContext, rebuild_lists: bool) -> void:
	var snapshot: WorldSnapshot = ctx.snapshot
	var self_pos: Vector3 = ctx.self_pos
	var attacking_goal: Vector3 = ctx.attacking_goal_pos
	if rebuild_lists:
		_field.fill(ctx)
	var our_goalie: Vector3 = AIRoleHelpers.resolve_our_goalie_pos(ctx)
	var puck_now: Vector3 = self_pos
	if snapshot.puck_state != null:
		puck_now = Vector3(
				snapshot.puck_state.position.x, 0.0,
				snapshot.puck_state.position.z)
	var directed_seam: Vector3 = evade_seam_world
	var current_safety: float = _phase_current_safety
	var shoot_score: float = _phase_shoot_score
	var best_pass_peer: int = _phase_best_pass_peer
	var best_pass_score: float = _phase_best_pass_score
	var best_pass_saucer: bool = _phase_best_pass_saucer
	var best_pass_rim_dir: Vector3 = _phase_best_pass_rim_dir

	# Stand-still's shot branch shares the raw shoot-now score (see _best_carry),
	# captured before the ping bias: an ordered "shoot!" must not make holding
	# look better too.
	var raw_shoot_score: float = shoot_score
	if ctx.ping_shoot_active and shoot_score > 0.0:
		shoot_score *= PING_SHOOT_EV_MULT

	# Runs BEFORE the carry search: its per-bearing by-product
	# (_scratch_bearing_control) is where _best_carry's forward candidates come
	# from.
	var forward_space: float = _carrier_forward_clearance(ctx)

	var carry_result: Array = _best_carry(
			ctx, raw_shoot_score, directed_seam)
	var carry_score: float = carry_result[0]
	last_carry_anchor = carry_result[1]
	var raw_carry_score: float = carry_result[2]
	# Pass-first under pressure (see FORWARD_PRESSURE_*); the dump still judges
	# against the raw carry.
	carry_score *= lerpf(AICarrierField.FORWARD_PRESSURE_MIN_SCALE, 1.0, forward_space)
	# …but SELF is floored by the same drive-in credit the pass search gives a receiver,
	# at our own velocity as his is at his. Without it two equally-covered
	# wingers at the blue line each rate the OTHER man's drive above their own
	# discounted carry, and the puck ping-pongs along the line instead of
	# entering the zone.
	var drive_in_value: float = _field.receiver_drive_in_value(
			ctx, self_pos, ctx.self_wrister_shot_speed,
			ctx.caps_by_peer.get(ctx.peer_id), ctx.self_velocity, Vector3.INF, 0.0, true)
	carry_score = maxf(carry_score, drive_in_value)

	# Hysteresis on FIRE intents only, proportional (positive scores only) so
	# stickiness scales with the score instead of swamping the small-score
	# defensive-zone regime. Never give CARRY a bonus: stand-still's shot branch
	# IS the raw shoot-now score, so a bonus would lift it above fire on every
	# re-eval and the bot would never fire.
	if intended_action == INTENT_SHOOT and shoot_score > 0.0:
		shoot_score *= 1.0 + AIActionScoring.ACTION_HYSTERESIS_MARGIN_FRAC
	elif (intended_action == INTENT_PASS or (intended_action == INTENT_DUMP
			and dump_is_rim)) and best_pass_score > 0.0:
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
	# A staggered bot does not START a fire — winding up through a body check's
	# stagger flails the release — but carry still computes normally.
	var staggered: bool = ctx.self_stagger_timer > 0.0

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
	# Only filled when the delivery search actually runs (the dump branch below);
	# -INF on the label means "nothing was conceded", not "a dump scored -INF".
	debug_dump_score = -INF
	# The dump is a RESIDUAL, never an option in the value compete — see
	# Scripts/domain/ai/CLAUDE.md → "Dumps are searched RELEASES". Retention is
	# hopeless only when BOTH reads of keeping the puck fail, because each is blind
	# where the other sees: the raw carry is one beat ahead and cannot see the
	# entry a carrier skates into by beating his man; the drive-in sees that but is
	# benefit-only, so it cannot say a carry is doomed. In our own zone the
	# drive-in gets no vote: it is positive for any carrier with a sliver of a lane
	# and would veto every clear.
	var in_own_zone: bool = AIActionScoring.in_offensive_zone(
			self_pos, ctx.defending_goal_pos)
	var retention_hopeless: bool = raw_carry_score <= 0.0 \
			and (in_own_zone or drive_in_value <= 0.0)
	# Fire if it beats retention (carrying, or holding for the developing play) —
	# or, when retention is hopeless, at all: the ordering is fire-then-dump with
	# nothing to compare, and an unqualified fire arrives as -INF and loses both.
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
			dump_target = puck_now + best_pass_rim_dir * AICarrierDumpSearch.DUMP_AIM_STANDOFF_M
			dump_is_soft = false
			dump_is_rim = true
			dump_launch_speed = _phase_best_pass_rim_pace
		elif new_intent == INTENT_PASS:
			pass_target_peer_id = best_pass_peer
			# Every pass is a paced wrister: distance-adaptive launch speed, soft for
			# a close feed and harder (still catchable) for a long one, capped at
			# what its load can carry.
			var receiver: SkaterNetworkState = ctx.snapshot.skater_states.get(best_pass_peer)
			if receiver != null:
				# Receiver-relative launch: the puck lands on the tape at the magnet
				# CLOSING speed in the receiver's frame — harder onto a streaking
				# receiver, softer to one curling back. Distance and direction from
				# the PUCK (the real release point).
				var to_receiver: Vector3 = receiver.position - puck_now
				to_receiver.y = 0.0
				var pass_dir: Vector3 = to_receiver.normalized()
				pass_target_speed = AIPuckLane.pass_launch_speed(
						puck_now.distance_to(receiver.position),
						_field.pass_launch_cap(ctx, pass_dir,
								ctx.snapshot.skater_states[ctx.peer_id].facing),
						ctx.pass_speed_scale, receiver.velocity, pass_dir)
			else:
				pass_target_speed = AIPuckLane.PASS_SPEED_M_S * ctx.pass_speed_scale
			pass_should_charge = true
			# A saucer's launch is capped at the receivability bound for the
			# distance — a flip still airborne at the tape flies over the
			# receiver's grounded blade — even after the receiver-relative solve.
			pass_should_saucer = best_pass_saucer
			if best_pass_saucer and receiver != null:
				pass_target_speed = clampf(
						AIPuckLane.saucer_max_launch_speed(
								puck_now.distance_to(receiver.position)),
						GameRules.DEFAULT_WRISTER_POWER_MIN_M_S,
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
			# Loft AND aim from the goalie-hole geometry, at the WINNING sample's
			# release/goalie/pace and the replicated pose (_shot_env_*), so both
			# describe one shot. The hole read includes screens (opponents and
			# in-zone teammates on the sightline), which the seam score does not.
			var shot_screen_dist: float = AIActionScoring.screen_along_m(
					_shot_sample_release, _shot_sample_goalie,
					_field.opponents_release, _field.receiver_pos)
			shot_loft_level = AIActionScoring.best_shot_loft(
					_shot_sample_release, attacking_goal, _shot_sample_goalie,
					GameRules.NET_HALF_WIDTH, _shot_sample_speed,
					_shot_env_unsettled, _shot_env_five_hole, _shot_env_goalie_down,
					_shot_env_seal_x, _shot_env_seal_tall, ctx.self_aim_spread_rad,
					shot_screen_dist, _shot_env_hands, _shot_env_pads, ctx.self_loft_tans)
			shot_aim_point = AIActionScoring.best_shot_aim(
					_shot_sample_release, attacking_goal, _shot_sample_goalie,
					GameRules.NET_HALF_WIDTH, _shot_sample_speed,
					_shot_env_unsettled, _shot_env_five_hole, _shot_env_goalie_down,
					ctx.self_aim_spread_rad,
					_shot_env_seal_x, _shot_env_seal_tall, shot_screen_dist,
					_shot_env_hands, _shot_env_pads, ctx.self_loft_tans)
			# Full power for every hole (see shot_power_t).
			shot_power_t = 1.0
			shot_hold_offset = shoot_now_hold
			shot_hold_share = _shot_sample_share
	elif retention_hopeless and not staggered:
		# Last resort, and the ONLY place the delivery search runs. Its job is to
		# pick WHICH delivery; its score is read only as availability (-INF where
		# no dump applies), and with none available the bot keeps skating and
		# the next re-eval looks again.
		_dump.search(ctx, _field, our_goalie)
		debug_dump_score = _dump.value
		if _dump.value > -INF:
			_hold_elapsed_s = 0.0
			new_intent = INTENT_DUMP
			dump_target = _dump.aim
			dump_is_soft = _dump.is_soft
			dump_is_rim = false
			dump_launch_speed = _dump.launch_speed
		else:
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


# Is a carry candidate on ice this bot can legally stand and handle on? In
# front of the net: rink side of both goal lines, a body's width off the boards.
#
# With `allow_behind` (the carrier is already behind a goal line) the ice back
# there is legal too, except what is genuinely illegal: off the playing surface
# (corners included) and inside the cage. Without it a carrier behind the net
# has no lateral move in the search — every local candidate fails the goal-line
# clamp — and plants on the end wall until stripped. The route to each candidate
# is still checked against the net by _score_move_candidate_base.
func _candidate_ice_legal(candidate: Vector3, allow_behind: bool) -> bool:
	if absf(candidate.x) > GameRules.RINK_HALF_WIDTH - AIRoleHelpers.RINK_INSET_M:
		return false
	if absf(candidate.z) <= GameRules.GOAL_LINE_Z - AIRoleHelpers.GOAL_LINE_BUFFER_M:
		return true
	if not allow_behind:
		return false
	# On the surface (rounded corners honoured) with a body's clearance.
	var xz := Vector2(candidate.x, candidate.z)
	if not GameRules.clamp_to_rink_inner(xz, AIRoleHelpers.RINK_INSET_M) \
			.is_equal_approx(xz):
		return false
	# Outside the cage (the same exclusion box the skater body is held clear of).
	return GameRules.push_out_of_net(xz).is_equal_approx(xz)


# The best carry, as [floored_score (float, ≥ 0), best_pos (Vector3),
# raw_score (float)]. Floored is the "keep the puck" value for the fire compete;
# raw keeps the honest sign for the dump's residual test (a pinned carry that
# will be stripped must read negative). Candidates:
#   - Stand-still (current position)
#   - Up to 6 field-derived FORWARD candidates: the space fan's best bearings
#     at two fractions of the planning beat (see CARRY_FIELD_*)
#   - Up to 10 REAR/LATERAL candidates: the five bearings the fan does not
#     span, each at two fractions of that bearing's OWN beat reach (see
#     _REAR_ANGLES)
#   - The OZ slot anchor (long-range "drive at slot")
#   - Two zone-exit wall routes in our defensive zone (see CARRY_EXIT_*)
#   - Two post walkouts when behind either goal line (see WALKOUT_*)
#   - The objective-directed evasion seam
#   - Two WHEEL exits, 5v5, behind our own goal line (see WHEEL_*)
#
# Movement candidates are scored in TWO PASSES (see CARRY_BEAM_WIDTH); a
# candidate whose straight route crosses a net frame prunes (the walkouts are
# the exempt, around-the-post routes).
#
# `shoot_now_score` is the top-level SHOOT eval (pre-ping, pre-hysteresis):
# stand-still's shot branch shares it verbatim — see the stand-still block.
func _best_carry(ctx: RoleContext, shoot_now_score: float,
		directed_seam: Vector3) -> Array:
	var self_pos: Vector3 = ctx.self_pos
	_field.holds.configure_from(ctx)
	var attacking_goal: Vector3 = ctx.attacking_goal_pos
	var own_goal_dir: float = ctx.own_goal_dir
	var our_goalie: Vector3 = AIRoleHelpers.resolve_our_goalie_pos(ctx)
	var slot_pos: Vector3 = AICarrierField.slot_anchor(own_goal_dir)
	# Forward = toward the slot; the attacking-goal axis when the bot is on it.
	var to_slot_x: float = slot_pos.x - self_pos.x
	var to_slot_z: float = slot_pos.z - self_pos.z
	var to_slot_len_sq: float = to_slot_x * to_slot_x + to_slot_z * to_slot_z
	var fwd_x: float
	var fwd_z: float
	if to_slot_len_sq < 0.001:
		fwd_x = 0.0
		fwd_z = -own_goal_dir
	else:
		var inv: float = 1.0 / sqrt(to_slot_len_sq)
		fwd_x = to_slot_x * inv
		fwd_z = to_slot_z * inv

	# Stand-still is compared last and wins only if STRICTLY greater than every
	# movement candidate: resolving carry ties toward movement keeps the bot
	# from dawdling when slot-drive is the play.
	var best_pos: Vector3 = self_pos
	var best_score: float = -INF

	# Stand-still is COMPUTED up front because it doubles as an exact pruning
	# floor: it always participates in this argmax, so a movement candidate whose
	# ceiling can't strictly beat stand_total can't affect the outcome. It seeds
	# the beam's pass-1 prune bound and the wheel's bound.
	var stand_score: float = shoot_now_score
	if not AIActionScoring.in_offensive_zone(self_pos, attacking_goal):
		var stand_potential: float = AIActionScoring.position_potential(
				self_pos, attacking_goal, _field.opponents)
		var stand_realization: float = AIActionScoring.potential_realization_discount(
				self_pos, attacking_goal)
		stand_score = maxf(stand_score, stand_potential * stand_realization)
	var stand_puck_pos: Vector3 = AICarrierField.puck_pos_at(self_pos, attacking_goal)
	var stand_safety: float = AICarrySpace.carry_safety(
			stand_puck_pos, stand_puck_pos, AICarrySpace.EVADE_HORIZON_S,
			_field.opponents, _field.opponent_vels, _field.opponent_caps)
	var stand_cost: float = _field.turnover_cost(ctx, stand_puck_pos,
			1.0 - stand_safety, our_goalie)
	stand_cost += _field.counter_exposure_cost(ctx, stand_puck_pos,
			1.0 - stand_safety, self_pos, our_goalie)
	var stand_total: float = stand_score * stand_safety - stand_cost

	# ── Pass 1 (beam base): one-ply rows for every legal candidate ───────────
	# Candidates stay ordered forward-first: the prune bound tightens to the
	# best one-ply total as rows land (see _beam_prune_bound), so a strong early
	# spot prunes the tail cheaply.
	_beam_pos.clear()
	_beam_total.clear()
	_beam_dest.clear()
	_beam_lane.clear()
	_beam_decay.clear()
	_beam_safety.clear()
	_beam_cost.clear()
	_beam_prune_bound = stand_total

	var behind_net: bool = absf(self_pos.z) > GameRules.GOAL_LINE_Z

	# FORWARD candidates — the top CARRY_FIELD_BEARINGS bearings of the space
	# field's per-bearing profile (_scratch_bearing_control), each at
	# CARRY_FIELD_RADII fractions of one planning beat of travel at the
	# carrier's real speed. Ranked by control × forward projection: control
	# alone would rate a wide-open sideways bearing above a merely-good netward
	# one, and the cos is the foreshortening the space aggregate itself uses.
	# See Scripts/domain/ai/CLAUDE.md → "Field-derived carry candidates".
	var beat_r: float = clampf(
			ctx.self_max_speed * CARRY_PLAN_BEAT_S,
			CARRY_SEARCH_STEP_M, AICarrierField.FORWARD_PRESSURE_HORIZON_M)
	if ctx.self_velocity.length_squared() > 1.0:
		beat_r = clampf(
				sqrt(ctx.self_velocity.x * ctx.self_velocity.x
						+ ctx.self_velocity.z * ctx.self_velocity.z) * CARRY_PLAN_BEAT_S,
				CARRY_SEARCH_STEP_M, AICarrierField.FORWARD_PRESSURE_HORIZON_M)
	for _rank: int in CARRY_FIELD_BEARINGS:
		var best_bi: int = -1
		var best_w: float = -1.0
		for bi: int in _scratch_bearing_control.size():
			var ang: float = AICarrySpace.SPACE_SAMPLE_ANGLES[bi]
			var wgt: float = _scratch_bearing_control[bi] * cos(ang)
			if wgt > best_w:
				best_w = wgt
				best_bi = bi
		if best_bi < 0:
			break
		var angle: float = AICarrySpace.SPACE_SAMPLE_ANGLES[best_bi]
		# Consume it so the next rank picks a different bearing.
		_scratch_bearing_control[best_bi] = -1.0
		var c: float = cos(angle)
		var s_a: float = sin(angle)
		var dir_x: float = fwd_x * c - fwd_z * s_a
		var dir_z: float = fwd_x * s_a + fwd_z * c
		for frac: float in CARRY_FIELD_RADII:
			var r: float = maxf(beat_r * frac, CARRY_SEARCH_STEP_M * 0.5)
			var candidate := Vector3(
					self_pos.x + dir_x * r, 0.0, self_pos.z + dir_z * r)
			if not _candidate_ice_legal(candidate, behind_net):
				continue
			_beam_score_base(ctx, candidate, our_goalie, false)

	# REAR/LATERAL ring (see _REAR_ANGLES). The radius is per BEARING, never the
	# forward beat_r: reusing it would grow the rear radii with speed, precisely
	# backwards — at pace a spot behind you costs shedding cross-speed, braking
	# out the reversal and re-accelerating. beat_reach_along returns negative
	# for a bearing off the reachable disc, so an unavailable direction produces
	# no candidate.
	for angle: float in _REAR_ANGLES:
		var c: float = cos(angle)
		var s_a: float = sin(angle)
		var dir_x: float = fwd_x * c - fwd_z * s_a
		var dir_z: float = fwd_x * s_a + fwd_z * c
		var reach: float = AICarrySpace.beat_reach_along(
				ctx.self_velocity, dir_x, dir_z, ctx.self_max_accel,
				CARRY_PLAN_BEAT_S)
		if reach < CARRY_REAR_MIN_STEP_M:
			continue
		for frac: float in CARRY_FIELD_RADII:
			var step: float = reach * frac
			if step < CARRY_REAR_MIN_STEP_M:
				continue
			var candidate := Vector3(
					self_pos.x + dir_x * step, 0.0, self_pos.z + dir_z * step)
			if not _candidate_ice_legal(candidate, behind_net):
				continue
			_beam_score_base(ctx, candidate, our_goalie, false)

	# Slot anchor — the long-range candidate, valid from anywhere on the rink.
	_beam_score_base(ctx, slot_pos, our_goalie, false)

	# Zone-exit wall routes (see CARRY_EXIT_*), only in our own DEFENSIVE ZONE:
	# never gate on own HALF, because past our blue line the exit target sits
	# BEHIND the carrier.
	if own_goal_dir * self_pos.z > GameRules.BLUE_LINE_Z:
		var exit_x: float = GameRules.RINK_HALF_WIDTH - CARRY_EXIT_WALL_INSET_M
		var exit_z: float = own_goal_dir * (GameRules.BLUE_LINE_Z - CARRY_EXIT_NZ_LEAD_M)
		_beam_score_base(ctx, Vector3(exit_x, 0.0, exit_z), our_goalie, false)
		_beam_score_base(ctx, Vector3(-exit_x, 0.0, exit_z), our_goalie, false)

	# Post walkouts (see WALKOUT_*): one outside each post; EV picks the side.
	if absf(self_pos.z) > GameRules.GOAL_LINE_Z:
		var behind_sign: float = signf(self_pos.z)
		var walk_z: float = behind_sign * (GameRules.GOAL_LINE_Z - WALKOUT_FRONT_M)
		var walk_x: float = GameRules.NET_HALF_WIDTH + WALKOUT_POST_CLEARANCE_M
		for side: float in [-1.0, 1.0]:
			_beam_score_base(
					ctx, Vector3(side * walk_x, 0.0, walk_z), our_goalie, true)

	# The objective-directed evasion seam (see evade_seam_world): the bot cuts
	# past a committed defender into the lane he vacates, and it wins only when
	# that space is worth carrying to.
	_beam_score_base(ctx, directed_seam, our_goalie, false)

	# ── Pass 2: complete the two-ply reads for the beam's best rows ──────────
	# Best-first, consuming each row as it upgrades. Rows outside the beam never
	# enter best_score (see CARRY_BEAM_WIDTH).
	for rank: int in CARRY_BEAM_WIDTH:
		var bi: int = -1
		var bt: float = -INF
		for j: int in _beam_total.size():
			if _beam_total[j] > bt:
				bt = _beam_total[j]
				bi = j
		if bi == -1:
			break
		var up_total: float = _upgrade_candidate_two_ply(ctx, bi)
		if up_total > best_score:
			best_score = up_total
			best_pos = _beam_pos[bi]
		_beam_total[bi] = -INF   # consumed — next rank takes the next-best row

	# WHEEL exits (see WHEEL_*), only for destinations whose straight route the
	# cage blocks — a side the straight line reaches is already covered above.
	# Already a complete two-leg read, so it competes after the beam.
	if absf(self_pos.z) > GameRules.GOAL_LINE_Z \
			and ctx.team_size >= 5 and own_goal_dir * self_pos.z > 0.0:
		var wheel_x: float = GameRules.RINK_HALF_WIDTH - CARRY_EXIT_WALL_INSET_M
		var wheel_z: float = own_goal_dir \
				* (GameRules.GOAL_LINE_Z - WHEEL_EXIT_UP_ICE_M)
		for side: float in [-1.0, 1.0]:
			var wheel := Vector3(side * wheel_x, 0.0, wheel_z)
			if not AINetObstacle.carry_path_blocked_by_net(self_pos, wheel):
				continue
			var wheel_total: float = _score_wheel_candidate(
					ctx, wheel, our_goalie, maxf(best_score, stand_total))
			if wheel_total > best_score:
				best_score = wheel_total
				best_pos = wheel

	# Stand-still last, winning only on STRICTLY greater. Its shot branch is the
	# shoot-now score verbatim because "hold and fire from here" and SHOOT are the
	# same physical act; priced separately at the CURRENT spot, a mid-cut hold
	# would read richer than the fire from the same instant and the bot would
	# hold exactly when the window is open. Sharing it makes fire-wins-ties hold
	# by definition: stand_total = shoot_now × safety − cost ≤ shoot_now ≤ fire.
	# Stand pays the strip cost like every candidate; without it freezing would be
	# the one option that never prices losing the puck, and a bot under a
	# converging forechecker would plant itself exactly when it should skate clear.
	if stand_total > best_score:
		best_score = stand_total
		best_pos = self_pos

	return [maxf(best_score, 0.0), best_pos, best_score]


# Pass-1 candidate entry (see CARRY_BEAM_WIDTH): base-score `candidate` into
# the beam rows and tighten the running prune bound to the best one-ply
# total so far (see _beam_prune_bound for why that stays exact).
func _beam_score_base(ctx: RoleContext, candidate: Vector3,
		our_goalie: Vector3, is_post_walkout: bool) -> void:
	var total: float = _score_move_candidate_base(
			ctx, candidate, our_goalie, is_post_walkout, _beam_prune_bound)
	if total > _beam_prune_bound:
		_beam_prune_bound = total


# One-ply EV of one movement carry candidate — the scoring every non-stand-still
# candidate in the beam runs:
#
#   dest_score × lane × decay × safety − turnover_cost
#
# `safety` is the reachable clearance over the PUCK's path to the candidate
# across the arrival time, so it sees both a defender converging on the ROUTE
# and one waiting at the DESTINATION; a committed charger whose momentum
# carries him past reads as clear. 1 − safety is the strip probability, priced
# at the EARLIEST covered point on the route (carry_strip_point), not the
# destination: a carry that ends in open ice but threads our own slot pays the
# slot's turnover cost.
#
# Returns -INF for an illegal or unreachable candidate, or one whose ceiling
# cannot beat `best_so_far`. Every finite score appends a beam row stashing the
# intermediates _upgrade_candidate_two_ply needs, so pass 2 recomputes nothing.
func _score_move_candidate_base(ctx: RoleContext, candidate: Vector3,
		our_goalie: Vector3, is_post_walkout: bool = false,
		best_so_far: float = -INF) -> float:
	var self_pos: Vector3 = ctx.self_pos
	# One-way valve: once in the offensive zone, don't carry the puck back out,
	# buffered by OZ_RETREAT_LINE_BUFFER_M. Stand-still never trips this, so the
	# candidate set is never empty; a carrier already inside the band keeps only
	# deeper candidates, easing it off the line.
	if AIActionScoring.in_offensive_zone(self_pos, ctx.attacking_goal_pos) \
			and not AIActionScoring.in_offensive_zone(
					candidate, ctx.attacking_goal_pos, OZ_RETREAT_LINE_BUFFER_M):
		return -INF
	# Its NHL mirror: with a teammate owing a tag-up, carrying in is whistled at
	# once. Judged on the body, so stand-still (outside) always survives; the last
	# stick of puck lead is the steering's offside brake on the puck.
	if ctx.zone_entry_blocked \
			and AIActionScoring.in_offensive_zone(candidate, ctx.attacking_goal_pos) \
			and not AIActionScoring.in_offensive_zone(self_pos, ctx.attacking_goal_pos):
		return -INF
	# The cage is a wall: the time/lane/safety math below assumes the straight
	# traverse. POST-WALKOUT candidates are exempt — they are reached around the
	# post (the steering's net detour), which the straight-segment test can't see.
	if not is_post_walkout \
			and AINetObstacle.carry_path_blocked_by_net(self_pos, candidate):
		return -INF
	var local_time: float = AIArrival.time_to_arrive(
			self_pos, candidate, ctx.self_velocity, ctx.self_max_speed,
			ctx.self_max_accel, ctx.self_lateral_grip)
	# CEILING PRUNES (exact): with dest_score ≤ 1 and cost ≥ 0, each partial
	# product of the ≤ 1 factors is a hard upper bound, checked in cost order —
	# decay alone before the opponent projection, × lane before the safety read,
	# × safety before the arrival-shot / strip machinery. Under pressure SAFETY
	# is the killer, so a swarmed carrier doesn't pay full price for doomed spots.
	var decay: float = AIActionScoring.delay_discount(local_time)
	if decay <= best_so_far:
		return -INF
	_field.project_opponents(local_time, _scratch_opponents_path)
	var lane: float = AICarrySpace.carry_lane_clearance(
			self_pos, candidate, local_time, _field.opponents, _field.opponent_vels,
			ctx.self_max_speed)
	if lane <= 0.0:
		return -INF
	if lane * decay <= best_so_far:
		return -INF
	var cand_puck_pos: Vector3 = AICarrierField.puck_pos_at(candidate, ctx.attacking_goal_pos)
	var cur_puck_pos: Vector3 = AICarrierField.puck_pos_at(self_pos, ctx.attacking_goal_pos)
	# apply_escape: a defender the carrier out-skates on this drive can't sustain
	# the strip, so driving PAST a man reads as winnable, not as a wall.
	var safety: float = AICarrySpace.carry_safety(
			cur_puck_pos, cand_puck_pos, local_time,
			_field.opponents, _field.opponent_vels, _field.opponent_caps,
			true)
	if lane * decay * safety <= best_so_far:
		return -INF
	# The candidate's shot is taken ARRIVING AT PACE (carry steps are skated at
	# speed; the arrival brake skips carry waypoints), so it is the same
	# moving-release wrister the shoot-now eval prices. Two-phase keeper:
	#   1. TRACK: he follows the whole carry to the candidate's arc-square
	#      (generous to him: he never falls behind en route).
	#   2. FINAL RACE: from that square he races the wind-up + flight against a
	#      release still sliding at the arrival speed — the race a hard lateral
	#      cut in tight genuinely wins.
	# Phase 2 is what gives a STANDSTILL 1v1 a gradient toward building the
	# lateral speed that opens the window; a static release would score every
	# one-step spot against a set keeper ~0. Because he is SQUARE at every
	# candidate before the final race, a further cut never prices more than the
	# last-quarter-second window, so the cut cannot recede forever.
	#
	# The arrival UNSETTLE is read from the TRACKED keeper over the FINAL window
	# only: the carry never catches him, only the re-square the release demands
	# can. Never measure it from his CURRENT position over the whole carry — that
	# charges him for a swing his tracking already covers and makes every
	# doorstep drive a phantom caught-moving goalie.
	var to_cand: Vector3 = candidate - self_pos
	to_cand.y = 0.0
	var cand_dist: float = to_cand.length()
	var arrive_vel: Vector3 = Vector3.ZERO
	if cand_dist > 0.001 and local_time > 0.001:
		# Arrival pace consistent with time_to_arrive's constant-effective-speed
		# travel model, capped at this bot's real top end.
		var arrive_speed: float = minf(cand_dist / local_time, ctx.self_max_speed)
		arrive_vel = to_cand * (arrive_speed / cand_dist)
	# The shot on arrival is held as the shoot-now sweep would hold it
	# (arrival_hold_wait): at that hold's pace and keep odds, with any pull the
	# carry is too short for waited out in the wind-up the keeper races.
	var cand_wait: float = 0.0
	var cand_share: float = 1.0
	var cand_keep: float = 1.0
	if AICarrierField.shot_reads(ctx, self_pos,
			candidate + arrive_vel * AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S):
		cand_wait = _field.arrival_hold_wait(ctx, candidate, arrive_vel, local_time)
		cand_share = _field.holds.arrival_share
		cand_keep = _field.holds.arrival_keep
	var cand_speed: float = ctx.self_wrister_shot_speed * cand_share
	var cand_windup: float = AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S + cand_wait
	# The keeper backs in as the carry closes on him (the planning depth model).
	# Closing is the rate this carry shortens the puck's distance to the goal.
	var carry_closing: float = (self_pos.distance_to(ctx.attacking_goal_pos)
			- candidate.distance_to(ctx.attacking_goal_pos)) / maxf(local_time, 0.001)
	var tracked_goalie: Vector3 = AIGoalieModel.predict_goalie_pos(
			AICarrierField.goalie_now(ctx), ctx.attacking_goal_pos, local_time, candidate,
			carry_closing)
	var cand_release: Vector3 = AIGoalieModel.release_ahead_of_goalie(
			candidate + arrive_vel * cand_windup,
			ctx.attacking_goal_pos, tracked_goalie)
	var cand_flight: float = cand_release.distance_to(ctx.attacking_goal_pos) \
			/ maxf(cand_speed, 1.0)
	# Same expected-lateness budget as the shoot-now sweep (timing error × 0.5),
	# and the keeper still backing in over the wind-up + flight at the arrival
	# pace.
	var release_closing: float = AIGoalieModel.closing_toward(
			candidate, arrive_vel, ctx.attacking_goal_pos)
	var cand_goalie: Vector3 = AIGoalieModel.predict_goalie_pos(
			tracked_goalie, ctx.attacking_goal_pos,
			cand_windup + cand_flight + ctx.shot_timing_error_s * 0.5,
			cand_release, release_closing)
	var cand_unsettled: float = 0.0
	if ctx.reads_goalie_motion:
		cand_unsettled = AIGoalieModel.goalie_unsettled(
				tracked_goalie, ctx.attacking_goal_pos,
				cand_windup + cand_flight + ctx.shot_timing_error_s * 0.5,
				cand_release, release_closing)
	# Displacement at the release: from where he is NOW over everything the play
	# gives him — carry, wind-up and flight. Measured at the DESTINATION, never as
	# a max over route samples: the ~30 Hz re-decide already re-prices the shot
	# at every point on the route, and a max over samples is optimistically
	# biased against the shoot and pass legs, which get one estimate each.
	var release_t: float = local_time + cand_windup + cand_flight \
			+ ctx.shot_timing_error_s * 0.5
	var cand_displacement: float = AIShotValue.displacement_deficit_m(
			AICarrierField.goalie_now(ctx), ctx.attacking_goal_pos, cand_release, release_t)
	var dest_score: float = _field.value_at(ctx, cand_release, self_pos,
			_scratch_opponents_path, cand_goalie,
			cand_speed, cand_unsettled, ctx.self_aim_spread_rad,
			cand_displacement, ctx.self_loft_tans.z, cand_keep)
	# ENTRY CONTINUATION: from outside the zone an in-zone candidate is worth what
	# a carrier there does next — the drive-in from it, priced in the in-zone
	# regime and starting when we arrive — which its own shot xG badly
	# understates just inside the line.
	if AIActionScoring.in_offensive_zone(candidate, ctx.attacking_goal_pos) \
			and not AIActionScoring.in_offensive_zone(self_pos, ctx.attacking_goal_pos):
		dest_score = maxf(dest_score, AICarrierField.entry_value(_field.receiver_drive_in_value(
				ctx, candidate, ctx.self_wrister_shot_speed,
				ctx.caps_by_peer.get(ctx.peer_id), arrive_vel, candidate, local_time, true)))
	var keep_prob: float = safety
	var cost: float = 0.0
	# A fully safe route (the common open-ice case) skips localizing a strip
	# that cannot happen.
	if keep_prob < 1.0:
		var strip_point: Vector3 = AICarrySpace.carry_strip_point(
				cur_puck_pos, cand_puck_pos, local_time,
				_field.opponents, _field.opponent_vels, _field.opponent_caps, true)
		cost = _field.turnover_cost(ctx, strip_point,
			1.0 - keep_prob, our_goalie)
		# Transition exposure (5v5): the carrier's recovery race starts from the
		# CANDIDATE, the spot this carry commits him to.
		cost += _field.counter_exposure_cost(ctx, strip_point, 1.0 - keep_prob,
				candidate, our_goalie)
	var total: float = dest_score * lane * decay * safety - cost
	# Beam row: this candidate's final value unless pass 2 upgrades it.
	_beam_pos.append(candidate)
	_beam_total.append(total)
	_beam_dest.append(dest_score)
	_beam_lane.append(lane)
	_beam_decay.append(decay)
	_beam_safety.append(safety)
	_beam_cost.append(cost)
	return total


# TWO-PLY pass of the beam (see CARRY_BEAM_WIDTH): completes beam row `i` with
# the pass OPTION the spot opens (pass_option_from), credited as the
# IMPROVEMENT over the same read at the current spot — a lane already open from
# here is the live pass's to take, so holding a cashable option is never a
# reason to keep carrying. CEILING PRUNE (exact): the credit can't exceed
# _field.pass_option_ceiling − _field.pass_option_at_self, so when that can't raise
# dest_score the per-receiver lane loop is skipped.
func _upgrade_candidate_two_ply(ctx: RoleContext, i: int) -> float:
	var candidate: Vector3 = _beam_pos[i]
	var dest_score: float = _beam_dest[i]
	var lane: float = _beam_lane[i]
	var decay: float = _beam_decay[i]
	var safety: float = _beam_safety[i]
	if _field.pass_option_ceiling - _field.pass_option_at_self > dest_score:
		dest_score = maxf(dest_score, maxf(
				0.0, _field.pass_option_from(ctx, candidate,
						dest_score + _field.pass_option_at_self) - _field.pass_option_at_self))
	return dest_score * lane * decay * safety - _beam_cost[i]


# FULL eval of a single candidate — base + two-ply upgrade in one call, for the
# single-candidate consumers (unit tests, the ai_micro bench); the compete runs
# the two-pass beam form. Leaves the candidate's row in the beam scratch, which
# the next _best_carry clears.
func _score_move_candidate(ctx: RoleContext, candidate: Vector3,
		our_goalie: Vector3, is_post_walkout: bool = false,
		best_so_far: float = -INF) -> float:
	var rows_before: int = _beam_total.size()
	var base: float = _score_move_candidate_base(
			ctx, candidate, our_goalie, is_post_walkout, best_so_far)
	if _beam_total.size() == rows_before:
		return base   # ceiling-pruned — no row to upgrade
	return _upgrade_candidate_two_ply(ctx, _beam_total.size() - 1)


# EV of a WHEEL candidate (see WHEEL_*): the two-leg carry self → the behind-net
# apex → the far half-wall exit. The same pricing pieces as
# _score_move_candidate_base, applied PER LEG with the defense projected through
# leg one, because a straight-line read for this route would sample the inside
# of the cage. The escape gate (apply_escape) makes a committed same-side chaser
# read as beaten, while a body already waiting on the far side kills leg two.
func _score_wheel_candidate(ctx: RoleContext, dest: Vector3,
		our_goalie: Vector3, best_so_far: float) -> float:
	var self_pos: Vector3 = ctx.self_pos
	var apex := Vector3(0.0, 0.0, ctx.own_goal_dir
			* (GameRules.GOAL_LINE_Z + GameRules.NET_DEPTH + WHEEL_APEX_CLEARANCE_M))
	var t1: float = AIArrival.time_to_arrive(
			self_pos, apex, ctx.self_velocity, ctx.self_max_speed,
			ctx.self_max_accel, ctx.self_lateral_grip)
	# Carry pace through the apex, consistent with the arrival model.
	var to_dest: Vector3 = dest - apex
	to_dest.y = 0.0
	var apex_speed: float = minf(
			self_pos.distance_to(apex) / maxf(t1, 0.001), ctx.self_max_speed)
	var v_apex: Vector3 = to_dest.normalized() * apex_speed \
			if to_dest.length_squared() > 0.0001 else Vector3.ZERO
	var t2: float = AIArrival.time_to_arrive(
			apex, dest, v_apex, ctx.self_max_speed, ctx.self_max_accel, ctx.self_lateral_grip)
	# The same exact ceiling ladder as _score_move_candidate_base, per leg.
	var decay: float = AIActionScoring.delay_discount(t1 + t2)
	if decay <= best_so_far:
		return -INF
	var lane1: float = AICarrySpace.carry_lane_clearance(
			self_pos, apex, t1, _field.opponents, _field.opponent_vels,
			ctx.self_max_speed)
	if lane1 <= 0.0 or lane1 * decay <= best_so_far:
		return -INF
	var cur_puck: Vector3 = AICarrierField.puck_pos_at(self_pos, ctx.attacking_goal_pos)
	var apex_puck: Vector3 = AICarrierField.puck_pos_at(apex, ctx.attacking_goal_pos)
	var dest_puck: Vector3 = AICarrierField.puck_pos_at(dest, ctx.attacking_goal_pos)
	var safety1: float = AICarrySpace.carry_safety(
			cur_puck, apex_puck, t1, _field.opponents,
			_field.opponent_vels, _field.opponent_caps, true)
	if lane1 * decay * safety1 <= best_so_far:
		return -INF
	# Leg two starts where the defense has skated to during leg one.
	_field.project_opponents(t1, _scratch_opponents_cont)
	var lane2: float = AICarrySpace.carry_lane_clearance(
			apex, dest, t2, _scratch_opponents_cont, _field.opponent_vels,
			ctx.self_max_speed)
	if lane2 <= 0.0:
		return -INF
	var safety2: float = AICarrySpace.carry_safety(
			apex_puck, dest_puck, t2, _scratch_opponents_cont,
			_field.opponent_vels, _field.opponent_caps, true)
	var keep: float = safety1 * safety2
	var ceiling: float = lane1 * lane2 * decay * keep
	if ceiling <= best_so_far:
		return -INF
	_field.project_opponents(t1 + t2, _scratch_opponents_cont)
	var dest_score: float = _field.value_at(ctx, dest, self_pos,
			_scratch_opponents_cont, AICarrierField.goalie_now(ctx),
			ctx.self_wrister_shot_speed, 0.0, ctx.self_aim_spread_rad, 0.0,
			ctx.self_loft_tans.z)
	var benefit: float = dest_score * ceiling
	if keep >= 1.0:
		return benefit
	# The strip is priced on whichever leg is the unsafe one.
	var strip_point: Vector3
	if safety1 <= safety2:
		strip_point = AICarrySpace.carry_strip_point(
				cur_puck, apex_puck, t1, _field.opponents,
				_field.opponent_vels, _field.opponent_caps, true)
	else:
		_field.project_opponents(t1, _scratch_opponents_cont)
		strip_point = AICarrySpace.carry_strip_point(
				apex_puck, dest_puck, t2, _scratch_opponents_cont,
				_field.opponent_vels, _field.opponent_caps, true)
	var cost: float = _field.turnover_cost(ctx, strip_point,
			1.0 - keep, our_goalie)
	cost += _field.counter_exposure_cost(ctx, strip_point, 1.0 - keep, dest, our_goalie)
	return benefit - cost


# How much room the carrier has to OPERATE toward the attacking objective —
# the controlled fraction of the forward cone over AICarrierField.FORWARD_PRESSURE_HORIZON_M
# (AICarrySpace.controlled_space), 1.0 when the ice ahead is his. Feeds the
# carry's pass-first discount (see FORWARD_PRESSURE_*) and, as a by-product,
# _scratch_bearing_control.
func _carrier_forward_clearance(ctx: RoleContext) -> float:
	# Size once, then reuse: controlled_space refills every entry each call.
	if _scratch_bearing_control.size() != AICarrySpace.SPACE_SAMPLE_ANGLES.size():
		_scratch_bearing_control.resize(
				AICarrySpace.SPACE_SAMPLE_ANGLES.size())
	return AICarrySpace.controlled_space(
			ctx.self_pos, ctx.self_velocity, ctx.caps_by_peer.get(ctx.peer_id),
			ctx.attacking_goal_pos, AICarrierField.FORWARD_PRESSURE_HORIZON_M,
			_field.opponents, _field.opponent_vels, _field.opponent_caps,
			_scratch_bearing_control)

