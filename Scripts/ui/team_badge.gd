class_name TeamBadge
extends Control
## A club's crest, muted and cropped, under its lettering in white: the team
## mark on the scorebug and the box score.
##
## The crest is drawn taller than the badge, so the badge crops it top and
## bottom, and a third of it hangs off the left edge. It is muted rather than
## faded (crest_tone.gdshader): transparency lets a dark panel grey every
## colour, and the lettering needs it dark enough on the light fruits (Lemon,
## Lime) too.

const _CREST_BLEED: float = 0.32
const _CREST_ALPHA: float = 0.85
const _CREST_SATURATION: float = 0.55
const _CREST_VALUE: float = 0.75
const _CREST_TONE := preload("res://Shaders/crest_tone.gdshader")

var _crest: ClubCrest = null
var _label: Label = null


# `inset` is where the lettering's box starts, in from the edge the crest is
# cropped at, so the letters sit over the crest's body. `mirrored` crops it at
# the right edge instead, for a badge on the right of a pair.
func _init(width: float, crest_px: float, font_size: int, inset: float,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER,
		mirrored: bool = false) -> void:
	custom_minimum_size = Vector2(width, 0)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_crest = ClubCrest.new(crest_px)
	_crest.modulate.a = _CREST_ALPHA
	var tone := ShaderMaterial.new()
	tone.shader = _CREST_TONE
	tone.set_shader_parameter(&"saturation", _CREST_SATURATION)
	tone.set_shader_parameter(&"value", _CREST_VALUE)
	_crest.material = tone
	_crest.anchor_top = 0.5
	_crest.anchor_bottom = 0.5
	if mirrored:
		_crest.anchor_left = 1.0
		_crest.anchor_right = 1.0
		_crest.offset_left = -crest_px * (1.0 - _CREST_BLEED)
		_crest.offset_right = crest_px * _CREST_BLEED
	else:
		_crest.offset_left = -crest_px * _CREST_BLEED
		_crest.offset_right = crest_px * (1.0 - _CREST_BLEED)
	_crest.offset_top = -crest_px * 0.5
	_crest.offset_bottom = crest_px * 0.5
	add_child(_crest)

	_label = Label.new()
	_label.add_theme_font_override(&"font", MenuStyle.display_font_spaced())
	_label.add_theme_font_size_override(&"font_size", font_size)
	_label.add_theme_color_override(&"font_color", MenuStyle.BROADCAST_CREAM)
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if mirrored:
		_label.offset_right = -inset
	else:
		_label.offset_left = inset
	_label.horizontal_alignment = align
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)


# -1 draws no crest.
func set_team(club: int, text: String) -> void:
	_crest.set_club(club)
	_label.text = text
