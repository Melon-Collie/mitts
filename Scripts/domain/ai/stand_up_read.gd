class_name AIStandUpRead

# Whether a defender the carrier is about to skate into meets him with the
# shoulder: Ctrl held for the beat before contact, so the contact is a check
# that strips him instead of a bump he skates through (docs/hit-outcomes-plan.md,
# Phase 3). Held only that late, the commit costs no containment: the contact
# is already happening, and the commit's weaker edges can't matter in the time
# left to cut.

# How long before contact the shoulder goes in: the beat a defender squares to
# a carrier he can't avoid, inside which the carrier can no longer turn away.
const MEET_S: float = 0.15


# `me_*` the defender, `man_*` the carrier; `transfer` the defender's delivery
# and `ref_impulse` the full check (BodyCheckRules.Config.ref_impulse). True
# when the contact lands inside MEET_S and, committed, it rocks him.
static func meets(me_pos: Vector3, me_vel: Vector3, my_weight: float,
		man_pos: Vector3, man_vel: Vector3, man_weight: float,
		transfer: float, ref_impulse: float) -> bool:
	if AIPinThreatRead.time_to_contact(me_pos, me_vel, man_pos, man_vel) > MEET_S:
		return false
	var to_man := Vector2(man_pos.x - me_pos.x, man_pos.z - me_pos.z)
	var dist: float = to_man.length()
	if dist < 1e-4:
		return false
	var closing: float = Vector2(me_vel.x - man_vel.x, me_vel.z - man_vel.z).dot(to_man / dist)
	return SkaterCollisionRules.victim_kick(closing, my_weight, man_weight, transfer) >= ref_impulse
