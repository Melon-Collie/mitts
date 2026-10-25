class_name HairStyleRegistry
extends RefCounted

# Hair, facial hair and hair colour: three fixed-look lists, picked on the
# player screen beside the skin. Indices ride the packed GearStyleConfig
# code, so like every wire table here rows are APPEND-ONLY and index 0 is what
# an untouched player wears — short dark-brown hair, no facial hair. Cosmetic
# only: nothing gameplay reads them.
#
# The helmet covers the crown, so a style is really a statement about what
# shows under its rim: a short cut is a nape and sideburns, medium covers the
# ears and the top of the neck, long hair spills out over the collar.

const HAIR_SHORT: int = 0
const HAIR_MEDIUM: int = 1
const HAIR_LONG: int = 2
const HAIR_BALD: int = 3
const HAIR_MULLET: int = 4
const HAIR_BUZZ: int = 5
const HAIR_SHAGGY: int = 6

const HAIR_NAME_KEYS: Array[StringName] = [
	&"HAIR_STYLE_SHORT",
	&"HAIR_STYLE_MEDIUM",
	&"HAIR_STYLE_LONG",
	&"HAIR_STYLE_BALD",
	&"HAIR_STYLE_MULLET",
	&"HAIR_STYLE_BUZZ",
	&"HAIR_STYLE_SHAGGY",
]

const FACIAL_NONE: int = 0
const FACIAL_STUBBLE: int = 1
const FACIAL_MUSTACHE: int = 2
const FACIAL_GOATEE: int = 3
const FACIAL_BEARD: int = 4
const FACIAL_HORSESHOE: int = 5
const FACIAL_PLAYOFF_BEARD: int = 6

const FACIAL_NAME_KEYS: Array[StringName] = [
	&"FACIAL_HAIR_NONE",
	&"FACIAL_HAIR_STUBBLE",
	&"FACIAL_HAIR_MUSTACHE",
	&"FACIAL_HAIR_GOATEE",
	&"FACIAL_HAIR_BEARD",
	&"FACIAL_HAIR_HORSESHOE",
	&"FACIAL_HAIR_PLAYOFF_BEARD",
]

const COLOR_NAME_KEYS: Array[StringName] = [
	&"HAIR_COLOR_DARK_BROWN",
	&"HAIR_COLOR_BLACK",
	&"HAIR_COLOR_BROWN",
	&"HAIR_COLOR_LIGHT_BROWN",
	&"HAIR_COLOR_BLONDE",
	&"HAIR_COLOR_RED",
	&"HAIR_COLOR_GREY",
	&"HAIR_COLOR_WHITE",
]

# Index-aligned with COLOR_NAME_KEYS; it colours the hair, beard and brows.
# Black is lifted off true black so the faceted shading still reads under the
# rink's light.
const COLORS: Array[Color] = [
	Color(0.20, 0.13, 0.09),
	Color(0.07, 0.06, 0.06),
	Color(0.33, 0.21, 0.12),
	Color(0.52, 0.37, 0.22),
	Color(0.82, 0.68, 0.42),
	Color(0.62, 0.27, 0.13),
	Color(0.55, 0.54, 0.52),
	Color(0.88, 0.87, 0.84),
]


static func hair_count() -> int:
	return HAIR_NAME_KEYS.size()


static func facial_count() -> int:
	return FACIAL_NAME_KEYS.size()


static func color_count() -> int:
	return COLORS.size()


static func is_valid_hair(style: int) -> bool:
	return style >= 0 and style < HAIR_NAME_KEYS.size()


static func is_valid_facial(style: int) -> bool:
	return style >= 0 and style < FACIAL_NAME_KEYS.size()


static func is_valid_color(index: int) -> bool:
	return index >= 0 and index < COLORS.size()


# A forged index reads the default colour, matching from_code's clamp.
static func color_for(index: int) -> Color:
	return COLORS[index] if is_valid_color(index) else COLORS[0]
