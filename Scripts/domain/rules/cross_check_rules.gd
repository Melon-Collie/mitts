class_name CrossCheckRules
extends RefCounted

# The cross-check on the Ctrl press: the shaft across the opponent in both hands,
# driven by the legs. The press throws it (EXTEND, the only phase that can land),
# the stick comes back (RECOVER), and the next one waits a rearm. Every
# transition is a function of the shover's own inputs, so the host and the
# predicting client step the same phases; whether one lands is the host's
# (CrossCheckTracker, CrossCheckClaimResolver).
#
# The push is a stride delivered through the arms: the force runs through the
# shover's skates, so it is what his stride pushes for PUSH_S, and the victim
# answers it with his edges (across his blades) and his own stride (pushing back
# into it). See victim_dv.

enum Phase { IDLE, EXTEND, RECOVER, REARM }

# The push itself: arms punched out over a short stride. Sized so a neutral
# shove along the blades lands in the stagger band and no legal pair of builds
# reaches a knockdown (test_cross_check_rules.gd holds both).
const PUSH_S: float = 0.10
# The stick back down after it: the cost of a whiff, in the stick's absence.
const RECOVER_S: float = 0.20
# Before the next press throws: about 0.7 s press to press.
const REARM_S: float = 0.40
# Body edge to body edge: an arm's extension with the shaft in both hands.
const REACH_M: float = 0.55
# In front of the chest, where the shaft is: cos 50°.
const CONE_COS: float = 0.6428

# The pose is fully on a third of the way out, so the shaft is across the chest
# before the push lands, and comes off over the last third of the way back.
const _POSE_IN: float = 3.0

# Wire packing: phase in bits 0-1, time elapsed in bits 2-7 as whole ticks. Every
# timed phase ends inside 63 (REARM_S, the longest, is 48 at 120 Hz).
const _WIRE_TICK_HZ: float = 120.0
const _WIRE_MAX_UNITS: int = 63


# One tick of the phase machine. Returns (phase, seconds elapsed in it) as a
# Vector2 so the per-tick call allocates nothing. `can_start` gates a press out
# of IDLE; `interrupted` (knocked down, pinned, a puck on the blade) drops any
# phase to IDLE.
static func step(phase: int, elapsed: float, pressed: bool, can_start: bool,
		interrupted: bool, delta: float) -> Vector2:
	if interrupted:
		return Vector2(Phase.IDLE, 0.0)
	if phase == Phase.IDLE:
		if pressed and can_start:
			return Vector2(Phase.EXTEND, 0.0)
		return Vector2(Phase.IDLE, 0.0)
	elapsed += delta
	match phase:
		Phase.EXTEND:
			if elapsed >= PUSH_S:
				return Vector2(Phase.RECOVER, 0.0)
		Phase.RECOVER:
			if elapsed >= RECOVER_S:
				return Vector2(Phase.REARM, 0.0)
		Phase.REARM:
			if elapsed >= REARM_S:
				return Vector2(Phase.IDLE, 0.0)
	return Vector2(phase, elapsed)


# The shaft is off the ice: no catch, no corral, no poke, no tip.
static func is_stick_busy(phase: int) -> bool:
	return phase == Phase.EXTEND or phase == Phase.RECOVER


static func can_land(phase: int) -> bool:
	return phase == Phase.EXTEND


# 0..1 through the push and back: up to 1 over EXTEND, back to 0 over RECOVER.
static func extension(phase: int, elapsed: float) -> float:
	match phase:
		Phase.EXTEND:
			return clampf(elapsed / PUSH_S, 0.0, 1.0)
		Phase.RECOVER:
			return 1.0 - clampf(elapsed / RECOVER_S, 0.0, 1.0)
	return 0.0


# 0..1 share of the cross-check pose over whatever the stick was doing: the hands
# and the shaft (SkaterIKCoordinator) and the chest squared to the push
# (SkaterPoseCoordinator) read the same share.
static func pose_weight(phase: int, elapsed: float) -> float:
	return clampf(extension(phase, elapsed) * _POSE_IN, 0.0, 1.0)


# Whether a victim is inside the shover's reach and in front of his chest.
# Facings are unit XZ (Skater.get_facing), the axis the skater strides along.
static func in_reach(shover_pos: Vector3, shover_facing: Vector2, shover_radius: float,
		victim_pos: Vector3, victim_radius: float) -> bool:
	var d := Vector2(victim_pos.x - shover_pos.x, victim_pos.z - shover_pos.z)
	var dist: float = d.length()
	if dist < 1e-4:
		return false
	if dist - shover_radius - victim_radius > REACH_M:
		return false
	return shover_facing.dot(d / dist) >= CONE_COS


# The victim's edge resistance (m/s²) to a push square across his blades: the
# grip the movement model turns with, in his posture, less the stagger's.
static func edge_accel(cfg: SkaterMovementRules.MovementConfig, posture: int,
		stagger_grip: float) -> float:
	var posture_grip: float = 1.0
	if posture == SkaterMovementRules.Posture.STANCE:
		posture_grip = cfg.stance_grip_mult
	elif posture == SkaterMovementRules.Posture.COMMIT:
		posture_grip = cfg.commit_grip_mult
	return cfg.turn_accel * cfg.lateral_grip * posture_grip * stagger_grip


# The victim's own stride (m/s²) pushing back, at `thrust` (stagger already in
# it), in his posture.
static func drive_accel(cfg: SkaterMovementRules.MovementConfig, posture: int,
		thrust: float) -> float:
	if posture == SkaterMovementRules.Posture.STANCE:
		return thrust * cfg.stance_stride_mult
	if posture == SkaterMovementRules.Posture.COMMIT:
		return thrust * cfg.commit_stride_mult
	return thrust


# The victim's Δv (m/s, along `push_dir`, unit XZ) from a shove: the shover's
# stride over PUSH_S on the victim's mass, less what his edges hold across his
# blades (|sin θ| of the push against his facing) and what his own stride pushes
# back into it. Never negative: a set man is not moved, nor pulled.
static func victim_dv(shover_mass: float, shover_thrust: float, victim_mass: float,
		push_dir: Vector2, victim_facing: Vector2, victim_edge_accel: float,
		victim_intent: Vector2, victim_drive_accel: float) -> float:
	var free: float = shover_mass * shover_thrust * PUSH_S / maxf(victim_mass, 0.001)
	var across: float = absf(victim_facing.cross(push_dir))
	var back: float = maxf(victim_intent.dot(-push_dir), 0.0)
	var resist: float = PUSH_S * (victim_edge_accel * across + victim_drive_accel * back)
	return maxf(free - resist, 0.0)


static func pack(phase: int, elapsed: float) -> int:
	var units: int = clampi(roundi(elapsed * _WIRE_TICK_HZ), 0, _WIRE_MAX_UNITS)
	return (phase & 0x03) | (units << 2)


static func unpack_phase(packed: int) -> int:
	return packed & 0x03


static func unpack_elapsed(packed: int) -> float:
	return float((packed >> 2) & _WIRE_MAX_UNITS) / _WIRE_TICK_HZ
