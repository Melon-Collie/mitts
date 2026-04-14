class_name PlayerRules

# Pure rules about players — team balance, visual-distinct color generation,
# and faceoff position lookup. No engine or GameManager access; callers do
# the data gathering (counting team members, etc.) and pass the numbers in.

const MAX_PER_TEAM: int = 3

# Returns team_id (0 or 1). Balances by count; ties go to team 0.
static func assign_team(team0_count: int, team1_count: int) -> int:
	return 0 if team0_count <= team1_count else 1

# HSV slot allocation for a visually-distinct shade per team slot.
#   Team 0 = warm reds (hue 340°–380°, wrapping through 0°)
#   Team 1 = cool blues (hue 200°–260°)
# `jitter` is a normalized value in [-1, 1]; the caller passes
# `randf_range(-1.0, 1.0)` at runtime, 0 in deterministic tests.
static func generate_player_color(team_id: int, existing_count: int, jitter: float) -> Color:
	var hue_min_deg: float = 340.0 if team_id == 0 else 200.0
	var hue_max_deg: float = 380.0 if team_id == 0 else 260.0
	var slot_size: float = (hue_max_deg - hue_min_deg) / MAX_PER_TEAM
	var slot_center: float = hue_min_deg + (existing_count + 0.5) * slot_size
	var hue_deg: float = slot_center + jitter * slot_size * 0.25
	return Color.from_hsv(fmod(hue_deg / 360.0, 1.0), 0.8, 0.9)

# Looks up the faceoff start position for a slot index.
static func faceoff_position_for_slot(slot: int) -> Vector3:
	return GameRules.CENTER_FACEOFF_POSITIONS[slot]
