class_name FightHoldRules
extends RefCounted

# The holding hand and what it holds (docs/fighting-plan.md §3). Held, the grab
# button takes the other man's sweater at his chest, or his punching arm between
# elbow and fist, whichever the hand is nearer to and can reach; held by the arm,
# that fist is tied up (FightFistRules.TIED_*). Either grip holds the pair in a
# band between bodies touching and the holder's arm's length, and with no grip
# they still cannot pass through each other. The band is laid on both bodies'
# velocities along the line between them, shared by their masses.

# What a fighter's holding hand holds (Skater.fight_grip, replicated): the other
# man's sweater, or his top or bottom arm.
enum Grip { NONE, JERSEY, ARM_TOP, ARM_BOTTOM }
# Which of a fighter's arms punches (Skater.fight_punch_side, replicated): the
# top hand's at first, the other after a swap.
enum Side { TOP, BOTTOM }

# The holding hand reaches this far past its arm's reach for a grip, metres: a
# lean into the grab.
const GRAB_SLACK_M: float = 0.1
# A grip is torn away once its point is this far past the arm's reach.
const TEAR_SLACK_M: float = 0.3
# The sweater is taken at the chest, this far under the shoulders and this
# share of the body's radius out in front of its centre toward the holder.
const JERSEY_DROP_M: float = 0.18
const JERSEY_OUT_SHARE: float = 0.8
# An arm is taken this share of the way from its shoulder to its fist: the
# forearm, above the wrist.
const ARM_TAKE_SHARE: float = 0.65
# An arm can be caught only while it is thrown: its fist out past this share of
# its reach. Held up in a guard it is the sweater the hand takes.
const ARM_THROWN_SHARE: float = 0.7
# Held, the centres are kept no further apart than the holder's arm's length
# and this much more: his shoulder off his centre, and the held point's.
const BAND_BODY_M: float = 0.3
# How fast the band takes up an overstretch or an overlap, 1/s: half of it in
# about a tenth of a second.
const BAND_RATE: float = 7.0


# The point of the sweater a holder at `holder` takes on a man at `body`
# (centres, world), at `shoulder_y` (world height of the man's shoulders).
static func jersey_point(body: Vector3, radius: float, holder: Vector3, shoulder_y: float) -> Vector3:
	var toward := Vector3(holder.x - body.x, 0.0, holder.z - body.z)
	toward = toward.normalized() if toward.length_squared() > 0.000001 else Vector3.ZERO
	var at: Vector3 = body + toward * radius * JERSEY_OUT_SHARE
	at.y = shoulder_y - JERSEY_DROP_M
	return at


static func arm_point(shoulder: Vector3, fist: Vector3) -> Vector3:
	return shoulder.lerp(fist, ARM_TAKE_SHARE)


static func thrown(shoulder: Vector3, fist: Vector3, reach: float) -> bool:
	return shoulder.distance_to(fist) > reach * ARM_THROWN_SHARE


# The grip a hand at `hand`, on an arm rooted at `shoulder` with `reach`, takes
# when the grab goes on: the nearer of the sweater and the punching arm (`arm`,
# which grip that is, NONE while the arm is not thrown) the arm can get to, or
# NONE.
static func choose(hand: Vector3, shoulder: Vector3, reach: float, jersey: Vector3,
		arm: Vector3, arm_grip: int) -> int:
	var limit: float = reach + GRAB_SLACK_M
	var best: int = Grip.NONE
	var best_d: float = INF
	if shoulder.distance_to(jersey) <= limit:
		best = Grip.JERSEY
		best_d = hand.distance_to(jersey)
	if arm_grip != Grip.NONE and shoulder.distance_to(arm) <= limit \
			and hand.distance_to(arm) < best_d:
		best = arm_grip
	return best


static func torn(shoulder: Vector3, point: Vector3, reach: float) -> bool:
	return shoulder.distance_to(point) > reach + TEAR_SLACK_M


static func arm_grip_for(side: int) -> int:
	return Grip.ARM_TOP if side == Side.TOP else Grip.ARM_BOTTOM


# Whether a fighter punching with `side` has that arm held by the other man's
# `their_grip`.
static func tied(side: int, their_grip: int) -> bool:
	return their_grip == arm_grip_for(side)


static func band_max(holder_reach: float) -> float:
	return holder_reach + BAND_BODY_M


# Your velocity along the line to the other man after the band: `dist` between
# the centres, `u_self` / `u_other` each body's velocity along the line from you
# to him (so their difference is how fast you are parting), `min_d` / `max_d`
# the band (max INF with no grip), and the masses. Inside the band it is your
# own; out of it the parting is taken up toward the band's edge and the change
# shared, the lighter body moving more. Each body lays its own share, so the
# pair agree.
static func band_along(dist: float, u_self: float, u_other: float, min_d: float, max_d: float,
		m_self: float, m_other: float) -> float:
	var parting: float = u_other - u_self
	var want: float = parting
	if dist > max_d:
		want = minf(parting, -(dist - max_d) * BAND_RATE)
	elif dist < min_d:
		want = maxf(parting, (min_d - dist) * BAND_RATE)
	if want == parting:
		return u_self
	return u_self - (want - parting) * m_other / maxf(m_self + m_other, 0.001)
