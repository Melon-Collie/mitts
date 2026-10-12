class_name StickCheckRules
extends RefCounted

# The stick lift on its own button: a press raises the blade, the hold keeps the
# hook open, and letting go drops the blade straight back down. Every transition
# is a function of the skater's own inputs, so the host and the predicting client
# step the same phases from the same input stream and nothing has to be rolled
# back when a lift lands. Held past the hook, the stick stays out as a TIE; which
# stick it ties, if any, is the host's call (StickTieTracker), never the phase's.

enum Phase { IDLE, RISE, HOOK, DROP, RECOVER, REARM, TIE }

# Blade off the ice and into the hook: a hand flick, about the blade lift's own
# ease (Skater._BLADE_LIFT_BLEND_SPEED reaches ~70 % of the lift in this time).
const RISE_S: float = 0.06
# A tap still gets a hook this long, so the shortest press can land one.
const HOOK_MIN_S: float = 0.04
# Holding past this turns the hook into a TIE: the stick stays out on whatever
# shaft it can hold, and stays out of the play.
const HOOK_MAX_S: float = 0.14
# The longest a tie holds; reaching it ends in RECOVER, letting go ends in DROP.
const TIE_MAX_S: float = 1.5
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

# Tie geometry. A tie latches when the stick's blade comes within the lift's own
# reach of an opponent's hand→blade shaft, and holds while it stays within a
# wider radius: the latch reach plus how far a stick held in a battle travels over
# the interpolation window the defender sees the shaft late by, plus IK slack.
const TIE_ENGAGE_RADIUS_M: float = GameRules.STICK_LIFT_RADIUS_M
# A stick braced against another one moves well under the free blade's cap
# (SkaterController.max_blade_speed, 10 m/s): this is a deliberate pull.
const TIE_BATTLE_BLADE_SPEED_M_S: float = 4.0
const TIE_IK_SLACK_M: float = 0.05
# After any tie breaks, the same defender cannot re-tie the same victim for this
# long — a broken tie is a stick won back, not one to be re-grabbed next tick.
const TIE_COOLDOWN_S: float = 0.75
# What a tied blade leaves of a puck it touches: the deflect off its face, laid
# flat and cut to this share of its pace, so it dies at the victim's feet.
const TIE_BOBBLE_RETAIN: float = 0.3


static func tie_hold_radius(interp_delay_s: float) -> float:
	return TIE_ENGAGE_RADIUS_M + interp_delay_s * TIE_BATTLE_BLADE_SPEED_M_S + TIE_IK_SLACK_M


# Wire packing: phase in bits 0-2, time elapsed in bits 3-7 as whole ticks —
# every phase but the tie ends inside 31 (REARM_S, the longest, is 30 at 120 Hz).
# The tie counts in eight-tick units: its only edge is the cap, and a reconcile
# landing up to 66 ms off it re-derives on the next one.
const _WIRE_TICK_HZ: float = 120.0
const _WIRE_MAX_UNITS: int = 31
const _TIE_TICKS_PER_UNIT: float = 8.0


# The stick takes no part in puck play: no catch, no corral, no poke, no tip.
static func is_stick_busy(phase: int) -> bool:
	return phase == Phase.RISE or phase == Phase.HOOK or phase == Phase.RECOVER \
			or phase == Phase.TIE


# Whether the blade is held up off the ice (the lift's target height).
static func is_blade_raised(phase: int) -> bool:
	return phase == Phase.RISE or phase == Phase.HOOK or phase == Phase.TIE


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
				return Vector2(Phase.TIE if held else Phase.DROP, 0.0)
			if not held and elapsed >= HOOK_MIN_S:
				return Vector2(Phase.DROP, 0.0)
		Phase.TIE:
			if not held:
				return Vector2(Phase.DROP, 0.0)
			if elapsed >= TIE_MAX_S:
				return Vector2(Phase.RECOVER, 0.0)
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
	var units: int = clampi(roundi(elapsed * _WIRE_TICK_HZ / _ticks_per_unit(phase)),
			0, _WIRE_MAX_UNITS)
	return (phase & 0x07) | (units << 3)


static func unpack_phase(byte: int) -> int:
	var phase: int = byte & 0x07
	return phase if phase <= Phase.TIE else Phase.IDLE


static func unpack_elapsed(byte: int) -> float:
	var phase: int = unpack_phase(byte)
	return float((byte >> 3) & 0x1F) * _ticks_per_unit(phase) / _WIRE_TICK_HZ


static func _ticks_per_unit(phase: int) -> float:
	return _TIE_TICKS_PER_UNIT if phase == Phase.TIE else 1.0
