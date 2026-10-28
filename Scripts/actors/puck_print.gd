class_name PuckPrint
extends RefCounted

# The print on the puck's top face: the Mitts skater over a bar, in white on the
# black rubber, so the eye can see the disc turn. Cosmetic only. The face is its
# own surface of the puck mesh (PuckMeshBuilder.SURF_FACE), mapped flat: UV
# (0.5, 0.5) is the face's centre and the face's corners reach radius 0.5.
#
# At speed the print is drawn smeared across the angle the disc turns in
# SHUTTER_S, the way a camera sees a spinning puck: a 30 m/s shot turns ~70° in
# a 60 fps frame, and drawn crisp it strobes or reads as turning backward.

const LOGO: Texture2D = preload("res://Assets/logos/Mitts_logo_skater.svg")
const SIZE: int = 128
# A broadcast frame. At the rig's spin cap the smear is ~2 rad.
const SHUTTER_S: float = 1.0 / 60.0
const SWEEP_PARAM: StringName = &"sweep"
const INK: Color = Color(0.92, 0.92, 0.88)

# In UV. The face polygon's inscribed radius is 0.5·cos(15°) ≈ 0.48; the print
# keeps a rubber margin inside it.
const LOGO_CENTRE: Vector2 = Vector2(0.5, 0.43)
const LOGO_SPAN: float = 0.6
const BAR_V: Vector2 = Vector2(0.75, 0.83)
const PRINT_RADIUS: float = 0.44

const _SHADER_CODE: String = """shader_type spatial;

uniform vec3 base_color : source_color;
uniform vec3 ink : source_color;
uniform sampler2D print_tex : filter_linear_mipmap, repeat_disable;
// Angle (rad) the disc turns in one exposure.
uniform float sweep = 0.0;

const int TAPS = 16;

void fragment() {
	float cover;
	if (sweep < 0.02) {
		cover = texture(print_tex, UV).r;
	} else {
		vec2 p = UV - 0.5;
		cover = 0.0;
		for (int i = 0; i < TAPS; i++) {
			float a = sweep * ((float(i) + 0.5) / float(TAPS) - 0.5);
			float c = cos(a);
			float s = sin(a);
			cover += texture(print_tex, vec2(c * p.x - s * p.y, s * p.x + c * p.y) + 0.5).r;
		}
		cover /= float(TAPS);
	}
	ALBEDO = mix(base_color, ink, cover);
}
"""

static var _material: ShaderMaterial = null


# Shared by every puck; the spin rig gives its own puck a copy to write the
# smear on.
static func material(base_color: Color) -> ShaderMaterial:
	if _material == null:
		var shader := Shader.new()
		shader.code = _SHADER_CODE
		_material = ShaderMaterial.new()
		_material.shader = shader
		_material.set_shader_parameter(&"ink", INK)
		_material.set_shader_parameter(&"print_tex", ImageTexture.create_from_image(build_image()))
	_material.set_shader_parameter(&"base_color", base_color)
	return _material


# Ink coverage in the red channel, mipmapped: from the game camera the face is
# a few pixels across.
static func build_image() -> Image:
	var img: Image = Image.create_empty(SIZE, SIZE, false, Image.FORMAT_L8)
	_print_logo(img)
	_print_bar(img)
	img.generate_mipmaps()
	return img


# The skater's silhouette in ink, its highlights left as rubber, as a
# one-colour screen print would. A renderer without textures (headless) gives
# no image, and the face carries the bar alone.
static func _print_logo(img: Image) -> void:
	var src: Image = LOGO.get_image()
	if src == null or src.is_empty():
		return
	src = src.duplicate() as Image
	if src.is_compressed():
		src.decompress()
	src.convert(Image.FORMAT_RGBA8)
	var fit: float = LOGO_SPAN * SIZE / float(maxi(src.get_width(), src.get_height()))
	var w: int = maxi(1, roundi(src.get_width() * fit))
	var h: int = maxi(1, roundi(src.get_height() * fit))
	src.resize(w, h, Image.INTERPOLATE_LANCZOS)
	var origin: Vector2i = Vector2i(LOGO_CENTRE * SIZE) - Vector2i(w, h) / 2
	for y in h:
		for x in w:
			var c: Color = src.get_pixel(x, y)
			var cover: float = clampf(c.a * (1.0 - c.get_luminance()), 0.0, 1.0)
			var at: Vector2i = origin + Vector2i(x, y)
			if cover > 0.0 and _inside(at):
				img.set_pixelv(at, Color(cover, cover, cover))


static func _print_bar(img: Image) -> void:
	for y in range(roundi(BAR_V.x * SIZE), roundi(BAR_V.y * SIZE)):
		for x in SIZE:
			if _inside(Vector2i(x, y)):
				img.set_pixel(x, y, Color.WHITE)


static func _inside(px: Vector2i) -> bool:
	var uv: Vector2 = (Vector2(px) + Vector2(0.5, 0.5)) / SIZE
	return uv.distance_to(Vector2(0.5, 0.5)) <= PRINT_RADIUS
