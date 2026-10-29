class_name StickModelRegistry
extends RefCounted

# The catalogue of stick MODELS — the graphic a stick carries, not its colors.
# A model lays out the brand wordmark and up to two BANDS (color spans along
# the shaft, in real metres from an anchor end — the same object-space metric
# placement the wordmark uses, so a blade-anchored kick zone stays pinned at
# the blade whatever the build's cut length), and names which of the player's
# three stick colors (GearStyleConfig: the shaft, the graphic's primary and
# its secondary) paints each piece. StickStyle turns a model and those colors
# into the shader materials; the tape job and grip wrap always paint over a
# band.
#
# Every row past the house Stealth is inspired by a recognizable real-world
# stick without naming it (same convention as the M88/M92/M28 blade patterns
# for P88/P92/P28): Redline reads as a Vapor's kick zone, Volt as a Ribcor's
# graphic block, Split as an Alpha's two-tone upper with a seam ring.
#
# The catalogue is wire data: the model index travels in the packed
# GearStyleConfig code, so rows must only ever be APPENDED. A model is retired
# rather than removed: its index stays, it leaves the picker and the bots'
# rolls, and GearStyleConfig decodes it to its stand-in from _RETIRED. Index 0
# is the house MITTS stick — the stock look an untouched player carries.

const ANCHOR_BUTT: int = 0
const ANCHOR_BLADE: int = 1

const STICK_STEALTH: int = 0
const STICK_REDLINE: int = 1
const STICK_VOLT: int = 2
const STICK_SPLIT: int = 3
const STICK_WHITEOUT: int = 4  # retired — a white shaft is now a color pick
const STICK_WOODIE: int = 5    # retired — wood is not one of the kit colors

const NAME_KEYS: Array[StringName] = [
	&"STICK_MODEL_STEALTH",
	&"STICK_MODEL_REDLINE",
	&"STICK_MODEL_VOLT",
	&"STICK_MODEL_SPLIT",
	&"STICK_MODEL_WHITEOUT",
	&"STICK_MODEL_WOODIE",
]

# Which of the player's stick colors paints a piece of the graphic.
enum Slot { PRIMARY, SECONDARY, SHAFT }

# Row fields: `brand` (the wordmark's Slot) always; `bands` is up to two
# {slot, from_m, to_m, anchor} spans (from < to, metres from the anchor end).
# Index-aligned with NAME_KEYS.
const _MODELS: Array[Dictionary] = [
	# Stealth — the house MITTS stick: a plain shaft and its wordmark.
	{"brand": Slot.PRIMARY},
	# Redline — a kick zone flooding up from the blade, the wordmark to match.
	{
		"brand": Slot.PRIMARY,
		"bands": [
			{"slot": Slot.PRIMARY, "from_m": 0.0, "to_m": 0.50, "anchor": ANCHOR_BLADE},
		],
	},
	# Volt — a graphic block low on the shaft (the heel keeps the shaft color so
	# the hosel reads apart from the graphic), the wordmark in the second color.
	{
		"brand": Slot.SECONDARY,
		"bands": [
			{"slot": Slot.PRIMARY, "from_m": 0.12, "to_m": 0.55, "anchor": ANCHOR_BLADE},
		],
	},
	# Split — the upper shaft over a bare lower, one seam ring. The wordmark
	# sits inside the upper zone, so it takes the shaft color to keep reading.
	{
		"brand": Slot.SHAFT,
		"bands": [
			{"slot": Slot.PRIMARY, "from_m": 0.0, "to_m": 0.78, "anchor": ANCHOR_BUTT},
			{"slot": Slot.SECONDARY, "from_m": 0.44, "to_m": 0.52, "anchor": ANCHOR_BLADE},
		],
	},
	{"brand": Slot.PRIMARY},  # Whiteout (retired)
	{"brand": Slot.PRIMARY},  # Woodie (retired)
]

const _RETIRED: Dictionary[int, int] = {
	STICK_WHITEOUT: STICK_STEALTH,
	STICK_WOODIE: STICK_STEALTH,
}


static func count() -> int:
	return _MODELS.size()


static func is_valid(model: int) -> bool:
	return model >= 0 and model < _MODELS.size()


static func is_retired(model: int) -> bool:
	return _RETIRED.has(model)


# The model a valid index is drawn as: itself, or a retired one's stand-in.
static func worn(model: int) -> int:
	return _RETIRED.get(model, model)


# Every model the picker offers, in index order. Allocates; menus only.
static func pickable() -> Array[int]:
	var out: Array[int] = []
	for model: int in _MODELS.size():
		if not is_retired(model):
			out.append(model)
	return out


# An out-of-range model (a forged wire code, a future catalogue) reads as the
# house stick, matching GearStyleConfig.from_code's clamp rather than throwing
# at the paint seam.
static func _row(model: int) -> Dictionary:
	return _MODELS[model] if is_valid(model) else _MODELS[STICK_STEALTH]


static func brand_slot(model: int) -> int:
	return _row(model)["brand"]


# Up to two {slot, from_m, to_m, anchor} spans; empty for a plain shaft.
static func bands(model: int) -> Array:
	return _row(model).get("bands", [])


# Whether any piece of the graphic paints in the secondary, so a picker can
# tell the player that pick has nothing to paint.
static func uses_secondary(model: int) -> bool:
	if brand_slot(model) == Slot.SECONDARY:
		return true
	for band: Dictionary in bands(model):
		if int(band["slot"]) == Slot.SECONDARY:
			return true
	return false


static func slot_color(slot: int, shaft: Color, primary: Color, secondary: Color) -> Color:
	match slot:
		Slot.SECONDARY:
			return secondary
		Slot.SHAFT:
			return shaft
		_:
			return primary


# The colors a UI swatch strip shows for one model in the given stick colors:
# shaft, then each band, then the wordmark — the parts of the design that read
# at chip size.
static func swatch_colors(model: int, shaft: Color, primary: Color,
		secondary: Color) -> Array[Color]:
	var colors: Array[Color] = [shaft]
	for band: Dictionary in bands(model):
		colors.append(slot_color(int(band["slot"]), shaft, primary, secondary))
	colors.append(slot_color(brand_slot(model), shaft, primary, secondary))
	return colors
