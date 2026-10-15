class_name GoalieTextDecal
extends Node2D

# Renders name and number on a fully transparent background. Consumed by the
# goalie_jersey.gdshader as the `text_decal` sampler, which projects this
# texture onto the front and back Z faces of the body BoxMesh.
#
# Viewport size (IMG_W x IMG_H = 256 x 320) is aspect-matched to the body
# face (0.48 m wide x 0.60 m tall = 4:5), so pixels are nearly square and
# text is undistorted after projection.
#
# Text is horizontally centred at x = IMG_W / 2 = 128. Vertical positions
# target the upper-chest region (face_v ≈ 0.14–0.60) — the enlarged number
# reads clearly on the goalie's back in post-goal replays.

const FONT: Font = preload("res://Assets/Fonts/BarlowSemiCondensed-ExtraBold.ttf")
const NAME_FONT: Font = preload("res://Assets/Fonts/Manrope-SemiBold.ttf")
const IMG_W: int = 256
const IMG_H: int = 320
const CENTER_X: int = IMG_W / 2

const NAME_FONT_SIZE: int = 40
const NUMBER_FONT_SIZE: int = 100
const NAME_Y_TOP: int = 44
const NUMBER_Y_TOP: int = 92

var player_name: String = ""
var jersey_number: int = 0
var text_color: Color = Color.WHITE


func _draw() -> void:
	# Transparent background — only the glyphs are opaque.
	var name_upper: String = player_name.to_upper()
	if name_upper.length() > 0:
		_draw_centred(NAME_FONT, name_upper, NAME_FONT_SIZE, NAME_Y_TOP)
	if jersey_number > 0:
		_draw_centred(FONT, str(jersey_number), NUMBER_FONT_SIZE, NUMBER_Y_TOP)


func update_text(p_name: String, number: int, t_color: Color) -> void:
	player_name = p_name
	jersey_number = number
	text_color = t_color
	queue_redraw()


# Lettering is one color, no outline — the kit's text.outline is for UI chrome.
func _draw_centred(font: Font, s: String, font_size: int, y_top: int) -> void:
	var width: float = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var ascent: float = font.get_ascent(font_size)
	var pos := Vector2(float(CENTER_X) - width * 0.5, float(y_top) + ascent)
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
