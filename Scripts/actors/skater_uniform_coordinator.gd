class_name SkaterUniformCoordinator
extends RefCounted

# Paints the skater from a v2 colors dict (see TeamColorRegistry.get_colors):
# the body's zones through SkaterKitPaint, and what only the rink's skater
# carries — the stick's shaft, blade, tape and knob, the head pieces, the
# ghost fade. Two entry points:
#
#   apply_uniform(colors)        — the kit and the gear it resolves against
#   apply_jersey_info(name, num) — name + number; re-renders the decals

# Stick-flex vertex shader — the shaft's per-skater ShaderMaterial wraps it
# (see _make_stick_shaft_mat); Skater drives the flex_m uniform per frame.
# (Stick surface design — shaft paint/wordmark, blade weave — lives in
# StickStyle; this coordinator layers the player's tape job on top.)

var _skater: Skater
var _kit: SkaterKitPaint
var _blade_mesh: MeshInstance3D
var _blade_tape: MeshInstance3D                    # team-colored tape band, child of _blade_mesh
# colors.primary, cached from the last apply_uniform so a live tape pick
# repaints without one: TEAM for tape.
var _team_accent: Color = Color.WHITE
# Whether the skater is currently ghost-faded — read by the face-gear repaint,
# whose design alpha is not 1.0 and so can't be restored by _fade_material.
var _ghosted: bool = false


func setup(skater: Skater, paint: BodyZonePaint) -> void:
	_skater = skater
	_blade_mesh = skater.blade.get_node("MeshInstance3D") as MeshInstance3D
	_kit = SkaterKitPaint.new(paint, skater)


func apply_uniform(colors: Dictionary) -> void:
	_team_accent = colors.primary
	_kit.apply_uniform(colors)
	_kit.apply_gear(_skater.gear_style)
	_resize_cuffs()
	_rebuild_blade()
	# Stick shaft — near-black composite, satin finish, on the flex vertex
	# shader (Shaders/stick_flex.gdshader). A ShaderMaterial PER SKATER, so
	# one player's shot doesn't bend every stick on the ice;
	# Skater._update_stick_flex drives its flex_m uniform at render rate.
	# Ghost mode swaps this override for a translucent standard mat and
	# rebuilds it on un-ghost — see apply_ghost's stick special case.
	_skater.stick_mesh.material_override = _make_stick_shaft_mat()
	# Butt-end knob — recreated here so the tape color tracks the kit.
	_rebuild_stick_knob()
	# Face gear and hair — fixed looks, no kit resolution; painted with the
	# uniform so a piece equipped before the first uniform pass isn't left
	# unpainted.
	_repaint_head_pieces()


func apply_jersey_info(p_name: String, number: int) -> void:
	_kit.set_jersey_info(p_name, number)


func set_skin_tone(index: int) -> void:
	_kit.set_skin_tone(index)


# The cuff rings stay proud of the forearm they wrap, scaled by the Hands
# forearm bulk (see Skater.forearm_visual_mult).
func _resize_cuffs() -> void:
	var cuff_radius: float = _skater.arm_mesh_thickness * 0.6 * _skater.forearm_visual_mult
	_skater.set_arm_cuff_radius(SkaterMeshBuilder.UpperBone.TOP_CUFF, cuff_radius)
	_skater.set_arm_cuff_radius(SkaterMeshBuilder.UpperBone.BOTTOM_CUFF, cuff_radius)


func _make_stick_shaft_mat() -> ShaderMaterial:
	# StickStyle owns the design (the picked model's paint + wordmark); the
	# grip wrap is the player's tape job, layered here.
	var mat: ShaderMaterial = StickStyle.make_shaft_material(
			_skater.gear_style.stick_model)
	_write_grip_uniforms(mat)
	# Fresh material, default uniforms — the skater's dirty guards must
	# forget their last-written flex/length or they never re-send.
	_skater.notify_shaft_material_rebuilt()
	return mat


# The handle wrap (candy-cane / full grip) is painted by the flex shader from
# the tape job; the wrap color is the knob palette pick.
func _write_grip_uniforms(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter(&"grip_mode", _skater.tape_config.knob_style)
	mat.set_shader_parameter(&"grip_color",
			TapeColorRegistry.resolve(_skater.tape_config.knob_color, _team_accent))


# Dresses the blade in the picked model's weave and (re)builds the tape wrap
# the skater's tape job describes (Skater.tape_config: palette color +
# coverage span). The wrap geometry comes from the skater
# (Skater.build_blade_tape_mesh — overlapping wrap bands of the same
# procedural curved-blade mesh), so it hugs the curve; on a handedness flip
# Skater._rebuild_blade_mesh regenerates the band mesh in place. The cosmetic
# tilt lives on the rig (Skater._apply_blade_tilt); the tape, being a child
# of the blade mesh, inherits it.
func _rebuild_blade() -> void:
	_blade_mesh.material_override = StickStyle.make_blade_material(
			_skater.gear_style.stick_model)

	if _blade_tape != null and is_instance_valid(_blade_tape):
		_blade_mesh.remove_child(_blade_tape)
		_blade_tape.queue_free()
	_blade_tape = null
	var tape_mesh: ArrayMesh = _skater.build_blade_tape_mesh()
	if tape_mesh == null:
		return  # bare blade — no tape node at all
	_blade_tape = MeshInstance3D.new()
	_blade_tape.name = "BladeTape"
	_blade_tape.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_blade_tape.mesh = tape_mesh
	_blade_tape.material_override = UniformPaint.solid(
			TapeColorRegistry.resolve(_skater.tape_config.blade_color, _team_accent),
			UniformPaint.ROUGH_CLOTH)
	_blade_mesh.add_child(_blade_tape)


# Repaints the gear-style pieces (both skates, both gloves, the laces, the
# stick's colorway) for a live model or lace change without touching the rest
# of the uniform. Same live-cosmetic contract as refresh_tape below — the
# stick rebuild skips the ghost window (a translucent standard mat holds the
# override there; un-ghost rebuilds from the live config anyway).
func refresh_gear_style() -> void:
	_kit.apply_gear(_skater.gear_style)
	_resize_cuffs()
	_repaint_head_pieces()
	if _skater.stick_mesh.material_override is ShaderMaterial:
		_skater.stick_mesh.material_override = _make_stick_shaft_mat()
		_rebuild_blade()


# Re-renders the tape-colored pieces (blade wrap, knob, handle-wrap paint) for
# a live tape-job change without touching the rest of the uniform. Safe before
# the first apply_uniform — the accent default just gets repainted when it
# lands. The shaft write skips the ghost window (a plain translucent standard
# mat holds the override there); un-ghost rebuilds the shader mat from the
# live config anyway.
func refresh_tape() -> void:
	_rebuild_blade()
	_rebuild_stick_knob()
	var shaft_mat: ShaderMaterial = _skater.stick_mesh.material_override as ShaderMaterial
	if shaft_mat != null:
		_write_grip_uniforms(shaft_mat)


# (Re)builds the butt-end knob cylinder, stored on the skater so update_stick_mesh
# rides it on the shaft each tick. Recreated per uniform so the knob's tape color
# tracks kit changes — same pattern as the glove cuffs.
func _rebuild_stick_knob() -> void:
	var color: Color = TapeColorRegistry.resolve(
			_skater.tape_config.knob_color, _team_accent)
	if _skater.stick_knob_mesh != null and is_instance_valid(_skater.stick_knob_mesh):
		_skater.upper_body.remove_child(_skater.stick_knob_mesh)
		_skater.stick_knob_mesh.queue_free()
	_skater.stick_knob_mesh = null
	var m := MeshInstance3D.new()
	m.name = "StickKnob"
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Posed on the shaft, which is drawn uninterpolated (SkaterStickRig.setup).
	m.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	m.mesh = SkaterMeshBuilder.shared_knob()
	m.material_override = UniformPaint.solid(color, UniformPaint.ROUGH_CLOTH)
	_skater.stick_knob_mesh = m
	_skater.upper_body.add_child(m)


# The head pieces fade with the body, but the face shields and stubble have a
# DESIGN alpha below 1.0, so they cannot ride the generic _fade_material
# restore — each material is rebuilt from its factory (with the geometry; these
# looks are kit-free) instead, with the ghost factor layered on top. Called from
# the uniform pass, the live gear refresh and apply_ghost, so a pick changed
# mid-ghost stays faded.
func _repaint_head_pieces() -> void:
	var gear: GearStyleConfig = _skater.gear_style
	_paint_head_piece(SkaterArmRig.HeadPiece.FACE_GEAR,
			SkaterMeshBuilder.make_face_gear_material(gear.helmet_face))
	_paint_head_piece(SkaterArmRig.HeadPiece.SCALP, SkaterHairMesh.make_material(
			gear.hair_color, SkaterHairMesh.is_scalp_translucent(gear.hair_style)))
	_paint_head_piece(SkaterArmRig.HeadPiece.FACIAL_HAIR, SkaterHairMesh.make_material(
			gear.hair_color, SkaterHairMesh.is_translucent(gear.facial_hair)))
	_paint_head_piece(SkaterArmRig.HeadPiece.BROWS,
			SkaterHairMesh.make_material(gear.hair_color, false))


func _paint_head_piece(piece: SkaterArmRig.HeadPiece, mat: StandardMaterial3D) -> void:
	var node: MeshInstance3D = _skater.head_piece(piece)
	if node == null or node.mesh == null:
		return
	if _ghosted:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color.a *= 0.3
	node.material_override = mat


func apply_ghost(ghost: bool) -> void:
	# Head pieces first (some transparent by design — see _repaint_head_pieces).
	_ghosted = ghost
	_repaint_head_pieces()
	# The stick shaft and blade are handled apart from the loop: their
	# overrides are ShaderMaterials (flex/brand, carbon weave), which the
	# StandardMaterial3D cast below can't see — the loop would replace them
	# with a default (WHITE) material and the un-ghost pass would then restore
	# that white mat to full alpha, leaving the stick white forever after the
	# first offside. Swap in colored translucent standard mats while ghosted
	# (the flex driver no-ops on a non-ShaderMaterial override by design) and
	# rebuild the real design materials on un-ghost.
	if ghost:
		var model: int = _skater.gear_style.stick_model
		var stick_ghost: StandardMaterial3D = UniformPaint.solid(
				StickModelRegistry.shaft_color(model), StickStyle.SHAFT_ROUGHNESS)
		stick_ghost.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		stick_ghost.albedo_color.a = 0.3
		_skater.stick_mesh.material_override = stick_ghost
		var blade_ghost: StandardMaterial3D = UniformPaint.solid(
				StickModelRegistry.blade_base_color(model), 0.5)
		blade_ghost.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		blade_ghost.albedo_color.a = 0.3
		_blade_mesh.material_override = blade_ghost
	else:
		_skater.stick_mesh.material_override = _make_stick_shaft_mat()
		_blade_mesh.material_override = StickStyle.make_blade_material(
				_skater.gear_style.stick_model)
	var meshes: Array[MeshInstance3D] = [
			_blade_tape,
			_skater.stick_knob_mesh,
		]
	for mesh: MeshInstance3D in meshes:
		if mesh == null:
			continue
		var mat: StandardMaterial3D = mesh.material_override as StandardMaterial3D
		if mat == null:
			mat = StandardMaterial3D.new()
			mesh.material_override = mat
		_fade_material(mat, ghost)
	# The body itself fades as one material, in Skater.set_ghost.


func _fade_material(mat: StandardMaterial3D, ghost: bool) -> void:
	if ghost:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color.a = 0.3
	else:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		mat.albedo_color.a = 1.0
