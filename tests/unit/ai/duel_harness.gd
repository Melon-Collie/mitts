extends RefCounted

# ── Bot-vs-bot DUEL HARNESS ──────────────────────────────────────────────────
# Steps full multi-second duels between real bot brains, headlessly, so
# emergent SEQUENCES (beat a container, escape a pincer, pick a puck up
# blade-first) become pinnable GUT scenarios instead of playtest-only
# observations. Loaded via preload from scenario test files — deliberately no
# class_name (test infrastructure stays out of the global namespace).
#
# What runs REAL, on the league body's numbers read off a set-up controller
# (match_caps), held to production by test_bot_mirrors.gd and
# test_duel_rig_mirrors.gd:
#   - Decisions: each skater is a live SkaterAgentStateMachine run through all
#     of SkaterAgent.tick (dispatch, then the stick-lift, stand-up, board-play,
#     shot-block, press and offside passes) and AIController's braked stick,
#     with a real per-team TeamBrain, on a snapshot filled as GameManager fills
#     it: the lagged carrier belief, shot state, stick check and tie, stagger
#     and knockdown, settle, top hand, loft and intents.
#   - The body: SkaterMovementRules at 120 Hz, the controller's facing step
#     (turn wind-up, board shield, a wrister's freeze, the slapper stance), a
#     wound-up body only gliding, skater contacts (SkaterCollisionRules), hits
#     staggering and knocking down by the balance model, the boards and nets
#     holding bodies.
#   - The arm (duel_rig.gd): the upper body's twist and reach lean, the blade
#     resolved through the top hand's range of motion, the carry's two hands and
#     backhand stop, and the rest reach without purpose, chased at the hands'
#     speed and acceleration.
#   - The puck: pickups, catches, settles, bobbles (with their hop), deflections
#     off a blade too fast to hold, contested pickups, pokes (with the pinch
#     hop), stick lifts, ties, hit strips, every cooldown; releases through
#     ShotMechanics on the controller's configs, a lofted one flying over the
#     sticks, each with its follow-through; puckless one-timers swung through
#     the slapper zone.
#
# What is APPROXIMATED (keep scenario assertions coarse because of these):
#   - The arm leaves out the skating lean and the trunk's fold, and the boards
#     do not limit its reach.
#   - The puck is flat: an airborne one is touched by nothing, and a landing
#     keeps its pace; shots take no body blocks.
#   - Board pins and the press's pair coupling are absent, as is goalie
#     BEHAVIOR (a static net-center keeper per team, or a goalie_provider's).
#   - Puppets and scripted attackers skate their own simple policies.

# ASSERTION PHILOSOPHY: scenarios pin THAT a behavior works — "possession
# retained and 5 m of progress within 6 s" — never frame-exact trajectories.
# Frame-exact pins would break on every future feel-tuning change and test
# the approximations instead of the decisions.

const Agent := preload("res://Scripts/ai/skater_agent_state_machine.gd")
const DuelRig := preload("res://tests/unit/ai/duel_rig.gd")
const DuelBody := preload("res://tests/unit/ai/duel_body.gd")

const DT: float = 1.0 / 120.0
# The puppets' plain facing, blade speed and reach (and a fixture's ring), and
# PuckController.PICKUP_RADIUS.
const FACING_DRAG: float = 5.0
const MAX_BLADE_SPEED: float = 10.0
const BLADE_REACH: float = 1.8
const PICKUP_RADIUS: float = 0.5
# A loose-puck attach is the production catch (PuckReceptionRules.should_receive)
# at Puck's defaults: always under PICKUP_MAX_REL_SPEED, at any angle under
# DEFLECT_MIN_REL_SPEED, and up to RECEIVE_ALIGNMENT_BONUS more for a blade square
# to the puck, the face read across the arm's shaft (hand to blade).
# test_bot_mirrors.gd holds the three to Puck.
const PICKUP_MAX_REL_SPEED: float = 8.0
const DEFLECT_MIN_REL_SPEED: float = 22.0
const RECEIVE_ALIGNMENT_BONUS: float = 8.0
# Past its bobble line (PuckReceptionRules.bobble_load_at, at Puck's defaults) a
# catch bobbles: the puck leaves the face on PuckCollisionRules.bobble_velocity
# at AIPuckLane's mirror of Puck's exit, in the receiver's frame (flat — the hop
# is not modeled), and he waits out the full settle before regathering.
# test_bot_mirrors.gd holds these to Puck.
const BOBBLE_LOAD: float = 0.67
const BOBBLE_EDGE_SHARE: float = 0.4
const BOBBLE_GRACE_TICKS: int = 48   # Puck.settle_max_s 0.40 s at 120 Hz
# A releaser can't re-catch its own release (Puck.release's reattach_cooldown).
const RELEASE_GRACE_TICKS: int = 60
# A strip leaves the puck at Puck.apply_poke_check's exit, with its cooldowns:
# the ex-carrier can't reattach for reattach_cooldown, the poker for
# poke_checker_cooldown.
const POKE_STRIP_MIN_M_S: float = 3.0
const POKE_STRIP_MAX_M_S: float = 9.0
const POKE_CARRIER_VEL_BLEND: float = 0.5
const STRIP_REATTACH_TICKS: int = 60
const STRIP_CHECKER_TICKS: int = 12
# A puck too fast to hold comes off the face (Puck.apply_blade_deflect) keeping
# this much of its glancing pace; under the bobble speed the deflector gets the
# short cooldown, over it the long one.
const DEFLECT_TANGENTIAL_RETAIN: float = 0.85
const BOBBLE_SPEED_M_S: float = 11.0
const BOBBLE_COOLDOWN_TICKS: int = 14
const DEFLECT_COOLDOWN_TICKS: int = 36
# The hop a squeezed puck takes: a bobble off the face, and two blades pinching it
# (a poke, a contested pickup) — PuckCollisionRules.squeeze_lift_speed's dials at
# Puck's values.
const BOBBLE_LIFT_THRESHOLD_M_S: float = 6.0
const BOBBLE_LIFT_GAIN: float = 0.15
const BOBBLE_LIFT_MAX_M_S: float = 1.9
const PINCH_LIFT_THRESHOLD_M_S: float = 2.5
const PINCH_LIFT_GAIN: float = 0.3
const PINCH_LIFT_MAX_M_S: float = 2.2
# Two blades on one loose puck squirt it (PuckController's contest pace).
const CONTEST_MIN_M_S: float = 1.5
const CONTEST_MAX_M_S: float = 9.0
const CONTEST_DEADLOCK_M_S: float = 1.2
const CONTEST_DEADLOCK_THRESHOLD_M_S: float = 0.5
# A puckless slapper wind-up holds the blade overhead, out of the catch's reach;
# the swing meets a loose puck in the slapper zone (the build's strike spot)
# after the retention hold (SkaterController._try_one_timer_release).
const SLAPPER_ZONE_RADIUS_M: float = 0.5
const ONE_TIMER_LENIENCY_S: float = 0.08
const ONE_TIMER_RETENTION_TICKS: int = 13
# Where Puck.release seats a lofted release.
const LOFT_SEAT_M: float = 0.1
# TeamBrain re-slot cadence (~6 Hz, the production rhythm).
const BRAIN_PERIOD_TICKS: int = 20

# ── Scripted PUPPET container tuning ─────────────────────────────────────────
# A puppet (add_puppet_container) is an agentless defender running a fixed
# containment policy: hold the puck→own-net line at a set gap, never retreat
# past a depth floor, mirror with real skater accel off a reaction-delayed
# puck read, blade presented on the puck line. Real defender bots CHASE a
# carrier one-on-one (and the carrier rightly beats them with speed and a cut),
# so patient containment has to be staged deliberately.
const PUPPET_REACTION_TICKS: int = 18       # ≈ EVADE_REACTION_S at 120 Hz
const PUPPET_ACCEL_M_S2: float = 10.5       # DEFAULT_SKATER_THRUST_M_S2
const PUPPET_MAX_SPEED_M_S: float = 9.0
const PUPPET_GAIN: float = 4.0              # P-control: desired m/s per m of error

# ── Scripted ATTACKER tuning ─────────────────────────────────────────────────
# A scripted attacker (add_scripted_attacker) is an agentless skater looping a
# fixed waypoint path at a set pace, facing the net it attacks. A scripted
# carrier keeps the puck on its blade for the whole run — no release, no strip
# — so a defensive fixture measures the defence against a held possession
# instead of riding on whatever the attack decides to do.
const SCRIPT_ARRIVE_M: float = 0.2
const SCRIPT_CARRY_REACH_M: float = 0.8


class SimSkater:
	var peer_id: int
	var team_id: int
	var pos: Vector3
	var vel: Vector3 = Vector3.ZERO
	var facing: Vector2 = Vector2(0, -1)
	var blade: Vector3
	var prev_blade: Vector3
	var agent: SkaterAgentStateMachine
	var input: InputState = InputState.new()
	var profile: BotSkillProfile = null
	var was_holding_shot: bool = false
	var was_holding_slap: bool = false
	# The charge held last tick was a pass (or dump): it leaves at the pace the bot
	# committed to (_release_speed).
	var was_passing: bool = false
	# The tick a puckless slapper swing lands (-1: none coming) and its aim.
	var swing_at: int = -1
	var swing_aim: Vector3 = Vector3.ZERO
	# Seconds the slapper has been wound up this charge (puck or not), and the
	# charge a puckless swing carries into its hold.
	var slap_charge_s: float = 0.0
	var swing_charge_s: float = 0.0
	# The hips' turn rate (rad/s), wound up toward each tick's turn
	# (FacingRules.turn_rate), and the facing's angular velocity as the wire
	# carries it (SkaterPoseCoordinator.update_angular_velocities).
	var turn_rate: float = 0.0
	var facing_ang_vel: float = 0.0
	# The tick a catch's settle lock ends (SkaterSettleGate), and a release's
	# follow-through.
	var settle_until: int = 0
	var follow_until: int = 0
	# The stick check (StickCheckRules' phase machine), its cooldown's end, a
	# lifted stick's end, and the opponent it is tied with (-1: none).
	var check_phase: int = StickCheckRules.Phase.IDLE
	var check_elapsed: float = 0.0
	var check_cooling_until: int = 0
	var lifted_until: int = 0
	var tied_with: int = -1
	# The body in contact (duel_body.gd): its stagger and knockdown timers, and
	# whether it is committed to a check or in the stance this tick.
	var stagger: float = 0.0
	var knockdown: float = 0.0
	var hit_active: bool = false
	var stance_active: bool = false
	# The blade marker's offset off the body, latched as a wrister charge starts
	# (see step()).
	var wrister_hold: Vector3 = Vector3.ZERO
	var wrister_active: bool = false
	# ≥ 0 marks a scripted puppet container (no agent); the gap it holds.
	var puppet_hold_gap: float = -1.0
	var puppet_depth_floor_z: float = 0.0
	# False: the presented blade holds lanes but never strips the carrier.
	var puppet_can_strip: bool = true
	# Non-empty marks a scripted attacker (no agent): its looped waypoints.
	var script_path: Array[Vector3] = []
	var script_speed: float = 0.0
	var script_idx: int = 0
	# True: the scripted skater drives its path through the real movement model
	# (stride ramp, power knee) facing its travel, instead of the flat-accel
	# P-control — for a fixture whose question is a race against it.
	var script_skates: bool = false
	# The arm the rig places the blade with (duel_rig.gd). A fixture may set
	# `blade_reach` to place the blade on a plain ring of that radius instead, and
	# a per-tick write over the decided input (`func(s: SimSkater) -> void`), run
	# after the agent decides.
	var arm: DuelRig.Arm = DuelRig.Arm.new()
	var blade_reach: float = INF
	var input_override: Callable = Callable()


var skaters: Array[SimSkater] = []
var team_map: Dictionary = {}
# Every body's caps (match_caps), as the brains and agents read them in a match.
var caps_by_peer: Dictionary = {}
var brains: Dictionary = {}
# Match team size for the brains (3 = legacy path, 5 = position-aware) and
# the peer_id → lobby-slot position map the 5v5 election reads. Set before
# start(); defaults reproduce the original 3v3 harness behavior.
var team_size: int = GameRules.DEFAULT_TEAM_SIZE
var positions: Dictionary = {}

# ── Perf instrumentation (benchmarks/) ───────────────────────────────────────
# When collect_perf is on, step() accumulates wall-clock µs for the brain
# ticks and each agent's dispatch, so the AI benchmark can attribute host
# cost per subsystem/slot. Off by default — scenario tests pay one branch.
var collect_perf: bool = false
var perf_brain_us: int = 0
var perf_dispatch_us: Dictionary = {}     # peer_id -> accumulated µs
var perf_dispatch_calls: Dictionary = {}  # peer_id -> dispatch() call count
# Per-tick AI cost distribution (brain + all dispatches on that tick), for
# frame-pacing analysis: FPS is set by the WORST tick, not the average.
var perf_tick_us: Array[int] = []
var puck_pos: Vector3 = Vector3.ZERO
var puck_vel: Vector3 = Vector3.ZERO
var carrier_id: int = -1
# Airborne CHIP support: while > 0 the puck is in the air — constant ground
# velocity (ballistic track), no ice friction, no pickups (no bot volunteers
# a deflect) — then it lands, keeping LANDING_SPEED_KEEP of its pace (the
# bounce/skid loss). Scenario harnesses set this to hang_time / DT when
# staging a lofted dump; 0 (the default) is the ordinary ice puck.
var airborne_ticks: int = 0
const LANDING_SPEED_KEEP: float = 0.6
# The share of pace the airborne puck lands with: LANDING_SPEED_KEEP for a staged
# chip, all of it for a saucer (the bots' own saucer model).
var _airborne_keep: float = LANDING_SPEED_KEEP
var ticks: int = 0
var move_cfg: SkaterMovementRules.MovementConfig
var _facing_cfg: FacingRules.Config
var _carry_facing_cfg: FacingRules.Config
var _caps: AISkaterCaps
var _facing_rule := FacingRules.Result.new()
var _load := WristerLoad.Result.new()
var _collision := SkaterCollisionRules.Result.new()
# Rolling puck positions for the puppets' reaction-delayed read.
var _puck_history: Array[Vector3] = []
# peer_id -> tick until which that peer can't re-catch its own release.
var _release_grace: Dictionary = {}
# Catches that bobbled, pucks deflected off a blade too fast to hold, contested
# pickups and landed stick lifts, this run.
var bobbles: int = 0
var lifts: int = 0
var hit_strips: int = 0
var deflects: int = 0
var contests: int = 0
# Per-team incumbent for the snapshot's chase election (hysteresis feed).
var _prev_chase_by_team: Dictionary = {}
# The bots' shared, lagged belief of who carries (GameManager
# ._apply_bot_carrier_reaction_delay), at the match's profile: the first
# skater's, else production's default.
var _carrier_belief := CarrierBelief.new()
var _reaction_delay_s: float = -1.0
# Each net's keeper x last tick, for the velocity a live keeper publishes.
var _keeper_x: Dictionary = {}
# Loose-puck board bounce restitution (the harness's coarse boards — flight
# fidelity is still not the point; containment is).
const BOARD_RESTITUTION: float = 0.5

# ── Outcome telemetry (scenario assertions read these) ──────────────────────
var strips: int = 0
# One entry per fired release: { "tick": int, "peer": int, ... } — pass/shot
# events (the carrier's compete at the moment of firing rides along).
var releases: Array[Dictionary] = []
# Ticks each peer spent as the carrier.
var carry_ticks: Dictionary = {}

# Optional real-goalie hook (default off → static keepers, existing scenarios
# unchanged). When set, called once per team per tick as
# `goalie_provider.call(team_id: int, puck_pos: Vector3) -> Variant`; a Vector3
# return overwrites that net's keeper position in the snapshot (a real
# GoalieController the test owns and ticks), anything else keeps the static one.
var goalie_provider: Callable = Callable()


func _init() -> void:
	# The league body's skating physics and facing, read from the real set-up
	# controller the bots' caps come from, so the plant skates what they price.
	_caps = match_caps()
	move_cfg = _caps.movement
	_facing_cfg = _caps.facing_rules
	_carry_facing_cfg = _caps.carry_facing_rules


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


static var _match_caps: AISkaterCaps = null
static var _match_rig: RefCounted = null
# The release, as the set-up controller fires it.
class ShotKit:
	var wrister: ShotMechanics.WristerConfig
	var slapper: ShotMechanics.SlapperConfig
	var wrister_load: WristerLoad.Config
	var min_wrister: float
	var max_wrister: float
	var unloaded_share: float
	var backhand_coefficient: float
	var wrister_finish_min: float
	var wrister_finish_max: float
	var slapper_finish_min: float
	var slapper_finish_max: float
	var quick_finish: float
	var one_timer_bonus: float
static var _shot_kit: ShotKit = null
static var _match_body: RefCounted = null


# The league body's caps as a match hands them to a bot (PlayerRegistry:
# SkaterController.build_ai_caps on a set-up body), right-handed like the
# harness's agents. Built once: the body needs the scene tree, and caps are
# never edited once built.
static func match_caps() -> AISkaterCaps:
	if _match_caps != null:
		return _match_caps
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var skater := (load("res://Scenes/Skater.tscn") as PackedScene).instantiate() as Skater
	var puck := (load("res://Scenes/Puck.tscn") as PackedScene).instantiate() as Puck
	var state := StubGameState.new()
	var ctrl := SkaterController.new()
	skater.is_left_handed = false
	for n: Node in [puck, skater, state, ctrl]:
		root.add_child(n)
		n.set_process(false)
		n.set_physics_process(false)
	ctrl.setup(skater, puck, state)
	_match_caps = ctrl.build_ai_caps()
	_match_rig = DuelRig.capture(skater, ctrl)
	_match_body = DuelBody.capture(skater, ctrl, puck)
	_shot_kit = ShotKit.new()
	_shot_kit.wrister = ctrl._wrister_config()
	_shot_kit.slapper = ctrl._slapper_config()
	_shot_kit.wrister_load = ctrl._wrister_load_config()
	_shot_kit.min_wrister = ctrl.min_wrister_power
	_shot_kit.max_wrister = ctrl.max_wrister_power
	_shot_kit.unloaded_share = ctrl.wrister_unloaded_share
	_shot_kit.backhand_coefficient = ctrl.backhand_power_coefficient
	_shot_kit.wrister_finish_min = ctrl.wrister_follow_through_time_min
	_shot_kit.wrister_finish_max = ctrl.wrister_follow_through_time_max
	_shot_kit.slapper_finish_min = ctrl.slapper_follow_through_time_min
	_shot_kit.slapper_finish_max = ctrl.slapper_follow_through_time_max
	_shot_kit.quick_finish = ctrl.quick_pass_follow_through_duration
	_shot_kit.one_timer_bonus = ctrl.one_timer_center_power_bonus
	for n: Node in [ctrl, state, skater, puck]:
		root.remove_child(n)
		n.free()
	return _match_caps


func add_skater(peer_id: int, team_id: int, pos: Vector3,
		profile: BotSkillProfile = null, vel: Vector3 = Vector3.ZERO) -> void:
	var s := SimSkater.new()
	s.peer_id = peer_id
	s.team_id = team_id
	s.pos = pos
	s.vel = vel
	s.blade = pos
	s.prev_blade = pos
	s.profile = profile
	skaters.append(s)
	team_map[peer_id] = team_id


# A scripted patient container (see the PUPPET_* block). `depth_floor_z` is
# the deepest own-net z it will retreat to (0.0 = hold the spawn line).
# `can_strip` false keeps it from taking the puck — for fixtures whose question
# needs possession granted rather than contested.
func add_puppet_container(peer_id: int, team_id: int, pos: Vector3,
		hold_gap: float = 2.3, depth_floor_z: float = 0.0, can_strip: bool = true) -> void:
	add_skater(peer_id, team_id, pos)
	var s: SimSkater = _skater(peer_id)
	s.puppet_hold_gap = hold_gap
	s.puppet_depth_floor_z = depth_floor_z if depth_floor_z != 0.0 else pos.z
	s.puppet_can_strip = can_strip


# A scripted attacker (see the SCRIPT_* block): starts on `path[0]` and loops
# the path at `speed` m/s.
func add_scripted_attacker(peer_id: int, team_id: int, path: Array[Vector3],
		speed: float) -> void:
	add_skater(peer_id, team_id, path[0])
	var s: SimSkater = _skater(peer_id)
	s.script_path = path
	s.script_speed = speed
	s.script_idx = 1 % path.size()


# Build brains + agents and hand the puck to `carrier_peer` (-1 = loose at
# `loose_puck_pos`). Call once, after every add_skater.
func start(carrier_peer: int, loose_puck_pos: Vector3 = Vector3.ZERO) -> void:
	var caps: AISkaterCaps = match_caps()
	for s: SimSkater in skaters:
		caps_by_peer[s.peer_id] = caps
	for tid: int in [0, 1]:
		brains[tid] = TeamBrain.new(tid, team_map, caps_by_peer, team_size, positions)
	for s: SimSkater in skaters:
		carry_ticks[s.peer_id] = 0
		if s.puppet_hold_gap >= 0.0 or not s.script_path.is_empty():
			continue
		s.agent = Agent.new()
		s.agent.setup(s.peer_id, s.team_id, brains[s.team_id], team_map, caps.is_left_handed,
				caps_by_peer)
		s.agent.apply_capabilities(caps)
		if s.profile != null:
			s.agent.apply_profile(s.profile)
	carrier_id = carrier_peer
	# The play is staged under way: the bots already know who has the puck.
	_carrier_belief.perceived = carrier_peer
	if carrier_peer == -1:
		puck_pos = loose_puck_pos
	else:
		puck_pos = _skater(carrier_peer).pos


func run(seconds: float) -> void:
	var n: int = int(seconds / DT)
	for i: int in n:
		step()


func step() -> void:
	ticks += 1
	_puck_history.append(puck_pos)
	if _puck_history.size() > PUPPET_REACTION_TICKS + 2:
		_puck_history.pop_front()
	var snapshot: WorldSnapshot = _build_snapshot()
	var tick_ai_us: int = 0
	if ticks % BRAIN_PERIOD_TICKS == 1:
		var brain_t0: int = Time.get_ticks_usec() if collect_perf else 0
		for tid: int in brains:
			brains[tid].tick(BRAIN_PERIOD_TICKS * DT, snapshot)
		if collect_perf:
			var brain_us: int = Time.get_ticks_usec() - brain_t0
			perf_brain_us += brain_us
			tick_ai_us += brain_us
	# Freeze each brain's strategy view every step (per-frame anchors), matching
	# GameManager, so the dispatch exercises the same frozen-view path production
	# uses rather than the live-brain fallback.
	for tid: int in brains:
		brains[tid].build_view()
	# Decide.
	for s: SimSkater in skaters:
		if s.agent == null:
			continue
		s.was_holding_shot = s.input.shoot_held
		s.was_holding_slap = s.input.slap_held
		s.was_passing = s.agent._state == SkaterAgentStateMachine.State.PASS_PRESSED
		# Production's per-tick reset (SkaterAgent.tick) — held flags that a
		# cancelled press state leaves set must not latch into later ticks.
		SkaterAgent.zero_input(s.input, DT, s.input.host_timestamp)
		if collect_perf:
			var t0: int = Time.get_ticks_usec()
			s.agent.dispatch(s.input, snapshot)
			var us: int = Time.get_ticks_usec() - t0
			perf_dispatch_us[s.peer_id] = int(perf_dispatch_us.get(s.peer_id, 0)) + us
			perf_dispatch_calls[s.peer_id] = int(perf_dispatch_calls.get(s.peer_id, 0)) + 1
			tick_ai_us += us
		else:
			s.agent.dispatch(s.input, snapshot)
		# The rest of SkaterAgent.tick, then AIController.apply_decision's stick.
		s.agent.apply_stick_lift_input(s.input)
		s.agent.apply_stand_up(s.input, snapshot)
		s.agent.apply_board_play(s.input, snapshot)
		s.agent.apply_shot_block(s.input, snapshot)
		s.agent.apply_press(s.input, snapshot)
		s.agent.apply_offside_guard(s.input, snapshot)
		s.input.move_vector = AIBotMechanics.braked_stick(s.input.move_vector, s.input.brake,
				s.vel, s.input.bot_shuffle)
		if s.input_override.is_valid():
			s.input_override.call(s)
	# Collect one-timer readiness into the brains after dispatch — the write moved
	# off _set_one_timer_ready for threading (AICoordinator does the same on the
	# host), so the frozen view reflects it next frame.
	for s: SimSkater in skaters:
		if s.agent != null:
			s.agent.push_one_timer_ready()
	if collect_perf:
		perf_tick_us.append(tick_ai_us)
	# Releases (pass/shot fired by the carrier): quick-shot edge, or a held
	# charge dropping. The puck leaves along the shooter's aim. A charge
	# dropped with the OTHER shot button pressed is the cancel, not a release
	# (SkaterStateMachine's wrister aim and slapper charge both bail on it).
	if carrier_id != -1:
		var c: SimSkater = _skater(carrier_id)
		# The settle lock holds every on-puck press (SkaterSettleGate).
		var released: bool = ticks >= c.settle_until and (c.input.quick_pass_pressed
				or (c.was_holding_shot and not c.input.shoot_held
						and not c.input.slap_pressed)
				or (c.was_holding_slap and not c.input.slap_held
						and not c.input.shoot_pressed))
		if released:
			# The release record carries the DECISION CONTEXT alongside the
			# event (all additive keys — older consumers read tick/peer only):
			# the carrier's intent and its compete debug scores at the moment
			# of firing, so scenario harnesses can trace WHY a release
			# happened and, later, compare scored completion odds against the
			# actual outcome (the calibration-probe loop).
			var rec: Dictionary = {"tick": ticks, "peer": c.peer_id,
					"team": c.team_id, "pos": c.pos}
			if c.agent != null and c.agent._carrier != null:
				rec["decision"] = c.agent.debug_last_decision
				rec["intent"] = c.agent._carrier.intended_action
				rec["pass_peer"] = c.agent._carrier.debug_pass_peer_id
				rec["pass_score"] = c.agent._carrier.debug_pass_score
				rec["carry_score"] = c.agent._carrier.debug_carry_score
			releases.append(rec)
			_release_grace[c.peer_id] = ticks + RELEASE_GRACE_TICKS
			_release(c)
			carrier_id = -1
	_puckless_swings()
	# Integrate bodies + blades.
	for s: SimSkater in skaters:
		if s.agent == null:
			if s.script_path.is_empty():
				_puppet_step(s)
			else:
				_script_step(s)
			continue
		# The controller's order: the move on last tick's facing, then the hips'
		# turn, then the blade in the frame the turn left.
		if _down(s):
			s.vel = s.vel.move_toward(Vector3.ZERO, _match_body.knockdown_friction * DT)
			s.pos += s.vel * DT
			s.turn_rate = 0.0
			s.facing_ang_vel = 0.0
		else:
			_move(s)
			_face(s)
		_hold_on_ice(s)
		s.prev_blade = s.blade
		_place_blade(s)
		s.slap_charge_s = s.slap_charge_s + DT if s.input.slap_held else 0.0
	_resolve_contacts()
	for s: SimSkater in skaters:
		if s.agent != null:
			_advance_stick_check(s)
	_tick_ties()
	# Puck.
	var prev_puck: Vector3 = puck_pos
	if carrier_id != -1:
		var c2: SimSkater = _skater(carrier_id)
		puck_pos = c2.blade
		puck_vel = c2.vel
		carry_ticks[carrier_id] += 1
		# Strips: an opponent's blade sweeping through the carried puck. A
		# scripted carrier holds possession by construction.
		for s: SimSkater in skaters:
			if not c2.script_path.is_empty():
				break
			if s.team_id == c2.team_id or not s.puppet_can_strip:
				continue
			# Down, or committed to a check, the stick is off the ice
			# (PuckController's poke gates).
			if s.knockdown > 0.0 or s.hit_active:
				continue
			# A hooking blade under the carrier's shaft lifts his stick; a stick
			# mid-lift or otherwise up pokes nothing.
			if s.check_phase == StickCheckRules.Phase.HOOK:
				if ticks >= s.check_cooling_until and PuckInteractionRules.check_blade_under_stick(
						s.blade, _hand(c2), c2.blade, GameRules.STICK_LIFT_RADIUS_M, 0.0):
					_land_lift(s, c2)
					break
				continue
			if _stick_up(s) or StickCheckRules.is_stick_busy(s.check_phase):
				continue
			if PuckInteractionRules.check_poke(
					prev_puck, puck_pos, s.prev_blade, s.blade, GameRules.POKE_RADIUS_M):
				strips += 1
				carrier_id = -1
				var poker_v: Vector3 = (s.blade - s.prev_blade) / DT
				var carrier_v: Vector3 = (c2.blade - c2.prev_blade) / DT
				puck_vel = PuckCollisionRules.poke_strip_velocity(poker_v, carrier_v,
						c2.pos, s.pos, POKE_CARRIER_VEL_BLEND, POKE_STRIP_MIN_M_S,
						POKE_STRIP_MAX_M_S, c2.pos - s.pos)
				_hop(PuckCollisionRules.pinch_lift_speed(poker_v, carrier_v, s.prev_blade,
						c2.blade, PINCH_LIFT_THRESHOLD_M_S, PINCH_LIFT_GAIN, PINCH_LIFT_MAX_M_S))
				_release_grace[c2.peer_id] = ticks + STRIP_REATTACH_TICKS
				_release_grace[s.peer_id] = ticks + STRIP_CHECKER_TICKS
				break
	elif airborne_ticks > 0:
		# In the air: ballistic ground track, untouchable, lands with a
		# bounce/skid speed loss. Rink clamp still applies (a chip into the
		# glass drops at the boards).
		airborne_ticks -= 1
		puck_pos += puck_vel * DT
		var clamped_air: Vector2 = GameRules.clamp_to_rink_inner(
				Vector2(puck_pos.x, puck_pos.z))
		if clamped_air.x != puck_pos.x or clamped_air.y != puck_pos.z:
			airborne_ticks = 0
			var outward_air := Vector2(puck_pos.x - clamped_air.x, puck_pos.z - clamped_air.y)
			puck_vel = PuckCollisionRules.board_rescue_velocity(
					puck_vel, outward_air, BOARD_RESTITUTION)
			puck_pos = Vector3(clamped_air.x, puck_pos.y, clamped_air.y)
		if airborne_ticks == 0:
			puck_vel *= _airborne_keep
			_airborne_keep = LANDING_SPEED_KEEP
	else:
		var speed: float = Vector2(puck_vel.x, puck_vel.z).length()
		if speed > 0.0:
			var drop: float = GameRules.PUCK_ICE_DECEL_M_S2 * DT
			var scale: float = maxf(speed - drop, 0.0) / speed
			puck_vel *= scale
		puck_pos += puck_vel * DT
		# Boards: clamp to the rink and reflect the outward component (the
		# same analytic backstop the real Puck runs). Without this a dumped
		# or rimmed puck sailed out of the world and every loose-puck
		# scenario beyond a few metres was unwinnable by construction —
		# and rims can't wrap corners a harness doesn't have.
		var clamped: Vector2 = GameRules.clamp_to_rink_inner(
				Vector2(puck_pos.x, puck_pos.z))
		if clamped.x != puck_pos.x or clamped.y != puck_pos.z:
			var outward := Vector2(puck_pos.x - clamped.x, puck_pos.z - clamped.y)
			puck_vel = PuckCollisionRules.board_rescue_velocity(
					puck_vel, outward, BOARD_RESTITUTION)
			puck_pos = Vector3(clamped.x, puck_pos.y, clamped.y)
		for s: SimSkater in skaters:
			if not _can_play(s) or not PuckInteractionRules.check_pickup(
					prev_puck, puck_pos, s.prev_blade, s.blade, PICKUP_RADIUS):
				continue
			var rel: Vector3 = puck_vel - s.vel
			rel.y = 0.0
			var face: Vector3 = _face_normal(s, rel)
			var catch_load: float = PuckReceptionRules.reception_load(
					Vector3(puck_vel.x, 0.0, puck_vel.z), Vector3(s.vel.x, 0.0, s.vel.z),
					face, DEFLECT_MIN_REL_SPEED, RECEIVE_ALIGNMENT_BONUS)
			if not _receives(s, face):
				# Too fast to hold: it comes off the face (Puck.apply_blade_deflect).
				puck_vel = PuckCollisionRules.deflect_velocity(puck_vel,
						_face_normal(s, puck_vel), AIFeedReception.DEFLECT_NORMAL_RESTITUTION,
						AIFeedReception.DEFLECT_NORMAL_RESTITUTION_MIN, DEFLECT_TANGENTIAL_RETAIN,
						AIFeedReception.DEFLECT_SPEED_REF_M_S)
				puck_vel.y = 0.0
				_release_grace[s.peer_id] = ticks + (BOBBLE_COOLDOWN_TICKS
						if puck_vel.length() < BOBBLE_SPEED_M_S else DEFLECT_COOLDOWN_TICKS)
				deflects += 1
				break
			var axis: Vector3 = PuckReceptionRules.blade_axis(s.blade, _hand(s),
					Vector3(s.facing.x, 0.0, s.facing.y))
			var bobble_at: float = PuckReceptionRules.bobble_load_at(
					PuckReceptionRules.blade_contact_offset(puck_pos, rel, s.blade, axis,
							GameRules.DEFAULT_BLADE_LENGTH_M * 0.5),
					BOBBLE_LOAD, BOBBLE_EDGE_SHARE)
			if catch_load >= bobble_at:
				var out: Vector3 = PuckCollisionRules.bobble_velocity(
						rel, face, AIFeedReception.DEFLECT_NORMAL_RESTITUTION,
						AIFeedReception.DEFLECT_NORMAL_RESTITUTION_MIN,
						AIFeedReception.DEFLECT_SPEED_REF_M_S, AIFeedReception.BOBBLE_TANGENTIAL_RETAIN,
						AIFeedReception.BOBBLE_PACE_RETAIN)
				puck_vel = Vector3(s.vel.x + out.x, 0.0, s.vel.z + out.z)
				_hop(PuckCollisionRules.squeeze_lift_speed(-rel.dot(face),
						BOBBLE_LIFT_THRESHOLD_M_S, BOBBLE_LIFT_GAIN, BOBBLE_LIFT_MAX_M_S))
				_release_grace[s.peer_id] = ticks + BOBBLE_GRACE_TICKS
				bobbles += 1
				break
			# A second blade corralling it on the same tick contests it: nobody gets
			# it (PuckController.apply_contested_pickup).
			var rival: SimSkater = _contesting(s, prev_puck)
			if rival != null:
				var a_v: Vector3 = (s.blade - s.prev_blade) / DT
				var b_v: Vector3 = (rival.blade - rival.prev_blade) / DT
				puck_vel = PuckCollisionRules.contested_pickup_velocity(a_v, b_v, s.blade,
						rival.blade, CONTEST_MIN_M_S, CONTEST_MAX_M_S, CONTEST_DEADLOCK_M_S,
						CONTEST_DEADLOCK_THRESHOLD_M_S, 1.0, puck_vel)
				_hop(PuckCollisionRules.pinch_lift_speed(a_v, b_v, s.blade, rival.blade,
						PINCH_LIFT_THRESHOLD_M_S, PINCH_LIFT_GAIN, PINCH_LIFT_MAX_M_S))
				_release_grace[s.peer_id] = ticks + STRIP_REATTACH_TICKS
				_release_grace[rival.peer_id] = ticks + STRIP_REATTACH_TICKS
				contests += 1
				break
			carrier_id = s.peer_id
			puck_pos = s.blade
			puck_vel = s.vel
			s.settle_until = ticks + roundi(PuckReceptionRules.settle_time(catch_load,
					AIFeedReception.SETTLE_CLEAN_LOAD, AIFeedReception.SETTLE_MAX_S) / DT)
			break


# The knockdown's clock (SkaterController._apply_movement): true while he is down,
# when input is ignored and the body slides out its momentum. Coming up, he finds
# his legs through a short stagger.
func _down(s: SimSkater) -> bool:
	var was_down: bool = s.knockdown > 0.0
	s.knockdown = maxf(s.knockdown - DT, 0.0)
	if was_down and s.knockdown <= 0.0:
		s.stagger = maxf(s.stagger, _match_body.getup_stagger_s)
	if s.knockdown <= 0.0:
		return false
	s.hit_active = false
	s.stance_active = false
	s.stagger = maxf(s.stagger - DT, 0.0)
	return true


# One tick of skating (SkaterController._apply_movement): the commit and the
# stance from the buttons (neither while wound up or rocked), the stagger's grip
# and thrust penalties, and a wound-up body only gliding, or shuffling on the
# brake while it waits on a feed.
func _move(s: SimSkater) -> void:
	var carrying: bool = carrier_id == s.peer_id
	var loaded: bool = s.input.slap_held or s.swing_at >= ticks
	var cfg: BodyCheckRules.Config = _match_body.check_cfg
	var rocked: bool = BodyCheckRules.is_rocked(s.stagger, cfg)
	s.hit_active = not loaded and s.input.hit_held and not rocked
	s.stance_active = not loaded and s.input.stance_held and not s.hit_active and not rocked
	s.stagger = maxf(s.stagger - DT, 0.0)
	var stick: Vector2 = s.input.move_vector
	var brake: bool = s.input.brake
	if loaded:
		brake = brake and s.input.slap_held and not carrying
		if not brake:
			stick = Vector2.ZERO
	var base_thrust: float = move_cfg.thrust
	move_cfg.thrust = base_thrust * BodyCheckRules.thrust_mult(s.stagger, cfg)
	s.vel = SkaterMovementRules.apply_movement(s.vel, stick, atan2(-s.facing.x, -s.facing.y),
			carrying, brake, DT, move_cfg,
			SkaterMovementRules.posture_of(s.stance_active, s.hit_active),
			BodyCheckRules.grip_mult(s.stagger, cfg))
	move_cfg.thrust = base_thrust
	s.pos += s.vel * DT


# Skater.clamp_body_to_rink and clamp_body_to_net: the body's edge stops at the
# boards and the net's panels, sliding along them.
func _hold_on_ice(s: SimSkater) -> void:
	var r: float = _match_body.radius
	var xz := Vector2(s.pos.x, s.pos.z)
	var held: Vector2 = GameRules.push_out_of_net(GameRules.clamp_to_rink_inner(xz, r), r)
	if xz.distance_squared_to(held) <= 1e-6:
		return
	var inward: Vector2 = (held - xz).normalized()
	var v := Vector2(s.vel.x, s.vel.z)
	var into: float = v.dot(inward)
	if into < 0.0:
		v -= into * inward
		s.vel = Vector3(v.x, s.vel.y, v.y)
	s.pos = Vector3(held.x, s.pos.y, held.y)


func _delivers(s: SimSkater) -> bool:
	return s.hit_active and carrier_id != s.peer_id


# Skater._resolve_player_collisions: each overlapping pair once, from the side
# closing harder (the lower id on a tie), each body taking its own Δv as a hit
# (the boards behind it counted), and a real closing hit is the committed
# body's check — a carrier struck hard enough loses the puck (Puck.on_body_check).
func _resolve_contacts() -> void:
	var body: RefCounted = _match_body
	var reach: float = 2.0 * body.radius
	for i: int in skaters.size():
		for j: int in range(i + 1, skaters.size()):
			var a: SimSkater = skaters[i]
			var b: SimSkater = skaters[j]
			var d := Vector3(b.pos.x - a.pos.x, 0.0, b.pos.z - a.pos.z)
			var dist: float = d.length()
			if dist >= reach:
				continue
			var n: Vector3 = Vector3(1.0, 0.0, 0.0) if dist < 0.0001 else d / dist
			var agg: float = (a.vel + b.vel).dot(n)
			if agg < -0.0001 or (absf(agg) <= 0.0001 and a.peer_id > b.peer_id):
				var t: SimSkater = a
				a = b
				b = t
				n = -n
			var contact: float = body.contact_transfer(a.hit_active, carrier_id == a.peer_id,
					b.hit_active, carrier_id == b.peer_id)
			SkaterCollisionRules.resolve(_collision, a.pos, a.vel, body.weight, body.radius,
					b.pos, b.vel, body.weight, body.radius, contact)
			if not _collision.overlapping:
				continue
			a.pos += _collision.sep_a
			a.vel += _collision.dvel_a
			b.pos += _collision.sep_b
			b.vel += _collision.dvel_b
			_take_hit(a, _collision.dvel_a, -n, contact)
			_take_hit(b, _collision.dvel_b, n, contact)
			if not _collision.impulse_applied:
				continue
			var checker: SimSkater = b if _delivers(b) and not _delivers(a) else a
			var victim: SimSkater = a if checker == b else b
			_check_strip(checker, victim, n if checker == a else -n, contact)


# A Δv landing on `s`, driven along `n` (toward him).
func _take_hit(s: SimSkater, dv: Vector3, n: Vector3, contact: float) -> void:
	if dv.length_squared() <= 0.0001:
		return
	var strength: float = BoardPinRules.backstop_hit_strength(dv.length(),
			_collision.closing_speed, contact, Vector2(n.x, n.z),
			BoardPinRules.wall_normal(s.pos, _match_body.radius, BoardPinRules.BACKSTOP_MARGIN_M),
			_match_body.weight, _match_body.weight)
	var timers: Vector2 = _match_body.absorb(s.stagger, s.knockdown, dv, strength, s.facing,
			s.stance_active, SkaterStateMachine.state_off_balance(_shot_state(s)), _delivers(s))
	s.stagger = timers.x
	s.knockdown = timers.y


# Puck.on_body_check: a hard hit locks the struck body off the puck, and one hard
# enough on the carrier knocks it off his stick along the hit.
func _check_strip(checker: SimSkater, victim: SimSkater, n: Vector3, contact: float) -> void:
	var delivered: float = _match_body.strip_impulse(_collision.closing_speed, contact,
			Vector2(n.x, n.z),
			BoardPinRules.wall_normal(victim.pos, _match_body.radius, BoardPinRules.BACKSTOP_MARGIN_M))
	if delivered < _match_body.hit_cooldown_threshold:
		return
	_release_grace[victim.peer_id] = maxi(int(_release_grace.get(victim.peer_id, 0)),
			ticks + roundi(_match_body.hit_cooldown_s / DT))
	if carrier_id != victim.peer_id or delivered < _match_body.strip_threshold:
		return
	hit_strips += 1
	carrier_id = -1
	puck_vel = _match_body.strip_velocity(n, delivered)
	_release_grace[victim.peer_id] = ticks + STRIP_REATTACH_TICKS
	_release_grace[checker.peer_id] = ticks + STRIP_CHECKER_TICKS


# The blade this tick. A wrister charge freezes it body-relative where the press
# found it (SkaterController._apply_wrister_aim_blade): the wind-up cursor never
# moves the puck, and the release fires from the hold. A carried slapshot takes
# it to the strike spot (SkaterController._apply_slapper_setup).
func _place_blade(s: SimSkater) -> void:
	var carrying: bool = carrier_id == s.peer_id
	var in_charge: bool = s.input.shoot_held and carrying
	if in_charge and not s.wrister_active:
		s.wrister_active = true
		s.wrister_hold = s.arm.heel - s.pos
	var held: bool = s.wrister_active
	s.wrister_active = in_charge
	var cursor: Vector3 = s.input.mouse_world_pos
	if s.input.slap_held and carrying:
		cursor = _strike_spot(s)
	if s.blade_reach != INF:
		var to_cursor: Vector3 = cursor - s.pos
		to_cursor.y = 0.0
		var desired: Vector3 = s.pos + s.wrister_hold if held \
				else s.pos + to_cursor.limit_length(s.blade_reach)
		s.blade += (desired - s.blade).limit_length((MAX_BLADE_SPEED + s.vel.length()) * DT)
		s.arm.heel = s.blade
		return
	s.arm.speed_cap = StickCheckRules.TIE_BLADE_SPEED_M_S if s.tied_with != -1 else INF
	_match_rig.step(s.arm, s.pos, s.facing, cursor, carrying, s.agent._is_left_handed,
			puck_pos, puck_vel, held, s.wrister_hold, DT)
	s.blade = s.arm.contact


# Where this body strikes a slapshot (the build's strike spot, in its facing).
func _strike_spot(s: SimSkater) -> Vector3:
	var strike: Vector2 = _caps.slapper_strike_local
	var off: Vector2 = SlapperRules.local_to_world(Vector2(
			strike.x * (-1.0 if s.agent._is_left_handed else 1.0), strike.y), s.facing)
	return Vector3(s.pos.x + off.x, 0.0, s.pos.z + off.y)


# The hips' turn this tick, as SkaterPoseCoordinator.apply_facing turns them:
# frozen through a wrister charge, pivoting to the shot's stance through a
# slapper charge, otherwise the facing rule's target (squared along the boards
# for a carrier on them, turned round by angle to anything behind, a carrier's
# yielding to a cursor round its forehand) — every turn wound up at the body's
# turn acceleration.
func _face(s: SimSkater) -> void:
	var was: float = atan2(s.facing.x, s.facing.y)
	_turn(s)
	s.facing_ang_vel = angle_difference(was, atan2(s.facing.x, s.facing.y)) / DT


func _turn(s: SimSkater) -> void:
	if s.wrister_active:
		s.turn_rate = 0.0
		return
	var turned: Vector2
	var slap_line := Vector2(s.input.bot_slapper_aim_dir.x, s.input.bot_slapper_aim_dir.z)
	if s.swing_at >= ticks:
		slap_line = Vector2(s.swing_aim.x, s.swing_aim.z)
	var lefty: bool = s.agent._is_left_handed
	var to_mouse := Vector2(s.input.mouse_world_pos.x - s.pos.x,
			s.input.mouse_world_pos.z - s.pos.z)
	if (s.input.slap_held or s.swing_at >= ticks) and slap_line != Vector2.ZERO:
		var stance: Vector2 = SlapperRules.stance_facing(slap_line.normalized(),
				-1.0 if lefty else 1.0, _caps.slapper_stance_open_rad)
		var step_rad: float = _caps.slapper_stance_turn_rad_s * DT
		turned = s.facing.rotated(clampf(s.facing.angle_to(stance), -step_rad, step_rad))
	elif to_mouse.length() > move_cfg.move_deadzone:
		var carrying: bool = carrier_id == s.peer_id
		var cursor_dir: Vector2 = to_mouse.normalized()
		FacingRules.solve(_facing_rule, s.facing, cursor_dir,
				Vector2(s.vel.x, s.vel.z), s.input.brake, s.input.stance_held, lefty,
				_carry_facing_cfg if carrying else _facing_cfg)
		var target: Vector2 = _facing_rule.target
		if carrying:
			target = BoardPlayRules.board_shield_facing(target, BoardPlayRules.board_proximity(
					Vector2(s.pos.x, s.pos.z), _caps.board_shield_probe), _caps.board_shield_max_rad)
		var drag: float = _caps.facing_drag_speed_braking if s.input.brake \
				else _caps.facing_drag_speed
		if absf(s.facing.angle_to(cursor_dir)) >= FacingRules.reach_edge(
				_facing_cfg, s.facing, cursor_dir, lefty) \
				or absf(s.facing.angle_to(target)) >= FacingRules.reach_edge(
						_facing_cfg, s.facing, target, lefty):
			turned = s.facing.rotated(FacingRules.turn_round_angle(s.facing, target,
					cursor_dir) * minf(drag * DT, 1.0))
		else:
			turned = s.facing.lerp(target, drag * DT).normalized()
		if carrying:
			turned = FacingRules.yield_on_forehand(turned, cursor_dir, lefty, _carry_facing_cfg)
	else:
		s.turn_rate = 0.0
		return
	s.turn_rate = FacingRules.turn_rate(s.turn_rate, s.facing.angle_to(turned) / DT,
			_caps.facing_turn_accel_max, DT)
	s.facing = s.facing.rotated(s.turn_rate * DT)


# One containment tick: P-control (accel-limited, speed-capped) toward the
# hold point on the [seen puck → own net] line, clamped at the depth floor;
# facing and blade play the reaction-delayed puck (the presented blade is a
# live poke threat — check_poke strips a puck carried into it).
func _puppet_step(s: SimSkater) -> void:
	var seen: Vector3 = _puck_history[maxi(0, _puck_history.size() - 1 - PUPPET_REACTION_TICKS)]
	var own_net_z: float = (1.0 if s.team_id == 0 else -1.0) * GameRules.GOAL_LINE_Z
	var to_net := Vector3(-seen.x, 0.0, own_net_z - seen.z)
	var target: Vector3 = seen
	if to_net.length() > 0.001:
		target = seen + to_net.normalized() * s.puppet_hold_gap
	if s.team_id == 0:
		target.z = minf(target.z, s.puppet_depth_floor_z)
	else:
		target.z = maxf(target.z, s.puppet_depth_floor_z)
	var err := Vector3(target.x - s.pos.x, 0.0, target.z - s.pos.z)
	var desired: Vector3 = (err * PUPPET_GAIN).limit_length(PUPPET_MAX_SPEED_M_S)
	s.vel += (desired - s.vel).limit_length(PUPPET_ACCEL_M_S2 * DT)
	s.pos += s.vel * DT
	var to_puck := Vector2(seen.x - s.pos.x, seen.z - s.pos.z)
	if to_puck.length() > 0.05:
		s.facing = s.facing.lerp(to_puck.normalized(), FACING_DRAG * DT).normalized()
	s.prev_blade = s.blade
	var reach := Vector3(to_puck.x, 0.0, to_puck.y).limit_length(BLADE_REACH * 0.8)
	var max_step: float = (MAX_BLADE_SPEED + s.vel.length()) * DT
	s.blade = s.blade + (s.pos + reach - s.blade).limit_length(max_step)


# One scripted tick: accel-limited toward the current waypoint at the path's
# pace, advancing (and looping) on arrival; facing the attacked net, blade
# carried out in front.
func _script_step(s: SimSkater) -> void:
	var target: Vector3 = s.script_path[s.script_idx]
	var err := Vector3(target.x - s.pos.x, 0.0, target.z - s.pos.z)
	if err.length() < SCRIPT_ARRIVE_M:
		s.script_idx = (s.script_idx + 1) % s.script_path.size()
		target = s.script_path[s.script_idx]
		err = Vector3(target.x - s.pos.x, 0.0, target.z - s.pos.z)
	if s.script_skates:
		_script_skate(s, err)
		return
	var desired: Vector3 = (err * PUPPET_GAIN).limit_length(s.script_speed)
	s.vel += (desired - s.vel).limit_length(PUPPET_ACCEL_M_S2 * DT)
	s.pos += s.vel * DT
	var attacked_net_z: float = (-1.0 if s.team_id == 0 else 1.0) * GameRules.GOAL_LINE_Z
	var to_net := Vector2(-s.pos.x, attacked_net_z - s.pos.z)
	if to_net.length() > 0.05:
		s.facing = to_net.normalized()
	s.prev_blade = s.blade
	s.blade = s.pos + Vector3(s.facing.x, 0.0, s.facing.y) * SCRIPT_CARRY_REACH_M


# The real stride toward the waypoint, facing travel, never past script_speed:
# full drive while under it, a glide once there.
func _script_skate(s: SimSkater, err: Vector3) -> void:
	var dir := Vector2(err.x, err.z)
	if dir.length() > 0.001:
		dir = dir.normalized()
		s.facing = dir
	var move: Vector2 = dir if Vector2(s.vel.x, s.vel.z).length() < s.script_speed \
			else Vector2.ZERO
	s.vel = SkaterMovementRules.apply_movement(s.vel, move,
			atan2(-s.facing.x, -s.facing.y), carrier_id == s.peer_id, false, DT,
			move_cfg)
	s.pos += s.vel * DT
	s.prev_blade = s.blade
	s.blade = s.pos + Vector3(s.facing.x, 0.0, s.facing.y) * SCRIPT_CARRY_REACH_M


# Whether `s` may play a loose puck this tick (PuckController's pickup gates): a
# body with a stick — a puppet contains and pokes, it never carries — off its
# cooldown, not committed to a check, not through a follow-through, and not
# wound up for a one-timer, whose blade is overhead.
func _can_play(s: SimSkater) -> bool:
	return s.agent != null and ticks >= int(_release_grace.get(s.peer_id, 0)) \
			and s.knockdown <= 0.0 and not s.hit_active and s.follow_until <= ticks \
			and not s.input.slap_held and s.swing_at < ticks \
			and not StickCheckRules.is_stick_busy(s.check_phase) and not _stick_up(s)


# A blade held off the ice by a lift that landed on it or a tie: it meets only an
# airborne puck (PuckReceptionRules.blade_can_interact), which no blade plays here.
func _stick_up(s: SimSkater) -> bool:
	return s.lifted_until > ticks or s.tied_with != -1


# SkaterController._advance_stick_check: a lift starts only from plain puckless
# skating, and anything else taking the stick ends it.
func _advance_stick_check(s: SimSkater) -> void:
	var taken: bool = carrier_id == s.peer_id or s.hit_active or s.knockdown > 0.0 \
			or _stick_up(s) \
			or _shot_state(s) != SkaterStateMachine.State.SKATING_WITHOUT_PUCK
	var next: Vector2 = StickCheckRules.step(s.check_phase, s.check_elapsed,
			s.input.stick_check_pressed and not s.input.hit_held, s.input.stick_check_held,
			not taken, taken, DT)
	s.check_phase = int(next.x)
	s.check_elapsed = next.y


# PuckController._land_stick_lift: the lifter cools, the carrier's stick is up
# for as long as the hook was good, and the puck goes on at his pace.
func _land_lift(lifter: SimSkater, c: SimSkater) -> void:
	lifts += 1
	var forced_s: float = StickCheckRules.forced_lift_seconds(StickCheckRules.hook_quality(
			PuckInteractionRules.distance_to_shaft(lifter.blade, _hand(c), c.blade),
			GameRules.STICK_LIFT_RADIUS_M))
	lifter.check_cooling_until = ticks + roundi(StickCheckRules.STICK_CHECK_COOLDOWN_S / DT)
	c.lifted_until = ticks + roundi(forced_s / DT)
	carrier_id = -1
	puck_vel = Vector3(c.vel.x, 0.0, c.vel.z)
	_release_grace[c.peer_id] = ticks + maxi(STRIP_REATTACH_TICKS,
			roundi((forced_s + StickCheckRules.REGRAB_MARGIN_S) / DT))


# StickTieTracker.tick: held pairs hold while either holds the button and the
# sticks stay together (breaking cools both), and a stick reaching in TIE latches
# the nearest free opponent's that it touches.
func _tick_ties() -> void:
	for a: SimSkater in skaters:
		if a.tied_with == -1 or a.tied_with < a.peer_id:
			continue
		var b: SimSkater = _skater(a.tied_with)
		var holds: bool = (a.input.stick_check_held or b.input.stick_check_held) \
				and a.knockdown <= 0.0 and b.knockdown <= 0.0 \
				and carrier_id != a.peer_id and carrier_id != b.peer_id \
				and _stick_gap(a, b) <= StickCheckRules.TIE_SEPARATION_M
		if not holds:
			a.tied_with = -1
			b.tied_with = -1
			var cool: int = ticks + roundi(StickCheckRules.STICK_CHECK_COOLDOWN_S / DT)
			a.check_cooling_until = cool
			b.check_cooling_until = cool
	for a: SimSkater in skaters:
		if a.agent == null or a.check_phase != StickCheckRules.Phase.TIE or a.tied_with != -1 \
				or ticks < a.check_cooling_until or a.knockdown > 0.0:
			continue
		var best: SimSkater = null
		var best_d: float = StickCheckRules.TIE_CONTACT_M
		for v: SimSkater in skaters:
			if v.team_id == a.team_id or v.tied_with != -1 or v.peer_id == carrier_id \
					or v.knockdown > 0.0:
				continue
			var d: float = _stick_gap(a, v)
			if d <= best_d:
				best_d = d
				best = v
		if best != null:
			a.tied_with = best.peer_id
			best.tied_with = a.peer_id


func _stick_gap(a: SimSkater, b: SimSkater) -> float:
	return StickCheckRules.stick_gap(_hand(a), a.blade, _hand(b), b.blade)


func _hand(s: SimSkater) -> Vector3:
	return s.arm.hand if s.blade_reach == INF else s.pos


# Skater.get_blade_face_normal: the face square to `toward` across the shaft.
func _face_normal(s: SimSkater, toward: Vector3) -> Vector3:
	return PuckReceptionRules.blade_face_normal(s.blade, _hand(s), toward,
			Vector3(s.facing.x, 0.0, s.facing.y))


func _receives(s: SimSkater, face: Vector3) -> bool:
	return PuckReceptionRules.should_receive(Vector3(puck_vel.x, 0.0, puck_vel.z),
			Vector3(s.vel.x, 0.0, s.vel.z), face, PICKUP_MAX_REL_SPEED,
			DEFLECT_MIN_REL_SPEED, RECEIVE_ALIGNMENT_BONUS)


# Another blade that would also take the puck `s` is taking this tick.
func _contesting(s: SimSkater, prev_puck: Vector3) -> SimSkater:
	for o: SimSkater in skaters:
		if o == s or not _can_play(o) or not PuckInteractionRules.check_pickup(
				prev_puck, puck_pos, o.prev_blade, o.blade, PICKUP_RADIUS):
			continue
		var rel: Vector3 = puck_vel - o.vel
		rel.y = 0.0
		if _receives(o, _face_normal(o, rel)):
			return o
	return null


# A puck knocked up off the ice at `vy`: out of every blade's reach while it is
# above the blade plane, its ground track carrying on.
func _hop(vy: float) -> void:
	var h: float = GameRules.PUCK_AIRBORNE_HEIGHT_M
	var disc: float = vy * vy - 2.0 * GameRules.GRAVITY_M_S2 * h
	if vy <= 0.0 or disc <= 0.0:
		return
	airborne_ticks = maxi(airborne_ticks, roundi((vy + sqrt(disc)) / GameRules.GRAVITY_M_S2 / DT))
	_airborne_keep = 1.0


# A puckless slapper swing: armed as the button drops, it lands after the
# retention hold and fires a loose puck it meets in the slapper zone
# (ShotReleaseRules.one_timer_connects) from there, along its committed aim.
func _puckless_swings() -> void:
	for s: SimSkater in skaters:
		if s.agent == null or carrier_id == s.peer_id:
			continue
		# The swing commits: a press through its retention hold is ignored
		# (SkaterStateMachine._state_one_timer_retention).
		if s.was_holding_slap and not s.input.slap_held and not s.input.shoot_pressed \
				and s.swing_at < ticks:
			s.swing_at = ticks + ONE_TIMER_RETENTION_TICKS
			s.swing_aim = s.input.bot_slapper_aim_dir
			s.swing_charge_s = s.slap_charge_s
		if s.swing_at != ticks:
			continue
		s.swing_at = -1
		if carrier_id != -1 or ticks < int(_release_grace.get(s.peer_id, 0)):
			continue
		var zone: Vector3 = _strike_spot(s)
		if not ShotReleaseRules.one_timer_connects(Vector2(zone.x, zone.z),
				SLAPPER_ZONE_RADIUS_M, Vector2(puck_pos.x, puck_pos.z),
				Vector2(puck_vel.x, puck_vel.z), airborne_ticks > 0,
				ONE_TIMER_LENIENCY_S + ONE_TIMER_RETENTION_TICKS * DT, ONE_TIMER_LENIENCY_S):
			continue
		releases.append({"tick": ticks, "peer": s.peer_id, "team": s.team_id,
				"pos": s.pos, "decision": "ONE_TIMER"})
		_release_grace[s.peer_id] = ticks + RELEASE_GRACE_TICKS
		var aim := Vector3(s.swing_aim.x, 0.0, s.swing_aim.z)
		if aim.length_squared() < 0.0001:
			aim = Vector3(s.facing.x, 0.0, s.facing.y)
		var result: ShotMechanics.ShotResult = ShotMechanics.release_slapper(zone,
				s.input.mouse_world_pos, s.input.elevation_level, s.swing_charge_s,
				_shot_kit.slapper, aim)
		result.power = ShotReleaseRules.one_timer_power(result.power, _shot_kit.one_timer_bonus,
				Vector2(zone.x, zone.z), Vector2(puck_pos.x, puck_pos.z), SLAPPER_ZONE_RADIUS_M)
		puck_pos = Vector3(zone.x, puck_pos.y, zone.z)
		s.follow_until = ticks + roundi(ShotMechanics.follow_through_time(
				ShotMechanics.slapper_power_t(s.swing_charge_s, _shot_kit.slapper),
				_shot_kit.slapper_finish_min, _shot_kit.slapper_finish_max) / DT)
		_launch(result.direction * result.power)


# The carrier's release as the controller fires it: the quick pass at its fixed
# pace toward the cursor; a charged wrister at the bot's committed power along its
# committed aim, at the backhand's share on the backhand, capped by how far the
# body loads it (WristerLoad); a slapper at its charge's power. Each finishes over
# its follow-through, and a lofted release flies over the sticks.
func _release(c: SimSkater) -> void:
	var kit: ShotKit = _shot_kit
	var lefty: bool = c.agent._is_left_handed
	var result: ShotMechanics.ShotResult
	var finish_s: float
	if c.input.quick_pass_pressed:
		result = ShotMechanics.release_wrister(c.pos, c.input.mouse_world_pos, c.blade, false,
				c.input.elevation_level, kit.wrister, Vector3.ZERO, true)
		finish_s = kit.quick_finish
	elif c.was_holding_slap and not c.input.slap_held:
		result = ShotMechanics.release_slapper(c.blade, c.input.mouse_world_pos,
				c.input.elevation_level, c.slap_charge_s, kit.slapper, c.input.bot_slapper_aim_dir)
		finish_s = ShotMechanics.follow_through_time(
				ShotMechanics.slapper_power_t(c.slap_charge_s, kit.slapper),
				kit.slapper_finish_min, kit.slapper_finish_max)
	else:
		var aim: Vector3 = ShotMechanics.wrister_aim_dir(c.input.bot_wrister_aim_dir,
				c.input.mouse_world_pos, c.pos)
		var to_local: Basis = Basis(Vector3.UP, atan2(-c.facing.x, -c.facing.y)).inverse()
		var pin: Vector3 = c.blade - c.pos
		WristerLoad.solve(_load, to_local * Vector3(pin.x, 0.0, pin.z), to_local * aim,
				lefty, kit.wrister_load)
		result = ShotMechanics.release_wrister(c.pos, c.input.mouse_world_pos, c.blade,
				_load.is_backhand, c.input.elevation_level, kit.wrister, aim, false,
				ShotMechanics.wrister_speed_for_power_t(c.input.bot_wrister_power_t, kit.wrister))
		result.power = minf(result.power, kit.max_wrister * WristerLoad.power_share(
				_load.load_share, _load.arm_share, _load.is_backhand, kit.unloaded_share,
				kit.backhand_coefficient))
		finish_s = ShotMechanics.follow_through_time(clampf((result.power - kit.min_wrister)
				/ maxf(kit.max_wrister - kit.min_wrister, 0.001), 0.0, 1.0),
				kit.wrister_finish_min, kit.wrister_finish_max)
	c.follow_until = ticks + roundi(finish_s / DT)
	_launch(result.direction * result.power)


# The puck off a blade at `v`: along the ice, and over the sticks for as long as
# a lofted one (seated at Puck.release's 0.1 m) is above the blade plane, keeping
# its pace.
func _launch(v: Vector3) -> void:
	puck_vel = Vector3(v.x, 0.0, v.z)
	if v.y <= 0.0:
		return
	var drop: float = LOFT_SEAT_M - GameRules.PUCK_AIRBORNE_HEIGHT_M
	airborne_ticks = roundi((v.y + sqrt(v.y * v.y + 2.0 * GameRules.GRAVITY_M_S2 * drop))
			/ GameRules.GRAVITY_M_S2 / DT)
	_airborne_keep = 1.0


func carrier() -> int:
	return carrier_id


func _skater(peer_id: int) -> SimSkater:
	for s: SimSkater in skaters:
		if s.peer_id == peer_id:
			return s
	return null


func skater_pos(peer_id: int) -> Vector3:
	return _skater(peer_id).pos


func skater_facing(peer_id: int) -> Vector2:
	return _skater(peer_id).facing


# The controller's state as the wire carries it (SkaterStateMachine.State), from
# what the harness plays of it.
func _shot_state(s: SimSkater) -> int:
	var carrying: bool = carrier_id == s.peer_id
	if s.wrister_active:
		return SkaterStateMachine.State.WRISTER_AIM
	if s.input.slap_held:
		return SkaterStateMachine.State.SLAPPER_CHARGE_WITH_PUCK if carrying \
				else SkaterStateMachine.State.SLAPPER_CHARGE_WITHOUT_PUCK
	if s.swing_at >= ticks:
		return SkaterStateMachine.State.ONE_TIMER_RETENTION
	if s.follow_until > ticks:
		return SkaterStateMachine.State.FOLLOW_THROUGH
	return SkaterStateMachine.State.SKATING_WITH_PUCK if carrying \
			else SkaterStateMachine.State.SKATING_WITHOUT_PUCK


func _reaction_delay() -> float:
	if _reaction_delay_s < 0.0:
		var profile: BotSkillProfile = BotSkillProfile.hard()
		for s: SimSkater in skaters:
			if s.profile != null:
				profile = s.profile
				break
		_reaction_delay_s = profile.carrier_reaction_delay_s
	return _reaction_delay_s


func _build_snapshot() -> WorldSnapshot:
	var snap := WorldSnapshot.new()
	for s: SimSkater in skaters:
		var st := SkaterNetworkState.new()
		st.position = s.pos
		st.velocity = s.vel
		st.facing = s.facing
		st.blade_contact_world = s.blade
		st.top_hand_world = s.arm.hand if s.agent != null and s.blade_reach == INF \
				else Vector3(s.pos.x, GameRules.FACEOFF_SPAWN_HEIGHT, s.pos.z) + (s.blade - s.pos) * 0.3
		st.facing_angular_velocity = s.facing_ang_vel
		st.shot_state = _shot_state(s)
		st.elevation_level = s.input.elevation_level
		st.move_intent = s.input.move_vector
		st.brake_intent = s.input.brake
		st.stance_active = s.stance_active
		st.hit_committed = s.hit_active
		st.stagger_timer = s.stagger
		st.knockdown_timer = s.knockdown
		st.stick_check_phase = s.check_phase
		st.stick_check_elapsed = s.check_elapsed
		st.stick_tied = s.tied_with != -1
		st.blade_up = StickCheckRules.blade_held_up(s.lifted_until > ticks, s.check_phase,
				s.tied_with != -1)
		if carrier_id == s.peer_id:
			st.settle_left_s = maxf(float(s.settle_until - ticks) * DT, 0.0)
		snap.skater_states[s.peer_id] = st
	snap.puck_state = PuckNetworkState.new()
	snap.puck_state.position = puck_pos
	snap.puck_state.velocity = puck_vel
	snap.real_puck_carrier_peer_id = carrier_id
	snap.puck_state.carrier_peer_id = _carrier_belief.update(carrier_id, _reaction_delay(), DT)
	# The AI enrichment GameManager publishes in production
	# (_enrich_snapshot_for_ai): team rosters + the hysteretic loose-puck
	# chase election. Without these no bot can ever be the elected chaser
	# (the CHASE_PUCK gate reads the election) and the brain's own race
	# read can't see a playable race — loose-puck scenarios silently played
	# without the production loose-puck machinery.
	for s: SimSkater in skaters:
		var arr: Array = snap.teammate_ids_by_team.get_or_add(s.team_id, [])
		arr.append(s.peer_id)
	for tid: int in snap.teammate_ids_by_team:
		# The camper filter is part of that enrichment too: a one-timer-ready
		# bot has opted out of loose-puck work, so electing him froze the whole
		# team (he refuses the chase, nobody else is elected). Omitting it here
		# ran every loose-puck scenario on an election production never makes.
		var camped: Array = []
		for pid: int in snap.teammate_ids_by_team[tid]:
			if brains[tid].is_one_timer_ready(pid):
				camped.append(pid)
		var elected: int = AILoosePuckChase.elect(
				snap.skater_states, snap.teammate_ids_by_team[tid],
				puck_pos, puck_vel, int(_prev_chase_by_team.get(tid, -1)),
				caps_by_peer, true, [], camped)
		snap.closest_to_puck_by_team[tid] = elected
		_prev_chase_by_team[tid] = elected
	# Static home keepers so shot scoring sees someone in each net (goalie
	# BEHAVIOR is out of scope — this only keeps "empty net!" from dominating
	# every carrier compete).
	for tid: int in [0, 1]:
		var g := GoalieNetworkState.new()
		g.position_x = 0.0
		g.position_z = (1.0 if tid == 0 else -1.0) * (GameRules.GOAL_LINE_Z - 0.8)
		# Real-goalie override (see goalie_provider): a Vector3 replaces the static
		# keeper for this net with the live controller's tracked position.
		if goalie_provider.is_valid():
			var real: Variant = goalie_provider.call(tid, puck_pos)
			if real is Vector3:
				g.position_x = real.x
				g.position_z = real.z
				g.velocity_x = (real.x - float(_keeper_x.get(tid, real.x))) / DT
				_keeper_x[tid] = real.x
		# Facing the puck, as a live keeper turns to it.
		g.rotation_y = atan2(-(puck_pos.x - g.position_x), -(puck_pos.z - g.position_z))
		snap.goalie_states[tid] = g
	return snap
