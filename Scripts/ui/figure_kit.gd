class_name FigureKit
extends RefCounted

# A kit-dressed display figure's parts and the dressing that paints them. The
# parts are the rink's own shared part meshes (SkaterMeshBuilder) and a stick
# assembly (shaft, blade, tape, knob); the dressing is the sweater through the
# rink's own decals (stripes, collar, yoke, crest, name and numbers), the kit,
# the four gear picks, the jersey's tuck, the hair and the stick's paint and
# tape. It builds and it dresses; the figure holding it poses the parts — the
# player screen's case stands it holding its stick, the lobby seats it on the
# bench.

const KNOB_HEIGHT_M: float = 0.05
const _SHAFT_CROSS := Vector2(0.04, 0.05)

# Surface finishes, matching the rink's (SkaterUniformCoordinator).
const _CLOTH_ROUGH: float = 0.9
const _LEATHER_ROUGH: float = 0.42
const _HELMET_ROUGH: float = 0.28
const _STEEL_ROUGH: float = 0.25

var torso: MeshInstance3D = null
# The pants from the waistband down — the seat under the jersey's hem, and on a
# tucked figure the waistband the jersey goes into.
var pelvis: MeshInstance3D = null
# Shell and head/neck skin as two surfaces, so the head rides the helmet's scale
# exactly as it rides its bone. Face gear and hair are its children at identity.
var helmet: MeshInstance3D = null
var face: MeshInstance3D = null
var scalp: MeshInstance3D = null
var facial_hair: MeshInstance3D = null
var brows: MeshInstance3D = null
var shoulders: Array[MeshInstance3D] = []
var thighs: Array[MeshInstance3D] = []
var knees: Array[MeshInstance3D] = []
var socks: Array[MeshInstance3D] = []
# Collar assembly = the ankle cuff plus its accent stripe; boot assembly =
# quarter, toe cap, holder, steel runner and laces. Between them they carry
# every zone a skate model paints, in one node each.
var collars: Array[MeshInstance3D] = []
var boots: Array[MeshInstance3D] = []
var upper_arms: Array[MeshInstance3D] = []
var forearms: Array[MeshInstance3D] = []
var elbows: Array[MeshInstance3D] = []
var hands: Array[MeshInstance3D] = []
var cuffs: Array[MeshInstance3D] = []

# The stick in its own frame: heel at the origin, the shaft climbing along the
# lie axis, so placing it is one transform on `stick_root`.
var stick_root: Node3D = null
var shaft: MeshInstance3D = null
var shaft_mat: ShaderMaterial = null
var blade: MeshInstance3D = null
var tape_mesh: MeshInstance3D = null
var knob: MeshInstance3D = null

var jersey_viewport: SubViewport = null
var jersey_decal: JerseyDecal = null
var shoulder_viewport: SubViewport = null
var shoulder_decal: ShoulderDecal = null

var _rig: Node3D = null
# The figure's pose, as drape() last had it, and the tuck the torso was last
# draped for — the drape is baked, not stepped, so it is rebuilt only when
# either moves.
var _drape_pose: Array[Transform3D] = []
var _draped_tuck: int = -1


# Every part under `rig`; the decal viewports under `viewport_host`.
func build(rig: Node3D, viewport_host: Node) -> void:
	_rig = rig
	torso = _part(SkaterMeshBuilder.shared_torso())
	pelvis = _part(SkaterMeshBuilder.shared_pelvis())
	helmet = _part(SkaterMeshBuilder.shared_helmet_assembly())
	face = MeshInstance3D.new()
	helmet.add_child(face)
	scalp = MeshInstance3D.new()
	helmet.add_child(scalp)
	facial_hair = MeshInstance3D.new()
	helmet.add_child(facial_hair)
	brows = MeshInstance3D.new()
	brows.mesh = SkaterHairMesh.shared_brows()
	helmet.add_child(brows)
	for i: int in 2:
		shoulders.append(_part(SkaterMeshBuilder.shared_shoulder_cap()))
		# The thigh carries the hip joint's own dome; the knee ball closes the
		# other end, where the thigh would otherwise stop short of the sock.
		thighs.append(_part(SkaterMeshBuilder.shared_thigh()))
		knees.append(_part(SkaterMeshBuilder.shared_knee_ball()))
		socks.append(_part(SkaterMeshBuilder.shared_sock()))
		collars.append(_part(SkaterMeshBuilder.shared_skate_assembly()))
		boots.append(_part(SkaterMeshBuilder.shared_boot_assembly()))
		upper_arms.append(_part(SkaterMeshBuilder.shared_arm_bone()))
		forearms.append(_part(SkaterMeshBuilder.shared_forearm_bone()))
		elbows.append(_part(SkaterMeshBuilder.shared_elbow_pad()))
		hands.append(_part(SkaterMeshBuilder.shared_glove_fist()))
		cuffs.append(_part(SkaterMeshBuilder.shared_cuff()))

	jersey_decal = JerseyDecal.new()
	jersey_viewport = _decal_viewport(viewport_host, jersey_decal,
			Vector2i(JerseyDecal.IMG_W, JerseyDecal.IMG_H))
	torso.set_surface_override_material(0,
			JerseyDecal.torso_material(jersey_viewport.get_texture()))
	shoulder_decal = ShoulderDecal.new()
	shoulder_viewport = _decal_viewport(viewport_host, shoulder_decal, shoulder_decal.size)
	for i: int in 2:
		shoulders[i].set_surface_override_material(0, ShoulderDecal.part_material(
				shoulder_viewport.get_texture(), -1.0 if i == 0 else 1.0))
	_build_stick()


# Where the posed figure's torso, pants and legs are (each leg as its frame at
# the hip, scaled by its bulk), for the jersey's tail to drape over; the next
# dress() bakes it.
func drape(torso_xf: Transform3D, pelvis_xf: Transform3D, legs: Array[Transform3D]) -> void:
	var pose: Array[Transform3D] = [torso_xf, pelvis_xf, legs[0], legs[1]]
	if pose != _drape_pose:
		_drape_pose = pose
		_draped_tuck = -1


# Paints every part. After the pose: the shaft's grip wrap is laid along the
# length the pose gave it, and the jersey drapes over the legs it gave.
func dress(colors: Dictionary, gear: GearStyleConfig, tape: StickTapeConfig,
		skin_tone: int, player_name: String, jersey_number: int) -> void:
	_paint_body(colors, skin_tone, player_name, jersey_number)
	_paint_gear(gear, colors)
	_paint_stick(gear, tape, colors)


func _part(mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	_rig.add_child(mi)
	return mi


static func _decal_viewport(host: Node, decal: Node2D, size: Vector2i) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = false
	vp.disable_3d = true
	vp.handle_input_locally = false
	vp.gui_disable_input = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	host.add_child(vp)
	vp.add_child(decal)
	return vp


func _build_stick() -> void:
	stick_root = Node3D.new()
	_rig.add_child(stick_root)

	shaft = MeshInstance3D.new()
	var shaft_box := BoxMesh.new()
	shaft_box.size = Vector3(_SHAFT_CROSS.x, _SHAFT_CROSS.y, 1.0)
	shaft.mesh = shaft_box
	shaft_mat = StickStyle.make_shaft_material()
	shaft.material_override = shaft_mat
	stick_root.add_child(shaft)

	blade = MeshInstance3D.new()
	blade.material_override = StickStyle.make_blade_material()
	stick_root.add_child(blade)

	tape_mesh = MeshInstance3D.new()
	blade.add_child(tape_mesh)

	knob = MeshInstance3D.new()
	var knob_cyl := CylinderMesh.new()
	knob_cyl.top_radius = 0.035
	knob_cyl.bottom_radius = 0.03
	knob_cyl.height = KNOB_HEIGHT_M
	knob_cyl.radial_segments = 12
	knob.mesh = knob_cyl
	stick_root.add_child(knob)


# ── Paint ────────────────────────────────────────────────────────────────────

# The kit, not flat team colors: the sweater through the rink's own decals,
# striped socks, solid pants. Sock stripes come from the painter the rink uses,
# so the bands land where the in-game skater's do.
func _paint_body(colors: Dictionary, skin_tone: int, player_name: String,
		jersey_number: int) -> void:
	var uniform: Dictionary = colors.uniform
	var jersey: Dictionary = uniform.jersey
	var sock_block: Dictionary = uniform.socks

	var preset: Dictionary = colors.get("preset", {})
	jersey_decal.update_crest(TeamCrest.fruit_for(preset), preset)
	jersey_decal.update_jersey(jersey.base, UniformPaint.yoke_color(jersey),
			UniformPaint.collar_color(jersey), jersey.stripes, player_name, jersey_number,
			colors.text, uniform.text.stroke)
	jersey_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	shoulder_decal.update_shoulder(uniform.shoulders.color, UniformPaint.yoke_color(jersey),
			jersey_number, uniform.shoulders.text, uniform.shoulders.stroke)
	shoulder_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_paint(pelvis, 0, uniform.pants.base, UniformPaint.ROUGH_NYLON)
	_paint(helmet, SkaterMeshBuilder.HELMET_SURF_SHELL, uniform.helmet, _HELMET_ROUGH)
	_paint(helmet, SkaterMeshBuilder.HELMET_SURF_SKIN,
			SkinToneRegistry.color_for(skin_tone), _CLOTH_ROUGH)

	var sock_tex: ImageTexture = null
	if not sock_block.stripes.is_empty():
		sock_tex = UniformPaint.h_stripes(sock_block.base, sock_block.stripes)
	var sleeve: Color = uniform.arms.upper.base
	# One-color sleeves here, so an unnamed elbow is the sleeve too.
	var elbow: Color = uniform.arms.elbow if uniform.arms.get("elbow") is Color else sleeve
	for i: int in 2:
		_paint(thighs[i], 0, uniform.pants.base, UniformPaint.ROUGH_NYLON)
		# Below the pant hem the knee is sock, solid base as on the rink.
		_paint(knees[i], 0, sock_block.base, _CLOTH_ROUGH)
		if sock_tex != null:
			_paint_texture(socks[i], 0, sock_tex, _CLOTH_ROUGH)
		else:
			_paint(socks[i], 0, sock_block.base, _CLOTH_ROUGH)
		_paint(upper_arms[i], 0, sleeve, _CLOTH_ROUGH)
		_paint(forearms[i], 0, sleeve, _CLOTH_ROUGH)
		_paint(elbows[i], 0, elbow, _CLOTH_ROUGH)


# The four gear picks, painted onto the pieces that wear them. A model paints
# every zone of its piece at once, against this kit's colors.
func _paint_gear(gear: GearStyleConfig, colors: Dictionary) -> void:
	# The tuck is the torso's shape and the pants' pad; the torso's one surface
	# keeps the sweater's paint.
	pelvis.mesh = SkaterMeshBuilder.shared_pelvis(gear.jersey_tuck)
	if _drape_pose.is_empty():
		torso.mesh = SkaterMeshBuilder.shared_torso(gear.jersey_tuck)
	elif gear.jersey_tuck != _draped_tuck:
		var legs: Array[Transform3D] = [_drape_pose[2], _drape_pose[3]]
		torso.mesh = SkaterHemFlaps.baked_torso(gear.jersey_tuck, _drape_pose[0],
				_drape_pose[1], legs)
		_draped_tuck = gear.jersey_tuck
	var team: Color = colors.primary
	var accent: Color = colors.secondary
	var light: Color = colors.light
	var quarter: Color = GearModelRegistry.skate_color(
			gear.skate_model, GearModelRegistry.SKATE_QUARTER, team, accent, light)
	var toe: Color = GearModelRegistry.skate_color(
			gear.skate_model, GearModelRegistry.SKATE_TOE, team, accent, light)
	var holder: Color = GearModelRegistry.skate_color(
			gear.skate_model, GearModelRegistry.SKATE_HOLDER, team, accent, light)
	var collar: Color = GearModelRegistry.skate_color(
			gear.skate_model, GearModelRegistry.SKATE_COLLAR, team, accent, light)
	var stripe: Color = GearModelRegistry.skate_color(
			gear.skate_model, GearModelRegistry.SKATE_STRIPE, team, accent, light)
	var lace: Color = TapeColorRegistry.resolve(gear.lace_color, team)

	var glove_kit: Color = colors.gloves
	var glove_accent: Color = colors.glove_accent
	var body: Color = GearModelRegistry.glove_color(
			gear.glove_model, GearModelRegistry.GLOVE_BODY, glove_kit, glove_accent, light)
	var fingers: Color = GearModelRegistry.glove_color(
			gear.glove_model, GearModelRegistry.GLOVE_FINGERS, glove_kit, glove_accent, light)
	var cuff: Color = GearModelRegistry.glove_color(
			gear.glove_model, GearModelRegistry.GLOVE_CUFF, glove_kit, glove_accent, light)

	for i: int in 2:
		_paint(boots[i], SkaterMeshBuilder.BOOT_SURF_SHELL, quarter, _LEATHER_ROUGH)
		_paint(boots[i], SkaterMeshBuilder.BOOT_SURF_TOE, toe, _LEATHER_ROUGH)
		_paint(boots[i], SkaterMeshBuilder.BOOT_SURF_HOLDER, holder, _LEATHER_ROUGH)
		# The steel runner is never a model zone — it is a few millimetres of
		# silhouette under the holder's rail, not a design surface.
		_paint(boots[i], SkaterMeshBuilder.BOOT_SURF_RUNNER,
				SkaterMeshBuilder.BLADE_STEEL_COLOR, _STEEL_ROUGH)
		_paint(boots[i], SkaterMeshBuilder.BOOT_SURF_LACES, lace, _CLOTH_ROUGH)
		_paint(collars[i], SkaterMeshBuilder.SKATE_SURF_COLLAR, collar, _LEATHER_ROUGH)
		_paint(collars[i], SkaterMeshBuilder.SKATE_SURF_STRIPE, stripe, _LEATHER_ROUGH)
		_paint(hands[i], SkaterMeshBuilder.FIST_PART_BACK, body, UniformPaint.ROUGH_GLOVE)
		_paint(hands[i], SkaterMeshBuilder.FIST_PART_FINGERS, fingers, UniformPaint.ROUGH_GLOVE)
		_paint(cuffs[i], 0, cuff, UniformPaint.ROUGH_GLOVE)

	# Face gear is a fixed look with no kit zones — the rink's own mesh and
	# material, and a null mesh for bare.
	face.mesh = SkaterMeshBuilder.shared_face_gear(gear.helmet_face)
	face.material_override = SkaterMeshBuilder.make_face_gear_material(gear.helmet_face)
	scalp.mesh = SkaterHairMesh.shared_hair(gear.hair_style)
	scalp.material_override = SkaterHairMesh.make_material(gear.hair_color,
			SkaterHairMesh.is_scalp_translucent(gear.hair_style))
	facial_hair.mesh = SkaterHairMesh.shared_facial_hair(gear.facial_hair, gear.helmet_face)
	facial_hair.material_override = SkaterHairMesh.make_material(gear.hair_color,
			SkaterHairMesh.is_translucent(gear.facial_hair))
	brows.material_override = SkaterHairMesh.make_material(gear.hair_color, false)


func _paint_stick(gear: GearStyleConfig, tape: StickTapeConfig,
		colors: Dictionary) -> void:
	var accent: Color = colors.primary
	# Fresh materials from the same factories the rink uses, so the figure's
	# stick IS the in-game stick. The shaft material comes back with default
	# uniforms, so the pose's shaft length has to be re-sent after it.
	shaft_mat = StickStyle.make_shaft_material(gear.stick_model)
	shaft.material_override = shaft_mat
	blade.material_override = StickStyle.make_blade_material(gear.stick_model)

	var knob_color: Color = TapeColorRegistry.resolve(tape.knob_color, accent)
	shaft_mat.set_shader_parameter(&"grip_mode", tape.knob_style)
	shaft_mat.set_shader_parameter(&"grip_color", knob_color)
	shaft_mat.set_shader_parameter(&"shaft_len_m",
			shaft.transform.basis.get_scale().z)
	tape_mesh.material_override = _flat(
			TapeColorRegistry.resolve(tape.blade_color, accent), _CLOTH_ROUGH)
	knob.material_override = _flat(knob_color, _CLOTH_ROUGH)


# Per-instance paint for one surface. Goes through surface_override so the
# shared default's finish (the steel, the laces, the body rim) is duplicated
# rather than discarded — the merged assemblies must never take a
# material_override, which would flatten every one of their surfaces into one.
func _paint(mi: MeshInstance3D, surface: int, color: Color, roughness: float) -> void:
	var mat: StandardMaterial3D = SkaterMeshBuilder.surface_override(mi, surface)
	mat.albedo_color = color
	mat.albedo_texture = null
	mat.roughness = roughness
	BodyRim.apply(mat)


func _paint_texture(mi: MeshInstance3D, surface: int, tex: Texture2D,
		roughness: float) -> void:
	var mat: StandardMaterial3D = SkaterMeshBuilder.surface_override(mi, surface)
	mat.albedo_color = Color.WHITE
	mat.albedo_texture = tex
	mat.roughness = roughness
	BodyRim.apply(mat)


# Plain material for the stick's non-body pieces (tape, knob) — no body rim:
# they are equipment in the hand, not skin or cloth on the silhouette.
static func _flat(color: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	return mat
