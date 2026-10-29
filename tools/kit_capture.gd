extends SceneTree

# Dev visualizer: lays each team's home and away kit out FLAT — jersey front and
# back with both sleeves, the breezers, the helmet, the socks, the gloves —
# beside a legend of every color and stripe in the kit, and saves one PNG per
# team. It is for editing data/team_colors.json: change a kit, re-run, look.
#
#   .claude/hooks/render-kits.sh                # every team, into ./.preview/kits
#   .claude/hooks/render-kits.sh pineapple,7       # named teams or slot numbers
#
# Nothing here re-paints a kit. Each garment is the skater's skin laid flat (a
# tube flattened is half its perimeter wide, so every width is measured off the
# skin's own rings: SkaterConnectedMesh.jersey_stations and sleeve_stations,
# SkaterConnectedPants.leg_stations) and textured by the game's own painters:
# JerseyDecal and SleeveDecal, UniformPaint.h_stripes for the socks and
# SkaterKitPaint's pants stripes. A band in the PNG is the band the game paints,
# at its part's real proportions.
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
# within _SHOULDER_LINE_SPAN_M of the collar), where the armhole's seam runs.
const _SLEEVE_INSET_M: float = 0.03
const _SHOULDER_LINE_SPAN_M: float = 0.10
# The neck opening cut into the collar station, trimmed in the collar color
# (the torso's top cap) — a flat-lay convention, not a measured part.
const _COLLAR_WIDTH_M: float = 0.025
const _NECK_HALF_WIDTH_M: float = 0.08
const _NECK_DEPTH_FRONT_M: float = 0.06
const _NECK_DEPTH_BACK_M: float = 0.02
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
# The outside of a sleeve, its number (at U 0.5) in the middle.
const _SLEEVE_U: Vector2 = Vector2(0.25, 0.75)

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
var _sleeve: Array[Vector3] = []
var _thigh: Array[Vector3] = []
var _sock: Array[Vector3] = []
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
var _sleeve_decals: Array[SleeveDecal] = []
var _sleeve_textures: Array[Texture2D] = []
# Per side, the stripe textures the canvas draws with. Held here because a
# texture made inside _draw is freed before the frame that would show it.
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
					kit.jersey.stripes, _player_name, _number, kit.text.color, kit.text.stroke)
			_sleeve_decals[side].update_sleeve(kit.sleeve, _number, kit.shoulders.text,
					kit.shoulders.stroke)
			_pants_textures[side] = SkaterKitPaint.make_pants_stripes_texture(
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
	# The skater's own glove defaults (an average build), read off a throwaway
	# instance rather than restated.
	var skater := Skater.new()
	var hand_r: float = skater.hand_sphere_radius
	_cuff_width_m = 2.0 * skater.arm_mesh_thickness * 0.6
	skater.free()
	var fist: ArrayMesh = SkaterMeshBuilder.shared_glove_fist()
	_glove_width_m = _surface_bounds(fist, SkaterMeshBuilder.FIST_PART_BACK).size.x * hand_r
	_glove_back_m = _surface_bounds(fist, SkaterMeshBuilder.FIST_PART_BACK).size.y * hand_r
	_glove_fingers_m = _surface_bounds(fist, SkaterMeshBuilder.FIST_PART_FINGERS).size.y * hand_r

	var xz: Vector2 = SkaterMeshBuilder.PELVIS_XZ_SCALE
	var stations: Array[Vector3] = SkaterConnectedMesh.jersey_stations()
	var top_y: float = stations[0].x
	for st: Vector3 in stations:
		# The torso's own V: down its side from the collar (SkaterConnectedMesh).
		_torso.append(Vector3(top_y - st.x, _half_ellipse(st.y * xz.x, st.y * xz.y),
				0.5 * (top_y - st.x) / SkaterMeshBuilder.TORSO_SIDE_HEIGHT_M))
	# The sleeve from the seam to where the glove's cuff covers it.
	var rings: PackedVector2Array = SkaterConnectedMesh.sleeve_stations()
	_sleeve.append(Vector3(0.0, PI * rings[0].y, 0.0))
	for k: int in rings.size():
		var m: float = rings[k].x
		var r: float = rings[k].y
		if m >= SleevePaint.LENGTH_M:
			var prev: Vector2 = rings[k - 1]
			r = lerpf(prev.y, r, (SleevePaint.LENGTH_M - prev.x) / (m - prev.x))
			_sleeve.append(Vector3(SleevePaint.LENGTH_M, PI * r, 1.0))
			break
		_sleeve.append(Vector3(m, PI * r, SleevePaint.pos_of(m)))
	_thigh = _leg(SkaterConnectedPants.leg_stations(false))
	_sock = _leg(SkaterConnectedPants.leg_stations(true))
	var shell: PackedVector3Array = SkaterMeshBuilder.shared_helmet_assembly().surface_get_arrays(
			SkaterMeshBuilder.HELMET_SURF_SHELL)[Mesh.ARRAY_VERTEX]
	for v: Vector3 in shell:
		_helmet_radius_m = maxf(_helmet_radius_m, absf(v.x))


# Half an ellipse's perimeter (Ramanujan's): the width of an oval tube laid flat.
static func _half_ellipse(a: float, b: float) -> float:
	return PI * 0.5 * (3.0 * (a + b) - sqrt((3.0 * a + b) * (a + 3.0 * b)))


# A leg's rings as flat stations from its first ring down.
static func _leg(rings: PackedVector3Array) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for st: Vector3 in rings:
		out.append(Vector3(rings[0].x - st.x, PI * st.y, st.z))
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


# ── The sheet ────────────────────────────────────────────────────────────────


func _build_sheet() -> void:
	for side: int in 2:
		var jersey_vp := _decal_viewport(Vector2i(JerseyDecal.IMG_W, JerseyDecal.IMG_H))
		var jersey := JerseyDecal.new()
		jersey_vp.add_child(jersey)
		_jersey_decals.append(jersey)
		_jersey_textures.append(jersey_vp.get_texture())
		var sleeve := SleeveDecal.new()
		var sleeve_vp := _decal_viewport(SleeveDecal.SIZE)
		sleeve_vp.add_child(sleeve)
		_sleeve_decals.append(sleeve)
		_sleeve_textures.append(sleeve_vp.get_texture())

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
		_draw_sleeve(c, roots[i], -1.0 if i == 0 else 1.0, side)
	_draw_tube(c, top_center, _torso, _jersey_textures[side], u)
	_draw_collar(c, top_center, UniformPaint.collar_color(kit.jersey), neck_depth_m)


# A sleeve hangs down and out from `root` at _SLEEVE_DROP_DEG, its outside
# toward the viewer, the number on it.
func _draw_sleeve(c: Node2D, root_px: Vector2, outward: float, side: int) -> void:
	var drop: float = deg_to_rad(_SLEEVE_DROP_DEG)
	var dir := Vector2(outward * cos(drop), sin(drop))
	c.draw_set_transform(root_px, atan2(-dir.x, dir.y))
	_draw_tube(c, Vector2.ZERO, _sleeve, _sleeve_textures[side], _SLEEVE_U)
	c.draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_collar(c: Node2D, top_center: Vector2, color: Color, neck_depth_m: float) -> void:
	var neck := PackedVector2Array()
	for k: int in 17:
		var t: float = PI * float(k) / 16.0
		neck.append(top_center + Vector2(cos(t) * _NECK_HALF_WIDTH_M,
				sin(t) * neck_depth_m) * _PX_PER_M)
	c.draw_colored_polygon(neck, _PANEL_BG)
	c.draw_polyline(neck, color, _COLLAR_WIDTH_M * _PX_PER_M, true)


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
	pen = _legend_row(c, pen, "shoulders", [kit.shoulders.text, kit.shoulders.stroke],
			["text (the sleeve's number)", _stroke_note(kit.shoulders.stroke)])
	pen = _legend_row(c, pen, "jersey", [kit.jersey.base, UniformPaint.yoke_color(kit.jersey),
			UniformPaint.collar_color(kit.jersey)],
			["", "yoke" if kit.jersey.yoke is Color else "yoke (base)",
			"collar" if kit.jersey.collar is Color else "collar (yoke)"])
	pen = _stripe_rows(c, pen, kit.jersey.stripes)
	pen = _legend_row(c, pen, "sleeve", [kit.sleeve.base], [""])
	pen = _stripe_rows(c, pen, kit.sleeve.stripes)
	pen = _legend_row(c, pen, "gloves", [kit.gloves], [""])
	pen = _legend_row(c, pen, "pants", [kit.pants.base], ["(stripe pos is across, U)"])
	pen = _stripe_rows(c, pen, kit.pants.stripes)
	pen = _legend_row(c, pen, "socks", [kit.socks.base], [""])
	pen = _stripe_rows(c, pen, kit.socks.stripes)
	pen = _legend_row(c, pen, "goalie_pads", [kit.goalie_pads], ["(and blocker, trapper)"])
	_legend_row(c, pen, "text", [kit.text.color, kit.text.stroke, kit.text.outline],
			["", _stroke_note(kit.text.stroke), "outline (UI only)"])


func _stroke_note(stroke: Color) -> String:
	return "stroke" if stroke.a > 0.0 else "(no stroke)"


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
		var note: String = "%.2f / %.2f" % [s.pos, s.width]
		if s.has("peak"):
			note += " peak %.2f×%d" % [s.peak.depth, s.peak.count]
		x = _chip(c, Vector2(x, y), s.color, note)
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
