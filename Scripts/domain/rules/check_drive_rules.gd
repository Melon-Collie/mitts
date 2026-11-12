class_name CheckDriveRules
extends RefCounted

const _PhysicsConstants: GDScript = preload("res://Scripts/game/constants.gd")

# The timed check (docs/hit-outcomes-plan.md, Phase 5): pressing Hit throws a
# short leg drive, and a contact inside it is the full check with the stride's
# push through it. Every transition is a function of the skater's own button and
# of whether he may commit at all, never of whether the drive landed, so the host
# and the predicting client step the same phases from the same inputs and
# nothing rolls back when a check lands.

enum Phase { IDLE, DRIVE, SPENT }

# How long after the press a contact is the timed check: one hard stride.
const DRIVE_S: float = 0.3
# After the drive, before the next one can start, and only once the button is
# up: a second drive is a second stride loaded, not the first one held.
const REARM_S: float = 0.7
# How long the legs push through the contact (s): the kick is the checker's
# stride force over it. Under the ~0.18 s a shoulder check's contact lasts,
# because the measured delivery (Skater.body_check_transfer) already has a
# driving checker's legs in it; this is the part closing speed cannot stand in
# for, a check thrown from matched speed.
const PUSH_S: float = 0.08
# What a shoulder merely held into a contact delivers of the driven check.
const HELD_SHARE: float = 0.6


# One tick of the phase machine, as (phase, seconds elapsed in it) in a Vector2
# so the per-tick call allocates nothing. `held` is the button; `eligible` is
# whether he may commit a check this tick (on his skates, not rocked or
# planted, and without the puck). A press he may not act on is spent: the drive
# never fires off a button still held when he becomes able to.
static func step(phase: int, elapsed: float, held: bool, eligible: bool,
		delta: float) -> Vector2:
	match phase:
		Phase.IDLE:
			if not held:
				return Vector2(Phase.IDLE, 0.0)
			if eligible:
				return Vector2(Phase.DRIVE, 0.0)
			return Vector2(Phase.SPENT, REARM_S)
		Phase.DRIVE:
			elapsed += delta
			if not eligible or elapsed >= DRIVE_S:
				return Vector2(Phase.SPENT, 0.0)
			return Vector2(Phase.DRIVE, elapsed)
	elapsed = minf(elapsed + delta, REARM_S)
	if elapsed >= REARM_S and not held:
		return Vector2(Phase.IDLE, 0.0)
	return Vector2(Phase.SPENT, elapsed)


static func is_driving(phase: int) -> bool:
	return phase == Phase.DRIVE


# The Δv (m/s) a driving checker's legs add to the man he hits: his stride force
# (`thrust` m/s² on his own mass) over the push, on the other man's mass. His
# skates take the reaction, so none of it comes back on him. Thrown into a man
# he is already leaning on it is the whole of the hit: a shove.
static func kick_dv(thrust: float, mass: float, other_mass: float) -> float:
	return thrust * PUSH_S * mass / maxf(other_mass, 0.001)


# Wire packing: phase in bits 0-1, time elapsed in bits 2-7 as whole ticks.
const _WIRE_TICK_HZ: float = _PhysicsConstants.PHYSICS_TICK
const _WIRE_MAX_UNITS: int = 63


static func pack(phase: int, elapsed: float) -> int:
	return (phase & 0x03) | (clampi(roundi(elapsed * _WIRE_TICK_HZ), 0, _WIRE_MAX_UNITS) << 2)


static func unpack_phase(packed: int) -> int:
	var phase: int = packed & 0x03
	return phase if phase <= Phase.SPENT else Phase.IDLE


static func unpack_elapsed(packed: int) -> float:
	return float((packed >> 2) & _WIRE_MAX_UNITS) / _WIRE_TICK_HZ
