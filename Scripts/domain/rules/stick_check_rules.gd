class_name StickCheckRules
extends RefCounted

# The stick lift on its own button: a press raises the blade, the hold keeps the
# hook open, and letting go drops the blade straight back down. Every transition
# is a function of the skater's own inputs, so the host and the predicting client
# step the same phases from the same input stream and nothing has to be rolled
# back when a lift lands.

enum Phase { IDLE, RISE, HOOK, DROP, RECOVER, REARM }

# Blade off the ice and into the hook: a hand flick, about the blade lift's own
# ease (Skater._BLADE_LIFT_BLEND_SPEED reaches ~70 % of the lift in this time).
const RISE_S: float = 0.06
# A tap still gets a hook this long, so the shortest press can land one.
const HOOK_MIN_S: float = 0.04
# Holding past this ends the hook in RECOVER instead of the fast drop: a stick
# left up is a stick out of the play.
const HOOK_MAX_S: float = 0.14
const DROP_S: float = 0.05
const RECOVER_S: float = 0.22
# After a drop, before the next lift can start. Keeps a missed lift from being
# re-thrown every few ticks; the stick plays the puck normally meanwhile.
const REARM_S: float = 0.25

# Victim's forced lift, by hook quality: a hook square under the shaft holds it
# up for the long end, one at the rim glances off for the short end.
const FORCED_LIFT_MIN_S: float = 0.4
const FORCED_LIFT_MAX_S: float = 0.9
# The victim's re-grab cooldown outlasts the forced lift by this, so the blade
# is back on the ice before it can corral anything — the lifter's window.
const REGRAB_MARGIN_S: float = 0.1

# Wire packing: phase in bits 0-2, whole ticks elapsed in bits 3-7. Every phase
# ends inside 31 ticks (REARM_S, the longest, is 30 at 120 Hz).
const _WIRE_TICK_HZ: float = 120.0
const _WIRE_MAX_TICKS: int = 31


# The stick takes no part in puck play: no catch, no corral, no poke, no tip.
static func is_stick_busy(phase: int) -> bool:
	return phase == Phase.RISE or phase == Phase.HOOK or phase == Phase.RECOVER


# Whether the blade is held up off the ice (the lift's target height).
static func is_blade_raised(phase: int) -> bool:
	return phase == Phase.RISE or phase == Phase.HOOK


# Up for any reason: a raised deflect or forced pop (`blade_up`), or a lift.
static func blade_held_up(blade_up: bool, phase: int) -> bool:
	return blade_up or is_blade_raised(phase)


# From the press until the blade is back down: the blade rides the lift's own
# height, not the deflect mode's, so the stick never steps between the two.
static func uses_lift_height(phase: int) -> bool:
	return phase != Phase.IDLE and phase != Phase.REARM


# One tick of the phase machine. Returns (phase, seconds elapsed in it) as a
# Vector2 so the per-tick call allocates nothing. `can_start` gates a press out
# of IDLE; `interrupted` (puck on the blade, check committed, shot started,
# knocked down, stick forced up) drops any phase straight to IDLE.
static func step(phase: int, elapsed: float, pressed: bool, held: bool,
		can_start: bool, interrupted: bool, delta: float) -> Vector2:
	if interrupted:
		return Vector2(Phase.IDLE, 0.0)
	if phase == Phase.IDLE:
		if pressed and can_start:
			return Vector2(Phase.RISE, 0.0)
		return Vector2(Phase.IDLE, 0.0)
	elapsed += delta
	match phase:
		Phase.RISE:
			if elapsed >= RISE_S:
				return Vector2(Phase.HOOK, 0.0)
		Phase.HOOK:
			if elapsed >= HOOK_MAX_S:
				return Vector2(Phase.RECOVER, 0.0)
			if not held and elapsed >= HOOK_MIN_S:
				return Vector2(Phase.DROP, 0.0)
		Phase.DROP:
			if elapsed >= DROP_S:
				return Vector2(Phase.REARM, 0.0)
		Phase.RECOVER:
			if elapsed >= RECOVER_S:
				return Vector2(Phase.IDLE, 0.0)
		Phase.REARM:
			if elapsed >= REARM_S:
				return Vector2(Phase.IDLE, 0.0)
	return Vector2(phase, elapsed)


# 1 for a blade on the shaft, 0 at the reach rim (`distance` = blade to the
# victim's hand→blade shaft, `radius` = the hook's reach).
static func hook_quality(distance: float, radius: float) -> float:
	if radius <= 0.0:
		return 0.0
	return clampf(1.0 - distance / radius, 0.0, 1.0)


static func forced_lift_seconds(quality: float) -> float:
	return lerpf(FORCED_LIFT_MIN_S, FORCED_LIFT_MAX_S, clampf(quality, 0.0, 1.0))


static func pack(phase: int, elapsed: float) -> int:
	var ticks: int = clampi(roundi(elapsed * _WIRE_TICK_HZ), 0, _WIRE_MAX_TICKS)
	return (phase & 0x07) | (ticks << 3)


static func unpack_phase(byte: int) -> int:
	var phase: int = byte & 0x07
	return phase if phase <= Phase.REARM else Phase.IDLE


static func unpack_elapsed(byte: int) -> float:
	return float((byte >> 3) & 0x1F) / _WIRE_TICK_HZ
