class_name KeeperGearView
extends Node3D

# The keeper's gear drawn on his skeleton: each piece's mesh on its save box
# (KeeperGearMeshes builds them inside the boxes) and his jersey skinned over
# them (KeeperJerseyMesh), all of it one skinned mesh (KeeperBodyRig), and the
# break above each knee joining the pad to its thigh rise, and the jersey's
# tail hanging over the pants, painted from the team kit. One material record
# per paint slot is shared by every piece that wears it. The jersey wears the
# skaters' paint: its body and tail a JerseyDecal laid out for him (yoke,
# collar, stripes, crest, name and number), its sleeves a SleeveDecal (stripes
# and the number from the shoulder to the cuff). The pants and socks wear
# keeper_kit.gdshader, which paints the kit's stripes down the side of the
# pants and round the socks.

const S := KeeperMeshKit.Slot
const P := KeeperGear.Part
const _KIT_SHADER: Shader = preload("res://Assets/Shaders/keeper_kit.gdshader")
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

var _rig: KeeperBodyRig = null
# A record per zone of his paint: the slots, then the jersey's (the body's on
# the JERSEY slot).
var _materials: Array[StandardMaterial3D] = []
var _knees: Array[KeeperKneeBreak] = []
var _tail: KeeperJerseyTail = null
# The pants' legs and their shell, each with its stripe down its outer side
# (the shell on both).
var _pants_paint: Dictionary = {}
var _sock: ShaderMaterial = null
var _mirrored: bool = false
var _jersey: JerseyDecal = null
var _jersey_view: SubViewport = null
var _sleeve: SleeveDecal = null
var _sleeve_view: SubViewport = null
var _uniform: Dictionary = {}
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
	_build_jersey_paint()
	_build_pants_paint()
	# The sock's bands run down the shin from its top at the knee, as the
	# skaters' do down theirs.
	_sock = _kit_shader(P.PAD_G)
	var pad: Vector3 = KeeperGear.half_extents(P.PAD_G)
	_sock.set_shader_parameter("half_size", Vector2(pad.x, KeeperGearMeshes.sock_top_in_pad(pad)))
	_sock.set_shader_parameter("height_m", KeeperAnatomy.SHIN_M)
	_rig = KeeperBodyRig.new()
	add_child(_rig)
	_rig.build(_materials, _kit_material, _mirrored)
	for side: int in 2:
		var knee := KeeperKneeBreak.new(KeeperGear.Part.PAD_G + side,
				KeeperGear.Part.RISE_G + side, _materials[S.PADS])
		add_child(knee)
		_knees.append(knee)
	_tail = KeeperJerseyTail.new(_materials[S.JERSEY])
	_rig.add_child(_tail)
	_tail.build(_rig, _mirrored)
	apply_uniform(TeamColorRegistry.get_colors(TeamColorRegistry.DEFAULT_HOME_SLOT, 0))


# A team's kit, as TeamColorRegistry.get_colors returns it.
func apply_uniform(colors: Dictionary) -> void:
	var kit: Dictionary = colors.uniform
	_uniform = kit
	_text_color = colors.text
	_paint_slot(S.HELMET, kit.helmet)
	# The blocker and trapper are a set with the pads, trimmed alike.
	_paint_slot(S.GLOVES, colors.goalie_pads)
	_paint_slot(S.ACCENT, colors.goalie_accent)
	_paint_slot(S.PADS, colors.goalie_pads)
	_paint_slot(S.PANTS, colors.pants)
	for m: ShaderMaterial in _pants_paint.values():
		m.set_shader_parameter("base_color", kit.pants.base)
		_set_stripes(m, kit.pants.stripes)
	_sock.set_shader_parameter("base_color", kit.socks.base)
	_set_stripes(_sock, kit.socks.stripes)
	var preset: Dictionary = colors.get("preset", {})
	_jersey.update_crest(TeamCrest.fruit_for(preset), preset)
	_letter()


func apply_jersey_info(p_name: String, number: int) -> void:
	_player_name = p_name
	_jersey_number = number
	_letter()


func update(skel: KeeperSkeleton) -> void:
	if skel.mirrored != _mirrored:
		_set_mirrored(skel.mirrored)
	_rig.update(skel)
	for knee: KeeperKneeBreak in _knees:
		knee.update(skel)


# One frame of the jersey's tail swinging on him: `down` is gravity's way and
# `acceleration` his own, both in his space; its bones are written if `write`.
func step_tail(delta: float, down: Vector3, acceleration: Vector3, write: bool) -> void:
	_tail.step(delta, down, acceleration, write)


# A right-catcher's bones are the left-catcher's reflected, each box on its own
# x too; his pieces are built turned over on that x, so each is the true mirror
# of the left-catcher's, its glove's thumb on the other side. His jersey is the
# same, its arms' binds on the other hand's bones.
func _set_mirrored(mirrored: bool) -> void:
	_mirrored = mirrored
	_rig.build(_materials, _kit_material, mirrored)
	_tail.build(_rig, mirrored)


func _paint_slot(slot: int, c: Variant) -> void:
	if c is Color:
		_materials[slot].albedo_color = c
		_rig.paint.set_zone(slot, _materials[slot])


# The kit, name and number into the jersey's and the sleeves' decals.
func _letter() -> void:
	if _uniform.is_empty():
		return
	var jersey: Dictionary = _uniform.jersey
	_jersey.update_jersey(jersey.base, UniformPaint.yoke_color(jersey),
			UniformPaint.collar_color(jersey), jersey.stripes, _player_name, _jersey_number,
			_text_color, _uniform.text.stroke)
	_jersey_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	var shoulders: Dictionary = _uniform.shoulders
	_sleeve.update_sleeve(_uniform.sleeve, _jersey_number, shoulders.text, shoulders.stroke)
	_sleeve_view.render_target_update_mode = SubViewport.UPDATE_ONCE


# The kit-shader material a piece's surface wears, or null for its slot's own:
# the pants with the kit's side stripes, and the socks.
func _kit_material(part: int, slot: int) -> Material:
	if slot == S.PANTS:
		return _pants_paint.get(part)
	if slot == S.SOCK:
		return _sock
	return null


# The jersey's two decals and the records that wear them: the body's (the
# tail's material too) on the JERSEY slot, the sleeves' one past the slots.
# Each mesh lays its U so the decal reads forwards on either hand, so neither
# record is turned.
func _build_jersey_paint() -> void:
	_jersey = JerseyDecal.new()
	KeeperJerseyMesh.lay_out(_jersey)
	_jersey_view = _decal_view(_jersey, Vector2i(JerseyDecal.IMG_W, JerseyDecal.IMG_H))
	_sleeve = SleeveDecal.new()
	_sleeve_view = _decal_view(_sleeve, SleeveDecal.SIZE)
	_materials[S.JERSEY] = _decal_record(_jersey_view.get_texture())
	_materials.append(_decal_record(_sleeve_view.get_texture()))
	assert(_materials.size() == KeeperJerseyMesh.ZONE_COUNT)


static func _decal_record(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.roughness = UniformPaint.ROUGH_CLOTH
	BodyRim.apply(m)
	return m


# The stripe's width is the kit's share of a leg's girth, the same on the
# shell, so the stripe runs on unbroken from the leg up over the hip.
func _build_pants_paint() -> void:
	var around: float = KeeperGearMeshes.thigh_girth_m()
	for part: int in [P.THIGH_G, P.THIGH_B, P.PANTS]:
		var m: ShaderMaterial = _kit_shader(part)
		m.set_shader_parameter("side_stripes", true)
		m.set_shader_parameter("around_m", around)
		_pants_paint[part] = m
	_pants_paint[P.THIGH_G].set_shader_parameter("stripe_side", -1.0)
	_pants_paint[P.THIGH_B].set_shader_parameter("stripe_side", 1.0)


func _kit_shader(part: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _KIT_SHADER
	var h: Vector3 = KeeperGear.half_extents(part)
	m.set_shader_parameter("half_size", Vector2(h.x, h.y))
	m.set_shader_parameter("height_m", 2.0 * h.y)
	return m


func _decal_view(decal: Node2D, size: Vector2i) -> SubViewport:
	var view := SubViewport.new()
	view.size = size
	view.disable_3d = true
	view.handle_input_locally = false
	view.gui_disable_input = true
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(view)
	view.add_child(decal)
	return view


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
