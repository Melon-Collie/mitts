class_name PlayerRules

# Pure rules about players — team balance, visual-distinct color generation,
# and faceoff position lookup. No engine or GameManager access; callers do
# the data gathering (counting team members, etc.) and pass the numbers in.

const MAX_PER_TEAM: int = 3

# Returns team_id (0 or 1). Balances by count; ties go to team 0.
static func assign_team(team0_count: int, team1_count: int) -> int:
	return 0 if team0_count <= team1_count else 1

# Primary color: jersey, arms, blade.
#   Team 0 (home) = red shades (hue 340°–380°, slot-based)
#   Team 1 (away) = fixed white
# `jitter` is a normalized value in [-1, 1]; the caller passes
# `randf_range(-1.0, 1.0)` at runtime, 0 in deterministic tests.
static func generate_primary_color(team_id: int, existing_count: int, jitter: float) -> Color:
	if team_id == 1:
		return Color(0.95, 0.95, 0.95)
	var hue_min_deg: float = 340.0
	var hue_max_deg: float = 380.0
	var slot_size: float = (hue_max_deg - hue_min_deg) / MAX_PER_TEAM
	var slot_center: float = hue_min_deg + (existing_count + 0.5) * slot_size
	var hue_deg: float = slot_center + jitter * slot_size * 0.25
	return Color.from_hsv(fmod(hue_deg / 360.0, 1.0), 0.85, 0.90)

# Secondary color: legs and helmet (DirectionIndicator).
#   Team 0 (home) = fixed near-black
#   Team 1 (away) = blue shades (hue 200°–260°, slot-based)
static func generate_secondary_color(team_id: int, existing_count: int, jitter: float) -> Color:
	if team_id == 0:
		return Color(0.08, 0.08, 0.08)
	var hue_min_deg: float = 200.0
	var hue_max_deg: float = 260.0
	var slot_size: float = (hue_max_deg - hue_min_deg) / MAX_PER_TEAM
	var slot_center: float = hue_min_deg + (existing_count + 0.5) * slot_size
	var hue_deg: float = slot_center + jitter * slot_size * 0.25
	return Color.from_hsv(hue_deg / 360.0, 0.80, 0.90)

# Looks up the faceoff start position for a slot index.
static func faceoff_position_for_slot(slot: int) -> Vector3:
	return GameRules.CENTER_FACEOFF_POSITIONS[slot]
