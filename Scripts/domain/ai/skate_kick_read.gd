class_name AISkateKickRead
extends RefCounted

# A bot about to take a puck in its skates sets the skate to kick it to its
# stick: the brake held as the puck arrives, the same ask a player makes
# (SkateContactRules). What it reads is what the player watching sees: the
# puck's line in its own frame, straight over the next beat, meeting a boot
# before it reaches the blade, and a kick the rule would grant.

# The look-ahead: the skate is turned across a stop's beat before the puck gets
# there, so the brake is held from this long out. Longer costs speed for nothing.
const SET_S: float = 0.2


# `blade_reach` is how close the line must pass the blade for the stick to take
# it first (the pickup radius). `contact` is caller-owned scratch.
static func should_kick(me_pos: Vector3, me_vel: Vector3, facing: Vector2, in_stance: bool,
		blade: Vector3, blade_reach: float, puck_pos: Vector3, puck_vel: Vector3,
		puck_team: int, my_team: int, stick_free: bool, pressured: bool,
		contact: SkateContactRules.Contact) -> bool:
	if not SkateContactRules.puck_below_boot_top(puck_pos.y) or facing.length_squared() < 1e-6:
		return false
	var rel_vel := Vector2(puck_vel.x - me_vel.x, puck_vel.z - me_vel.z)
	if not SkateContactRules.can_kick(rel_vel.length(), puck_team, my_team, true,
			stick_free, pressured):
		return false
	var from := Vector2(puck_pos.x - me_pos.x, puck_pos.z - me_pos.z)
	if not SkateContactRules.find_contact(from, from + rel_vel * SET_S, facing.normalized(),
			SkateContactRules.half_spacing(in_stance), contact):
		return false
	if not SkateContactRules.approaching(rel_vel, contact.normal):
		return false
	var blade_rel := Vector2(blade.x - me_pos.x, blade.z - me_pos.z)
	return _closest_on_segment(blade_rel, from, contact.point).distance_to(blade_rel) > blade_reach


static func _closest_on_segment(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab: Vector2 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq <= 1e-10:
		return a
	return a + ab * clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
