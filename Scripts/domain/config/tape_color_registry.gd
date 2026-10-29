class_name TapeColorRegistry
extends RefCounted

# The shared cosmetic color palette: stick tape (blade wrap, bottom strip and
# butt-end knob), laces and the stick's own colors (shaft and graphic) each
# index into it independently. Every entry is a kit color or a neutral, never a
# fixed hue, so whatever a player picks belongs to the team they skate for:
# the team's primary, its secondary, black, and the team's own white (`light`
# in the preset — cream for some teams, which their away sweater already
# wears, so the gear matches it instead of out-whiting it). These are the
# same four paints GearModelRegistry's skate and glove models draw from.
#
# The palette is wire data: indices travel in the packed tape and gear-style
# codes (StickTapeConfig, GearStyleConfig), so entries must only ever be
# APPENDED — reordering or removing one silently repaints every player who had
# picked it. GearStyleConfig packs its stick colors in 2 bits each, so a fifth
# entry also means widening those fields.

const TEAM_INDEX: int = 0
const WHITE_INDEX: int = 1
const BLACK_INDEX: int = 2
const SECONDARY_INDEX: int = 3

# Locale keys and the short label drawn on a picker chip (empty = color only),
# indexed in lockstep with the palette. The two team chips are labeled so a
# player can tell them from fixed colors, and from each other on a kit whose
# primary and secondary are close.
const NAME_KEYS: Array[StringName] = [
	&"TAPE_COLOR_TEAM",
	&"TAPE_COLOR_WHITE",
	&"TAPE_COLOR_BLACK",
	&"TAPE_COLOR_SECONDARY",
]
const CHIP_KEYS: Array[StringName] = [
	&"TAPE_COLOR_TEAM_SHORT",
	&"",
	&"",
	&"TAPE_COLOR_SECONDARY_SHORT",
]

const _PAINTS: Array[int] = [
	GearModelRegistry.Paint.TEAM,
	GearModelRegistry.Paint.LIGHT,
	GearModelRegistry.Paint.BLACK,
	GearModelRegistry.Paint.ACCENT,
]


static func count() -> int:
	return _PAINTS.size()


static func is_valid(index: int) -> bool:
	return index >= 0 and index < _PAINTS.size()


# The paint color for a palette pick (also what a picker swatch shows), against
# the kit's primary, secondary and white. An out-of-range index from a hostile
# or older wire resolves to the primary, matching the pre-pick default look.
static func resolve(index: int, primary: Color, secondary: Color, light: Color) -> Color:
	if not is_valid(index):
		return primary
	return GearModelRegistry.resolve(_PAINTS[index], primary, secondary, light)
