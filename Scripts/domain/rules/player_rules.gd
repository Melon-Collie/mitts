class_name PlayerRules

# Pure rules about players — team balance and faceoff position lookup. No
# engine or GameManager access; callers do the data gathering (counting team
# members, etc.) and pass the numbers in. Color presets live in
# TeamColorRegistry.

const MAX_PER_TEAM: int = 3

# Returns team_id (0 or 1). Balances by count; ties are broken randomly.
static func assign_team(team0_count: int, team1_count: int) -> int:
	if team0_count < team1_count:
		return 0
	if team1_count < team0_count:
		return 1
	return randi() % 2

# Looks up the faceoff start position for a team and within-team slot.
static func faceoff_position(team_id: int, team_slot: int) -> Vector3:
	return GameRules.CENTER_FACEOFF_POSITIONS[team_id][team_slot]
