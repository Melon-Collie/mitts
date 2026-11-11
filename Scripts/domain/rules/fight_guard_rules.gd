class_name FightGuardRules
extends RefCounted

# Where a fighter holds his fists with the gloves off (FightRules.Role.FIGHTING):
# up in front of the chin, closer together than the shoulders they hang from.
# Every position is in UpperBody's frame (−Z forward, +Y up), off the shoulder
# the arm is drawn from, so one rule serves the top hand the tick places and
# the off hand the render pass does.

# In front of the shoulder, metres: a forearm's bend short of a jab.
const GUARD_FORWARD_M: float = 0.30
# Above the shoulder, metres: the fists at the chin.
const GUARD_UP_M: float = 0.12
# The share of the shoulder's offset off the centre line the fist keeps: the
# guard sits inside the shoulders, covering the face.
const GUARD_IN_SHARE: float = 0.45
# The shaft a fist would grip, toward where its blade would be: straight down,
# so each glove-less fist is drawn thumb up, as a fighter's are.
const FIST_GRIP_AXIS := Vector3.DOWN
# Where the stick's blade marker is parked while the stick lies on the ice: this
# far down the grip axis from the fist. Nothing draws or plays it; it keeps the
# marker off the fist, which the solves that read a shaft need.
const PARKED_BLADE_M: float = 0.5
# Seconds the hands take to come up into the guard, and down out of it.
const EASE_S: float = 0.25


static func guard_hand(shoulder: Vector3) -> Vector3:
	return Vector3(shoulder.x * GUARD_IN_SHARE, shoulder.y + GUARD_UP_M,
			shoulder.z - GUARD_FORWARD_M)


static func parked_blade(hand: Vector3) -> Vector3:
	return hand + FIST_GRIP_AXIS * PARKED_BLADE_M
