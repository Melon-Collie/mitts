class_name JerseyDecal
extends Node2D

# Draws the jersey base color, the collar (the torso's top cap) and the yoke (the
# side from the collar down to the shoulder line), the procedural stripe
# array, and player name/number into a SubViewport that the torso material
# samples as its albedo texture. The torso's CylinderMesh wraps this 2D
# texture around its surface; text at x=BACK_CENTER_X lands on the +Z back
# of the skater (paired with the torso material's uv1_offset.x = UV_OFFSET_X).
#
# Stripes follow the v2 schema convention: each stripe has pos∈[0,1] (band
# center) and width∈[0,1] (band height as a fraction of the visible torso
# UV region). Stripes paint in array order; later overpaints earlier, so
# stacked stripes sharing pos with shrinking widths produce concentric
# centered bands.

const FONT: Font = preload("res://Assets/Fonts/BarlowSemiCondensed-ExtraBold.ttf")
const NAME_FONT: Font = preload("res://Assets/Fonts/Manrope-SemiBold.ttf")
const IMG_W: int = 1024
const IMG_H: int = 512
# The torso material's uv1_offset.x: a quarter turn puts texel x = IMG_W / 4 at
# the skater's +Z back, plus the torso's half-facet phase.
const UV_OFFSET_X: float = 0.25 + SkaterMeshBuilder.TORSO_U_PHASE
const BACK_CENTER_X: int = IMG_W / 4
# Godot's CylinderMesh allocates the top half of the texture's V range to the
# side surface; cap disks use the bottom half. All visible torso side content
# stays inside [0, SIDE_V_MAX_PX).
const SIDE_V_MAX_PX: int = IMG_H / 2
# Top-cap disk region after uv1_offset: the cap UV centers at
# (0.25 + UV_OFFSET_X, 0.75) with radius 0.25, disjoint from the bottom cap's
# (which wraps round the seam), so filling this rect paints only the top cap.
# Only the inscribed disk is sampled; a rect fill is just simpler than a circle.
const TOP_CAP_RECT: Rect2 = Rect2(UV_OFFSET_X * IMG_W, SIDE_V_MAX_PX, IMG_W / 2, IMG_H / 2)

# The back's size on the torso mesh: the side's height, and its girth through
# the name and number. The texture wraps that girth across IMG_W and that
# height down SIDE_V_MAX_PX, so its texels are not square; lettering is sized
# in metres and drawn through PX_PER_M so it lands undistorted.
# test_lettering_scale.gd measures both against the mesh.
const BACK_HEIGHT_M: float = 0.55
const BACK_GIRTH_M: float = 1.32
const PX_PER_M: Vector2 = Vector2(IMG_W / BACK_GIRTH_M, SIDE_V_MAX_PX / BACK_HEIGHT_M)

# Layout down the back, in metres: the name hangs just under the yoke, as it
# does under a real sweater's shoulder panel, and the number under it. Sizes are
# font ems; the glyphs are about 0.7 of that.
const NAME_GAP_M: float = 0.02
const NAME_EM_M: float = 0.075
const NUMBER_GAP_M: float = 0.012
const NUMBER_EM_M: float = 0.25
const YOKE_BOTTOM_PX: int = roundi(SkaterMeshBuilder.TORSO_YOKE_SIDE_FRACTION * SIDE_V_MAX_PX)

# The chest wordmark, half a turn from the back. It rises left to right and
# shrinks from WORDMARK_MAX_EM_M until its horizontal extent fits
# WORDMARK_SPAN_M — about the chest's flat width, so long names stay off the sides.
const FRONT_CENTER_X: int = BACK_CENTER_X + IMG_W / 2
const WORDMARK_ANGLE_RAD: float = -0.28
const WORDMARK_MAX_EM_M: float = 0.13
const WORDMARK_SPAN_M: float = 0.40
const WORDMARK_CENTER_DROP_M: float = 0.21
const CREST_RADIUS_M: float = 0.14
const CREST_CENTER_DROP_M: float = 0.2
# Cap height over em, for the glyph box's vertical half.
const _CAP_HEIGHT_EM: float = 0.7

var jersey_color: Color = Color.WHITE
var yoke_color: Color = Color.WHITE
var collar_color: Color = Color.WHITE
var stripes: Array[Dictionary] = []       # [{pos, width, color}]
var player_name: String = ""
var jersey_number: int = 0
var text_color: Color = Color.BLACK
var wordmark: String = ""
# A chest crest instead of the wordmark when `crest_id` (a CrestFruits id) is set.
var crest_id: String = ""
var crest_preset: Dictionary = {}


func _draw() -> void:
	# Base fill across the whole texture so cap disks aren't transparent.
	draw_rect(Rect2(0, 0, IMG_W, IMG_H), jersey_color, true)
	draw_rect(TOP_CAP_RECT, collar_color, true)
	draw_rect(Rect2(0, 0, IMG_W, YOKE_BOTTOM_PX), yoke_color, true)
	# Stripes paint in array order over the side region [0, SIDE_V_MAX_PX].
	for stripe: Dictionary in stripes:
		var band: Vector2i = _stripe_band(stripe, SIDE_V_MAX_PX)
		if band.y > band.x:
			draw_rect(Rect2(0, band.x, IMG_W, band.y - band.x), stripe.color, true)

	draw_back_lettering(self, player_name, jersey_number, text_color, float(BACK_CENTER_X),
			PX_PER_M, float(YOKE_BOTTOM_PX) / PX_PER_M.y)
	if not crest_id.is_empty():
		var r: Vector2 = PX_PER_M * CREST_RADIUS_M
		TeamCrest.draw(self, crest_id, Transform2D(Vector2(r.x, 0.0),
				Vector2(0.0, r.y), Vector2(FRONT_CENTER_X, CREST_CENTER_DROP_M * PX_PER_M.y)),
				crest_preset)
	elif not wordmark.is_empty():
		_draw_wordmark(self, wordmark.to_upper(), text_color)


# Set in metres (at the vertical texel density), rotated there, then stretched to
# the horizontal one — so the slant, like the letters, is the shape it has on the body.
static func _draw_wordmark(canvas: CanvasItem, s: String, color: Color) -> void:
	var ref_size: int = roundi(WORDMARK_MAX_EM_M * PX_PER_M.y)
	var width_m: float = FONT.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1,
			ref_size).x / PX_PER_M.y
	var cos_a: float = absf(cos(WORDMARK_ANGLE_RAD))
	var sin_a: float = absf(sin(WORDMARK_ANGLE_RAD))
	var extent_m: float = width_m * cos_a + WORDMARK_MAX_EM_M * _CAP_HEIGHT_EM * sin_a
	var em_m: float = WORDMARK_MAX_EM_M * minf(1.0, WORDMARK_SPAN_M / extent_m)
	var size: int = roundi(em_m * PX_PER_M.y)
	var width: float = FONT.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var stretch: float = PX_PER_M.x / PX_PER_M.y
	var rot := Transform2D(WORDMARK_ANGLE_RAD, Vector2.ZERO)
	var xform := Transform2D(Vector2(stretch * rot.x.x, rot.x.y),
			Vector2(stretch * rot.y.x, rot.y.y),
			Vector2(FRONT_CENTER_X, WORDMARK_CENTER_DROP_M * PX_PER_M.y))
	canvas.draw_set_transform_matrix(xform)
	canvas.draw_string(FONT, Vector2(-width * 0.5, size * _CAP_HEIGHT_EM * 0.5), s,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)


# A back's name and number, laid out in metres down from the top of the back
# (`yoke_bottom_m` is where the yoke ends) and centred on `center_x` px. The
# goalie's back letters through this too, so every player's back reads alike.
static func draw_back_lettering(canvas: CanvasItem, p_name: String, number: int, color: Color,
		center_x: float, px_per_m: Vector2, yoke_bottom_m: float) -> void:
	var name_top_m: float = yoke_bottom_m + NAME_GAP_M
	if not p_name.is_empty():
		_draw_centered(canvas, NAME_FONT, p_name.to_upper(), NAME_EM_M, name_top_m,
				center_x, px_per_m, color)
	_draw_centered(canvas, FONT, str(number), NUMBER_EM_M,
			name_top_m + NAME_EM_M + NUMBER_GAP_M, center_x, px_per_m, color)


# Converts a v2 stripe {pos, width} over a region of height region_px into
# [y_start, y_end] pixel coords, clamped to the region. width is the band's
# total height as a fraction of the region; pos is the center.
static func _stripe_band(stripe: Dictionary, region_px: int) -> Vector2i:
	var center: float = float(stripe.pos) * float(region_px)
	var half: float   = float(stripe.width) * float(region_px) * 0.5
	var y0: int = clampi(int(round(center - half)), 0, region_px)
	var y1: int = clampi(int(round(center + half)), 0, region_px)
	return Vector2i(y0, y1)


# `em_m` tall with its em box's top `top_m` below the top of the back. The text
# is set at the vertical texel density and squeezed or widened to the
# horizontal one, so it is the shape the font draws once on the body. One
# color, no outline — the kit's text.outline is for UI chrome.
static func _draw_centered(canvas: CanvasItem, font: Font, s: String, em_m: float,
		top_m: float, center_x: float, px_per_m: Vector2, color: Color) -> void:
	var size: int = roundi(em_m * px_per_m.y)
	var stretch: float = px_per_m.x / px_per_m.y
	var width: float = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pos := Vector2(center_x / stretch - width * 0.5,
			top_m * px_per_m.y + font.get_ascent(size))
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2(stretch, 1.0))
	canvas.draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)


func update_jersey(
		j_color: Color, j_yoke: Color, j_collar: Color, j_stripes: Array[Dictionary],
		p_name: String, p_number: int, t_color: Color) -> void:
	jersey_color = j_color
	yoke_color = j_yoke
	collar_color = j_collar
	stripes = j_stripes
	player_name = p_name
	jersey_number = p_number
	text_color = t_color
	queue_redraw()
