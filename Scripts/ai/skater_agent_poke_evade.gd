class_name SkaterAgentPokeEvade
extends RefCounted

const _PhysicsConstants: GDScript = preload("res://Scripts/game/constants.gd")

# FAKE-THEN-CUT deke windows, in ticks, derived from AICarrySpace.DEKE_FAKE_S /
# DEKE_CUT_S so the gesture performed is the one the eval priced. The cooldown
# keeps dekes deliberate, occasional moves.
const DEKE_FAKE_TICKS: int = int(
		AICarrySpace.DEKE_FAKE_S * _PhysicsConstants.PHYSICS_TICK)
const DEKE_CUT_TICKS: int = int(
		AICarrySpace.DEKE_CUT_S * _PhysicsConstants.PHYSICS_TICK)
const DEKE_COOLDOWN_TICKS: int = _PhysicsConstants.PHYSICS_TICK   # ~1 s

# One carrier's committed fake-then-cut deke, and the carry cursor that sells
# it. Owns the window and what it latched; the carrier's read and the bot's
# knobs come in per call. Every other answer to pressure — cut, stop, shield —
# is a move the carry rolls out and prices. Public so tests can stage a window;
# the agent itself only calls methods.

# The window and cooldown. While active, the deke overrides move_vector.
var active_ticks: int = 0
var cooldown_ticks: int = 0
# Maneuver LATCHED at trigger: the FAKE-THEN-CUT deke. Phase splits on the
# remaining active ticks (fake while > DEKE_CUT_TICKS, then the cut); both
# directions latched from the carrier's manufactured-opening read at trigger
# (a deke re-read mid-gesture would un-sell the fake).
var deking: bool = false
var deke_fake_dir: Vector2 = Vector2.ZERO
var deke_cut_dir: Vector2 = Vector2.ZERO


# Back to idle: no window, no cooldown, nothing latched.
func reset() -> void:
	active_ticks = 0
	cooldown_ticks = 0
	deking = false
	deke_fake_dir = Vector2.ZERO
	deke_cut_dir = Vector2.ZERO


# The deke: commits when the carrier's re-eval says a fake manufactures an
# opening (deke_go, which carries its own range, closing and protect-tier gates)
# and the carry did not choose to stop — a rolled BRAKE is the carrier's answer
# to this pressure, and a fake would override it.
#
# Lifecycle: while active, drive the gesture and count down, then start the
# cooldown; during the cooldown, normal steering; otherwise check the read.
# `self_vel` is the body's velocity; `upright_lateral_accel` what the bot's edges
# can turn; the window counts down by `dispatch_period_ticks`, the span one call
# covers.
func modulate(input: InputState, self_vel: Vector3, carrier: AIRoleCarrier,
		upright_lateral_accel: float, dispatch_period_ticks: int) -> void:
	var vel_xz := Vector2(self_vel.x, self_vel.z)
	if active_ticks > 0:
		_drive(input, vel_xz, upright_lateral_accel)
		# Decrement by the dispatch span: the window is sized in physics ticks.
		active_ticks -= dispatch_period_ticks
		if active_ticks <= 0:
			active_ticks = 0
			cooldown_ticks = DEKE_COOLDOWN_TICKS
			deking = false
		return
	if cooldown_ticks > 0:
		cooldown_ticks = maxi(0, cooldown_ticks - dispatch_period_ticks)
		return
	if carrier.deke_go and carrier.carry_move != AICarryRollout.Move.BRAKE:
		_start_deke(input, vel_xz, carrier, upright_lateral_accel)


# Latch and start the FAKE-THEN-CUT deke: one committed window covering both
# phases; the drive below splits them on the remaining ticks. Directions come
# from the carrier's manufactured-opening read (same axis frame as the eval,
# so the gesture performed is the gesture priced).
func _start_deke(input: InputState, vel_xz: Vector2, carrier: AIRoleCarrier,
		upright_lateral_accel: float) -> void:
	deking = true
	deke_fake_dir = carrier.deke_fake_dir
	deke_cut_dir = carrier.deke_cut_dir
	active_ticks = DEKE_FAKE_TICKS + DEKE_CUT_TICKS
	_drive(input, vel_xz, upright_lateral_accel)


# One active-window tick: thrust the fake side, then across to the cut side (the
# cursor follows — mouse_target). The cut digs in the stance when the upright
# edges can't turn onto it inside its window (AISteering.stance_cuts_onto).
func _drive(input: InputState, vel_xz: Vector2, upright_lateral_accel: float) -> void:
	var cutting: bool = active_ticks <= DEKE_CUT_TICKS
	input.move_vector = deke_cut_dir if cutting else deke_fake_dir
	input.stance_held = cutting and AISteering.stance_cuts_onto(
			deke_cut_dir, vel_xz, upright_lateral_accel, AICarrySpace.DEKE_CUT_S)


# The deke's carry-cursor override: sell the fake WITH THE PUCK — the
# defender's read tracks the puck, not the chest — then snap it across for
# the cut; the pull through the wide ROM is the visible toe-drag. INF when no
# deke is active (the normal carry aim runs). Board + net clamps keep the
# blade legal against the walls and the cage.
func mouse_target(self_pos: Vector3) -> Vector3:
	if not deking or active_ticks <= 0:
		return Vector3.INF
	var dir: Vector2 = deke_fake_dir \
			if active_ticks > DEKE_CUT_TICKS else deke_cut_dir
	if dir == Vector2.ZERO:
		return Vector3.INF
	var target := Vector3(
			self_pos.x + dir.x * AIBotMechanics.CARRY_BLADE_AIM_FORWARD_M, 0.0,
			self_pos.z + dir.y * AIBotMechanics.CARRY_BLADE_AIM_FORWARD_M)
	var on_ice: Vector2 = GameRules.clamp_to_rink_inner(
			Vector2(target.x, target.z), AIBotMechanics.CARRY_BLADE_WALL_MARGIN_M)
	target.x = on_ice.x
	target.z = on_ice.y
	return AINetObstacle.net_safe_blade_target(self_pos, target)
