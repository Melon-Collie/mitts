class_name StickModelRegistry
extends RefCounted

# The catalogue of stick PATTERNS — the layout of a stick's paint, each zone of
# which (shaft, up to two bands, wordmark, blade) the player colours from the
# tape palette under CosmeticUnlocks' rules (docs/game-pucks-plan.md, Phase 4).
# A pattern also names the colours it wears until the player paints it
# (StickTapeConfig.paint_custom off), so an untouched stick, a bot and an older
# code all draw the pattern's defaults.
#
# The pattern index travels in the packed GearStyleConfig code (its
# `stick_model` field) and the zone colours in the tape code, so rows must only
# ever be APPENDED. PATTERN_SOLID_WHITE is an alias kept for codes saved when it
# was a fixed white colourway: it draws a white solid stick but is not listed,
# since painting Solid white is the same stick.
#
# Bands are spans along the shaft in real metres from an anchor end — the same
# object-space placement the wordmark uses, so a blade-anchored kick zone stays
# pinned at the blade whatever the build's cut length. The wood pattern's shaft
# and blade are varnished ash, not paint.

const ANCHOR_BUTT: int = 0
const ANCHOR_BLADE: int = 1

const PATTERN_SOLID: int = 0
const PATTERN_KICK: int = 1
const PATTERN_BLOCK: int = 2
const PATTERN_SPLIT: int = 3
const PATTERN_SOLID_WHITE: int = 4
const PATTERN_WOOD: int = 5

# Paint zones, the index into a pattern's colours and the tape code's paint.
enum Zone { SHAFT, BAND1, BAND2, WORDMARK, BLADE }
const ZONE_COUNT: int = 5
const ZONE_NAME_KEYS: Array[StringName] = [
	&"STICK_ZONE_SHAFT", &"STICK_ZONE_BAND1", &"STICK_ZONE_BAND2", &"STICK_ZONE_WORDMARK",
	&"STICK_ZONE_BLADE",
]

const _TEAM: int = TapeColorRegistry.TEAM_INDEX
const _WHITE: int = TapeColorRegistry.WHITE_INDEX
const _BLACK: int = TapeColorRegistry.BLACK_INDEX

# The wood pattern's fixed finish.
const WOOD_SHAFT := Color(0.50, 0.34, 0.16)
const WOOD_BLADE_WEAVE: Array[Color] = [Color(0.47, 0.32, 0.15), Color(0.41, 0.27, 0.12)]
const WOOD_BLADE_BASE := Color(0.45, 0.31, 0.15)

# Row fields: `name` (locale key), `listed` (offered in the picker), `zones`
# (the zones it paints), `bands` (geometry for BAND1/BAND2, in order),
# `defaults` (a palette index per Zone), `wood` (fixed wood shaft and blade).
const _PATTERNS: Array[Dictionary] = [
	# Solid — one colour shaft with the wordmark: the house stick.
	{"name": &"STICK_PATTERN_SOLID", "listed": true,
		"zones": [Zone.SHAFT, Zone.WORDMARK, Zone.BLADE],
		"defaults": [_BLACK, _TEAM, _TEAM, _WHITE, _BLACK]},
	# Kick — a kick zone flooding up from the blade.
	{"name": &"STICK_PATTERN_KICK", "listed": true,
		"zones": [Zone.SHAFT, Zone.BAND1, Zone.WORDMARK, Zone.BLADE],
		"bands": [{"from_m": 0.0, "to_m": 0.50, "anchor": ANCHOR_BLADE}],
		"defaults": [_BLACK, _TEAM, _TEAM, _TEAM, _BLACK]},
	# Block — a graphic block low on the shaft, the heel left bare so the hosel
	# reads apart from it.
	{"name": &"STICK_PATTERN_BLOCK", "listed": true,
		"zones": [Zone.SHAFT, Zone.BAND1, Zone.WORDMARK, Zone.BLADE],
		"bands": [{"from_m": 0.12, "to_m": 0.55, "anchor": ANCHOR_BLADE}],
		"defaults": [_BLACK, _TEAM, _TEAM, _TEAM, _BLACK]},
	# Split — an upper half over the lower shaft, with a seam ring between.
	{"name": &"STICK_PATTERN_SPLIT", "listed": true,
		"zones": [Zone.SHAFT, Zone.BAND1, Zone.BAND2, Zone.WORDMARK, Zone.BLADE],
		"bands": [
			{"from_m": 0.0, "to_m": 0.78, "anchor": ANCHOR_BUTT},
			{"from_m": 0.44, "to_m": 0.52, "anchor": ANCHOR_BLADE},
		],
		"defaults": [_BLACK, _WHITE, _TEAM, _BLACK, _BLACK]},
	# Solid in white — the alias (see the header).
	{"name": &"STICK_PATTERN_SOLID", "listed": false,
		"zones": [Zone.SHAFT, Zone.WORDMARK, Zone.BLADE],
		"defaults": [_WHITE, _TEAM, _TEAM, _BLACK, _BLACK]},
	# Wood — varnished ash with a burnt-in wordmark.
	{"name": &"STICK_PATTERN_WOOD", "listed": true, "wood": true,
		"zones": [Zone.WORDMARK],
		"defaults": [_BLACK, _TEAM, _TEAM, _BLACK, _BLACK]},
]


static func count() -> int:
	return _PATTERNS.size()


static func is_valid(pattern: int) -> bool:
	return pattern >= 0 and pattern < _PATTERNS.size()


# The patterns the picker offers, in catalogue order.
static func listed() -> Array[int]:
	var out: Array[int] = []
	for i: int in _PATTERNS.size():
		if bool(_PATTERNS[i]["listed"]):
			out.append(i)
	return out


static func name_key(pattern: int) -> StringName:
	return _row(pattern)["name"]


static func has_zone(pattern: int, zone: int) -> bool:
	return (_row(pattern)["zones"] as Array).has(zone)


# Up to two {from_m, to_m, anchor} spans, in BAND1, BAND2 order.
static func bands(pattern: int) -> Array:
	return _row(pattern).get("bands", [])


static func is_wood(pattern: int) -> bool:
	return bool(_row(pattern).get("wood", false))


static func default_zones(pattern: int) -> Array[int]:
	var out: Array[int] = []
	for c: Variant in _row(pattern)["defaults"]:
		out.append(int(c))
	return out


# The palette index each zone is painted: the tape job's paint once the player
# has painted, otherwise the pattern's defaults.
static func zone_colors(pattern: int, tape: StickTapeConfig) -> Array[int]:
	if tape != null and tape.paint_custom:
		return tape.paint.duplicate()
	return default_zones(pattern)


# A look saved with the white alias, rewritten as Solid painted white — the
# same stick, on the pattern the picker lists. Anything else is left alone.
static func unalias(gear: GearStyleConfig, tape: StickTapeConfig) -> void:
	if gear.stick_model != PATTERN_SOLID_WHITE:
		return
	if not tape.paint_custom:
		tape.set_paint(default_zones(PATTERN_SOLID_WHITE))
	gear.stick_model = PATTERN_SOLID


# An out-of-range pattern (a forged wire code, a future catalogue) reads as the
# house stick rather than throwing at the paint seam.
static func _row(pattern: int) -> Dictionary:
	return _PATTERNS[pattern] if is_valid(pattern) else _PATTERNS[PATTERN_SOLID]
