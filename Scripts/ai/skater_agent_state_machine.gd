class_name SkaterAgentStateMachine
extends RefCounted

const _PhysicsConstants: GDScript = preload("res://Scripts/game/constants.gd")

# Per-bot AI state machine. See Scripts/ai/CLAUDE.md → How an agent is put together.

enum State {
	OFF_PUCK,         # default off-puck — anchor from brain slot
	CHASE_PUCK,       # loose-puck chase — pursue, blade on the puck
	CARRY,            # with puck, no committed action — aim at goal
	SHOOT_PRESSED,    # multi-tick wrister charge aimed at goalie shadow
	PASS_PRESSED,     # multi-tick wrister charge aimed at a lead or a dump line
	ONE_TIMER_PRESSED,   # off-puck FINISHER fire-on-contact when ready + puck in zone
}

# Margin from the goal line that anchors are clamped inside of. The X-inset is
# AIStationSearch.RINK_INSET_M.
const RINK_Z_INSET: float = 1.0

# How far inside the hard reach-cone edge (_self_reach_cone_half_angle, ≈ 157°)
# an aim must sit to count as reachable with the heading frozen — the one-timer's
# press gate. Feel knob: widen toward 0 if bots pass up reachable aims, tighten if
# a wide aim's blade visibly lags the release.
const AIM_COMMIT_CONE_MARGIN_RAD: float = deg_to_rad(25.0)

# Default / floor for the pre-aim convergence timeout — the safety net for
# convergence that never lands (a receiver who keeps moving past the lead point,
# numerical drift). Sized on the worst case under the arc-step model: a 180° swing
# at MOUSE_ARC_RATE_RAD_S = 7.5 rad/s takes π / 7.5 ≈ 420 ms, so ~500 ms leaves
# margin and then bails; typical 30-60° swings converge in 60-120 ms, so this is an
# edge guard, not the dominant timing path. _apply_aim_slew raises
# _intent_max_wait_ticks above this when a lower blade-slew cap slows that swing.
const INTENT_MAX_WAIT_TICKS: int = _PhysicsConstants.PHYSICS_TICK / 2   # ~500 ms
var _intent_max_wait_ticks: int = INTENT_MAX_WAIT_TICKS
# After a puck-engagement event (we got stripped, or we just stripped someone —
# both detected as "puck became loose while we were close"), pull the blade back to
# our body for this many ticks. Speed-scaled: a bot at full skating speed was
# committed harder and takes longer to reset. The variance also breaks lockstep
# between two bots in the same engagement (their speeds are almost never equal).
const ENGAGEMENT_COOLDOWN_MIN_TICKS: int = _PhysicsConstants.PHYSICS_TICK / 10        # ~100 ms
const ENGAGEMENT_COOLDOWN_MAX_TICKS: int = _PhysicsConstants.PHYSICS_TICK * 2 / 5     # ~400 ms
const ENGAGEMENT_PROXIMITY_M: float = 2.0        # blade-on-puck range

# This bot's standing-start push — what its own ETA reads price the pursuit
# ramp at (see _lead_intercept). Set to the real value via apply_capabilities.
var _chase_max_accel: float = GameRules.DEFAULT_SKATER_THRUST_M_S2

# Above this speed a loose puck is a live pass / stripped puck rather than one to
# skate onto: the chase aims the blade along its flight line instead of at a fixed
# intercept point. See Scripts/ai/CLAUDE.md → Reception doctrine.
const LOOSE_PUCK_TRACK_SPEED_M_S: float = 8.0

# Sideways stand-off from a fast feed's path for the squared pass reception
# (SkaterAgentReception.read_pass). Rescaled per build in apply_capabilities; the
# default is the league baseline.
var _receive_body_offset: float = (
		GameRules.DEFAULT_STICK_LENGTH_M
		+ GameRules.DEFAULT_BLADE_LENGTH_M
		- SkaterAgentReception.RECEIVE_BODY_INSET_M)

# Reception-decision return codes (see _try_shot_reception).
const _RECV_NONE: int = 0           # not a shot reception — run the normal catch
const _RECV_CATCH_STRIDE: int = 1   # Mode B handled aim+steer; caller runs transitions
const _RECV_ONE_TIME: int = 2       # Mode A transitioned to ONE_TIMER_PRESSED; caller returns


# Behind-the-net cradle. A full CARRY_BLADE_AIM_FORWARD_M reach from behind the
# attacking cage chords the blade into the mesh, and stick-on-net contact strips
# the carried puck. The forward reach shortens toward CARRY_BEHIND_NET_CRADLE_M as
# the body enters the net's work zone (the frame's lateral span plus a margin,
# ramping in over CARRY_BEHIND_NET_BAND_M across the goal line). This is the SOFT
# layer; the puck pin's net collision (SkaterController) is the hard backstop.
# Fire-tracking overrides carry aim, so a net-front shot is never blunted. Feel
# constants.
const CARRY_BEHIND_NET_CRADLE_M: float = 0.6
const CARRY_BEHIND_NET_BAND_M: float = 0.6      # ramp band around the goal line
const CARRY_BEHIND_NET_LATERAL_M: float = 1.0   # lateral reach past the frame side still cradled


# Stickhandling: shift the carrier's mouse perpendicular to the attacking-goal
# aim, AWAY from the nearest opposing blade, measured blade-tip to puck (as the
# poke is). Full offset inside STICKHANDLE_FULL_OFFSET_RADIUS_M, tapering to zero
# at STICKHANDLE_THREAT_RADIUS_M. Not gated on closing velocity: a still defender
# with his stick out is as much a poke threat as one skating in.
#
# QUIET HANDS: body facing chases the carry cursor, so a sustained offset becomes
# body rotation — 0.33 m on the 1.3 m ring is ~±14° of wag; wider turns a threat
# crossing the line into a twitchy ~44° swing. The big threats belong to the
# deliberate answers (protect blend, the rolled carry). Ring metres —
# rescale with CARRY_BLADE_AIM_FORWARD_M.
const STICKHANDLE_THREAT_RADIUS_M: float = 3.0
const STICKHANDLE_FULL_OFFSET_RADIUS_M: float = 1.5
const STICKHANDLE_OFFSET_MAX_M: float = 0.33

# Face-the-route gates (the FACE THE ROUTE block in _carry_mouse_aim).
# ROUTE_MIN_DIST: below this the anchor is underfoot, so face the play.
# RETREAT_ADVANCE: the route's advance component along the attack axis below
# which it is a genuine retreat (face the play and back out); −0.3 keeps lateral
# and shallow-back routes faced. Feel choices.
const CARRY_FACE_ROUTE_MIN_DIST_M: float = 1.0
const CARRY_FACE_RETREAT_ADVANCE: float = -0.3

# "Man to beat" bar (_has_man_to_beat / the O-ZONE SQUARE block in
# _carry_mouse_aim): the carrier still has a man to beat while the presented-
# forward puck has less than this much room (AIRoleCarrier.forward_puck_clearance)
# from the nearest un-beaten stick; in the offensive zone with nobody to beat,
# the body squares to the net. A blade of real air — the same bar every other
# "is this puck safe" read uses, so the facing and the shield cannot disagree.
# Tier-agnostic: it needs no protect read.
const CARRY_MAN_TO_BEAT_CLEAR_M: float = AICarrySpace.EVADE_SAFE_CLEAR_MIN_M
# Once a man is engaged the bar rises by this, so a defender riding the boundary
# doesn't flip the carry-aim forward direction every re-eval. Debounce.
const CARRY_MAN_TO_BEAT_HYSTERESIS_M: float = 0.5 * GameRules.DEFAULT_BLADE_LENGTH_M

# How far off the play line the protect aim may swing the body. Facing chases
# the carry cursor, so aiming straight at a seam on the far hip spins the carrier
# out of the play; capped at side-on, the body turns just enough to interpose and
# the blade's ~157° reach cone extends to the seam from there. Feel tunable.
const CARRY_PROTECT_MAX_TURN_DEG: float = 90.0
# Rate (1/s) the shield blend eases toward the carrier mirror's raw protect_gain /
# protect_offset (~125 ms time constant), so a defender crossing the screen filter
# (a hard on/off) ramps the blade instead of snapping it. Feel tunable.
const CARRY_PROTECT_SMOOTH_RATE: float = 8.0


# ── Defensive poke jab ────────────────────────────────────────────────────────
# The host strips the carrier when a defender's blade SWEEPS THROUGH the puck
# (PuckController._check_interactions → check_poke); the ready-stance aim never
# reaches through it. Within reach, a pressurer briefly aims its blade tip AT the
# puck. Discrete (jab + cooldown), so it commits and can miss.
#
# Reach: stick + blade + poke radius, rescaled per build in apply_capabilities;
# the default is the league baseline.
var _poke_jab_reach: float = (
		GameRules.DEFAULT_STICK_LENGTH_M
		+ GameRules.DEFAULT_BLADE_LENGTH_M
		+ GameRules.POKE_RADIUS_M)
var _stick_lift_reach: float = (
		GameRules.DEFAULT_STICK_LENGTH_M
		+ GameRules.DEFAULT_BLADE_LENGTH_M
		+ GameRules.STICK_LIFT_RADIUS_M)

# Longest a one-timer-ready stance is held across a carrier gap (pass/shot in
# flight). A real pass flight is well under this; the cap catches passes that die
# or deflect and leave the puck loose, which would otherwise camp the bot forever.
const ONE_TIMER_PRESERVE_MAX_TICKS: int = _PhysicsConstants.PHYSICS_TICK * 3 / 2   # ~1.5 s

# How far on the NZ side of the OZ blue line the offside-holding carrier waits and
# the tag-up target sits; past the line so InfractionRules.has_tagged_up doesn't
# oscillate at the boundary.
const OFFSIDE_HOLD_BUFFER_M: float = 1.0


var _blade_reach: float = AIBotMechanics.BLADE_REACH_M

# ── Wrister charge ───────────────────────────────────────────────────────────

# Straight-line span (m) of the cosmetic wind-up sweep. A full-power shot uses the
# whole span; a soft pass scales it down so the gesture reads as gentle. Compact,
# to match the ~125 ms charge.
const BOT_WRISTER_WIND_UP_SPAN_M: float = 0.4
# Mid-charge bail radius: an opponent inside it cancels the charge via
# slap_pressed (the other shot button), and CARRY re-evaluates next tick.
const BOT_WRISTER_BAIL_RADIUS_M: float = 2.0
# Committed speed (m/s) at charge start below which the wind-up PLANTS (brakes in
# place) instead of steering to the projected release anchor: a near-still bot
# has no release spot to skate to, and steering lets the repulsion fields wander
# the body. Above it, a rush wrister arrives at the locked anchor in stride.
const BOT_WRISTER_PLANT_SPEED_M_S: float = 1.5

# Perpendicular offset of the wind-up lerp line off aim_dir, so the cosmetic
# sweep reads as a forehand pose rather than a jab through the body's centreline
# while staying inside ROM. The hand is the load's, from where the puck sits; a
# backhand is drawn on the backhand side.
const BOT_WRISTER_SIDE_OFFSET_M: float = 0.15

# How far short of the priced share the live load may be when a charged
# release presses: the aim the pre-aim checks is the locked hole, a few degrees
# off the line the share was priced along.
const LOAD_READY_SHARE_SLACK: float = 0.05

# ── Unified mouse motion ─────────────────────────────────────────────────────
# Every state's `input.mouse_world_pos` goes through `_step_mouse_internal` (one of
# the `_step_mouse_*` modes), which moves the cursor toward its shaped target at
# most one tick of the slew cap.
#
# MOUSE_MAX_SPEED_M_S is the perfect-bot default: at 100 m/s the cursor reaches
# any normal target inside one tick. The per-agent cap (_mouse_max_speed_m_s) is
# the bot's real blade speed, set in apply_capabilities.
const MOUSE_MAX_SPEED_M_S: float = 100.0
var _mouse_max_speed_m_s: float = MOUSE_MAX_SPEED_M_S
# ── Per-release execution error ──────────────────────────────────────────────
# Aim error budgets (radians on the release direction, uniform ±): shots on the
# shot budget, passes / dumps on the pass budget. ONE sample per release, drawn at
# press-state entry (_set_state → _sample_aim_error_rad) and held through the
# windup — a missed spot, not a shaking hand. From BotSkillProfile via
# apply_profile; both default 0, so raw test agents stay
# bit-deterministic.
var _shot_aim_error_rad: float = 0.0
var _pass_aim_error_rad: float = 0.0
# The error sampled for the CURRENT committed release (radians; + rotates the aim
# CCW around Y). Meaningless outside a press cycle.
var _committed_aim_error_rad: float = 0.0
# Motor timing variance on the SHOT release (max seconds late, from
# BotSkillProfile.shot_timing_error_s); see _sample_release_hold_ticks.
var _shot_timing_error_s: float = 0.0
var _shoot_release_hold_ticks: int = 0
# Bots run at the host physics rate, so the mouse step uses a fixed delta, which
# keeps it deterministic.
const MOUSE_TICK_DELTA: float = 1.0 / _PhysicsConstants.PHYSICS_TICK

# How fast an ARC-mode target sweeps around self_pos (see _STEP_ARC). Capped at
# the IK-gate ceiling: above 7.5 rad/s, steady-state body lag (arc_rate /
# facing_drag_speed_braking) exceeds the ~157° twist the pose coordinator's IK
# gate allows and facing freezes. At 7.5 rad/s a 180° swing takes π/7.5 ≈ 420 ms
# with ~43° of body lag.
#
# The effective rate (_mouse_arc_rate_rad_s, from apply_capabilities) is the
# lesser of this ceiling and the blade-slew cap projected onto the blade's real
# orbit radius (_apply_aim_slew); above that the arc target would outrun the
# mouse's max step and the step would chord-cut the arc.
const MOUSE_ARC_RATE_RAD_S: float = 7.5
var _mouse_arc_rate_rad_s: float = MOUSE_ARC_RATE_RAD_S

# ── Owned state ──────────────────────────────────────────────────────────────
var _state: State = State.OFF_PUCK

# Identity / orientation
var _peer_id: int = 0
var _team_id: int = 0
# +1 if own goal is at +GOAL_LINE_Z (Team 0), -1 for Team 1.
# See GameManager._assign_goals_to_teams for the source of truth.
var _own_goal_dir: float = 1.0
var _attacking_goal_pos: Vector3 = Vector3.ZERO
var _team_brain: TeamBrain = null
# The strategy surface read during this dispatch — set at the top of dispatch()
# from _strategy(). See the dispatch-site comment and docs/ai-threading-plan.md.
var _current_strategy: TeamStrategyView = null


# The team-strategy surface for the current dispatch: the brain's frozen
# per-frame view when it exists (the off-thread-safe read path), falling back to
# the live brain when no view has been built (unit tests that dispatch without
# GameManager's per-frame build_view — single-threaded, so reading the live brain
# is safe). Null when no brain is wired.
func _strategy() -> TeamStrategyView:
	if _team_brain == null:
		return null
	var v: TeamBrainView = _team_brain.get_view()
	if v != null:
		return v
	return _team_brain
# Live peer -> team_id dict owned by PlayerRegistry. Read via
# `_team_id_by_peer.get(pid, -1)` in hot loops (lane filters,
# closest-teammate checks). A dict rather than a Callable — the
# Callable.call overhead shows up at the dispatch rate.
var _team_id_by_peer: Dictionary = {}
# Live peer -> AISkaterCaps dict owned by PlayerRegistry (memoized, rebuilt only
# on spawn / picker). Copied by reference onto RoleContext.caps_by_peer each build
# so roles / scorers can read any player's real build. Empty when unwired.
var _caps_by_peer: Dictionary = {}
# Handedness drives the wrister wind-up side: RH winds up on the +X
# (player-local) side of the aim line, LH on -X. Without this, every
# bot wrister would register as a backhand half the time and lose
# power via the backhand_power_coefficient.
var _is_left_handed: bool = false

# Reused fallback buffer for _opponent_ids when the per-frame team cache is
# empty (unit tests). Production always hits the cache and never touches this.
var _scratch_opp_ids: Array[int] = []
# Reused RoleContext — refilled (not reallocated) each dispatch so its scratch
# buffers persist across calls. Dispatch is sequential per bot, so a single
# instance is safe; the role decide() consumes everything before the next build.
var _role_ctx := RoleContext.new()
# Never-written stand-in for the brainless ctx build (no per-build literal —
# a {} in the hot path would allocate every dispatch).
var _empty_threat_memo: Dictionary[int, float] = {}
# Inert transition read for the no-brain path (tests, unwired agents): Mode.NONE
# with no attackers, so every consumer behaves as it did before the read existed.
var _inert_rush_read := AIRushRead.new()

# The slot + target this bot's role chose on the previous role dispatch —
# feeds RoleContext.prev_role_target for argmax switch-hysteresis (INF is
# stamped across a slot change so no role inherits another role's target).
var _prev_role_slot: int = AIRoleSlots.Slot.NONE
var _prev_role_target: Vector3 = Vector3.INF
# The man this skater's role is covering, from the last role dispatch
# (RoleDecision.locked_man_pid) — reset on slot change, and cleared on
# leaving OFF_PUCK: a skater chasing or carrying
# the puck covers nobody, whatever his last role decision said.
var _prev_locked_man_pid: int = -1
# Incumbent for the offensive stations' control hysteresis (see
# RoleDecision.held_forward_stand).
var _prev_held_forward_stand: bool = false

# Local acceleration fallback (_update_acceleration_cache), filled only when the
# snapshot lacks the host's shared cache. peer_id → Vector3 (last tick's velocity
# / smoothed accel).
var _prev_velocity_by_peer: Dictionary = {}
var _accel_by_peer: Dictionary = {}
# Local per-peer heading turn rate (rad/s), the receiver-commitment fallback
# built alongside _accel_by_peer when the shared snapshot cache is absent.
var _heading_omega_by_peer: Dictionary = {}
# The accel source consumed this tick: snapshot.accel_by_peer when present, else
# the local _accel_by_peer. Set every dispatch.
var _accel_ref: Dictionary = _accel_by_peer
# Heading-turn-rate source, resolved alongside _accel_ref.
var _omega_ref: Dictionary = _heading_omega_by_peer

# Carrier-role decision behavior. `_state_carry` calls `_carrier.decide(ctx)`
# every tick (it throttles re-evaluation internally) and copies its public fields
# into the mirror fields below for the press states and pre-aim.
var _carrier := AIRoleCarrier.new()

# Mirrored from `_carrier.pass_target_peer_id`; -1 = no pass target.
var _pass_target_peer_id: int = -1

# CARRY pre-aim state: the latched intent being pre-aimed before its press
# transition. State.CARRY = no intent.
var _intended_action: State = State.CARRY
var _intent_wait_ticks: int = 0

# Mirrored from `_carrier.last_carry_anchor`; CARRY steers to it.
var _last_carry_anchor: Vector3 = Vector3.ZERO

# Engagement cooldown (ENGAGEMENT_COOLDOWN_MIN/MAX_TICKS). _prev_carrier_peer_id
# is last tick's puck carrier, to detect the transition into "loose".
var _engagement_cooldown: int = 0
var _prev_carrier_peer_id: int = -1

# Mirrored from `_carrier.shot_loft_level` — the release loft
# (ShotMechanics.ELEVATION_*) of the best goalie hole aimed at.
var _shot_loft_level: int = ShotMechanics.ELEVATION_FLAT

# Mirrored from `_carrier.shot_aim_point` — the world aim point of that same hole,
# locked at charge start. INF → the continuous _shot_aim_point geometry.
var _shot_aim_locked: Vector3 = Vector3.INF

# Mirrored from `_carrier.shot_power_t` — the release power fraction of that same
# hole (every hole fires full power). Fed to input.bot_wrister_power_t.
var _shot_power_committed: float = 1.0

# Mirrored from `_carrier.shot_hold_offset` / `shot_hold_share`: where the puck
# sits off the body (world XZ) at the press of the hold the shot was priced
# from, and the share of pace its load gives there. Pre-aim carries the puck to
# it and presses once the live load reaches the share (_load_ready).
var _shot_hold_offset_locked: Vector3 = Vector3.ZERO
var _shot_hold_share_locked: float = 1.0
# The same for a charged pass or dump, solved at its intent transition
# (_lock_pass_hold): the puck stays where it is when its load already carries
# the pace, else it goes to the pocket for the feed.
var _pass_hold_offset: Vector3 = Vector3.ZERO
var _pass_hold_share: float = 0.0
# Configured from this bot's context each dispatch (_build_role_context).
var _holds := AIShotHolds.new()

# DUMP target, mirrored from `_carrier.dump_target` at commit and frozen through
# pre-aim + release. INF → not dumping. The dump reuses the PASS_PRESSED plumbing
# (_state_from_carrier_intent); this sentinel tells that state to aim at a
# LOCATION and skip the receiver-close bail.
#
# The dump is the rim pass (AIRimPass): it fires FLAT on the charged wrister at
# `_dump_launch_speed`, because how far round the boards it carries IS its pace.
var _dump_target: Vector3 = Vector3.INF
var _dump_launch_speed: float = AIPuckLane.PASS_SPEED_M_S

# Multi-tick wrister charge: shoot_held for BOT_WRISTER_CHARGE_TICKS while the
# cursor sweeps, so SkaterStateMachine fires a real wrister at release (direction
# = sweep direction, power = the committed bot_wrister_power_t).
var _shoot_charge_tick: int = 0
# Wind-up endpoint OFFSETS from self_pos, captured at SHOOT_PRESSED tick 0 and
# added to the CURRENT self_pos each tick. They must not be world positions: the
# charge tracker measures blade motion in the skater-translation-subtracted
# frame, where fixed world endpoints would have locomotion cancel the sweep.
var _shoot_wind_up_start: Vector3 = Vector3.ZERO
var _shoot_aim_target: Vector3 = Vector3.ZERO
# Committed shot direction (world XZ, normalized), locked at charge tick 0 and fed
# to InputState.bot_wrister_aim_dir — the wind-up cursor is a near-body bubble and
# would give a garbage origin→cursor. release_pos → aim_point, execution error
# folded in.
var _shoot_aim_dir_locked: Vector3 = Vector3.ZERO
# Wind-up side for SHOOT_PRESSED: +1 = forehand, -1 = backhand — the hand the
# load reads from the puck's spot at tick 0, locked for the charge.
var _shoot_side_sign: float = 1.0
# Locked steering destination for the wind-up (projected release position at
# charge tick 0). Never recompute it per tick from live velocity: the target turns
# self-referential and the body wobbles. _shoot_wind_up_moving: rush wrister
# (steer to the anchor) vs near-still (plant).
var _shoot_release_anchor: Vector3 = Vector3.ZERO
var _shoot_wind_up_moving: bool = false

# +1 for right-handed (blade on left), -1 for left-handed; orients the wind-up's
# lateral offset onto the forehand side.
var _handedness_perp_sign: float = 1.0

# Mirrored from _carrier.pass_target_speed: the distance-adaptive LAUNCH speed
# the chosen pass should fire at. Drives both the pass lead (so the fired aim
# matches the scored one) and the wrister charge fraction the wind-up targets.
var _pass_target_speed: float = AIPuckLane.PASS_SPEED_M_S
# Mirrored from _carrier.pass_should_saucer: PASS_PRESSED lofts the release over a
# contested mid-lane stick; _pass_target_speed carries the matching (capped) pace.
var _pass_should_saucer: bool = false
var _pass_charge_tick: int = 0
# The charged pass's committed power fraction, solved at its tick 0 for the hand
# the puck's spot gives (_pass_power_t).
var _pass_power_committed: float = 1.0
# Wind-up endpoint OFFSETS from self_pos for the charged pass, as for
# SHOOT_PRESSED but aimed at the receiver lead.
var _pass_wind_up_start: Vector3 = Vector3.ZERO
var _pass_aim_target: Vector3 = Vector3.ZERO
# Committed charged-pass direction (world XZ, normalized), locked at tick 0 — the
# controller aims the positional wrister along this directly for bots (passes are
# always forehand, so no committed backhand). See _shoot_aim_dir_locked.
var _pass_aim_dir_locked: Vector3 = Vector3.ZERO

# This bot's own attribute-scaled capabilities, set by apply_capabilities, used
# wherever the bot reasons about ITSELF. Defaults are the league baseline, for an
# unwired bot and the unit tests.
var _self_max_speed: float = GameRules.DEFAULT_SKATER_MAX_SPEED_M_S
var _self_wrister_shot_speed: float = GameRules.DEFAULT_WRISTER_POWER_MAX_M_S
var _self_lateral_grip: float = 1.0
# Body-check delivery (mass-emergent), so a defensive role can predict THIS bot's
# hit strength before committing to a check.
var _self_weight: float = 1.0
var _self_body_check_transfer: float = 0.65
var _self_handle_reach: float = 0.9
# Blade reach cone half-angle (ROM + torso twist) and Agility-scaled facing turn
# rate, so the carrier prices body rotation at this bot's real reach and speed.
var _self_reach_cone_half_angle: float = deg_to_rad(157.0)
var _self_facing_turn_rate: float = 6.0
# The wrist shot's load as this bot's body fires it (RoleContext's self_wrister_*
# block).
var _self_blade_speed: float = 10.0
var _self_backhand_coefficient: float = 0.75

# Sticky mode for _carry_aim_track_fire (shot-aim vs carry-aim), so close
# shoot/carry scores don't flip the blade between the two targets every ~30 Hz
# re-eval. Reset on CARRY entry.
var _carry_tracking_fire: bool = false

# The shield, low-passed toward the carrier mirror's raw protect_gain /
# protect_offset at CARRY_PROTECT_SMOOTH_RATE. Reset on CARRY entry so a fresh
# pickup doesn't inherit a previous carry's shield.
var _carry_protect_gain_smooth: float = 0.0
var _carry_protect_offset_smooth: Vector3 = Vector3.ZERO
# Latched side of the man-to-beat contest (_has_man_to_beat). Reset on CARRY
# entry.
var _carry_has_man: bool = false


# One-timer readiness mirrored from the most recent OFF_PUCK role decision, and
# published to TeamBrain for the carrier's pass scoring.
var _is_one_timer_ready: bool = false
# Physics ticks the ready flag has been PRESERVED across a carrier gap, bounded by
# ONE_TIMER_PRESERVE_MAX_TICKS. Reset whenever the flag is re-confirmed.
var _one_timer_preserve_ticks: int = 0

# Arrival tolerance for the one-timer's live-line settle anchor
# (SkaterAgentOneTimer.line_anchor): inside this we stop seeking and brake/hold
# so the feed arrives into the armed slapper zone.
const ONE_TIMER_ANCHOR_ARRIVE_M: float = 0.6

# Tick counter for ONE_TIMER_PRESSED, which holds slap_held (the real slapper
# one-timer charge) until the puck reaches the slapper zone, then drops it.
var _one_timer_press_tick: int = 0

# Whether ONE_TIMER_PRESSED has fired its slap press yet. Wound up, the body
# only pivots and shuffles, so the press waits until it can set for the feed
# that way before it arrives (_state_one_timer_pressed).
var _one_timer_slap_down: bool = false
# Seconds wound up since that press.
var _one_timer_charge_s: float = 0.0
# The feed in this body's frame (world XZ) as last seen loose: the swing leads
# against its pull, and once it is caught the snapshot no longer shows it.
var _one_timer_feed := Vector2.ZERO

# Budget backstop for ONE_TIMER_PRESSED. Entry happens at feed RELEASE, so it
# must outlast a full pass flight (~1 s on a long diagonal) plus settle slack;
# the dead-feed bail handles every genuine failure earlier.
const ONE_TIMER_PRESS_MAX_TICKS: int = _PhysicsConstants.PHYSICS_TICK * 6 / 5   # ~1.2 s
const _ONE_TICK_S: float = 1.0 / _PhysicsConstants.PHYSICS_TICK


# Pre-aim target locked when intent flips from CARRY to a fire action:
# recomputed per tick, compute_open_net_aim can flip corners with a centred
# goalie and the cursor never converges. INF on CARRY entry and after pre-aim
# hands off to the press state.
var _locked_pre_aim_point: Vector3 = Vector3.INF

# Per-bot RNG for hands-side execution sampling (per-release aim/timing errors),
# seeded in setup() so each bot has a deterministic but distinct stream.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Decision-rate throttle. The full dispatch runs every _dispatch_period_ticks in
# non-press states; skipped ticks reuse the cached move_vector and step the mouse
# toward the cached aim target, so blade motion stays at the physics rate. Press
# states always run full-rate (charge timing and pre-aim convergence are
# tick-sensitive). DISPATCH_PERIOD_TICKS is the perfect-bot default; the per-agent
# cadence comes from BotSkillProfile in apply_profile().
const DISPATCH_PERIOD_TICKS: int = (_PhysicsConstants.PHYSICS_TICK + 30) / 60   # ~60 Hz, rounded
var _dispatch_period_ticks: int = DISPATCH_PERIOD_TICKS

var _dispatch_skip_counter: int = 0

# ── Loose-puck reactivity clock ──────────────────────────────────────────────
# The chase gate reads the REAL carrier (snapshot.real_puck_carrier_peer_id) and
# applies its own delay here. Never gate the chase on puck_state's delayed
# carrier: that is GameManager's global team-shape settle timer, which restarts
# on every carrier change, so a scramble of grazes would defer the chase
# indefinitely. This clock measures how long the puck has been nobody's; a graze
# doesn't reset it — the puck must be held CONTROL_CONFIRM_S to count as possessed.
const CONTROL_CONFIRM_S: float = 0.08   # continuous carry before a touch counts as control
var _chase_reaction_delay_s: float = 0.0
var _loose_elapsed_s: float = 0.0       # how long the puck has been genuinely loose
var _control_elapsed_s: float = 0.0     # how long the current carrier has held it
var _cached_move_vector: Vector2 = Vector2.ZERO

# Off-puck role-decision throttle. The role argmax is the dominant AI cost and a
# slow-moving positional read, so it re-evaluates at ~30 Hz (the carrier's
# cadence) and the cached RoleDecision is reused between; steering, aim and
# transitions still run every full dispatch. Drained by the dispatch span so the
# wall-clock cadence holds across tiers. Timing-critical reads force an immediate
# re-eval (must_recompute in _state_off_puck).
const ROLE_DECISION_PERIOD_TICKS: int = _PhysicsConstants.PHYSICS_TICK / 30  # ~30 Hz
# Far-from-play LOD radius (see the throttle site): beyond this distance from
# the puck the argmax runs at half rate. Physical grounding: at the ~33 m/s max
# shot speed the play needs ≥ 0.55 s to arrive from 18 m out, an order of
# magnitude above the ≤ 50 ms of latency the halved cadence adds.
const FAR_PLAY_LOD_RADIUS_M: float = 18.0
# Finisher full-rate ring (must_recompute): a loose/in-flight puck inside this
# radius can reach the blade within ~0.36 s at the max shot speed, so only then
# are the one-timer trigger and crash read tick-critical.
const FINISHER_FLIGHT_NEAR_M: float = 12.0
var _role_decision_cooldown: int = 0
# The real tick gap armed by the most recent full dispatch (including the far-play
# LOD), which the role-argmax cooldown drains by so its wall-clock cadence holds.
# One arming goes stale at the far↔near boundary (±2 ticks, once); tolerated.
var _dispatch_armed_span_ticks: int = DISPATCH_PERIOD_TICKS
# Full-dispatch counter, read by the AI benchmarks to verify the dispatch LODs
# thin; no gameplay consumer.
var full_dispatch_count: int = 0


# True for slots whose positioning read tracks something that moves at play
# speed — the carrier, an assigned or soft-locked man, a race, or a live
# one-timer camp. These keep the ~30 Hz argmax cadence; shape-holding posts
# re-eval at half that (~15 Hz).
func _is_reactive_slot(slot: int, snapshot: WorldSnapshot) -> bool:
	# The zone defender who owns pressure this tick does PRESSURE's job.
	if AIRoleSlots.is_reactive(slot) or _owns_zone_pressure(slot, snapshot):
		return true
	match slot:
		AIRoleSlots.Slot.FINISHER, AIRoleSlots.Slot.NET_FRONT:
			# The one-timer camp's fast cadence buys a live seam read, which only
			# exists while the puck is IN the attacking zone; elsewhere the
			# finisher is staging a formation post. The one-timer trigger bypasses
			# the throttle (must_recompute) either way.
			if snapshot != null and snapshot.puck_state != null:
				return AIActionScoring.in_offensive_zone(
						snapshot.puck_state.position,
						Vector3(0.0, 0.0, -_own_goal_dir * GameRules.GOAL_LINE_Z))
			return true
	# A zone defender with a live soft-lock is covering a mover — reactive
	# while the lock holds, a breathing post once it releases.
	return _cached_role_decision != null \
			and _cached_role_decision.locked_man_pid != -1


# Seed the dispatch / role-argmax counters with a per-bot phase. Multiplying by a
# prime before the modulo spreads consecutive bot ids across the role period
# instead of marching them in lockstep pairs. Real bot peers only: unit tests and
# duel scenarios pin tick-exact behavior off an immediate first dispatch.
func _stagger_cadence_phases() -> void:
	if _peer_id < NetworkManager.BOT_ID_BASE:
		return
	_dispatch_skip_counter = _peer_id % maxi(1, _dispatch_period_ticks)
	_role_decision_cooldown = (_peer_id * 3) % ROLE_DECISION_PERIOD_TICKS
var _cached_role_decision: RoleDecision = null
# True when the cached decision was built under a live location ping, whose
# override mutates its target_position in place — so the first tick after the
# ping expires must recompute rather than reuse it.
var _role_decision_pinged: bool = false

# Difficulty PACE knobs (BotSkillProfile via apply_profile), copied onto the
# RoleContext each tick. The defaults are the perfect bot.
var _pursuit_standoff_m: float = 0.0
var _pass_speed_scale: float = 1.0
var _check_aggression: float = 1.0
var _defensive_anticipation_scale: float = 1.0
# Post-possession settle doubt forwarded to the carrier via RoleContext (see
# BotSkillProfile.settle_penalty_frac). 0.0 = commit the tick the compete says so.
var _settle_penalty_frac: float = 0.0
var _settle_penalty_tau_s: float = 0.25
# Difficulty COGNITION gates (BotSkillProfile via apply_profile); true = the
# perfect bot. _reads_goalie_motion gates the goalie velocity projection in
# _shot_aim_point (and rides RoleContext into the carrier's unsettled read);
# _holds_for_developing_feeds rides RoleContext into the carrier's hold;
# _angles_the_chase gates the inside-lane intercept shift in the chase.
var _reads_goalie_motion: bool = true
var _holds_for_developing_feeds: bool = true
# _reads_receiver_commitment rides RoleContext into the carrier's pass EV (a
# turning receiver is a riskier feed).
var _reads_receiver_commitment: bool = true
var _angles_the_chase: bool = true
# _plays_rush_pass_lanes rides RoleContext into RUSH_D1's odd-man lane fan.
var _plays_rush_pass_lanes: bool = true
# _protects_the_puck gates the carry blade's protect blend. False = naive forward
# carry, the puck presented ahead of the body.
var _protects_the_puck: bool = true
# _lifts_sticks gates the jab-or-lift read (AIStickLiftRead). False = jab only.
var _lifts_sticks: bool = true
# _ties_sticks gates both halves of the stick battle: tying a covered man's stick
# and yanking one's own free. False = neither.
var _ties_sticks: bool = true
# _blocks_shots gates the standing block and the 2-on-1 dive (_shot_block).
var _blocks_shots: bool = true
var _shot_block := SkaterAgentShotBlock.new()
var _board_play := SkaterAgentBoardPlay.new()
var _stand_up := SkaterAgentStandUp.new()
var _press := SkaterAgentPress.new()
var _stick_play := SkaterAgentStickPlay.new()
var _steering := SkaterAgentSteering.new()
var _reception := SkaterAgentReception.new()
var _one_timer := SkaterAgentOneTimer.new()
# The FINISHER's raised blade (stick_lift_held, to tip an elevated shot) is set
# only on dispatch ticks, so it is replayed on skipped ticks — otherwise it strobes
# 1-in-dispatch_period and the lift blend never leaves ~0 on the slower tiers.
var _cached_stick_lift_held: bool = false
# Same for the brake (pivot / arrival stops), the stance (pivot cuts) and the
# body-check commit: set only on dispatch ticks, so without the replay a
# lower tier — dispatching every 6–9 ticks — would hold them for one tick in N.
var _cached_brake: bool = false
var _cached_stance_held: bool = false
var _cached_hit_held: bool = false
# Cached by `_step_mouse_internal` so skipped ticks can re-step toward the most
# recently decided target without re-running the state handler.
# _has_cached_aim_target is false until the first full dispatch sets one.
var _cached_aim_target: Vector3 = Vector3.ZERO
var _has_cached_aim_target: bool = false
# The cursor-shaping mode (_STEP_*) that produced the cached target, so the
# skipped-tick re-step re-shapes the same way every physics frame.
var _cached_aim_mode: int = _STEP_DIRECT
# The linear + angular cursor rates that produced the cached target (a FACE aim
# and a blade aim step at different rates).
var _cached_aim_max_speed: float = MOUSE_MAX_SPEED_M_S
var _cached_aim_arc_rate: float = MOUSE_ARC_RATE_RAD_S

# Off-puck ready-stance aim, re-derived live on the throttle's skipped ticks
# (_off_puck_live_aim): the DECISION stays throttled, but the blade target is a
# pure function of current perception, so it tracks the puck smoothly instead of
# staircasing at the dispatch rate. `_off_puck_aim_live` is true only when the
# dispatch tick resolved to the plain ready-stance branch; anchor + near
# threshold are captured so the re-derive matches that call exactly.
var _off_puck_aim_live: bool = false
var _off_puck_aim_anchor: Vector3 = Vector3.ZERO
var _off_puck_aim_near_m: float = 0.0
# Set when the dispatch tick resolved to an ACTIVE poke-jab: skipped ticks re-track
# the moving puck live, since check_poke is a swept segment test a staircased stab
# can skip. The jab's counters still advance on the dispatch cadence.
var _off_puck_jab_live: bool = false
# Same live re-aim for a held tie (the man's shaft) and for a tied attacker's
# yank (away from the stick holding his).
var _off_puck_tie_live: bool = false
var _off_puck_yank_live: bool = false
# Latched side of the far/near aim flip (_compute_desired_aim_dir): true = NEAR
# (aiming the threat), false = FAR (aiming the anchor).
var _aim_near_anchor: bool = false
# Latched puck-too-close state for _face_threat_or_current: true = hold facing.
var _threat_too_close: bool = false

# Captured at the top of each dispatch() so _step_mouse_internal can shape the
# cursor around the body without threading self_pos / self_state through every
# call site. null until the first dispatch.
var _current_self_pos: Vector3 = Vector3.ZERO
var _current_self_state: SkaterNetworkState = null
var _current_snapshot: WorldSnapshot = null
# The real frame delta captured at the top of each dispatch (including skipped
# ticks), so per-tick smoothing (the carry protect blend) holds under host time
# dilation.
var _current_delta: float = 0.0

# Last action the bot actually fired (debug label), set when the press is
# dispatched rather than when intent is picked.
var debug_last_decision: String = ""

# Gate for the costly debug-readout strings (strategy lookup + `%` formatting on
# the hot path); bare-literal labels stay ungated. AIController.SHOW_DEBUG_LABEL
# derives from this — flip it here to turn the labels on.
const DEBUG_DECISIONS: bool = false


# Debug-label scoring readout, from the carrier's most recent re-eval.
var debug_shoot_score: float = 0.0
var debug_pass_score: float = 0.0
var debug_pass_peer_id: int = 0
var debug_carry_score: float = 0.0
var debug_carry_pos: Vector3 = Vector3.ZERO


# ── Setup ────────────────────────────────────────────────────────────────────

# Apply this bot's attribute-scaled self-capabilities (AIController.apply_attributes
# via SkaterAgent, on spawn and every free-play picker change), so its model of
# its own reach / speed / shot matches its body. Null keeps the league baseline.
func apply_capabilities(caps: AISkaterCaps) -> void:
	if caps == null:
		return
	_self_max_speed = caps.max_speed
	_chase_max_accel = caps.max_accel
	_blade_reach = caps.blade_span + AIBotMechanics.BLADE_REACH_BUFFER_M
	_receive_body_offset = caps.blade_span - SkaterAgentReception.RECEIVE_BODY_INSET_M
	_poke_jab_reach = caps.blade_span + GameRules.POKE_RADIUS_M
	_stick_lift_reach = caps.blade_span + GameRules.STICK_LIFT_RADIUS_M
	_self_wrister_shot_speed = caps.wrister_shot_speed
	_self_lateral_grip = caps.lateral_grip
	_self_weight = caps.weight
	_self_body_check_transfer = caps.body_check_transfer
	_self_handle_reach = caps.handle_reach
	_self_reach_cone_half_angle = caps.reach_cone_half_angle
	_self_facing_turn_rate = caps.facing_turn_rate
	_self_blade_speed = caps.blade_speed
	_self_backhand_coefficient = caps.backhand_power_coefficient
	_one_timer.set_caps(caps)
	_role_ctx.self_wrister_unloaded_share = caps.wrister_unloaded_share
	_role_ctx.self_wrister_load = caps.wrister_load
	_role_ctx.self_facing_rules = caps.facing_rules
	_role_ctx.self_carry_facing_rules = caps.carry_facing_rules
	# The cursor slews at the bot's real blade speed: "aimed" means the blade is there.
	_apply_aim_slew(caps.blade_speed, caps.blade_span)


# This bot's power fraction (0..1) for a charged pass whose blade push is `push`
# (m/s), over its own wrister band [floor_push, _self_wrister_shot_speed]: the
# controller holds the standing floor at the league baseline for every build,
# and cushions it to a pace on the ice by the body's motion
# (ReleaseMomentum.floor_push). `hand_coefficient` is the share the release's
# hand fires at (the backhand coefficient on a backhand), so the commit asks for
# the push over it.
func _pass_power_t(push: float, floor_push: float, hand_coefficient: float = 1.0) -> float:
	return clampf(
			(push / maxf(hand_coefficient, 0.05) - floor_push)
			/ maxf(_self_wrister_shot_speed - floor_push, 0.001),
			0.0, 1.0)


func setup(peer_id: int, team_id: int, brain: TeamBrain, team_id_by_peer: Dictionary,
		is_left_handed: bool, caps_by_peer: Dictionary = {}) -> void:
	if brain == null:
		push_error("SkaterAgentStateMachine.setup: null TeamBrain for peer_id=%d team_id=%d — bot was spawned before GameManager.team_brains was populated. Bot will run without role assignments." % [peer_id, team_id])
	_peer_id = peer_id
	_team_id = team_id
	_own_goal_dir = 1.0 if team_id == 0 else -1.0
	# The opposing goal mouth: fallback aim and the net plane for shot-aim geometry.
	_attacking_goal_pos = Vector3(0.0, 0.0, -_own_goal_dir * GameRules.GOAL_LINE_Z)
	_team_brain = brain
	_team_id_by_peer = team_id_by_peer
	_caps_by_peer = caps_by_peer
	_shot_block.setup(peer_id, team_id, team_id_by_peer, caps_by_peer)
	_board_play.setup(peer_id, team_id, team_id_by_peer, caps_by_peer)
	_stand_up.setup(peer_id, team_id, team_id_by_peer, caps_by_peer)
	_press.setup(peer_id, team_id, team_id_by_peer, caps_by_peer)
	_stick_play.setup(peer_id, team_id, team_id_by_peer)
	_steering.setup(peer_id, team_id, team_id_by_peer)
	_reception.setup(peer_id, team_id, team_id_by_peer, caps_by_peer, is_left_handed)
	_one_timer.setup(peer_id, team_id, team_id_by_peer, is_left_handed)
	_is_left_handed = is_left_handed
	# Stagger this bot's dispatch and role-argmax phases by peer id, so a full
	# roster doesn't run every expensive re-eval on the SAME physics tick (host
	# FPS is set by the worst tick).
	_stagger_cadence_phases()
	# Must match the forehand convention of the release classifier
	# (skater_controller.gd: RH forehand = skater-local +X) and
	# SkaterAgentReception.read_shot (RH forehand = -left_dir): a right-hander's wind-up perp is
	# Vector3(-aim.z, 0, aim.x), i.e. -1. Inverted, every bot winds up on the
	# backhand and silently pays the backhand power penalty.
	_handedness_perp_sign = 1.0 if _is_left_handed else -1.0
	# peer_id × prime spreads the bot id range across the seed space; host_tick at
	# spawn salts it per session.
	_rng.seed = (peer_id * 1000003) ^ NetworkManager.host_tick


# Apply a difficulty skill profile, once at spawn via SkaterAgent.apply_profile,
# before the first dispatch. Null keeps the perfect-bot defaults.
func apply_profile(profile: BotSkillProfile) -> void:
	if profile == null:
		return
	# Aim slew is not a difficulty knob (apply_capabilities sets it).
	_dispatch_period_ticks = maxi(1, profile.dispatch_period_ticks)
	_dispatch_armed_span_ticks = _dispatch_period_ticks
	# Cadence changed — re-derive this bot's pacing phase for the new period.
	_stagger_cadence_phases()
	_pursuit_standoff_m = profile.pursuit_standoff_m
	_pass_speed_scale = profile.pass_speed_scale
	_check_aggression = profile.check_aggression
	_defensive_anticipation_scale = profile.defensive_anticipation_scale
	_settle_penalty_frac = profile.settle_penalty_frac
	_settle_penalty_tau_s = profile.settle_penalty_tau_s
	# Same lever the global carrier debounce uses, applied HERE for the chase
	# gate so puck reactivity has its own bounded clock (see _loose_elapsed_s).
	_chase_reaction_delay_s = maxf(profile.carrier_reaction_delay_s, 0.0)
	_reads_goalie_motion = profile.reads_goalie_motion
	_holds_for_developing_feeds = profile.holds_for_developing_feeds
	_reads_receiver_commitment = profile.reads_receiver_commitment
	_angles_the_chase = profile.angles_the_chase
	_plays_rush_pass_lanes = profile.plays_rush_pass_lanes
	_protects_the_puck = profile.protects_the_puck
	_lifts_sticks = profile.lifts_sticks
	_ties_sticks = profile.ties_sticks
	_blocks_shots = profile.blocks_shots
	# The shot error is the tier's scoring dial; the pass error stays small so
	# passes keep connecting.
	_shot_aim_error_rad = profile.shot_aim_error_rad
	_pass_aim_error_rad = profile.pass_aim_error_rad
	_shot_timing_error_s = profile.shot_timing_error_s


# Set the aim-cursor slew (and the arc rate + pre-aim timeout derived from it) to
# `slew` m/s — the bot's real blade speed, so the cursor tracks the blade.
# `orbit_radius_m` is the blade's real orbit radius (stick + blade span): the
# angular swing the linear blade-speed cap physically allows is slew / THAT radius, not
# slew / the virtual cursor ring. Defaults to the ring radius; every live caller
# passes the real span.
func _apply_aim_slew(slew: float,
		orbit_radius_m: float = AIBotMechanics.CARRY_BLADE_AIM_FORWARD_M) -> void:
	_mouse_max_speed_m_s = slew
	# Arc rate: lesser of the IK-gate ceiling and the linear slew cap projected
	# onto the blade's orbit radius — above either, the arc-step chord-cuts the
	# back-pass swing or the body-facing lag trips the pose IK gate.
	_mouse_arc_rate_rad_s = minf(MOUSE_ARC_RATE_RAD_S,
			_mouse_max_speed_m_s / maxf(orbit_radius_m, 0.1))
	# Pre-aim convergence timeout: time for a worst-case 180° swing at the
	# (possibly reduced) arc rate, plus a fixed margin — never below the perfect-bot
	# default. Keeps a slow blade from bailing pre-aim early on a
	# back-pass and firing in the wrong direction.
	var swing_ticks: int = int(ceil((PI / _mouse_arc_rate_rad_s) / MOUSE_TICK_DELTA))
	_intent_max_wait_ticks = maxi(INTENT_MAX_WAIT_TICKS, swing_ticks + 60)


# ── State accessors ──────────────────────────────────────────────────────────

func get_state() -> State:
	return _state


# Debug label: "TEAM_STATE: Slot", or "?" with no brain.
func debug_role() -> String:
	if _team_brain == null:
		return "?"
	return "%s: %s" % [_team_state_label(_team_brain.state), AIRoleSlots.label(_team_brain.get_slot(_peer_id))]


# Debug label: the option that scored highest on the carrier's latest re-eval,
# regardless of commit.
func debug_winner() -> String:
	# The wrister is the only shot type.
	var best_shot_score: float = debug_shoot_score
	var fire_score: float = best_shot_score if best_shot_score >= debug_pass_score else debug_pass_score
	var fire_label: String = "SHOOT" if best_shot_score >= debug_pass_score else "PASS"
	if fire_score == 0.0 and debug_carry_score == 0.0:
		return "—"
	if fire_score >= debug_carry_score:
		return fire_label
	return "CARRY"


# Debug label: the committed intent.
func debug_intent() -> String:
	match _intended_action:
		State.SHOOT_PRESSED: return "SHOOT"
		State.PASS_PRESSED: return "PASS"
		_: return "CARRY"


# Debug label: the best pass's receiver slot.
func debug_pass_slot() -> String:
	if debug_pass_peer_id == 0 or _team_brain == null:
		return "—"
	return AIRoleSlots.label(_team_brain.get_slot(debug_pass_peer_id))


# Debug label: compass direction of the best carry destination, forward = toward
# the attacking goal.
func debug_carry_dir(self_pos: Vector3) -> String:
	if debug_carry_pos == Vector3.ZERO:
		return "—"
	var dx: float = debug_carry_pos.x - self_pos.x
	var dz: float = debug_carry_pos.z - self_pos.z
	if dx * dx + dz * dz < 0.25:  # within 0.5 m → stand-still
		return "stand"
	var fwd_z_sign: float = -_own_goal_dir
	var dz_signed: float = dz * fwd_z_sign  # positive = forward
	var ax: float = absf(dx)
	var az: float = absf(dz_signed)
	var lon: String = ("fwd" if dz_signed > 0.0 else "back") if az > 0.5 else ""
	var lat: String = ("L" if dx < 0.0 else "R") if ax > 0.5 else ""
	if lon != "" and lat != "":
		return "%s-%s" % [lon, lat]
	if lon != "":
		return lon
	if lat != "":
		return lat
	return "stand"


func _team_state_label(state: int) -> String:
	match state:
		AIPossessionState.State.DZONE:
			return "DZ"
		AIPossessionState.State.OZONE:
			return "OZ"
		AIPossessionState.State.TRANS_OFFENSE:
			return "TransOff"
		AIPossessionState.State.TRANS_DEFENSE:
			return "TransDef"
		AIPossessionState.State.NEUTRAL:
			return "Neutral"
		AIPossessionState.State.BREAKOUT:
			return "Breakout"
		AIPossessionState.State.FORECHECK:
			return "Forecheck"
		_:
			return "?"


# ── Dispatch ─────────────────────────────────────────────────────────────────

# Caller (SkaterAgent) is responsible for zeroing `input` before this call.
# We fill move_vector / mouse_world_pos / shoot flags based on _state.
func dispatch(input: InputState, snapshot: WorldSnapshot) -> void:
	if snapshot == null or snapshot.puck_state == null or snapshot.skater_states.is_empty():
		_reset_to_off_puck()
		return
	var self_state: SkaterNetworkState = snapshot.skater_states.get(_peer_id)
	if self_state == null:
		# Snapshot pre-dates this bot's spawn; freeze for one tick.
		_reset_to_off_puck()
		return

	var self_pos: Vector3 = self_state.position
	# For _step_mouse_internal's cursor shaping, refreshed on skipped ticks too so
	# an arc keeps walking between full re-evals. The snapshot feeds the arc
	# step's protect-side turn read.
	_current_self_pos = self_pos
	_current_self_state = self_state
	_current_snapshot = snapshot
	_current_delta = input.delta
	# EVERY dispatch-path brain read must go through this, so dispatch can run
	# off-thread.
	_current_strategy = _strategy()
	# Self-possession is instant (proprioception): read the REAL carrier, or the
	# bot freezes holding the puck for the reaction window. Everything else reads
	# the delayed puck_state.carrier_peer_id, so the bot reacts to OTHERS'
	# possession changes a beat late.
	var have_puck: bool = (snapshot.real_puck_carrier_peer_id == _peer_id)
	_update_loose_reaction_clock(snapshot, input.delta)
	_update_engagement_cooldown(snapshot, self_state)
	# Resolved on skipped ticks too: press states read it.
	if not snapshot.accel_by_peer.is_empty():
		_accel_ref = snapshot.accel_by_peer
		_omega_ref = snapshot.heading_omega_by_peer
	else:
		_update_acceleration_cache(snapshot, input.delta)
		_accel_ref = _accel_by_peer
		_omega_ref = _heading_omega_by_peer

	# When we can't legally play the puck (ghosted, or must tag up under NHL
	# delayed offside), chase behavior is degenerate. Drop to OFF_PUCK so the
	# tag-up override in _state_off_puck routes us back to the blue line.
	if snapshot.is_out_of_play(_peer_id) and _state == State.CHASE_PUCK:
		_set_state(State.OFF_PUCK)

	# Decision throttle (see DISPATCH_PERIOD_TICKS). `_set_state` zeroes
	# `_dispatch_skip_counter`, so a fresh state dispatches full on its first tick.
	var is_press_state: bool = (_state == State.SHOOT_PRESSED
			or _state == State.PASS_PRESSED
			or _state == State.ONE_TIMER_PRESSED)
	if not is_press_state and _dispatch_skip_counter > 0:
		_dispatch_skip_counter -= 1
		input.move_vector = _cached_move_vector
		input.stick_lift_held = _cached_stick_lift_held
		input.brake = _cached_brake
		input.stance_held = _cached_stance_held
		input.hit_held = _cached_hit_held
		# Aim runs at the physics rate even though the DECISION is throttled:
		# while chasing, the reception blade target re-derives from current
		# perception, so a catchable feed can't transit a blade that only re-aims
		# on dispatch ticks.
		if _state == State.CHASE_PUCK:
			var live_recv_aim: Vector3 = _chase_reception_aim_target(snapshot, self_pos)
			if live_recv_aim.is_finite():
				input.mouse_world_pos = _step_mouse_toward(live_recv_aim)
				return
		elif _state == State.OFF_PUCK:
			# Off-puck blade target from CURRENT perception (_off_puck_live_aim),
			# through the same _step_mouse_face path as the dispatch tick.
			var live_off_aim: Vector3 = _off_puck_live_aim(snapshot, self_pos)
			if live_off_aim.is_finite():
				input.mouse_world_pos = _step_mouse_face(live_off_aim)
				return
		elif _state == State.CARRY and _intended_action == State.CARRY:
			# Carry blade target re-derived live. Not during a pre-aim, whose
			# convergence gate must not advance off-dispatch.
			_step_carry_cursor(input, snapshot, self_pos, self_state)
			return
		if _has_cached_aim_target:
			input.mouse_world_pos = _step_mouse_internal(
					_cached_aim_target, _cached_aim_mode,
					_cached_aim_max_speed, _cached_aim_arc_rate)
		return
	# FAR-FROM-PLAY DISPATCH LOD: an OFF_PUCK bot beyond FAR_PLAY_LOD_RADIUS_M of
	# the puck dispatches at HALF rate — the shell-level twin of the role-argmax far
	# LOD, with the same grounding. Skipped ticks still re-derive blade aim and
	# re-step the cached move vector. FINISHER_FLIGHT_NEAR_M sits inside the LOD
	# radius, so a bot arming a one-timer is never on the halved shell.
	var dispatch_span: int = _dispatch_period_ticks
	if _state == State.OFF_PUCK and snapshot.puck_state != null \
			and self_pos.distance_squared_to(snapshot.puck_state.position) \
			> FAR_PLAY_LOD_RADIUS_M * FAR_PLAY_LOD_RADIUS_M:
		dispatch_span = _dispatch_period_ticks * 2
		# Anti-lockstep: a possession flip zeroes many bots' counters at once, and
		# slightly unequal periods drift their phases apart again (host FPS is the
		# worst tick).
		dispatch_span += _peer_id % 2
	_dispatch_armed_span_ticks = dispatch_span
	_dispatch_skip_counter = dispatch_span - 1
	full_dispatch_count += 1

	match _state:
		State.OFF_PUCK:
			_state_off_puck(input, snapshot, self_pos, have_puck)
		State.CHASE_PUCK:
			_state_chase_puck(input, snapshot, self_pos, have_puck)
		State.CARRY:
			_state_carry(input, snapshot, self_pos, have_puck)
		State.SHOOT_PRESSED:
			_state_shoot_pressed(input, snapshot, self_pos, have_puck)
		State.PASS_PRESSED:
			_state_pass_pressed(input, snapshot, self_pos, have_puck)
		State.ONE_TIMER_PRESSED:
			_state_one_timer_pressed(input, snapshot, self_pos, have_puck)

	_cached_move_vector = input.move_vector
	_cached_stick_lift_held = input.stick_lift_held
	_cached_brake = input.brake
	_cached_stance_held = input.stance_held
	_cached_hit_held = input.hit_held


# ── State handlers ───────────────────────────────────────────────────────────

func _state_off_puck(input: InputState, snapshot: WorldSnapshot, self_pos: Vector3, have_puck: bool) -> void:
	var self_state: SkaterNetworkState = snapshot.skater_states.get(_peer_id)

	# Default: no live aim refresh on skipped ticks. The branches below re-arm
	# the one they hit — plain ready-stance (_off_puck_aim_live) or an active
	# poke-jab (_off_puck_jab_live). One-timer pre-aim / explicit aim override
	# leave both off so they keep the throttled cached-target path.
	_off_puck_aim_live = false
	_off_puck_jab_live = false
	_off_puck_tie_live = false
	_off_puck_yank_live = false

	# Tag-up override: when ghosted or owing an NHL tag-up, bot must clear
	# back across the blue line before doing anything else. Highest-priority
	# override above all slot logic — bypasses role dispatch entirely.
	if self_state != null and snapshot.is_out_of_play(_peer_id):
		var tag_up: Vector3 = _tag_up_anchor(self_pos)
		# Velocity-matched seek: redirect cross-drift onto the line back to the
		# tag-up point rather than orbiting it (same as the role stations).
		_apply_steering(input, snapshot, self_pos, tag_up, false, _self_max_speed)
		_arm_off_puck_live_aim(tag_up, FACE_TRAVEL_TAG_UP_NEAR_M)
		input.mouse_world_pos = _step_mouse_face(_ready_stance_aim(
				self_pos, tag_up, snapshot, FACE_TRAVEL_TAG_UP_NEAR_M))
		_set_one_timer_ready(false)
	else:
		var ctx: RoleContext = _build_role_context(snapshot, self_pos, self_state)
		# Role-argmax throttle (ROLE_DECISION_PERIOD_TICKS). Bypassed for
		# timing-critical reads: a finisher-type slot with a loose / in-flight puck
		# near, a live one-timer-ready or body-check commit in the cache, a location
		# ping (its override mutates the decision each tick), and a slot change. ctx
		# is rebuilt every tick regardless.
		var slot: int = _current_strategy.get_slot(_peer_id) if _current_strategy != null \
				else AIRoleSlots.Slot.NONE
		var is_finisher_slot: bool = slot == AIRoleSlots.Slot.FINISHER \
				or slot == AIRoleSlots.Slot.NET_FRONT
		# Finisher reads are only trigger-critical inside FINISHER_FLIGHT_NEAR_M: a
		# flight outside it cannot arrive faster than it crosses the ring, so the
		# throttled cadence loses nothing there. The ready-armed bypass rides the
		# same ring: arming is positional, and its consumers run at the ~30 Hz
		# argmax anyway.
		var finisher_puck_near: bool = is_finisher_slot \
				and snapshot.puck_state != null \
				and snapshot.puck_state.carrier_peer_id == -1 \
				and snapshot.puck_state.position.distance_squared_to(self_pos) \
						<= FINISHER_FLIGHT_NEAR_M * FINISHER_FLIGHT_NEAR_M
		var must_recompute: bool = _cached_role_decision == null \
				or slot != _prev_role_slot \
				or finisher_puck_near \
				or ctx.ping_move_target.is_finite() \
				or _role_decision_pinged \
				or (_cached_role_decision.is_one_timer_ready \
						and (finisher_puck_near or not is_finisher_slot)) \
				or _cached_role_decision.commit_check
		var decision: RoleDecision
		if must_recompute or _role_decision_cooldown <= 0:
			decision = _dispatch_role_decision(ctx)
			_cached_role_decision = decision
			# Reactive roles re-eval at ~30 Hz; shape-holding roles at ~15 Hz —
			# slow-moving formation posts behind multi-second hysteresis.
			#
			# Per-peer period skew (+0..2 ticks): a possession flip zeroes many
			# bots' cooldowns at once, and unequal periods drift them out of
			# lockstep again (host FPS is the worst tick).
			var period: int = ROLE_DECISION_PERIOD_TICKS \
					if _is_reactive_slot(slot, snapshot) \
					else ROLE_DECISION_PERIOD_TICKS * 2
			# FAR-FROM-PLAY LOD: half rate beyond FAR_PLAY_LOD_RADIUS_M.
			if snapshot.puck_state != null \
					and ctx.self_pos.distance_squared_to(
							snapshot.puck_state.position) \
					> FAR_PLAY_LOD_RADIUS_M * FAR_PLAY_LOD_RADIUS_M:
				period *= 2
			_role_decision_cooldown = (_peer_id % 3) + period
			_role_decision_pinged = ctx.ping_move_target.is_finite()
		else:
			# Drain by the REAL dispatch span, or the far-play dispatch LOD would
			# stretch the argmax cadence a second time.
			_role_decision_cooldown -= _dispatch_armed_span_ticks
			decision = _cached_role_decision
		# Smart-ping GO_THERE override: a live location order from a human
		# teammate replaces the role's move target for its duration. The role
		# keeps supplying aim / lift / one-timer readiness — only the skating
		# destination is commandeered (and a check commit is stood down; the
		# order says go THERE, not through someone).
		if ctx.ping_move_target.is_finite():
			decision.target_position = _clamp_anchor(ctx.ping_move_target)
			decision.target_velocity = Vector3.ZERO  # an ordered SPOT, not a man
			decision.commit_check = false
		# Arrival brake at the role destination, except on a body-check commit
		# (maximum closing velocity) or a role pacing a MOVING waypoint at speed
		# (OUTLET timing its rush entry). A stand that rides a man is flown in its
		# own frame (RoleDecision.target_velocity).
		_apply_steering(input, snapshot, self_pos, decision.target_position,
				not decision.commit_check and not decision.arrive_at_speed,
				_self_max_speed, decision.target_velocity,
				decision.engaged_peer_id, decision.retreat_floor_center,
				decision.retreat_floor_radius_m, decision.advance_cap_m_s)
		if decision.commit_check:
			# Hit held delivers the FULL transfer AIBodyCheck's predicted_impulse
			# assumed (an uncommitted drive lands only the passive fraction).
			input.hit_held = true
		# FINISHER raises its blade to tip an incoming ELEVATED on-net shot. HIGH
		# is the deflect mode and puts the lifted blade on the high-air plane.
		input.stick_lift_held = decision.lift_blade
		if decision.lift_blade:
			input.elevation_level = ShotMechanics.ELEVATION_HIGH
		# Preserve one-timer readiness through pass flights: with no carrier,
		# FINISHER can't score the feed and reports "not ready", though the stance
		# hasn't moved — dropping the flag there would stop the trigger firing when
		# the puck arrives.
		var would_be_ready: bool = decision.is_one_timer_ready
		if would_be_ready:
			# Genuinely (re-)confirmed ready — reset the preserve budget.
			_one_timer_preserve_ticks = 0
		elif _is_one_timer_ready \
				and _in_attacking_zone(self_pos) \
				and (slot == AIRoleSlots.Slot.FINISHER
						or slot == AIRoleSlots.Slot.NET_FRONT) \
				and snapshot.puck_state != null \
				and (snapshot.puck_state.carrier_peer_id == -1
						or snapshot.real_puck_carrier_peer_id == -1) \
				and _one_timer_preserve_ticks < ONE_TIMER_PRESERVE_MAX_TICKS:
			# Bounded by ONE_TIMER_PRESERVE_MAX_TICKS. The REAL carrier check
			# matters: for carrier_reaction_delay_s after the release the debounced
			# carrier still reads as holding the puck. The zone + slot gate bridges
			# only OUR feed: an opponent gaining the puck flips the slot off
			# FINISHER, so readiness can't leak into a defensive-zone one-timer.
			_one_timer_preserve_ticks += _dispatch_period_ticks
			would_be_ready = true
		_set_one_timer_ready(would_be_ready)
		# Defensive poke jab, only with no one-timer live so its lifecycle doesn't
		# tick during offensive states. INF (no jab) falls through to the normal aim.
		var jab_aim: Vector3 = Vector3.INF
		if not would_be_ready:
			jab_aim = _poke_jab_aim(snapshot, self_pos)
		# The stick battle: a tied attacker pulls his stick free before anything
		# else it could be doing, and a defender with no jab ties his man.
		var yank_aim: Vector3 = _tie_yank_aim(snapshot, self_pos, self_state)
		var tie_aim: Vector3 = Vector3.INF
		if not jab_aim.is_finite():
			tie_aim = _stick_tie_aim(snapshot, self_pos, self_state, decision)
		else:
			_stick_play.drop_tie()
		if yank_aim.is_finite():
			_off_puck_yank_live = true
			input.mouse_world_pos = _step_mouse_face(yank_aim)
		elif jab_aim.is_finite():
			_off_puck_jab_live = true
			input.mouse_world_pos = _step_mouse_face(jab_aim)
		elif tie_aim.is_finite():
			_off_puck_tie_live = true
			input.mouse_world_pos = _step_mouse_face(tie_aim)
		elif would_be_ready:
			input.mouse_world_pos = _step_mouse_face(_shot_aim_point(snapshot, self_pos, 0.0))
		elif decision.has_aim_override:
			input.mouse_world_pos = _step_mouse_face(decision.aim_world_pos)
		elif decision.face_travel and input.move_vector.length_squared() > 0.01:
			# The cursor down the route: past the backward line's reach edge, so
			# FacingRules pivots the hips onto the forward one.
			var travel := Vector3(input.move_vector.x, 0.0, input.move_vector.y).normalized()
			input.mouse_world_pos = _step_mouse_face(self_pos + travel * READY_STANCE_AIM_FORWARD_M)
		else:
			_arm_off_puck_live_aim(decision.target_position, FACE_THREAT_NEAR_ANCHOR_M)
			input.mouse_world_pos = _step_mouse_face(_ready_stance_aim(self_pos, decision.target_position, snapshot))

	# Transitions
	if have_puck:
		_set_state(State.CARRY)
	elif _is_one_timer_ready and _in_attacking_zone(self_pos) \
			and (_one_timer.line_anchor(snapshot, self_pos, _attacking_goal_pos).is_finite()
			or _puck_in_one_timer_zone(snapshot, self_pos)):
		# Commit at feed RELEASE, not contact: the slap wind-up needs the flight
		# time to build, and the live-line settle needs it to walk the slapper zone
		# onto the pass's path. The zone-entry check is the fallback for feeds too
		# soft/close to read as a live line.
		_set_state(State.ONE_TIMER_PRESSED)
	elif _is_one_timer_ready and not _loose_puck_in_reach_band(snapshot, self_pos):
		# Stay camped + pre-aimed even if the brain says we're closest to a loose
		# puck: chasing would lose the goal-aim lock. The exception is a puck
		# coming into the camper's own reach band — he takes it.
		pass
	elif _should_chase_loose_puck(snapshot, self_pos) \
			or _reception.incoming_pass(snapshot, self_pos):
		# Chase either the loose puck we're closest to, OR a pass released our way —
		# the latter gets us into the squared reception setup before the fast puck
		# arrives, rather than reacting only once it's on top of us.
		_set_state(State.CHASE_PUCK)


# Fills the reused RoleContext (_role_ctx — never a fresh allocation, this runs per
# dispatch per bot) with the read-only inputs every role-behavior decide() needs.
func _build_role_context(snapshot: WorldSnapshot, self_pos: Vector3,
		self_state: SkaterNetworkState) -> RoleContext:
	var ctx := _role_ctx
	ctx.snapshot = snapshot
	ctx.self_pos = self_pos
	ctx.self_velocity = self_state.velocity if self_state != null else Vector3.ZERO
	ctx.team_id = _team_id
	ctx.peer_id = _peer_id
	ctx.attacking_goal_pos = _attacking_goal_pos
	ctx.defending_goal_pos = Vector3(0.0, 0.0, _own_goal_dir * GameRules.GOAL_LINE_Z)
	ctx.own_goal_dir = _own_goal_dir
	ctx.team_brain = _current_strategy
	ctx.team_id_by_peer = _team_id_by_peer
	ctx.acceleration_by_peer = _accel_ref
	ctx.heading_omega_by_peer = _omega_ref
	ctx.caps_by_peer = _caps_by_peer
	# This bot's own attribute-scaled speeds, so the carrier scores ITS shots /
	# passes / carry ETAs with real numbers (cross-player evals stay default).
	ctx.self_max_speed = _self_max_speed
	ctx.self_max_accel = _chase_max_accel
	ctx.self_wrister_shot_speed = _self_wrister_shot_speed
	ctx.self_lateral_grip = _self_lateral_grip
	ctx.self_pass_aim_error_rad = _pass_aim_error_rad
	ctx.self_weight = _self_weight
	ctx.self_body_check_transfer = _self_body_check_transfer
	ctx.self_handle_reach = _self_handle_reach
	ctx.self_blade_reach = _blade_reach
	ctx.self_reach_cone_half_angle = _self_reach_cone_half_angle
	ctx.self_facing_turn_rate = _self_facing_turn_rate
	ctx.self_blade_speed = _self_blade_speed
	ctx.self_arc_rate = _mouse_arc_rate_rad_s
	ctx.self_backhand_power_coefficient = _self_backhand_coefficient
	ctx.self_forehand_perp_sign = _handedness_perp_sign
	_holds.configure_from(ctx)
	ctx.self_stagger_timer = self_state.stagger_timer if self_state != null else 0.0
	ctx.self_settle_s = self_state.settle_left_s if self_state != null else 0.0
	ctx.pursuit_standoff_m = _pursuit_standoff_m
	ctx.pass_speed_scale = _pass_speed_scale
	ctx.check_aggression = _check_aggression
	ctx.defensive_anticipation_scale = _defensive_anticipation_scale
	ctx.settle_penalty_frac = _settle_penalty_frac
	ctx.settle_penalty_tau_s = _settle_penalty_tau_s
	ctx.reads_goalie_motion = _reads_goalie_motion
	ctx.holds_for_developing_feeds = _holds_for_developing_feeds
	ctx.reads_receiver_commitment = _reads_receiver_commitment
	ctx.plays_rush_pass_lanes = _plays_rush_pass_lanes
	ctx.protects_the_puck = _protects_the_puck
	# The carrier runs its cooldown / hold-decay clock in real time, but decide()
	# is only called on dispatch ticks — hand it the span so it can compensate.
	ctx.dispatch_period_ticks = _dispatch_period_ticks
	# Every ctx field below is re-stamped every build: the instance is reused, and
	# a stale field would carry another match's, brain's or tick's value.
	ctx.zone_entry_blocked = _teammate_must_tag_up(snapshot)
	if _current_strategy != null:
		ctx.strong_x = _current_strategy.strong_x()
		ctx.assigned_threat_peer = _current_strategy.assigned_threat(_peer_id)
		ctx.threat_shoot_base_by_opp = _current_strategy.get_threat_shoot_base_by_opp()
		ctx.rush_read = _current_strategy.get_rush_read()
		ctx.team_size = _current_strategy.get_team_size()
		var lobby_slot: int = _current_strategy.position_of(_peer_id)
		ctx.self_is_defense = PlayerRules.is_defense_slot(lobby_slot)
		ctx.self_home_side = PlayerRules.home_side_x(lobby_slot, _own_goal_dir)
		# Live smart-ping directives on this bot (AIPingDirectives).
		ctx.ping_move_target = _current_strategy.ping_move_target(_peer_id)
		ctx.ping_shoot_active = _current_strategy.ping_shoot(_peer_id)
		ctx.ping_pass_target_peer = _current_strategy.ping_pass_target(_peer_id)
	else:
		# RoleContext.new()'s defaults, for no brain (tests).
		ctx.strong_x = 1.0
		ctx.assigned_threat_peer = -1
		ctx.threat_shoot_base_by_opp = _empty_threat_memo
		ctx.rush_read = _inert_rush_read
		ctx.ping_move_target = Vector3.INF
		ctx.ping_shoot_active = false
		ctx.ping_pass_target_peer = -1
		ctx.team_size = GameRules.DEFAULT_TEAM_SIZE
		ctx.self_is_defense = false
		ctx.self_home_side = 0.0
	return ctx


# Routes the bot's current slot to its role-behavior module. The CARRIER role is
# dispatched by _state_carry instead (see Scripts/ai/CLAUDE.md).
func _dispatch_role_decision(ctx: RoleContext) -> RoleDecision:
	var slot: int = _current_strategy.get_slot(_peer_id) if _current_strategy != null else AIRoleSlots.Slot.NONE
	# Target switch-hysteresis input: the target this bot's role chose last
	# dispatch — INF across a slot change so no role inherits another's
	# target (see RoleContext.prev_role_target).
	ctx.prev_role_target = _prev_role_target if slot == _prev_role_slot else Vector3.INF
	# Pinch-read hysteresis incumbent, same reset-across-slot-change contract.
	ctx.prev_held_forward_stand = _prev_held_forward_stand \
			if slot == _prev_role_slot else false
	var decision: RoleDecision
	match slot:
		AIRoleSlots.Slot.FINISHER:
			decision = AIRoleFinisher.decide(ctx)
		AIRoleSlots.Slot.SUPPORT:
			decision = AIRoleSupport.decide(ctx)
		AIRoleSlots.Slot.OUTLET:
			decision = AIRoleOutlet.decide(ctx)
		AIRoleSlots.Slot.BREAKOUT_STRONG:
			decision = AIRoleBreakout.decide(ctx, true)
		AIRoleSlots.Slot.BREAKOUT_WEAK:
			decision = AIRoleBreakout.decide(ctx, false)
		AIRoleSlots.Slot.F1_PRESSURE:
			# F1 reuses PRESSURE — goal-side cutoff of the carrier, already
			# loose-puck-safe; follows the puck out and accepts the tag-up
			# risk if the opp breaks out.
			decision = AIRolePressure.decide(ctx)
		AIRoleSlots.Slot.F2_MID:
			decision = AIRoleForecheck.decide(ctx, false)
		AIRoleSlots.Slot.F3_HIGH:
			decision = AIRoleForecheck.decide(ctx, true)
		AIRoleSlots.Slot.PRESSURE:
			decision = AIRolePressure.decide(ctx)
		AIRoleSlots.Slot.MARK:
			decision = AIRoleMark.decide(ctx)
		AIRoleSlots.Slot.RUSH_D1, AIRoleSlots.Slot.RUSH_D2:
			decision = AIRoleRushD.decide(ctx, slot)
		AIRoleSlots.Slot.TRACK_PUCK, AIRoleSlots.Slot.TRACK_MID_STRONG, \
		AIRoleSlots.Slot.TRACK_MID_WEAK, AIRoleSlots.Slot.TRACK_MID:
			decision = AIRoleTrack.decide(ctx, slot)
		AIRoleSlots.Slot.CHASE:
			decision = AIRoleChase.decide(ctx)
		AIRoleSlots.Slot.FLANK_L:
			decision = AIRoleFlank.decide(ctx, -1.0)
		AIRoleSlots.Slot.FLANK_R:
			decision = AIRoleFlank.decide(ctx, 1.0)
		# ── 5v5 slots (AIRoleSlots5).
		AIRoleSlots.Slot.NET_FRONT:
			# The crease-edge screen/backdoor man — FINISHER's argmax already
			# owns that ice (one-timer camp + tip logic included).
			decision = AIRoleFinisher.decide(ctx)
		AIRoleSlots.Slot.HIGH_SLOT:
			decision = AIRoleHighSlot.decide(ctx)
		AIRoleSlots.Slot.POINT_STRONG, AIRoleSlots.Slot.POINT_WEAK, \
		AIRoleSlots.Slot.DP_STRONG, AIRoleSlots.Slot.DP_WEAK, \
		AIRoleSlots.Slot.DVALVE, \
		AIRoleSlots.Slot.DBACK_L, AIRoleSlots.Slot.DBACK_R:
			decision = AIRoleDefenseman.decide(ctx, slot)
		AIRoleSlots.Slot.ZONE_D_STRONG, AIRoleSlots.Slot.ZONE_D_WEAK, \
		AIRoleSlots.Slot.ZONE_C, AIRoleSlots.Slot.ZONE_W_STRONG, \
		AIRoleSlots.Slot.ZONE_W_WEAK:
			decision = AIRoleZoneDefense.decide(ctx, slot)
		AIRoleSlots.Slot.F2_STRONG:
			decision = AIRoleForecheck.decide_f2(ctx, true)
		AIRoleSlots.Slot.F2_WEAK:
			decision = AIRoleForecheck.decide_f2(ctx, false)
		AIRoleSlots.Slot.BREAKOUT_D2:
			# Net-front reverse valve — the weak-side breakout outlet's job.
			decision = AIRoleBreakout.decide(ctx, false)
		AIRoleSlots.Slot.BREAKOUT_STRETCH:
			# Weak winger's stretch: OUTLET paces the far blue line legally.
			decision = AIRoleOutlet.decide(ctx)
		AIRoleSlots.Slot.BREAKOUT_C:
			decision = AIRoleBreakoutCenter.decide(ctx)
		AIRoleSlots.Slot.WIDE_L:
			decision = AIRoleWideLane.decide(ctx, -1.0)
		AIRoleSlots.Slot.WIDE_R:
			decision = AIRoleWideLane.decide(ctx, 1.0)
		AIRoleSlots.Slot.TRAILER, AIRoleSlots.Slot.CARRIER:
			# High-slot trailer — SUPPORT's goal-side trail read. CARRIER lands
			# here off the puck: the brain slots off the reaction-delayed carrier
			# belief, so a passer keeps it for carrier_reaction_delay_s after the
			# release. SUPPORT is his next job; holding braked him to a stop.
			decision = AIRoleSupport.decide(ctx)
		_:
			# Slot.NONE: nothing to be in position FOR yet. Hold.
			decision = RoleDecision.new()
			decision.target_position = ctx.self_pos
	_prev_role_slot = slot
	_prev_role_target = decision.target_position
	_prev_locked_man_pid = decision.locked_man_pid
	_prev_held_forward_stand = decision.held_forward_stand
	return decision


# Reception blade-aim target for CHASE — the engagement pull-back, in-reach snap,
# and gate-park branches. A pure, cheap function of current perception, so it is
# called EVERY physics tick, throttle-skipped ticks included. INF when no
# reception branch applies (far chase, or a carried / slow puck out of reach).
func _chase_reception_aim_target(snapshot: WorldSnapshot, self_pos: Vector3) -> Vector3:
	# Just got stripped / stick-checked: pull the blade back to the body so the
	# loose puck can settle without auto-magnetting straight back onto the stick.
	if _engagement_cooldown > 0:
		return Vector3(self_pos.x, 0.0, self_pos.z)
	var puck_pos: Vector3 = snapshot.puck_state.position
	# A teammate's blade is first to it: take the stick OFF the puck (see
	# Scripts/domain/ai/CLAUDE.md → "Teammates don't stab at each other's puck").
	if _teammate_first_to_puck(snapshot, puck_pos):
		return Vector3(self_pos.x, 0.0, self_pos.z)
	# Inside reach: aim at the puck's ACTUAL position (leading here would put the
	# blade past a puck already on the stick).
	if self_pos.distance_to(puck_pos) <= _blade_reach:
		return puck_pos
	# Fast loose puck (an incoming feed): PARK at the gate — the earliest point on
	# the puck's travel line the blade can touch — and let the puck arrive into it.
	if snapshot.puck_state.carrier_peer_id == -1:
		var pv: Vector3 = snapshot.puck_state.velocity
		if pv.x * pv.x + pv.z * pv.z > LOOSE_PUCK_TRACK_SPEED_M_S * LOOSE_PUCK_TRACK_SPEED_M_S:
			var self_state: SkaterNetworkState = snapshot.skater_states.get(_peer_id)
			return SkaterAgentReception.blade_gate(self_pos,
					self_state.velocity if self_state != null else Vector3.ZERO,
					puck_pos, pv, _blade_reach)
	return Vector3.INF


func _state_chase_puck(input: InputState, snapshot: WorldSnapshot, self_pos: Vector3, have_puck: bool) -> void:
	# Shot-aware reception first: if a pass is incoming and a shot from the
	# reception area is on, one-time it (Mode A → ONE_TIMER_PRESSED) or catch it
	# in a net-ward posture (Mode B, input set in-place) instead of turning to
	# grab. Mode A has already changed state, so return without running the
	# chase transitions below.
	var recv: int = _try_shot_reception(input, snapshot, self_pos)
	if recv == _RECV_ONE_TIME:
		return
	# An INBOUND fast loose puck is a reception, not a race: the catch gate judges
	# the puck's speed in OUR frame, so skating hard into the feed knocks it down.
	var give_brake: bool = false
	if snapshot.puck_state.carrier_peer_id == -1:
		var pv: Vector3 = snapshot.puck_state.velocity
		var pv_speed_sq: float = pv.x * pv.x + pv.z * pv.z
		if pv_speed_sq > LOOSE_PUCK_TRACK_SPEED_M_S * LOOSE_PUCK_TRACK_SPEED_M_S:
			var pp: Vector3 = snapshot.puck_state.position
			var inbound: bool = pv.x * (self_pos.x - pp.x) \
					+ pv.z * (self_pos.z - pp.z) > 0.0
			if inbound:
				var sv: Vector3 = Vector3.ZERO
				var give_state: SkaterNetworkState = snapshot.skater_states.get(_peer_id)
				if give_state != null:
					sv = give_state.velocity
				give_brake = SkaterAgentReception.gives_with(pv, sv)
	# Pass-receive setup, unless Mode B already set aim+steer; false falls through
	# to the default chase.
	if recv == _RECV_NONE and not _pass_receive_aim_and_steer(input, snapshot, self_pos):
		# Lead intercept: where the puck WILL be when we'd actually arrive.
		var puck_pos: Vector3 = snapshot.puck_state.position
		var self_vel_3d: Vector3 = Vector3.ZERO
		var self_state2: SkaterNetworkState = snapshot.skater_states.get(_peer_id)
		if self_state2 != null:
			self_vel_3d = self_state2.velocity
		var target: Vector3 = _lead_intercept(
				self_pos, self_vel_3d, puck_pos, snapshot.puck_state.velocity)
		# Angle an opponent carrier (Scripts/ai/CLAUDE.md → Chase doctrine). A
		# teammate carrier never reaches here (the chase ends on possession), so a
		# carrier is an opponent. Without the angling read the bot chases straight.
		var carrier_pid: int = snapshot.puck_state.carrier_peer_id
		if _angles_the_chase and carrier_pid != -1 and carrier_pid != _peer_id:
			var our_net := Vector3(0.0, 0.0, _own_goal_dir * GameRules.GOAL_LINE_Z)
			target = _shade_intercept_goal_side(target, our_net)

		# No "soft-hands" slow-down here: easing the approach doesn't help the
		# pickup (see Reception doctrine) and only surrenders time on a race.
		var puck_velocity: Vector3 = snapshot.puck_state.velocity
		var puck_speed_xz: float = sqrt(puck_velocity.x * puck_velocity.x
				+ puck_velocity.z * puck_velocity.z)

		# Contested 50/50 (a slow loose puck an OPPONENT'S blade can also reach):
		# never hover blade-first — both bots park at reach and nobody separates
		# the play. Overshoot along the approach line instead, so our momentum
		# weights the contested squirt our way
		# (PuckCollisionRules.contested_pickup_velocity) and carries us through.
		var contested: bool = carrier_pid == -1 \
				and puck_speed_xz <= LOOSE_PUCK_TRACK_SPEED_M_S \
				and _opponent_within_of(snapshot, puck_pos, ENGAGEMENT_PROXIMITY_M)
		if contested:
			var through: Vector3 = Vector3(
					puck_pos.x - self_pos.x, 0.0, puck_pos.z - self_pos.z)
			if through.length_squared() > 0.0001:
				target = puck_pos + through.normalized() * ENGAGEMENT_PROXIMITY_M
				# A drive-through that crosses a net engages at the puck instead,
				# rather than driving the body through the frame.
				if AINetObstacle.carry_path_blocked_by_net(puck_pos, target):
					target = puck_pos
		elif carrier_pid == -1:
			# BLADE-FIRST pickup route: steer the BODY one carry cradle SHORT of the
			# intercept, so the puck meets the blade a cradle ahead on the skating
			# line (and lands at the carry spot) rather than the chest overrunning
			# it. A CARRIED puck keeps the raw intercept — body pressure is the
			# point there.
			var approach: Vector3 = Vector3(
					target.x - self_pos.x, 0.0, target.z - self_pos.z)
			var approach_len: float = approach.length()
			if approach_len > AIBotMechanics.CARRY_BLADE_AIM_FORWARD_M:
				target -= approach * (AIBotMechanics.CARRY_BLADE_AIM_FORWARD_M / approach_len)
		# Every target above is built off the PUCK, whose path can ride ice a
		# skater's centre never reaches (the contested overshoot can even land
		# inside the glass), and steering at it grinds the body into the boards.
		# Clamp to standable ice; the blade still plays the wall once in reach.
		var chase_on_ice: Vector2 = GameRules.clamp_to_rink_inner(
				Vector2(target.x, target.z), SkaterAgentReception.BODY_WALL_MARGIN_M)
		target = Vector3(chase_on_ice.x, 0.0, chase_on_ice.y)
		_apply_steering(input, snapshot, self_pos, target)
		if give_brake:
			input.brake = true   # give with the puck — shed our own closing

		# INF = no reception branch → FACE-aim the far chase.
		var recv_aim: Vector3 = _chase_reception_aim_target(snapshot, self_pos)
		if recv_aim.is_finite():
			input.mouse_world_pos = _step_mouse_toward(recv_aim)
		else:
			# FACE-aim the far chase at the intercept, so the bot looks down its
			# chase line the whole run.
			input.mouse_world_pos = _step_mouse_face(target)

	# Transitions: chase ends when we have the puck or are no longer the chaser.
	# A ready one-timer with the puck in our zone fires instead of picking up.
	if have_puck:
		_set_state(State.CARRY)
	elif _is_one_timer_ready and _in_attacking_zone(self_pos) \
			and _puck_in_one_timer_zone(snapshot, self_pos):
		_set_state(State.ONE_TIMER_PRESSED)
	elif not _should_chase_loose_puck(snapshot, self_pos) \
			and not _reception.incoming_pass(snapshot, self_pos):
		# A pass still heading our way keeps the chase even when we aren't
		# closest to the puck's current spot (near the passer early in flight).
		_set_state(State.OFF_PUCK)


# Pass-receive sub-behavior (SkaterAgentReception.read_pass). True if it handled
# the tick; false when the feed isn't one to square up to.
func _pass_receive_aim_and_steer(input: InputState, snapshot: WorldSnapshot, self_pos: Vector3) -> bool:
	if not _reception.read_pass(snapshot, self_pos, _blade_reach, _receive_body_offset,
			_self_max_speed):
		return false
	_apply_steering(input, snapshot, self_pos, _reception.pass_body_anchor,
			_reception.pass_overruns)
	if _reception.pass_give:
		input.brake = true
	input.mouse_world_pos = _step_mouse_toward(_reception.pass_blade_aim)
	return true


# Shot-aware reception decision (SkaterAgentReception.read_shot). Returns one of
# the _RECV_* codes:
#   _RECV_NONE         — not a shot reception; caller runs the normal catch.
#   _RECV_CATCH_STRIDE — Mode B: aim+steer set here (net-ward catch); caller
#                        falls through to the chase transitions (have_puck →
#                        CARRY, which then takes the in-stride/closer shot).
#   _RECV_ONE_TIME     — Mode A: transitioned to ONE_TIMER_PRESSED; caller must
#                        return.
func _try_shot_reception(input: InputState, snapshot: WorldSnapshot, self_pos: Vector3) -> int:
	if not _reception.read_shot(snapshot, self_pos, _blade_reach, _attacking_goal_pos):
		return _RECV_NONE
	if _reception.shot_one_time_geometry and _squared_to_shoot(snapshot, self_pos):
		# One transitional tick of net-aimed steering before ONE_TIMER_PRESSED
		# takes over next dispatch (it presses slap on its tick 0 and settles
		# on the live line itself — no latched anchor to hand over).
		_apply_steering(input, snapshot, self_pos, _reception.shot_anchor)
		input.mouse_world_pos = _step_mouse_toward(_shot_aim_point(snapshot, self_pos, 0.0))
		_set_state(State.ONE_TIMER_PRESSED)
		return _RECV_ONE_TIME
	# Mode B: steer to the net-forward anchor and PARK the blade at the gate, which
	# sits net-ward of the body, so facing stays net-ward. No brake: keep momentum
	# to drive in.
	_apply_steering(input, snapshot, self_pos, _reception.shot_anchor)
	input.mouse_world_pos = _step_mouse_toward(SkaterAgentReception.blade_gate(
			self_pos, _reception.shot_self_vel, snapshot.puck_state.position,
			snapshot.puck_state.velocity, _blade_reach))
	return _RECV_CATCH_STRIDE


# Whether the body already faces within ONE_TIME_MAX_SQUARE_UP_RAD of a contact
# release's aim, so a one-time press doesn't whip it round. Unreadable facing
# counts as square.
func _squared_to_shoot(snapshot: WorldSnapshot, self_pos: Vector3) -> bool:
	var self_state: SkaterNetworkState = snapshot.skater_states.get(_peer_id)
	if self_state == null or self_state.facing.length_squared() <= 0.0001:
		return true
	var net_aim: Vector3 = _shot_aim_point(snapshot, self_pos, 0.0)
	var aim_dir := Vector2(net_aim.x - self_pos.x, net_aim.z - self_pos.z)
	if aim_dir.length_squared() <= 0.0001:
		return true
	return absf(self_state.facing.angle_to(aim_dir)) \
			<= SkaterAgentReception.ONE_TIME_MAX_SQUARE_UP_RAD


func _state_carry(input: InputState, snapshot: WorldSnapshot, self_pos: Vector3, have_puck: bool) -> void:
	if not have_puck:
		_carrier.reset()
		_intended_action = State.CARRY
		_intent_wait_ticks = 0
		_pass_target_peer_id = -1
		_pass_should_saucer = false
		_shot_loft_level = ShotMechanics.ELEVATION_FLAT
		_shot_aim_locked = Vector3.INF
		_shot_power_committed = 1.0
		_shot_hold_offset_locked = Vector3.ZERO
		_shot_hold_share_locked = 1.0
		_locked_pre_aim_point = Vector3.INF
		_dump_target = Vector3.INF
		_set_state(_post_puck_lost_state(snapshot))
		return

	# Throttled internally; between re-evals it returns its cached decision.
	var self_state: SkaterNetworkState = snapshot.skater_states.get(_peer_id)
	var ctx: RoleContext = _build_role_context(snapshot, self_pos, self_state)
	_carrier.decide(ctx)

	# Mirrored every tick: press states and pre-aim read these fresh.
	_last_carry_anchor = _carrier.last_carry_anchor
	_pass_target_peer_id = _carrier.pass_target_peer_id
	_pass_target_speed = _carrier.pass_target_speed
	_pass_should_saucer = _carrier.pass_should_saucer
	# Shot params must NOT keep tracking the carrier once a fire intent is latched,
	# so the bot performs the exact shot that won the compete; they refresh only
	# while still deliberating.
	if _intended_action == State.CARRY:
		_shot_loft_level = _carrier.shot_loft_level
		_shot_aim_locked = _carrier.shot_aim_point
		_shot_power_committed = _carrier.shot_power_t
		_shot_hold_offset_locked = _carrier.shot_hold_offset
		_shot_hold_share_locked = _carrier.shot_hold_share
		# The dump target freezes the same way. (_pass_aim_point reads
		# _dump_target first, so the always-fresh pass mirror can't hijack a dump.)
		if _carrier.intended_action == AIRoleCarrier.INTENT_DUMP:
			_dump_target = _carrier.dump_target
			_dump_launch_speed = _carrier.dump_launch_speed
		else:
			_dump_target = Vector3.INF
	debug_shoot_score = _carrier.debug_shoot_score
	debug_pass_score = _carrier.debug_pass_score
	debug_pass_peer_id = _carrier.debug_pass_peer_id
	debug_carry_score = _carrier.debug_carry_score
	debug_carry_pos = _carrier.debug_carry_pos

	# A latched fire intent is held through pre-aim convergence (or the timeout),
	# or score oscillations between re-evals flip it back to CARRY before the aim
	# converges and the bot never fires. Press states own their own bails.
	if _intended_action == State.CARRY:
		var new_intent: State = _state_from_carrier_intent(_carrier.intended_action)
		if new_intent != _intended_action:
			_intent_wait_ticks = 0
			# Lock the pre-aim point once (see _locked_pre_aim_point).
			match new_intent:
				State.SHOOT_PRESSED:
					# Prefer the carrier's locked hole aim so pre-aim faces the
					# exact hole the charge will shoot at (no side-flip wiggle).
					_locked_pre_aim_point = (_shot_aim_locked
							if _shot_aim_locked.is_finite()
							else _shot_aim_point(snapshot, self_pos))
				State.PASS_PRESSED:
					_locked_pre_aim_point = _pass_aim_point(snapshot, self_pos)
					_lock_pass_hold(snapshot, self_pos, self_state)
		_intended_action = new_intent

	# Steering by latched intent. CARRY drifts to the carry destination. A SHOOT
	# pre-aim steers to the projected release position — no braking, so the shot
	# fires before the goalie can reset. A PASS brakes: pass leads aim from a held
	# spot.
	if _intended_action == State.CARRY:
		if _carrier.carry_move >= 0:
			# The rolled move the carrier priced is the input it skates, the stance
			# by the read the roll held it on (AICarryRollout.STANCE_TURN_WINDOW_S).
			input.move_vector = _carrier.carry_stick
			input.brake = _carrier.carry_brake
			var v: Vector3 = self_state.velocity if self_state != null else Vector3.ZERO
			input.stance_held = not input.brake and AISteering.stance_cuts_onto(
					input.move_vector, Vector2(v.x, v.z), _upright_lateral_accel(),
					AICarryRollout.STANCE_TURN_WINDOW_S, _cached_stance_held)
		else:
			# Skated through at pace — no arrival brake.
			_apply_steering(input, snapshot, self_pos, _last_carry_anchor,
					false, _self_max_speed)
	elif _intended_action == State.SHOOT_PRESSED:
		var hv: Vector3 = Vector3.ZERO
		if self_state != null:
			hv = Vector3(self_state.velocity.x, 0.0, self_state.velocity.z)
		_apply_steering(input, snapshot, self_pos,
				self_pos + hv * AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S)
	else:
		_apply_brake_steering(input, snapshot, self_pos)

	# Mouse target depends on intent: carry uses normal goal-aim, fire states
	# pre-aim toward action direction.
	if _intended_action == State.CARRY:
		# _step_carry_cursor is also re-run on throttle-skipped ticks.
		_step_carry_cursor(input, snapshot, self_pos, self_state)
	else:
		var mouse_target: Vector3 = _aim_target_for_intent(snapshot, self_pos)
		# ARC pre-aim swing toward the FINAL target. A charged release's hold is
		# a carry reach, not an aim: FRONT in front of the body, round to the hold
		# itself behind it.
		if not _pre_aim_holds_puck():
			input.mouse_world_pos = _step_mouse_aim(mouse_target)
		elif _target_is_behind(mouse_target - self_pos, self_state):
			input.mouse_world_pos = _step_mouse_hold_arc(mouse_target)
		else:
			input.mouse_world_pos = _step_mouse_front(mouse_target)

	# Every release is a charged wrister, which fires along its committed aim
	# from wherever the puck sits: the press waits (or times out) only until the
	# puck carries the share of pace it was priced at.
	if _intended_action != State.CARRY:
		if _load_ready(snapshot, self_pos, self_state) \
				or _intent_wait_ticks >= _intent_max_wait_ticks:
			_set_state(_intended_action)
			_intended_action = State.CARRY
			_intent_wait_ticks = 0
			_locked_pre_aim_point = Vector3.INF
			# Or the carrier re-fires the same action on re-entering CARRY.
			_carrier.clear_intent()
		else:
			# Advance by the dispatch span: _intent_max_wait_ticks is in physics ticks.
			_intent_wait_ticks += _dispatch_period_ticks


# The carried puck's offset off the body, world XZ.
func _puck_offset(snapshot: WorldSnapshot, self_pos: Vector3) -> Vector2:
	if snapshot.puck_state == null:
		return Vector2.ZERO
	var p: Vector3 = snapshot.puck_state.position
	return Vector2(p.x - self_pos.x, p.z - self_pos.z)


# Share of this bot's pace a charged release toward `aim_world` carries with the
# puck where it is and the body as it faces now. The hand is left in _holds.
func _share_as_is(snapshot: WorldSnapshot, self_pos: Vector3,
		self_state: SkaterNetworkState, aim_world: Vector3) -> float:
	var puck: Vector2 = _puck_offset(snapshot, self_pos)
	var aim := Vector2(aim_world.x - self_pos.x, aim_world.z - self_pos.z) - puck
	return _holds.share_at(puck, aim, self_state.facing)


# Where a charged pass or dump holds the puck at the press, solved once at the
# intent transition like the pre-aim point (AIShotHolds.solve_pass).
func _lock_pass_hold(snapshot: WorldSnapshot, self_pos: Vector3,
		self_state: SkaterNetworkState) -> void:
	_pass_hold_share = 0.0
	if self_state == null:
		return
	var pace: float = _dump_launch_speed if _dump_target.is_finite() else _pass_target_speed
	var puck: Vector2 = _puck_offset(snapshot, self_pos)
	_holds.solve_pass(Vector2(_locked_pre_aim_point.x - self_pos.x,
			_locked_pre_aim_point.z - self_pos.z) - puck, puck,
			Vector2(self_state.velocity.x, self_state.velocity.z), self_state.facing,
			pace / maxf(_self_wrister_shot_speed, 0.001))
	_pass_hold_offset = Vector3(_holds.pass_offset.x, 0.0, _holds.pass_offset.y)
	_pass_hold_share = _holds.pass_share


# True once the puck carries the share of pace the locked charged release was
# priced at, read live (the body's facing freezes at the press).
func _load_ready(snapshot: WorldSnapshot, self_pos: Vector3,
		self_state: SkaterNetworkState) -> bool:
	if self_state == null or not _locked_pre_aim_point.is_finite():
		return true
	var priced: float = _shot_hold_share_locked if _intended_action == State.SHOOT_PRESSED \
			else _pass_hold_share
	return _share_as_is(snapshot, self_pos, self_state, _locked_pre_aim_point) \
			>= priced - LOAD_READY_SHARE_SLACK


# Maps the carrier's INTENT_* enum (decoupled from State for unit testing) to a
# State.
func _state_from_carrier_intent(intent: int) -> State:
	match intent:
		AIRoleCarrier.INTENT_SHOOT:
			return State.SHOOT_PRESSED
		AIRoleCarrier.INTENT_PASS:
			return State.PASS_PRESSED
		AIRoleCarrier.INTENT_DUMP:
			# A dump is a pass to a LOCATION (no receiver) — reuse the PASS_PRESSED
			# release path; _dump_target (finite) redirects the aim and the bail.
			return State.PASS_PRESSED
		_:
			return State.CARRY


# The mouse target (world XZ) while pre-aiming for `_intended_action`: a charged
# release's hold, else the aim ring toward the locked pre-aim point (a fresh
# compute if none is locked).
func _aim_target_for_intent(snapshot: WorldSnapshot, self_pos: Vector3) -> Vector3:
	match _intended_action:
		State.PASS_PRESSED:
			if _pass_hold_share > 0.0:
				return self_pos + _pass_hold_offset
			var target: Vector3 = (_locked_pre_aim_point
					if _locked_pre_aim_point.is_finite()
					else _pass_aim_point(snapshot, self_pos))
			return _aim_ring_toward(self_pos, target)
		State.SHOOT_PRESSED:
			if _shot_hold_offset_locked != Vector3.ZERO:
				return self_pos + _shot_hold_offset_locked
			var target: Vector3 = (_locked_pre_aim_point
					if _locked_pre_aim_point.is_finite()
					else _shot_aim_point(snapshot, self_pos))
			return _aim_ring_toward(self_pos, target)
		_:
			return _carry_mouse_aim(snapshot, self_pos)


# Whether _aim_target_for_intent is carrying the puck to a charged release's hold
# rather than aiming the ring.
func _pre_aim_holds_puck() -> bool:
	match _intended_action:
		State.SHOOT_PRESSED:
			return _shot_hold_offset_locked != Vector3.ZERO
		State.PASS_PRESSED:
			return _pass_hold_share > 0.0
	return false


# The point on the carry aim ring (CARRY_BLADE_AIM_FORWARD_M) toward `aim_world`:
# the right DIRECTION close to the bot, so pre-aim swings there fast. It is the
# FINAL point of the pre-aim swing, not an arc step.
func _aim_ring_toward(self_pos: Vector3, aim_world: Vector3) -> Vector3:
	var to_aim: Vector3 = aim_world - self_pos
	to_aim.y = 0.0
	if to_aim.length_squared() < 0.0001:
		# Fall back to the attacking direction (team-aware). Vector3.FORWARD
		# is (0, 0, -1), which is correct for team 0 but inverts for team 1.
		return self_pos + Vector3(0.0, 0.0, -_own_goal_dir) * AIBotMechanics.CARRY_BLADE_AIM_FORWARD_M
	return self_pos + to_aim.normalized() * AIBotMechanics.CARRY_BLADE_AIM_FORWARD_M


# ── Protect-side turn ────────────────────────────────────────────────────────
# A carrier's turn-around sweeps the puck along the arc the mouse walks, and the
# SHORT way may drag it through a defender's poke reach where the LONG way keeps
# the body between. When a big swing starts, both sides are read at their
# midpoint against the nearest opposing blade; the long way is taken iff the
# short side is inside poke threat and the long side is meaningfully clearer.
# The sign is latched until the swing passes halfway or completes, or a per-tick
# re-read would flip direction mid-sweep.
const PROTECT_TURN_MIN_SWING_RAD: float = deg_to_rad(100.0)
# How far short of straight behind the body a turning-round cursor waits: inside
# the gap between the reach edge and straight back, so it stays past the edge.
const TURN_ROUND_BACK_MARGIN_RAD: float = deg_to_rad(10.0)
# A stick's poke reach off the swept puck: a blade-length lunge plus the stick
# itself, held out from the defender's body.
const PROTECT_TURN_THREAT_RADIUS_M: float = 2.5
# The long way must beat the short way's clearance by this much — a marginal
# gain isn't worth the extra rotation time.
const PROTECT_TURN_MARGIN_M: float = 0.5
# Committed long-way sweep sign; 0.0 = no commitment (shortest way).
var _arc_protect_sign: float = 0.0


# The sweep sign for a carry-arc swing of `diff` (wrapped desired−current):
# signf(diff) (shortest way) unless the short sweep drags the puck into poke
# threat and the long sweep is meaningfully clearer. Pure read, no state —
# _arc_step_mouse_target owns the commitment.
func _protect_turn_direction(self_pos: Vector3, current_angle: float,
		diff: float, snapshot: WorldSnapshot) -> float:
	var short_sign: float = signf(diff)
	if snapshot == null:
		return short_sign
	var short_mid: float = current_angle + diff * 0.5
	var short_puck := Vector3(
			self_pos.x + sin(short_mid) * _blade_reach, 0.0,
			self_pos.z + cos(short_mid) * _blade_reach)
	var short_clear: float = _nearest_opponent_blade_dist(snapshot, short_puck)
	if short_clear >= PROTECT_TURN_THREAT_RADIUS_M:
		return short_sign
	var long_mid: float = current_angle + (diff - short_sign * TAU) * 0.5
	var long_puck := Vector3(
			self_pos.x + sin(long_mid) * _blade_reach, 0.0,
			self_pos.z + cos(long_mid) * _blade_reach)
	var long_clear: float = _nearest_opponent_blade_dist(snapshot, long_puck)
	if long_clear > short_clear + PROTECT_TURN_MARGIN_M:
		return -short_sign
	return short_sign


# Distance from `point` to the nearest opposing blade (body position when the
# blade telemetry isn't populated yet). Pure read over the roster; no allocation.
func _nearest_opponent_blade_dist(snapshot: WorldSnapshot, point: Vector3) -> float:
	var nearest: float = INF
	for peer_id: int in _opponent_ids(snapshot):
		var opp_state: SkaterNetworkState = snapshot.skater_states[peer_id]
		var threat_pos: Vector3 = opp_state.blade_contact_world
		if threat_pos == Vector3.ZERO:
			threat_pos = opp_state.position
		var dx: float = threat_pos.x - point.x
		var dz: float = threat_pos.z - point.z
		var d: float = sqrt(dx * dx + dz * dz)
		if d < nearest:
			nearest = d
	return nearest


# Is the desired blade direction in the body's BACK hemisphere (>90° off the
# current facing)? Gates the long-way protect orbit to genuine turn-arounds. A
# null/degenerate facing returns false — bias toward the short-way reach, never
# an unprovoked spin.
func _target_is_behind(desired_dir: Vector3, self_state: SkaterNetworkState) -> bool:
	if self_state == null or self_state.facing.length_squared() < 0.0001:
		return false
	var facing: Vector2 = self_state.facing.normalized()
	return desired_dir.x * facing.x + desired_dir.z * facing.y < 0.0


# An intermediate mouse target on the `ring_radius` ring around self_pos that
# walks toward `final_target` at no more than `arc_rate` (see _STEP_ARC). The
# linear step tracks this slowly-moving target with sub-tick error, so the mouse
# describes the same arc.
func _arc_step_mouse_target(self_pos: Vector3, final_target: Vector3,
		self_state: SkaterNetworkState, arc_rate: float,
		ring_radius: float = AIBotMechanics.CARRY_BLADE_AIM_FORWARD_M) -> Vector3:
	var to_final: Vector3 = final_target - self_pos
	to_final.y = 0.0
	if to_final.length_squared() < 0.0001:
		return final_target
	var desired_dir: Vector3 = to_final.normalized()

	# Seed the current angle from the mouse's offset from self_pos, or from facing
	# when the mouse is parked on the body — not desired_dir, which would let the
	# next chord cross self_pos when desired_dir points behind the bot.
	var current_offset := Vector2(_mouse_pos.x - self_pos.x, _mouse_pos.z - self_pos.z)
	var seed_dir: Vector3
	if _mouse_pos_initialized and current_offset.length_squared() >= 0.04:
		seed_dir = Vector3(current_offset.x, 0.0, current_offset.y).normalized()
	elif self_state != null \
			and Vector2(self_state.facing.x, self_state.facing.y).length_squared() > 0.0001:
		seed_dir = Vector3(self_state.facing.x, 0.0, self_state.facing.y).normalized()
	else:
		seed_dir = desired_dir

	var current_angle: float = atan2(seed_dir.x, seed_dir.z)
	var desired_angle: float = atan2(desired_dir.x, desired_dir.z)
	var diff: float = wrapf(desired_angle - current_angle, -PI, PI)
	var max_step: float = arc_rate * MOUSE_TICK_DELTA
	# Moving, a target inside the blade's reach edge is swung round the front
	# (BladeRoute.swing_angle, as AIShotHolds prices it); one past it turns the
	# body round (FacingRules).
	var vel := Vector2.ZERO
	var facing := Vector2.ZERO
	if self_state != null:
		vel = Vector2(self_state.velocity.x, self_state.velocity.z)
		facing = Vector2(self_state.facing.x, self_state.facing.y)
	var rules: FacingRules.Config = _role_ctx.self_facing_rules
	var to_dir := Vector2(desired_dir.x, desired_dir.z)
	var moving: bool = vel.length() > rules.hold_min_speed and facing.length_squared() > 0.0001
	var turning_round: bool = facing.length_squared() > 0.0001 and absf(facing.angle_to(to_dir)) \
			>= FacingRules.reach_edge(rules, facing, to_dir, _is_left_handed)
	if moving and not turning_round:
		diff = -BladeRoute.swing_angle(Vector2(seed_dir.x, seed_dir.z), to_dir, facing, vel,
				rules, _is_left_handed)
	# Protect-side turn (carriers only — see PROTECT_TURN_*): pick which way a
	# big swing sweeps the puck, latch it, and hold it until the shortest way
	# agrees (swung past halfway) or the swing completes.
	if _state != State.CARRY or (moving and not turning_round):
		_arc_protect_sign = 0.0
	elif _arc_protect_sign != 0.0:
		if signf(diff) == _arc_protect_sign or absf(diff) <= max_step:
			_arc_protect_sign = 0.0
	elif absf(diff) >= PROTECT_TURN_MIN_SWING_RAD and _target_is_behind(desired_dir, self_state):
		# Long-way orbit only for a genuine TURN-AROUND (target behind the body). A
		# front-hemisphere target is a protect REACH: take the short way and let
		# the blade's ROM extend across the front.
		var protect_sign: float = _protect_turn_direction(
				self_pos, current_angle, diff, _current_snapshot)
		if protect_sign != signf(diff):
			_arc_protect_sign = protect_sign
	var step: float = _arc_protect_sign * max_step if _arc_protect_sign != 0.0 \
			else clampf(diff, -max_step, max_step)
	if turning_round:
		# Turning round, the cursor waits short of straight behind the body until it
		# comes round: across it the pivot would reverse (FacingRules.turn_round_angle).
		var back: float = wrapf(atan2(-facing.x, -facing.y) - current_angle, -PI, PI)
		if signf(back) == signf(step):
			step = signf(step) * minf(absf(step), maxf(absf(back) - TURN_ROUND_BACK_MARGIN_RAD, 0.0))
	var stepped_angle: float = current_angle + step
	return self_pos + Vector3(sin(stepped_angle), 0.0, cos(stepped_angle)) * ring_radius


# FACE-mode cursor placement: a point on the body ring straight at the target.
# Behind the body that turns it round, on the cursor's side, standing or moving.
func _face_ring_point(self_pos: Vector3, target: Vector3) -> Vector3:
	var to_target := Vector2(target.x - self_pos.x, target.z - self_pos.z)
	if to_target.length_squared() < 0.0001:
		return target
	var out_dir: Vector2 = to_target.normalized()
	return self_pos + Vector3(out_dir.x, 0.0, out_dir.y) * AIBotMechanics.CARRY_BLADE_AIM_FORWARD_M


func _state_shoot_pressed(input: InputState, snapshot: WorldSnapshot, self_pos: Vector3, have_puck: bool) -> void:
	# Lost the puck mid-charge: the release path is a no-op without the puck.
	if not have_puck:
		_set_state(_post_puck_lost_state(snapshot))
		return

	# Mid-charge bail on a body check (stagger_timer set), from any direction.
	var charge_self_state: SkaterNetworkState = snapshot.skater_states.get(_peer_id)
	if _shoot_charge_tick > 0 and charge_self_state != null \
			and charge_self_state.stagger_timer > 0.0:
		input.slap_pressed = true
		_set_state(State.CARRY)
		return

	# Mid-charge bail on an opponent closing from the FRONT: slap_pressed cancels
	# WRISTER_AIM without a release. Skipped on tick 0. A defender behind the
	# shooter can't realistically disrupt the windup.
	if _shoot_charge_tick > 0 and _opponent_within_forward(
			snapshot, self_pos, _attacking_goal_pos - self_pos,
			BOT_WRISTER_BAIL_RADIUS_M):
		input.slap_pressed = true
		_set_state(State.CARRY)
		return

	# Lock the steering destination at charge start (_shoot_release_anchor): the
	# projected release position the carrier scored the shot from.
	var self_state: SkaterNetworkState = snapshot.skater_states.get(_peer_id)
	if _shoot_charge_tick == 0:
		var hv0: Vector3 = Vector3.ZERO
		if self_state != null:
			hv0 = Vector3(self_state.velocity.x, 0.0, self_state.velocity.z)
		_shoot_release_anchor = self_pos + hv0 * AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S
		_shoot_wind_up_moving = hv0.length() > BOT_WRISTER_PLANT_SPEED_M_S
	# Rush wrister: steer to the anchor. Near-still: plant (BOT_WRISTER_PLANT_SPEED_M_S).
	if _shoot_wind_up_moving:
		_apply_steering(input, snapshot, self_pos, _shoot_release_anchor)
	else:
		_apply_brake_steering(input, snapshot, self_pos)
	# The loft is absolute per input frame (SkaterAgent.zero_input resets it), so
	# it is set on every charge tick.
	input.elevation_level = _shot_loft_level

	# First tick: capture aim, compute the wind-up, fire the shoot_pressed edge.
	# The forehand/backhand read is the sticky carry face (Skater._carry_side),
	# advanced every tick from the blade pose, so the cursor must be at the
	# wind-up start THIS tick to keep the carried face through the wind-up.
	if _shoot_charge_tick == 0:
		debug_last_decision = "SHOOT"
		# The locked aim direction must hit the aim point from where the shot
		# ACTUALLY leaves: the projected release anchor plus the puck's offset
		# (the blade freezes it there).
		var puck_off: Vector2 = _puck_offset(snapshot, self_pos)
		var release_pos: Vector3 = _shoot_release_anchor + Vector3(puck_off.x, 0.0, puck_off.y)
		# The carrier's locked hole when there is one. Its distance feeds
		# _wind_up_endpoint_offsets' side-offset compensation.
		var aim_point: Vector3 = (_shot_aim_locked
				if _shot_aim_locked.is_finite()
				else _shot_aim_point(snapshot, release_pos))
		var aim_vec: Vector3 = Vector3(aim_point.x - release_pos.x, 0.0, aim_point.z - release_pos.z)
		# This release's committed execution error (sampled at press entry):
		# rotate the whole aim frame once, so the windup sweeps cleanly to a
		# slightly-wrong spot and the release direction carries the error.
		if _committed_aim_error_rad != 0.0:
			aim_vec = aim_vec.rotated(Vector3.UP, _committed_aim_error_rad)
		var aim_dir_init: Vector3 = aim_vec.normalized() if aim_vec.length_squared() > 0.0001 else Vector3(0.0, 0.0, 1.0)
		var aim_distance: float = aim_vec.length()
		_shoot_aim_dir_locked = aim_dir_init
		# Wind-up side: the hand the load reads from where the puck sits.
		_shoot_side_sign = 1.0
		if self_state != null:
			_share_as_is(snapshot, self_pos, self_state, aim_point)
			_shoot_side_sign = -1.0 if _holds.is_backhand else 1.0

		# Wind-up endpoint OFFSETS, frozen at tick 0 so a shuffling goalie can't
		# flip the arc mid-swing, sized to the cosmetic span.
		var shot_span: float = BOT_WRISTER_WIND_UP_SPAN_M * _shot_power_committed
		var endpoints: Dictionary = _wind_up_endpoint_offsets(aim_dir_init, aim_distance, shot_span, _shoot_side_sign)
		_shoot_wind_up_start = endpoints.start
		_shoot_aim_target = endpoints.target
		# Snap the cursor to the wind-up start: stepping there from the pre-aim
		# ring takes several ticks of -aim_dir catch-up motion, which the charge
		# tracker reads as a direction reversal.
		_mouse_pos = self_pos + _shoot_wind_up_start
		_mouse_pos_initialized = true
		input.shoot_pressed = true

	# Clamped at 1: during the sampled late-release hold the blade sits at the
	# aim target.
	var t: float = minf(
			float(_shoot_charge_tick) / float(AIBotMechanics.BOT_WRISTER_CHARGE_TICKS), 1.0)
	input.mouse_world_pos = _step_mouse_toward(self_pos + _shoot_wind_up_start.lerp(_shoot_aim_target, t))

	# The charge tracker reads its DIRECTION from the screen-pos delta, which a bot
	# doesn't have: synthesize one along the sweep. Only the direction is read.
	var sweep_dir_3d: Vector3 = (_shoot_aim_target - _shoot_wind_up_start).normalized()
	input.mouse_screen_pos = Vector2(sweep_dir_3d.x, sweep_dir_3d.z) * float(_shoot_charge_tick)
	# The controller reads power and direction from these, not from the cosmetic
	# sweep. Set every tick so they're live on the release tick.
	input.bot_wrister_power_t = _shot_power_committed
	input.bot_wrister_aim_dir = _shoot_aim_dir_locked

	if _shoot_charge_tick < AIBotMechanics.BOT_WRISTER_CHARGE_TICKS + _shoot_release_hold_ticks:
		# Still charging, or on the sampled late-release hold.
		input.shoot_held = true
		_shoot_charge_tick += 1
	else:
		# Release: shoot_held drops and release_wrister fires.
		#
		# RE-DERIVE the direction from where the puck ACTUALLY is: the aim was
		# locked against a PREDICTED release, and on a sharp-angle look a few cm
		# of release depth error swings the crossing point by a metre. The aim
		# POINT and the execution error stay locked, so this is not re-deciding.
		_retarget_release_dir(input, snapshot, self_pos)
		input.shoot_held = false
		_set_state(State.CARRY)


func _wind_up_endpoint_offsets(aim_dir: Vector3, aim_distance_m: float, wind_up_span_m: float, side_sign: float) -> Dictionary:
	var half: float = wind_up_span_m * 0.5
	var compensated: Vector3 = _aim_dir_compensated_for_side_offset(aim_dir, aim_distance_m, side_sign)
	var forehand_perp: Vector3 = Vector3(
			compensated.z * _handedness_perp_sign, 0.0, -compensated.x * _handedness_perp_sign)
	var perp: Vector3 = forehand_perp * side_sign
	return {
		"start":  -compensated * half + perp * BOT_WRISTER_SIDE_OFFSET_M,
		"target": +compensated * half + perp * BOT_WRISTER_SIDE_OFFSET_M,
	}


# Re-points the committed release direction from the live blade to the locked
# aim point, carrying the same per-release execution error the press sampled.
# No-op when no aim was locked (the continuous-geometry fallback path) or the
# blade is unavailable, so those keep the press-entry direction.
func _retarget_release_dir(input: InputState, snapshot: WorldSnapshot,
		self_pos: Vector3) -> void:
	if not _shot_aim_locked.is_finite():
		return
	var self_state: SkaterNetworkState = snapshot.skater_states.get(_peer_id)
	if self_state == null:
		return
	var blade: Vector3 = self_state.blade_contact_world
	if blade == Vector3.ZERO:
		blade = self_pos
	var aim_vec := Vector3(
			_shot_aim_locked.x - blade.x, 0.0, _shot_aim_locked.z - blade.z)
	if aim_vec.length_squared() < 0.0001:
		return
	# The SAME committed error the press drew — re-aiming must not re-roll the
	# execution dice, or the tier's spread would be sampled twice per shot.
	if _committed_aim_error_rad != 0.0:
		aim_vec = aim_vec.rotated(Vector3.UP, _committed_aim_error_rad)
	_shoot_aim_dir_locked = aim_vec.normalized()
	input.bot_wrister_aim_dir = _shoot_aim_dir_locked


# Pre-tilts aim_dir for the wind-up's lateral release offset: both endpoints sit
# SIDE_OFFSET off the aim line, so an untilted puck misses by SIDE_OFFSET at every
# distance. Rotating the frame by θ = asin(SIDE_OFFSET / aim_distance) toward
# -perp puts the flight exactly through the aim point. Inside SIDE_OFFSET there
# is no solution; the raw aim_dir is returned.
func _aim_dir_compensated_for_side_offset(aim_dir: Vector3, aim_distance_m: float, side_sign: float) -> Vector3:
	if aim_distance_m <= BOT_WRISTER_SIDE_OFFSET_M:
		return aim_dir
	var theta: float = asin(BOT_WRISTER_SIDE_OFFSET_M / aim_distance_m)
	var forehand_perp: Vector3 = Vector3(
			aim_dir.z * _handedness_perp_sign, 0.0, -aim_dir.x * _handedness_perp_sign)
	return aim_dir * cos(theta) - forehand_perp * side_sign * sin(theta)


func _state_pass_pressed(input: InputState, snapshot: WorldSnapshot, self_pos: Vector3, have_puck: bool) -> void:
	# Lost the puck mid-charge: release-without-puck is a no-op.
	if not have_puck:
		_pass_target_peer_id = -1
		_pass_should_saucer = false
		_dump_target = Vector3.INF
		_set_state(_post_puck_lost_state(snapshot))
		return

	# Dump override: a release at a LOCATION, not a receiver (see _dump_target).
	# Set here in the press state, after _state_carry has stopped clobbering the
	# pass fields. `_dump_target` is an AIM point, not where the puck stops.
	var is_dump: bool = _dump_target.is_finite()
	if is_dump:
		_pass_should_saucer = false
		_pass_target_peer_id = -1
		# FLAT is load-bearing on the charged path: release_wrister normalizes
		# (dir.x, tan, dir.z) at `power`, so any loft spends pace going up and the
		# ground speed stops being the pace the landing search solved.
		input.elevation_level = ShotMechanics.ELEVATION_FLAT
		_pass_target_speed = _dump_launch_speed

	_apply_brake_steering(input, snapshot, self_pos)
	# Saucer: LOW loft over a contested mid-lane stick. Set every tick (the level
	# is absolute per frame).
	if _pass_should_saucer:
		input.elevation_level = ShotMechanics.ELEVATION_LOW
	# Debug label, resolved before `_pass_target_peer_id` is cleared below.
	var target_slot_label: String = "?"
	if DEBUG_DECISIONS and _current_strategy != null and _pass_target_peer_id != -1:
		target_slot_label = AIRoleSlots.label(_current_strategy.get_slot(_pass_target_peer_id))
	# The receiver's lead (or the dump target), rotated by this release's
	# committed execution error.
	var clean_pass_aim: Vector3 = _apply_committed_aim_error(
			self_pos, _pass_aim_point(snapshot, self_pos))

	# ── Charged wrister pass ──
	# Mid-charge bail, as in SHOOT_PRESSED. Skipped on tick 0.
	if _pass_charge_tick > 0:
		var receiver_state: SkaterNetworkState = snapshot.skater_states.get(_pass_target_peer_id)
		if receiver_state != null:
			var forward: Vector3 = receiver_state.position - self_pos
			if _opponent_within_forward(snapshot, self_pos, forward, BOT_WRISTER_BAIL_RADIUS_M):
				input.slap_pressed = true
				_pass_target_peer_id = -1
				_pass_should_saucer = false
				_set_state(State.CARRY)
				return

	if DEBUG_DECISIONS:
		if is_dump:
			debug_last_decision = "DUMP↝rim"
		else:
			debug_last_decision = "PASS+→%s" % target_slot_label

	if _pass_charge_tick == 0:
		# aim_dir comes from clean_pass_aim rather than the stepped mouse, so a
		# cursor residual can't tilt it. A softer pass scales the cosmetic span
		# down so a gentle gesture reads gentle.
		var sweep: Vector3 = clean_pass_aim - self_pos
		sweep.y = 0.0
		var aim_distance: float = sweep.length()
		var aim_dir_init: Vector3 = sweep.normalized() if aim_distance > 0.01 else Vector3(0.0, 0.0, 1.0)
		_pass_aim_dir_locked = aim_dir_init
		# The hand is the load's, from where the puck sits; a backhand fires at
		# the build's backhand share, so its commit asks for the pace over it.
		var self_state0: SkaterNetworkState = snapshot.skater_states.get(_peer_id)
		var backhand: bool = false
		if self_state0 != null:
			_share_as_is(snapshot, self_pos, self_state0, clean_pass_aim)
			backhand = _holds.is_backhand
		# The puck keeps the passer's motion (ReleaseMomentum), so the blade pushes
		# what lands the pace the pass was priced at from how he is moving now.
		var push: float = _pass_target_speed
		var floor_push: float = GameRules.DEFAULT_WRISTER_POWER_MIN_M_S
		if self_state0 != null:
			push = ReleaseMomentum.push_for_pace(_pass_target_speed,
					Vector2(aim_dir_init.x, aim_dir_init.z), self_state0.velocity)
			floor_push = ReleaseMomentum.floor_push(floor_push, aim_dir_init, self_state0.velocity)
		_pass_power_committed = _pass_power_t(push, floor_push,
				_self_backhand_coefficient if backhand else 1.0)
		var pass_span: float = BOT_WRISTER_WIND_UP_SPAN_M * maxf(_pass_power_committed, 0.35)
		var endpoints: Dictionary = _wind_up_endpoint_offsets(aim_dir_init, aim_distance, pass_span,
				-1.0 if backhand else 1.0)
		_pass_wind_up_start = endpoints.start
		_pass_aim_target = endpoints.target
		# Snap the cursor to the wind-up start, as SHOOT_PRESSED does.
		_mouse_pos = self_pos + endpoints.start
		_mouse_pos_initialized = true
		input.shoot_pressed = true

	# Endpoints are offsets from the current self_pos (see _shoot_wind_up_start).
	var t: float = float(_pass_charge_tick) / float(AIBotMechanics.BOT_WRISTER_CHARGE_TICKS)
	input.mouse_world_pos = _step_mouse_toward(self_pos + _pass_wind_up_start.lerp(_pass_aim_target, t))

	# Synthesized screen-pos sweep and committed power / direction, as in
	# SHOOT_PRESSED.
	var sweep_dir_3d: Vector3 = (_pass_aim_target - _pass_wind_up_start).normalized()
	input.mouse_screen_pos = Vector2(sweep_dir_3d.x, sweep_dir_3d.z) * float(_pass_charge_tick)
	input.bot_wrister_power_t = _pass_power_committed
	input.bot_wrister_aim_dir = _pass_aim_dir_locked

	if _pass_charge_tick < AIBotMechanics.BOT_WRISTER_CHARGE_TICKS:
		input.shoot_held = true
		_pass_charge_tick += 1
	else:
		# Release: shoot_held drops and release_wrister fires.
		input.shoot_held = false
		_pass_target_peer_id = -1
		_pass_should_saucer = false
		# A charged dump (the rim) releases here, so its aim is spent here.
		_dump_target = Vector3.INF
		_set_state(State.CARRY)


# One-timer fire from off-puck, entered from OFF_PUCK / CHASE_PUCK when a ready
# FINISHER's feed is released (or the puck enters the one-timer zone).
#
# The real slapper one-timer (SkaterStateMachine.SLAPPER_CHARGE_WITHOUT_PUCK):
# press slap and HOLD — the controller runs the visible wind-up and arms the
# slapper pickup zone, and the feed's flight builds the charge. Dropping slap_held
# fires through the controller's own paths: attached mid-charge → release_slapper
# with the centre-timing bonus; at the zone but not attached →
# try_one_timer_release's leniency buffer. Never use a wrister hold:
# on_puck_picked_up_network forces SKATING_WITH_PUCK for every state except the
# slapper charge, so the bot would silently catch the feed instead.
func _state_one_timer_pressed(input: InputState, snapshot: WorldSnapshot, self_pos: Vector3, have_puck: bool) -> void:
	# Settle on the LIVE line (SkaterAgentOneTimer.line_anchor), re-derived every tick.
	var line_anchor: Vector3 = _one_timer.line_anchor(snapshot, self_pos, _attacking_goal_pos)
	var self_v: Vector3 = snapshot.skater_states[_peer_id].velocity
	if _one_timer_slap_down:
		# Wound up the legs only glide, so the circle reaches the line on the
		# glide the press counted on and then a shuffle: the brake with a stick,
		# stepping across. Faster than a shuffle, the brake would be a stop.
		var step: Vector2 = _one_timer.shuffle_stick(self_pos, line_anchor)
		if Vector2(self_v.x, self_v.z).length() > SkaterMovementRules.SHUFFLE_MAX_SPEED:
			pass
		elif step != Vector2.ZERO:
			input.move_vector = step
			input.brake = true
			input.bot_shuffle = true
		else:
			_apply_brake_steering(input, snapshot, self_pos)
	elif line_anchor.is_finite() \
			and self_pos.distance_to(line_anchor) > ONE_TIMER_ANCHOR_ARRIVE_M:
		_apply_steering(input, snapshot, self_pos, line_anchor)
	else:
		_apply_brake_steering(input, snapshot, self_pos)
	# Open up through the wait, as a shooter loading a one-timer does: skating,
	# the hips ride the skating line (FacingRules), and only the stance squares
	# them to the cursor, which shortens the pivot the press has left to make.
	input.stance_held = true
	# AIM FROM THE RELEASE POINT, NOT THE CURRENT BODY: the body may still shuffle
	# up to the reception lateral (SkaterAgentReception.RECEIVE_TRIGGER_LATERAL_M)
	# onto the feed line, which would bake in a parallel miss. The release point
	# is the slapper zone centre once settled on the live line (or the current
	# zone when there's none).
	var release_point: Vector3 = _one_timer.zone_center(
			line_anchor if line_anchor.is_finite() else self_pos, _attacking_goal_pos)
	# FACE-aimed at the hole read AGAINST THE FEED'S ARRIVAL — the goalie
	# re-squares while the pass flies — from the release point.
	var feed_s: float = SkaterAgentOneTimer.feed_time_s(snapshot, self_pos)
	var net_hole: Vector3 = _shot_aim_point(snapshot, release_point, feed_s)
	if not have_puck and snapshot.puck_state != null:
		var pv: Vector3 = snapshot.puck_state.velocity
		_one_timer_feed = Vector2(pv.x - self_v.x, pv.z - self_v.z)
	# COMMIT the direction (input.bot_slapper_aim_dir): release_point → net_hole
	# plus the committed execution error, led against the feed's pull at the
	# power the swing will have built when it meets the puck. Never aim through
	# the cursor: the human lock measures from the strike spot, off the body, so
	# no cursor placement cancels the offset. The cursor points the way the
	# stance faces for that line, so the stance (Shift) opens the hips side-on to it.
	var shot_vec: Vector3 = net_hole - release_point
	var clean_aim: Vector3 = _apply_committed_aim_error(self_pos, self_pos + shot_vec)
	var committed_dir := Vector3(
			clean_aim.x - self_pos.x, 0.0, clean_aim.z - self_pos.z)
	var shot_line := Vector2.ZERO
	if committed_dir.length_squared() > 0.0001:
		shot_line = Vector2(committed_dir.x, committed_dir.z).normalized()
		var charge_at_contact: float = _one_timer_charge_s + (0.0 if have_puck else feed_s)
		var swing: Vector2 = _one_timer.swing_for(shot_line, _one_timer_feed,
				_one_timer.power_after(charge_at_contact))
		input.bot_slapper_aim_dir = Vector3(swing.x, 0.0, swing.y)
		var stance: Vector2 = _one_timer.stance_facing(shot_line)
		var reach: float = committed_dir.length()
		input.mouse_world_pos = _step_mouse_face(
				self_pos + Vector3(stance.x, 0.0, stance.y) * reach)
	else:
		input.mouse_world_pos = _step_mouse_face(clean_aim)

	# The press waits until the body can set — hips pivoted into the stance, the
	# circle shuffled onto the line — before the feed gets there
	# (SkaterAgentOneTimer.time_to_set). One whose feed will arrive before a
	# wind-up could open the one-timer's window, still unable to set, catches it
	# instead.
	if not _one_timer_slap_down:
		if shot_line != Vector2.ZERO and _one_timer.time_to_set(
				snapshot, self_pos, shot_line, line_anchor, feed_s) <= maxf(feed_s, _ONE_TICK_S):
			debug_last_decision = "ONE_TIMER"
			input.slap_pressed = true
			_one_timer_slap_down = true
		elif feed_s < _one_timer.min_windup_s():
			# Nothing was pressed yet, so there's no charge to cancel.
			debug_last_decision = "ONE_TIMER_ABORT_WIDE"
			_set_state(_post_puck_lost_state(snapshot))
			return

	if have_puck:
		# Attached mid-charge (SLAPPER_CHARGE_WITH_PUCK): drop the button and
		# release_slapper fires. CARRY is one tick of cleanup.
		input.slap_held = false
		_set_state(State.CARRY)
		return

	if _one_timer.puck_at_zone(snapshot, self_pos, _attacking_goal_pos):
		# On the centre beat but not attached: drop the button and let the
		# controller's release buffer sweep the leniency zone.
		input.slap_held = false
		_set_state(_post_puck_lost_state(snapshot))
		return

	if not line_anchor.is_finite():
		# The feed died (picked off, deflected, or crossed outside the zone):
		# drop the swing — a visible whiff — and get back into the play.
		input.slap_held = false
		_set_state(_post_puck_lost_state(snapshot))
		return

	# Feed still inbound — keep the wind-up building (once pressed).
	input.slap_held = _one_timer_slap_down
	if _one_timer_slap_down:
		_one_timer_charge_s += input.delta
	_one_timer_press_tick += 1

	# Budget backstop (see ONE_TIMER_PRESS_MAX_TICKS) — the dead-feed bail
	# above handles every genuine failure earlier.
	if _one_timer_press_tick >= ONE_TIMER_PRESS_MAX_TICKS:
		input.slap_held = false
		_set_state(_post_puck_lost_state(snapshot))


# Local only: push_one_timer_ready() publishes it to the brain on the main thread
# after dispatch, so the worker never writes team state. Teammates read it from
# the frozen per-frame view, one frame late.
func _set_one_timer_ready(ready: bool) -> void:
	_is_one_timer_ready = ready


# Main-thread collection of this agent's one-timer readiness into the shared
# brain (called by the AI coordinator / duel harness after dispatch). Idempotent:
# pushes the current local flag every frame, so a false erases the entry.
func push_one_timer_ready() -> void:
	if _team_brain != null:
		_team_brain.set_one_timer_ready(_peer_id, _is_one_timer_ready)


# The guard that makes a defensive-zone one-timer impossible: the shooter must be
# fully inside the attacking zone. `-_own_goal_dir * z` is the distance into
# attacking territory.
func _in_attacking_zone(self_pos: Vector3) -> bool:
	return -_own_goal_dir * self_pos.z > GameRules.BLUE_LINE_Z


# True when the puck (projected one tick, for input → controller latency) is
# within _blade_reach AND forward of the bot along the shot aim — a puck behind
# can't be swung through cleanly.
func _puck_in_one_timer_zone(snapshot: WorldSnapshot, self_pos: Vector3) -> bool:
	if snapshot.puck_state == null:
		return false
	if snapshot.real_puck_carrier_peer_id != -1:
		# The REAL carrier, not the debounced one: the pre-armed FINISHER is
		# waiting on this exact feed, so seeing it leave the stick is not a
		# reaction the difficulty delay should slow.
		return false
	var puck_pos: Vector3 = snapshot.puck_state.position
	var puck_vel: Vector3 = snapshot.puck_state.velocity
	var puck_next := Vector3(
			puck_pos.x + puck_vel.x * MOUSE_TICK_DELTA,
			puck_pos.y,
			puck_pos.z + puck_vel.z * MOUSE_TICK_DELTA)
	var to_puck_x: float = puck_next.x - self_pos.x
	var to_puck_z: float = puck_next.z - self_pos.z
	var dist_sq: float = to_puck_x * to_puck_x + to_puck_z * to_puck_z
	if dist_sq > _blade_reach * _blade_reach:
		return false
	# Zero lookahead: one-timers fire on contact.
	var clean_aim: Vector3 = _shot_aim_point(snapshot, self_pos, 0.0)
	var aim_x: float = clean_aim.x - self_pos.x
	var aim_z: float = clean_aim.z - self_pos.z
	return aim_x * to_puck_x + aim_z * to_puck_z > 0.0


# Hold-position steering: anchor = self_pos zeroes the seek force so friction
# bleeds momentum, while the repel forces still apply.
func _apply_hold_steering(input: InputState, snapshot: WorldSnapshot, self_pos: Vector3) -> void:
	_apply_steering(input, snapshot, self_pos, self_pos)


# Brake steering: point the anchor behind the current velocity, which trips the
# brake-pivot in _apply_steering (AISteering.should_brake) — far faster than
# coasting. Falls back to hold below BRAKE_STEERING_MIN_SPEED_M_S so the bot
# doesn't glide backward after stopping.
const BRAKE_STEERING_ANCHOR_DIST_M: float = 5.0
const BRAKE_STEERING_MIN_SPEED_M_S: float = 0.5
func _apply_brake_steering(input: InputState, snapshot: WorldSnapshot, self_pos: Vector3) -> void:
	var self_state: SkaterNetworkState = snapshot.skater_states.get(_peer_id)
	if self_state == null:
		_apply_hold_steering(input, snapshot, self_pos)
		return
	var v: Vector3 = self_state.velocity
	var v_mag_sq: float = v.x * v.x + v.z * v.z
	if v_mag_sq < BRAKE_STEERING_MIN_SPEED_M_S * BRAKE_STEERING_MIN_SPEED_M_S:
		_apply_hold_steering(input, snapshot, self_pos)
		return
	var v_mag: float = sqrt(v_mag_sq)
	var brake_anchor: Vector3 = Vector3(
			self_pos.x - v.x / v_mag * BRAKE_STEERING_ANCHOR_DIST_M,
			0.0,
			self_pos.z - v.z / v_mag * BRAKE_STEERING_ANCHOR_DIST_M)
	_apply_steering(input, snapshot, self_pos, brake_anchor)


# The pass aim: the dump target, else the receiver's lead (AIPassLead). Falls
# back to the goal if the receiver disappeared between picking and pressing.
func _pass_aim_point(snapshot: WorldSnapshot, self_pos: Vector3) -> Vector3:
	# Dump: aim at the fixed location, not a receiver lead. Checked first so a
	# stale _pass_target_peer_id (never cleared for a dump) can't override it.
	if _dump_target.is_finite():
		return _dump_target
	var receiver: SkaterNetworkState = snapshot.skater_states.get(_pass_target_peer_id)
	if receiver == null:
		return _attacking_goal_pos
	# Lead at the launch speed the controller will actually fire at.
	var pass_speed: float = _pass_target_speed
	var accel: Vector3 = _accel_ref.get(_pass_target_peer_id, Vector3.ZERO)
	# Shared with the carrier's pass scoring, so the fired aim is the scored one.
	# Origin = the carried PUCK (the real release point), as the scoring uses;
	# leading from the body centre over-leads close feeds.
	var receiver_caps: AISkaterCaps = _caps_by_peer.get(_pass_target_peer_id)
	var origin: Vector3 = self_pos
	if snapshot.puck_state != null and snapshot.puck_state.carrier_peer_id == _peer_id:
		origin = Vector3(
				snapshot.puck_state.position.x, 0.0, snapshot.puck_state.position.z)
	var lead: Vector3 = AIPassLead.lead_point(
			origin, receiver, accel, pass_speed, AICarrierPassSearch.PASS_LEAD_MAX_S, receiver_caps)
	# Net guard on the FIRED lane: the scored lane was net-checked at commit, but
	# the lead re-solves every tick and a receiver drifting near the net plane can
	# walk it into the cage (the classic behind-the-net feed that rings off the
	# outside of the frame). If the led lane crosses a net but the receiver's body
	# line doesn't, fire at the body — a catch on the tape beats a clank.
	if AINetObstacle.pass_lane_blocked_by_net(origin, lead) \
			and not AINetObstacle.pass_lane_blocked_by_net(origin, receiver.position):
		return Vector3(receiver.position.x, 0.0, receiver.position.z)
	return lead


# Steers the body toward `anchor` (SkaterAgentSteering). `arrive` opts into the
# arrival brake: station-keeping callers (off-puck role destinations) brake to
# STOP at the anchor; waypoint-style callers (carry steps, puck chase, check
# commits, tag-up) re-pick the anchor continuously or want to arrive at speed.
func _apply_steering(input: InputState, snapshot: WorldSnapshot, self_pos: Vector3,
		anchor: Vector3, arrive: bool = false, velocity_match_speed: float = 0.0,
		anchor_velocity: Vector3 = Vector3.ZERO,
		engaged_peer_id: int = -1,
		retreat_floor_center: Vector3 = Vector3.ZERO,
		retreat_floor_radius: float = 0.0, advance_cap: float = INF) -> void:
	_steering.steer(input, snapshot, self_pos, anchor, arrive, velocity_match_speed,
			anchor_velocity, engaged_peer_id, retreat_floor_center, retreat_floor_radius,
			_attacking_goal_pos, _upright_lateral_accel(), _blade_reach, advance_cap)


# Body-level offside guard: keep an attacking non-carrier's momentum-driven body
# short of the attacking blue line before the puck (instant ghost in ARCADE), and
# a team owing an NHL tag-up out entirely (Scripts/ai/CLAUDE.md → Who may play
# the puck). SkaterAgent.tick runs it every tick as the LAST write to the move.
func apply_offside_guard(input: InputState, snapshot: WorldSnapshot) -> void:
	if snapshot == null or snapshot.puck_state == null:
		return
	var self_state: SkaterNetworkState = snapshot.skater_states.get(_peer_id)
	if self_state == null:
		return
	var puck_pos: Vector3 = snapshot.puck_state.position
	var team_offside: bool = _teammate_must_tag_up(snapshot)
	var is_carrier: bool = snapshot.real_puck_carrier_peer_id == _peer_id
	var hold_entry: bool = is_carrier and team_offside
	input.move_vector = AISteering.offside_brake(
			input.move_vector, puck_pos if hold_entry else self_state.position,
			self_state.velocity, _own_goal_dir, puck_pos.z,
			is_carrier and not hold_entry, team_offside)


# Opponent peer ids, read straight from the per-frame roster cache published by
# GameManager._enrich_snapshot_for_ai (no allocation, no per-peer team lookup).
# Falls back to a live partition into a reused buffer when the cache is empty
# (unit tests); production on the host always hits the cache.
func _opponent_ids(snapshot: WorldSnapshot) -> Array:
	var opp_team: int = 1 - _team_id
	if snapshot.teammate_ids_by_team.has(opp_team):
		return snapshot.teammate_ids_by_team[opp_team]
	_scratch_opp_ids.clear()
	for pid: int in snapshot.skater_states:
		if pid != _peer_id and _team_id_by_peer.get(pid, -1) != _team_id:
			_scratch_opp_ids.append(pid)
	return _scratch_opp_ids


# Returns the opposing goalie's CURRENT world position. Used as input
# to AIGoalieModel.predict_goalie_pos, which models the goalie's
# react-then-slide forward along the puck's lateral target. Falls back
# to _attacking_goal_pos when goalie state isn't buffered yet (first-
# frame edge case); downstream geometry handles that gracefully.
func _goalie_now(snapshot: WorldSnapshot) -> Vector3:
	var opp_goalie: GoalieNetworkState = snapshot.goalie_states.get(1 - _team_id)
	if opp_goalie == null:
		return _attacking_goal_pos
	return Vector3(opp_goalie.position_x, 0.0, opp_goalie.position_z)


# Our OWN goalie's current world position, or Vector3.INF when its state isn't
# buffered yet (for the carry cursor's goalie cradle).
func _own_goalie_now(snapshot: WorldSnapshot) -> Vector3:
	var own_goalie: GoalieNetworkState = snapshot.goalie_states.get(_team_id)
	if own_goalie == null:
		return Vector3.INF
	return Vector3(own_goalie.position_x, 0.0, own_goalie.position_z)


# Wraps AIGoalieModel.predict_goalie_pos for the common case where
# the puck-at-release is the position we're scoring a shot from.
# `release_time_s` is the time from now until the bot fires (e.g.,
# wrister charge time + any path/flight time before the fire).
func _predict_goalie_at(snapshot: WorldSnapshot, release_time_s: float,
		puck_pos_at_release: Vector3) -> Vector3:
	return AIGoalieModel.predict_goalie_pos(
			_goalie_now(snapshot), _attacking_goal_pos,
			release_time_s, puck_pos_at_release)


# CARRY-state mouse target: the shot aim while a live shot look dominates, else
# the carry aim (_carry_mouse_aim). Tracking the shot continuously during CARRY
# means facing is already aligned when the carrier commits, so pre-aim convergence
# is near-instant. Pass-favored ticks fall through to the carry aim: the best pass
# can flip per tick between teammates spread across the rink, and predictively
# rotating toward each one twists the body back and forth. Passes still pre-aim
# inside the press-state handler.
#
# CRITICAL: the returned point must be where _aim_target_for_intent's pre-aim
# will put the cursor (the shot's hold, else the CARRY_BLADE_AIM_FORWARD_M
# ring). If the two differ, the mouse target jumps at commit and the
# motion-limited cursor can blow past INTENT_MAX_WAIT_TICKS, timing out pre-aim.
func _carry_aim_track_fire(snapshot: WorldSnapshot, self_pos: Vector3) -> Vector3:
	const FIRE_AIM_THRESHOLD: float = 0.05
	# Debounce band for the aim-mode flip (see _carry_tracking_fire). ABSOLUTE,
	# not the proportional AIActionScoring.ACTION_HYSTERESIS_MARGIN_FRAC: it filters
	# wobble around the fixed FIRE_AIM_THRESHOLD, and a fraction of a near-zero
	# score would be a near-zero band.
	const FIRE_AIM_HYSTERESIS_BAND: float = 0.05
	var best_shot_score: float = debug_shoot_score
	# Entry requires being CLEARLY past the thresholds; exit CLEARLY below them.
	var margin: float = FIRE_AIM_HYSTERESIS_BAND
	var threshold_gate: float
	var pass_gate: float
	if _carry_tracking_fire:
		threshold_gate = FIRE_AIM_THRESHOLD - margin
		pass_gate = debug_pass_score - margin
	else:
		threshold_gate = FIRE_AIM_THRESHOLD + margin
		pass_gate = debug_pass_score + margin
	var should_track: bool = (best_shot_score >= threshold_gate
			and best_shot_score >= pass_gate)
	_carry_tracking_fire = should_track
	if not should_track:
		return _carry_mouse_aim(snapshot, self_pos)
	# Hold the puck where the live shot look fires from, so the press finds it
	# loaded.
	if _carrier.shoot_now_hold != Vector3.ZERO:
		return self_pos + _carrier.shoot_now_hold
	return _aim_ring_toward(self_pos, _shot_aim_point(snapshot, self_pos))


# Computes and steps the CARRY-intent mouse cursor: the carry-or-fire track aim.
# A front-hemisphere reach steps FRONT; a turn-around (target BEHIND the body)
# steps ARC. Its callees only READ
# dispatch-throttled state, so the skipped-tick path may call it every physics
# tick.
func _step_carry_cursor(input: InputState, snapshot: WorldSnapshot,
		self_pos: Vector3, self_state: SkaterNetworkState) -> void:
	var mouse_target: Vector3 = _carry_aim_track_fire(snapshot, self_pos)
	var to_target := Vector3(mouse_target.x - self_pos.x, 0.0, mouse_target.z - self_pos.z)
	if not _target_is_behind(to_target, self_state):
		# No arc walk on a front reach — clear any long-way orbit latched by a
		# prior turn-around so the next ARC swing re-evaluates from scratch.
		_arc_protect_sign = 0.0
		input.mouse_world_pos = _step_mouse_front(mouse_target)
	elif _carry_tracking_fire and _carrier.shoot_now_hold != Vector3.ZERO:
		input.mouse_world_pos = _step_mouse_hold_arc(mouse_target)
	else:
		input.mouse_world_pos = _step_mouse_aim(mouse_target)


# Forward carry reach, cradled tight when the body is behind/beside EITHER net
# (see CARRY_BEHIND_NET_CRADLE_M). Returns the full reach everywhere else.
func _carry_reach_behind_net(self_pos: Vector3) -> float:
	# Wide of the cage laterally: full reach (the wall margin and
	# net_safe_blade_target own that side).
	if absf(self_pos.x) > GameRules.NET_BACK_HALF_WIDTH + CARRY_BEHIND_NET_LATERAL_M:
		return AIBotMechanics.CARRY_BLADE_AIM_FORWARD_M
	# Signed distance PAST a goal line toward its end boards (>0 = behind that
	# net). BOTH nets cradle: behind our own, a puck popped loose by the cage is
	# loose in our crease.
	var past_att: float = (self_pos.z - _attacking_goal_pos.z) * (-_own_goal_dir)
	var past_own: float = (self_pos.z - _own_goal_dir * GameRules.GOAL_LINE_Z) * _own_goal_dir
	var past: float = maxf(past_att, past_own)
	# Ramp: full reach until a band's width in front of the line, tight cradle at
	# or behind it.
	var t: float = clampf((past + CARRY_BEHIND_NET_BAND_M) / CARRY_BEHIND_NET_BAND_M, 0.0, 1.0)
	return lerpf(AIBotMechanics.CARRY_BLADE_AIM_FORWARD_M, CARRY_BEHIND_NET_CRADLE_M, t)


func _carry_mouse_aim(snapshot: WorldSnapshot, self_pos: Vector3) -> Vector3:
	# Goalie cradle: within _blade_reach of EITHER goalie, the forward aim drives
	# the blade through him, and stick-on-goalie contact dislodges the puck — a
	# feedback loop, since the bot reacquires it and aims forward again. Parking
	# the cursor on the body holds the blade tight with zero extension; facing is
	# held (zero direction), so the bot backs out facing the play.
	var goalie_pos: Vector3 = _goalie_now(snapshot)
	if self_pos.distance_to(goalie_pos) < _blade_reach:
		return self_pos
	var own_goalie_pos: Vector3 = _own_goalie_now(snapshot)
	if own_goalie_pos.is_finite() and self_pos.distance_to(own_goalie_pos) < _blade_reach:
		return self_pos

	var to_goal: Vector3 = _attacking_goal_pos - self_pos
	to_goal.y = 0.0
	var forward_dir: Vector3
	# Attacking direction is -_own_goal_dir along z. Fall back to it past the
	# attacking goal line, where `to_goal` points back down the rink.
	var attacking_z: float = -_own_goal_dir
	if to_goal.length_squared() > 0.0001 and to_goal.z * attacking_z > 0.0:
		forward_dir = to_goal.normalized()
	else:
		forward_dir = Vector3(0.0, 0.0, attacking_z)
	# O-ZONE SQUARE: in the offensive zone with no man to beat, face the GOALIE —
	# square to the net, every shot/pass option open. Owns the facing outright.
	#
	# FACE THE ROUTE otherwise: while driving somewhere, face the carry anchor, not
	# the goal — speed classes are facing-relative (forward > crossover >
	# backward), so goal-facing down a lateral route skates it in the slow
	# crossover class. The goal-facing default keeps a route too short to define a
	# direction and a genuine RETREAT (below CARRY_FACE_RETREAT_ADVANCE), which
	# backs out facing the play. Fire-tracking overrides all of this.
	var squared_to_net: bool = false
	if AIActionScoring.in_offensive_zone(self_pos, _attacking_goal_pos) \
			and not _has_man_to_beat():
		var goalie_square: Vector3 = _goalie_now(snapshot)
		var to_goalie: Vector3 = goalie_square - self_pos
		to_goalie.y = 0.0
		if to_goalie.length_squared() > 0.0001:
			forward_dir = to_goalie.normalized()
			squared_to_net = true
	var route: Vector3 = _last_carry_anchor - self_pos
	route.y = 0.0
	if not squared_to_net \
			and route.length_squared() >= CARRY_FACE_ROUTE_MIN_DIST_M * CARRY_FACE_ROUTE_MIN_DIST_M:
		var route_dir: Vector3 = route.normalized()
		if route_dir.z * attacking_z >= CARRY_FACE_RETREAT_ADVANCE:
			forward_dir = route_dir
	# Cradled tight behind/beside a net (_carry_reach_behind_net).
	var reach: float = _carry_reach_behind_net(self_pos)
	var base: Vector3 = self_pos + forward_dir * reach
	# Stickhandling offset is raw; the slew-limited cursor step smooths it. Folded
	# in BEFORE the protect blend, so a blade pinned to the protect seam isn't
	# pulled back into the checker's reach.
	var target: Vector3 = base + _stickhandle_offset(snapshot, self_pos, forward_dir)
	# Puck protection: blend the blade from the presented-forward carry toward
	# the carrier's protect seam, weighted by its protect_gain (the safety the
	# shield buys — see Scripts/domain/ai/CLAUDE.md → Carry safety). The seam
	# direction is re-based on the LIVE body and projected out to the carry
	# reach. The low-pass runs every tick, raw zero included, so a disengaging
	# shield decays smoothly.
	var raw_gain: float = _carrier.protect_gain if _protects_the_puck else 0.0
	var raw_offset: Vector3 = _carrier.protect_offset if _protects_the_puck else Vector3.ZERO
	var smooth_t: float = clampf(CARRY_PROTECT_SMOOTH_RATE * _current_delta, 0.0, 1.0)
	_carry_protect_gain_smooth = lerpf(_carry_protect_gain_smooth, raw_gain, smooth_t)
	_carry_protect_offset_smooth = _carry_protect_offset_smooth.lerp(raw_offset, smooth_t)
	var protect_w: float = _carry_protect_gain_smooth
	if _protects_the_puck and protect_w > 0.0:
		var protect_dir: Vector3 = _carry_protect_offset_smooth
		protect_dir.y = 0.0
		if protect_dir.length_squared() > 0.0025:
			# Shield with REACH, not a spin: clamp how far the protect aim swings off
			# the play line (CARRY_PROTECT_MAX_TURN_DEG). The body turns only to
			# side-on to interpose; the blade ROM covers the rest of the seam.
			var prot2 := Vector2(protect_dir.x, protect_dir.z).normalized()
			var fwd2 := Vector2(forward_dir.x, forward_dir.z)
			if fwd2.length_squared() > 0.0001:
				fwd2 = fwd2.normalized()
				var turn: float = fwd2.angle_to(prot2)
				var max_turn: float = deg_to_rad(CARRY_PROTECT_MAX_TURN_DEG)
				if absf(turn) > max_turn:
					prot2 = fwd2.rotated(signf(turn) * max_turn)
			var protect_target: Vector3 = self_pos \
					+ Vector3(prot2.x, 0.0, prot2.y) * reach
			target = target.lerp(protect_target, minf(protect_w, 1.0))
	# Keep the target on the rink side of the attacking goal line, or the blade
	# punches through the net.
	var goal_line_z: float = _attacking_goal_pos.z
	var max_forward_z: float = goal_line_z + AIStationSearch.GOAL_LINE_BUFFER_M * _own_goal_dir
	if (target.z - max_forward_z) * _own_goal_dir < 0.0:
		target.z = max_forward_z
	# ...and inside the boards (CARRY_BLADE_WALL_MARGIN_M), clamped after every
	# offset above, none of which is wall-aware.
	var on_ice: Vector2 = GameRules.clamp_to_rink_inner(
			Vector2(target.x, target.z), AIBotMechanics.CARRY_BLADE_WALL_MARGIN_M)
	target.x = on_ice.x
	target.z = on_ice.y
	# ...and never THROUGH a net frame: the chord swings around the nearer post.
	return AINetObstacle.net_safe_blade_target(self_pos, target)


# True while the presented-forward puck is inside somebody's reach — there is
# still a man to beat. Reads AIRoleCarrier.forward_puck_clearance, the
# reachable-set clearance against every un-beaten defender's momentum-projected
# stick, which is the SAME read the shield's necessity half runs, so body and
# stick never disagree about whether the man is beaten. Reach answers "have I
# beaten him?" as a closing-rate question: a chaser losing ground can't get
# there, and a defender abreast and wide can't reach the puck in time.
func _has_man_to_beat() -> bool:
	# Sticky: an engaged man must open the bar plus the hysteresis to be beaten.
	var bar: float = CARRY_MAN_TO_BEAT_CLEAR_M
	if _carry_has_man:
		bar += CARRY_MAN_TO_BEAT_HYSTERESIS_M
	_carry_has_man = _carrier.forward_puck_clearance < bar
	return _carry_has_man


# The stickhandling offset: perpendicular to `forward_dir`, away from the summed
# signed-lateral pull of every opposing blade within STICKHANDLE_THREAT_RADIUS_M of
# our puck, clamped to STICKHANDLE_OFFSET_MAX_M. A sum rather than the nearest
# threat, which can swap per tick and snap the offset side to side: opposite
# threats cancel (blade holds central) and threats dead ahead contribute ~0.
#
# `blade_contact_world` is host-only, which is safe because bots only run on the
# host; ZERO (before SkaterController populates it) falls back to the body.
func _stickhandle_offset(snapshot: WorldSnapshot, self_pos: Vector3, forward_dir: Vector3) -> Vector3:
	var right_axis: Vector3 = Vector3(forward_dir.z, 0.0, -forward_dir.x)
	# Threat distance is measured from the carried puck, not the body.
	var carry_pos: Vector3 = self_pos + forward_dir * AIBotMechanics.CARRY_BLADE_AIM_FORWARD_M
	# Positive = pull toward +right_axis (away from a threat on the left).
	var lateral_force: float = 0.0
	for peer_id: int in _opponent_ids(snapshot):
		var opp_state: SkaterNetworkState = snapshot.skater_states[peer_id]
		var threat_pos: Vector3 = opp_state.blade_contact_world
		if threat_pos == Vector3.ZERO:
			threat_pos = opp_state.position
		var to_threat: Vector3 = threat_pos - carry_pos
		to_threat.y = 0.0
		var dist: float = to_threat.length()
		if dist > STICKHANDLE_THREAT_RADIUS_M or dist < 0.001:
			continue
		var ramp: float = clampf(inverse_lerp(
				STICKHANDLE_THREAT_RADIUS_M,
				STICKHANDLE_FULL_OFFSET_RADIUS_M,
				dist), 0.0, 1.0)
		# Lateral component of the unit direction toward the threat, in [-1, 1].
		var lateral_unit: float = right_axis.dot(to_threat) / dist
		lateral_force -= lateral_unit * ramp
	var magnitude: float = clampf(lateral_force, -1.0, 1.0) * STICKHANDLE_OFFSET_MAX_M
	return right_axis * magnitude


# What the upright edges can turn: the movement core's turn_accel × our grip.
func _upright_lateral_accel() -> float:
	return GameRules.DEFAULT_SKATER_TURN_ACCEL_M_S2 * _self_lateral_grip


# Stick play (SkaterAgentStickPlay): these gather the bot's role, gates and reaches.
func _poke_jab_aim(snapshot: WorldSnapshot, self_pos: Vector3) -> Vector3:
	return _stick_play.jab_aim(snapshot, self_pos, _is_puck_pressurer_slot(snapshot),
			_lifts_sticks, _stick_lift_reach, _poke_jab_reach, _dispatch_period_ticks)


func _jab_target(snapshot: WorldSnapshot) -> Vector3:
	return _stick_play.jab_target(snapshot)


func _stick_tie_aim(snapshot: WorldSnapshot, self_pos: Vector3,
		self_state: SkaterNetworkState, decision: RoleDecision) -> Vector3:
	return _stick_play.tie_aim(snapshot, self_pos, self_state, decision, _ties_sticks,
			_stick_lift_reach, _blade_reach)


func _tie_yank_aim(snapshot: WorldSnapshot, self_pos: Vector3,
		self_state: SkaterNetworkState) -> Vector3:
	return _stick_play.tie_yank_aim(snapshot, self_pos, self_state, _ties_sticks, _blade_reach)


# Meeting a carrier about to skate into us with the shoulder
# (SkaterAgentStandUp), every physics tick after dispatch and before the board
# play, which may turn that check at the wall into a pin.
func apply_stand_up(input: InputState, snapshot: WorldSnapshot) -> void:
	_stand_up.apply(input, snapshot, _check_aggression)


# The boards, every physics tick after dispatch (SkaterAgentBoardPlay).
func apply_board_play(input: InputState, snapshot: WorldSnapshot) -> void:
	_board_play.apply(input, snapshot, _own_goal_dir, _check_aggression,
			_state == State.CARRY and _protects_the_puck, _chase_max_accel)


# Shot blocks and the 2-on-1 dive (SkaterAgentShotBlock), every physics tick
# after dispatch, so a held block is continuous. A carrier never blocks.
func apply_shot_block(input: InputState, snapshot: WorldSnapshot) -> void:
	if not _blocks_shots or _state == State.CARRY:
		return
	var rush: AIRushRead = _current_strategy.get_rush_read() if _current_strategy != null \
			else _inert_rush_read
	_shot_block.apply(input, snapshot, _own_goal_dir, rush, _blade_reach, _chase_max_accel)


# The press (SkaterAgentPress), every physics tick after the other body and stick
# passes; true when it took the body. The screener's dig-in and the carrier's
# drive through a man ride the protects_the_puck gate: answering a physical
# threat to what we hold.
func apply_press(input: InputState, snapshot: WorldSnapshot) -> bool:
	return _press.apply(input, snapshot, _own_goal_dir,
			_cached_role_decision.locked_man_pid if _cached_role_decision != null else -1,
			_check_aggression, _protects_the_puck, _state == State.CARRY)


# Holds the stick-check button for a lift or a tie the dispatch started, every
# physics tick after dispatch.
func apply_stick_lift_input(input: InputState) -> void:
	_stick_play.apply_button(input, _state == State.OFF_PUCK)


# True if our current role is on the puck defensively — the only roles that jab:
# the PRESSURER slots (AIRoleSlots.pressures_puck), a station role pressuring
# this beat, and in the 5v5 zone the one area role that owns the puck
# (AIZoneCoverage.pressure_owner).
func _is_puck_pressurer_slot(snapshot: WorldSnapshot) -> bool:
	if _current_strategy == null:
		return false
	if _cached_role_decision != null and _cached_role_decision.pressures_puck:
		return true   # a station role on the carrier this beat (the pinching D)
	var slot: int = _current_strategy.get_slot(_peer_id)
	return AIRoleSlots.pressures_puck(slot) or _owns_zone_pressure(slot, snapshot)


# Whether `slot` is the 5v5 zone area that owns the puck this tick
# (AIZoneCoverage.pressure_owner). Ownership moves with the puck, so it is
# resolved per call, never fixed to a slot.
func _owns_zone_pressure(slot: int, snapshot: WorldSnapshot) -> bool:
	if not AIRoleSlots5.is_zone_slot(slot) or snapshot == null \
			or snapshot.puck_state == null:
		return false
	var strong_x: float = _current_strategy.strong_x() if _current_strategy != null \
			else 1.0
	return AIZoneCoverage.pressure_owner(strong_x, _own_goal_dir * GameRules.GOAL_LINE_Z,
			snapshot.puck_state.position) == slot


# The carried puck's position (the jab aim point), or INF with no carrier.
func _carrier_puck_pos(snapshot: WorldSnapshot) -> Vector3:
	if snapshot.puck_state == null or snapshot.puck_state.carrier_peer_id == -1:
		return Vector3.INF
	return snapshot.puck_state.position


# Shot aim past the goalie's shadow predicted `release_lookahead_s` from now (the
# wrister window by default; 0 for a contact release). The goalie's CURRENT
# lateral velocity biases the aim back across the grain — unless this tier is
# goalie-motion blind (_reads_goalie_motion).
func _shot_aim_point(snapshot: WorldSnapshot, self_pos: Vector3,
		release_lookahead_s: float = AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S) -> Vector3:
	var goalie: Vector3 = _predict_goalie_at(
			snapshot, release_lookahead_s, self_pos)
	var goalie_vx: float = 0.0
	var opp_team_id: int = 1 - _team_id
	var opp_goalie_state: GoalieNetworkState = snapshot.goalie_states.get(opp_team_id)
	if opp_goalie_state != null and _reads_goalie_motion:
		goalie_vx = opp_goalie_state.velocity_x
	return AIShotAim.compute_open_net_aim(
			self_pos, goalie,
			_attacking_goal_pos.z,
			GameRules.NET_HALF_WIDTH,
			AIGoalieModel.GOALIE_SHADOW_HALF_M,
			AIShotAim.DEFAULT_CORNER_BIAS,
			goalie_vx)


# OFF_PUCK ready-stance aim (_ready_stance_aim): a target
# READY_STANCE_AIM_FORWARD_M out, FACE-stepped.
#   - FAR from the anchor: toward the anchor — thrust scales with facing
#     alignment (SkaterMovementRules), so this is full skating speed.
#   - NEAR: toward the threat (the puck), eyes on the play.
# The near threshold is ~0.6 s of skating at top speed: a move that long is a
# committed skate; shorter is positioning. Tighter leaves station-keeping bots
# forever "far" from a drifting anchor, looking away from the play.
const READY_STANCE_AIM_FORWARD_M: float = 2.0
const FACE_THREAT_NEAR_ANCHOR_M: float = 6.0
# Debounce band around the far/near threshold, so a bot orbiting the boundary
# doesn't swing the blade between the anchor and the puck every tick (the aim
# refreshes at the physics rate).
const FACE_NEAR_ANCHOR_HYSTERESIS_M: float = 0.75
# Below this puck→self distance the direction is too short to aim by, so the
# threat read holds current facing (_face_threat_or_current); debounced by
# FACE_THREAT_MIN_DIST_HYSTERESIS_M.
const FACE_THREAT_MIN_DIST_M: float = 0.3
const FACE_THREAT_MIN_DIST_HYSTERESIS_M: float = 0.15
# Tag-up override: a ghosted bot racing back to the blue line faces its
# travel direction until nearly there — the tag-up is a race, not
# positioning, so it keeps a tight face-travel threshold.
const FACE_TRAVEL_TAG_UP_NEAR_M: float = 2.0

# Persistent cursor position, stepped by `_step_mouse_internal`. The first call
# snaps to the target; the bool (not `_mouse_pos == ZERO`) gates the snap, since
# a legitimate target at the world origin would otherwise re-trigger it.
var _mouse_pos: Vector3 = Vector3.ZERO
var _mouse_pos_initialized: bool = false


# Cursor-shaping modes for `_step_mouse_internal`, which steps `_mouse_pos` toward
# the shaped target at the slew cap (the first call snaps):
#   DIRECT — chord straight toward the target. Press states (the wrister windup
#            interpolates a specific blade path an arc would distort, and facing
#            is locked during a press anyway) and the chase's CLOSE-RANGE aims —
#            the puck inside blade reach, the blade gate on a fast puck's line —
#            where the exact point matters for the pickup and a ring projection
#            would overshoot it.
#   ARC    — walk the target around the body ring at the blade slew (CARRY / blade
#            pre-aim), keeping the mouse-body angle inside the pose coordinator's
#            IK gate (~157°) mid-swing. A single straight chord across self_pos —
#            a target that flipped 180°, or exiting a back-pass press with the
#            cursor parked behind the body — trips that gate and leaves facing
#            permanently locked opposite to where the bot is skating.
#   FACE   — snap the cursor to where the bot wants to point, clamped to the
#            reachable cone; facing_drag_speed is the sole turn limit.
#   FRONT  — DIRECT while the line to the target clears the body; when it would
#            run the puck through the skater, walk BladeRoute around the front at
#            the slew, measured off the body so the route rides it.
#   HOLD_ARC — ARC on the target's own ring rather than the aim ring, so a swing
#            to a charged release's hold behind the body lands on the hold.
const _STEP_DIRECT: int = 0
const _STEP_ARC: int = 1
const _STEP_FACE: int = 2
const _STEP_FRONT: int = 3
const _STEP_HOLD_ARC: int = 4

func _step_mouse_aim(target: Vector3) -> Vector3:
	return _step_mouse_internal(target, _STEP_ARC, _mouse_max_speed_m_s, _mouse_arc_rate_rad_s)


# Body-FACING aim (off-puck ready stance, tag-up, one-timer/jab/tie aims): the
# cursor goes DIRECTLY where the bot wants to point, like a human flicking the
# mouse (_face_ring_point); facing_drag_speed
# is the one rotation limit, as for a human. Any implied blade motion stays
# clamped to the real max_blade_speed downstream.
func _step_mouse_face(target: Vector3) -> Vector3:
	return _step_mouse_internal(target, _STEP_FACE, MOUSE_MAX_SPEED_M_S, MOUSE_ARC_RATE_RAD_S)


func _step_mouse_toward(target: Vector3) -> Vector3:
	return _step_mouse_internal(target, _STEP_DIRECT, _mouse_max_speed_m_s, _mouse_arc_rate_rad_s)


# A carried puck's reach to a spot in front of the body (see _STEP_FRONT).
func _step_mouse_front(target: Vector3) -> Vector3:
	return _step_mouse_internal(target, _STEP_FRONT, _mouse_max_speed_m_s, _mouse_arc_rate_rad_s)


# A carried puck's swing to a charged release's hold behind the body.
func _step_mouse_hold_arc(target: Vector3) -> Vector3:
	return _step_mouse_internal(target, _STEP_HOLD_ARC, _mouse_max_speed_m_s,
			_mouse_arc_rate_rad_s)


# Sample this release's execution error (radians, uniform ±budget), once per
# press-state entry. A zero budget returns 0 WITHOUT advancing the RNG, keeping
# raw test agents bit-deterministic.
func _sample_aim_error_rad(budget_rad: float) -> float:
	if budget_rad == 0.0:
		return 0.0
	return _rng.randf_range(-1.0, 1.0) * budget_rad


# Sample this shot's late-release hold (ticks past the completed charge), uniform
# in [0, max]. The eval budgeted the MEAN (max/2, RoleContext.shot_timing_error_s)
# into the goalie's tracking time, so thin windows are attempted and the draw
# decides them; the worst case would prune them all. Zero variance returns 0
# without advancing the RNG.
func _sample_release_hold_ticks() -> int:
	if _shot_timing_error_s == 0.0:
		return 0
	return _rng.randi_range(
			0, int(round(_shot_timing_error_s * _PhysicsConstants.PHYSICS_TICK)))


# Rotate an aim point around `pivot` by the committed per-release error.
# Applied to press-state aim geometry only — the error is a property of the
# RELEASE gesture, not of tracking (which stays clean and smooth).
func _apply_committed_aim_error(pivot: Vector3, aim_point: Vector3) -> Vector3:
	if _committed_aim_error_rad == 0.0:
		return aim_point
	var offset: Vector3 = aim_point - pivot
	return pivot + offset.rotated(Vector3.UP, _committed_aim_error_rad)


func _step_mouse_internal(target: Vector3, mode: int,
		max_speed: float, arc_rate: float) -> Vector3:
	# Cache the FINAL un-shaped target, mode and rates so skipped ticks re-shape
	# fresh every physics frame, or a swing would take dispatch-period× too long.
	_cached_aim_target = target
	_has_cached_aim_target = true
	_cached_aim_mode = mode
	_cached_aim_max_speed = max_speed
	_cached_aim_arc_rate = arc_rate
	var step_target: Vector3 = target
	if mode == _STEP_ARC:
		step_target = _arc_step_mouse_target(
				_current_self_pos, target, _current_self_state, arc_rate)
	elif mode == _STEP_HOLD_ARC:
		step_target = _arc_step_mouse_target(
				_current_self_pos, target, _current_self_state, arc_rate,
				Vector2(target.x - _current_self_pos.x, target.z - _current_self_pos.z).length())
	elif mode == _STEP_FACE:
		# Snap the cursor to the clamped point (facing_drag_speed does all the
		# smoothing), so return straight out without the linear slew below.
		step_target = _face_ring_point(_current_self_pos, target)
		_mouse_pos = Vector3(step_target.x, 0.0, step_target.z)
		_mouse_pos_initialized = true
		return Vector3(_mouse_pos.x, 0.0, _mouse_pos.z)
	elif mode == _STEP_FRONT and _mouse_pos_initialized and _current_self_state != null:
		var from := Vector2(_mouse_pos.x - _current_self_pos.x, _mouse_pos.z - _current_self_pos.z)
		var to := Vector2(target.x - _current_self_pos.x, target.z - _current_self_pos.z)
		var facing: Vector2 = _current_self_state.facing
		if BladeRoute.crosses_body(from, to):
			var at: Vector2 = BladeRoute.point_along(from, to, facing,
					max_speed * MOUSE_TICK_DELTA)
			_mouse_pos = Vector3(_current_self_pos.x + at.x, 0.0, _current_self_pos.z + at.y)
			return Vector3(_mouse_pos.x, 0.0, _mouse_pos.z)
	if not _mouse_pos_initialized:
		_mouse_pos = Vector3(step_target.x, 0.0, step_target.z)
		_mouse_pos_initialized = true
	var to_target_x: float = step_target.x - _mouse_pos.x
	var to_target_z: float = step_target.z - _mouse_pos.z
	var dist: float = sqrt(to_target_x * to_target_x + to_target_z * to_target_z)
	var max_step: float = max_speed * MOUSE_TICK_DELTA
	if dist > max_step:
		var inv: float = 1.0 / dist
		_mouse_pos.x += to_target_x * inv * max_step
		_mouse_pos.z += to_target_z * inv * max_step
	else:
		_mouse_pos.x = step_target.x
		_mouse_pos.z = step_target.z
	# No per-tick noise: execution error moves the TARGET (per release), never
	# the cursor.
	return Vector3(_mouse_pos.x, 0.0, _mouse_pos.z)


# Record the ready-stance anchor + threshold so skipped ticks can re-derive the
# same _ready_stance_aim target. Only the plain ready-stance branches call this.
func _arm_off_puck_live_aim(anchor: Vector3, near_anchor_m: float) -> void:
	_off_puck_aim_live = true
	_off_puck_aim_anchor = anchor
	_off_puck_aim_near_m = near_anchor_m


# The off-puck blade target the dispatch tick would produce from CURRENT
# perception, for the skipped-tick re-derive. INF for the branches not refreshed
# live (one-timer pre-aim, explicit aim override).
func _off_puck_live_aim(snapshot: WorldSnapshot, self_pos: Vector3) -> Vector3:
	if _off_puck_yank_live:
		var me: SkaterNetworkState = snapshot.skater_states.get(_peer_id)
		var yank: Vector3 = _tie_yank_aim(snapshot, self_pos, me)
		if yank.is_finite():
			return yank
	if _off_puck_jab_live:
		return _jab_target(snapshot)
	if _off_puck_tie_live and _cached_role_decision != null:
		var man: SkaterNetworkState = snapshot.skater_states.get(
				_cached_role_decision.locked_man_pid)
		if man != null:
			return _stick_play.step_tie_follow(man)
	if _off_puck_aim_live:
		return _ready_stance_aim(
				self_pos, _off_puck_aim_anchor, snapshot, _off_puck_aim_near_m)
	return Vector3.INF


# The ready-stance target (see READY_STANCE_AIM_FORWARD_M).
func _ready_stance_aim(self_pos: Vector3, anchor: Vector3, snapshot: WorldSnapshot,
		near_anchor_m: float = FACE_THREAT_NEAR_ANCHOR_M) -> Vector3:
	var desired_dir: Vector3 = _compute_desired_aim_dir(
			self_pos, anchor, snapshot, near_anchor_m)
	desired_dir = _deflect_safe_aim_dir(self_pos, desired_dir, snapshot)
	return self_pos + desired_dir * READY_STANCE_AIM_FORWARD_M


# ── Own-net blade discipline ─────────────────────────────────────────────────
# In our own house, a passively parked blade in the puck→our-mouth corridor is a
# deflection surface (glancing contact keeps the along-face pace,
# PuckCollisionRules) and in tight the redirect finds the mouth. So the ready
# stance takes the BLADE out of the shooting lane; the body stays where the role
# put it. Active plays (interceptions, jabs, pickups) keep the blade on the line.

# Depth of the discipline zone from our goal center — the house, where a
# redirect still fits inside the mouth angle (tactical staging constant).
const OWN_NET_BLADE_DISCIPLINE_M: float = 8.0
# Clearance the parked blade keeps off the puck→mouth corridor: a blade
# length plus the puck's contact radius, with a step of margin.
const BLADE_LANE_CLEAR_M: float = (
		GameRules.DEFAULT_BLADE_LENGTH_M + GameRules.PUCK_COLLISION_RADIUS + 0.2)


# Returns `dir` unchanged outside the discipline conditions; otherwise the
# minimal rotation that slides the parked blade point to the edge of the
# puck→our-mouth corridor on its current side.
func _deflect_safe_aim_dir(
		self_pos: Vector3, dir: Vector3, snapshot: WorldSnapshot) -> Vector3:
	if snapshot == null or snapshot.puck_state == null:
		return dir
	# Runs every physics tick per off-puck bot: the cheap house test goes first.
	var own_net := Vector3(0.0, 0.0, _own_goal_dir * GameRules.GOAL_LINE_Z)
	var net_dx: float = own_net.x - self_pos.x
	var net_dz: float = own_net.z - self_pos.z
	if net_dx * net_dx + net_dz * net_dz \
			> OWN_NET_BLADE_DISCIPLINE_M * OWN_NET_BLADE_DISCIPLINE_M:
		return dir
	var carrier: int = snapshot.puck_state.carrier_peer_id
	if carrier != -1 and _team_id_by_peer.get(carrier, -1) == _team_id:
		return dir   # our puck — offensive stance, no lane to guard
	var puck_pos: Vector3 = snapshot.puck_state.position
	var pdx: float = puck_pos.x - self_pos.x
	var pdz: float = puck_pos.z - self_pos.z
	if pdx * pdx + pdz * pdz <= _blade_reach * _blade_reach:
		return dir   # contest range — play the puck, don't concede it
	var lane: Vector3 = own_net - puck_pos
	lane.y = 0.0
	var lane_len: float = lane.length()
	if lane_len < 0.001:
		return dir
	var u: Vector3 = lane / lane_len
	var blade_pt: Vector3 = self_pos + dir * READY_STANCE_AIM_FORWARD_M
	var t: float = (blade_pt.x - puck_pos.x) * u.x \
			+ (blade_pt.z - puck_pos.z) * u.z
	if t <= 0.0 or t >= lane_len:
		return dir   # parked blade outside the corridor's span
	var foot := Vector3(puck_pos.x + u.x * t, 0.0, puck_pos.z + u.z * t)
	var perp := Vector3(blade_pt.x - foot.x, 0.0, blade_pt.z - foot.z)
	var perp_len: float = perp.length()
	if perp_len >= BLADE_LANE_CLEAR_M:
		return dir
	var side: Vector3
	if perp_len > 0.001:
		side = perp / perp_len
	else:
		side = Vector3(-u.z, 0.0, u.x)   # on the line — either edge works
	# Park the blade ON the corridor-edge line at the full stance length:
	# intersect the stance circle (radius READY_STANCE_AIM_FORWARD_M around
	# the body) with the edge line, taking the crossing nearest the original
	# park (least rotation). No crossing → the stance can't reach the edge;
	# hold the blade perpendicular-off for the max clearance available.
	var p0: Vector3 = puck_pos + side * BLADE_LANE_CLEAR_M
	var d0x: float = self_pos.x - p0.x
	var d0z: float = self_pos.z - p0.z
	var along: float = d0x * u.x + d0z * u.z
	var hx: float = d0x - u.x * along
	var hz: float = d0z - u.z * along
	var h_sq: float = hx * hx + hz * hz
	var r_sq: float = READY_STANCE_AIM_FORWARD_M * READY_STANCE_AIM_FORWARD_M
	if h_sq >= r_sq:
		return side
	var half_span: float = sqrt(r_sq - h_sq)
	var s_pick: float = along + half_span if absf(along + half_span - t) \
			< absf(along - half_span - t) else along - half_span
	var safe_dir: Vector3 = p0 + u * s_pick - self_pos
	safe_dir.y = 0.0
	if safe_dir.length_squared() < 0.0001:
		return dir
	return safe_dir.normalized()


# Picks the desired raw aim direction: anchor direction when far,
# threat direction when near anchor — except the OPEN-HIPS catch stance: a
# TEAMMATE has the puck and we're in the offensive zone, so we're a candidate
# receiver, and the stance splits between the play and the net (the puck-net
# bisector — both stay comfortably inside the blade cone). The catch then
# lands with the shot already loaded instead of needing a full post-catch
# rotation toward a net that was at our back. Defensive watching (loose puck
# or an opponent carrier) keeps eyes-on-the-threat.
func _compute_desired_aim_dir(self_pos: Vector3, anchor: Vector3, snapshot: WorldSnapshot,
		near_anchor_m: float = FACE_THREAT_NEAR_ANCHOR_M) -> Vector3:
	var to_anchor: Vector3 = anchor - self_pos
	# Latched far/near flip (FACE_NEAR_ANCHOR_HYSTERESIS_M).
	var dist: float = to_anchor.length()
	if _aim_near_anchor:
		if dist > near_anchor_m + FACE_NEAR_ANCHOR_HYSTERESIS_M:
			_aim_near_anchor = false
	elif dist < near_anchor_m - FACE_NEAR_ANCHOR_HYSTERESIS_M:
		_aim_near_anchor = true
	if not _aim_near_anchor:
		if dist < 0.0001:
			return _face_threat_or_current(snapshot, self_pos)
		return to_anchor.normalized()
	var threat_dir: Vector3 = _face_threat_or_current(snapshot, self_pos)
	if snapshot.puck_state == null:
		return threat_dir
	var carrier: int = snapshot.puck_state.carrier_peer_id
	if carrier == -1 or carrier == _peer_id \
			or _team_id_by_peer.get(carrier, -1) != _team_id \
			or not AIActionScoring.in_offensive_zone(self_pos, _attacking_goal_pos):
		return threat_dir
	var to_net: Vector3 = _attacking_goal_pos - self_pos
	to_net.y = 0.0
	if to_net.length_squared() < 0.01:
		return threat_dir
	var open_hips: Vector3 = threat_dir + to_net.normalized()
	if open_hips.length_squared() < 0.01:
		return threat_dir   # puck and net dead-opposite — degenerate bisector
	return open_hips.normalized()


# Reads the bot's facing as a unit XZ Vector3, with safe fallback.
func _read_facing_3d(snapshot: WorldSnapshot) -> Vector3:
	var self_state: SkaterNetworkState = snapshot.skater_states.get(_peer_id)
	if self_state == null or self_state.facing.length_squared() < 0.0001:
		return Vector3.FORWARD
	return Vector3(self_state.facing.x, 0.0, self_state.facing.y)


# Unit direction toward the defensive threat (the puck). Falls back to current
# facing if the threat is essentially on top of us (avoids a degenerate aim
# direction).
func _face_threat_or_current(snapshot: WorldSnapshot, self_pos: Vector3) -> Vector3:
	var to_puck: Vector3 = snapshot.puck_state.position - self_pos
	var dist: float = to_puck.length()
	# Debounced geometry floor (FACE_THREAT_MIN_DIST_HYSTERESIS_M).
	if _threat_too_close:
		if dist > FACE_THREAT_MIN_DIST_M + FACE_THREAT_MIN_DIST_HYSTERESIS_M:
			_threat_too_close = false
	elif dist < FACE_THREAT_MIN_DIST_M - FACE_THREAT_MIN_DIST_HYSTERESIS_M:
		_threat_too_close = true
	if _threat_too_close or dist < 0.0001:
		return _read_facing_3d(snapshot)
	return to_puck / dist


# True iff any opponent is within `radius` of `self_pos` AND in the forward
# half-plane of `forward_dir` (omnidirectional when forward_dir is degenerate).
# The mid-charge bail check.
func _opponent_within_forward(snapshot: WorldSnapshot, self_pos: Vector3,
		forward_dir: Vector3, radius: float) -> bool:
	var fl: float = sqrt(forward_dir.x * forward_dir.x + forward_dir.z * forward_dir.z)
	var fwd_x: float = 0.0
	var fwd_z: float = 0.0
	var have_dir: bool = fl > 0.001
	if have_dir:
		fwd_x = forward_dir.x / fl
		fwd_z = forward_dir.z / fl
	var r2: float = radius * radius
	for peer_id: int in snapshot.skater_states:
		if _team_id_by_peer.get(peer_id, -1) == _team_id:
			continue
		var pos: Vector3 = snapshot.skater_states[peer_id].position
		var dx: float = pos.x - self_pos.x
		var dz: float = pos.z - self_pos.z
		if dx * dx + dz * dz >= r2:
			continue
		if not have_dir:
			return true   # degenerate forward — fall through to omni
		if dx * fwd_x + dz * fwd_z > 0.0:
			return true
	return false


# Tag-up anchor, current X preserved: until tagged up, the NZ side of our OWN
# blue line, so the bot skates straight back out of the zone
# (InfractionRules.has_tagged_up); OFFSIDE_HOLD_BUFFER_M keeps it off the line.
# Tagged up but still held (NHL: the rest of the team hasn't cleared the zone) →
# wait just outside the ATTACKING blue line.
func _tag_up_anchor(self_pos: Vector3) -> Vector3:
	if InfractionRules.has_tagged_up(self_pos.z, _team_id):
		var hold_z: float = -_own_goal_dir * (GameRules.BLUE_LINE_Z - OFFSIDE_HOLD_BUFFER_M)
		return Vector3(self_pos.x, 0.0, hold_z)
	# Our own blue line is at +z for team 0, -z for team 1. NZ side of
	# it means slightly less depth (toward midrink, away from own goal).
	var z: float = _own_goal_dir * (GameRules.BLUE_LINE_Z - OFFSIDE_HOLD_BUFFER_M)
	return Vector3(self_pos.x, 0.0, z)


func _teammate_must_tag_up(snapshot: WorldSnapshot) -> bool:
	if snapshot.tag_up_peers.is_empty() or not snapshot.teammate_ids_by_team.has(_team_id):
		return false
	var mates: Array = snapshot.teammate_ids_by_team[_team_id]
	for pid: int in mates:
		if pid != _peer_id and snapshot.tag_up_peers.has(pid):
			return true
	return false


# Clamp an anchor to the playable rink with a small margin so steering
# doesn't pull the bot into the boards or behind the goal line.
func _clamp_anchor(p: Vector3) -> Vector3:
	var x: float = clampf(p.x,
			-GameRules.RINK_HALF_WIDTH + AIStationSearch.RINK_INSET_M,
			GameRules.RINK_HALF_WIDTH - AIStationSearch.RINK_INSET_M)
	var z: float = clampf(p.z,
			-GameRules.GOAL_LINE_Z + RINK_Z_INSET,
			GameRules.GOAL_LINE_Z - RINK_Z_INSET)
	# Push out of either crease — bots shouldn't anchor inside a goalie's
	# space. Steering's crease repel is the runtime force; this is the
	# destination-side guard so the anchor doesn't actively PULL the bot
	# into the crease in the first place.
	var xz := Vector2(x, z)
	if CreaseRules.is_in_crease(xz):
		var dir: Vector2 = CreaseRules.outward_direction(xz)
		var goal_z: float = signf(xz.y) * GameRules.GOAL_LINE_Z
		var center := Vector2(0.0, goal_z)
		var pushed: Vector2 = center + dir * (CreaseRules.ARC_RADIUS + RINK_Z_INSET)
		x = pushed.x
		z = pushed.y
	return Vector3(x, 0.0, z)


# Shades a carrier-chase intercept one stick-reach (BLADE_REACH_M) toward our net
# — the inside lane (see Scripts/ai/CLAUDE.md → Chase doctrine). The shade is
# exactly what the stick can poke, so the blade still reaches the puck from the
# shaded body, and it is clamped so a doorstep intercept never projects past our
# goal line. Static so it's unit-testable.
static func _shade_intercept_goal_side(target: Vector3, our_net: Vector3) -> Vector3:
	var to_net: Vector3 = our_net - target
	var dist: float = Vector2(to_net.x, to_net.z).length()
	if dist < 0.001:
		return target
	var shade: float = minf(AIBotMechanics.BLADE_REACH_M, dist)
	var inv: float = shade / dist
	return Vector3(target.x + to_net.x * inv, target.y, target.z + to_net.z * inv)


# Where to steer for a loose puck: the earliest point on its own predicted path
# this body can meet it at, solved by THE SAME race read the election used to
# assign this chase (AILoosePuckChase.path_intercept_time, over the shared
# per-tick trajectory walk). One solver, so the body cannot skate to a different
# spot than the one it was elected on.
#
# `vmax` overrides the speed cap for the race walk (< 0 → _self_max_speed).
func _lead_intercept(self_pos: Vector3, self_vel: Vector3, puck_pos: Vector3,
		puck_vel: Vector3, vmax: float = -1.0) -> Vector3:
	var cap: float = vmax if vmax > 0.0 else _self_max_speed
	var traj: Array[Vector3] = AILoosePuckChase.race_trajectory(puck_pos, puck_vel)
	var step_dt: float = AILoosePuckChase.RACE_LOOKAHEAD_S \
			/ float(AILoosePuckChase.RACE_STEPS)
	# Own thrust and own stick, not the league defaults: this caller reasons about
	# ITSELF. `_blade_reach`, not the bare blade_span: it must be the SAME radius
	# the pickup gate and puck_comes_to_reach use, or the chase steers to a point
	# its own reach band disagrees about.
	var t: float = AILoosePuckChase.path_intercept_time(
			traj, step_dt, puck_pos, self_pos, self_vel, cap,
			AILoosePuckChase.setup_margin(puck_vel), _chase_max_accel, _blade_reach,
			AILoosePuckChase.race_playable_time(puck_pos, puck_vel))
	# The TIME is reach-aware; the steering target is not pulled back onto the
	# reach circle. Where the blade can first touch the puck is the right answer
	# to "am I in this race"; the body should still drive at the meeting point
	# and close the last stick-length, rather than parking at full extension.
	return AILoosePuckChase.path_intercept_point(traj, step_dt, puck_pos, t)


func _post_puck_lost_state(snapshot: WorldSnapshot) -> State:
	if snapshot == null or snapshot.puck_state == null:
		return State.OFF_PUCK
	# If someone has the puck (likely a teammate snagged it), no chase.
	if snapshot.puck_state.carrier_peer_id != -1:
		return State.OFF_PUCK
	var s: SkaterNetworkState = snapshot.skater_states.get(_peer_id)
	# A bot that can't legally play the puck stays OFF_PUCK.
	if s == null or snapshot.is_out_of_play(_peer_id):
		return State.OFF_PUCK
	return State.CHASE_PUCK if _is_closest_teammate_to_puck_at(snapshot, s.position) else State.OFF_PUCK


# Advances the loose-puck reactivity clock. Runs BEFORE the dispatch throttle so
# a skipped tick can't drop time out of the reaction delay. See the field block.
func _update_loose_reaction_clock(snapshot: WorldSnapshot, delta: float) -> void:
	if snapshot == null or delta <= 0.0:
		return
	if snapshot.real_puck_carrier_peer_id == -1:
		_loose_elapsed_s += delta
		_control_elapsed_s = 0.0
		return
	# A graze isn't possession: only a sustained carry clears the loose clock.
	_control_elapsed_s += delta
	if _control_elapsed_s >= CONTROL_CONFIRM_S:
		_loose_elapsed_s = 0.0


func _should_chase_loose_puck(snapshot: WorldSnapshot, self_pos: Vector3) -> bool:
	if snapshot == null or snapshot.puck_state == null:
		return false
	# REAL carrier, on the bot's own reaction clock (see CONTROL_CONFIRM_S).
	if snapshot.real_puck_carrier_peer_id != -1:
		return false  # someone has the puck
	if _loose_elapsed_s < _chase_reaction_delay_s:
		return false  # hasn't been loose long enough for us to have reacted
	# Smart-ping GET_PUCK: an ordered bot chases regardless of the natural
	# election and the race-lost decline below — an order is an order (the
	# election override in GameManager._enrich_snapshot_for_ai keeps a second
	# natural chaser from doubling up).
	if _current_strategy != null and _current_strategy.ping_chase_peer() == _peer_id:
		return true
	# A free puck coming into your reach band is yours, election or not, and
	# ahead of the race-lost decline (see Scripts/domain/ai/CLAUDE.md →
	# "Loose-puck retrieval is two reads").
	if _loose_puck_in_reach_band(snapshot, self_pos):
		return true
	if not _is_closest_teammate_to_puck_at(snapshot, self_pos):
		return false
	# A race an opponent has already won isn't run: declining drops the bot to its
	# role positioning, where the CHASE slot pre-contains the pickup.
	var self_state: SkaterNetworkState = snapshot.skater_states.get(_peer_id)
	var self_vel: Vector3 = self_state.velocity if self_state != null else Vector3.ZERO
	return not AILoosePuckChase.loose_puck_race_lost(
			snapshot, self_pos, self_vel, _self_max_speed,
			_team_id, _team_id_by_peer, _caps_by_peer, _peer_id, _own_goal_dir)


# Does the loose puck's own path cross inside our reach band
# (AILoosePuckChase.puck_comes_to_reach)? False unless the puck is genuinely
# loose. The path walk is memoized on the puck state, one walk per tick.
func _loose_puck_in_reach_band(snapshot: WorldSnapshot, self_pos: Vector3) -> bool:
	if snapshot == null or snapshot.puck_state == null \
			or snapshot.real_puck_carrier_peer_id != -1:
		return false
	# A DEAD loose puck (goalie smother / phase lock) publishes a -1 election for
	# every team; the band bypasses the election, so it honours that veto itself.
	# An EMPTY cache means an unenriched snapshot (unit tests), not a dead puck.
	if not snapshot.closest_to_puck_by_team.is_empty() \
			and snapshot.closest_to_puck_by_team.get(_team_id, -1) == -1:
		return false
	var self_state: SkaterNetworkState = snapshot.skater_states.get(_peer_id)
	if self_state == null or snapshot.is_out_of_play(_peer_id):
		return false
	# A teammate's blade first to it makes the puck his.
	if _teammate_first_to_puck(snapshot, snapshot.puck_state.position):
		return false
	return AILoosePuckChase.puck_comes_to_reach(
			snapshot.puck_state.position, snapshot.puck_state.velocity,
			self_pos, self_state.velocity, _self_max_speed, _blade_reach)


# Is a teammate's blade clearly first to this puck? See
# AILoosePuckChase.teammate_first_to_puck — deadlock-free, so we can never both
# yield and leave the puck sitting.
func _teammate_first_to_puck(snapshot: WorldSnapshot, puck_pos: Vector3) -> bool:
	# has()+index, not get(_team_id, []): the default is built eagerly, and this
	# runs per tick while chasing.
	if not snapshot.teammate_ids_by_team.has(_team_id):
		return false
	var mates: Array = snapshot.teammate_ids_by_team[_team_id]
	if mates.is_empty():
		return false
	var self_state: SkaterNetworkState = snapshot.skater_states.get(_peer_id)
	if self_state == null:
		return false
	return AILoosePuckChase.teammate_first_to_puck(
			snapshot.skater_states, mates, _peer_id,
			self_state.blade_contact_world, puck_pos, snapshot.tag_up_peers)


# Whether this bot is its team's elected loose-puck chaser
# (closest_to_puck_by_team, from GameManager._enrich_snapshot_for_ai); a plain
# nearest-teammate scan when the cache is empty (unit tests).
func _is_closest_teammate_to_puck_at(snapshot: WorldSnapshot, self_pos: Vector3) -> bool:
	if not snapshot.closest_to_puck_by_team.is_empty():
		return snapshot.closest_to_puck_by_team.get(_team_id, -1) == _peer_id
	var puck_pos: Vector3 = snapshot.puck_state.position
	var dx: float = self_pos.x - puck_pos.x
	var dz: float = self_pos.z - puck_pos.z
	var my_d2: float = dx * dx + dz * dz
	for pid: int in snapshot.skater_states:
		if pid == _peer_id:
			continue
		if _team_id_by_peer.get(pid, -1) != _team_id:
			continue
		var pos: Vector3 = snapshot.skater_states[pid].position
		var ox: float = pos.x - puck_pos.x
		var oz: float = pos.z - puck_pos.z
		if ox * ox + oz * oz < my_d2:
			return false
	return true


# Local fallback for the per-peer acceleration read when the snapshot lacks the
# host's shared AIAccelerationTracker cache (unit tests), on the tracker's own
# filter constants. Frame-over-frame velocity diff per peer, low-passed into
# _accel_by_peer. Stale peers (left the snapshot — disconnect, swap)
# get pruned so the dict size stays bounded. First-sight peers seed
# prev_velocity from the current value and contribute zero accel so
# a respawn doesn't register as a thrust spike.
func _update_acceleration_cache(snapshot: WorldSnapshot, delta: float) -> void:
	if delta <= 0.0:
		return
	var inv_delta: float = 1.0 / delta
	var seen: Dictionary = {}
	for peer_id: int in snapshot.skater_states:
		seen[peer_id] = true
		var s: SkaterNetworkState = snapshot.skater_states[peer_id]
		var curr_v: Vector3 = s.velocity
		var prev_v: Vector3 = _prev_velocity_by_peer.get(peer_id, curr_v)
		_prev_velocity_by_peer[peer_id] = curr_v
		var raw_a: Vector3 = (curr_v - prev_v) * inv_delta
		raw_a.y = 0.0
		var smoothed: Vector3 = _accel_by_peer.get(peer_id, Vector3.ZERO)
		smoothed = smoothed.lerp(raw_a, AIAccelerationTracker.SMOOTH_ALPHA)
		var mag: float = sqrt(smoothed.x * smoothed.x + smoothed.z * smoothed.z)
		if mag > AIAccelerationTracker.CLAMP_M_S2:
			var scale: float = AIAccelerationTracker.CLAMP_M_S2 / mag
			smoothed.x *= scale
			smoothed.z *= scale
		_accel_by_peer[peer_id] = smoothed
		# Heading turn rate: must match AIAccelerationTracker's, so a unit-test
		# snapshot reads the same signal the host serves.
		var raw_omega: float = 0.0
		var prev_speed: float = sqrt(prev_v.x * prev_v.x + prev_v.z * prev_v.z)
		var curr_speed: float = sqrt(curr_v.x * curr_v.x + curr_v.z * curr_v.z)
		if prev_speed > AIAccelerationTracker.OMEGA_MIN_SPEED_M_S \
				and curr_speed > AIAccelerationTracker.OMEGA_MIN_SPEED_M_S:
			var dot: float = prev_v.x * curr_v.x + prev_v.z * curr_v.z
			var cross: float = prev_v.x * curr_v.z - prev_v.z * curr_v.x
			raw_omega = atan2(cross, dot) * inv_delta
		var omega: float = lerpf(_heading_omega_by_peer.get(peer_id, 0.0),
				raw_omega, AIAccelerationTracker.OMEGA_SMOOTH_ALPHA)
		omega = clampf(omega, -AIAccelerationTracker.OMEGA_CLAMP_RAD_S,
				AIAccelerationTracker.OMEGA_CLAMP_RAD_S)
		_heading_omega_by_peer[peer_id] = omega
	# Prune peers that left the snapshot. Iterate a copy of the keys: `erase`
	# during iteration is unsafe.
	var existing_ids: Array = _prev_velocity_by_peer.keys()
	for peer_id: int in existing_ids:
		if not seen.has(peer_id):
			_prev_velocity_by_peer.erase(peer_id)
			_accel_by_peer.erase(peer_id)
			_heading_omega_by_peer.erase(peer_id)


# True when any OPPONENT skater is within `r` of `point` (XZ) — the "their
# blade can reach this puck too" contest read (r = blade-on-puck range).
func _opponent_within_of(snapshot: WorldSnapshot, point: Vector3, r: float) -> bool:
	for pid: int in snapshot.skater_states:
		if pid == _peer_id or _team_id_by_peer.get(pid, -1) == _team_id:
			continue
		var p: Vector3 = snapshot.skater_states[pid].position
		var dx: float = p.x - point.x
		var dz: float = p.z - point.z
		if dx * dx + dz * dz < r * r:
			return true
	return false


# Detects "puck just became loose" and arms the engagement cooldown if we were
# close enough to be involved. Single rule covers both sides:
#   - We had the puck and got stripped: prev=us, now=-1, distance≈0
#   - We stick-checked someone: prev=opp, now=-1, we were near to do it
# The carrier-just-changed-to-someone-else case (a teammate or opp picked up
# cleanly without us being close) doesn't fire — prev was set, now is the new
# carrier, not -1. Duration scales with our speed at engagement: see
# ENGAGEMENT_COOLDOWN_MIN_TICKS.
func _update_engagement_cooldown(snapshot: WorldSnapshot, self_state: SkaterNetworkState) -> void:
	var carrier: int = snapshot.puck_state.carrier_peer_id
	if _prev_carrier_peer_id != -1 and carrier == -1:
		var self_pos: Vector3 = self_state.position
		var puck_pos: Vector3 = snapshot.puck_state.position
		var dx: float = puck_pos.x - self_pos.x
		var dz: float = puck_pos.z - self_pos.z
		if dx * dx + dz * dz < ENGAGEMENT_PROXIMITY_M * ENGAGEMENT_PROXIMITY_M:
			var v: Vector3 = self_state.velocity
			var speed: float = sqrt(v.x * v.x + v.z * v.z)
			var ratio: float = clampf(speed / _self_max_speed, 0.0, 1.0)
			_engagement_cooldown = int(round(lerpf(
					float(ENGAGEMENT_COOLDOWN_MIN_TICKS),
					float(ENGAGEMENT_COOLDOWN_MAX_TICKS),
					ratio)))
	_prev_carrier_peer_id = carrier
	if _engagement_cooldown > 0:
		_engagement_cooldown -= 1


func _set_state(s: State) -> void:
	if s != _state:
		if s != State.OFF_PUCK:
			_prev_locked_man_pid = -1
			_stick_play.drop_tie()
		# Every press entry draws its execution samples HERE, once per release,
		# so the whole windup commits to one slightly-imperfect gesture.
		if s == State.SHOOT_PRESSED:
			_shoot_charge_tick = 0
			_committed_aim_error_rad = _sample_aim_error_rad(_shot_aim_error_rad)
			_shoot_release_hold_ticks = _sample_release_hold_ticks()
		if s == State.PASS_PRESSED:
			_pass_charge_tick = 0
			_committed_aim_error_rad = _sample_aim_error_rad(_pass_aim_error_rad)
		if s == State.ONE_TIMER_PRESSED:
			_one_timer_press_tick = 0
			_one_timer_slap_down = false
			_one_timer_charge_s = 0.0
			_one_timer_feed = Vector2.ZERO
			# The SHOT budget, as the reception gate's spread assumes.
			_committed_aim_error_rad = _sample_aim_error_rad(_shot_aim_error_rad)
		# CARRY entry starts a fresh carry; _carrier.clear_intent() also forces an
		# immediate re-eval.
		if s == State.CARRY:
			_intended_action = State.CARRY
			_intent_wait_ticks = 0
			_one_timer_preserve_ticks = 0
			_carry_tracking_fire = false
			_carry_protect_gain_smooth = 0.0
			_carry_protect_offset_smooth = Vector3.ZERO
			_carry_has_man = false
			_stick_play.reset_reach_in()
			_carrier.clear_intent()
		_state = s
		# The new state's first tick dispatches full.
		_dispatch_skip_counter = 0
		# Force a fresh off-puck role decision on the first tick of the new
		# state (cooldown <= 0 recomputes), so a re-entry into OFF_PUCK never
		# steers on a RoleDecision cached from a previous stint.
		_role_decision_cooldown = 0


func _reset_to_off_puck() -> void:
	_set_state(State.OFF_PUCK)
	_pass_target_peer_id = -1
	_carrier.reset()
