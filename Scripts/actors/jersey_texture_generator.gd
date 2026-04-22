class_name JerseyTextureGenerator

# Static utility for jersey texture generation and uniform stripe geometry.
# All mesh-drawing code that was previously in skater.gd lives here so it can
# be reused or tested without instantiating a Skater node.

# 5×7 pixel bitmap font. Each entry is 7 row-bitmasks (MSB = leftmost of 5 columns).
const _JERSEY_FONT: Dictionary = {
	"0": [14,17,17,17,17,17,14], "1": [4,12,4,4,4,4,14],
	"2": [14,17,1,2,4,8,31],    "3": [14,17,1,6,1,17,14],
	"4": [2,6,10,18,31,2,2],    "5": [31,16,16,30,1,1,30],
	"6": [6,8,16,30,17,17,14],  "7": [31,1,2,4,8,8,8],
	"8": [14,17,17,14,17,17,14],"9": [14,17,17,15,1,2,12],
	"A": [14,17,17,31,17,17,17],"B": [30,17,17,30,17,17,30],
	"C": [14,17,16,16,16,17,14],"D": [30,17,17,17,17,17,30],
	"E": [31,16,16,30,16,16,31],"F": [31,16,16,30,16,16,16],
	"G": [14,17,16,23,17,17,14],"H": [17,17,17,31,17,17,17],
	"I": [14,4,4,4,4,4,14],     "J": [7,1,1,1,1,17,14],
	"K": [17,18,20,24,20,18,17],"L": [16,16,16,16,16,16,31],
	"M": [17,27,21,17,17,17,17],"N": [17,25,21,19,17,17,17],
	"O": [14,17,17,17,17,17,14],"P": [30,17,17,30,16,16,16],
	"Q": [14,17,17,17,21,18,13],"R": [30,17,17,30,20,18,17],
	"S": [14,17,16,14,1,17,14], "T": [31,4,4,4,4,4,4],
	"U": [17,17,17,17,17,17,14],"V": [17,17,17,17,10,10,4],
	"W": [17,17,17,21,21,27,17],"X": [17,10,10,4,10,10,17],
	"Y": [17,17,10,4,4,4,4],    "Z": [31,1,2,4,8,16,31],
	" ": [0,0,0,0,0,0,0],
}


static func _draw_glyph(img: Image, ch: String, x: int, y: int, glyph_scale: int, color: Color) -> void:
	var rows: Array = _JERSEY_FONT.get(ch.to_upper(), _JERSEY_FONT[" "])
	for row: int in rows.size():
		var bits: int = rows[row]
		for col: int in 5:
			if bits & (1 << (4 - col)):
				for sy: int in glyph_scale:
					for sx: int in glyph_scale:
						var px: int = x + col * glyph_scale + sx
						var py: int = y + row * glyph_scale + sy
						if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
							img.set_pixel(px, py, color)


static func make_jersey_texture(p_name: String, number: int, text_color: Color) -> ImageTexture:
	const IMG_W: int = 256
	const IMG_H: int = 192
	const NUM_SCALE: int = 18
	const NAME_SCALE: int = 5
	const GLYPH_W: int = 5
	const GLYPH_H: int = 7

	var img := Image.create(IMG_W, IMG_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))

	var name_upper: String = p_name.to_upper()
	var char_w_name: int = GLYPH_W * NAME_SCALE
	var gap_name: int = NAME_SCALE
	var total_w_name: int = name_upper.length() * char_w_name + (name_upper.length() - 1) * gap_name
	var name_x: int = int((IMG_W - total_w_name) / 2.0)
	var name_y: int = 2
	for i: int in name_upper.length():
		_draw_glyph(img, name_upper[i], name_x + i * (char_w_name + gap_name), name_y, NAME_SCALE, text_color)

	var num_str: String = str(number)
	var char_w_num: int = GLYPH_W * NUM_SCALE
	var gap_num: int = NUM_SCALE
	var total_w_num: int = num_str.length() * char_w_num + (num_str.length() - 1) * gap_num
	var num_x: int = int((IMG_W - total_w_num) / 2.0)
	var num_y: int = name_y + GLYPH_H * NAME_SCALE + 6
	for i: int in num_str.length():
		_draw_glyph(img, num_str[i], num_x + i * (char_w_num + gap_num), num_y, NUM_SCALE, text_color)

	return ImageTexture.create_from_image(img)


static func make_shoulder_texture(number: int, text_color: Color) -> ImageTexture:
	const IMG_W: int = 128
	const IMG_H: int = 128
	const NUM_SCALE: int = 10
	const GLYPH_W: int = 5
	const GLYPH_H: int = 7

	var img := Image.create(IMG_W, IMG_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))

	var num_str: String = str(number)
	var char_w: int = GLYPH_W * NUM_SCALE
	var gap: int = NUM_SCALE
	var total_w: int = num_str.length() * char_w + (num_str.length() - 1) * gap
	var x: int = int((IMG_W - total_w) / 2.0)
	var y: int = int((IMG_H - GLYPH_H * NUM_SCALE) / 2.0)
	for i: int in num_str.length():
		_draw_glyph(img, num_str[i], x + i * (char_w + gap), y, NUM_SCALE, text_color)

	return ImageTexture.create_from_image(img)


static func make_shoulder_mesh(tex: ImageTexture, x_side: float) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = false

	var quad := QuadMesh.new()
	quad.size = Vector2(0.18, 0.18)

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = quad
	mesh_inst.material_override = mat
	mesh_inst.position = Vector3(x_side, 0.635, 0.0)
	mesh_inst.rotation_degrees = Vector3(-90.0, 90.0 * sign(x_side), 0.0)
	return mesh_inst


# ── Stripe helpers ─────────────────────────────────────────────────────────────

# Builds 4 quads (front/back/left/right faces) forming a horizontal band around
# a box mesh. Use for jersey hem stripes and sock stripes.
# box_center / box_half are in the caller's parent-node local space.
# stripe_y_bottom is the Y coordinate of the bottom edge of the stripe band.
# Returns Array[MeshInstance3D]; caller adds them to the appropriate parent node.
static func make_box_stripe_band(
		box_center: Vector3,
		box_half: Vector3,
		stripe_y_bottom: float,
		stripe_height: float,
		color: Color,
		name_prefix: String) -> Array:
	var mat: StandardMaterial3D = _make_stripe_mat(color)
	const OFFSET: float = 0.005
	var cy: float = stripe_y_bottom + stripe_height * 0.5
	var quads: Array = []

	# Front face (faces -Z, outward from box front)
	var front_quad := QuadMesh.new()
	front_quad.size = Vector2(box_half.x * 2.0, stripe_height)
	var front := MeshInstance3D.new()
	front.name = name_prefix + "_F"
	front.mesh = front_quad
	front.material_override = mat
	front.position = Vector3(box_center.x, cy, box_center.z - box_half.z - OFFSET)
	front.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	quads.append(front)

	# Back face (faces +Z)
	var back_quad := QuadMesh.new()
	back_quad.size = Vector2(box_half.x * 2.0, stripe_height)
	var back := MeshInstance3D.new()
	back.name = name_prefix + "_B"
	back.mesh = back_quad
	back.material_override = mat
	back.position = Vector3(box_center.x, cy, box_center.z + box_half.z + OFFSET)
	quads.append(back)

	# Left face (faces -X); rotate -90° around Y so quad width spans box depth
	var left_quad := QuadMesh.new()
	left_quad.size = Vector2(box_half.z * 2.0, stripe_height)
	var left := MeshInstance3D.new()
	left.name = name_prefix + "_L"
	left.mesh = left_quad
	left.material_override = mat
	left.position = Vector3(box_center.x - box_half.x - OFFSET, cy, box_center.z)
	left.rotation_degrees = Vector3(0.0, -90.0, 0.0)
	quads.append(left)

	# Right face (faces +X); rotate +90° around Y
	var right_quad := QuadMesh.new()
	right_quad.size = Vector2(box_half.z * 2.0, stripe_height)
	var right := MeshInstance3D.new()
	right.name = name_prefix + "_R"
	right.mesh = right_quad
	right.material_override = mat
	right.position = Vector3(box_center.x + box_half.x + OFFSET, cy, box_center.z)
	right.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	quads.append(right)

	return quads


# Builds 2 quads forming a vertical stripe piping on the left and right side
# faces of a box mesh (e.g. pants side seam). Full-height of the box.
static func make_box_side_stripe(
		box_center: Vector3,
		box_half: Vector3,
		stripe_width: float,
		color: Color,
		name_prefix: String) -> Array:
	var mat: StandardMaterial3D = _make_stripe_mat(color)
	const OFFSET: float = 0.005
	var quads: Array = []

	# Left face stripe (faces -X)
	var left_quad := QuadMesh.new()
	left_quad.size = Vector2(stripe_width, box_half.y * 2.0)
	var left := MeshInstance3D.new()
	left.name = name_prefix + "_L"
	left.mesh = left_quad
	left.material_override = mat
	left.position = Vector3(box_center.x - box_half.x - OFFSET, box_center.y, box_center.z)
	left.rotation_degrees = Vector3(0.0, -90.0, 0.0)
	quads.append(left)

	# Right face stripe (faces +X)
	var right_quad := QuadMesh.new()
	right_quad.size = Vector2(stripe_width, box_half.y * 2.0)
	var right := MeshInstance3D.new()
	right.name = name_prefix + "_R"
	right.mesh = right_quad
	right.material_override = mat
	right.position = Vector3(box_center.x + box_half.x + OFFSET, box_center.y, box_center.z)
	right.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	quads.append(right)

	return quads


# Builds 4 quads forming a horizontal band around a thin square cross-section
# (used for sleeve cuffs around the arm mesh at the hand/wrist position).
# box_half_xz is the half-size of the arm cross-section (arm_mesh_thickness / 2).
# The band is centered at the parent node's origin (Marker3D = wrist position).
static func make_sleeve_cuff(
		box_half_xz: float,
		stripe_height: float,
		color: Color,
		name_prefix: String) -> Array:
	var half: Vector3 = Vector3(box_half_xz, stripe_height * 0.5, box_half_xz)
	return make_box_stripe_band(Vector3.ZERO, half, -stripe_height * 0.5, stripe_height, color, name_prefix)


static func _make_stripe_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = 1
	return mat
