class_name FightGuardRules
extends RefCounted

# Where a fighter holds a fist he is not throwing or holding with, the gloves off
# (FightRules.Role.FIGHTING): up in front of the chin, closer in than the
# shoulder it hangs from. In UpperBody's frame (−Z forward, +Y up), off that
# shoulder (SkaterFightHands).

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
# Seconds the drawn off hand takes to come off the stick into the fight, and the
# stick to come back into the hands after it.
const EASE_S: float = 0.25


static func guard_hand(shoulder: Vector3) -> Vector3:
	return Vector3(shoulder.x * GUARD_IN_SHARE, shoulder.y + GUARD_UP_M,
			shoulder.z - GUARD_FORWARD_M)

