class_name KeeperGearView
extends Node3D

# The keeper's gear drawn on his skeleton: each piece's mesh placed on its save
# box (KeeperGearMeshes builds them inside the boxes), and the break above each
# knee joining the pad to its thigh rise, and the jersey's tail hanging over
# the pants, painted from the team kit. One
# material per paint slot is shared by every piece that wears it; the jersey
# and its sleeves wear keeper_jersey.gdshader instead, which paints the kit's
# yoke, collar, shoulder caps, stripes, crest and lettering by height, and the
# kit's pants stripes down the sides of the pants.

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
var _tail: KeeperJerseyTail = null
var _jersey: ShaderMaterial = null
var _tail_paint: ShaderMaterial = null
var _upper_arm: ShaderMaterial = null
var _forearm: ShaderMaterial = null
# The pants' legs and their shell, each with its stripe down its outer side
# (the shell on both).
var _pants_paint: Dictionary = {}
var _front: KeeperJerseyDecal = null
var _back: KeeperJerseyDecal = null
var _shoulder: KeeperJerseyDecal = null
var _front_view: SubViewport = null
var _back_view: SubViewport = null
var _shoulder_view: SubViewport = null
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
			var mat: Material = _kit_material(part, slots[s])
			mi.set_surface_override_material(s, mat if mat != null else _materials[slots[s]])
		add_child(mi)
		_pieces.append(mi)
	for side: int in 2:
		var knee := KeeperKneeBreak.new(KeeperGear.Part.PAD_G + side,
				KeeperGear.Part.RISE_G + side, _materials[S.PADS])
		add_child(knee)
		_knees.append(knee)
	_tail = KeeperJerseyTail.new(_tail_paint)
	add_child(_tail)
	apply_uniform(TeamColorRegistry.get_colors(TeamColorRegistry.DEFAULT_HOME_SLOT, 0))


# A team's kit, as TeamColorRegistry.get_colors returns it.
func apply_uniform(colors: Dictionary) -> void:
	var kit: Dictionary = colors.uniform
	var jersey: Dictionary = kit.jersey
	var h: Vector3 = KeeperGear.half_extents(P.CHEST)
	var length: float = 2.0 * h.y + KeeperJerseyTail.length_m()
	for m: ShaderMaterial in [_jersey, _tail_paint]:
		m.set_shader_parameter("base_color", jersey.base)
		m.set_shader_parameter("yoke_color", UniformPaint.yoke_color(jersey))
		m.set_shader_parameter("collar_color", UniformPaint.collar_color(jersey))
		m.set_shader_parameter("height_m", length)
		_set_stripes(m, _jersey_stripes(jersey.stripes, length))
	var arms: Dictionary = kit.arms
	_upper_arm.set_shader_parameter("base_color", arms.upper.base)
	_upper_arm.set_shader_parameter("yoke_color", UniformPaint.yoke_color(jersey))
	_upper_arm.set_shader_parameter("cap_color", kit.shoulders.color)
	_shoulder.text_color = kit.shoulders.text
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
	for m: ShaderMaterial in _pants_paint.values():
		m.set_shader_parameter("base_color", kit.pants.base)
		_set_stripes(m, kit.pants.stripes)
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
	_tail.update(skel)


func _paint_slot(slot: int, c: Variant) -> void:
	if c is Color:
		_materials[slot].albedo_color = c


func _letter() -> void:
	_back.set_lettering(_player_name, _jersey_number, _text_color)
	_back_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	_shoulder.set_lettering("", _jersey_number, _shoulder.text_color)
	_shoulder_view.render_target_update_mode = SubViewport.UPDATE_ONCE


# The kit-shader material a piece's surface wears, or null for its slot's own:
# the jersey and its sleeves, and the pants with the kit's side stripes.
func _kit_material(part: int, slot: int) -> Material:
	if slot == S.PANTS:
		return _pants_paint.get(part)
	if slot != S.JERSEY:
		return null
	match part:
		P.CHEST:
			return _jersey
		P.UPPER_ARM_G, P.UPPER_ARM_B:
			return _upper_arm
		P.FOREARM_G, P.FOREARM_B:
			return _forearm
	return null


func _build_jersey_materials() -> void:
	var h: Vector3 = KeeperGear.half_extents(P.CHEST)
	_jersey = _jersey_shader(P.CHEST)
	_jersey.set_shader_parameter("yoke_depth", KeeperJerseyDecal.YOKE_DEPTH_M / (2.0 * h.y))
	_jersey.set_shader_parameter("collar_radius", _COLLAR_RADIUS_M)
	_jersey.set_shader_parameter("decals", true)
	_front = KeeperJerseyDecal.new()
	_front_view = _decal_view(_front)
	_back = KeeperJerseyDecal.new()
	_back.face = KeeperJerseyDecal.Face.BACK
	_back_view = _decal_view(_back)
	_shoulder = KeeperJerseyDecal.new()
	_shoulder.face = KeeperJerseyDecal.Face.SHOULDER
	_shoulder_view = _decal_view(_shoulder)
	_jersey.set_shader_parameter("crest_decal", _front_view.get_texture())
	_jersey.set_shader_parameter("text_decal", _back_view.get_texture())
	_tail_paint = _jersey_shader(P.CHEST)
	_tail_paint.set_shader_parameter("depth_in_uv", true)
	_upper_arm = _jersey_shader(P.UPPER_ARM_G)
	_build_shoulder_paint()
	_build_pants_paint()
	_forearm = _jersey_shader(P.FOREARM_G)
	# The sleeve's bands run from the elbow joint, above which is the pad.
	var elbow: Vector3 = KeeperGearMeshes.elbow_in_forearm(KeeperGear.half_extents(P.FOREARM_G))
	_forearm.set_shader_parameter("half_size", Vector2(KeeperGear.FOREARM_PAD_RADIUS_M, elbow.y))
	_forearm.set_shader_parameter("height_m", KeeperAnatomy.FOREARM_M)
	_forearm.set_shader_parameter("cap_center", elbow)
	_forearm.set_shader_parameter("cap_radii", Vector3.ONE * KeeperGear.ELBOW_PAD_RADIUS_M)


# The shoulder cap over the top of each sleeve: the yoke over its top, the
# kit's shoulder colour down to its bottom, the number on its outer face.
func _build_shoulder_paint() -> void:
	var h: Vector3 = KeeperGear.half_extents(P.UPPER_ARM_G)
	var joint: float = h.y - KeeperGear.SHOULDER_CAP_ABOVE_JOINT_M
	_upper_arm.set_shader_parameter("yoke_depth",
			(h.y - joint - KeeperGearMeshes.SHOULDER_CAP_YOKE_M) / (2.0 * h.y))
	_upper_arm.set_shader_parameter("cap_until",
			(h.y - joint - KeeperGearMeshes.SHOULDER_CAP_BOTTOM_M) / (2.0 * h.y))
	_upper_arm.set_shader_parameter("shoulder_number", true)
	_upper_arm.set_shader_parameter("number_decal", _shoulder_view.get_texture())
	_upper_arm.set_shader_parameter("number_band", Vector2(
			joint + KeeperGearMeshes.SHOULDER_CAP_PROFILE[2].x, KeeperJerseyDecal.SHOULDER_BAND.y))
	_upper_arm.set_shader_parameter("number_width", KeeperJerseyDecal.SHOULDER_BAND.x)


# The stripe's width is the kit's share of a leg's girth, the same on the
# shell, so the stripe runs on unbroken from the leg up over the hip.
func _build_pants_paint() -> void:
	var around: float = KeeperGearMeshes.thigh_girth_m()
	for part: int in [P.THIGH_G, P.THIGH_B, P.PANTS]:
		var m: ShaderMaterial = _jersey_shader(part)
		m.set_shader_parameter("side_stripes", true)
		m.set_shader_parameter("around_m", around)
		_pants_paint[part] = m
	_pants_paint[P.THIGH_G].set_shader_parameter("stripe_side", -1.0)
	_pants_paint[P.THIGH_B].set_shader_parameter("stripe_side", 1.0)


func _jersey_shader(part: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _JERSEY_SHADER
	var h: Vector3 = KeeperGear.half_extents(part)
	m.set_shader_parameter("half_size", Vector2(h.x, h.y))
	m.set_shader_parameter("height_m", 2.0 * h.y)
	return m


func _decal_view(decal: KeeperJerseyDecal) -> SubViewport:
	var view := SubViewport.new()
	view.size = KeeperJerseyDecal.image_size(decal.face)
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
