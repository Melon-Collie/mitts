class_name GoalieUniformCoordinator
extends RefCounted

# Paints the goalie uniform using a custom spatial shader on the body solid
# (goalie_jersey.gdshader) rather than the lathe + JerseyDecal viewport the
# skaters use, but to the same design: collar, yoke over the shoulders, the
# shoulders' own color below it, metric lettering, the elbow in its own color.
# The body is GoalieMeshBuilder's sculpted solid, held inside the square hitbox
# of a heavily-padded goalie.
#
# Follows the SkaterUniformCoordinator pattern: takes a Goalie reference and
# reads all mesh refs from its public fields, so adding new visual nodes to
# Goalie doesn't require updating the setup() signature.
#
# Entry points match the skater coordinator interface:
#   apply_uniform(colors)           — full v2 colors dict → body shader + all meshes
#   apply_jersey_info(name, number) — repaint text decal only (cached colors reused)

const _ROUGH_PADS: float = 0.75  # leather-and-nylon pad face, between cloth and helmet
const _MAX_STRIPES: int = 5

const _JERSEY_SHADER: Shader = preload("res://Assets/Shaders/goalie_jersey.gdshader")

# Where the jersey ends and the pants band begins on the body solid, in the
# shader's normalized height (0 = collar, 1 = bottom). 0.72 lands just above
# the mesh's hip-crest station (body-local y −0.16) so the color split rides
# the silhouette split.
const PANTS_START_NORM_Y: float = 0.72

# The shoulder floater (Goalie.FLOATER_SEMI_AXES on the shared joint ball),
# measured by test_lettering_scale.gd like the skater's cap: its equator's
# girth and metres of meridian per unit V through the number band.
const FLOATER_GIRTH_M: float = 0.78
const FLOATER_M_PER_V: float = 0.32
const _FLOATER_DECAL_SIZE: Vector2i = Vector2i(512, 256)
const _FLOATER_NUMBER_CENTER_V: float = 0.58


var _goalie: Goalie
# The parts drawn as one mesh from the paint below; rebuilt after every repaint.
var _rig: GoalieBodyRig
var _jersey_mat: ShaderMaterial
var _text_viewport: SubViewport
var _text_decal: GoalieTextDecal
var _crest_viewport: SubViewport
var _crest_decal: GoalieCrestDecal
var _shoulder_viewport: SubViewport
var _shoulder_decal: ShoulderDecal

# Cached for apply_jersey_info refresh.
var _text_color: Color = Color.WHITE
var _shoulder_color: Color = Color.WHITE
var _yoke_color: Color = Color.WHITE
var _shoulder_text_color: Color = Color.BLACK
var _player_name: String = ""
var _jersey_number: int = 0


func setup(goalie: Goalie) -> void:
	_goalie = goalie
	_create_jersey_material()
	_create_shoulder_viewport()
	_rig = GoalieBodyRig.new(goalie)
	goalie.add_child(_rig)
	_rig.rebuild()


func apply_uniform(colors: Dictionary) -> void:
	var uniform: Dictionary = colors.uniform
	_text_color = colors.text

	var jersey: Dictionary = uniform.jersey
	_jersey_mat.set_shader_parameter("base_color", jersey.base)
	_set_stripe_params(jersey.stripes)
	_yoke_color = UniformPaint.yoke_color(jersey)
	_jersey_mat.set_shader_parameter("yoke_color", _yoke_color)
	_jersey_mat.set_shader_parameter("collar_color", UniformPaint.collar_color(jersey))

	# The mask, pads, glove and blocker bake their detail as dark per-facet
	# vertex tints (GoalieMeshBuilder._bake_facet_tint) — multiply them under
	# the kit paint.
	var mask_mat: StandardMaterial3D = UniformPaint.solid(uniform.helmet, UniformPaint.ROUGH_HELMET)
	mask_mat.vertex_color_use_as_albedo = true
	_goalie.head_mesh.material_override = mask_mat

	var pads_mat: StandardMaterial3D = UniformPaint.solid(colors.goalie_pads, _ROUGH_PADS)
	pads_mat.vertex_color_use_as_albedo = true
	_goalie.left_pad_mesh.material_override = pads_mat
	_goalie.right_pad_mesh.material_override = pads_mat.duplicate()
	# The glove (rim + pocket + cuff) and the blocker (board + hand) are each one
	# merged mesh wearing one material, so each is a single paint target.
	_goalie.glove_main_mesh.material_override = pads_mat.duplicate()
	_goalie.blocker_mesh.material_override = pads_mat.duplicate()

	var arms: Dictionary = uniform.arms
	_paint_cylinder_h(_goalie.glove_upper_arm, arms.upper)
	_paint_cylinder_h(_goalie.blocker_upper_arm, arms.upper)
	_paint_cylinder_h(_goalie.glove_forearm, arms.lower)
	_paint_cylinder_h(_goalie.blocker_forearm, arms.lower)

	_shoulder_color = uniform.shoulders.color
	_shoulder_text_color = uniform.shoulders.text
	_rebuild_shoulder_texture()

	var elbow_mat: StandardMaterial3D = UniformPaint.solid(
			SkaterUniformCoordinator.elbow_color(arms))
	_goalie.glove_elbow_sphere.material_override = elbow_mat
	_goalie.blocker_elbow_sphere.material_override = elbow_mat.duplicate()

	# Hip connectors — painted like pants (same horizontal stripe pipeline as
	# the skater's thigh cylinders, minus the per-side uv1_offset since these
	# connectors are too thin for side-stripe positioning to matter).
	_paint_mesh_h(_goalie.left_hip_connector, uniform.pants)
	_paint_mesh_h(_goalie.right_hip_connector, uniform.pants)

	# The body solid is torso THROUGH hips — its lower band paints as the
	# kit's pants (the mesh's hip flare marks the same line in silhouette;
	# see GoalieMeshBuilder._BODY_STATIONS).
	_jersey_mat.set_shader_parameter("pants_color", uniform.pants.base)
	_jersey_mat.set_shader_parameter("pants_start", PANTS_START_NORM_Y)

	# Stick — the house design's goalie colorway (#586): all-white composite,
	# shaft through blade, the real-world goalie norm. The white tape knob is
	# geometry-side (Goalie._init_stick_knob) and never repaints.
	var stick_mat: StandardMaterial3D = StickStyle.make_goalie_stick_material()
	# Shaft and paddle are one merged mesh; the BLADE is a separate node and needs
	# painting in its own right (see GoalieMeshBuilder._merge_stick for why it is
	# held out). It went unpainted and rendered in the default grey against a
	# white composite stick.
	_goalie.stick_shaft_mesh.material_override = stick_mat
	_goalie.stick_blade_mesh.material_override = stick_mat

	var preset: Dictionary = colors.get("preset", {})
	_crest_decal.update_crest(TeamCrest.fruit_for(preset), preset)
	_crest_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_rebuild_text_decal()
	_rig.rebuild()


func apply_jersey_info(p_name: String, number: int) -> void:
	_player_name = p_name
	_jersey_number = number
	_rebuild_text_decal()
	_rebuild_shoulder_texture()


func _create_jersey_material() -> void:
	_jersey_mat = ShaderMaterial.new()
	_jersey_mat.shader = _JERSEY_SHADER
	var body_height: float = 2.0 * GoalieMeshBuilder.BODY_TOP_Y
	_jersey_mat.set_shader_parameter("yoke_depth", GoalieMeshBuilder.YOKE_DEPTH_M / body_height)
	_jersey_mat.set_shader_parameter("collar_radius", GoalieMeshBuilder.COLLAR_RADIUS_M)
	_jersey_mat.set_shader_parameter("collar_center_z", GoalieMeshBuilder.COLLAR_CENTER_Z)

	_text_viewport = SubViewport.new()
	_text_viewport.name = "GoalieTextViewport"
	_text_viewport.size = Vector2i(GoalieTextDecal.IMG_W, GoalieTextDecal.IMG_H)
	_text_viewport.transparent_bg = true
	_text_viewport.disable_3d = true
	_text_viewport.handle_input_locally = false
	_text_viewport.gui_disable_input = true
	_text_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_goalie.add_child(_text_viewport)

	_text_decal = GoalieTextDecal.new()
	_text_decal.name = "GoalieTextDecal"
	_text_viewport.add_child(_text_decal)

	_jersey_mat.set_shader_parameter("text_decal", _text_viewport.get_texture())

	_crest_viewport = SubViewport.new()
	_crest_viewport.name = "GoalieCrestViewport"
	_crest_viewport.size = Vector2i(GoalieTextDecal.IMG_W, GoalieTextDecal.IMG_H)
	_crest_viewport.transparent_bg = true
	_crest_viewport.disable_3d = true
	_crest_viewport.handle_input_locally = false
	_crest_viewport.gui_disable_input = true
	_crest_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_goalie.add_child(_crest_viewport)

	_crest_decal = GoalieCrestDecal.new()
	_crest_decal.name = "GoalieCrestDecal"
	_crest_viewport.add_child(_crest_decal)

	_jersey_mat.set_shader_parameter("crest_decal", _crest_viewport.get_texture())
	_goalie.body_mesh.material_override = _jersey_mat


# Shared SubViewport + ShoulderDecal for both shoulder spheres, each turned to
# face the number outward: the glove side is -X, the blocker side +X.
func _create_shoulder_viewport() -> void:
	_shoulder_decal = ShoulderDecal.new()
	_shoulder_decal.name = "GoalieShoulderDecal"
	_shoulder_decal.use_part(_FLOATER_DECAL_SIZE, FLOATER_GIRTH_M, FLOATER_M_PER_V,
			floater_yoke_v(), _FLOATER_NUMBER_CENTER_V)
	_shoulder_viewport = SubViewport.new()
	_shoulder_viewport.name = "GoalieShoulderViewport"
	_shoulder_viewport.size = _shoulder_decal.size
	_shoulder_viewport.transparent_bg = false
	_shoulder_viewport.disable_3d = true
	_shoulder_viewport.handle_input_locally = false
	_shoulder_viewport.gui_disable_input = true
	_shoulder_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_goalie.add_child(_shoulder_viewport)
	_shoulder_viewport.add_child(_shoulder_decal)

	var tex: ViewportTexture = _shoulder_viewport.get_texture()
	_goalie.glove_shoulder_sphere.material_override = ShoulderDecal.part_material(tex, -1.0)
	_goalie.blocker_shoulder_sphere.material_override = ShoulderDecal.part_material(tex, 1.0)


func _rebuild_shoulder_texture() -> void:
	if _shoulder_decal == null:
		return
	_shoulder_decal.update_shoulder(_shoulder_color, _yoke_color, _jersey_number,
			_shoulder_text_color)
	_shoulder_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


# The V at which the body's yoke line crosses the floater, so the yoke runs off
# the body's sides over the top of each floater at one height. The floater
# hangs at the shoulder joint plus its outset and tilts with the body, so the
# crossing is fixed in the body's frame; V runs pole to pole as cos⁻¹ of height.
static func floater_yoke_v() -> float:
	var line_y: float = GoalieMeshBuilder.BODY_TOP_Y - GoalieMeshBuilder.YOKE_DEPTH_M
	var center_y: float = GoalieAnatomy.SHOULDER_OFFSET.y + Goalie.FLOATER_OUTSET.y
	return acos(clampf((line_y - center_y) / Goalie.FLOATER_SEMI_AXES.y, -1.0, 1.0)) / PI


# Packs up to _MAX_STRIPES stripe definitions from the v2 stripes array into
# the shader's fixed-size uniform arrays.
func _set_stripe_params(stripes: Array[Dictionary]) -> void:
	var count: int = mini(stripes.size(), _MAX_STRIPES)
	_jersey_mat.set_shader_parameter("stripe_count", count)

	var colors: Array[Color] = []
	var positions: PackedFloat32Array = PackedFloat32Array()
	var widths: PackedFloat32Array = PackedFloat32Array()
	for i: int in range(_MAX_STRIPES):
		if i < count:
			colors.append(stripes[i].color as Color)
			positions.append(float(stripes[i].pos))
			widths.append(float(stripes[i].width))
		else:
			colors.append(Color.WHITE)
			positions.append(0.0)
			widths.append(0.0)
	_jersey_mat.set_shader_parameter("stripe_colors", colors)
	_jersey_mat.set_shader_parameter("stripe_positions", positions)
	_jersey_mat.set_shader_parameter("stripe_widths", widths)


func _rebuild_text_decal() -> void:
	_text_decal.update_text(_player_name, _jersey_number, _text_color)
	_text_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


# Paints an arm bone. The bone IS the MeshInstance3D (Goalie._make_arm_bone), not
# a wrapper around a child mesh.
func _paint_cylinder_h(bone: Node3D, segment: Dictionary) -> void:
	var visual: MeshInstance3D = bone as MeshInstance3D
	if visual == null:
		return
	_paint_mesh_h(visual, segment)


# Paints any MeshInstance3D directly with horizontal stripes (or solid).
func _paint_mesh_h(visual: MeshInstance3D, segment: Dictionary) -> void:
	if visual == null:
		return
	var stripes: Array = segment.get("stripes", []) as Array
	if stripes.is_empty():
		visual.material_override = UniformPaint.solid(segment.base)
		return
	var tex: ImageTexture = UniformPaint.h_stripes(segment.base, stripes)
	visual.material_override = UniformPaint.textured(tex)
