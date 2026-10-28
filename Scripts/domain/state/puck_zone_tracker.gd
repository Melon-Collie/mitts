class_name PuckZoneTracker
extends RefCounted

# Which attacking zone the puck is in, followed tick to tick: on the blue line
# the answer is the zone it was last in (InfractionRules.puck_in_attacking_zone).
# Indexed by the attacking team.
var _in_zone: Array[bool] = [false, false]


func update(puck_z: float) -> void:
	_in_zone[0] = InfractionRules.puck_in_attacking_zone(puck_z, 0, _in_zone[0])
	_in_zone[1] = InfractionRules.puck_in_attacking_zone(puck_z, 1, _in_zone[1])


func in_attacking_zone(team_id: int) -> bool:
	if team_id != 0 and team_id != 1:
		return false
	return _in_zone[team_id]
