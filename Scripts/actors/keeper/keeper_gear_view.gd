class_name KeeperGearView
extends Node3D

# The keeper's gear drawn on his skeleton: each piece's mesh placed on its save
# box (KeeperGearMeshes builds them inside the boxes), and the break above each
# knee joining the pad to its thigh rise, painted from the team kit. One
# material per paint slot is shared by every piece that wears it; the jersey
# and its sleeves wear keeper_jersey.gdshader instead, which paints the kit's
# yoke, collar, shoulder caps, stripes, crest and lettering by height.

const S := KeeperMeshKit.Slot
const P := KeeperGear.Part
const _JERSEY_SHADER: Shader = preload("res://Assets/Shaders/keeper_jersey.gdshader")
const _MAX_STRIPES: int = 5

# The slots no kit colours: skate steel and boot, the stick, tape, straps, cage
# (and the skin, the default tone until he is given one).
const _FIXED: Dictionary = {
	S.SKATE_BOOT: Color(0.10, 0.10, 0.11),
	S.SKATE_STEEL: Color(0.78, 0.80, 0.84),
	S.STICK: Color(0.92, 0.92, 0.90),
	S.STICK_TAPE: Color(0.12, 0.12, 0.13),
	S.STRAP: Color(0.15, 0.15, 0.16),
	S.CAGE: Color(0.86, 0.86, 0.88),
}
# The collar ring on the jersey's top face, in its box frame.
const _COLLAR_RADIUS_M: float = 0.085

var _pieces: Array[MeshInstance3D] = []
var _materials: Array[StandardMaterial3D] = []
var _knees: Array[KeeperKneeBreak] = []
var _jersey: ShaderMaterial = null
var _upper_arm: ShaderMaterial = null
var _forearm: ShaderMaterial = null
var _front: KeeperJerseyDecal = null
var _back: KeeperJerseyDecal = null
var _front_view: SubViewport = null
var _back_view: SubViewport = null
var _text_color: Color = Color.WHITE
var _player_name: String = ""
var _jersey_number: int = 0


func _ready() -> void:
	for slot: int in KeeperMeshKit.SLOT_COUNT:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.75
		m.albedo_color = _FIXED.get(slot, Color(0.85, 0.85, 0.85))
		BodyRim.apply(m)
		_materials.append(m)
	_materials[S.SKATE_STEEL].metallic = 0.6
	_materials[S.SKATE_STEEL].roughness = 0.35
	_materials[S.SKIN].albedo_color = SkinToneRegistry.color_for(SkinToneRegistry.DEFAULT_INDEX)
	_materials[S.SKIN].roughness = 0.85
	_materials[S.HELMET].roughness = UniformPaint.ROUGH_HELMET
	_build_jersey_materials()
	for part: int in KeeperGear.PART_COUNT:
		var mi := MeshInstance3D.new()
		var mesh: ArrayMesh = KeeperGearMeshes.mesh(part)
		mi.mesh = mesh
		var slots: PackedInt32Array = KeeperMeshKit.surface_slots(mesh)
		for s: int in slots.size():
			var mat: Material = _materials[slots[s]]
			if slots[s] == S.JERSEY:
				mat = _jersey_material(part)
			mi.set_surface_override_material(s, mat)
		add_child(mi)
		_pieces.append(mi)
	for side: int in 2:
		var knee := KeeperKneeBreak.new(KeeperGear.Part.PAD_G + side,
				KeeperGear.Part.RISE_G + side, _materials[S.PADS])
		add_child(knee)
		_knees.append(knee)
	apply_uniform(TeamColorRegistry.get_colors(TeamColorRegistry.DEFAULT_HOME_SLOT, 0))


# A team's kit, as TeamColorRegistry.get_colors returns it.
func apply_uniform(colors: Dictionary) -> void:
	var kit: Dictionary = colors.uniform
	var jersey: Dictionary = kit.jersey
	var h: Vector3 = KeeperGear.half_extents(P.CHEST)
	_jersey.set_shader_parameter("base_color", jersey.base)
	_jersey.set_shader_parameter("yoke_color", UniformPaint.yoke_color(jersey))
	_jersey.set_shader_parameter("collar_color", UniformPaint.collar_color(jersey))
	_jersey.set_shader_parameter("cap_color", kit.shoulders.color)
	_set_stripes(_jersey, _jersey_stripes(jersey.stripes, 2.0 * h.y))
	var arms: Dictionary = kit.arms
	_upper_arm.set_shader_parameter("base_color", arms.upper.base)
	_set_stripes(_upper_arm, arms.upper.stripes)
	_forearm.set_shader_parameter("base_color", arms.lower.base)
	_forearm.set_shader_parameter("cap_color", _elbow_color(arms))
	_set_stripes(_forearm, arms.lower.stripes)
	_paint_slot(S.JERSEY, jersey.base)
	_paint_slot(S.HELMET, kit.helmet)
	_paint_slot(S.GLOVES, colors.gloves)
	_paint_slot(S.GLOVE_ACCENT, colors.glove_accent)
	_paint_slot(S.PADS, colors.goalie_pads)
	_paint_slot(S.PANTS, colors.pants)
	_paint_slot(S.PANTS_STRIPE, colors.pants_stripe)
	var preset: Dictionary = colors.get("preset", {})
	_front.set_crest(TeamCrest.fruit_for(preset), preset)
	_front_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	_text_color = colors.text
	_letter()


func apply_jersey_info(p_name: String, number: int) -> void:
	_player_name = p_name
	_jersey_number = number
	_letter()


func update(skel: KeeperSkeleton) -> void:
	for part: int in _pieces.size():
		_pieces[part].transform = KeeperGear.box(skel, part)
	for knee: KeeperKneeBreak in _knees:
		knee.update(skel)


func _paint_slot(slot: int, c: Variant) -> void:
	if c is Color:
		_materials[slot].albedo_color = c


func _letter() -> void:
	_back.set_lettering(_player_name, _jersey_number, _text_color)
	_back_view.render_target_update_mode = SubViewport.UPDATE_ONCE


func _jersey_material(part: int) -> Material:
	match part:
		P.CHEST:
			return _jersey
		P.UPPER_ARM_G, P.UPPER_ARM_B:
			return _upper_arm
		P.FOREARM_G, P.FOREARM_B:
			return _forearm
	return _materials[S.JERSEY]


func _build_jersey_materials() -> void:
	var h: Vector3 = KeeperGear.half_extents(P.CHEST)
	_jersey = _jersey_shader(P.CHEST)
	_jersey.set_shader_parameter("yoke_depth", KeeperJerseyDecal.YOKE_DEPTH_M / (2.0 * h.y))
	_jersey.set_shader_parameter("collar_radius", _COLLAR_RADIUS_M)
	_jersey.set_shader_parameter("cap_center", Vector3(KeeperGearMeshes.SHOULDER_CAP.x,
			h.y - KeeperGearMeshes.SHOULDER_CAP.y, 0.0))
	_jersey.set_shader_parameter("cap_radii", KeeperGearMeshes.SHOULDER_CAP_R)
	_jersey.set_shader_parameter("decals", true)
	_front = KeeperJerseyDecal.new()
	_front_view = _decal_view(_front)
	_back = KeeperJerseyDecal.new()
	_back.face = KeeperJerseyDecal.Face.BACK
	_back_view = _decal_view(_back)
	_jersey.set_shader_parameter("crest_decal", _front_view.get_texture())
	_jersey.set_shader_parameter("text_decal", _back_view.get_texture())
	_upper_arm = _jersey_shader(P.UPPER_ARM_G)
	_forearm = _jersey_shader(P.FOREARM_G)
	var f: Vector3 = KeeperGear.half_extents(P.FOREARM_G)
	_forearm.set_shader_parameter("cap_center", KeeperGearMeshes.ELBOW_CAP_CENTER * f)
	_forearm.set_shader_parameter("cap_radii", KeeperGearMeshes.ELBOW_CAP_RADII * f)


func _jersey_shader(part: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _JERSEY_SHADER
	var h: Vector3 = KeeperGear.half_extents(part)
	m.set_shader_parameter("half_size", Vector2(h.x, h.y))
	return m


func _decal_view(decal: KeeperJerseyDecal) -> SubViewport:
	var view := SubViewport.new()
	view.size = KeeperJerseyDecal.image_size()
	view.transparent_bg = true
	view.disable_3d = true
	view.handle_input_locally = false
	view.gui_disable_input = true
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(view)
	view.add_child(decal)
	return view


# The kit's jersey stripes as shares of a jersey `height_m` tall. They are
# authored against UniformPaint's design height: a hem band keeps its place
# above the hem, a band in the top half its place under the collar.
static func _jersey_stripes(stripes: Array, height_m: float) -> Array:
	var design: float = UniformPaint.JERSEY_STRIPE_DESIGN_HEIGHT_M
	var out: Array = []
	for s: Dictionary in stripes:
		var centre_m: float = float(s.pos) * design
		if float(s.pos) > 0.5:
			centre_m += height_m - design
		out.append({"pos": centre_m / height_m, "width": float(s.width) * design / height_m,
				"color": s.color})
	return out


# The elbow cap's colour: the kit's arms.elbow when it names one, else whatever
# the forearm's bands put at its elbow end, so the cap disappears into the
# sleeve.
static func _elbow_color(arms: Dictionary) -> Color:
	var elbow: Variant = arms.get("elbow")
	if elbow is Color:
		return elbow
	var c: Color = arms.lower.base
	for s: Dictionary in arms.lower.stripes:
		if absf(float(s.pos)) < float(s.width) * 0.5:
			c = s.color
	return c


static func _set_stripes(m: ShaderMaterial, stripes: Array) -> void:
	var count: int = mini(stripes.size(), _MAX_STRIPES)
	var colors: Array[Color] = []
	var positions := PackedFloat32Array()
	var widths := PackedFloat32Array()
	for i: int in _MAX_STRIPES:
		var s: Dictionary = stripes[i] if i < count else {}
		colors.append(s.get("color", Color.WHITE))
		positions.append(float(s.get("pos", 0.0)))
		widths.append(float(s.get("width", 0.0)))
	m.set_shader_parameter("stripe_count", count)
	m.set_shader_parameter("stripe_colors", colors)
	m.set_shader_parameter("stripe_positions", positions)
	m.set_shader_parameter("stripe_widths", widths)
