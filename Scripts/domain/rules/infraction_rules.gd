class_name InfractionRules

# Pure rules for hockey infractions that trigger ghost mode.
# Offside: skater in attacking zone before the puck.
# Icing: puck shot from own half past the opponent's goal line.
#
# Team 0 attacks toward -Z (defends +Z goal at z = +GoalLineZ).
# Team 1 attacks toward +Z (defends -Z goal at z = -GoalLineZ).

# Returns true if this skater is offside given their position, team, and the
# puck's position. Carriers are never offside.
static func is_offside(
		skater_z: float,
		skater_team_id: int,
		puck_z: float,
		is_carrier: bool) -> bool:
	if is_carrier:
		return false
	if skater_team_id == 0:
		# Team 0 attacking zone: z < -BlueLineZ
		return skater_z < -GameRules.BLUE_LINE_Z and puck_z >= -GameRules.BLUE_LINE_Z
	else:
		# Team 1 attacking zone: z > BlueLineZ
		return skater_z > GameRules.BLUE_LINE_Z and puck_z <= GameRules.BLUE_LINE_Z

# Hybrid icing race: returns true if the defending team wins (icing confirmed).
# icing_min_dist:     closest icing-team player's distance to the crossed goal line.
# defending_min_dist: closest defending-team player's distance to the crossed goal line.
# Ties go to the defending team (icing called).
static func defending_wins_icing_race(
		icing_min_dist: float, defending_min_dist: float) -> bool:
	return defending_min_dist <= icing_min_dist

# Returns true when a player who was serving an offside has crossed back into
# the neutral zone or their own zone — i.e. they have "tagged up" at the line.
static func has_tagged_up(skater_z: float, team_id: int) -> bool:
	if team_id == 0:
		return skater_z >= -GameRules.BLUE_LINE_Z
	else:
		return skater_z <= GameRules.BLUE_LINE_Z

# Detects a potential icing crossing. Returns the offending team id (0 or 1),
# or -1 if no icing condition is present. The caller applies the hybrid-icing
# race check to decide whether to confirm or wave off.
static func check_icing(
		last_carrier_team_id: int,
		last_carrier_z: float,
		puck_z: float) -> int:
	if last_carrier_team_id == -1:
		return -1
	# Team 0: released from z > 0 (own half), puck now past -GoalLineZ
	if last_carrier_team_id == 0 and last_carrier_z > 0.0 and puck_z < -GameRules.GOAL_LINE_Z:
		return 0
	# Team 1: released from z < 0 (own half), puck now past +GoalLineZ
	if last_carrier_team_id == 1 and last_carrier_z < 0.0 and puck_z > GameRules.GOAL_LINE_Z:
		return 1
	return -1
