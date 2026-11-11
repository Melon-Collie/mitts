class_name StickCheckRules
extends RefCounted

const _PhysicsConstants: GDScript = preload("res://Scripts/game/constants.gd")

# The stick lift on its own button: a press raises the blade, the hold keeps the
# hook open, and letting go drops the blade straight back down. Every transition
# is a function of the skater's own inputs, so the host and the predicting client
# step the same phases from the same input stream and nothing has to be rolled
# back when a lift lands. Held past the hook, the stick stays out as a TIE,
# reaching for another stick; whether it ties one, and the tie itself, are the
# host's call (StickTieTracker), never the phase's.

enum Phase { IDLE, RISE, HOOK, DROP, REARM, TIE }

# Blade off the ice and into the hook: a hand flick, about the blade lift's own
# ease (Skater._BLADE_LIFT_BLEND_SPEED reaches ~70 % of the lift in this time).
const RISE_S: float = 0.06
# A tap still gets a hook this long, so the shortest press can land one.
const HOOK_MIN_S: float = 0.04
# Holding past this turns the hook into a TIE: the stick stays out, reaching for
# another stick, until the button is let go.
const HOOK_MAX_S: float = 0.14
const DROP_S: float = 0.05
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

# Tie geometry, measured stick to stick in plan view (top hand→blade on both,
# XZ): what the camera shows as two sticks crossing is what touches. A tie
# latches at shaft thickness plus IK slack.
const TIE_CONTACT_M: float = 0.08
# Two tied sticks push against each other, so both blades chase their cursors at
# this instead of the free cap (SkaterController.max_blade_speed, 10 m/s).
const TIE_BLADE_SPEED_M_S: float = 1.5
# The network part of how late one tied player sees the other's stick: the
# interpolation delay plus a typical trip. A late human reaction is not covered —
# reading a pull is the skill.
const TIE_LAG_BUDGET_S: float = 0.2
# A tie breaks once the sticks are this far apart: contact, plus the gap a pull
# opens while the other player's answer is in flight both ways.
const TIE_SEPARATION_M: float = TIE_CONTACT_M + 2.0 * TIE_BLADE_SPEED_M_S * TIE_LAG_BUDGET_S
# One cooldown per player for both verbs on the button: started by a landed lift
# (the lifter) and by a tie ending (both players); while it runs, a hook lifts
# nothing and a stick latches no tie.
const STICK_CHECK_COOLDOWN_S: float = 0.75
# What a tied blade leaves of a puck it touches: the deflect off its face, laid
# flat and cut to this share of its pace, so it dies at the player's feet.
const TIE_BOBBLE_RETAIN: float = 0.3


# Plan-view (XZ) gap between two sticks, each its top hand→blade segment.
static func stick_gap(a_hand: Vector3, a_blade: Vector3, b_hand: Vector3,
		b_blade: Vector3) -> float:
	var p1 := Vector2(a_hand.x, a_hand.z)
	var q1 := Vector2(a_blade.x, a_blade.z)
	var p2 := Vector2(b_hand.x, b_hand.z)
	var q2 := Vector2(b_blade.x, b_blade.z)
	if _segments_cross(p1, q1, p2, q2):
		return 0.0
	return minf(minf(_point_to_segment(p1, p2, q2), _point_to_segment(q1, p2, q2)),
			minf(_point_to_segment(p2, p1, q1), _point_to_segment(q2, p1, q1)))


static func _segments_cross(p1: Vector2, q1: Vector2, p2: Vector2, q2: Vector2) -> bool:
	var d1: float = (q2 - p2).cross(p1 - p2)
	var d2: float = (q2 - p2).cross(q1 - p2)
	var d3: float = (q1 - p1).cross(p2 - p1)
	var d4: float = (q1 - p1).cross(q2 - p1)
	return d1 * d2 < 0.0 and d3 * d4 < 0.0


static func _point_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var len_sq: float = ab.length_squared()
	var t: float = 0.0 if len_sq < 1e-10 else clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)


# Wire packing: phase in bits 0-2, time elapsed in bits 3-7 as whole ticks. Every
# timed phase ends inside 31 (REARM_S, the longest, is under 23 at 90 Hz); the tie
# has no timed edge, so its count saturates harmlessly.
const _WIRE_TICK_HZ: float = _PhysicsConstants.PHYSICS_TICK
const _WIRE_MAX_UNITS: int = 31


# The stick takes no part in puck play: no catch, no corral, no poke, no tip.
static func is_stick_busy(phase: int) -> bool:
	return phase == Phase.RISE or phase == Phase.HOOK or phase == Phase.TIE


# Whether the blade is held up off the ice (the lift's target height).
static func is_blade_raised(phase: int) -> bool:
	return phase == Phase.RISE or phase == Phase.HOOK or phase == Phase.TIE


# Up for any reason: a raised deflect or forced pop (`blade_up`), a lift, or a
# tie (`tied`, which outlasts the phase that started it).
static func blade_held_up(blade_up: bool, phase: int, tied: bool) -> bool:
	return blade_up or tied or is_blade_raised(phase)


# From the press until the blade is back down, and for as long as it is tied: the
# blade rides the lift's own height, not the deflect's rise to the puck, so the
# stick never steps between the two.
static func uses_lift_height(phase: int, tied: bool) -> bool:
	return tied or (phase != Phase.IDLE and phase != Phase.REARM)


# One tick of the phase machine. Returns (phase, seconds elapsed in it) as a
# Vector2 so the per-tick call allocates nothing. `can_start` gates a press out
# of IDLE; `interrupted` (puck on the blade, check committed, shot started,
# knocked down, stick forced up or tied) drops any phase straight to IDLE.
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
		Phase.DROP:
			if elapsed >= DROP_S:
				return Vector2(Phase.REARM, 0.0)
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
	var units: int = clampi(roundi(elapsed * _WIRE_TICK_HZ), 0, _WIRE_MAX_UNITS)
	return (phase & 0x07) | (units << 3)


static func unpack_phase(byte: int) -> int:
	var phase: int = byte & 0x07
	return phase if phase <= Phase.TIE else Phase.IDLE


static func unpack_elapsed(byte: int) -> float:
	return float((byte >> 3) & 0x1F) / _WIRE_TICK_HZ
