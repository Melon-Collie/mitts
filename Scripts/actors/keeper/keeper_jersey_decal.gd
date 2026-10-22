class_name KeeperJerseyDecal
extends Node2D

# One face of the keeper's jersey drawn on a transparent background: the team
# crest for the front or the name and number for the back. keeper_jersey.gdshader
# projects it onto that face with U across the chest box's width and V down its
# height, the frame PX_PER_M measures, so both are laid out in metres exactly as
# a skater's are (JerseyDecal).

enum Face { FRONT, BACK }

# The yoke over his shoulders, down from the collar: the crest and the name hang
# below it.
const YOKE_DEPTH_M: float = 0.09
const IMG_W: int = 512

var face: int = Face.FRONT
var fruit: String = ""
var preset: Dictionary = {}
var player_name: String = ""
var jersey_number: int = 0
var text_color: Color = Color.WHITE


# The texture's size: the chest box's aspect at IMG_W across.
static func image_size() -> Vector2i:
	var h: Vector3 = KeeperGear.half_extents(KeeperGear.Part.CHEST)
	return Vector2i(IMG_W, roundi(IMG_W * h.y / h.x))


static func px_per_m() -> Vector2:
	var h: Vector3 = KeeperGear.half_extents(KeeperGear.Part.CHEST)
	var size: Vector2i = image_size()
	return Vector2(size.x / (2.0 * h.x), size.y / (2.0 * h.y))


func _draw() -> void:
	if face == Face.FRONT:
		if not fruit.is_empty():
			JerseyDecal.draw_chest_crest(self, fruit, preset, IMG_W * 0.5, px_per_m(), YOKE_DEPTH_M)
	else:
		JerseyDecal.draw_back_lettering(self, player_name, jersey_number, text_color,
				IMG_W * 0.5, px_per_m(), YOKE_DEPTH_M)


func set_crest(p_fruit: String, p_preset: Dictionary) -> void:
	fruit = p_fruit
	preset = p_preset
	queue_redraw()


func set_lettering(p_name: String, number: int, color: Color) -> void:
	player_name = p_name
	jersey_number = number
	text_color = color
	queue_redraw()
