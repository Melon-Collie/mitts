class_name KeeperJerseyDecal
extends Node2D

# One face of the keeper's jersey drawn on a transparent background: the team
# crest for the front, the name and number for the back, or the number alone
# for the shoulder caps. keeper_jersey.gdshader projects it onto its face, U
# across and V down the frame px_per_m measures, so it is laid out in metres
# exactly as a skater's is (JerseyDecal): the chest box's width and height, or
# the shoulder's number band.

enum Face { FRONT, BACK, SHOULDER }

# The yoke over his shoulders, down from the collar: the crest and the name hang
# below it.
const YOKE_DEPTH_M: float = 0.09
const IMG_W: int = 512
# The shoulder number's band on the cap, and how tall its digits stand.
const SHOULDER_BAND := Vector2(0.14, 0.10)
const SHOULDER_NUMBER_EM_M: float = 0.08
const _SHOULDER_IMG_W: int = 256

var face: int = Face.FRONT
var fruit: String = ""
var preset: Dictionary = {}
var player_name: String = ""
var jersey_number: int = 0
var text_color: Color = Color.WHITE
var text_stroke: Color = Color.TRANSPARENT


# The texture's size for a face: the chest box's or the shoulder band's aspect.
static func image_size(p_face: int) -> Vector2i:
	var m: Vector2 = _face_m(p_face)
	var w: int = _SHOULDER_IMG_W if p_face == Face.SHOULDER else IMG_W
	return Vector2i(w, roundi(w * m.y / m.x))


static func px_per_m(p_face: int) -> Vector2:
	var size: Vector2i = image_size(p_face)
	var m: Vector2 = _face_m(p_face)
	return Vector2(size.x / m.x, size.y / m.y)


static func _face_m(p_face: int) -> Vector2:
	if p_face == Face.SHOULDER:
		return SHOULDER_BAND
	var h: Vector3 = KeeperGear.half_extents(KeeperGear.Part.CHEST)
	return Vector2(2.0 * h.x, 2.0 * h.y)


func _draw() -> void:
	match face:
		Face.FRONT:
			if not fruit.is_empty():
				JerseyDecal.draw_chest_crest(self, fruit, preset, IMG_W * 0.5,
						px_per_m(face), YOKE_DEPTH_M)
		Face.BACK:
			JerseyDecal.draw_back_lettering(self, player_name, jersey_number, text_color,
					text_stroke, IMG_W * 0.5, px_per_m(face), YOKE_DEPTH_M)
		Face.SHOULDER:
			_draw_shoulder_number()


# The number centred in the band, set at the vertical texel density and
# stretched to the horizontal one so it keeps the font's shape on the cap.
func _draw_shoulder_number() -> void:
	var ppm: Vector2 = px_per_m(face)
	var size: Vector2i = image_size(face)
	var font: Font = JerseyDecal.FONT
	var font_size: int = roundi(SHOULDER_NUMBER_EM_M * ppm.y)
	var stretch: float = ppm.x / ppm.y
	var num: String = str(jersey_number)
	var text: Vector2 = font.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pos := Vector2(size.x * 0.5 / stretch - text.x * 0.5,
			size.y * 0.5 - text.y * 0.5 + font.get_ascent(font_size))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(stretch, 1.0))
	JerseyDecal.draw_lettering(self, font, pos, num, font_size, text_color, text_stroke)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func set_crest(p_fruit: String, p_preset: Dictionary) -> void:
	fruit = p_fruit
	preset = p_preset
	queue_redraw()


func set_lettering(p_name: String, number: int, color: Color, stroke: Color) -> void:
	player_name = p_name
	jersey_number = number
	text_color = color
	text_stroke = stroke
	queue_redraw()
