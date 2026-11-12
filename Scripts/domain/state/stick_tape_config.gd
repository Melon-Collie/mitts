class_name StickTapeConfig
extends RefCounted

# A player's stick look beyond its pattern: the tape job (blade wrap color and
# coverage, butt-end knob, toe cap) and the colours the player painted the
# pattern's zones (StickModelRegistry). Cosmetic only — nothing gameplay reads it.
#
# Travels the wire as one packed int (to_code/from_code) appended to the join
# and spawn payloads, like the attribute gear ints. from_code clamps every
# field, so a forged code lands on a legal look instead of being rejected. The
# packed code must stay within 53 bits: a replay's JSON header holds it as a
# double.

# Coverage presets, heel→toe spans in blade-length fractions (span_range).
# WIRE VALUES — append only. HEEL_TO_MID sits at 0 so the all-default config
# packs to code 0: a payload that omits the field (an older entry, a bot)
# decodes to exactly the pre-customization look.
# SPACED and BOTTOM_STRIP are not one wrap over their range: SPACED spreads a
# few narrow wraps across it, BOTTOM_STRIP lays one strip along the blade's
# bottom edge and caps the toe in toe_color (StickBladeMeshBuilder.build_tape_job).
enum Span { HEEL_TO_MID, TOE, MID, FULL, NONE, MID_TO_TOE, SPACED, BOTTOM_STRIP }
# Locale keys naming each span, index-aligned with Span.
const SPAN_NAME_KEYS: Array[StringName] = [
	&"TAPE_SPAN_HEEL_TO_MID", &"TAPE_SPAN_TOE", &"TAPE_SPAN_MID", &"TAPE_SPAN_FULL",
	&"TAPE_SPAN_NONE", &"TAPE_SPAN_MID_TO_TOE", &"TAPE_SPAN_SPACED", &"TAPE_SPAN_BOTTOM_STRIP",
]

# u ranges per span (x = start, y = end; u: 0 = heel, 1 = toe). Spans that
# include the heel start slightly negative so the tape's heel cap sits proud
# of the blade's own heel cap instead of z-fighting it coplanar.
const _HEEL_OVERHANG: float = -0.02
const _SPAN_RANGES: Array[Vector2] = [
	Vector2(_HEEL_OVERHANG, 0.62),  # HEEL_TO_MID — the long-time house look
	Vector2(0.55, 1.0),             # TOE
	Vector2(0.22, 0.72),            # MID — the classic middle patch
	Vector2(_HEEL_OVERHANG, 1.0),   # FULL
	Vector2(0.0, 0.0),              # NONE — no band at all
	Vector2(0.38, 1.0),             # MID_TO_TOE — HEEL_TO_MID's mirror
	Vector2(0.36, 0.94),            # SPACED — where its narrow wraps spread
	Vector2(_HEEL_OVERHANG, 1.0),   # BOTTOM_STRIP — heel to toe (the cap ends it)
]

# Handle wrap style: just the butt knob, a candy-cane spiral running down the
# upper shaft from it, or a full grip section (knob included in all three).
# WIRE VALUES — append only. KNOB at 0 keeps the all-default code at 0.
enum KnobStyle { KNOB, CANDY_CANE, FULL }

# The all-default packed code (blade TEAM, span HEEL_TO_MID, knob TEAM, style
# KNOB) — the wire default for every payload that carries a tape code.
const DEFAULT_CODE: int = 0

# Code packing: 5 bits per color index (palette growth headroom), 3 bits span,
# 2 bits handle style, then the toe-cap color. The span's 3 bits are full.
const _COLOR_BITS: int = 5
const _COLOR_MASK: int = (1 << _COLOR_BITS) - 1
const _SPAN_MASK: int = 0x7
const _STYLE_SHIFT: int = _COLOR_BITS + 3 + _COLOR_BITS
const _STYLE_MASK: int = 0x3
const _TOE_SHIFT: int = _STYLE_SHIFT + 2
const _PAINT_FLAG_SHIFT: int = _TOE_SHIFT + _COLOR_BITS
const _PAINT_SHIFT: int = _PAINT_FLAG_SHIFT + 1

var blade_color: int = TapeColorRegistry.TEAM_INDEX
var span: int = Span.HEEL_TO_MID
var knob_color: int = TapeColorRegistry.TEAM_INDEX
var knob_style: int = KnobStyle.KNOB
# The toe cap's color, worn only by BOTTOM_STRIP.
var toe_color: int = TapeColorRegistry.TEAM_INDEX
# Off: the stick wears its pattern's default colours. On: `paint` holds a palette
# index per StickModelRegistry.Zone. A code from before paint existed reads off.
var paint_custom: bool = false
var paint: Array[int] = [0, 0, 0, 0, 0]


func _init(p_blade_color: int = TapeColorRegistry.TEAM_INDEX,
		p_span: int = Span.HEEL_TO_MID,
		p_knob_color: int = TapeColorRegistry.TEAM_INDEX,
		p_knob_style: int = KnobStyle.KNOB,
		p_toe_color: int = TapeColorRegistry.TEAM_INDEX) -> void:
	blade_color = _clamp_color(p_blade_color)
	span = clampi(p_span, 0, Span.size() - 1)
	knob_color = _clamp_color(p_knob_color)
	knob_style = clampi(p_knob_style, 0, KnobStyle.size() - 1)
	toe_color = _clamp_color(p_toe_color)


static func _clamp_color(index: int) -> int:
	return index if TapeColorRegistry.is_valid(index) else TapeColorRegistry.TEAM_INDEX


func has_blade_tape() -> bool:
	return span != Span.NONE


func has_toe_cap() -> bool:
	return span == Span.BOTTOM_STRIP


# Heel→toe u range of the wrap for this span (meaningless for NONE — gate on
# has_blade_tape first).
func span_range() -> Vector2:
	return _SPAN_RANGES[span]


# Paints the zones `colors` (a palette index per Zone), turning paint on.
func set_paint(colors: Array[int]) -> void:
	paint_custom = true
	for zone: int in StickModelRegistry.ZONE_COUNT:
		paint[zone] = _clamp_color(colors[zone] if zone < colors.size() else 0)


func clear_paint() -> void:
	paint_custom = false
	paint = [0, 0, 0, 0, 0]


func to_code() -> int:
	var code: int = blade_color | (span << _COLOR_BITS) \
			| (knob_color << (_COLOR_BITS + 3)) \
			| (knob_style << _STYLE_SHIFT) | (toe_color << _TOE_SHIFT)
	if paint_custom:
		code |= 1 << _PAINT_FLAG_SHIFT
		for zone: int in StickModelRegistry.ZONE_COUNT:
			code |= paint[zone] << (_PAINT_SHIFT + zone * _COLOR_BITS)
	return code


static func from_code(code: int) -> StickTapeConfig:
	var config := StickTapeConfig.new(
			code & _COLOR_MASK,
			(code >> _COLOR_BITS) & _SPAN_MASK,
			(code >> (_COLOR_BITS + 3)) & _COLOR_MASK,
			(code >> _STYLE_SHIFT) & _STYLE_MASK,
			(code >> _TOE_SHIFT) & _COLOR_MASK)
	if (code >> _PAINT_FLAG_SHIFT) & 1 == 1:
		var colors: Array[int] = []
		for zone: int in StickModelRegistry.ZONE_COUNT:
			colors.append((code >> (_PAINT_SHIFT + zone * _COLOR_BITS)) & _COLOR_MASK)
		config.set_paint(colors)
	return config
