class_name HelmetDecal
extends Node2D

# Draws a kit's helmet into a viewport the shell (HelmetShellMesh) samples as its
# albedo: the shell's color, and the player's number on the brow above the brim
# and on either side of the back, where a camera behind the play reads it. U
# runs round the shell and V down it (HelmetShellMesh.uv_of).

const FONT: Font = preload("res://Assets/Fonts/BarlowSemiCondensed-ExtraBold.ttf")
const SIZE := Vector2i(1024, 352)
# Each number as (θ, height of its centre, em), helmet-local m: θ is from dead
# back, so π is the brow; the back ones sit behind the ear loops. Each clears
# the lip under it (test_helmet_shell.gd).
const NUMBERS: Array[Vector3] = [
	Vector3(PI, 0.094, 0.060),
	Vector3(0.7, 0.006, 0.052),
	Vector3(-0.7, 0.006, 0.052),
]
# The font's cap height in ems: a number's digits are centred on it.
const CAP_EM: float = 0.7

var shell_color: Color = Color.WHITE
var jersey_number: int = 0
var number_color: Color = Color.BLACK


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, SIZE), shell_color, true)
	var num_str: String = str(jersey_number)
	for site: Vector3 in NUMBERS:
		var at: Vector2 = HelmetShellMesh.uv_of(site.x, site.y) * Vector2(SIZE)
		# Set at the vertical texel density there and stretched to the
		# horizontal one, so the digits keep the font's shape on the shell.
		var px_per_m: Vector2 = Vector2(SIZE) / HelmetShellMesh.metres_per_uv(site.x, site.y)
		var font_size: int = roundi(site.z * px_per_m.y)
		var width: float = FONT.get_string_size(num_str, HORIZONTAL_ALIGNMENT_LEFT, -1,
				font_size).x
		draw_set_transform(at, 0.0, Vector2(px_per_m.x / px_per_m.y, 1.0))
		draw_string(FONT, Vector2(-width * 0.5, CAP_EM * font_size * 0.5), num_str,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, number_color)
	draw_set_transform_matrix(Transform2D.IDENTITY)


# The shell's material over a HelmetDecal viewport's texture.
static func material(tex: Texture2D) -> StandardMaterial3D:
	return UniformPaint.textured(tex, UniformPaint.ROUGH_HELMET)


# Of the kit's lettering colors and the team's palette, the one that stands out
# most on its helmet. `colors` is TeamColorRegistry.get_colors' dict; a kit
# built in code may carry only some of them.
static func number_color_for(colors: Dictionary) -> Color:
	var kit: Dictionary = colors.uniform
	var shell: Color = kit.helmet
	var text: Dictionary = kit.get("text", {})
	var best: Color = kit.get("shoulders", {}).get("text", Color.BLACK)
	for c: Variant in [text.get("color"), text.get("stroke"), colors.get("primary"),
			colors.get("secondary"), colors.get("light")]:
		if c is Color and (c as Color).a > 0.0 and TeamColorRegistry.contrast_ratio(c, shell) \
				> TeamColorRegistry.contrast_ratio(best, shell):
			best = c
	return best


func update_helmet(p_shell: Color, p_number: int, p_number_color: Color) -> void:
	shell_color = p_shell
	jersey_number = p_number
	number_color = p_number_color
	queue_redraw()
