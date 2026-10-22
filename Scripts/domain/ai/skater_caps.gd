class_name AISkaterCaps
extends RefCounted

# One skater's attribute-scaled physical capabilities, as the bot AI models them.
# Built from the SAME scaled controller/skater values the physics body actually
# uses (SkaterController.build_ai_caps), so the AI plans with what a body can
# really do instead of league-default constants.
#
# Two uses, one class:
#   - SELF: a bot's model of its OWN body, pushed into its state machine via
#     apply_capabilities (AIController.apply_attributes → the RoleContext.self_*
#     mirror).
#   - PER-PEER: PlayerRegistry memoizes one of these per player in caps_by_peer
#     (rebuilt only on spawn / picker — never per tick), so a bot can model every
#     OTHER player — a teammate receiver's speed, an opponent's reach — with that
#     player's ACTUAL build. Threaded to roles via RoleContext.caps_by_peer.
#
# Every field defaults to the league baseline, so an unset caps (unit tests, a
# bot before any attributes apply) plans like a league-average body.

# Top skating speed (height-derived, leaned by the skate profile).
var max_speed: float = GameRules.DEFAULT_SKATER_MAX_SPEED_M_S

# All-direction acceleration / thrust (Acceleration): the reachable-set ceiling on
# how far off its momentum line a skater can pull a stick.
var max_accel: float = GameRules.DEFAULT_SKATER_THRUST_M_S2

# Hand-to-toe blade span = stick + blade (Size, via stick length). The state
# machine derives its reach gates (blade reach, pass-reception offset, poke reach)
# by adding its own ± buffers to this.
var blade_span: float = GameRules.DEFAULT_STICK_LENGTH_M + GameRules.DEFAULT_BLADE_LENGTH_M

# Stick length ALONE (height + the stick-length gear slot): what the
# lane-interception model reaches into a pass/shot lane with.
var stick_reach: float = GameRules.DEFAULT_STICK_LENGTH_M

# Maximum distance from the body origin to a legal blade-contact point
# (TopHandIK.full_reach: the trunk at its deepest fold, the arm out ahead, the
# stick down to the ice). The host's anti-cheat ceiling on client-
# authoritative blade claims (pickup / poke / stick-lift), pinning the claimed
# blade to within this reach of the server-authoritative body; and where a lane
# read lets a defender hold the stick he is reaching with (AIPuckLane
# ._blade_block). Default = the neutral build's (test_top_hand_reaches_its_rim).
const LEAGUE_MAX_BLADE_REACH_M: float = 2.33
var max_blade_reach: float = LEAGUE_MAX_BLADE_REACH_M
# The furthest the balance lean can carry the shoulders off the body, metres
# (Skater.max_lean_shift). The claim reach bound adds it; the bots' own reach
# model does not, since a lean is not something a bot plans a reach around.
var max_lean_shift: float = 0.0

# Charged wrister release speed (height-derived, leaned by stick flex and blade
# curve). Shot quality reads it (a harder shot leaves defenders less reaction
# time), and it caps the hardest pass (AIPuckLane.pass_launch_speed).
var wrister_shot_speed: float = GameRules.DEFAULT_WRISTER_POWER_MAX_M_S

# How fast the blade traverses its ROM to chase the aim cursor (=
# SkaterController.max_blade_speed, lever-scaled per build). A bot slews its aim cursor at exactly this
# rate.
const LEAGUE_BLADE_SPEED_M_S: float = 10.0
var blade_speed: float = LEAGUE_BLADE_SPEED_M_S

# Lateral grip multiplier (= SkaterController.lateral_grip — agility × the
# skate-profile lean). Scales edge turn authority, so planning reads it wherever
# it models a direction change (the cross-momentum shed in time_to_arrive /
# reach_clearance). Grip never limits parallel drive, in planning or in physics.
var lateral_grip: float = 1.0

# Reception ceiling lean (= Skater.reception_ceiling_mult, from the blade
# curve): scales the deflect ceiling + squared bonus this receiver's blade can
# soak. Carried per-peer; the pass-speed solver does not read it and prices the
# league constant.
var reception_ceiling_mult: float = 1.0

# Backhand power coefficient (= SkaterController.backhand_power_coefficient — a
# flat mechanic: backhand technique is the human, leaned only by the blade-curve
# gear). Part of the wrist shot's load cap (WristerLoad.power_share).
var backhand_power_coefficient: float = 0.75

# The wrist shot's load (= SkaterController's own config objects and
# wrister_unloaded_share), so a bot prices and executes a release under the
# rules its body fires it with.
var wrister_load: WristerLoad.Config = WristerLoad.Config.new()
var facing_rules: FacingRules.Config = FacingRules.Config.new()
# The pivot a carrier's hips make (SkaterController.carry_facing_rules): its
# blade stops at the backhand angle, so its backhand edge is that angle.
var carry_facing_rules: FacingRules.Config = FacingRules.Config.new()
var wrister_unloaded_share: float = 0.6
# Which side the forehand is on, for the facing rule's per-side reach edges.
var is_left_handed: bool = true
# The slapshot stance this body sets (SkaterController.slapper_strike_local /
# slapper_stance_open_deg): where it strikes the puck in its own frame — x
# toward the stick side, so one value serves either hand — and how far its hips
# open off the shot line.
var slapper_strike_local: Vector2 = Vector2(-0.08, -1.07)
var slapper_stance_open_rad: float = PI * 0.5
# The rate the hips pivot into that stance once wound up
# (SkaterController.slapper_stance_turn_deg_s).
var slapper_stance_turn_rad_s: float = deg_to_rad(450.0)
# The slapshot's power band over its charge (SkaterController's
# min/max_slapper_power, max_slapper_charge_time), and the wind-up a feed must
# find built for the one-timer window to open (one_timer_min_windup_time).
var slapper_power_min: float = GameRules.DEFAULT_SLAPPER_POWER_MIN_M_S
var slapper_power_max: float = GameRules.DEFAULT_SLAPPER_POWER_MAX_M_S
var slapper_max_charge_s: float = 0.7
var one_timer_min_windup_s: float = 0.15
# How much of a feed's cross speed the one-timer's face keeps
# (SkaterController.one_timer_feed_grip).
var one_timer_feed_grip: float = 0.2

# Body-check delivery inputs to SkaterCollisionRules.victim_kick
# (closing × transfer × m_a / (m_a + m_b)): a heavier player predicts harder
# hits and commits to checks more readily.
var weight: float = 1.0
var body_check_transfer: float = 0.65

# How far the carrier holds/protects the puck off its body while HANDLING it —
# the reach that sets how tight an evasion seam it can thread (best_evade_point).
# Scaled by the blade lever (max_blade_speed over its base). Puck HANDLING, not
# pass reception. Default is the league carry-handle reach
# (AIBotMechanics.EVADE_CARRY_HANDLE_M).
var handle_reach: float = 0.9

# Half-angle of the blade's reach cone: how far off its FACING the body can
# place the blade WITHOUT turning — arm ROM plus torso twist
# (SkaterController.rom_backhand_angle_max_deg + upper_body_max_twist_deg, the
# backhand side of the per-side gate SkaterPoseCoordinator.apply_facing enforces,
# FacingRules.reach_edge; one cone for both sides here). Only aims beyond it (the
# narrow back wedge) cost a body rotation. Not attribute-scaled.
# Default = 90° + 67°.
var reach_cone_half_angle: float = deg_to_rad(157.0)

# The skating physics this body runs (SkaterController's movement config, a copy:
# the controller writes the body-check stagger into its own every tick, on the
# main thread, while bots read on the AI worker).
var movement: SkaterMovementRules.MovementConfig = SkaterMovementRules.league_config()
# The pose coordinator's facing lerp rates, per second (Agility-scaled).
var facing_drag_speed: float = 5.0
var facing_drag_speed_braking: float = 10.0
# How fast it winds a turn up, rad/s² (FacingRules.turn_rate).
var facing_turn_accel_max: float = 300.0
# The body's contact disc (girth-scaled): how close to the boards and the cage its
# centre can get.
var body_radius: float = 0.35
# A carrier on the boards squares up along them (BoardPlayRules
# .board_shield_facing): the probe distance it starts at and the most it turns.
var board_shield_probe: float = 1.1
var board_shield_max_rad: float = deg_to_rad(55.0)

# Effective body-facing turn rate (rad/s) used to price the rotation an out-of-cone
# aim costs: a constant-rate approximation of the real exponential lerp at
# facing_drag_speed, 6.0 rad/s at baseline and scaled by the skater's Agility.
var facing_turn_rate: float = 6.0
