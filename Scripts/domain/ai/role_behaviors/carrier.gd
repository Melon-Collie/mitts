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
var _holds := AIShotHolds.new()


# The fastest charged pass along `dir` (world XZ) this bot can load: its pace at
# the pocket's share, the hold the state machine pulls the puck to first when
# the puck's own spot can't carry the feed.
func _pass_launch_cap(ctx: RoleContext, dir: Vector3, facing: Vector2) -> float:
	_holds.configure_from(ctx)
	_holds.pocket(Vector2(dir.x, dir.z), Vector2(ctx.self_velocity.x, ctx.self_velocity.z),
			facing)
	return ctx.self_wrister_shot_speed * _holds.pocket_result.power_share


# ── Smart-ping obedience ─────────────────────────────────────────────────────
# EV multipliers a live human ping applies inside the normal compete — a
# tactical ORDER, not an evaluation curve. A bias rather than a force: the
# giveaway floors still veto a hopeless order (a zero shot stays zero, a dead
# lane stays dead), but any reasonable read wins, so the bot visibly obeys.
const PING_SHOOT_EV_MULT: float = 3.0
const PING_PASS_EV_MULT: float = 3.0

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

# Cap on a pass's solved lead time (s); longer leads rest on stale opponent
# projections.
const PASS_LEAD_MAX_S: float = 0.6

# Receiver drive-in credit (see _receiver_drive_in_value): the MAX distance an open
# man is credited with carrying toward the net (the actual reach is the clear
# extent of that path), and the closest to the net that drive may end (no credit
# for a drive into the crease). The max is a horizon cap, finite because opponent
# projections go stale over a long carry. Feel tunables, not an evaluation curve.
const RECEIVER_DRIVE_MAX_M: float = 12.0
const RECEIVER_DRIVE_MIN_NET_DIST_M: float = 3.0

# Forward-pressure discount on the CARRY (see _carrier_forward_clearance). The
# strip model prices a defender ON the puck but not one sitting in the path the
# carrier must beat to advance, so without this a lightly-pressured carrier
# grinds forward instead of moving the puck to an unimpeded teammate. HORIZON is
# how far ahead the contest is felt; MIN_SCALE is the most a fully-blocked path
# discounts the carry (never to zero — a carrier with no outlet still carries).
# Feel tunables; the clearance itself is the grounded read. Applied ONLY to the
# fire-vs-carry compete, never to the raw carry the dump is judged against.
const FORWARD_PRESSURE_HORIZON_M: float = 9.0
const FORWARD_PRESSURE_MIN_SCALE: float = 0.55

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

# RECEIVE: how far inside the line a pass target's intercept lead must sit
# when the carrier is in the OZ (see _pass_variant_ev). The catch plays the puck
# up to a stick's reach around the body and gives with it (~a stride), so
# routine reception slop on a line-hugging target takes the puck out. Such feeds
# are hard reads for a human receiver too, so they're excluded, not discounted.
const OZ_RECEIVE_LINE_BUFFER_M: float = GameRules.DEFAULT_STICK_LENGTH_M + 0.7
# A rim is fired as soft as the race allows: any launch reaching the receiver at
# least this share as surely as the best one may be picked, and the softest of
# those is. Doctrine, not a measurement — a soft rim is easier to stop, and one
# that gets by him dies sooner (under NHL rules, short of an icing).
const RIM_SOFT_SHARE: float = 0.9

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

# Developing-feed hold: how far ahead (s) a skating teammate's spot is projected
# when valuing the pass he is CREATING (see _best_developing_feed) — the spot he
# is getting open at. 1.2 s ≈ a finisher's next two strides at a zone entry,
# still inside the pass-lead horizon by release; the delay discount prices the
# wait. Much shorter (~0.7 s) and the window cannot see past the calibrated
# surface's dead mid-band, so a fresh entry reads "nothing developing" while the
# house drive is one stride from being the best play on the ice.
const OUTLET_DEVELOP_WINDOW_S: float = 1.2
# Below this speed the outlet isn't going anywhere — the spot it offers
# is the spot it's at, and the live pass scoring already prices that.
const OUTLET_DEVELOP_MIN_SPEED_M_S: float = 1.0

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


# Haircut on the pass-OPTION value a carry candidate inherits (see
# _candidate_pass_option): the option is a coarse read — receiver valued at his
# CURRENT spot, lane judged against CURRENT defenders — and it still has to
# survive until the carrier arrives and releases. Tactical haircut; the grounded
# terms are inside the option itself.
const PASS_OPTION_DISCOUNT: float = 0.8

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

# LAUNCH speed for the chosen PASS (AIActionScoring.pass_launch_speed): set so
# the puck arrives on the teammate's tape at the magnet pace, friction-compensated
# by distance. The state machine maps this to the wrister charge fraction it winds
# up to, and leads the pass at this speed.
var pass_target_speed: float = AIActionScoring.PASS_SPEED_M_S

# Set alongside pass_target_peer_id when the chosen PASS is the LOW-loft saucer
# variant (see _pass_variant_ev). The state machine reads it entering
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

# How far down the chosen launch line the dump's aim point is placed. Distance
# is not direction, but it has to clear the blade: the quick release aims
# blade->cursor and the blade is the ROM-projection of that same cursor, so a
# cursor inside the stick's reach carries no direction at all. Comfortably
# outside any reach.
const DUMP_AIM_STANDOFF_M: float = 20.0

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
var dump_launch_speed: float = AIActionScoring.PASS_SPEED_M_S

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
# The best launch _rim_launch_for found, and its path reads.
var _rim_k: int = -1
var _rim_t: float = 0.0
var _rim_lane: float = 0.0
var _rim_miss: float = 0.0
# Per-launch reads for one receiver (index-matched to AIRimPass' scratch, -1 =
# not a candidate), so the softest near-best launch can be picked after the scan.
var _rim_sure_by_k: PackedFloat64Array = PackedFloat64Array()
var _rim_t_by_k: PackedFloat64Array = PackedFloat64Array()
var _rim_lane_by_k: PackedFloat64Array = PackedFloat64Array()
var _rim_miss_by_k: PackedFloat64Array = PackedFloat64Array()
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

# ── Transition-exposure appetite (5v5 only — plan §6) ────────────────────────
# The per-position risk-aversion FEEL scalar on the counter-rush cost: the model
# does the seeing, this sets the appetite. Forwards discount it because the
# F3-high rotation is expected to absorb a forward caught deep. 3v3 pays zero
# (gated on ctx.team_size in _counter_exposure_cost).
const EXPOSURE_APPETITE_DEFENSE: float = 1.0
const EXPOSURE_APPETITE_FORWARD: float = 0.7
# Loss probabilities below this skip the counter read entirely (hot-path
# floor, not a tuning knob: at 4% × a bounded threat the term is noise).
const EXPOSURE_PROB_FLOOR: float = 0.04

# ── Scratch buffers (reused across ticks, refilled per call) ────────────────
var _scratch_opponents: Array[Vector3] = []
# Velocities index-matched to _scratch_opponents.
var _scratch_opponent_vels: Array[Vector3] = []
# AISkaterCaps index-matched to _scratch_opponents (entries may be null), so the
# reachable-set model reads each defender's real reach.
var _scratch_opponent_caps: Array[AISkaterCaps] = []
# Opponent positions advanced by the commit→release windup
# (BOT_WRISTER_LOOKAHEAD_S): the shot and the charged pass both leave the blade
# ~135 ms after the intent commits, so their lanes are priced at release-time
# defender spots. Index-matched to _scratch_opponent_vels / _caps.
var _scratch_opponents_release: Array[Vector3] = []
var _scratch_opponents_pass: Array[Vector3] = []
var _scratch_opponents_path: Array[Vector3] = []
# Two-leg (wheel/apex) projections: filled at the apex arrival time for the
# second leg's reach read, then refilled at destination arrival for that
# leg's lane/pressure read.
var _scratch_opponents_cont: Array[Vector3] = []
# Opponents at the start of an entry continuation (_receiver_drive_in_value).
var _scratch_opponents_entry: Array[Vector3] = []
var _scratch_teammate_ids: Array[int] = []
# Our skaters excluding the carrier (the man who just lost it covers nothing) —
# the defenders that reduce the opponent's threat in the turnover-cost term.
# Rebuilt every re-eval; caps index-matched.
var _scratch_our_defenders: Array[Vector3] = []
var _scratch_our_defender_caps: Array[AISkaterCaps] = []
# Teammate velocities, in the same order — the dump's chase clock is
# momentum-honest (see _best_dump), so the race needs their motion too.
var _scratch_our_defender_vels: Array[Vector3] = []
# Caller-owned out-param for the dump-in landing solve, so the release search
# returns its resting spot without allocating on the compete path.
var _scratch_dump_landing: Array[Vector3] = [Vector3.ZERO]
# Teammate ETAs to the counter point (transition exposure, 5v5) — rebuilt
# with _scratch_our_defenders, candidate-invariant across one compete.
var _scratch_exposure_mate_etas: Array[float] = []
# Lane of the last FLAT _pass_variant_ev (0.0 when the variant filtered out
# before its lane solve). The saucer gate reads it — see _compute_best_pass.
var _last_flat_variant_lane: float = 0.0
# The forward-space read _pass_ev resolved for the receiver it just priced, so
# the flat and saucer variants of one feed share a single solve. Reset to -1
# before each receiver's first variant.
var _last_receiver_space: float = -1.0
# Per-bearing control from the carrier's own forward-space read, filled every
# re-eval by _carrier_forward_clearance and consumed by _best_carry's candidate
# generator, which overwrites entries as it takes them.
var _scratch_bearing_control: Array[float] = []
# Counter-threat memo by covering-body count (see counter_rush_cost) —
# -1-seeded alongside the ETAs each compete.
var _scratch_exposure_threat_memo: Array[float] = []
# Our chasers for a dump race: our defenders plus ourselves (we dump and chase),
# and their velocities index-matched — the race is run on ETAs, so a chaser's
# momentum is part of it. Rebuilt inside _best_dump.
var _scratch_our_chasers: Array[Vector3] = []
var _scratch_our_chaser_vels: Array[Vector3] = []
# Legal DZ-clear launches and where each comes to rest, index-matched
# (AIActionScoring.dump_clear_candidates fills them; _best_dump prices them).
var _scratch_clear_vels: Array[Vector3] = []
var _scratch_clear_spots: Array[Vector3] = []
# Each clear candidate's recovery odds, filled by _best_dump's first pass so the
# second doesn't re-race the same bodies to the same spots.
var _scratch_clear_recovery: Array[float] = []
# Directional-filtered opponents for the puck-protect read: the full opponent
# set minus defenders the carrier's body already screens (see
# PROTECT_SCREEN_BEHIND_M). Kept separate from _scratch_opponents so the shot /
# pass / carry lanes still see every defender. Index-matched triple, refilled
# every re-eval by _fill_protect_opponents.
var _scratch_protect_opponents: Array[Vector3] = []
var _scratch_protect_vels: Array[Vector3] = []
var _scratch_protect_caps: Array[AISkaterCaps] = []
# Pass-OPTION cache (see _candidate_pass_option): each legal receiver's
# position and spot value at its CURRENT location, so the per-candidate option
# read only prices the LANE from the candidate. Index-matched pair; refilled
# every re-eval.
var _scratch_option_receiver_pos: Array[Vector3] = []
var _scratch_option_receiver_val: Array[float] = []
# The pass-option read at the current puck spot — candidates credit only their
# improvement over this.
var _pass_option_at_self: float = 0.0
# Best cached receiver value × PASS_OPTION_DISCOUNT — the exact upper bound on
# any candidate's option read.
var _pass_option_ceiling: float = 0.0

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
	for opp: Vector3 in _scratch_opponents:
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
	pass_target_speed = AIActionScoring.PASS_SPEED_M_S
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
	dump_launch_speed = AIActionScoring.PASS_SPEED_M_S
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
	pass_target_speed = AIActionScoring.PASS_SPEED_M_S
	pass_should_saucer = false
	dump_target = Vector3.INF
	dump_is_soft = false
	dump_is_rim = false
	dump_launch_speed = AIActionScoring.PASS_SPEED_M_S
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

	_build_action_opponents_lists(ctx)

	# Our current possession safety, read as EVADABILITY — the clearance at the
	# best seam we could handle the puck into — so pressure we can dance out of
	# doesn't read as danger while a stick on the puck does. Feeds the hold's
	# keep-probability in the commit phase.
	var cur_puck_pos: Vector3 = _puck_pos_at(self_pos, attacking_goal)
	var evade_seam: Vector3 = AICarrySpace.best_evade_point(
			cur_puck_pos, ctx.self_velocity, _scratch_opponents, _scratch_opponent_vels,
			ctx.self_handle_reach, _scratch_opponent_caps)
	_phase_current_safety = AICarrySpace.clearance_to_safety(
			AICarrySpace.reach_clearance(evade_seam, AICarrySpace.EVADE_HORIZON_S,
					_scratch_opponents, _scratch_opponent_vels, _scratch_opponent_caps))
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
			_scratch_opponents, _scratch_opponent_vels,
			ctx.self_handle_reach, _scratch_opponent_caps)
	evade_seam_world = directed_seam
	# Gated with the other protect-tier reads: the brake check is taught puck
	# skill.
	brake_check_favored = ctx.protects_the_puck \
			and AICarrySpace.prefers_brake_check(
					cur_puck_pos, ctx.self_velocity, directed_seam,
					_scratch_opponents, _scratch_opponent_vels, _scratch_opponent_caps)

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
			for i: int in _scratch_opponents.size():
				var to_opp: Vector3 = _scratch_opponents[i] - cur_puck_pos
				to_opp.y = 0.0
				var d: float = to_opp.length()
				if d >= deked_dist or d < 0.001:
					continue
				if to_opp.dot(obj_dir) <= 0.0:
					continue   # behind the play — not the man to beat
				var closing: float = (ctx.self_velocity - _scratch_opponent_vels[i]) \
						.dot(to_opp / d)
				if absf(closing) > DEKE_CONTAIN_MAX_CLOSING_M_S:
					continue   # committed pressure — other maneuvers own it
				deked_dist = d
				deked_idx = i
			if deked_idx != -1:
				var d_proj: Vector3 = _scratch_opponents[deked_idx] \
						+ _scratch_opponent_vels[deked_idx] \
								* (AICarrySpace.DEKE_FAKE_S + AICarrySpace.DEKE_CUT_S)
				var axis: Vector3 = d_proj - cur_puck_pos
				axis.y = 0.0
				if axis.length_squared() > 0.0001:
					axis = axis.normalized()
					var perp := Vector3(axis.z, 0.0, -axis.x)
					var side: int = AICarrySpace.deke_cut_side(
							cur_puck_pos, ctx.self_velocity, ctx.self_handle_reach,
							axis, perp, deked_idx,
							_scratch_opponents, _scratch_opponent_vels,
							_scratch_opponent_caps)
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
	var fwd_spot: Vector3 = _puck_pos_at(
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

	_scratch_teammate_ids.clear()
	for peer_id: int in snapshot.skater_states:
		if peer_id == ctx.peer_id:
			continue
		if ctx.team_id_by_peer.get(peer_id, -1) == ctx.team_id:
			_scratch_teammate_ids.append(peer_id)

	# Pass-OPTION cache: each legal receiver's spot value at his CURRENT position
	# (goalie arc-squared to it). Legality approximates _compute_best_pass's: no
	# out-of-play receivers, and an OZ carrier counts only receivers standing
	# OZ_RECEIVE_LINE_BUFFER_M inside the line (the live pass applies that
	# buffer to the solved lead instead).
	_scratch_option_receiver_pos.clear()
	_scratch_option_receiver_val.clear()
	var in_oz_now: bool = _zone_taken(ctx)
	for pid: int in _scratch_teammate_ids:
		var tm: SkaterNetworkState = snapshot.skater_states[pid]
		if snapshot.is_out_of_play(pid):
			continue
		if in_oz_now and not AIActionScoring.in_offensive_zone(
				tm.position, attacking_goal, OZ_RECEIVE_LINE_BUFFER_M):
			continue
		var tm_caps: AISkaterCaps = ctx.caps_by_peer.get(pid)
		var tm_shot_speed: float = tm_caps.wrister_shot_speed if tm_caps != null \
				else AIActionScoring.WRISTER_SHOT_SPEED_M_S
		var tm_goalie: Vector3 = AIActionScoring.goalie_squared_pos(
				_goalie_now(ctx), attacking_goal, tm.position)
		_scratch_option_receiver_pos.append(tm.position)
		_scratch_option_receiver_val.append(_score_at(
				ctx, tm.position, self_pos, _scratch_opponents, tm_goalie,
				tm_shot_speed, 0.0, 0.0, 0.0, _loft_high(tm_caps)))
	# The same option read at the CURRENT puck spot — the baseline a candidate's
	# option credit is measured against (see _upgrade_candidate_two_ply): an
	# option already available from here belongs to the live pass in the fire
	# compete, so only the IMPROVEMENT motivates a carry. Subtracting it also
	# cancels the coarse option model's bias against the fully-priced pass
	# common-mode.
	_pass_option_at_self = _candidate_pass_option(ctx, cur_puck_pos)
	# Exact ceiling on ANY candidate's option (lane/miss/decay all ≤ 1); when
	# it can't improve on the at-self read, the per-candidate option read skips.
	_pass_option_ceiling = 0.0
	for v: float in _scratch_option_receiver_val:
		if v * PASS_OPTION_DISCOUNT > _pass_option_ceiling:
			_pass_option_ceiling = v * PASS_OPTION_DISCOUNT

	# SHOOT is scored at the projected RELEASE: the puck leaves the blade a
	# wind-up after the intent commits, so a bot rushing into the slot scores
	# the spot it will release from — which also lets it start the wind-up early.
	var self_velocity: Vector3 = ctx.self_velocity
	var horizontal_velocity: Vector3 = Vector3(self_velocity.x, 0.0, self_velocity.z)
	# Where the goalie actually is: a body the release can't cross.
	var goalie_now: Vector3 = _goalie_now(ctx)
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
	# threat_surface_shoot and _score_at run). Gating it, rather than leaving it
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
		_holds.configure_from(ctx)
		_holds.solve_shot(Vector2(shot_dir.x, shot_dir.z),
				Vector2(puck_now.x - self_pos.x, puck_now.z - self_pos.z),
				Vector2(horizontal_velocity.x, horizontal_velocity.z),
				snapshot.skater_states[ctx.peer_id].facing)
		_holds.price_keep(self_pos, Vector2(horizontal_velocity.x, horizontal_velocity.z),
				snapshot.skater_states[ctx.peer_id].facing,
				AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S, _scratch_opponents,
				_scratch_opponent_vels, _scratch_opponent_caps)
	_phase_shoot_score = -1.0
	for k: int in _holds.count:
		if shot_unavailable:
			break
		var hold := Vector3(_holds.offset[k].x, 0.0, _holds.offset[k].y)
		var share: float = _holds.share[k]
		var pull_s: float = _holds.pull_s[k]
		var sample_speed: float = ctx.self_wrister_shot_speed * share
		var release: Vector3 = AIActionScoring.release_ahead_of_goalie(
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
		var shot_closing: float = AIActionScoring.closing_toward(
				ctx.self_pos, ctx.self_velocity, attacking_goal)
		var sample_goalie: Vector3 = goalie_now if _shot_env_seal_x != 0.0 \
				else AIActionScoring.predict_goalie_pos(
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
				GameRules.NET_HALF_WIDTH, _scratch_opponents_release,
				sample_speed, _scratch_opponent_caps, ShotEvent.ShotType.SHOT,
				ctx.self_loft_tans.z) * _holds.keep[k]
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
	if not shot_unavailable and not _scratch_option_receiver_pos.is_empty():
		var tip_k: int = 1 if _holds.share[1] > _holds.share[0] else 0
		var tip_hold := Vector3(_holds.offset[tip_k].x, 0.0, _holds.offset[tip_k].y)
		var tip_share: float = _holds.share[tip_k]
		var tip_pull_s: float = _holds.pull_s[tip_k]
		var tip_release: Vector3 = AIActionScoring.release_ahead_of_goalie(
				self_pos + tip_hold + horizontal_velocity
						* (AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S + tip_pull_s),
				attacking_goal, goalie_now)
		var tip_speed: float = ctx.self_wrister_shot_speed * tip_share
		for tip_man: Vector3 in _scratch_option_receiver_pos:
			var tip_s: float = AIActionScoring.tip_ev(
					tip_release, tip_man, attacking_goal, goalie_now,
					GameRules.NET_HALF_WIDTH, _scratch_opponents_release,
					tip_speed, _scratch_opponent_caps) * _holds.keep[tip_k]
			if tip_s > _phase_shoot_score:
				_phase_shoot_score = tip_s
				_shot_sample_release = tip_release
				_shot_sample_goalie = goalie_now
				_shot_sample_speed = tip_speed
				_shot_sample_share = tip_share
				shoot_now_hold = tip_hold
				_shot_sample_is_tip = true

	var self_state: SkaterNetworkState = snapshot.skater_states[ctx.peer_id]
	var best_pass: Array = _compute_best_pass(
			ctx, self_state.facing, _scratch_teammate_ids)
	_phase_best_pass_peer = best_pass[0]
	_phase_best_pass_score = best_pass[1]
	_phase_best_pass_saucer = best_pass[2]
	_phase_best_pass_rim_dir = best_pass[3]
	_phase_best_pass_rim_pace = best_pass[4]


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
		_build_action_opponents_lists(ctx)
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
	carry_score *= lerpf(FORWARD_PRESSURE_MIN_SCALE, 1.0, forward_space)
	# …but SELF is floored by the same drive-in credit _pass_ev gives a receiver,
	# at our own velocity as his is at his. Without it two equally-covered
	# wingers at the blue line each rate the OTHER man's drive above their own
	# discounted carry, and the puck ping-pongs along the line instead of
	# entering the zone.
	var drive_in_value: float = _receiver_drive_in_value(
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
	# teammate is still creating (_best_developing_feed), × the odds we keep the
	# puck that long (our current evadability), × the delay discount on how long
	# we've already held — so a wait that never materialises self-extinguishes.
	# When the play arrives the live pass scoring converges on it and fire wins
	# the tie.
	var keep_prob: float = current_safety
	var hold_value: float = (_best_developing_feed(ctx)
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
			dump_target = puck_now + best_pass_rim_dir * DUMP_AIM_STANDOFF_M
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
				pass_target_speed = AIActionScoring.pass_launch_speed(
						puck_now.distance_to(receiver.position),
						_pass_launch_cap(ctx, pass_dir,
								ctx.snapshot.skater_states[ctx.peer_id].facing),
						ctx.pass_speed_scale, receiver.velocity, pass_dir)
			else:
				pass_target_speed = AIActionScoring.PASS_SPEED_M_S * ctx.pass_speed_scale
			pass_should_charge = true
			# A saucer's launch is capped at the receivability bound for the
			# distance — a flip still airborne at the tape flies over the
			# receiver's grounded blade — even after the receiver-relative solve.
			pass_should_saucer = best_pass_saucer
			if best_pass_saucer and receiver != null:
				pass_target_speed = clampf(
						AIActionScoring.saucer_max_launch_speed(
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
					_scratch_opponents_release, _scratch_option_receiver_pos)
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
		var dump_result: Array = _best_dump(ctx, our_goalie)
		debug_dump_score = dump_result[0]
		if dump_result[0] > -INF:
			_hold_elapsed_s = 0.0
			new_intent = INTENT_DUMP
			dump_target = dump_result[1]
			dump_is_soft = dump_result[2]
			dump_is_rim = dump_result[3]
			dump_launch_speed = dump_result[5]
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


# Populates the per-re-eval opponent and teammate scratch lists (see each
# field's doc). The per-receiver flight-time projection (_scratch_opponents_pass)
# is rebuilt per call in _pass_ev instead, because its lookahead varies.
func _build_action_opponents_lists(ctx: RoleContext) -> void:
	_scratch_opponents.clear()
	_scratch_opponent_vels.clear()
	_scratch_opponent_caps.clear()
	_scratch_opponents_release.clear()
	_scratch_our_defenders.clear()
	_scratch_our_defender_caps.clear()
	_scratch_our_defender_vels.clear()
	for peer_id: int in ctx.snapshot.skater_states:
		if peer_id == ctx.peer_id:
			continue
		var s: SkaterNetworkState = ctx.snapshot.skater_states[peer_id]
		if ctx.team_id_by_peer.get(peer_id, -1) != ctx.team_id:
			_scratch_opponents.append(s.position)
			_scratch_opponent_vels.append(s.velocity)
			_scratch_opponent_caps.append(ctx.caps_by_peer.get(peer_id))
			_scratch_opponents_release.append(AITrajectory.predict_at(
					s.position, s.velocity, AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S))
		else:
			_scratch_our_defenders.append(s.position)
			_scratch_our_defender_caps.append(ctx.caps_by_peer.get(peer_id))
			_scratch_our_defender_vels.append(s.velocity)
	# Transition-exposure precompute (5v5): each teammate's ETA to the counter
	# point is candidate-invariant, so race them once per re-eval instead of
	# once per counter_rush_cost call.
	if ctx.team_size >= 5:
		AIActionScoring.fill_counter_cover_etas(
				ctx.defending_goal_pos, _scratch_our_defenders,
				_scratch_exposure_mate_etas)
		_scratch_exposure_threat_memo.resize(_scratch_our_defenders.size() + 2)
		_scratch_exposure_threat_memo.fill(-1.0)


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
	for i: int in _scratch_opponents.size():
		if have_dir:
			var opp_proj_x: float = _scratch_opponents[i].x \
					+ _scratch_opponent_vels[i].x * horizon
			var opp_proj_z: float = _scratch_opponents[i].z \
					+ _scratch_opponent_vels[i].z * horizon
			var ahead: float = (opp_proj_x - self_proj_x) * nx \
					+ (opp_proj_z - self_proj_z) * nz
			if ahead < -PROTECT_SCREEN_BEHIND_M:
				continue   # beaten — the body screens the forward puck for free
		_scratch_protect_opponents.append(_scratch_opponents[i])
		_scratch_protect_vels.append(_scratch_opponent_vels[i])
		_scratch_protect_caps.append(_scratch_opponent_caps[i])


# Refills `out_buf` with each opponent's position projected forward by `time_s`,
# in the same snapshot order as _scratch_opponent_caps / _vels, so the lane
# reads index the caps of the right defender.
func _project_opponents_to(ctx: RoleContext, time_s: float,
		out_buf: Array[Vector3]) -> void:
	out_buf.clear()
	for peer_id: int in ctx.snapshot.skater_states:
		if ctx.team_id_by_peer.get(peer_id, -1) != ctx.team_id and peer_id != ctx.peer_id:
			var s: SkaterNetworkState = ctx.snapshot.skater_states[peer_id]
			out_buf.append(AITrajectory.predict_at(s.position, s.velocity, time_s))


# The best pass this eval, as [best_peer_id (int, 0 when none), best_score
# (float), is_saucer (bool), rim_dir (Vector3, ZERO for a straight feed),
# rim_pace (float, m/s)].
#
# Each receiver is scored as up to two straight variants competing on EV
# (_pass_variant_ev): the flat feed at the receiver-relative launch pace, and —
# when the flat lane is contested — a saucer at min(that pace, the
# receivability bound), paying SAUCER_EXTRA_MISS_PROB for its landing. Rim
# launches are ranked per receiver too, and only the eval's single best rim is
# priced through the full _pass_ev, after the loop.
#
# Filtered here: out-of-play receivers, and, for an OZ carrier, receivers
# outside the zone. The lead-dependent filters live in _pass_variant_ev, the
# lane hard-zeros in _pass_ev. Behind-the-back receivers are NOT skipped: only
# the narrow wedge past the reach cone pays, as rotation time in the delay
# (_facing_rotation_time).
func _compute_best_pass(ctx: RoleContext, self_facing_xz: Vector2,
		teammate_ids: Array[int]) -> Array:
	var snapshot: WorldSnapshot = ctx.snapshot
	var self_pos: Vector3 = ctx.self_pos
	var best_pass_peer: int = 0
	var best_pass_score: float = 0.0
	var best_pass_saucer: bool = false
	var our_goalie: Vector3 = AIRoleHelpers.resolve_our_goalie_pos(ctx)
	var attacking_goal: Vector3 = ctx.attacking_goal_pos
	# One-way valve: once the zone is taken the carrier won't pass the puck back
	# out of it (the carry-side valve is in _score_move_candidate_base).
	var carrier_in_oz: bool = _zone_taken(ctx)
	var pass_origin: Vector3 = _pass_origin(ctx)
	var best_pass_rim_dir := Vector3.ZERO
	var best_pass_rim_pace: float = 0.0
	# Rim launches are receiver-independent: searched once per eval, and only
	# once some receiver's flat lane is contested enough to want one (-1 =
	# not searched yet).
	var rim_count: int = -1
	# The eval's best rim candidate: receiver, launch, and its path reads.
	var rim_rank: float = 0.0
	var rim_peer: int = -1
	var rim_space: float = -1.0
	var rim_k: int = -1
	var rim_t: float = 0.0
	var rim_lane: float = 0.0
	var rim_miss: float = 0.0
	for peer_id: int in teammate_ids:
		var receiver_state: SkaterNetworkState = snapshot.skater_states[peer_id]
		if snapshot.is_out_of_play(peer_id):
			continue
		if carrier_in_oz and not AIActionScoring.in_offensive_zone(
				receiver_state.position, attacking_goal):
			continue
		var receiver_is_one_timer: bool = (ctx.team_brain != null
				and ctx.team_brain.is_one_timer_ready(peer_id))
		# Score at the speed the commit will actually fire: the same
		# receiver-relative launch solve as the INTENT_PASS block in
		# _pick_commit_phase, capped at what this bot's load can carry
		# (_pass_launch_cap). Any other pace mis-places the lead and gives the
		# defenders the wrong flight time to close.
		var dist: float = pass_origin.distance_to(receiver_state.position)
		var to_recv: Vector3 = receiver_state.position - pass_origin
		to_recv.y = 0.0
		var scored_pass_dir: Vector3 = to_recv.normalized() \
				if to_recv.length_squared() > 0.0001 else Vector3.ZERO
		var pass_speed: float = AIActionScoring.pass_launch_speed(
				dist, _pass_launch_cap(ctx, scored_pass_dir, self_facing_xz),
				ctx.pass_speed_scale, receiver_state.velocity, scored_pass_dir)
		var receiver_accel: Vector3 = ctx.acceleration_by_peer.get(peer_id, Vector3.ZERO)
		# Receiver's heading turn rate — the commitment read; 0 for a
		# commitment-blind tier.
		var receiver_omega: float = ctx.heading_omega_by_peer.get(peer_id, 0.0) \
				if ctx.reads_receiver_commitment else 0.0
		var receiver_caps: AISkaterCaps = ctx.caps_by_peer.get(peer_id)
		# How much room this MAN has — solved at most once per receiver (it is a
		# property of him and the ice around him, not of which variant reaches
		# him), and lazily inside _pass_ev, because it is the dominant cost here
		# and the hard-zero gates reject many receivers before it is needed.
		_last_receiver_space = -1.0
		# Exact prune floor for this receiver: the running best, divided by any
		# bonus applied to him AFTER scoring (the ping multiplier below), so the
		# bound stays sound.
		var prune_floor: float = best_pass_score
		if peer_id == ctx.ping_pass_target_peer:
			prune_floor /= PING_PASS_EV_MULT
		# Flat feed.
		_last_flat_variant_lane = 0.0
		var s: float = _pass_variant_ev(
				ctx, receiver_state, receiver_accel, receiver_omega, receiver_caps,
				pass_origin, pass_speed, false, receiver_is_one_timer,
				self_facing_xz, our_goalie, carrier_in_oz, -1.0, prune_floor)
		var receiver_space: float = _last_receiver_space
		var use_saucer: bool = false
		# Saucer variant: the fastest RECEIVABLE flip. Below the soft-touch
		# wrister floor no legal saucer exists (the physical minimum saucer
		# distance, ~6.5 m).
		var saucer_speed: float = minf(
				pass_speed, AIActionScoring.saucer_max_launch_speed(dist))
		# Saucer competes only when the FLAT feed is contested
		# (SAUCER_SKIP_WHEN_LANE_CLEAR), read off the flat variant's solved lane so
		# a clear-lane receiver skips the second solve. A flat variant filtered
		# before its lane solve leaves 0.0 — "contested" — so the saucer still
		# gets its own look at leads the flat pass couldn't take.
		if saucer_speed >= GameRules.DEFAULT_WRISTER_POWER_MIN_M_S \
				and _last_flat_variant_lane < AIActionScoring.SAUCER_SKIP_WHEN_LANE_CLEAR:
			var s_saucer: float = _pass_variant_ev(
					ctx, receiver_state, receiver_accel, receiver_omega, receiver_caps,
					pass_origin, saucer_speed, true, receiver_is_one_timer,
					self_facing_xz, our_goalie, carrier_in_oz, receiver_space,
					maxf(prune_floor, s))
			if s_saucer > s:
				s = s_saucer
				use_saucer = true
		# Like the saucer, the rim competes only when the flat feed is contested:
		# with the lane clear there is nothing for the boards to carry it past.
		# Its candidate is only RANKED here (see _rim_launch_for); the one best
		# rim of the eval is priced after the loop.
		if rim_count != 0 \
				and _last_flat_variant_lane < AIActionScoring.SAUCER_SKIP_WHEN_LANE_CLEAR:
			if rim_count < 0:
				rim_count = AIRimPass.build(pass_origin, ctx.self_wrister_shot_speed,
						ctx.defending_goal_pos.z, _scratch_opponents,
						_scratch_opponent_vels, _scratch_opponent_caps,
						_goalie_now(ctx), _scratch_our_defenders)
			var rank: float = _rim_launch_for(ctx, receiver_state, receiver_omega,
					receiver_caps, carrier_in_oz) \
					* _cached_option_value(receiver_state.position)
			if rank > rim_rank:
				rim_rank = rank
				rim_peer = peer_id
				rim_space = receiver_space
				rim_k = _rim_k
				rim_t = _rim_t
				rim_lane = _rim_lane
				rim_miss = _rim_miss
		# Smart-ping PASS_TO_ME / IM_OPEN (see PING_PASS_EV_MULT).
		if peer_id == ctx.ping_pass_target_peer and s > 0.0:
			s *= PING_PASS_EV_MULT
		if s > best_pass_score:
			best_pass_score = s
			best_pass_peer = peer_id
			best_pass_saucer = use_saucer
	if rim_peer != -1:
		var rim_state: SkaterNetworkState = snapshot.skater_states[rim_peer]
		var rim_caps: AISkaterCaps = ctx.caps_by_peer.get(rim_peer)
		var floor_ev: float = best_pass_score
		if rim_peer == ctx.ping_pass_target_peer:
			floor_ev /= PING_PASS_EV_MULT
		var rotation_time: float = _facing_rotation_time(self_facing_xz,
				ctx.self_pos, ctx.self_pos + AIRimPass.dirs[rim_k],
				ctx.self_reach_cone_half_angle, ctx.self_facing_turn_rate)
		var s_rim: float = _pass_ev(ctx, AIRimPass.meet_point(rim_k, rim_t),
				AIRimPass.paces[rim_k], rim_t,
				rim_t + AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S,
				rim_t + rotation_time, our_goalie, rim_caps, rim_lane, rim_miss,
				rim_state.velocity, rim_space, floor_ev,
				AIRimPass.dirs[rim_k], AIRimPass.opp_meet[rim_k])
		if rim_peer == ctx.ping_pass_target_peer and s_rim > 0.0:
			s_rim *= PING_PASS_EV_MULT
		if s_rim > best_pass_score:
			best_pass_score = s_rim
			best_pass_peer = rim_peer
			best_pass_saucer = false
			best_pass_rim_dir = AIRimPass.dirs[rim_k]
			best_pass_rim_pace = AIRimPass.paces[rim_k]
	return [best_pass_peer, best_pass_score, best_pass_saucer, best_pass_rim_dir,
			best_pass_rim_pace]


# How surely and soon a RIM reaches `receiver_state` (completion × the delay
# discount, 0.0 when none does) — the softest launch within RIM_SOFT_SHARE of the
# surest — with that launch's path reads (meet time on the walked path, the race
# against the soonest opponent as the lane, the passer's aim error over the path
# length) left in _rim_k / _rim_t / _rim_lane / _rim_miss.
#
# A RANK, not a price: _compute_best_pass weighs it by the receiver's cached spot
# value and pays the full _pass_ev only for the eval's single best rim. Launches
# that reach one receiver meet him within a stride of each other, so his value
# cannot reorder them.
#
# Zone rules follow the straight feed's: a carrier in the zone keeps the puck in
# it up to the meet, and one outside it does not rim the puck into it (the
# receiver would be offside).
func _rim_launch_for(ctx: RoleContext, receiver_state: SkaterNetworkState,
		receiver_omega: float, receiver_caps: AISkaterCaps,
		carrier_in_oz: bool) -> float:
	var speed: float = receiver_caps.max_speed if receiver_caps != null \
			else AIArrival.SKATER_REF_SPEED_M_S
	var catch_radius: float = receiver_caps.handle_reach if receiver_caps != null \
			else AIBotMechanics.EVADE_CARRY_HANDLE_M
	var receiver_speed: float = Vector2(
			receiver_state.velocity.x, receiver_state.velocity.z).length()
	if _rim_sure_by_k.size() != AIRimPass.MAX_LAUNCHES:
		_rim_sure_by_k.resize(AIRimPass.MAX_LAUNCHES)
		_rim_t_by_k.resize(AIRimPass.MAX_LAUNCHES)
		_rim_lane_by_k.resize(AIRimPass.MAX_LAUNCHES)
		_rim_miss_by_k.resize(AIRimPass.MAX_LAUNCHES)
	var best_sure: float = 0.0
	for k: int in AIRimPass.count:
		_rim_sure_by_k[k] = -1.0
		var t: float = AIRimPass.meet_time(k, receiver_state.position,
				receiver_state.velocity, speed)
		if t == INF:
			continue
		if not AIRimPass.catchable(k, t, receiver_state.velocity):
			continue
		if carrier_in_oz:
			if not AIRimPass.stays_in_zone(k, t, ctx.attacking_goal_pos,
					OZ_RECEIVE_LINE_BUFFER_M):
				continue
		elif AIActionScoring.in_offensive_zone(
				AIRimPass.meet_point(k, t), ctx.attacking_goal_pos):
			continue
		var miss_prob: float = AIActionScoring.pass_miss_prob(
				AIRimPass.path_length(k, t), ctx.self_pass_aim_error_rad,
				catch_radius, AIActionScoring.receiver_heading_uncertainty_m(
						receiver_speed, receiver_omega, t))
		var sure: float = (1.0 - miss_prob) * AIActionScoring.delay_discount(t)
		# Exact prune before the opponent race (the costly read): the lane is at
		# most 1, so a launch that cannot reach the soft band unraced cannot raced.
		if sure < best_sure * RIM_SOFT_SHARE:
			continue
		var lane: float = AIRimPass.race_completion(k, t)
		sure *= lane
		_rim_sure_by_k[k] = sure
		_rim_t_by_k[k] = t
		_rim_lane_by_k[k] = lane
		_rim_miss_by_k[k] = miss_prob
		best_sure = maxf(best_sure, sure)
	if best_sure <= 0.0:
		return 0.0
	# Fire it as soft as the race allows: among the launches nearly as sure as the
	# best, the softest — easier to stop, and a missed one dies sooner.
	var pick: int = -1
	for k: int in AIRimPass.count:
		var sure_k: float = _rim_sure_by_k[k]
		if sure_k < best_sure * RIM_SOFT_SHARE:
			continue
		if pick == -1 or AIRimPass.paces[k] < AIRimPass.paces[pick] \
				or (AIRimPass.paces[k] == AIRimPass.paces[pick] and sure_k > _rim_sure_by_k[pick]):
			pick = k
	_rim_k = pick
	_rim_t = _rim_t_by_k[pick]
	_rim_lane = _rim_lane_by_k[pick]
	_rim_miss = _rim_miss_by_k[pick]
	return _rim_sure_by_k[pick]


# The pass-option cache's spot value for the receiver standing at `pos` (0.0 when
# he is not in it — an illegal or out-of-play receiver).
func _cached_option_value(pos: Vector3) -> float:
	for i: int in _scratch_option_receiver_pos.size():
		if _scratch_option_receiver_pos[i] == pos:
			return _scratch_option_receiver_val[i]
	return 0.0


# EV of ONE pass variant (flat, or saucer at a possibly-reduced launch
# speed) to `receiver_state`. Solves the intercept lead at the variant's
# actual speed, applies the per-variant filters, then prices it through
# the shared _pass_ev. Returns 0.0 when the variant is filtered out:
#   - Lead past our own goal line (own-goal risk).
#   - Carrier in OZ → lead must sit OZ_RECEIVE_LINE_BUFFER_M inside the line.
#   - Carrier outside with a delayed offside up → lead must stay outside.
#   - Saucer only: the lead must leave the flip landing runway (airborne carry
#     + SAUCER_LANDING_RUN_M — a closing receiver can shrink the solved lead
#     under what the current distance allowed), the flat lane must be contested
#     (SAUCER_SKIP_WHEN_LANE_CLEAR), and the loft must clear MORE of the lane
#     than staying flat.
#
# One-timer-ready receivers fire on contact (no wrister windup), so the goalie
# only gets the pass flight to react.
func _pass_variant_ev(ctx: RoleContext, receiver_state: SkaterNetworkState,
		receiver_accel: Vector3, receiver_omega: float, receiver_caps: AISkaterCaps,
		pass_origin: Vector3, pass_speed: float, saucer: bool,
		receiver_is_one_timer: bool, self_facing_xz: Vector2,
		our_goalie: Vector3, carrier_in_oz: bool,
		receiver_space: float = -1.0,
		useless_below: float = -INF) -> float:
	# Intercept-aware lead, shared with the state machine's firing aim; flight_t
	# is the SOLVED time. The receiver's real build bounds how far he is led.
	var lead: Array = AIPassLead.lead(
			pass_origin, receiver_state, receiver_accel, pass_speed,
			PASS_LEAD_MAX_S, receiver_caps)
	var receiver: Vector3 = lead[0]
	var flight_t: float = lead[1]
	if ctx.own_goal_dir * receiver.z > GameRules.GOAL_LINE_Z:
		return 0.0
	if carrier_in_oz and not AIActionScoring.in_offensive_zone(
			receiver, ctx.attacking_goal_pos, OZ_RECEIVE_LINE_BUFFER_M):
		return 0.0
	# A delayed offside is up: a feed caught in the zone is a touch that whistles.
	if ctx.zone_entry_blocked and not carrier_in_oz \
			and AIActionScoring.in_offensive_zone(receiver, ctx.attacking_goal_pos):
		return 0.0
	var lane: float
	# Execution miss (AIActionScoring.pass_miss_prob): this bot's release error
	# projected over the pass distance vs the receiver's catch envelope.
	var catch_radius: float = receiver_caps.handle_reach if receiver_caps != null \
			else AIBotMechanics.EVADE_CARRY_HANDLE_M
	# Receiver-commitment term: a receiver mid-cut curves off the straight-line
	# lead. Zero for a settled receiver (or a commitment-blind tier, which
	# passes receiver_omega 0).
	var receiver_speed: float = sqrt(
			receiver_state.velocity.x * receiver_state.velocity.x
			+ receiver_state.velocity.z * receiver_state.velocity.z)
	var turn_uncertainty: float = AIActionScoring.receiver_heading_uncertainty_m(
			receiver_speed, receiver_omega, flight_t)
	var miss_prob: float = AIActionScoring.pass_miss_prob(
			pass_origin.distance_to(receiver), ctx.self_pass_aim_error_rad,
			catch_radius, turn_uncertainty)
	if saucer:
		# Small tolerance: a speed sitting exactly on the receivability
		# bound round-trips through the kinematics to the exact distance.
		if pass_origin.distance_to(receiver) \
				< AIActionScoring.saucer_airborne_distance_m(pass_speed) \
				+ AIActionScoring.SAUCER_LANDING_RUN_M - 0.01:
			return 0.0
		var lane_flat: float = AIActionScoring.lane_clear(
				pass_origin, receiver, _scratch_opponents_release, pass_speed,
				_scratch_opponent_vels, _scratch_opponent_caps, true)
		if lane_flat >= AIActionScoring.SAUCER_SKIP_WHEN_LANE_CLEAR:
			return 0.0
		lane = AIActionScoring.lane_clear_saucer(
				pass_origin, receiver, _scratch_opponents_release, pass_speed,
				_scratch_opponent_vels, _scratch_opponent_caps)
		if lane <= lane_flat:
			return 0.0
		miss_prob += AIActionScoring.SAUCER_EXTRA_MISS_PROB
	else:
		lane = AIActionScoring.lane_clear(
				pass_origin, receiver, _scratch_opponents_release, pass_speed,
				_scratch_opponent_vels, _scratch_opponent_caps, true)
		_last_flat_variant_lane = lane
	var receiver_release_t: float = flight_t
	if not receiver_is_one_timer:
		receiver_release_t += AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S
	var rotation_time: float = _facing_rotation_time(
			self_facing_xz, ctx.self_pos, receiver,
			ctx.self_reach_cone_half_angle, ctx.self_facing_turn_rate)
	return _pass_ev(ctx, receiver, pass_speed, flight_t,
			receiver_release_t, flight_t + rotation_time, our_goalie,
			receiver_caps, lane, miss_prob, receiver_state.velocity,
			receiver_space, useless_below)


# Expected value of firing a pass from our current position to
# `receiver_spot`. Shared by the live pass scoring (_compute_best_pass) and the
# developing-outlet hold (_developing_outlet_feed), so "the pass this wait is
# creating" and "the pass I can fire now" are priced identically — the hold
# self-terminates the instant the real pass matches it (fire wins ties).
#
# Benefit = P(complete) × the receiver's value at the spot, decayed by
# `delay_s` (flight + any facing rotation). Cost = the opponent's value at each
# loss mode's location (release poke, lane interception, execution miss,
# reception strip), so a low-upside backpass deep in our own end loses to
# skating: its miss mode surrenders the ice in front of our net.
#
# `lane` < 0 has the flat lane computed here; `miss_prob` is this variant's
# execution-miss probability. The goalie is predicted at `receiver_release_t`
# (flight + the receiver's wrister charge, or flight alone for a one-timer —
# the caller decides), so a cross-seam feed is scored against a keeper caught
# mid-slide. The receiver shoots at his own build's speed and loft when
# `receiver_caps` is given, the league default otherwise. A rim passes
# `rim_dir` and the point its path is lost at (`rim_loss_point`).
func _pass_ev(ctx: RoleContext, receiver_spot: Vector3, pass_speed: float,
		flight_t: float, receiver_release_t: float, delay_s: float,
		our_goalie: Vector3, receiver_caps: AISkaterCaps = null,
		lane: float = -1.0,
		miss_prob: float = AIActionScoring.PASS_MISS_BASE_PROB,
		receiver_vel: Vector3 = Vector3.ZERO,
		receiver_space: float = -1.0,
		useless_below: float = -INF,
		rim_dir: Vector3 = Vector3.ZERO,
		rim_loss_point: Vector3 = Vector3.INF) -> float:
	var self_pos: Vector3 = ctx.self_pos
	# The pass flies from the PUCK, not the body: behind the net the two differ
	# by up to a stick's reach. self_pos stays the body reference for the
	# receiver scoring / loss-point terms below.
	var origin: Vector3 = _pass_origin(ctx)
	# Hard zeros: net-blocker (segment crosses a net body) and own-DZ
	# slot crossing (intercepted = goal-against). A rim's path is not this
	# segment — AIRimPass checked each of its legs instead.
	var is_rim: bool = rim_dir != Vector3.ZERO
	if not is_rim and AINetObstacle.pass_lane_blocked_by_net(origin, receiver_spot):
		return 0.0
	if not is_rim and AINetObstacle.pass_crosses_own_slot(
			origin, receiver_spot, ctx.own_goal_dir * GameRules.GOAL_LINE_Z):
		return 0.0
	if lane < 0.0:
		lane = AIActionScoring.lane_clear(
				origin, receiver_spot, _scratch_opponents_release, pass_speed,
				_scratch_opponent_vels, _scratch_opponent_caps, true)
	if lane <= 0.0:
		return 0.0
	# RELEASE CONTEST — the cough-up loss mode: a forechecker whose stick reaches
	# the release point inside the ~135 ms windup pokes the puck off the blade
	# before it flies (the same race as the shot's release_contest_clean). It is
	# what prices a defender on the carrier's HIP, off the lane line. Raced from
	# CURRENT opponent spots, since the windup starts now.
	var release_clean: float = AIActionScoring.release_contest_clean(
			AIActionScoring.release_point_toward(self_pos,
					self_pos + rim_dir if is_rim else receiver_spot),
			_scratch_opponents, _scratch_opponent_caps)
	_project_opponents_to(ctx, flight_t, _scratch_opponents_pass)
	# A receiver streaking netward backs the keeper in over the feed's flight,
	# same planning depth model the carrier's own reads use.
	var receiver_closing: float = AIActionScoring.closing_toward(
			receiver_spot, receiver_vel, ctx.attacking_goal_pos)
	var receiver_goalie: Vector3 = _predict_goalie_at(
			ctx, receiver_release_t, receiver_spot, receiver_closing)
	var receiver_unsettled: float = _goalie_unsettled_at(
			ctx, receiver_release_t, receiver_spot, receiver_closing)
	var receiver_shot_speed: float = receiver_caps.wrister_shot_speed if receiver_caps != null \
			else AIActionScoring.WRISTER_SHOT_SPEED_M_S
	# The feed's edge: the puck relocates the shot origin far faster than the
	# keeper re-squares, and what he cannot cover over the flight plus the
	# receiver's release is the displacement — the same quantity the carry leg
	# reads.
	var receiver_displacement: float = AIShotValue.displacement_deficit_m(
			_goalie_now(ctx), ctx.attacking_goal_pos, receiver_spot,
			receiver_release_t)
	var receiver_value: float = _score_at(ctx, receiver_spot, self_pos,
			_scratch_opponents_pass, receiver_goalie,
			receiver_shot_speed, receiver_unsettled, 0.0,
			receiver_displacement, _loft_high(receiver_caps))
	# An OPEN receiver can carry into a better look, so he is credited the best
	# value he can REACH with a short drive toward the net. It bites in the OZ,
	# where _score_at is shot-only. (Re-projects _scratch_opponents_pass, which
	# the instant value above has already consumed.)
	receiver_value = maxf(receiver_value, _receiver_drive_in_value(
			ctx, receiver_spot, receiver_shot_speed, receiver_caps, receiver_vel))
	var time_decay: float = AIActionScoring.delay_discount(delay_s)
	# Reception pressure: the reachable-set clearance at the reception spot when
	# the puck arrives — defenders momentum-projected from their RELEASE-TIME
	# spots over the flight, sticks maneuvering over the short reception window.
	# It prices a defender draped on the receiver's back, who is off both the
	# lane and the receiver's forward shot cone.
	var reception_safety: float = AICarrySpace.clearance_to_safety(
			AICarrySpace.reach_clearance(receiver_spot, flight_t,
					_scratch_opponents_release, _scratch_opponent_vels,
					_scratch_opponent_caps, AICarrySpace.EVADE_HORIZON_S))
	# Four completion loss modes, mutually exclusive and summing to 1 with the
	# retained case: poked at the release (1 − release_clean), lane interception
	# (release_clean × (1 − lane)), execution miss (release_clean × lane × miss),
	# and a strip on reception (clean lane, no miss, but a stick on the catch).
	var clean_lane: float = lane * (1.0 - miss_prob)   # reaches the tape, in flight
	var completion: float = release_clean * clean_lane * reception_safety
	# CEILING PRUNE (exact): the space toll and every turnover cost below can
	# only LOWER this EV, so the undiscounted benefit is a hard upper bound, and
	# a receiver who cannot beat the best feed even at full marks skips the
	# costly space read.
	if receiver_value * completion * time_decay <= useless_below:
		return 0.0
	# The receiver pays the SAME forward-pressure toll the carrier's own carry
	# does, at his own velocity and build, so symmetric coverage gives symmetric
	# discount and the pass wins only when the mate is genuinely clearer.
	# `receiver_space` < 0 means "compute it here".
	if receiver_space < 0.0:
		receiver_space = _forward_clearance_at(
				ctx, receiver_spot, receiver_vel, receiver_caps)
	# Published for the caller's per-receiver reuse (see _compute_best_pass).
	_last_receiver_space = receiver_space
	receiver_value *= lerpf(FORWARD_PRESSURE_MIN_SCALE, 1.0, receiver_space)
	# No separate "escape" bonus for a pressured carrier: the pressure is
	# already priced by the carry/hold alternatives' own strip cost.
	var benefit: float = receiver_value * completion * time_decay
	# Poked at the release: the puck squirts loose at the blade.
	var cost: float = _turnover_cost(ctx, origin,
			1.0 - release_clean, our_goalie)
	# A rim is lost where the soonest opponent meets its path.
	var loss_point: Vector3 = rim_loss_point if is_rim and rim_loss_point.is_finite() \
			else AIActionScoring.lane_loss_point(
					self_pos, receiver_spot, _scratch_opponents_release, pass_speed,
					_scratch_opponent_vels, _scratch_opponent_caps)
	cost += _turnover_cost(ctx, loss_point,
			release_clean * (1.0 - lane), our_goalie)
	cost += _turnover_cost(ctx, AIActionScoring.pass_miss_loss_point(self_pos, receiver_spot),
			release_clean * lane * miss_prob, our_goalie)
	# Reception strip: the puck dies AT the receiver, in whatever traffic he was
	# about to catch it in.
	cost += _turnover_cost(ctx, receiver_spot,
			release_clean * clean_lane * (1.0 - reception_safety), our_goalie)
	# Transition exposure (5v5): each loss mode also prices the COUNTER-RUSH
	# it hands over — the carrier stays at self_pos through a pass, so his
	# own recovery race starts from here (plan §6).
	cost += _counter_exposure_cost(ctx, loss_point, 1.0 - lane,
			self_pos, our_goalie)
	cost += _counter_exposure_cost(ctx, receiver_spot,
			clean_lane * (1.0 - reception_safety), self_pos, our_goalie)
	return benefit - cost


# turnover_cost in the unit of this carrier's gains: xG once he is in the zone,
# the potential scale outside it (see AIActionScoring.turnover_cost).
func _turnover_cost(ctx: RoleContext, loss_point: Vector3, loss_prob: float,
		our_goalie: Vector3) -> float:
	return AIActionScoring.turnover_cost(
			loss_point, loss_prob, ctx.defending_goal_pos, our_goalie,
			GameRules.NET_HALF_WIDTH, _scratch_our_defenders,
			_scratch_our_defender_caps,
			AIActionScoring.in_offensive_zone(ctx.self_pos, ctx.attacking_goal_pos))


# Transition-exposure cost of losing the puck at `loss_point` with
# probability `loss_prob`, while this carrier would be recovering from
# `recover_from` — the additive counter-rush half of the turnover price
# (AIActionScoring.counter_rush_cost; plan §6). 5v5 only: 3v3 pays zero.
# Scaled by the per-position appetite (EXPOSURE_APPETITE_*).
func _counter_exposure_cost(ctx: RoleContext, loss_point: Vector3,
		loss_prob: float, recover_from: Vector3, our_goalie: Vector3) -> float:
	# Probability floor (EXPOSURE_PROB_FLOOR): a play that barely risks the puck
	# prices its counter at ~0 anyway.
	if ctx.team_size < 5 or loss_prob <= EXPOSURE_PROB_FLOOR:
		return 0.0
	var appetite: float = EXPOSURE_APPETITE_DEFENSE if ctx.self_is_defense \
			else EXPOSURE_APPETITE_FORWARD
	return appetite * AIActionScoring.counter_rush_cost(
			loss_point, loss_prob, ctx.defending_goal_pos, our_goalie,
			GameRules.NET_HALF_WIDTH, _scratch_our_defenders,
			recover_from, ctx.self_max_speed,
			_scratch_opponents, _scratch_opponent_vels, _scratch_opponent_caps,
			_scratch_exposure_mate_etas, _scratch_exposure_threat_memo,
			AIActionScoring.in_offensive_zone(ctx.self_pos, ctx.attacking_goal_pos))


# Seconds the bot needs to rotate its facing before the blade can fire at
# `target`. The blade reaches anywhere inside the reach cone (`cone_half_angle`
# = ROM + torso twist, the IK gate the pose coordinator enforces), so an in-cone
# target costs 0; past the cone only the OVERSHOOT pays, at this bot's real
# turn rate.
func _facing_rotation_time(self_facing_xz: Vector2, self_pos: Vector3,
		target: Vector3, cone_half_angle: float, turn_rate: float) -> float:
	var to_target_x: float = target.x - self_pos.x
	var to_target_z: float = target.z - self_pos.z
	var to_target_len: float = sqrt(
			to_target_x * to_target_x + to_target_z * to_target_z)
	if to_target_len <= 0.001:
		return 0.0
	var inv_len: float = 1.0 / to_target_len
	var cos_angle: float = clampf(
			self_facing_xz.x * to_target_x * inv_len
			+ self_facing_xz.y * to_target_z * inv_len, -1.0, 1.0)
	var angular_distance: float = acos(cos_angle)
	var overshoot: float = maxf(0.0, angular_distance - cone_half_angle)
	return overshoot / maxf(turn_rate, 0.001)


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
	_holds.configure_from(ctx)
	var attacking_goal: Vector3 = ctx.attacking_goal_pos
	var own_goal_dir: float = ctx.own_goal_dir
	var our_goalie: Vector3 = AIRoleHelpers.resolve_our_goalie_pos(ctx)
	var slot_pos: Vector3 = _slot_anchor(own_goal_dir)
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
				self_pos, attacking_goal, _scratch_opponents)
		var stand_realization: float = AIActionScoring.potential_realization_discount(
				self_pos, attacking_goal)
		stand_score = maxf(stand_score, stand_potential * stand_realization)
	var stand_puck_pos: Vector3 = _puck_pos_at(self_pos, attacking_goal)
	var stand_safety: float = AICarrySpace.carry_safety(
			stand_puck_pos, stand_puck_pos, AICarrySpace.EVADE_HORIZON_S,
			_scratch_opponents, _scratch_opponent_vels, _scratch_opponent_caps)
	var stand_cost: float = _turnover_cost(ctx, stand_puck_pos,
			1.0 - stand_safety, our_goalie)
	stand_cost += _counter_exposure_cost(ctx, stand_puck_pos,
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
			CARRY_SEARCH_STEP_M, FORWARD_PRESSURE_HORIZON_M)
	if ctx.self_velocity.length_squared() > 1.0:
		beat_r = clampf(
				sqrt(ctx.self_velocity.x * ctx.self_velocity.x
						+ ctx.self_velocity.z * ctx.self_velocity.z) * CARRY_PLAN_BEAT_S,
				CARRY_SEARCH_STEP_M, FORWARD_PRESSURE_HORIZON_M)
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


# Two clears priced within this of each other are the same clear, so depth
# breaks the tie (see _best_dump). Sized well under the shot-threat scale the
# prices are denominated in.
const CLEAR_PRICE_TIE_BAND: float = 0.001


# What handing the puck over at `spot` costs us: the immediate threat there, plus
# the counter-rush the loss opens (5v5). Returns (concede, recovery) packed into
# a Vector2 — a value type, so pricing a whole candidate set allocates nothing.
# The clear's search ranks its candidates with this and _best_dump reports the
# winner with it, so the chosen delivery is the one the compete is told about.
func _dump_concession(ctx: RoleContext, spot: Vector3, our_goalie: Vector3,
		known_recovery: float = -1.0) -> Vector2:
	var recovery: float = known_recovery
	if recovery < 0.0:
		recovery = AIActionScoring.chase_recovery(
				spot, _scratch_our_chasers, _scratch_opponents,
				_scratch_our_chaser_vels, _scratch_opponent_vels)
	var loss: float = 1.0 - recovery
	var concede: float = _turnover_cost(ctx, spot, loss, our_goalie)
	concede += _counter_exposure_cost(ctx, spot, loss, ctx.self_pos, our_goalie)
	return Vector2(concede, recovery)


# Last-resort DUMP. Returns [dump_value, aim_point, is_soft, is_rim (always
# false here — a rim is chosen as a pass), settle_point, launch_speed];
# dump_value is -INF when no dump applies: the own-side neutral zone or the OZ,
# a delayed offside or an icing release, no legal clear, or no dump-in solution.
# The caller reads the value only as availability and for the debug label.
#
# The aim (a standoff down the launch line, where the stick points) and the
# settle (where the puck comes to rest) are DIFFERENT, and every term is priced
# at the settle. Both dumps are searched releases — see
# Scripts/domain/ai/CLAUDE.md → "Dumps are searched RELEASES":
#   DZ CLEAR — the legal launch we concede LEAST by; a pure concession.
#   NZ DUMP-IN — offensive, priced on the race to the resting spot; never icing,
#     since it is offered only past the red line.
func _best_dump(ctx: RoleContext, our_goalie: Vector3) -> Array:
	var self_pos: Vector3 = ctx.self_pos
	var attacking_goal: Vector3 = ctx.attacking_goal_pos
	var defending_goal: Vector3 = ctx.defending_goal_pos
	var in_own_zone: bool = AIActionScoring.in_offensive_zone(self_pos, defending_goal)
	var past_center: bool = AIActionScoring.past_center_toward_attack(
			self_pos, attacking_goal)
	if not in_own_zone and not (past_center
			and not AIActionScoring.in_offensive_zone(self_pos, attacking_goal)):
		return [-INF, Vector3.INF, false, false, Vector3.INF, 0.0]

	var origin: Vector3 = _pass_origin(ctx)
	if not in_own_zone:
		# Icing reads the PUCK, which sits a stick off the body: a dump-in from a
		# body past centre can still leave from behind the red line. And with a
		# teammate owing a tag-up, a dumped puck is one nobody may touch.
		if ctx.zone_entry_blocked or (ctx.icing_enforced and InfractionRules.behind_red_line(
				origin.z, signf(attacking_goal.z))):
			return [-INF, Vector3.INF, false, false, Vector3.INF, 0.0]
	# Our chasers = teammates + ourselves (we dump and chase).
	_scratch_our_chasers.clear()
	_scratch_our_chaser_vels.clear()
	for i: int in _scratch_our_defenders.size():
		_scratch_our_chasers.append(_scratch_our_defenders[i])
		_scratch_our_chaser_vels.append(_scratch_our_defender_vels[i])
	_scratch_our_chasers.append(self_pos)
	_scratch_our_chaser_vels.append(ctx.self_velocity)

	var launch: Vector3
	var settle: Vector3
	var is_soft: bool
	# (concede, recovery) for the delivery finally chosen.
	var priced := Vector2.ZERO
	if in_own_zone:
		# HIGH is doctrine, not a searched axis: the loft buys passage over the
		# sticks between us and the blue line, not time.
		is_soft = false
		var n: int = AIActionScoring.dump_clear_candidates(
				origin, -ctx.own_goal_dir, AIActionScoring.PASS_SPEED_M_S,
				ShotMechanics.ELEVATION_HIGH, defending_goal,
				_scratch_clear_vels, _scratch_clear_spots)
		if n == 0:
			# Every launch either ices or dies in our own zone: decline rather than
			# fire one.
			return [-INF, Vector3.INF, false, false, Vector3.INF, 0.0]
		# Rank the legal launches by concession, depth (nearness to their blue
		# line) only as the tie-break. The race runs first: every concession term
		# scales by the loss probability, so a certain recovery concedes exactly
		# zero — the best any clear can score — and once a free clear exists the
		# dearer ones are skipped unpriced (an exact prune).
		_scratch_clear_recovery.resize(n)
		var free_exists: bool = false
		for i: int in n:
			var rec: float = AIActionScoring.chase_recovery(
					_scratch_clear_spots[i], _scratch_our_chasers, _scratch_opponents,
					_scratch_our_chaser_vels, _scratch_opponent_vels)
			_scratch_clear_recovery[i] = rec
			free_exists = free_exists or rec >= 1.0
		var target_z: float = -ctx.own_goal_dir * GameRules.BLUE_LINE_Z
		var best_price: float = -INF
		var best_miss: float = INF
		for i: int in n:
			var rec: float = _scratch_clear_recovery[i]
			if free_exists and rec < 1.0:
				continue
			var spot: Vector3 = _scratch_clear_spots[i]
			var spot_priced := Vector2(0.0, rec)
			if rec < 1.0:
				spot_priced = _dump_concession(ctx, spot, our_goalie, rec)
			var price: float = -spot_priced.x
			var miss: float = absf(spot.z - target_z)
			if price <= best_price - CLEAR_PRICE_TIE_BAND:
				continue
			if price < best_price + CLEAR_PRICE_TIE_BAND and miss >= best_miss:
				continue
			best_price = maxf(price, best_price)
			best_miss = miss
			launch = _scratch_clear_vels[i]
			settle = spot
			priced = spot_priced
	else:
		is_soft = true
		_scratch_dump_landing[0] = origin
		# The pace ladder runs over the dumper's OWN release band, and the winning
		# pace must be carried out to the release (dump_launch_speed), or the
		# placement is lost.
		launch = AIActionScoring.solve_dump_in(
				origin, attacking_goal, ctx.self_wrister_shot_speed,
				ShotMechanics.ELEVATION_FLAT,
				_scratch_our_chasers, _scratch_opponents, _goalie_now(ctx),
				_scratch_dump_landing, _scratch_our_chaser_vels,
				_scratch_opponent_vels)
		if launch == Vector3.ZERO:
			return [-INF, Vector3.INF, false, false, Vector3.INF, 0.0]
		settle = _scratch_dump_landing[0]
		priced = _dump_concession(ctx, settle, our_goalie)

	# Everything below prices the RESTING spot.
	var recovery: float = priced.y
	var concede: float = priced.x
	# Only the DUMP-IN earns a gain, for the race it is trying to win. The clear
	# stays a pure concession; its recovery race reaches it through `concede`.
	var gain: float = 0.0
	if is_soft:
		# MOMENTUM-HONEST chase clock; never `nearest_distance / max_speed`, an
		# instant full-speed sprint from a standstill. Nearest by ETA, not by
		# metres: the man already moving that way is the chaser even when someone
		# flat-footed stands closer.
		var chase_t: float = AIArrival.time_to_arrive(
				self_pos, settle, ctx.self_velocity, ctx.self_max_speed,
				ctx.self_max_accel, ctx.self_lateral_grip)
		for i: int in _scratch_our_defenders.size():
			var mate_caps: AISkaterCaps = _scratch_our_defender_caps[i]
			chase_t = minf(chase_t, AIArrival.time_to_arrive(
					_scratch_our_defenders[i], settle, _scratch_our_defender_vels[i],
					mate_caps.max_speed if mate_caps != null else ctx.self_max_speed,
					mate_caps.max_accel if mate_caps != null else ctx.self_max_accel))
		var chase_decay: float = AIActionScoring.delay_discount(chase_t)
		# The settle spot's potential is FUTURE value, so it pays the realization
		# discount like every other future-value read.
		gain = recovery * AIActionScoring.position_potential(
				settle, attacking_goal, _scratch_opponents) * chase_decay \
				* AIActionScoring.potential_realization_discount(
						settle, attacking_goal)

	# Aim down the launch line, not at the resting spot (see DUMP_AIM_STANDOFF_M).
	var aim: Vector3 = origin + launch.normalized() * DUMP_AIM_STANDOFF_M
	return [gain - concede, aim, is_soft, false, settle, launch.length()]


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
	_project_opponents_to(ctx, local_time, _scratch_opponents_path)
	var lane: float = AICarrySpace.carry_lane_clearance(
			self_pos, candidate, local_time, _scratch_opponents, _scratch_opponent_vels,
			ctx.self_max_speed)
	if lane <= 0.0:
		return -INF
	if lane * decay <= best_so_far:
		return -INF
	var cand_puck_pos: Vector3 = _puck_pos_at(candidate, ctx.attacking_goal_pos)
	var cur_puck_pos: Vector3 = _puck_pos_at(self_pos, ctx.attacking_goal_pos)
	# apply_escape: a defender the carrier out-skates on this drive can't sustain
	# the strip, so driving PAST a man reads as winnable, not as a wall.
	var safety: float = AICarrySpace.carry_safety(
			cur_puck_pos, cand_puck_pos, local_time,
			_scratch_opponents, _scratch_opponent_vels, _scratch_opponent_caps,
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
	# (_arrival_hold_wait): at that hold's pace and keep odds, with any pull the
	# carry is too short for waited out in the wind-up the keeper races.
	var cand_wait: float = 0.0
	var cand_share: float = 1.0
	var cand_keep: float = 1.0
	if _shot_reads(ctx, self_pos,
			candidate + arrive_vel * AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S):
		cand_wait = _arrival_hold_wait(ctx, candidate, arrive_vel, local_time)
		cand_share = _holds.arrival_share
		cand_keep = _holds.arrival_keep
	var cand_speed: float = ctx.self_wrister_shot_speed * cand_share
	var cand_windup: float = AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S + cand_wait
	# The keeper backs in as the carry closes on him (the planning depth model).
	# Closing is the rate this carry shortens the puck's distance to the goal.
	var carry_closing: float = (self_pos.distance_to(ctx.attacking_goal_pos)
			- candidate.distance_to(ctx.attacking_goal_pos)) / maxf(local_time, 0.001)
	var tracked_goalie: Vector3 = AIActionScoring.predict_goalie_pos(
			_goalie_now(ctx), ctx.attacking_goal_pos, local_time, candidate,
			carry_closing)
	var cand_release: Vector3 = AIActionScoring.release_ahead_of_goalie(
			candidate + arrive_vel * cand_windup,
			ctx.attacking_goal_pos, tracked_goalie)
	var cand_flight: float = cand_release.distance_to(ctx.attacking_goal_pos) \
			/ maxf(cand_speed, 1.0)
	# Same expected-lateness budget as the shoot-now sweep (timing error × 0.5),
	# and the keeper still backing in over the wind-up + flight at the arrival
	# pace.
	var release_closing: float = AIActionScoring.closing_toward(
			candidate, arrive_vel, ctx.attacking_goal_pos)
	var cand_goalie: Vector3 = AIActionScoring.predict_goalie_pos(
			tracked_goalie, ctx.attacking_goal_pos,
			cand_windup + cand_flight + ctx.shot_timing_error_s * 0.5,
			cand_release, release_closing)
	var cand_unsettled: float = 0.0
	if ctx.reads_goalie_motion:
		cand_unsettled = AIActionScoring.goalie_unsettled(
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
			_goalie_now(ctx), ctx.attacking_goal_pos, cand_release, release_t)
	var dest_score: float = _score_at(ctx, cand_release, self_pos,
			_scratch_opponents_path, cand_goalie,
			cand_speed, cand_unsettled, ctx.self_aim_spread_rad,
			cand_displacement, ctx.self_loft_tans.z, cand_keep)
	# ENTRY CONTINUATION: from outside the zone an in-zone candidate is worth what
	# a carrier there does next — the drive-in from it, priced in the in-zone
	# regime and starting when we arrive — which its own shot xG badly
	# understates just inside the line.
	if AIActionScoring.in_offensive_zone(candidate, ctx.attacking_goal_pos) \
			and not AIActionScoring.in_offensive_zone(self_pos, ctx.attacking_goal_pos):
		dest_score = maxf(dest_score, _entry_value(_receiver_drive_in_value(
				ctx, candidate, ctx.self_wrister_shot_speed,
				ctx.caps_by_peer.get(ctx.peer_id), arrive_vel, candidate, local_time, true)))
	var keep_prob: float = safety
	var cost: float = 0.0
	# A fully safe route (the common open-ice case) skips localizing a strip
	# that cannot happen.
	if keep_prob < 1.0:
		var strip_point: Vector3 = AICarrySpace.carry_strip_point(
				cur_puck_pos, cand_puck_pos, local_time,
				_scratch_opponents, _scratch_opponent_vels, _scratch_opponent_caps, true)
		cost = _turnover_cost(ctx, strip_point,
			1.0 - keep_prob, our_goalie)
		# Transition exposure (5v5): the carrier's recovery race starts from the
		# CANDIDATE, the spot this carry commits him to.
		cost += _counter_exposure_cost(ctx, strip_point, 1.0 - keep_prob,
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
# the pass OPTION the spot opens (_candidate_pass_option), credited as the
# IMPROVEMENT over the same read at the current spot — a lane already open from
# here is the live pass's to take, so holding a cashable option is never a
# reason to keep carrying. CEILING PRUNE (exact): the credit can't exceed
# _pass_option_ceiling − _pass_option_at_self, so when that can't raise
# dest_score the per-receiver lane loop is skipped.
func _upgrade_candidate_two_ply(ctx: RoleContext, i: int) -> float:
	var candidate: Vector3 = _beam_pos[i]
	var dest_score: float = _beam_dest[i]
	var lane: float = _beam_lane[i]
	var decay: float = _beam_decay[i]
	var safety: float = _beam_safety[i]
	if _pass_option_ceiling - _pass_option_at_self > dest_score:
		dest_score = maxf(dest_score, maxf(
				0.0, _candidate_pass_option(ctx, candidate,
						dest_score + _pass_option_at_self) - _pass_option_at_self))
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
			self_pos, apex, t1, _scratch_opponents, _scratch_opponent_vels,
			ctx.self_max_speed)
	if lane1 <= 0.0 or lane1 * decay <= best_so_far:
		return -INF
	var cur_puck: Vector3 = _puck_pos_at(self_pos, ctx.attacking_goal_pos)
	var apex_puck: Vector3 = _puck_pos_at(apex, ctx.attacking_goal_pos)
	var dest_puck: Vector3 = _puck_pos_at(dest, ctx.attacking_goal_pos)
	var safety1: float = AICarrySpace.carry_safety(
			cur_puck, apex_puck, t1, _scratch_opponents,
			_scratch_opponent_vels, _scratch_opponent_caps, true)
	if lane1 * decay * safety1 <= best_so_far:
		return -INF
	# Leg two starts where the defense has skated to during leg one.
	_project_opponents_to(ctx, t1, _scratch_opponents_cont)
	var lane2: float = AICarrySpace.carry_lane_clearance(
			apex, dest, t2, _scratch_opponents_cont, _scratch_opponent_vels,
			ctx.self_max_speed)
	if lane2 <= 0.0:
		return -INF
	var safety2: float = AICarrySpace.carry_safety(
			apex_puck, dest_puck, t2, _scratch_opponents_cont,
			_scratch_opponent_vels, _scratch_opponent_caps, true)
	var keep: float = safety1 * safety2
	var ceiling: float = lane1 * lane2 * decay * keep
	if ceiling <= best_so_far:
		return -INF
	_project_opponents_to(ctx, t1 + t2, _scratch_opponents_cont)
	var dest_score: float = _score_at(ctx, dest, self_pos,
			_scratch_opponents_cont, _goalie_now(ctx),
			ctx.self_wrister_shot_speed, 0.0, ctx.self_aim_spread_rad, 0.0,
			ctx.self_loft_tans.z)
	var benefit: float = dest_score * ceiling
	if keep >= 1.0:
		return benefit
	# The strip is priced on whichever leg is the unsafe one.
	var strip_point: Vector3
	if safety1 <= safety2:
		strip_point = AICarrySpace.carry_strip_point(
				cur_puck, apex_puck, t1, _scratch_opponents,
				_scratch_opponent_vels, _scratch_opponent_caps, true)
	else:
		_project_opponents_to(ctx, t1, _scratch_opponents_cont)
		strip_point = AICarrySpace.carry_strip_point(
				apex_puck, dest_puck, t2, _scratch_opponents_cont,
				_scratch_opponent_vels, _scratch_opponent_caps, true)
	var cost: float = _turnover_cost(ctx, strip_point,
			1.0 - keep, our_goalie)
	cost += _counter_exposure_cost(ctx, strip_point, 1.0 - keep, dest, our_goalie)
	return benefit - cost


# Whether a shot released at `release` by a carrier now at `from_pos` is what
# _score_at prices the spot by. Outside the zone, from outside it, at a keeper
# home, the spot is worth its position and the shot (near nothing at that range)
# is never the better read, so its hold is not worth solving.
func _shot_reads(ctx: RoleContext, from_pos: Vector3, release: Vector3) -> bool:
	return AIActionScoring.in_offensive_zone(from_pos, ctx.attacking_goal_pos) \
			or AIActionScoring.in_offensive_zone(release, ctx.attacking_goal_pos) \
			or _goalie_now(ctx).distance_to(ctx.attacking_goal_pos) \
					>= AIActionScoring.THREAT_GOALIE_HOME_M


# The hold a carry candidate's shot on arrival is taken from (AIShotHolds
# .solve_arrival, its share and keep left in _holds), and the wait it owes before
# the press: the pull there from where the puck sits now, less the `carry_s` the
# carry gives the hands to make it.
func _arrival_hold_wait(ctx: RoleContext, candidate: Vector3, arrive_vel: Vector3,
		carry_s: float) -> float:
	var aim := Vector2(ctx.attacking_goal_pos.x - candidate.x,
			ctx.attacking_goal_pos.z - candidate.z)
	if aim.length_squared() < 0.0001:
		aim = Vector2(0.0, -signf(ctx.attacking_goal_pos.z))
	var facing: Vector2 = ctx.snapshot.skater_states[ctx.peer_id].facing
	var windup: float = AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S
	_holds.solve_arrival(aim.normalized(), Vector2(arrive_vel.x, arrive_vel.z), facing,
			candidate + arrive_vel * windup, carry_s + windup,
			_scratch_opponents, _scratch_opponent_vels, _scratch_opponent_caps)
	var puck: Vector3 = ctx.self_pos if ctx.snapshot.puck_state == null \
			else ctx.snapshot.puck_state.position
	var from := Vector2(puck.x - ctx.self_pos.x, puck.z - ctx.self_pos.z)
	return maxf(0.0, _holds.pull_time(from, _holds.arrival_offset, facing) - carry_s)


# The steepest loft rung a player's blade has, the league's when unknown.
static func _loft_high(caps: AISkaterCaps) -> float:
	return caps.loft_tans.z if caps != null else GameRules.DEFAULT_LOFT_TAN_HIGH


# Position-value scorer at `pos`, evaluated from the carrier at `from_pos`.
#
#   carrier in the zone:            shot xG at `pos`
#   carrier outside, `pos` outside: max(shot xG, position_potential × realization)
#   carrier outside, `pos` inside:  shot xG at `pos`, converted (_entry_value)
#
# Two value scales, keyed on the CARRIER — see Scripts/domain/ai/CLAUDE.md →
# "Positional value". The potential branch pays the realization discount: it is
# future value that still has to be skated to the slot, and undecayed,
# stand-still strictly beats a step toward the net in open ice.
#
# `opps` must already be projected to the time the actor will be at `pos`, in
# the same snapshot order as _scratch_opponent_caps. `shot_speed_m_s` and
# `loft_tan_high` are the SHOOTER's (this bot's for carry/stand candidates, the
# receiver's build for a pass). `_aim_spread_rad` is unused: the seam prices the
# chance, not the shooter. `shot_keep` is the odds the shooter still has the
# puck at the press; it discounts the shot, never the position value.
func _score_at(ctx: RoleContext, pos: Vector3, from_pos: Vector3,
		opps: Array[Vector3],
		predicted_goalie_pos: Vector3,
		shot_speed_m_s: float = AIActionScoring.WRISTER_SHOT_SPEED_M_S,
		goalie_unsettled_factor: float = 0.0,
		_aim_spread_rad: float = 0.0,
		keeper_displacement_m: float = 0.0,
		loft_tan_high: float = GameRules.DEFAULT_LOFT_TAN_HIGH,
		shot_keep: float = 1.0) -> float:
	var attacking_goal: Vector3 = ctx.attacking_goal_pos
	# Hot-path skip (the same proof threat_surface_shoot runs): with the keeper
	# HOME and settled, a direct shot from OUTSIDE the attacking zone is dead by
	# score_shoot's own coverage math, so the potential branch always wins. A
	# displaced, pulled or unsettled keeper voids the proof and computes fully.
	var out_of_zone: bool = not AIActionScoring.in_offensive_zone(pos, attacking_goal)
	if out_of_zone and goalie_unsettled_factor <= 0.0 \
			and not AIActionScoring.in_offensive_zone(from_pos, attacking_goal) \
			and predicted_goalie_pos.distance_to(attacking_goal) \
					< AIActionScoring.THREAT_GOALIE_HOME_M:
		var potential_nz: float = AIActionScoring.position_potential(
				pos, attacking_goal, opps)
		return potential_nz * AIActionScoring.potential_realization_discount(
				pos, attacking_goal)
	# THE SEAM (AIShotValue): xG plus a keeper-displacement term. A max over five
	# holes with structural cliffs cannot supply the small differences a carry
	# beam consumes. Displacement arrives in metres rather than the 0..1
	# unsettled scalar, which saturates the moment he is caught moving at all
	# and cannot say HOW beaten he is. The post seal is derived inside.
	var shoot_s: float = AIActionScoring.score_shoot_value(
			pos, attacking_goal, predicted_goalie_pos, keeper_displacement_m,
			GameRules.NET_HALF_WIDTH, opps, shot_speed_m_s,
			_scratch_opponent_caps, ShotEvent.ShotType.SHOT, loft_tan_high) * shot_keep
	if AIActionScoring.in_offensive_zone(from_pos, attacking_goal):
		# PURE xG in the offensive zone, with no possession floor: a smooth xG
		# surface does not go flat where no shot is available right now, so the
		# gradient is real.
		return shoot_s
	var potential_s: float = AIActionScoring.position_potential(
			pos, attacking_goal, opps)
	var realization: float = AIActionScoring.potential_realization_discount(
			pos, attacking_goal)
	if AIActionScoring.in_offensive_zone(pos, attacking_goal):
		return _entry_value(shoot_s)
	return maxf(shoot_s, potential_s * realization)


# An in-zone xG value as an out-of-zone carrier reads it, in position_potential's
# unit. Capped at a clean slot look, potential's own ceiling, which also keeps the
# [0, 1] bound the carry candidates' ceiling prunes rely on.
static func _entry_value(in_zone_xg: float) -> float:
	return minf(in_zone_xg / AIActionScoring.XG_SLOT_REF, 1.0)


# The pass OPTION a carry candidate opens: the best cached receiver value
# reachable through a CLEAR lane from the candidate spot, priced as a future
# action — lane × completion odds × the pass's flight decay ×
# PASS_OPTION_DISCOUNT. Without it a contained carrier's retreat earns nothing,
# since separation's value is the lanes it reopens. Coarse by design (receivers
# at their CURRENT spots, lanes against CURRENT defenders): it only has to rank
# spots; the fired pass is fully solved at fire time.
func _candidate_pass_option(ctx: RoleContext, candidate: Vector3,
		useless_below: float = 0.0) -> float:
	var best: float = 0.0
	for i: int in _scratch_option_receiver_pos.size():
		# Receiver ceiling (exact): lane/miss/decay all ≤ 1.
		if _scratch_option_receiver_val[i] * PASS_OPTION_DISCOUNT \
				<= maxf(best, useless_below):
			continue
		var rpos: Vector3 = _scratch_option_receiver_pos[i]
		if AINetObstacle.pass_lane_blocked_by_net(candidate, rpos):
			continue
		if AINetObstacle.pass_crosses_own_slot(
				candidate, rpos, ctx.own_goal_dir * GameRules.GOAL_LINE_Z):
			continue
		var dist: float = candidate.distance_to(rpos)
		var pass_speed: float = AIActionScoring.pass_launch_speed(
				dist, ctx.self_wrister_shot_speed, ctx.pass_speed_scale)
		var lane: float = AIActionScoring.lane_clear(
				candidate, rpos, _scratch_opponents, pass_speed,
				_scratch_opponent_vels, _scratch_opponent_caps)
		if lane <= 0.0:
			continue
		var option: float = _scratch_option_receiver_val[i] \
				* lane * (1.0 - AIActionScoring.pass_miss_prob(
						dist, ctx.self_pass_aim_error_rad)) \
				* AIActionScoring.delay_discount(dist / maxf(pass_speed, 1.0)) \
				* PASS_OPTION_DISCOUNT
		if option > best:
			best = option
	return best


# The value of a man DRIVING IN from `receiver_spot`: the value he reaches by
# carrying toward the net, up to RECEIVER_DRIVE_MAX_M and only as far as the path
# stays clear (carry_strip_point). Value = _score_at(reached) × keep × decay(time
# to reach it), on the same reach/clearance machinery as the carrier's own carry,
# so both sides of a pass are valued alike. One straight drive, no search.
# Serves pass receivers, the carrier's own floor, and the entry continuation.
#
# `start_s` > 0 prices a drive that begins that far in the future (the entry
# continuation after a carry candidate): defenders are read where they will be
# then, and `from_pos` names whose regime values the reached spot. `own_hands`:
# the drive is this carrier's, so the shot at its end is held as a carry
# candidate's is (_arrival_hold_wait); a receiver's hands are not modelled.
func _receiver_drive_in_value(ctx: RoleContext, receiver_spot: Vector3,
		receiver_shot_speed: float, receiver_caps: AISkaterCaps,
		receiver_vel: Vector3 = Vector3.ZERO, from_pos: Vector3 = Vector3.INF,
		start_s: float = 0.0, own_hands: bool = false) -> float:
	# A delayed offside is up: driving in from outside the zone is not on.
	if ctx.zone_entry_blocked \
			and not AIActionScoring.in_offensive_zone(receiver_spot, ctx.attacking_goal_pos):
		return 0.0
	var to_net_x: float = ctx.attacking_goal_pos.x - receiver_spot.x
	var to_net_z: float = ctx.attacking_goal_pos.z - receiver_spot.z
	var d: float = sqrt(to_net_x * to_net_x + to_net_z * to_net_z)
	# Already tight to the net: no room to improve by driving.
	if d <= RECEIVER_DRIVE_MIN_NET_DIST_M + 0.1:
		return 0.0
	var reach: float = minf(RECEIVER_DRIVE_MAX_M, d - RECEIVER_DRIVE_MIN_NET_DIST_M)
	var inv: float = 1.0 / d
	var dir_x: float = to_net_x * inv
	var dir_z: float = to_net_z * inv
	var target := Vector3(
			receiver_spot.x + dir_x * reach, 0.0, receiver_spot.z + dir_z * reach)
	if not AIRoleHelpers.is_legal_position(target):
		return 0.0
	var recv_speed: float = receiver_caps.max_speed if receiver_caps != null \
			else ctx.self_max_speed
	var recv_accel: float = receiver_caps.max_accel if receiver_caps != null \
			else ctx.self_max_accel
	# Momentum-honest: a man in stride carries his pace into the drive, one curling
	# back brakes it out first. Never `reach / max_speed`.
	var reach_time: float = AIArrival.time_to_arrive(
			receiver_spot, target, receiver_vel, recv_speed, recv_accel)
	# A defender in the way drops keep and stops the drive where he covers it;
	# apply_escape as for the carrier's own candidates.
	var opps: Array[Vector3] = _scratch_opponents
	if start_s > 0.0:
		_project_opponents_to(ctx, start_s, _scratch_opponents_entry)
		opps = _scratch_opponents_entry
	var keep: float = AICarrySpace.carry_safety(
			receiver_spot, target, reach_time,
			opps, _scratch_opponent_vels, _scratch_opponent_caps, true)
	if keep <= 0.0:
		return 0.0
	var reached: Vector3 = AICarrySpace.carry_strip_point(
			receiver_spot, target, reach_time,
			opps, _scratch_opponent_vels, _scratch_opponent_caps, true, true)
	var t: float = reach_time if reached == target \
			else AIArrival.time_to_arrive(
					receiver_spot, reached, receiver_vel, recv_speed, recv_accel)
	_project_opponents_to(ctx, start_s + t, _scratch_opponents_pass)
	# The keeper backs in over the receiver's drive exactly as over the carrier's
	# own: both sides of the carry-vs-pass compete must read the same keeper.
	var goalie: Vector3 = AIActionScoring.goalie_squared_pos(
			_goalie_now(ctx), ctx.attacking_goal_pos, reached, start_s + t,
			(receiver_spot.distance_to(ctx.attacking_goal_pos)
					- reached.distance_to(ctx.attacking_goal_pos)) / maxf(t, 0.001))
	var regime_from: Vector3 = from_pos if from_pos.is_finite() else ctx.self_pos
	var shot_speed: float = receiver_shot_speed
	var hold_keep: float = 1.0
	var wait: float = 0.0
	if own_hands and _shot_reads(ctx, regime_from, reached):
		var arrive_vel: Vector3 = (reached - receiver_spot) / t if t > 0.001 else Vector3.ZERO
		wait = _arrival_hold_wait(ctx, reached, arrive_vel, start_s + t)
		shot_speed *= _holds.arrival_share
		hold_keep = _holds.arrival_keep
	var advanced: float = _score_at(ctx, reached, regime_from,
			_scratch_opponents_pass, goalie, shot_speed, 0.0, 0.0, 0.0,
			_loft_high(receiver_caps), hold_keep)
	return advanced * keep * AIActionScoring.delay_discount(t + wait)


# How much room the carrier has to OPERATE toward the attacking objective —
# the controlled fraction of the forward cone over FORWARD_PRESSURE_HORIZON_M
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
			ctx.attacking_goal_pos, FORWARD_PRESSURE_HORIZON_M,
			_scratch_opponents, _scratch_opponent_vels, _scratch_opponent_caps,
			_scratch_bearing_control)


# The same forward-space read for a pass receiver at `pos` with velocity `vel`
# and build `caps` (see _pass_ev), so both sides of a carry-vs-pass compete pay
# the same toll for the same clogged ice.
func _forward_clearance_at(ctx: RoleContext, pos: Vector3, vel: Vector3,
		caps: AISkaterCaps) -> float:
	return AICarrySpace.controlled_space(
			pos, vel, caps, ctx.attacking_goal_pos, FORWARD_PRESSURE_HORIZON_M,
			_scratch_opponents, _scratch_opponent_vels, _scratch_opponent_caps)


# Value (EV) of the best DEVELOPING feed — a play a teammate is still
# creating, worth keeping the puck for. 0 if nothing is developing, and always
# 0 for a tier with ctx.holds_for_developing_feeds false (a cognition gate: it
# plays only what exists right now). Two kinds, both self-gating:
#
#   - FINISHER, not yet one-timer-ready: the feed to the spot he is DRIVING TO
#     (projected OUTLET_DEVELOP_WINDOW_S along his velocity, inside the zone by
#     the reception band), priced on the seam (score_pass_value) with the keeper
#     given the flight plus the finisher's wrister charge to re-square. So a
#     fresh zone entry holds for the mates still arriving instead of settling
#     for the weak from-the-top shot.
#
#   - Breakout OUTLET (BREAKOUT_STRONG / OUTLET / BREAKOUT_D2): an outlet
#     skating its route toward open ice — see _developing_outlet_feed. This is
#     why a pressured own-zone carrier protects the puck and skates instead of
#     forcing a low-value backpass.
func _best_developing_feed(ctx: RoleContext) -> float:
	if not ctx.holds_for_developing_feeds:
		return 0.0
	if ctx.team_brain == null:
		return 0.0
	var self_pos: Vector3 = ctx.self_pos
	var our_goalie: Vector3 = AIRoleHelpers.resolve_our_goalie_pos(ctx)
	var self_state: SkaterNetworkState = ctx.snapshot.skater_states.get(ctx.peer_id)
	var self_facing: Vector2 = self_state.facing if self_state != null else Vector2.ZERO
	var best: float = 0.0
	for pid: int in _scratch_teammate_ids:
		var slot: int = ctx.team_brain.get_slot(pid)
		var tm: SkaterNetworkState = ctx.snapshot.skater_states.get(pid)
		# The live pass scoring skips a mate who can't legally play the puck, so
		# holding for one would wait forever.
		if tm == null or ctx.snapshot.is_out_of_play(pid):
			continue
		var feed: float = 0.0
		if slot == AIRoleSlots.Slot.FINISHER:
			# A one-timer-flagged finisher is already fed by the normal pass
			# scoring. The OZ gate reads the PROJECTED spot — a finisher a stride
			# outside the line, driving in, is the developing cross-seam — and
			# uses the live pass filter's reception band, since holding for a
			# spot the pass scoring may never hit would wait forever.
			var fin_vel: Vector3 = tm.velocity
			var spot := Vector3(
					tm.position.x + fin_vel.x * OUTLET_DEVELOP_WINDOW_S, 0.0,
					tm.position.z + fin_vel.z * OUTLET_DEVELOP_WINDOW_S)
			if ctx.team_brain.is_one_timer_ready(pid) \
					or not AIActionScoring.in_offensive_zone(
							spot, ctx.attacking_goal_pos, OZ_RECEIVE_LINE_BUFFER_M) \
					or not AIRoleHelpers.is_legal_position(spot):
				continue
			var dist: float = self_pos.distance_to(spot)
			var pass_speed: float = AIActionScoring.pass_launch_speed(
					dist, ctx.self_wrister_shot_speed, ctx.pass_speed_scale)
			var flight_t: float = clampf(dist / pass_speed, 0.0, PASS_LEAD_MAX_S)
			_project_opponents_to(ctx, flight_t, _scratch_opponents_pass)
			# On the seam, because this value is compared directly against
			# fire_score (see score_pass_value).
			feed = AIActionScoring.score_pass_value(
					self_pos, spot, ctx.attacking_goal_pos,
					AIShotValue.displacement_deficit_m(
							_goalie_now(ctx), ctx.attacking_goal_pos, spot,
							flight_t + AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S),
					_scratch_opponents_pass, pass_speed, _scratch_opponent_caps)
		elif slot == AIRoleSlots.Slot.BREAKOUT_STRONG \
				or slot == AIRoleSlots.Slot.OUTLET \
				or slot == AIRoleSlots.Slot.BREAKOUT_D2:
			# BREAKOUT_D2 (5v5): the D-to-D behind the net that reverses the flow
			# when F1 overcommits strong-side — worth a beat's hold while the
			# partner is still SKATING to it (unlike BREAKOUT_WEAK, see
			# _developing_outlet_feed). The min-speed gate means a partner
			# already parked there never reads as developing.
			feed = _developing_outlet_feed(ctx, tm, our_goalie, self_facing, ctx.caps_by_peer.get(pid))
		if feed > best:
			best = feed
	return best


# EV of the breakout feed a skating outlet is CREATING: the pass to his spot
# projected OUTLET_DEVELOP_WINDOW_S along his velocity, priced through the SAME
# _pass_ev as the live pass scoring. That parity is the termination guarantee:
# as the outlet arrives the live pass converges to this value and fire wins
# the tie (and _hold_elapsed_s decays a wait that never materialises).
#
# BREAKOUT_WEAK is deliberately excluded: the weak-side valve stays goal-side
# of the carrier by role contract, so waiting for it would mean holding for a
# backpass — the play this hold exists to avoid forcing.
func _developing_outlet_feed(ctx: RoleContext, tm: SkaterNetworkState,
		our_goalie: Vector3, self_facing_xz: Vector2,
		receiver_caps: AISkaterCaps = null) -> float:
	var vel: Vector3 = tm.velocity
	if vel.x * vel.x + vel.z * vel.z \
			< OUTLET_DEVELOP_MIN_SPEED_M_S * OUTLET_DEVELOP_MIN_SPEED_M_S:
		return 0.0
	var spot := Vector3(
			tm.position.x + vel.x * OUTLET_DEVELOP_WINDOW_S, 0.0,
			tm.position.z + vel.z * OUTLET_DEVELOP_WINDOW_S)
	if not AIRoleHelpers.is_legal_position(spot):
		return 0.0
	var dist: float = ctx.self_pos.distance_to(spot)
	var pass_speed: float = AIActionScoring.pass_launch_speed(
			dist, ctx.self_wrister_shot_speed, ctx.pass_speed_scale)
	var flight_t: float = clampf(dist / pass_speed, 0.0, PASS_LEAD_MAX_S)
	# Breakout receivers carry on reception (no one-timer): flight + wrister
	# charge, as the live pass scoring bills a non-ready receiver.
	var release_t: float = flight_t + AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S
	var rotation_time: float = _facing_rotation_time(self_facing_xz, ctx.self_pos, spot,
			ctx.self_reach_cone_half_angle, ctx.self_facing_turn_rate)
	return _pass_ev(ctx, spot, pass_speed, flight_t, release_t,
			flight_t + rotation_time, our_goalie, receiver_caps)


# Approximate carried-puck position when the carrier is at `body_pos`:
# CARRY_BLADE_AIM_FORWARD_M toward the attacking goal, where the state
# machine's carry mouse aims. The safety reads measure defender → puck (the real
# poke geometry), not defender → body. Falls back to `body_pos` when it sits on
# the goal.
func _puck_pos_at(body_pos: Vector3, attacking_goal: Vector3) -> Vector3:
	var to_goal: Vector3 = attacking_goal - body_pos
	to_goal.y = 0.0
	var len_sq: float = to_goal.x * to_goal.x + to_goal.z * to_goal.z
	if len_sq < 0.0001:
		return body_pos
	var inv: float = 1.0 / sqrt(len_sq)
	return body_pos + to_goal * (inv * AIBotMechanics.CARRY_BLADE_AIM_FORWARD_M)


# The pass valve's read: the offside line reads the PUCK, which leads the body,
# so the zone is taken once the body, the puck, or the puck at release is in.
func _zone_taken(ctx: RoleContext) -> bool:
	var goal: Vector3 = ctx.attacking_goal_pos
	if AIActionScoring.in_offensive_zone(ctx.self_pos, goal):
		return true
	if ctx.snapshot.puck_state == null:
		return false
	var puck: Vector3 = ctx.snapshot.puck_state.position
	return AIActionScoring.in_offensive_zone(puck, goal) or AIActionScoring.in_offensive_zone(
			puck + ctx.self_velocity * AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S, goal)


# OZ slot anchor — the long-range carry candidate and the forward axis of the
# carry search, a fixed depth off the attacking goal line.
func _slot_anchor(own_goal_dir: float) -> Vector3:
	var slot_z: float = -own_goal_dir * (GameRules.GOAL_LINE_Z - GameRules.SLOT_DIST_M)
	return Vector3(0.0, 0.0, slot_z)


# Where a pass physically leaves from: the carried puck (up to a stick's reach
# from the body), falling back to the body center when the snapshot has no
# puck. Measured from the chest instead, the ~1 m origin error is a systematic
# over-lead on a close feed.
func _pass_origin(ctx: RoleContext) -> Vector3:
	if ctx.snapshot.puck_state != null:
		return Vector3(
				ctx.snapshot.puck_state.position.x, 0.0,
				ctx.snapshot.puck_state.position.z)
	return ctx.self_pos


# The opposing goalie's CURRENT world position; the attacking goal when his
# state isn't buffered yet.
func _goalie_now(ctx: RoleContext) -> Vector3:
	var opp_goalie: GoalieNetworkState = ctx.snapshot.goalie_states.get(1 - ctx.team_id)
	if opp_goalie == null:
		return ctx.attacking_goal_pos
	return Vector3(opp_goalie.position_x, 0.0, opp_goalie.position_z)


# AIActionScoring.predict_goalie_pos from the goalie's current position.
# `release_time_s` is the time from now until the shot leaves the blade.
func _predict_goalie_at(ctx: RoleContext, release_time_s: float,
		puck_pos_at_release: Vector3, closing_speed_m_s: float = 0.0) -> Vector3:
	return AIActionScoring.predict_goalie_pos(
			_goalie_now(ctx), ctx.attacking_goal_pos,
			release_time_s, puck_pos_at_release, closing_speed_m_s)


# Companion to _predict_goalie_at: how unsettled [0,1] the goalie is at that
# same release. _score_at reads it only to void its keeper-home skip; the seam
# itself prices a caught-moving keeper by displacement. Cognition gate: a
# goalie-motion-blind tier (ctx.reads_goalie_motion false) reads 0.
func _goalie_unsettled_at(ctx: RoleContext, release_time_s: float,
		puck_pos_at_release: Vector3, closing_speed_m_s: float = 0.0) -> float:
	if not ctx.reads_goalie_motion:
		return 0.0
	return AIActionScoring.goalie_unsettled(
			_goalie_now(ctx), ctx.attacking_goal_pos,
			release_time_s, puck_pos_at_release, closing_speed_m_s)
