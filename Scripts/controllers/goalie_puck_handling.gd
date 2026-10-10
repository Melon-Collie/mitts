class_name GoaliePuckHandling
extends RefCounted

# The goalie with the puck on his stick: how long he holds it, when pressure
# makes him move it, and the release itself. The decision is GoalieOutlet's; the
# release is ShotMechanics', fed exactly as a bot skater feeds it, so a goalie
# pass and a skater pass at the same target leave the blade identically.
#
# Laid out like GoaliePuckPlay: tuning pushed at config time, geometry set once,
# possession state owned outright, and requests the controller reads back after
# `advance()`. Every puck write is the controller's.

enum Origin { CATCH, CREASE, RIM }

# ── Tuning (pushed in by GoalieController._configure_collaborators) ───────────
var read_beat_s: float = 0.4          # s — look up ice before the first release
var max_hold_s: float = 2.0           # s — then the best option goes, whatever it is
var pressure_release_s: float = 0.5   # s — a forechecker this close in time forces the release
var decide_period_s: float = 0.1      # s — re-price the options this often while holding
var reads_motion: bool = true         # tier perception: sees the forecheckers' velocities

# ── Geometry (set once by the controller at setup) ───────────────────────────
var our_net: Vector3 = Vector3.ZERO
var their_net: Vector3 = Vector3.ZERO

# ── Possession state ─────────────────────────────────────────────────────────
var holding: bool = false
var origin: int = Origin.CREASE
var hold_timer: float = 0.0
var decide_timer: float = 0.0
# The velocity he last wrote onto the pinned puck. Anything else found there
# next tick was written by somebody else — a stick, a body — and the puck is
# no longer his.
var pinned_velocity: Vector3 = Vector3.ZERO

# ── Requests to the controller (read after `advance`) ────────────────────────
var lost: bool = false
var wants_release: bool = false
# ZERO with `wants_release` means no option exists from here; the controller
# supplies its own safe exit.
var release_velocity: Vector3 = Vector3.ZERO

var _outlet: GoalieOutlet = GoalieOutlet.new()
var _shot: ShotMechanics.ShotResult = ShotMechanics.ShotResult.new()
var _wrister_cfg: ShotMechanics.WristerConfig = _league_wrister()


func reset() -> void:
	holding = false
	hold_timer = 0.0
	decide_timer = 0.0
	pinned_velocity = Vector3.ZERO
	lost = false
	wants_release = false
	release_velocity = Vector3.ZERO


func begin(from: int) -> void:
	reset()
	holding = true
	origin = from


# The carry point: on the blade's face, in front of it along his facing. The
# puck rides there while he holds it and leaves from there when he releases.
static func carry_spot(blade_pos: Vector3, facing: Vector3, ice_height: float) -> Vector3:
	var flat := Vector3(facing.x, 0.0, facing.z).normalized()
	var spot: Vector3 = blade_pos + flat * (GameRules.PUCK_COLLISION_RADIUS
			+ 0.5 * GoalieStickRules.BLADE_THICKNESS_M)
	spot.y = ice_height
	return spot


func advance(delta: float, carry_pos: Vector3, facing: Vector3,
		puck_vel: Vector3, puck_carried: bool, phase_locked: bool,
		teammates: PackedVector3Array, teammate_vels: PackedVector3Array,
		opponents: PackedVector3Array, opponent_vels: PackedVector3Array) -> void:
	lost = false
	wants_release = false
	release_velocity = Vector3.ZERO
	if not holding:
		return
	if puck_carried or phase_locked or not puck_vel.is_equal_approx(pinned_velocity):
		holding = false
		lost = true
		return
	hold_timer += delta
	decide_timer -= delta
	var pressed: bool = _pressure_eta(carry_pos, opponents, opponent_vels) \
			<= pressure_release_s
	if not pressed and hold_timer < read_beat_s:
		return
	if not pressed and decide_timer > 0.0:
		return
	decide_timer = decide_period_s
	_outlet.evaluate(carry_pos, facing, our_net, their_net, teammates,
			teammate_vels, opponents, opponent_vels, reads_motion)
	# Holding is only worth it while there is a pass that could still become the
	# play: a teammate in front of him getting open. With nobody to pass to there
	# is nothing to wait for.
	var waiting_on_a_pass: bool = _outlet.best_pass.kind == GoalieOutlet.Kind.PASS \
			and _outlet.best.kind != GoalieOutlet.Kind.PASS
	if waiting_on_a_pass and not pressed and hold_timer < max_hold_s:
		return
	var choice: GoalieOutlet.Choice = _outlet.best
	holding = false
	wants_release = true
	if choice.kind != GoalieOutlet.Kind.NONE:
		release_velocity = _release(carry_pos, choice)


# Seconds until the soonest forechecker reaches the puck, INF with nobody.
func _pressure_eta(puck_pos: Vector3, opponents: PackedVector3Array,
		opponent_vels: PackedVector3Array) -> float:
	var best: float = INF
	for i: int in opponents.size():
		var v: Vector3 = opponent_vels[i] if reads_motion and i < opponent_vels.size() \
				else Vector3.ZERO
		best = minf(best, AIActionScoring.time_to_arrive(opponents[i], puck_pos, v))
	return best


# The release a bot skater would make for this choice: a charged flat wrister at
# the solved pace for a pass, the quick release at its fixed pace for a clear.
func _release(blade_pos: Vector3, c: GoalieOutlet.Choice) -> Vector3:
	var to_target := Vector3(c.target.x - blade_pos.x, 0.0, c.target.z - blade_pos.z)
	if c.kind == GoalieOutlet.Kind.CLEAR:
		ShotMechanics.release_wrister(blade_pos, c.target, blade_pos, false,
				c.elevation, _wrister_cfg, Vector3.ZERO, true, 0.0, INF, _shot)
	else:
		var span: float = _wrister_cfg.max_wrister_power - _wrister_cfg.min_wrister_power
		var power_t: float = clampf(
				(c.launch_speed - _wrister_cfg.min_wrister_power) / maxf(span, 0.001), 0.0, 1.0)
		ShotMechanics.release_wrister(blade_pos, c.target, blade_pos, false,
				c.elevation, _wrister_cfg, to_target, false,
				ShotMechanics.wrister_speed_for_power_t(power_t, _wrister_cfg), INF, _shot)
	return _shot.direction * _shot.power


# League-default wrister: the goalie's stick is nobody's build. The pointer
# scale is arbitrary (1.0) because the release is driven through its own
# inverse, and the travel gate is off like every bot's.
static func _league_wrister() -> ShotMechanics.WristerConfig:
	var cfg := ShotMechanics.WristerConfig.new()
	cfg.min_wrister_power = GameRules.DEFAULT_WRISTER_POWER_MIN_M_S
	cfg.max_wrister_power = GameRules.DEFAULT_WRISTER_POWER_MAX_M_S
	cfg.backhand_power_coefficient = 1.0
	cfg.quick_pass_power = GameRules.DEFAULT_QUICK_PASS_POWER_M_S
	cfg.loft_vy_low = GameRules.DEFAULT_LOFT_VY_LOW_M_S
	cfg.loft_vy_high = GameRules.DEFAULT_LOFT_VY_HIGH_M_S
	cfg.power_curve = GameRules.DEFAULT_WRISTER_POWER_CURVE
	cfg.full_sweep_speed = 1.0
	return cfg
