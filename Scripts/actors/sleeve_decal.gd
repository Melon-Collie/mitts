class_name SleeveDecal
extends Node2D

# Draws a kit's sleeve (SleevePaint) into a viewport both of the connected
# body's sleeves sample as their albedo: the base, its stripes across the
# texture from the shoulder (top) to the cuff (bottom), and the player number
# on the outside of the arm near its top. U wraps the arm with the number at
# 0.5, which each sleeve's material turns outward (part_material); V runs down
# the sleeve's length (SleevePaint.LENGTH_M).

const SIZE := Vector2i(512, 512)
# Round the sleeve where the number sits, metres: the arm's girth there.
const _GIRTH_M: float = 0.60

var sleeve: Dictionary = {"base": Color.WHITE, "stripes": []}
var jersey_number: int = 0
var text_color: Color = Color.BLACK
var text_stroke: Color = Color.TRANSPARENT
var _px_per_m := Vector2(SIZE.x / _GIRTH_M, SIZE.y / SleevePaint.LENGTH_M)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, SIZE), sleeve.base, true)
	for s: Dictionary in sleeve.stripes:
		var top: float = (float(s.pos) - float(s.width) * 0.5) * SIZE.y
		draw_rect(Rect2(0.0, top, SIZE.x, float(s.width) * SIZE.y), s.color, true)
	var num_str: String = str(jersey_number)
	# Set at the vertical texel density and stretched to the horizontal one, so
	# the number keeps the font's shape once it is on the arm.
	var font_size: int = roundi(ShoulderDecal.NUMBER_EM_M * _px_per_m.y)
	var stretch: float = _px_per_m.x / _px_per_m.y
	var text: Vector2 = ShoulderDecal.FONT.get_string_size(num_str, HORIZONTAL_ALIGNMENT_LEFT,
			-1, font_size)
	var pos := Vector2(float(SIZE.x) * 0.5 / stretch - text.x * 0.5,
			SleevePaint.NUMBER_CENTER_M * _px_per_m.y - text.y * 0.5
			+ ShoulderDecal.FONT.get_ascent(font_size))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(stretch, 1.0))
	JerseyDecal.draw_lettering(self, ShoulderDecal.FONT, pos, num_str, font_size, text_color,
			text_stroke)
	draw_set_transform_matrix(Transform2D.IDENTITY)


# A sleeve's material over a SleeveDecal viewport's texture, for the sleeve on
# `side` (-1 the -X arm, +1 the +X one): U = 0 is the arm's back, so a quarter
# turn each way faces the number outward.
static func part_material(tex: Texture2D, side: float) -> StandardMaterial3D:
	return ShoulderDecal.part_material(tex, side)


func update_sleeve(p_sleeve: Dictionary, p_number: int, t_color: Color, t_stroke: Color) -> void:
	sleeve = p_sleeve
	jersey_number = p_number
	text_color = t_color
	text_stroke = t_stroke
	queue_redraw()
