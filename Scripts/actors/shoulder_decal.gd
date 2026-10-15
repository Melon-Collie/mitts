class_name ShoulderDecal
extends Node2D

# Draws a shoulder's color and the player number into a small viewport that the
# shoulder parts sample as their albedo — the same render-to-texture pattern as
# JerseyDecal, one viewport shared by both shoulders. The number sits on V's
# middle band and U = 0.5; each shoulder's uv1_offset turns that outward.
#
# The skater's cap (use_skater_cap) also wears the yoke over its top
# (SkaterMeshBuilder.SHOULDER_CAP_YOKE_V) and letters in metres, like the back,
# at the cap's own texel density. The goalie's shoulders keep the plain layout:
# one color, the number at a fixed pixel size.
#
# 'No outline' = outline equal to text color → skip the outline pass.

const FONT: Font = preload("res://Assets/Fonts/BarlowSemiCondensed-ExtraBold.ttf")
const IMG_W: int = 256
const IMG_H: int = 256
const NUMBER_FONT_SIZE: int = 56
const NUMBER_OUTLINE_PX: int = 5

# The skater's cap mesh, measured by test_lettering_scale.gd: the equator's
# girth (U wraps it across the texture's width) and metres of meridian per unit
# of V through the number band.
const SKATER_SIZE: Vector2i = Vector2i(512, 256)
const CAP_GIRTH_M: float = 0.556
const CAP_M_PER_V: float = 0.23
const SKATER_PX_PER_M: Vector2 = Vector2(SKATER_SIZE.x / CAP_GIRTH_M, SKATER_SIZE.y / CAP_M_PER_V)
# A sleeve number a little over half the back name's em, on the part of the cap
# that hangs down the arm, below the yoke.
const SKATER_NUMBER_EM_M: float = 0.10
const SKATER_NUMBER_OUTLINE_M: float = 0.006
const SKATER_NUMBER_CENTER_V: float = 0.58

var size: Vector2i = Vector2i(IMG_W, IMG_H)
var shoulder_color: Color = Color.WHITE
var yoke_color: Color = Color.WHITE
var jersey_number: int = 0
var text_color: Color = Color.BLACK
var text_outline_color: Color = Color.BLACK
var _skater_cap: bool = false


# Before the viewport is sized from `size`.
func use_skater_cap() -> void:
	_skater_cap = true
	size = SKATER_SIZE


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), shoulder_color, true)
	if _skater_cap:
		draw_rect(Rect2(0, 0, size.x, roundf(SkaterMeshBuilder.SHOULDER_CAP_YOKE_V * size.y)),
				yoke_color, true)
	var num_str: String = str(jersey_number)
	if num_str.is_empty():
		return
	var font_size: int = NUMBER_FONT_SIZE
	var outline: int = NUMBER_OUTLINE_PX
	var stretch: float = 1.0
	var center_v: float = 0.5
	if _skater_cap:
		font_size = roundi(SKATER_NUMBER_EM_M * SKATER_PX_PER_M.y)
		outline = roundi(SKATER_NUMBER_OUTLINE_M * SKATER_PX_PER_M.y)
		stretch = SKATER_PX_PER_M.x / SKATER_PX_PER_M.y
		center_v = SKATER_NUMBER_CENTER_V
	# Set at the vertical texel density and stretched to the horizontal one, so
	# the number keeps the font's shape once it is on the cap.
	var text: Vector2 = FONT.get_string_size(num_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pos := Vector2(float(size.x) * 0.5 / stretch - text.x * 0.5,
			center_v * float(size.y) - text.y * 0.5 + FONT.get_ascent(font_size))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(stretch, 1.0))
	if not text_outline_color.is_equal_approx(text_color):
		draw_string_outline(FONT, pos, num_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
				outline, text_outline_color)
	draw_string(FONT, pos, num_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func update_shoulder(s_color: Color, s_yoke: Color, p_number: int, t_color: Color,
		t_outline: Color) -> void:
	shoulder_color = s_color
	yoke_color = s_yoke
	jersey_number = p_number
	text_color = t_color
	text_outline_color = t_outline
	queue_redraw()
