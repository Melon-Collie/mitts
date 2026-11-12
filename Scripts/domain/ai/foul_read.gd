class_name AIFoulRead

# Whether the check a bot is about to land would be called a foul: the contact
# it is skating into, judged the way the referee will judge it
# (PenaltyRules.judge), from what the bot can see now. Pure.

# A contact further off than this is not yet the bot's to call off: the man
# can still get the puck, lose it or turn before it comes.
const CONTACT_HORIZON_S: float = 0.5


# `seconds_since_man_lost_puck` is how long ago the bot saw `man` stop being
# the carrier (INF if it never has); the read adds the time until contact,
# since that is when the referee measures it.
static func would_foul(me_pos: Vector3, me_vel: Vector3, me_weight: float,
		man: SkaterNetworkState, man_radius: float, man_is_carrier: bool,
		seconds_since_man_lost_puck: float, puck_loose: bool, puck_pos: Vector3) -> bool:
	var time_to_contact: float = AIPinThreatRead.time_to_contact(
			me_pos, me_vel, man.position, man.velocity)
	if time_to_contact > CONTACT_HORIZON_S:
		return false
	var to_man := Vector2(man.position.x - me_pos.x, man.position.z - me_pos.z)
	if to_man.length_squared() < 1e-6:
		return false
	var drive: Vector2 = to_man.normalized()
	var closing: float = Vector2(me_vel.x - man.velocity.x, me_vel.z - man.velocity.z).dot(drive)
	var impulse: float = closing * me_weight
	var puck_dist: float = Vector2(puck_pos.x - man.position.x,
			puck_pos.z - man.position.z).length()
	var eligible: bool = PenaltyRules.is_eligible_to_be_hit(man_is_carrier,
			seconds_since_man_lost_puck + time_to_contact, puck_loose, puck_dist)
	var wall_out: Vector2 = BoardWallRules.wall_normal(man.position, man_radius,
			PenaltyRules.BOARDING_ZONE_M)
	return PenaltyRules.judge(impulse, true, false, eligible,
			PenaltyRules.is_driven_into_boards(drive, wall_out),
			PenaltyRules.is_hit_from_behind(man.facing, drive)) != PenaltyRules.Foul.NONE
