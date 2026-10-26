class_name RoleContext
extends RefCounted

# Inputs every role decide() consumes, the carrier's included. Built per
# dispatch by SkaterAgentStateMachine. Roles never write the input fields; the
# scratch buffers at the bottom are the exception.

var snapshot: WorldSnapshot = null
var self_pos: Vector3 = Vector3.ZERO
var self_velocity: Vector3 = Vector3.ZERO
var team_id: int = 0
var peer_id: int = 0
# Y is 0.
var attacking_goal_pos: Vector3 = Vector3.ZERO
# Y is 0.
var defending_goal_pos: Vector3 = Vector3.ZERO
# +1 if own goal sits at +GOAL_LINE_Z (Team 0), -1 otherwise. "Forward"
# (toward attacking goal) along Z is `-own_goal_dir`.
var own_goal_dir: float = 1.0
# The live TeamBrain in unit tests, the frozen TeamBrainView in production.
var team_brain: TeamStrategyView = null
# The brain's hysteretic strong-side sign (+1 = +X side), so a role's
# strong/weak side matches its slot assignment. +1 when no brain is wired.
var strong_x: float = 1.0
# The man TeamBrain's threat partition assigned this defender (MARK and the 5v5
# zone roles cover him), or -1 when unassigned — the role then falls back to
# its own read.
var assigned_threat_peer: int = -1
# TeamBrain's per-opponent shoot-threat bases (opp peer_id -> surface; the
# approximation contract is on TeamBrain.threat_shoot_base_by_opp), used by
# MARK's unassigned fallback as ordering / pruning bounds. Empty = no memo:
# compute exactly.
var threat_shoot_base_by_opp: Dictionary[int, float] = {}
# The team's shared transition read (docs/transition-defense-plan.md §4). Never
# null: an unwired context gets TeamStrategyView's inert read (Mode.NONE, no
# attackers).
var rush_read: AIRushRead = TeamStrategyView.new().get_rush_read()
# Last dispatch's RoleDecision.held_forward_stand — the incumbent side of
# AILastManDiscipline.may_hold_forward_stand's hysteresis. False across a slot change.
var prev_held_forward_stand: bool = false
# Peer -> team_id, live dict owned by PlayerRegistry; read with
# `get(pid, -1)`. A Dictionary rather than a resolver Callable because roles
# iterate skaters at dispatch rate, where Callable.call overhead shows.
var team_id_by_peer: Dictionary = {}
# Smoothed per-peer linear acceleration (m/s², world XZ) — the host's shared
# AIAccelerationTracker cache, or the state machine's local fallback. Leads a
# receiver along `pos + vel·t + ½·a·t²`. Missing entry = ZERO.
var acceleration_by_peer: Dictionary = {}

# Smoothed per-peer heading turn rate (rad/s, signed) — the passer's
# receiver-commitment read (AIPuckLane.pass_miss_prob). Missing entry = 0.
var heading_omega_by_peer: Dictionary = {}

# Per-peer AISkaterCaps — every player's real build. Live reference to
# PlayerRegistry's memo (rebuilt on spawn / picker, never per tick). Read
# `get(pid, null)`; a missing entry means the league default.
var caps_by_peer: Dictionary = {}

# ── Self capabilities (attribute-scaled, this bot only) ───────────────────────
# From this bot's AISkaterCaps. Defaults are the league baseline, so an unwired
# context scores as an average body.
var self_max_speed: float = GameRules.DEFAULT_SKATER_MAX_SPEED_M_S
# All-direction thrust, m/s² — time_to_arrive's cross-momentum shed cost.
var self_max_accel: float = GameRules.DEFAULT_SKATER_THRUST_M_S2
# AISkaterCaps.lateral_grip — perpendicular authority in its own ETA reads.
var self_lateral_grip: float = 1.0
# Pass release-direction error, radians (BotSkillProfile.pass_aim_error_rad);
# drives AIPuckLane.pass_miss_prob. 0 = error-free agent (miss = base floor).
var self_pass_aim_error_rad: float = 0.0
# Charged wrister release speed, m/s — also the cap on its pass launch speed.
var self_wrister_shot_speed: float = GameRules.DEFAULT_WRISTER_POWER_MAX_M_S
# Body-check delivery and current stagger, for AIDefensiveVerbs.evaluate_body_check.
var self_weight: float = 1.0
var self_body_check_transfer: float = 0.65
var self_stagger_timer: float = 0.0
# Seconds left settling a hard catch: no release can start until it ends.
var self_settle_s: float = 0.0
# Lever-scaled carry-handle reach, m — how tight a seam best_evade_point threads.
var self_handle_reach: float = 0.9
# Stick + blade reach, m — the "one stick length" unit of the gap ladder.
var self_blade_reach: float = AIBotMechanics.BLADE_REACH_M
# Blade reach cone half-angle (ROM + torso twist) and facing turn rate, rad/s —
# what the carrier's _facing_rotation_time charges an aim outside the cone.
var self_reach_cone_half_angle: float = deg_to_rad(157.0)
var self_facing_turn_rate: float = 6.0
# Cursor arc rate round the body, rad/s (SkaterAgentStateMachine._mouse_arc_rate_rad_s).
var self_arc_rate: float = 7.5
# The wrist shot's load as this bot fires it (AISkaterCaps): blade traverse
# speed (m/s), backhand coefficient, unloaded share, load and facing rules, and
# the forehand perpendicular sign (-1 right-handed, +1 left).
var self_blade_speed: float = 10.0
var self_backhand_power_coefficient: float = 0.75
var self_wrister_unloaded_share: float = 0.6
var self_wrister_load: WristerLoad.Config = WristerLoad.Config.new()
var self_facing_rules: FacingRules.Config = FacingRules.Config.new()
var self_carry_facing_rules: FacingRules.Config = FacingRules.Config.new()
var self_forehand_perp_sign: float = -1.0

# ── Difficulty knobs (from BotSkillProfile, this bot only) ────────────────────
# Defaults are the no-op baseline (perfect bot).
# Extra metres on PRESSURE's gap to the carrier.
var pursuit_standoff_m: float = 0.0
# Multiplier on this bot's own pass launch speed.
var pass_speed_scale: float = 1.0
# How hard the on-puck pressurer hunts body checks: 1 = full, 0 = never commits.
var check_aggression: float = 1.0
# Multiplier on AIRoleReads.DEFENSIVE_ANTICIPATION_S (lead_threat). Never
# moves a stand.
var defensive_anticipation_scale: float = 1.0
# Settle doubt: the fraction a fresh carrier raises every active option's
# giveaway bar by, decaying exp(-t / settle_penalty_tau_s) from the gain. See
# Scripts/domain/ai/CLAUDE.md → "Hesitation is a raised bar, never a timer".
var settle_penalty_frac: float = 0.0
var settle_penalty_tau_s: float = 0.25
# COGNITION gate: false = the keeper always reads SET to the carrier: still to the
# shot reads (AICarrierField.goalie_unsettled_at returns 0) and already square on a
# pass's receiver (AICarrierField.feed_value_at). The aim-side half of the gate
# lives on the state machine.
var reads_goalie_motion: bool = true
# COGNITION gate: false = the carrier never values a play that doesn't exist
# yet (AICarrierPassSearch.developing_feed_value returns 0).
var holds_for_developing_feeds: bool = true
# COGNITION gate: false = heading_omega reads as 0 in the pass EV, so a feed to
# a hard-cutting receiver prices like one to a straight-line skater.
var reads_receiver_commitment: bool = true
# COGNITION gate: false = RUSH_D1 retreats on the carrier→net line only; true =
# it splits toward an uncovered receiver's feed lane (AIRoleRushD's lane fan).
var plays_rush_pass_lanes: bool = true
# COGNITION gate: true = the carrier shields the puck (protect_offset /
# protect_gain); false = the puck stays presented ahead of the body.
var protects_the_puck: bool = true

# ── Smart-ping directive (a human teammate's tactical order) ──────────────────
# From TeamBrain.ping_* (AIPingDirectives).
# GO_THERE override for RoleDecision.target_position; Vector3.INF = none.
var ping_move_target: Vector3 = Vector3.INF
# The carrier multiplies its shoot EV by AIRoleCarrier.PING_SHOOT_EV_MULT.
var ping_shoot_active: bool = false
# The pinger of a live PASS_TO_ME / IM_OPEN ping (-1 none); the carrier
# multiplies that receiver's pass EV by AICarrierPassSearch.PING_PASS_EV_MULT.
var ping_pass_target_peer: int = -1

# Physics ticks per decide() call. A role counting ticks must scale by this, or
# its wall-clock durations stretch with the tier.
var dispatch_period_ticks: int = 1

# Last dispatch's target_position carried to now at its target_velocity (a stand
# riding a man is held in his frame, not left on the ice behind him), or
# Vector3.INF on the first dispatch and across a slot change (no role inherits
# another's target). The incumbent for argmax switch-hysteresis
# (AIStationSearch.append_incumbent / incumbent_bonus).
var prev_role_target: Vector3 = Vector3.INF

# NHL delayed offside: a teammate owes a tag-up, so the carrier keeps its
# carries, feeds and rims out of the attacking zone.
var zone_entry_blocked: bool = false

# ── 5v5 position identity ────────────────────────────────────────────────────
# Latched match team size (TeamBrain.team_size). Gates the 5v5-only reads.
var team_size: int = GameRules.DEFAULT_TEAM_SIZE
# Lobby position is LD/RD, and home side as a world-X sign
# (PlayerRules.home_side_x; 0 = center) — AIZoneCoverage.defensive_anchor's inputs.
var self_is_defense: bool = false
var self_home_side: float = 0.0

# ── Reusable scratch buffers (not inputs) ────────────────────────────────────
# One RoleContext is reused across dispatches, so the collect_* helpers fill
# these instead of allocating. Each helper clears its buffer first; fill through
# the helpers, never read stale contents, and never retain a buffer past decide().
var scratch_opp_positions: Array[Vector3] = []
var scratch_opp_states: Array[SkaterNetworkState] = []
# Index-matched to scratch_opp_positions; a null entry / short buffer means the
# league default.
var scratch_opp_caps: Array[AISkaterCaps] = []
# Index-matched to scratch_opp_positions.
var scratch_opp_ids: Array[int] = []
# Index-matched to scratch_opp_positions: each opponent's velocity, never led.
var scratch_opp_vels: Array[Vector3] = []
# The defence our carrier's feed is read against (AIRoleReads.collect_feed_defence),
# index-matched: each opponent and his blade carried to the release, his
# velocity and his build.
var scratch_feed_opp_release: Array[Vector3] = []
var scratch_feed_opp_blades: Array[Vector3] = []
var scratch_feed_opp_vels: Array[Vector3] = []
var scratch_feed_opp_caps: Array[AISkaterCaps] = []
# Our possession read against the opponents (AIRoleReads.attack_possession), over
# the opponent buffers above.
var scratch_attack_possession := AIPossessionValue.new()
var scratch_teammates: Array[Vector3] = []
# Index-matched to scratch_teammates; entries may be null.
var scratch_teammate_caps: Array[AISkaterCaps] = []
# Index-matched to scratch_teammates.
var scratch_teammate_vels: Array[Vector3] = []
# The opposing attack's possession read against our skaters
# (AIRoleReads.defence_possession), over the three teammate buffers above.
var scratch_defence_possession := AIPossessionValue.new()
# The attacking side a possession read pairs its defence to
# (AIDefencePairing.collect_attack): ours for attack_possession, theirs for
# defence_possession.
var scratch_attack_pairing: Array[Vector3] = []
var scratch_attack_pairing_vels: Array[Vector3] = []
var scratch_defence_pairing: Array[Vector3] = []
var scratch_defence_pairing_vels: Array[Vector3] = []
var scratch_opp_receivers: Array[Vector3] = []
# Option-value upper bounds (AIDefensiveVerbs.carrier_option_bases).
var scratch_option_bases: Array[float] = []
# A feed station's argmax (AIFeedStationPick).
var scratch_feed_pick := AIFeedStationPick.new()
# AIDefensiveVerbs.read_carrier_approach's output.
var scratch_carrier_approach := AICarrierApproach.new()
