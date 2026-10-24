class_name ShoulderDecal
extends Node2D

# Draws a shoulder part's paint — the yoke over its top, its own color below —
# and the player number into a small viewport that both shoulders sample as
# their albedo, the same render-to-texture pattern as JerseyDecal. U wraps the
# part with the number at 0.5 (each shoulder's uv1_offset turns that outward)
# and V runs pole to pole.
#
# The number is lettered in metres at the part's own texel density, so it is
# the same size and shape on every player's shoulder. One color, no outline,
# like the back's lettering. Defaults are the skater's cap; the goalie's
# floater states its own (use_part).

const FONT: Font = preload("res://Assets/Fonts/BarlowSemiCondensed-ExtraBold.ttf")
# A sleeve number a little over half the back name's em.
const NUMBER_EM_M: float = 0.10

# The skater's cap mesh, measured by test_lettering_scale.gd: the equator's
# girth (U wraps it across the texture's width) and metres of meridian per unit
# of V through the number band. Its number hangs below the equator, on the part
# of the cap that runs down the arm.
const CAP_SIZE: Vector2i = Vector2i(512, 256)
const CAP_GIRTH_M: float = 0.556
const CAP_M_PER_V: float = 0.23
const CAP_NUMBER_CENTER_V: float = 0.58

var size: Vector2i = CAP_SIZE
var shoulder_color: Color = Color.WHITE
var yoke_color: Color = Color.WHITE
var jersey_number: int = 0
var text_color: Color = Color.BLACK
var _px_per_m: Vector2 = Vector2(CAP_SIZE.x / CAP_GIRTH_M, CAP_SIZE.y / CAP_M_PER_V)
var _yoke_v: float = SkaterMeshBuilder.SHOULDER_CAP_YOKE_V
var _number_center_v: float = CAP_NUMBER_CENTER_V


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), shoulder_color, true)
	draw_rect(Rect2(0, 0, size.x, roundf(_yoke_v * size.y)), yoke_color, true)
	var num_str: String = str(jersey_number)
	# Set at the vertical texel density and stretched to the horizontal one, so
	# the number keeps the font's shape once it is on the part.
	var font_size: int = roundi(NUMBER_EM_M * _px_per_m.y)
	var stretch: float = _px_per_m.x / _px_per_m.y
	var text: Vector2 = FONT.get_string_size(num_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pos := Vector2(float(size.x) * 0.5 / stretch - text.x * 0.5,
			_number_center_v * float(size.y) - text.y * 0.5 + FONT.get_ascent(font_size))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(stretch, 1.0))
	draw_string(FONT, pos, num_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
	draw_set_transform_matrix(Transform2D.IDENTITY)


# A shoulder part's material over a ShoulderDecal viewport's texture, for the
# part on `side` (-1 the -X shoulder, +1 the +X one). The part's U=0 is at +Z, so
# a quarter turn each way faces the number (at U 0.5) outward.
static func part_material(tex: Texture2D, side: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.roughness = UniformPaint.ROUGH_CLOTH
	mat.uv1_offset = Vector3(0.25 * side, 0.0, 0.0)
	BodyRim.apply(mat)
	return mat


func update_shoulder(s_color: Color, s_yoke: Color, p_number: int, t_color: Color) -> void:
	shoulder_color = s_color
	yoke_color = s_yoke
	jersey_number = p_number
	text_color = t_color
	queue_redraw()
