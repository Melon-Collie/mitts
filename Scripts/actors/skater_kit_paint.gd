class_name SkaterKitPaint
extends RefCounted

# A kit on a skater's body: every zone of its BodyZonePaint the uniform and the
# gear style dress — the jersey and its sleeves through their decals, the
# helmet, the pants, the socks and the knees under them, the gloves, the skates
# and the skin. Shared by the rink's skater (SkaterUniformCoordinator) and the
# display figures (LockerMannequin), so a figure wears exactly what the ice
# shows. The decals' viewports live under `viewport_host`.

const _Upper = SkaterMeshBuilder.UpperSurface
const _Leg = SkaterMeshBuilder.LegSurface
const _UPPER: int = SkaterMeshBuilder.UPPER_ZONE_BASE
const _PANTS_TEX_WIDTH_PX: int = 128

var _paint: BodyZonePaint
var _jersey_viewport: SubViewport
var _jersey_decal: JerseyDecal
var _sleeve_viewport: SubViewport
var _sleeve_decal: SleeveDecal

var _uniform: Dictionary = {}
var _text_color: Color = Color.BLACK
var _player_name: String = ""
var _jersey_number: int = 0
# The slots a gear model's TEAM / ACCENT / LIGHT zones resolve against.
var _team_accent: Color = Color.WHITE
var _team_secondary: Color = Color.WHITE
var _team_light: Color = Color.WHITE
var _glove_accent: Color = Color.WHITE


func _init(paint: BodyZonePaint, viewport_host: Node) -> void:
	_paint = paint
	_jersey_decal = JerseyDecal.new()
	_jersey_decal.name = "JerseyDecal"
	_jersey_viewport = _decal_viewport(viewport_host, "JerseyViewport", _jersey_decal,
			Vector2i(JerseyDecal.IMG_W, JerseyDecal.IMG_H))
	_upper(_Upper.TORSO, JerseyDecal.torso_material(_jersey_viewport.get_texture()))
	_sleeve_decal = SleeveDecal.new()
	_sleeve_decal.name = "SleeveDecal"
	_sleeve_viewport = _decal_viewport(viewport_host, "SleeveViewport", _sleeve_decal,
			SleeveDecal.SIZE)
	for side: float in [-1.0, 1.0]:
		_upper(SkaterConnectedMesh.sleeve_surface(side),
				SleeveDecal.part_material(_sleeve_viewport.get_texture(), side))


# The full v2 colors dict (TeamColorRegistry.get_colors): the kit and the slots
# its gear resolves against.
func apply_uniform(colors: Dictionary) -> void:
	_uniform = colors.uniform
	_text_color = colors.text
	_team_accent = colors.primary
	_team_secondary = colors.secondary
	_team_light = colors.light
	_glove_accent = colors.glove_accent
	var preset: Dictionary = colors.get("preset", {})
	_jersey_decal.update_crest(TeamCrest.fruit_for(preset), preset)
	_rebuild_decals()
	_upper(_Upper.HELMET_SHELL, UniformPaint.solid(_uniform.helmet, UniformPaint.ROUGH_HELMET))
	var pants: Dictionary = _uniform.pants
	_paint_pants(pants)
	_upper(_Upper.PELVIS, UniformPaint.solid(pants.base, UniformPaint.ROUGH_NYLON))
	var socks: Dictionary = _uniform.socks
	var sock: StandardMaterial3D = UniformPaint.solid(socks.base) if socks.stripes.is_empty() \
			else UniformPaint.textured(UniformPaint.h_stripes(socks.base, socks.stripes))
	_leg_pair(_Leg.SOCK_L, _Leg.SOCK_R, sock)
	# The knee sits below the pant hem, over the shin guard's cap, so it is sock:
	# solid base, which every kit's sock top already is (test_knee_wears_the_sock.gd).
	_leg_pair(_Leg.KNEE_L, _Leg.KNEE_R, UniformPaint.solid(socks.base))


# The gear style's models on the gloves and the skates, and its laces, against
# the kit applied last.
func apply_gear(gear: GearStyleConfig) -> void:
	if _uniform.is_empty():
		return
	var gloves: Color = _uniform.gloves
	var glove_mats: Array[StandardMaterial3D] = []
	for zone: int in [GearModelRegistry.GLOVE_BODY, GearModelRegistry.GLOVE_FINGERS,
			GearModelRegistry.GLOVE_CUFF]:
		glove_mats.append(UniformPaint.solid(GearModelRegistry.glove_color(gear.glove_model,
				zone, gloves, _glove_accent, _team_light), UniformPaint.ROUGH_GLOVE))
	_upper_pair(_Upper.TOP_HAND, _Upper.BOTTOM_HAND, glove_mats[0])
	_upper_pair(_Upper.TOP_FINGERS, _Upper.BOTTOM_FINGERS, glove_mats[1])
	_upper_pair(_Upper.TOP_CUFF, _Upper.BOTTOM_CUFF, glove_mats[2])
	# The five zones a skate model paints. The holder wears the skate finish
	# rather than the runner's steel gloss — it is molded plastic; the runner is
	# not a zone and keeps the steel its part ships with.
	for zone: Array in [
			[GearModelRegistry.SKATE_QUARTER, _Leg.FOOT_L_SHELL, _Leg.FOOT_R_SHELL],
			[GearModelRegistry.SKATE_TOE, _Leg.FOOT_L_TOE, _Leg.FOOT_R_TOE],
			[GearModelRegistry.SKATE_COLLAR, _Leg.SKATE_L_COLLAR, _Leg.SKATE_R_COLLAR],
			[GearModelRegistry.SKATE_STRIPE, _Leg.SKATE_L_STRIPE, _Leg.SKATE_R_STRIPE],
			[GearModelRegistry.SKATE_HOLDER, _Leg.FOOT_L_HOLDER, _Leg.FOOT_R_HOLDER]]:
		_leg_pair(zone[1], zone[2], UniformPaint.solid(GearModelRegistry.skate_color(
				gear.skate_model, zone[0], _team_accent, _team_secondary, _team_light),
				UniformPaint.ROUGH_SKATE))
	_leg_pair(_Leg.FOOT_L_LACES, _Leg.FOOT_R_LACES, UniformPaint.solid(
			TapeColorRegistry.resolve(gear.lace_color, _team_accent)))


# The name and number the sweater and its sleeves are lettered with.
func set_jersey_info(player_name: String, jersey_number: int) -> void:
	_player_name = player_name
	_jersey_number = jersey_number
	_rebuild_decals()


# The head and neck in the identity's tone, albedo only: the record keeps the
# vertex-colour read the face's features need.
func set_skin_tone(index: int) -> void:
	var zone: int = _UPPER + _Upper.HELMET_SKIN
	var mat: StandardMaterial3D = _paint.zone(zone)
	var skin: Color = SkinToneRegistry.color_for(index)
	mat.albedo_color = Color(skin.r, skin.g, skin.b, mat.albedo_color.a)
	_paint.set_zone(zone, mat)


func _rebuild_decals() -> void:
	if _uniform.is_empty():
		return
	var jersey: Dictionary = _uniform.jersey
	_jersey_decal.update_jersey(jersey.base, UniformPaint.yoke_color(jersey),
			UniformPaint.collar_color(jersey), jersey.stripes, _player_name, _jersey_number,
			_text_color, _uniform.text.stroke)
	_jersey_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var shoulders: Dictionary = _uniform.shoulders
	_sleeve_decal.update_sleeve(_uniform.sleeve, _jersey_number, shoulders.text,
			shoulders.stroke)
	_sleeve_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


# The pants' vertical side stripes, turned per leg so the column lands on each
# one's outside.
func _paint_pants(pants: Dictionary) -> void:
	if pants.stripes.is_empty():
		_leg_pair(_Leg.THIGH_L, _Leg.THIGH_R, UniformPaint.solid(pants.base, UniformPaint.ROUGH_NYLON))
		return
	var left: StandardMaterial3D = UniformPaint.textured(
			make_pants_stripes_texture(pants.base, pants.stripes),
			UniformPaint.ROUGH_NYLON)
	var right: StandardMaterial3D = left.duplicate() as StandardMaterial3D
	left.uv1_offset = Vector3(-0.25, 0.0, 0.0)
	right.uv1_offset = Vector3(0.25, 0.0, 0.0)
	_paint.set_zone(_Leg.THIGH_L, left)
	_paint.set_zone(_Leg.THIGH_R, right)


# A (width_px × 4) image of vertical stripe columns: each stripe's pos is the U
# of its column's centre and its width the column's width. Public because
# tools/kit_capture.gd lays the pants out flat in this same paint.
static func make_pants_stripes_texture(base: Color, stripes: Array[Dictionary]) -> ImageTexture:
	var img := Image.create(_PANTS_TEX_WIDTH_PX, UniformPaint.STRIPE_TEX_WIDTH_PX, false,
			Image.FORMAT_RGBA8)
	img.fill(base)
	for s: Dictionary in stripes:
		var center_px: float = float(s.pos) * float(_PANTS_TEX_WIDTH_PX)
		var half_px: float = float(s.width) * float(_PANTS_TEX_WIDTH_PX) * 0.5
		var x0: int = clampi(int(round(center_px - half_px)), 0, _PANTS_TEX_WIDTH_PX)
		var x1: int = clampi(int(round(center_px + half_px)), 0, _PANTS_TEX_WIDTH_PX)
		if x1 > x0:
			img.fill_rect(Rect2i(x0, 0, x1 - x0, UniformPaint.STRIPE_TEX_WIDTH_PX), s.color)
	return ImageTexture.create_from_image(img)


func _upper(surface: int, mat: StandardMaterial3D) -> void:
	_paint.set_zone(_UPPER + surface, mat)


func _upper_pair(a: int, b: int, mat: StandardMaterial3D) -> void:
	_upper(a, mat)
	_upper(b, mat.duplicate() as StandardMaterial3D)


func _leg_pair(a: int, b: int, mat: StandardMaterial3D) -> void:
	_paint.set_zone(a, mat)
	_paint.set_zone(b, mat.duplicate() as StandardMaterial3D)


static func _decal_viewport(host: Node, node_name: String, decal: Node2D,
		size: Vector2i) -> SubViewport:
	var vp := SubViewport.new()
	vp.name = node_name
	vp.size = size
	vp.transparent_bg = false
	vp.disable_3d = true
	vp.handle_input_locally = false
	vp.gui_disable_input = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	host.add_child(vp)
	vp.add_child(decal)
	return vp
