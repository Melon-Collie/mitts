class_name PlayerRules

# Pure rules about players — team balance, visual-distinct color generation,
# and faceoff position lookup. No engine or GameManager access; callers do
# the data gathering (counting team members, etc.) and pass the numbers in.

const MAX_PER_TEAM: int = 3

# Returns team_id (0 or 1). Balances by count; ties are broken randomly.
static func assign_team(team0_count: int, team1_count: int) -> int:
	if team0_count < team1_count:
		return 0
	if team1_count < team0_count:
		return 1
	return randi() % 2

# Primary color: used for UI badges/scoreboard. Fixed per team.
#   Team 0 (home) = Pittsburgh Penguins Gold (#FCB514)
#   Team 1 (away) = Toronto Maple Leafs Blue (#00205B)
static func generate_primary_color(team_id: int) -> Color:
	if team_id == 0:
		return Color(0.988, 0.710, 0.078)  # Penguins Gold #FCB514
	return Color(0.000, 0.125, 0.357)      # Leafs Blue #00205B

# Uniform colors for skater meshes.
static func generate_jersey_color(team_id: int) -> Color:
	if team_id == 0:
		return Color(0.988, 0.710, 0.078)  # Penguins Gold #FCB514
	return Color(0.000, 0.125, 0.357)      # Leafs Blue #00205B

static func generate_helmet_color(team_id: int) -> Color:
	if team_id == 0:
		return Color(0.06, 0.06, 0.06)  # Penguins Black
	return Color(0.000, 0.125, 0.357)   # Leafs Blue #00205B

static func generate_pants_color(team_id: int) -> Color:
	if team_id == 0:
		return Color(0.06, 0.06, 0.06)  # Penguins Black
	return Color(1.00, 1.00, 1.00)      # Leafs White

static func generate_pads_color(team_id: int) -> Color:
	if team_id == 0:
		return Color(1.00, 1.00, 1.00)  # Penguins White pads
	return Color(1.00, 1.00, 1.00)      # Leafs White pads

# Looks up the faceoff start position for a team and within-team slot.
static func faceoff_position(team_id: int, team_slot: int) -> Vector3:
	return GameRules.CENTER_FACEOFF_POSITIONS[team_id][team_slot]
