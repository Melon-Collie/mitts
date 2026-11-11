class_name HelmetDecal
extends Node2D

# Draws the helmet's paint into a viewport its shell samples: the kit's helmet
# colour, and the player's number on the front above the brow. The shell is
# laid on it round the head (shell_uv): across by the angle round it, the
# front in the middle and the back at both edges, which wrap, and down by
# height; so the number is only ever on the front.

const FONT: Font = preload("res://Assets/Fonts/BarlowSemiCondensed-ExtraBold.ttf")
const SIZE := Vector2i(512, 256)
# The heights (helmet-local) the texture runs down between, and the shell's
# girth round where the number is, which turns its angle into metres.
const TOP_Y_M: float = 0.20
const BOTTOM_Y_M: float = -0.15
const GIRTH_RADIUS_M: float = 0.13
const NUMBER_CENTER_Y_M: float = 0.095
const NUMBER_EM_M: float = 0.065

var helmet_color: Color = Color.WHITE
var jersey_number: int = 0
var text_color: Color = Color.BLACK


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, SIZE), helmet_color, true)
	var px_per_m := Vector2(SIZE.x / (TAU * GIRTH_RADIUS_M), SIZE.y / (TOP_Y_M - BOTTOM_Y_M))
	var num_str: String = str(jersey_number)
	# Set at the vertical texel density and stretched to the horizontal one, so
	# the number keeps the font's shape once it is on the shell.
	var font_size: int = roundi(NUMBER_EM_M * px_per_m.y)
	var stretch: float = px_per_m.x / px_per_m.y
	var text: Vector2 = FONT.get_string_size(num_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pos := Vector2(float(SIZE.x) * 0.5 / stretch - text.x * 0.5,
			(TOP_Y_M - NUMBER_CENTER_Y_M) * px_per_m.y - text.y * 0.5 + FONT.get_ascent(font_size))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(stretch, 1.0))
	JerseyDecal.draw_lettering(self, FONT, pos, num_str, font_size, text_color,
			Color.TRANSPARENT)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func update_helmet(color: Color, number: int, number_color: Color) -> void:
	helmet_color = color
	jersey_number = number
	text_color = number_color
	queue_redraw()


# Where a point of the shell (helmet-local, the face toward -Z) samples the
# texture: across by its angle round the head from straight ahead, read the
# right way round from in front (the skater's +X on the viewer's left), down
# by its height.
static func shell_uv(p: Vector3) -> Vector2:
	return Vector2(0.5 + atan2(-p.x, -p.z) / TAU,
			(TOP_Y_M - p.y) / (TOP_Y_M - BOTTOM_Y_M))


# One face's three `uvs` from `first` (shell_uv's), unwrapped where it spans
# the seam behind the head, so it runs on past the edge, which the texture
# repeats, instead of back across the number.
static func unwrap_face(uvs: PackedVector2Array, first: int) -> void:
	var lo: float = minf(uvs[first].x, minf(uvs[first + 1].x, uvs[first + 2].x))
	var hi: float = maxf(uvs[first].x, maxf(uvs[first + 1].x, uvs[first + 2].x))
	if hi - lo <= 0.5:
		return
	for c: int in 3:
		if uvs[first + c].x < 0.5:
			uvs[first + c].x += 1.0


# The shell's material over a HelmetDecal viewport's texture.
static func shell_material(tex: Texture2D) -> StandardMaterial3D:
	return UniformPaint.textured(tex, UniformPaint.ROUGH_HELMET)
