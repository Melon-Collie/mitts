class_name SkaterUniformCoordinator
extends RefCounted

# Paints the full skater uniform from a v2 colors dict (see
# TeamColorRegistry.get_colors). Two entry points:
#
#   apply_uniform(colors)        — colors, stripes, text colors, blade
#   apply_jersey_info(name, num) — name + number; re-renders decals
#                                  using cached text colors from apply_uniform
#
# Painting paths:
#   - Torso  → SubViewport + JerseyDecal (base + collar + yoke + stripe array
#     + name/number text + the team's chest crest). One viewport per skater.
#   - Shoulders → shared SubViewport + ShoulderDecal (the yoke over the top,
#     the shoulder color below, its own text color/outline).
#   - Forearm / upper arm / socks → ImageTexture with horizontal bands stacked
#     in array order; widths shrink to form concentric "centered cross-section"
#     bands (watermelon rind, lime pith).
#   - Pants thighs → ImageTexture with vertical columns positioned by stripe.pos
#     (kept as a vertical side stripe, not a horizontal band — pants are the
#     one region whose stripe.pos refers to U, not V).
#   - Helmet / gloves / cuffs / elbow / hand spheres / hips / knees (sock base) /
#     skates → solid materials.

# Stick-flex vertex shader — the shaft's per-skater ShaderMaterial wraps it
# (see _make_stick_shaft_mat); Skater drives the flex_m uniform per frame.
# (Stick surface design — shaft paint/wordmark, blade weave — lives in
# StickStyle; this coordinator layers the player's tape job on top.)

var _skater: Skater
var _blade_mesh: MeshInstance3D
var _blade_tape: MeshInstance3D                    # team-colored tape band, child of _blade_mesh

# Cached jersey + shoulder decal inputs. Both decals are repainted whenever
# either the uniform (apply_uniform) or the name/number (apply_jersey_info)
# changes; the cache lets each entry point trigger a refresh without re-
# supplying the other side's data.
var _jersey_base_color: Color = Color.WHITE
var _jersey_yoke_color: Color = Color.WHITE
var _jersey_collar_color: Color = Color.WHITE
var _jersey_stripes: Array[Dictionary] = []
var _shoulder_color: Color = Color.WHITE
var _shoulder_text_color: Color = Color.BLACK
var _player_name: String = ""
var _jersey_number: int = 0
var _text_color: Color = Color.BLACK
# The kit colors a gear model or tape pick resolves against, cached from the
# last apply_uniform so a live cosmetic change repaints without one.
# _team_accent is colors.primary (TEAM for tape and skates), _kit_gloves is
# uniform.gloves (TEAM for gloves), and _team_light is the kit's own white —
# CREAM for some teams, so gear matches the sweater rather than out-whiting it.
# The models' ACCENT slot reads _team_secondary on skates but _glove_accent on
# gloves: most presets dress their gloves in the secondary already, so the
# glove's second color has to be the one it is NOT (TeamColorRegistry derives
# it).
var _team_accent: Color = Color.WHITE
var _kit_gloves: Color = Color.BLACK
var _team_secondary: Color = Color.WHITE
var _glove_accent: Color = Color.WHITE
var _team_light: Color = Color.WHITE
var _jersey_viewport: SubViewport
var _jersey_decal: JerseyDecal
var _shoulder_viewport: SubViewport
var _shoulder_decal: ShoulderDecal
# Whether the skater is currently ghost-faded — read by the face-gear repaint,
# whose design alpha is not 1.0 and so can't be restored by _fade_material.
var _ghosted: bool = false


func setup(skater: Skater) -> void:
	_skater = skater
	_blade_mesh = skater.blade.get_node("MeshInstance3D") as MeshInstance3D
	# The body is painted per LegSurface / UpperSurface through the skater's
	# surface seams; each is a zone of the body's one material (BodyZonePaint),
	# which holds at most BodyZonePaint.MAX_TEXTURES textures — so a pattern both
	# sides wear is built once and handed to both.
	_create_jersey_viewport()
	_create_shoulder_viewport()


# Spawns the SubViewport + JerseyDecal that renders the procedural jersey
# texture, and points the torso material at the viewport's texture. The
# albedo material is created once here so apply_uniform / apply_jersey_info
# can refresh the texture without recreating the material (which would lose
# ghost-mode transparency state). Same pattern as the rink's center-ice
# decal viewport.
func _create_jersey_viewport() -> void:
	_jersey_viewport = SubViewport.new()
	_jersey_viewport.name = "JerseyViewport"
	_jersey_viewport.size = Vector2i(JerseyDecal.IMG_W, JerseyDecal.IMG_H)
	_jersey_viewport.transparent_bg = false
	_jersey_viewport.disable_3d = true
	_jersey_viewport.handle_input_locally = false
	_jersey_viewport.gui_disable_input = true
	_jersey_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_skater.add_child(_jersey_viewport)

	_jersey_decal = JerseyDecal.new()
	_jersey_decal.name = "JerseyDecal"
	_jersey_viewport.add_child(_jersey_decal)

	_skater.set_upper_surface_material(SkaterMeshBuilder.UpperSurface.TORSO,
			JerseyDecal.torso_material(_jersey_viewport.get_texture()))


# Shared SubViewport + ShoulderDecal for both shoulder spheres, each turned to
# face the number outward (ShoulderDecal.part_material).
func _create_shoulder_viewport() -> void:
	_shoulder_decal = ShoulderDecal.new()
	_shoulder_decal.name = "ShoulderDecal"
	_shoulder_viewport = SubViewport.new()
	_shoulder_viewport.name = "ShoulderViewport"
	_shoulder_viewport.size = _shoulder_decal.size
	_shoulder_viewport.transparent_bg = false
	_shoulder_viewport.disable_3d = true
	_shoulder_viewport.handle_input_locally = false
	_shoulder_viewport.gui_disable_input = true
	_shoulder_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_skater.add_child(_shoulder_viewport)
	_shoulder_viewport.add_child(_shoulder_decal)

	var tex: ViewportTexture = _shoulder_viewport.get_texture()
	_skater.set_upper_surface_material(SkaterMeshBuilder.UpperSurface.SHOULDER_L,
			ShoulderDecal.part_material(tex, -1.0))
	_skater.set_upper_surface_material(SkaterMeshBuilder.UpperSurface.SHOULDER_R,
			ShoulderDecal.part_material(tex, 1.0))


# Applies the full v2 colors dict (TeamColorRegistry.get_colors output) to
# every uniform mesh. Reads colors.uniform for kit detail and colors.primary
# for the stick blade; text colors come from colors.text/.text_outline.
func apply_uniform(colors: Dictionary) -> void:
	# Sweep legacy mesh-based stripes from older builds (if a saved scene
	# happens to carry them) so they don't double up with the texture paint.
	for node: Node in _skater.upper_body.get_children():
		if node.name.begins_with("Stripe_"):
			_skater.upper_body.remove_child(node)
			node.queue_free()
	for node: Node in _skater.lower_body.get_children():
		if node.name.begins_with("Stripe_"):
			_skater.lower_body.remove_child(node)
			node.queue_free()

	var uniform: Dictionary = colors.uniform
	_text_color = colors.text

	# Jersey torso (decal repaint).
	_jersey_base_color = uniform.jersey.base
	_jersey_yoke_color = UniformPaint.yoke_color(uniform.jersey)
	_jersey_collar_color = UniformPaint.collar_color(uniform.jersey)
	_jersey_stripes = uniform.jersey.stripes
	if _jersey_decal != null:
		var preset: Dictionary = colors.get("preset", {})
		_jersey_decal.update_crest(TeamCrest.fruit_for(preset), preset)
	_rebuild_jersey_texture()

	# Shoulder caps (decal repaint with shoulder-specific color + text).
	_shoulder_color = uniform.shoulders.color
	_shoulder_text_color = uniform.shoulders.text
	_rebuild_shoulder_texture()

	# Helmet — glossy hard plastic.
	# Shell only — the head/neck skin is its own surface of the same bone.
	_skater.set_upper_surface_material(SkaterMeshBuilder.UpperSurface.HELMET_SHELL,
			UniformPaint.solid(uniform.helmet, UniformPaint.ROUGH_HELMET))

	# Blade — matte black with the player's tape job riding it (palette picks
	# resolve against colors.primary, so TEAM picks track the kit).
	_team_accent = colors.primary
	_team_secondary = colors.secondary
	_glove_accent = colors.glove_accent
	_team_light = colors.light
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

	# Gloves: the gear style's glove MODEL paints the back of the hand, the
	# fingers and the wrist cuff rings, each from black / white / the kit's own
	# glove color.
	_kit_gloves = uniform.gloves
	_repaint_gloves()

	# Arms — upper + lower bone cylinders, each painted with horizontal
	# stripes (or solid if the stripes array is empty).
	_paint_sleeves(SkaterMeshBuilder.UpperBone.TOP_UPPER_ARM,
			SkaterMeshBuilder.UpperBone.BOTTOM_UPPER_ARM, uniform.arms.upper)
	_paint_sleeves(SkaterMeshBuilder.UpperBone.TOP_FOREARM,
			SkaterMeshBuilder.UpperBone.BOTTOM_FOREARM, uniform.arms.lower)

	var elbow_mat: StandardMaterial3D = UniformPaint.solid(elbow_color(uniform.arms))
	_skater.set_upper_surface_material(SkaterMeshBuilder.UpperBone.TOP_ELBOW, elbow_mat)
	_skater.set_upper_surface_material(
			SkaterMeshBuilder.UpperBone.BOTTOM_ELBOW, elbow_mat.duplicate())

	# Pants — vertical side stripes (pants stripe pos is U, width is column
	# thickness; see make_pants_stripes_texture). The thigh carries the hip joint's
	# dome now, so its stripe runs up over the hip the way a real pant's does.
	var pants_block: Dictionary = uniform.pants
	_paint_pants_thighs(pants_block)
	# The pelvis rides the UPPER mesh (it must not fold with the torso, and it
	# must not swing with a leg either) but it is pants, not jersey.
	_skater.set_upper_surface_material(SkaterMeshBuilder.UpperSurface.PELVIS,
			UniformPaint.solid(pants_block.base, UniformPaint.ROUGH_NYLON))

	# Socks — horizontal stripes on the cylinder side.
	var sock_mat: StandardMaterial3D = _socks_material(uniform.socks)
	_skater.set_leg_surface_material(SkaterMeshBuilder.LegSurface.SOCK_L, sock_mat)
	_skater.set_leg_surface_material(
			SkaterMeshBuilder.LegSurface.SOCK_R, sock_mat.duplicate())
	# The knee ball sits below the pant hem, over the shin guard's cap, so it is
	# sock: solid base, which every kit's sock top already is
	# (test_knee_wears_the_sock.gd).
	var knee_mat: StandardMaterial3D = UniformPaint.solid(uniform.socks.base)
	_skater.set_leg_surface_material(SkaterMeshBuilder.LegSurface.KNEE_L, knee_mat)
	_skater.set_leg_surface_material(
			SkaterMeshBuilder.LegSurface.KNEE_R, knee_mat.duplicate())

	# Skates — the gear style's skate MODEL paints the boot quarter, the toe
	# cap, the ankle collar, the band ringing it and the blade holder. Painted
	# unconditionally (not only when a model asks for color) so ghost mode never
	# leaves a blank gray override behind. The steel runner is not a zone: it
	# keeps the default steel the mesh ships with.
	_repaint_skates()
	_repaint_laces()


# Repaints the jersey + shoulder decals with the new name/number using the
# text colors cached from the last apply_uniform.
func apply_jersey_info(p_name: String, number: int) -> void:
	# Clean up legacy floating decal meshes from older box-geometry builds.
	for child: Node in _skater.upper_body.get_children():
		if child.name in ["JerseyBackMesh", "JerseyShoulderL", "JerseyShoulderR"]:
			_skater.upper_body.remove_child(child)
			child.queue_free()
	_player_name = p_name
	_jersey_number = number
	_rebuild_jersey_texture()
	_rebuild_shoulder_texture()


func _rebuild_jersey_texture() -> void:
	if _jersey_decal == null:
		return
	_jersey_decal.update_jersey(
			_jersey_base_color, _jersey_yoke_color, _jersey_collar_color, _jersey_stripes,
			_player_name, _jersey_number, _text_color)
	_jersey_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _rebuild_shoulder_texture() -> void:
	if _shoulder_decal == null:
		return
	_shoulder_decal.update_shoulder(
			_shoulder_color, _jersey_yoke_color, _jersey_number, _shoulder_text_color)
	_shoulder_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


# Arm-vs-sock stripe scale. A stripe's `width` is a fraction of the cylinder's
# own side length (see UniformPaint.h_stripes), and jerseys author arms and
# socks with the SAME fractions (data/team_colors.json — Dragonfruit/Blueberry
# use identical arrays). But the arm bones render longer than the socks: the
# forearm/upper-arm design length is 0.35 m (Skater.forearm_length /
# upper_arm_length) against the sock cylinder's 0.30 m height (SockL/R in
# Skater.tscn). Both scale together with Size (m_height), so the ratio is fixed.
# Without correction the identical fraction paints a physically taller band on
# the thinner arm — the "arm stripes are too big" mismatch. Shrink the arm
# pattern about its center by the length ratio so an authored width renders at
# the same physical band height on arms as on socks.
const _FOREARM_DESIGN_LEN: float = 0.33   # Skater.forearm_length / upper_arm_length default
const _SOCK_DESIGN_LEN: float = 0.30      # SockL/R CylinderMesh height (Skater.tscn)
const _ARM_STRIPE_SCALE: float = _SOCK_DESIGN_LEN / _FOREARM_DESIGN_LEN


# Paints a pair of bone cylinders (both upper arms, or both forearms) with
# horizontal stripes, or solid when the segment has none.
func _paint_sleeves(top: int, bottom: int, segment: Dictionary) -> void:
	var mat: StandardMaterial3D
	if segment.stripes.is_empty():
		mat = UniformPaint.solid(segment.base)
	else:
		mat = UniformPaint.textured(make_arm_stripes_texture(segment.base, segment.stripes))
	_skater.set_upper_surface_material(top, mat)
	_skater.set_upper_surface_material(bottom, mat.duplicate() as StandardMaterial3D)


# The elbow pad's color: the kit's arms.elbow when it names one, else whatever
# the forearm's stripes put at its elbow end, so the pad disappears into the
# sleeve. Public static because the lobby backdrop's dummies wear the same pad.
static func elbow_color(arms: Dictionary) -> Color:
	var elbow: Variant = arms.get("elbow")
	if elbow is Color:
		return elbow
	return make_arm_stripes_texture(arms.lower.base, arms.lower.stripes) \
			.get_image().get_pixel(0, 0)


# Arm variant of UniformPaint.h_stripes: pre-shrinks the pattern about its
# center by _ARM_STRIPE_SCALE so authored fractions render at the same
# physical band height on the longer arm bones as on the socks. Public static
# because the lobby's bench dummies wear the same arm meshes and must not
# re-derive the correction.
static func make_arm_stripes_texture(base: Color, stripes: Array[Dictionary]) -> ImageTexture:
	return UniformPaint.h_stripes(
			base, _scale_stripes_about_center(stripes, _ARM_STRIPE_SCALE))


# Returns a copy of `stripes` with each band's width and its offset from the
# region center (0.5) multiplied by `scale`, shrinking the whole pattern about
# its center while keeping it centered. Runs on uniform apply, not per tick, so
# the fresh array is not a hot-path concern.
static func _scale_stripes_about_center(
		stripes: Array[Dictionary], scale: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s: Dictionary in stripes:
		out.append({
			"pos": 0.5 + (float(s.pos) - 0.5) * scale,
			"width": float(s.width) * scale,
			"color": s.color,
		})
	return out


# Paints both thigh cylinders with vertical side-column stripes. Per-side
# uv1_offset rotates the wrap so the texture's stripe column (centered around
# U=0.5 by convention) lands on each thigh's outer face.
func _paint_pants_thighs(pants_block: Dictionary) -> void:
	if pants_block.stripes.is_empty():
		var solid: StandardMaterial3D = UniformPaint.solid(pants_block.base, UniformPaint.ROUGH_NYLON)
		_skater.set_leg_surface_material(SkaterMeshBuilder.LegSurface.THIGH_L, solid)
		_skater.set_leg_surface_material(SkaterMeshBuilder.LegSurface.THIGH_R,
				solid.duplicate() as StandardMaterial3D)
		return
	var left: StandardMaterial3D = UniformPaint.textured(
			make_pants_stripes_texture(pants_block.base, pants_block.stripes), UniformPaint.ROUGH_NYLON)
	var right: StandardMaterial3D = left.duplicate() as StandardMaterial3D
	left.uv1_offset = Vector3(-0.25, 0.0, 0.0)
	right.uv1_offset = Vector3(0.25, 0.0, 0.0)
	_skater.set_leg_surface_material(SkaterMeshBuilder.LegSurface.THIGH_L, left)
	_skater.set_leg_surface_material(SkaterMeshBuilder.LegSurface.THIGH_R, right)


# Returns the sock material — textured if stripes are present, solid otherwise.
func _socks_material(socks_block: Dictionary) -> StandardMaterial3D:
	if socks_block.stripes.is_empty():
		return UniformPaint.solid(socks_block.base)
	return UniformPaint.textured(UniformPaint.h_stripes(socks_block.base, socks_block.stripes))


# Builds a (width_px × 4) image of vertical stripe columns. Used by pants:
# each stripe.pos is the U position of the column center, stripe.width is the
# column width. The caller's per-thigh uv1_offset.x lands the centered column
# on the outer face of each leg. Public static because tools/kit_capture.gd
# lays the breezers out flat in this same paint.
const _PANTS_TEX_WIDTH_PX: int = 128

static func make_pants_stripes_texture(base: Color, stripes: Array[Dictionary]) -> ImageTexture:
	var img := Image.create(_PANTS_TEX_WIDTH_PX, UniformPaint.STRIPE_TEX_WIDTH_PX, false, Image.FORMAT_RGBA8)
	img.fill(base)
	for s: Dictionary in stripes:
		var center_px: float = float(s.pos) * float(_PANTS_TEX_WIDTH_PX)
		var half_px:   float = float(s.width) * float(_PANTS_TEX_WIDTH_PX) * 0.5
		var x0: int = clampi(int(round(center_px - half_px)), 0, _PANTS_TEX_WIDTH_PX)
		var x1: int = clampi(int(round(center_px + half_px)), 0, _PANTS_TEX_WIDTH_PX)
		if x1 > x0:
			img.fill_rect(Rect2i(x0, 0, x1 - x0, UniformPaint.STRIPE_TEX_WIDTH_PX), s.color)
	return ImageTexture.create_from_image(img)


# ── Surface finishes ──────────────────────────────────────────────────────────
# Roughness presets so each material reads as its real surface instead of the
# uniform default-plastic look. Metallic stays 0 everywhere (all dielectric);
# the spread in roughness alone separates cloth / plastic / leather / composite.
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


func _skate_zone_color(zone: int) -> Color:
	return GearModelRegistry.skate_color(_skater.gear_style.skate_model, zone,
			_team_accent, _team_secondary, _team_light)


func _glove_zone_color(zone: int) -> Color:
	return GearModelRegistry.glove_color(_skater.gear_style.glove_model, zone,
			_kit_gloves, _glove_accent, _team_light)


func _resolve_lace_color() -> Color:
	return TapeColorRegistry.resolve(_skater.gear_style.lace_color, _team_accent)


# The five zones a skate model paints, each on both feet. The holder wears the
# skate finish rather than the runner's steel gloss — it is molded plastic.
func _repaint_skates() -> void:
	_paint_skate_zone(GearModelRegistry.SKATE_QUARTER,
			SkaterMeshBuilder.LegSurface.FOOT_L_SHELL,
			SkaterMeshBuilder.LegSurface.FOOT_R_SHELL)
	_paint_skate_zone(GearModelRegistry.SKATE_TOE,
			SkaterMeshBuilder.LegSurface.FOOT_L_TOE,
			SkaterMeshBuilder.LegSurface.FOOT_R_TOE)
	_paint_skate_zone(GearModelRegistry.SKATE_COLLAR,
			SkaterMeshBuilder.LegSurface.SKATE_L_COLLAR,
			SkaterMeshBuilder.LegSurface.SKATE_R_COLLAR)
	_paint_skate_zone(GearModelRegistry.SKATE_STRIPE,
			SkaterMeshBuilder.LegSurface.SKATE_L_STRIPE,
			SkaterMeshBuilder.LegSurface.SKATE_R_STRIPE)
	_paint_skate_zone(GearModelRegistry.SKATE_HOLDER,
			SkaterMeshBuilder.LegSurface.FOOT_L_HOLDER,
			SkaterMeshBuilder.LegSurface.FOOT_R_HOLDER)


func _paint_skate_zone(zone: int, left: int, right: int) -> void:
	var mat: StandardMaterial3D = UniformPaint.solid(_skate_zone_color(zone), UniformPaint.ROUGH_SKATE)
	_skater.set_leg_surface_material(left, mat)
	_skater.set_leg_surface_material(right, mat.duplicate())


func _repaint_laces() -> void:
	var lace_mat: StandardMaterial3D = UniformPaint.solid(_resolve_lace_color())
	_skater.set_leg_surface_material(
			SkaterMeshBuilder.LegSurface.FOOT_L_LACES, lace_mat.duplicate())
	_skater.set_leg_surface_material(
			SkaterMeshBuilder.LegSurface.FOOT_R_LACES, lace_mat.duplicate())


# Repaints the gear-style pieces (both skates, both gloves, the laces, the
# stick's colorway) for a live model or lace change without touching the rest
# of the uniform. Same live-cosmetic contract as refresh_tape below — the
# stick rebuild skips the ghost window (a translucent standard mat holds the
# override there; un-ghost rebuilds from the live config anyway).
func refresh_gear_style() -> void:
	_repaint_gloves()
	_repaint_skates()
	_repaint_laces()
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


# Back of the hand, fingers and cuff rings — the three zones a glove model
# paints. (The hand surfaces take UpperBone values because for the arm parts a
# surface index and its bone index coincide; the FINGERS surfaces sit outside
# that run and are addressed as surfaces — see the UpperSurface doc block.)
func _repaint_gloves() -> void:
	var body_mat: StandardMaterial3D = UniformPaint.solid(
			_glove_zone_color(GearModelRegistry.GLOVE_BODY), UniformPaint.ROUGH_GLOVE)
	_skater.set_upper_surface_material(SkaterMeshBuilder.UpperBone.TOP_HAND, body_mat)
	_skater.set_upper_surface_material(
			SkaterMeshBuilder.UpperBone.BOTTOM_HAND, body_mat.duplicate())
	var finger_mat: StandardMaterial3D = UniformPaint.solid(
			_glove_zone_color(GearModelRegistry.GLOVE_FINGERS), UniformPaint.ROUGH_GLOVE)
	_skater.set_upper_surface_material(
			SkaterMeshBuilder.UpperSurface.TOP_FINGERS, finger_mat)
	_skater.set_upper_surface_material(
			SkaterMeshBuilder.UpperSurface.BOTTOM_FINGERS, finger_mat.duplicate())
	_paint_glove_cuffs(_glove_zone_color(GearModelRegistry.GLOVE_CUFF))


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
	_paint_head_piece(SkaterArmRig.HeadPiece.SCALP,
			SkaterHairMesh.make_material(gear.hair_color, false))
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


# The cuff rings are surfaces of the arm rig's shared mesh, so a gear-colour
# change is a repaint and a resize — the geometry is permanent, and nothing here
# frees or recreates a MeshInstance3D.
func _paint_glove_cuffs(gloves_color: Color) -> void:
	var mat: StandardMaterial3D = UniformPaint.solid(gloves_color, UniformPaint.ROUGH_GLOVE)
	_skater.set_upper_surface_material(SkaterMeshBuilder.UpperBone.TOP_CUFF, mat)
	_skater.set_upper_surface_material(
			SkaterMeshBuilder.UpperBone.BOTTOM_CUFF, mat.duplicate())
	# Scaled by the Hands forearm bulk so the cuff stays proud of the forearm
	# cylinder it wraps — equal radii z-fight (see Skater.forearm_visual_mult).
	var cuff_radius: float = _skater.arm_mesh_thickness * 0.6 * _skater.forearm_visual_mult
	_skater.set_arm_cuff_radius(SkaterMeshBuilder.UpperBone.TOP_CUFF, cuff_radius)
	_skater.set_arm_cuff_radius(SkaterMeshBuilder.UpperBone.BOTTOM_CUFF, cuff_radius)


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
