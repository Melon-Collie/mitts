class_name TapeColorRegistry
extends RefCounted

# The shared cosmetic color palette: stick tape (blade wrap and butt-end
# knob) and the skate laces each index into it independently. Two entries are
# team sentinels resolved at paint time: TEAM (index 0) to the kit's primary,
# which keeps every untouched slot looking exactly like the pre-customization
# kit, and TEAM_SECOND to its secondary. Which entries a player may pick is
# CosmeticUnlocks' call, not this file's.
#
# The palette is wire data: indices travel in the packed tape and gear-style
# codes (StickTapeConfig, GearStyleConfig), so entries must only ever be
# APPENDED — reordering or removing one silently repaints every player who had
# picked it.

const TEAM_INDEX: int = 0
const WHITE_INDEX: int = 1
const BLACK_INDEX: int = 2
const YELLOW_INDEX: int = 5
const TEAM_SECOND_INDEX: int = 11

# Locale keys, indexed in lockstep with _COLORS (TEAM at 0 has no swatch color;
# resolve() substitutes the live team accent).
const NAME_KEYS: Array[StringName] = [
	&"TAPE_COLOR_TEAM",
	&"TAPE_COLOR_WHITE",
	&"TAPE_COLOR_BLACK",
	&"TAPE_COLOR_RED",
	&"TAPE_COLOR_BLUE",
	&"TAPE_COLOR_YELLOW",
	&"TAPE_COLOR_GREEN",
	&"TAPE_COLOR_ORANGE",
	&"TAPE_COLOR_PURPLE",
	&"TAPE_COLOR_PINK",
	&"TAPE_COLOR_TEAL",
	&"TAPE_COLOR_TEAM_SECOND",
]

# Cloth-tape albedos. Slot 0 (TEAM) holds a neutral placeholder that only
# shows if a caller paints without resolving; real paint goes through resolve().
const _COLORS: Array[Color] = [
	Color(0.6, 0.6, 0.6),
	Color(0.92, 0.92, 0.92),   # white — the classic
	Color(0.07, 0.07, 0.07),   # black
	Color(0.78, 0.10, 0.12),   # red
	Color(0.10, 0.22, 0.75),   # royal blue
	Color(0.95, 0.78, 0.08),   # yellow
	Color(0.05, 0.45, 0.18),   # green
	Color(0.95, 0.42, 0.05),   # orange
	Color(0.40, 0.12, 0.65),   # purple
	Color(0.95, 0.35, 0.65),   # pink
	Color(0.05, 0.60, 0.60),   # teal
	Color(0.6, 0.6, 0.6),      # TEAM_SECOND — resolved like TEAM
]


static func count() -> int:
	return _COLORS.size()


static func is_valid(index: int) -> bool:
	return index >= 0 and index < _COLORS.size()


# The paint color for a palette pick (also what a picker swatch shows). TEAM —
# and any out-of-range index from a hostile or future wire — resolves to the
# team's primary, matching the pre-pick default look; TEAM_SECOND to its
# secondary.
static func resolve(index: int, team_primary: Color, team_secondary: Color = team_primary) -> Color:
	if index == TEAM_SECOND_INDEX:
		return team_secondary
	if index <= TEAM_INDEX or index >= _COLORS.size():
		return team_primary
	return _COLORS[index]
