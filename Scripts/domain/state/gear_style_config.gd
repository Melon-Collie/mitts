class_name GearStyleConfig
extends RefCounted

# A player's gear cosmetics: a skate MODEL, a glove MODEL, a lace color, a
# stick MODEL, a helmet FACE option, how the jersey is TUCKED, and what shows
# under the helmet — a hair
# style, a facial-hair style and their shared colour (HairStyleRegistry). The
# skate/glove picks are indices into GearModelRegistry — whole designs that
# paint every zone of the piece (boot / collar / accent band; glove body /
# cuff) out of black, white and the team's own colors, rather than a single
# accent color the player tints.
# The stick pick is an index into StickModelRegistry — the graphic — and the
# stick's three colors (the shaft, the graphic's primary and its secondary) are
# TapeColorRegistry picks, as is the lace color, chosen apart from the skate. The face pick is a
# GearModelRegistry FACE_* option (bare / visor / cage / fishbowl) — a fixed
# look, like the stick. The tuck is a GearModelRegistry TUCK_* option. The hair
# rides the same code rather than one of its own because it goes everywhere the
# face gear goes — join, spawn, replay header, the bot card. Cosmetic only —
# nothing gameplay reads it. Every field is picked on the player screen and
# painted by SkaterUniformCoordinator.
#
# Travels the wire as one packed int (to_code/from_code) appended to the join
# and spawn payloads, like the tape code. from_code clamps every field, so a
# forged code lands on a legal look instead of being rejected.
#
# Defaults — skate model 0 (all-black boot), glove model 0 (kit-colored body
# and cuff), laces WHITE, stick model 0 (the house MITTS stick) on a black
# shaft with a white graphic, face 0 (bare), short dark-brown hair, no facial
# hair, the jersey worn loose — are the stock look an untouched player wears.
# Zero in every hair, tuck and stick-color field is that stock look, so a code
# saved before those fields existed decodes to it. A retired hair style or
# stick model decodes to the one that stands in for it.

# 5 bits per field, matching StickTapeConfig's palette headroom.
const _FIELD_BITS: int = 5
const _FIELD_MASK: int = (1 << _FIELD_BITS) - 1
const _LACE_SHIFT: int = _FIELD_BITS * 2
const _STICK_SHIFT: int = _FIELD_BITS * 3
const _FACE_SHIFT: int = _FIELD_BITS * 4
const _HAIR_SHIFT: int = _FIELD_BITS * 5
const _FACIAL_SHIFT: int = _FIELD_BITS * 6
const _HAIR_COLOR_SHIFT: int = _FIELD_BITS * 7
const _TUCK_SHIFT: int = _FIELD_BITS * 8
# The stick colors take 2 bits each — the whole four-entry palette — because
# the code rides replay headers as a JSON number, exact only to 53 bits. Each
# stores its pick XOR its default, so the zeros of a code packed before they
# existed decode to the stock stick.
const _STICK_COLOR_BITS: int = 2
const _STICK_COLOR_MASK: int = (1 << _STICK_COLOR_BITS) - 1
const _STICK_SHAFT_SHIFT: int = _FIELD_BITS * 9
const _STICK_PRIMARY_SHIFT: int = _STICK_SHAFT_SHIFT + _STICK_COLOR_BITS
const _STICK_SECONDARY_SHIFT: int = _STICK_PRIMARY_SHIFT + _STICK_COLOR_BITS

# Palette index of the classic lace (TapeColorRegistry WHITE).
const LACE_DEFAULT_INDEX: int = 1
const STICK_SHAFT_DEFAULT: int = TapeColorRegistry.BLACK_INDEX
const STICK_PRIMARY_DEFAULT: int = TapeColorRegistry.WHITE_INDEX
const STICK_SECONDARY_DEFAULT: int = TapeColorRegistry.SECONDARY_INDEX

# The all-default packed code — the wire default for every payload that carries
# a gear style code.
const DEFAULT_CODE: int = LACE_DEFAULT_INDEX << _LACE_SHIFT

var skate_model: int = 0
var glove_model: int = 0
var lace_color: int = LACE_DEFAULT_INDEX
var stick_model: int = 0
var helmet_face: int = GearModelRegistry.FACE_NONE
var hair_style: int = HairStyleRegistry.HAIR_SHORT
var facial_hair: int = HairStyleRegistry.FACIAL_NONE
var hair_color: int = 0
var jersey_tuck: int = GearModelRegistry.TUCK_NONE
var stick_shaft: int = STICK_SHAFT_DEFAULT
var stick_primary: int = STICK_PRIMARY_DEFAULT
var stick_secondary: int = STICK_SECONDARY_DEFAULT


func _init(p_skate_model: int = 0, p_glove_model: int = 0,
		p_lace_color: int = LACE_DEFAULT_INDEX, p_stick_model: int = 0,
		p_helmet_face: int = GearModelRegistry.FACE_NONE,
		p_hair_style: int = HairStyleRegistry.HAIR_SHORT,
		p_facial_hair: int = HairStyleRegistry.FACIAL_NONE,
		p_hair_color: int = 0,
		p_jersey_tuck: int = GearModelRegistry.TUCK_NONE,
		p_stick_shaft: int = STICK_SHAFT_DEFAULT,
		p_stick_primary: int = STICK_PRIMARY_DEFAULT,
		p_stick_secondary: int = STICK_SECONDARY_DEFAULT) -> void:
	skate_model = p_skate_model if GearModelRegistry.is_valid_skate(p_skate_model) else 0
	glove_model = p_glove_model if GearModelRegistry.is_valid_glove(p_glove_model) else 0
	lace_color = p_lace_color if TapeColorRegistry.is_valid(p_lace_color) \
			else LACE_DEFAULT_INDEX
	stick_model = StickModelRegistry.worn(p_stick_model) \
			if StickModelRegistry.is_valid(p_stick_model) else 0
	stick_shaft = _color_or(p_stick_shaft, STICK_SHAFT_DEFAULT)
	stick_primary = _color_or(p_stick_primary, STICK_PRIMARY_DEFAULT)
	stick_secondary = _color_or(p_stick_secondary, STICK_SECONDARY_DEFAULT)
	# The one retired model that was a color scheme comes back as that scheme.
	if p_stick_model == StickModelRegistry.STICK_WHITEOUT:
		stick_shaft = TapeColorRegistry.WHITE_INDEX
		stick_primary = TapeColorRegistry.BLACK_INDEX
	helmet_face = p_helmet_face if GearModelRegistry.is_valid_face(p_helmet_face) \
			else GearModelRegistry.FACE_NONE
	hair_style = HairStyleRegistry.worn_hair(p_hair_style) \
			if HairStyleRegistry.is_valid_hair(p_hair_style) else HairStyleRegistry.HAIR_SHORT
	facial_hair = p_facial_hair if HairStyleRegistry.is_valid_facial(p_facial_hair) \
			else HairStyleRegistry.FACIAL_NONE
	hair_color = p_hair_color if HairStyleRegistry.is_valid_color(p_hair_color) else 0
	jersey_tuck = p_jersey_tuck if GearModelRegistry.is_valid_tuck(p_jersey_tuck) \
			else GearModelRegistry.TUCK_NONE


static func _color_or(index: int, fallback: int) -> int:
	return index if TapeColorRegistry.is_valid(index) else fallback


func to_code() -> int:
	return skate_model | (glove_model << _FIELD_BITS) | (lace_color << _LACE_SHIFT) \
			| (stick_model << _STICK_SHIFT) | (helmet_face << _FACE_SHIFT) \
			| (hair_style << _HAIR_SHIFT) | (facial_hair << _FACIAL_SHIFT) \
			| (hair_color << _HAIR_COLOR_SHIFT) | (jersey_tuck << _TUCK_SHIFT) \
			| ((stick_shaft ^ STICK_SHAFT_DEFAULT) << _STICK_SHAFT_SHIFT) \
			| ((stick_primary ^ STICK_PRIMARY_DEFAULT) << _STICK_PRIMARY_SHIFT) \
			| ((stick_secondary ^ STICK_SECONDARY_DEFAULT) << _STICK_SECONDARY_SHIFT)


static func from_code(code: int) -> GearStyleConfig:
	return GearStyleConfig.new(
			code & _FIELD_MASK,
			(code >> _FIELD_BITS) & _FIELD_MASK,
			(code >> _LACE_SHIFT) & _FIELD_MASK,
			(code >> _STICK_SHIFT) & _FIELD_MASK,
			(code >> _FACE_SHIFT) & _FIELD_MASK,
			(code >> _HAIR_SHIFT) & _FIELD_MASK,
			(code >> _FACIAL_SHIFT) & _FIELD_MASK,
			(code >> _HAIR_COLOR_SHIFT) & _FIELD_MASK,
			(code >> _TUCK_SHIFT) & _FIELD_MASK,
			((code >> _STICK_SHAFT_SHIFT) & _STICK_COLOR_MASK) ^ STICK_SHAFT_DEFAULT,
			((code >> _STICK_PRIMARY_SHIFT) & _STICK_COLOR_MASK) ^ STICK_PRIMARY_DEFAULT,
			((code >> _STICK_SECONDARY_SHIFT) & _STICK_COLOR_MASK) ^ STICK_SECONDARY_DEFAULT)


