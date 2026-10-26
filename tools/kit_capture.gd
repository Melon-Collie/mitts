extends SceneTree

# Dev visualizer: lays each team's home and away kit out FLAT — jersey front and
# back with both sleeves and shoulder caps, the breezers, the helmet, the socks,
# the gloves — beside a legend of every color and stripe in the kit, and saves one PNG per team. It is
# for editing data/team_colors.json: change a kit, re-run, look.
#
#   .claude/hooks/render-kits.sh                # every team, into ./.preview/kits
#   .claude/hooks/render-kits.sh pineapple,7       # named teams or slot numbers
#
# Nothing here re-paints a kit. Each garment is a rink mesh laid flat (a tube
# flattened is half its perimeter wide, so every width is measured off the shared
# lathe meshes, ring by ring) and textured by the game's own painters:
# JerseyDecal and ShoulderDecal, UniformPaint.h_stripes for the socks, and
# SkaterUniformCoordinator's arm and pants stripe textures. A band in the PNG is
# the band the game paints, at its part's real proportions — arm stripes come out
# shorter than sock stripes of the same authored width, as they do on the ice.
#
# Kits load through TeamColorRegistry, so user://team_colors.json shadows the
# bundled file exactly as it does in the game; the run prints which one won.
# KIT_PREVIEW_OUT (default user://kit_preview), KIT_PREVIEW_TEAMS (comma list),
# KIT_PREVIEW_NAME / KIT_PREVIEW_NUMBER (the back's name bar and number).
#
# Needs a real (software) renderer, not --headless — see the hook.

const _PX_PER_M: float = 420.0
# Columns per tube band: the band's two edges differ in width, and a single quad
# would bend the texture across that trapezoid.
const _TUBE_COLUMNS: int = 12
const _SLEEVE_DROP_DEG: float = 40.0
# Sleeve root: in from the edge of the torso's shoulder line (its widest ring
# within _SHOULDER_LINE_SPAN_M of the collar), so the shoulder cap covers the join.
const _SLEEVE_INSET_M: float = 0.03
const _SHOULDER_LINE_SPAN_M: float = 0.10
# The neck opening cut into the collar station, trimmed in the collar color
# (the torso's top cap) — a flat-lay convention, not a measured part.
const _COLLAR_WIDTH_M: float = 0.025
const _NECK_HALF_WIDTH_M: float = 0.08
const _NECK_DEPTH_FRONT_M: float = 0.06
const _NECK_DEPTH_BACK_M: float = 0.02
const _CAP_SEGMENTS: int = 28
# A thigh is a tube under the hip dome; the dome (buried in the pelvis in game)
# would flatten into a spike, so the leg starts at the first ring this wide.
const _THIGH_FULL_WIDTH_SHARE: float = 0.95
const _WAISTBAND_M: float = 0.10

# Lathe side U, with each part's uv1_offset already added. Front view puts +X on
# the viewer's left, so U rises left to right on every panel.
const _JERSEY_FRONT_U: Vector2 = Vector2(0.5, 1.0)
const _JERSEY_BACK_U: Vector2 = Vector2(0.0, 0.5)
# Each breezer leg shows its front and its outer side, so the side stripe (U 0.5)
# lands a quarter in from the outer edge rather than on the fold.
const _PANTS_LEFT_U: Vector2 = Vector2(0.375, 0.875)
const _PANTS_RIGHT_U: Vector2 = Vector2(0.125, 0.625)
const _FULL_U: Vector2 = Vector2(0.0, 1.0)

const _MARGIN: float = 32.0
const _PANEL_GAP: float = 24.0
const _PANEL_H: float = 600.0
const _JERSEY_HALF_SPAN: float = 380.0
const _JERSEY_GAP: float = 40.0
const _LEGEND_W: float = 600.0
const _BODY_TOP: float = 120.0
const _ROW2_TOP: float = 420.0
const _LEGEND_TOP: float = 92.0
const _LINE_H: float = 22.0
const _CHIP_PX: float = 14.0

const _BG: Color = Color(0.13, 0.14, 0.17)
const _PANEL_BG: Color = Color(0.21, 0.23, 0.28)
const _INK: Color = Color(0.93, 0.94, 0.96)
const _INK_DIM: Color = Color(0.63, 0.66, 0.72)
const _EDGE: Color = Color(0.0, 0.0, 0.0, 0.5)

const _OUT_ENV: String = "KIT_PREVIEW_OUT"
const _TEAMS_ENV: String = "KIT_PREVIEW_TEAMS"
const _NAME_ENV: String = "KIT_PREVIEW_NAME"
const _NUMBER_ENV: String = "KIT_PREVIEW_NUMBER"
const _DEFAULT_NAME: String = "Player"
const _DEFAULT_NUMBER: int = 19
const _USER_JSON: String = "user://team_colors.json"

# Flattened parts, as (drop below the first ring m, flat width m, texture V).
var _torso: Array[Vector3] = []
var _upper_arm: Array[Vector3] = []
var _forearm: Array[Vector3] = []
var _thigh: Array[Vector3] = []
var _sock: Array[Vector3] = []
var _arm_radius_m: float = 0.0
# The cap is drawn at its projected size, not flattened: laid flat at half its
# perimeter it would hide the name bar it sits beside on the ice.
var _cap_half: Vector2 = Vector2.ZERO
# The helmet as a disc as wide as its shell, between the pants and the socks.
var _helmet_radius_m: float = 0.0
# The glove, fingers up, right of the socks: the fist's width and the heights of
# its back and its fingers (its two surfaces), and the cuff under them.
var _glove_width_m: float = 0.0
var _glove_back_m: float = 0.0
var _glove_fingers_m: float = 0.0
var _cuff_width_m: float = 0.0
# Per side, the default glove model's three zone colors (body, fingers, cuff).
var _glove_colors: Array[PackedColorArray] = [PackedColorArray(), PackedColorArray()]

var _sheet: SubViewport
var _canvas: Node2D
var _jersey_decals: Array[JerseyDecal] = []
var _jersey_textures: Array[Texture2D] = []
var _shoulder_decals: Array[ShoulderDecal] = []
var _shoulder_textures: Array[Texture2D] = []
# Per side, the stripe textures the canvas draws with. Held here because a
# texture made inside _draw is freed before the frame that would show it.
var _upper_arm_textures: Array[Texture2D] = [null, null]
var _forearm_textures: Array[Texture2D] = [null, null]
var _pants_textures: Array[Texture2D] = [null, null]
var _sock_textures: Array[Texture2D] = [null, null]
var _preset: Dictionary = {}
var _player_name: String = _DEFAULT_NAME
var _number: int = _DEFAULT_NUMBER


func _initialize() -> void:
	_render.call_deferred()


func _render() -> void:
	await process_frame
	var out_dir: String = OS.get_environment(_OUT_ENV)
	if out_dir.is_empty():
		out_dir = "user://kit_preview"
	DirAccess.make_dir_recursive_absolute(out_dir)
	if not OS.get_environment(_NAME_ENV).is_empty():
		_player_name = OS.get_environment(_NAME_ENV)
	if OS.get_environment(_NUMBER_ENV).is_valid_int():
		_number = int(OS.get_environment(_NUMBER_ENV))
	if FileAccess.file_exists(_USER_JSON):
		print("[kit_capture] kits from %s — it shadows res://data/team_colors.json"
				% ProjectSettings.globalize_path(_USER_JSON))
	else:
		print("[kit_capture] kits from res://data/team_colors.json")

	_measure_parts()
	_build_sheet()
	for slot: int in _wanted_slots():
		_preset = TeamColorRegistry.get_preset(slot)
		for side: int in 2:
			var kit: Dictionary = _kit(side)
			_jersey_decals[side].update_crest(TeamCrest.fruit_for(_preset), _preset)
			_jersey_decals[side].update_jersey(kit.jersey.base,
					UniformPaint.yoke_color(kit.jersey), UniformPaint.collar_color(kit.jersey),
					kit.jersey.stripes, _player_name, _number, kit.text.color)
			_shoulder_decals[side].update_shoulder(kit.shoulders.color,
					UniformPaint.yoke_color(kit.jersey), _number,
					kit.shoulders.text)
			_upper_arm_textures[side] = SkaterUniformCoordinator.make_arm_stripes_texture(
					kit.arms.upper.base, kit.arms.upper.stripes)
			_forearm_textures[side] = SkaterUniformCoordinator.make_arm_stripes_texture(
					kit.arms.lower.base, kit.arms.lower.stripes)
			_pants_textures[side] = SkaterUniformCoordinator.make_pants_stripes_texture(
					kit.pants.base, kit.pants.stripes)
			_sock_textures[side] = UniformPaint.h_stripes(kit.socks.base, kit.socks.stripes)
			var colors: Dictionary = TeamColorRegistry.get_colors(slot, side)
			_glove_colors[side].clear()
			for zone: int in GearModelRegistry.GLOVE_ZONE_COUNT:
				_glove_colors[side].append(GearModelRegistry.glove_color(
						GearStyleConfig.new().glove_model, zone,
						colors.gloves, colors.glove_accent, colors.light))
		_canvas.queue_redraw()
		# Decal viewports draw first, the sheet samples them a frame later.
		for _i: int in 4:
			await process_frame
		var path: String = "%s/kit_%s.png" % [out_dir, String(_preset.name).to_lower()]
		_sheet.get_texture().get_image().save_png(path)
		print("[kit_capture] %s -> %s" % [_preset.name, ProjectSettings.globalize_path(path)])
	quit()


func _wanted_slots() -> Array[int]:
	var all: Array[int] = TeamColorRegistry.get_all_slots()
	var requested: String = OS.get_environment(_TEAMS_ENV)
	if requested.is_empty():
		return all
	var out: Array[int] = []
	for token: String in requested.split(",", false):
		var key: String = token.strip_edges().to_lower()
		for slot: int in all:
			if key == str(slot) or key == TeamColorRegistry.get_preset_name(slot).to_lower():
				out.append(slot)
	if out.is_empty():
		push_warning("[kit_capture] no team matches '%s'" % requested)
	return out


func _kit(side: int) -> Dictionary:
	return _preset.home if side == 0 else _preset.away


# ── Measuring the parts ──────────────────────────────────────────────────────


func _measure_parts() -> void:
	# The skater's own arm defaults (an average build), read off a throwaway
	# instance rather than restated.
	var skater := Skater.new()
	_arm_radius_m = skater.arm_mesh_thickness * 0.5
	var upper_len: float = skater.upper_arm_length
	var fore_len: float = skater.forearm_length
	var hand_r: float = skater.hand_sphere_radius
	_cuff_width_m = 2.0 * skater.arm_mesh_thickness * 0.6
	skater.free()
	var fist: ArrayMesh = SkaterMeshBuilder.shared_glove_fist()
	_glove_width_m = _surface_bounds(fist, SkaterMeshBuilder.FIST_PART_BACK).size.x * hand_r
	_glove_back_m = _surface_bounds(fist, SkaterMeshBuilder.FIST_PART_BACK).size.y * hand_r
	_glove_fingers_m = _surface_bounds(fist, SkaterMeshBuilder.FIST_PART_FINGERS).size.y * hand_r

	_torso = _lathe_stations(SkaterMeshBuilder.shared_torso())
	_upper_arm = _lathe_stations(SkaterMeshBuilder.shared_arm_bone(), _arm_radius_m, upper_len)
	_forearm = _lathe_stations(SkaterMeshBuilder.shared_arm_bone(), _arm_radius_m, fore_len)
	_sock = _lathe_stations(SkaterMeshBuilder.shared_sock())
	_thigh = _below_dome(_lathe_stations(SkaterMeshBuilder.shared_thigh()))
	var cap: AABB = SkaterMeshBuilder.shared_shoulder_cap().get_aabb()
	_cap_half = cap.size.x * 0.5 * Vector2.ONE
	var shell: PackedVector3Array = SkaterMeshBuilder.shared_helmet_assembly().surface_get_arrays(
			SkaterMeshBuilder.HELMET_SURF_SHELL)[Mesh.ARRAY_VERTEX]
	for v: Vector3 in shell:
		_helmet_radius_m = maxf(_helmet_radius_m, absf(v.x))


# One station per side ring of a lathe mesh, top to bottom: the ring's V, its
# drop below the top ring, and half its perimeter — the width of the tube laid
# flat. Caps are skipped by their UVs, which sit below the side's V range.
static func _lathe_stations(mesh: ArrayMesh, radius_scale: float = 1.0,
		length_scale: float = 1.0) -> Array[Vector3]:
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var rings: Dictionary = {}
	for i: int in verts.size():
		var uv: Vector2 = uvs[i]
		if uv.y > UniformPaint.CYLINDER_SIDE_V_FRACTION + 0.001:
			continue
		var ring: Dictionary = rings.get_or_add(snappedf(uv.y, 0.0001), {})
		ring[snappedf(uv.x, 0.0001)] = verts[i]
	var vs: Array = rings.keys()
	vs.sort()
	var out: Array[Vector3] = []
	var top_y: float = 0.0
	for v: float in vs:
		var ring: Dictionary = rings[v]
		var us: Array = ring.keys()
		us.sort()
		var perimeter: float = 0.0
		for k: int in us.size() - 1:
			var a: Vector3 = ring[us[k]]
			var b: Vector3 = ring[us[k + 1]]
			perimeter += Vector2(b.x - a.x, b.z - a.z).length()
		var y: float = (ring[us[0]] as Vector3).y
		if out.is_empty():
			top_y = y
		out.append(Vector3((top_y - y) * length_scale, perimeter * 0.5 * radius_scale, v))
	return out


func _shoulder_line() -> Vector3:
	var best: Vector3 = _torso[0]
	for s: Vector3 in _torso:
		if s.x <= _SHOULDER_LINE_SPAN_M and s.y > best.y:
			best = s
	return best


static func _surface_bounds(mesh: ArrayMesh, surface: int) -> AABB:
	var verts: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
	var bounds := AABB(verts[0], Vector3.ZERO)
	for v: Vector3 in verts:
		bounds = bounds.expand(v)
	return bounds


static func _below_dome(stations: Array[Vector3]) -> Array[Vector3]:
	var widest: float = 0.0
	for s: Vector3 in stations:
		widest = maxf(widest, s.y)
	var out: Array[Vector3] = []
	for s: Vector3 in stations:
		if out.is_empty() and s.y < widest * _THIGH_FULL_WIDTH_SHARE:
			continue
		out.append(s)
	var drop0: float = out[0].x
	for i: int in out.size():
		out[i].x -= drop0
	return out


# ── The sheet ────────────────────────────────────────────────────────────────


func _build_sheet() -> void:
	for side: int in 2:
		var jersey_vp := _decal_viewport(Vector2i(JerseyDecal.IMG_W, JerseyDecal.IMG_H))
		var jersey := JerseyDecal.new()
		jersey_vp.add_child(jersey)
		_jersey_decals.append(jersey)
		_jersey_textures.append(jersey_vp.get_texture())
		var shoulder := ShoulderDecal.new()
		var shoulder_vp := _decal_viewport(shoulder.size)
		shoulder_vp.add_child(shoulder)
		_shoulder_decals.append(shoulder)
		_shoulder_textures.append(shoulder_vp.get_texture())

	_sheet = SubViewport.new()
	_sheet.size = Vector2i(_sheet_size())
	_sheet.transparent_bg = false
	_sheet.disable_3d = true
	_sheet.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_sheet)
	_canvas = Node2D.new()
	_canvas.draw.connect(_draw_sheet)
	_sheet.add_child(_canvas)


func _decal_viewport(size: Vector2i) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = false
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	return vp


func _glove_x() -> float:
	return _back_x() + _JERSEY_HALF_SPAN * 0.72


func _helmet_x() -> float:
	return (_front_x() + _back_x()) * 0.5


func _sheet_size() -> Vector2:
	return Vector2(_legend_x() + _LEGEND_W + _MARGIN,
			_MARGIN * 2.0 + _PANEL_H * 2.0 + _PANEL_GAP)


func _front_x() -> float:
	return _MARGIN + _JERSEY_HALF_SPAN


func _back_x() -> float:
	return _front_x() + _JERSEY_HALF_SPAN * 2.0 + _JERSEY_GAP


func _legend_x() -> float:
	return _back_x() + _JERSEY_HALF_SPAN + _JERSEY_GAP


func _draw_sheet() -> void:
	var c: Node2D = _canvas
	c.draw_rect(Rect2(Vector2.ZERO, _sheet_size()), _BG)
	if _preset.is_empty():
		return
	for side: int in 2:
		var top: float = _MARGIN + float(side) * (_PANEL_H + _PANEL_GAP)
		_draw_panel(c, top, side)


func _draw_panel(c: Node2D, top: float, side: int) -> void:
	var kit: Dictionary = _kit(side)
	var width: float = _sheet_size().x - _MARGIN * 2.0
	c.draw_rect(Rect2(_MARGIN, top, width, _PANEL_H), _PANEL_BG)
	var title: String = "%s — %s" % [_preset.name, "HOME" if side == 0 else "AWAY"]
	c.draw_string(JerseyDecal.FONT, Vector2(_legend_x(), top + 52.0), title,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 34, _INK)

	var body_y: float = top + _BODY_TOP
	_caption(c, Vector2(_front_x(), body_y - 62.0), "JERSEY FRONT")
	_caption(c, Vector2(_back_x(), body_y - 62.0), "JERSEY BACK")
	_draw_jersey(c, Vector2(_front_x(), body_y), kit, side, _JERSEY_FRONT_U, _NECK_DEPTH_FRONT_M)
	_draw_jersey(c, Vector2(_back_x(), body_y), kit, side, _JERSEY_BACK_U, _NECK_DEPTH_BACK_M)

	var row2: float = top + _ROW2_TOP
	_caption(c, Vector2(_front_x(), row2 - 8.0), "PANTS")
	_draw_pants(c, Vector2(_front_x(), row2 + _WAISTBAND_M * _PX_PER_M), kit.pants.base,
			_pants_textures[side])
	_caption(c, Vector2(_helmet_x(), row2 - 8.0), "HELMET")
	var helmet_at := Vector2(_helmet_x(), row2 + 12.0 + _helmet_radius_m * _PX_PER_M)
	c.draw_circle(helmet_at, _helmet_radius_m * _PX_PER_M, kit.helmet)
	c.draw_arc(helmet_at, _helmet_radius_m * _PX_PER_M, 0.0, TAU, 48, _EDGE, 1.5, true)
	_caption(c, Vector2(_glove_x(), row2 - 8.0), "GLOVE")
	_draw_glove(c, Vector2(_glove_x(), row2 + 14.0), _glove_colors[side])
	_caption(c, Vector2(_back_x(), row2 - 8.0), "SOCKS")
	_draw_socks(c, Vector2(_back_x(), row2 + 10.0), _sock_textures[side])

	_draw_legend(c, Vector2(_legend_x(), top + _LEGEND_TOP), kit)


func _caption(c: Node2D, at: Vector2, text: String) -> void:
	c.draw_string(JerseyDecal.NAME_FONT, at - Vector2(200.0, 0.0), text,
			HORIZONTAL_ALIGNMENT_CENTER, 400.0, 15, _INK_DIM)


# ── Garments ─────────────────────────────────────────────────────────────────


func _draw_jersey(c: Node2D, top_center: Vector2, kit: Dictionary, side: int,
		u: Vector2, neck_depth_m: float) -> void:
	var line: Vector3 = _shoulder_line()
	var roots: Array[Vector2] = []
	for dir: float in [-1.0, 1.0]:
		roots.append(top_center + Vector2(dir * (line.y * 0.5 - _SLEEVE_INSET_M),
				line.x) * _PX_PER_M)
	for i: int in 2:
		_draw_sleeve(c, roots[i], -1.0 if i == 0 else 1.0,
				SkaterUniformCoordinator.elbow_color(kit.arms), side)
	_draw_tube(c, top_center, _torso, _jersey_textures[side], u)
	_draw_collar(c, top_center, UniformPaint.collar_color(kit.jersey), neck_depth_m)
	for root_px: Vector2 in roots:
		_draw_shoulder_cap(c, root_px, _shoulder_textures[side])


# A sleeve hangs down and out from `root` at _SLEEVE_DROP_DEG: upper arm from
# the shoulder, the elbow pad in its own color (as the rink paints it), the
# forearm on. Stripe V 0 is the proximal end of each bone, as on the arm mesh.
func _draw_sleeve(c: Node2D, root_px: Vector2, outward: float, elbow_color: Color,
		side: int) -> void:
	var drop: float = deg_to_rad(_SLEEVE_DROP_DEG)
	var dir := Vector2(outward * cos(drop), sin(drop))
	c.draw_set_transform(root_px, atan2(-dir.x, dir.y))
	var elbow := Vector2(0.0, _upper_arm[_upper_arm.size() - 1].x * _PX_PER_M)
	_draw_tube(c, Vector2.ZERO, _upper_arm, _upper_arm_textures[side], _FULL_U)
	_draw_tube(c, elbow, _forearm, _forearm_textures[side], _FULL_U)
	var pad_px: float = SkaterMeshBuilder.ELBOW_PAD_RADIUS_M * _PX_PER_M
	c.draw_circle(elbow, pad_px, elbow_color)
	c.draw_arc(elbow, pad_px, 0.0, TAU, 32, _EDGE, 1.5, true)
	c.draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_collar(c: Node2D, top_center: Vector2, color: Color, neck_depth_m: float) -> void:
	var neck := PackedVector2Array()
	for k: int in 17:
		var t: float = PI * float(k) / 16.0
		neck.append(top_center + Vector2(cos(t) * _NECK_HALF_WIDTH_M,
				sin(t) * neck_depth_m) * _PX_PER_M)
	c.draw_colored_polygon(neck, _PANEL_BG)
	c.draw_polyline(neck, color, _COLLAR_WIDTH_M * _PX_PER_M, true)


# The decal window is the patch of the cap facing outward (the per-shoulder
# uv1_offset puts the number at U 0.5), as wide and tall in metres as the patch
# is drawn, centred on the number — so the number keeps its shape.
func _draw_shoulder_cap(c: Node2D, center: Vector2, tex: Texture2D) -> void:
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var half_px: Vector2 = _cap_half * _PX_PER_M
	for k: int in _CAP_SEGMENTS:
		var t: float = TAU * float(k) / float(_CAP_SEGMENTS)
		var unit := Vector2(cos(t), sin(t))
		pts.append(center + unit * half_px)
		uvs.append(Vector2(0.5 + unit.x * _cap_half.x / ShoulderDecal.CAP_GIRTH_M,
				ShoulderDecal.CAP_NUMBER_CENTER_V + unit.y * _cap_half.y / ShoulderDecal.CAP_M_PER_V))
	c.draw_polygon(pts, PackedColorArray([Color.WHITE]), uvs, tex)
	pts.append(pts[0])
	c.draw_polyline(pts, _EDGE, 1.5, true)


# Two legs side by side under a waistband (the pelvis, which the rink paints the
# pants base). `top_center` is the top of the legs.
func _draw_pants(c: Node2D, top_center: Vector2, base: Color, tex: Texture2D) -> void:
	var leg_w: float = 0.0
	for s: Vector3 in _thigh:
		leg_w = maxf(leg_w, s.y)
	var half: float = leg_w * 0.5 * _PX_PER_M
	_draw_tube(c, top_center + Vector2(-half, 0.0), _thigh, tex, _PANTS_LEFT_U)
	_draw_tube(c, top_center + Vector2(half, 0.0), _thigh, tex, _PANTS_RIGHT_U)
	var band := Rect2(top_center.x - half * 2.0, top_center.y - _WAISTBAND_M * _PX_PER_M,
			half * 4.0, _WAISTBAND_M * _PX_PER_M)
	c.draw_rect(band, base)
	c.draw_rect(band, _EDGE, false, 1.5)


# Fingers at the top, the back of the hand under them with the thumb off its
# side, the cuff at the bottom, each in its zone's color; creases split the
# fingers.
func _draw_glove(c: Node2D, top_center: Vector2, colors: PackedColorArray) -> void:
	var w: float = _glove_width_m * _PX_PER_M
	var fingers := Rect2(top_center.x - w * 0.5, top_center.y, w, _glove_fingers_m * _PX_PER_M)
	var back := Rect2(fingers.position.x, fingers.end.y, w, _glove_back_m * _PX_PER_M)
	var cuff_w: float = _cuff_width_m * _PX_PER_M
	var cuff := Rect2(top_center.x - cuff_w * 0.5, back.end.y,
			cuff_w, SkaterMeshBuilder.CUFF_HEIGHT_M * _PX_PER_M)
	var thumb := Rect2(back.position.x - w * 0.3, back.position.y + back.size.y * 0.15,
			w * 0.3, back.size.y * 0.6)
	for part: Array in [[thumb, colors[GearModelRegistry.GLOVE_BODY]],
			[fingers, colors[GearModelRegistry.GLOVE_FINGERS]],
			[back, colors[GearModelRegistry.GLOVE_BODY]],
			[cuff, colors[GearModelRegistry.GLOVE_CUFF]]]:
		c.draw_rect(part[0], part[1])
		c.draw_rect(part[0], _EDGE, false, 1.5)
	for k: int in range(1, 4):
		var x: float = fingers.position.x + w * float(k) / 4.0
		c.draw_line(Vector2(x, fingers.position.y), Vector2(x, fingers.end.y), _EDGE, 1.5)


func _draw_socks(c: Node2D, top_center: Vector2, tex: Texture2D) -> void:
	var gap: float = (_sock[0].y * 0.5 + 0.04) * _PX_PER_M
	_draw_tube(c, top_center + Vector2(-gap, 0.0), _sock, tex, _FULL_U)
	_draw_tube(c, top_center + Vector2(gap, 0.0), _sock, tex, _FULL_U)


# A flattened tube hanging down local +Y from `top_center`, each station band
# split into columns with exact UVs, then outlined.
func _draw_tube(c: Node2D, top_center: Vector2, stations: Array[Vector3],
		tex: Texture2D, u: Vector2) -> void:
	var white := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
	for i: int in stations.size() - 1:
		var a: Vector3 = stations[i]
		var b: Vector3 = stations[i + 1]
		for k: int in _TUBE_COLUMNS:
			var f0: float = float(k) / float(_TUBE_COLUMNS)
			var f1: float = float(k + 1) / float(_TUBE_COLUMNS)
			var u0: float = lerpf(u.x, u.y, f0)
			var u1: float = lerpf(u.x, u.y, f1)
			c.draw_primitive(PackedVector2Array([
				top_center + Vector2((f0 - 0.5) * a.y, a.x) * _PX_PER_M,
				top_center + Vector2((f1 - 0.5) * a.y, a.x) * _PX_PER_M,
				top_center + Vector2((f1 - 0.5) * b.y, b.x) * _PX_PER_M,
				top_center + Vector2((f0 - 0.5) * b.y, b.x) * _PX_PER_M,
			]), white, PackedVector2Array([
				Vector2(u0, a.z), Vector2(u1, a.z), Vector2(u1, b.z), Vector2(u0, b.z),
			]), tex)
	var outline := PackedVector2Array()
	for s: Vector3 in stations:
		outline.append(top_center + Vector2(-0.5 * s.y, s.x) * _PX_PER_M)
	for i: int in range(stations.size() - 1, -1, -1):
		var s: Vector3 = stations[i]
		outline.append(top_center + Vector2(0.5 * s.y, s.x) * _PX_PER_M)
	outline.append(outline[0])
	c.draw_polyline(outline, _EDGE, 1.5, true)


# ── Legend ───────────────────────────────────────────────────────────────────
# Every color in the kit, keyed by its path in team_colors.json, with stripes
# as pos/width — what an edit to the file is written in.


func _draw_legend(c: Node2D, at: Vector2, kit: Dictionary) -> void:
	var pen: Vector2 = at
	pen = _legend_row(c, pen, "helmet", [kit.helmet], [""])
	pen = _legend_row(c, pen, "shoulders", [kit.shoulders.color, kit.shoulders.text],
			["", "text"])
	pen = _legend_row(c, pen, "jersey", [kit.jersey.base, UniformPaint.yoke_color(kit.jersey),
			UniformPaint.collar_color(kit.jersey)],
			["", "yoke" if kit.jersey.yoke is Color else "yoke (base)",
			"collar" if kit.jersey.collar is Color else "collar (yoke)"])
	pen = _stripe_rows(c, pen, kit.jersey.stripes)
	pen = _legend_row(c, pen, "arms.upper", [kit.arms.upper.base], [""])
	pen = _stripe_rows(c, pen, kit.arms.upper.stripes)
	pen = _legend_row(c, pen, "arms.lower", [kit.arms.lower.base], [""])
	pen = _stripe_rows(c, pen, kit.arms.lower.stripes)
	pen = _legend_row(c, pen, "arms.elbow", [SkaterUniformCoordinator.elbow_color(kit.arms)],
			["" if kit.arms.elbow is Color else "(forearm at the elbow)"])
	pen = _legend_row(c, pen, "gloves", [kit.gloves], [""])
	pen = _legend_row(c, pen, "pants", [kit.pants.base], ["(stripe pos is across, U)"])
	pen = _stripe_rows(c, pen, kit.pants.stripes)
	pen = _legend_row(c, pen, "socks", [kit.socks.base], [""])
	pen = _stripe_rows(c, pen, kit.socks.stripes)
	pen = _legend_row(c, pen, "goalie_pads", [kit.goalie_pads], ["(and blocker, trapper)"])
	_legend_row(c, pen, "text", [kit.text.color, kit.text.outline], ["", "outline (UI only)"])


# One labelled row of chips; returns the pen at the next row.
func _legend_row(c: Node2D, pen: Vector2, label: String, colors: Array,
		notes: Array) -> Vector2:
	c.draw_string(JerseyDecal.NAME_FONT, pen + Vector2(0.0, 12.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, _INK)
	var x: float = pen.x + 104.0
	for i: int in colors.size():
		x = _chip(c, Vector2(x, pen.y), colors[i], notes[i])
	return pen + Vector2(0.0, _LINE_H)


# Stripes indented under their region, wrapping at the legend's width.
func _stripe_rows(c: Node2D, pen: Vector2, stripes: Array) -> Vector2:
	if stripes.is_empty():
		return pen
	var x: float = pen.x + 124.0
	var y: float = pen.y
	for s: Dictionary in stripes:
		if x > pen.x + _LEGEND_W - 170.0:
			x = pen.x + 124.0
			y += _LINE_H
		x = _chip(c, Vector2(x, y), s.color, "%.2f / %.2f" % [s.pos, s.width])
	return Vector2(pen.x, y + _LINE_H)


func _chip(c: Node2D, at: Vector2, color: Color, note: String) -> float:
	var box := Rect2(at, Vector2(_CHIP_PX, _CHIP_PX))
	c.draw_rect(box, color)
	c.draw_rect(box, _INK_DIM, false, 1.0)
	var text: String = "#" + color.to_html(false).to_upper()
	if not note.is_empty():
		text += " " + note
	var font: Font = JerseyDecal.NAME_FONT
	var pos := Vector2(at.x + _CHIP_PX + 6.0, at.y + 12.0)
	c.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, _INK_DIM)
	return pos.x + font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 18.0
