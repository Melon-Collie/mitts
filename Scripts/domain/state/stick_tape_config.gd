class_name StickTapeConfig
extends RefCounted

# A player's tape job: blade wrap color + coverage, the bottom strip's color,
# and the butt-end knob color + handle style. Cosmetic only — nothing gameplay
# reads it. Today it is authored by the player-settings picker; the seam is
# deliberately author-agnostic so a future taping flow (or gear presets) can
# produce one the same way.
#
# Travels the wire as one packed int (to_code/from_code) appended to the join
# and spawn payloads, like the attribute gear ints. from_code clamps every
# field, so a forged code lands on a legal tape job instead of being rejected.

# Coverage presets. Each is a heel→toe wrap span in blade-length fractions
# (span_range), how the wraps are laid over it (wrap_count), and the span of a
# lengthwise strip along the blade's bottom edge (strip_range).
# WIRE VALUES — append only. HEEL_TO_MID sits at 0 so the all-default config
# packs to code 0: a payload that omits the field (an older entry, a bot)
# decodes to exactly the pre-customization look.
enum Span {
	HEEL_TO_MID, TOE, MID, FULL, NONE, MID_TO_TOE,
	SPACED, CENTER, STRIP, STRIP_AND_TOE,
}

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
	Vector2(0.12, 0.72),            # SPACED — a few wraps, gaps between, toe bare
	Vector2(0.33, 0.70),            # CENTER — a short patch just past mid
	Vector2(0.0, 0.0),              # STRIP — the bottom strip alone
	Vector2(0.50, 1.0),             # STRIP_AND_TOE — the strip under toe wraps
]

# Wraps laid evenly over the span, edge to edge; 0 overlaps them solid.
const _OVERLAPPED: int = 0
const _SPAN_WRAP_COUNTS: Array[int] = [
	_OVERLAPPED, _OVERLAPPED, _OVERLAPPED, _OVERLAPPED, _OVERLAPPED, _OVERLAPPED,
	3, 4, _OVERLAPPED, _OVERLAPPED,
]

# The strip only needs to clear the blade's heel cap: it runs along the sole,
# where the full overhang would stand out behind the heel as a ledge. Under
# toe wraps it stops short of the toe, whose tip pinches the two skins
# together until they z-fight.
const _STRIP_HEEL_OVERHANG: float = -0.006
const _SPAN_STRIP_RANGES: Array[Vector2] = [
	Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO,
	Vector2.ZERO, Vector2.ZERO,
	Vector2(_STRIP_HEEL_OVERHANG, 1.0),   # STRIP — heel to toe
	Vector2(_STRIP_HEEL_OVERHANG, 0.85),  # STRIP_AND_TOE — most of the blade
]

# Handle wrap style: just the butt knob, a candy-cane spiral running down the
# upper shaft from it, or a full grip section (knob included in all three).
# WIRE VALUES — append only. KNOB at 0 keeps the all-default code at 0.
enum KnobStyle { KNOB, CANDY_CANE, FULL }

# The all-default packed code (blade TEAM, span HEEL_TO_MID, knob TEAM, style
# KNOB, strip TEAM) — the wire default for every payload that carries a tape
# code.
const DEFAULT_CODE: int = 0

# Code packing: 5 bits per color index (palette growth headroom), the span's
# low 3 bits, 2 bits handle style, then the strip color and the span's 4th bit
# above them — appended rather than widening the span field in place, so every
# code packed before the strip existed still decodes to the same job.
const _COLOR_BITS: int = 5
const _COLOR_MASK: int = (1 << _COLOR_BITS) - 1
const _SPAN_LO_BITS: int = 3
const _SPAN_LO_MASK: int = (1 << _SPAN_LO_BITS) - 1
const _KNOB_SHIFT: int = _COLOR_BITS + _SPAN_LO_BITS
const _STYLE_SHIFT: int = _KNOB_SHIFT + _COLOR_BITS
const _STYLE_MASK: int = 0x3
const _STRIP_SHIFT: int = _STYLE_SHIFT + 2
const _SPAN_HI_SHIFT: int = _STRIP_SHIFT + _COLOR_BITS

var blade_color: int = TapeColorRegistry.TEAM_INDEX
var span: int = Span.HEEL_TO_MID
var knob_color: int = TapeColorRegistry.TEAM_INDEX
var knob_style: int = KnobStyle.KNOB
var strip_color: int = TapeColorRegistry.TEAM_INDEX


func _init(p_blade_color: int = TapeColorRegistry.TEAM_INDEX,
		p_span: int = Span.HEEL_TO_MID,
		p_knob_color: int = TapeColorRegistry.TEAM_INDEX,
		p_knob_style: int = KnobStyle.KNOB,
		p_strip_color: int = TapeColorRegistry.TEAM_INDEX) -> void:
	blade_color = _clamp_color(p_blade_color)
	span = clampi(p_span, 0, Span.size() - 1)
	knob_color = _clamp_color(p_knob_color)
	knob_style = clampi(p_knob_style, 0, KnobStyle.size() - 1)
	strip_color = _clamp_color(p_strip_color)


static func _clamp_color(index: int) -> int:
	return index if TapeColorRegistry.is_valid(index) else TapeColorRegistry.TEAM_INDEX


func has_wraps() -> bool:
	var r: Vector2 = _SPAN_RANGES[span]
	return r.y > r.x


func has_strip() -> bool:
	var r: Vector2 = _SPAN_STRIP_RANGES[span]
	return r.y > r.x


# Heel→toe u range of the wraps for this span (meaningless without wraps —
# gate on has_wraps first).
func span_range() -> Vector2:
	return _SPAN_RANGES[span]


# How many wraps are laid edge to edge over span_range, or 0 to overlap them
# solid over it.
func wrap_count() -> int:
	return _SPAN_WRAP_COUNTS[span]


# Heel→toe u range of the bottom strip (gate on has_strip first).
func strip_range() -> Vector2:
	return _SPAN_STRIP_RANGES[span]


func to_code() -> int:
	return blade_color | ((span & _SPAN_LO_MASK) << _COLOR_BITS) \
			| (knob_color << _KNOB_SHIFT) \
			| (knob_style << _STYLE_SHIFT) \
			| (strip_color << _STRIP_SHIFT) \
			| ((span >> _SPAN_LO_BITS) << _SPAN_HI_SHIFT)


static func from_code(code: int) -> StickTapeConfig:
	return StickTapeConfig.new(
			code & _COLOR_MASK,
			((code >> _COLOR_BITS) & _SPAN_LO_MASK)
					| (((code >> _SPAN_HI_SHIFT) & 0x1) << _SPAN_LO_BITS),
			(code >> _KNOB_SHIFT) & _COLOR_MASK,
			(code >> _STYLE_SHIFT) & _STYLE_MASK,
			(code >> _STRIP_SHIFT) & _COLOR_MASK)
