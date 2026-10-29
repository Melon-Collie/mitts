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
# center) and width∈[0,1] (band height), fractions of the side height the kits
# are authored against (UniformPaint.jersey_side_stripe), and may peak
# (StripeOutline) with its `u` from the back's centre, the chest at 0.5, or fill
# the side below it to the hem in its `fill_below`. Stripes
# paint in array order; later overpaints earlier, so stacked stripes sharing pos
# with shrinking widths produce concentric centered bands.

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
const BACK_HEIGHT_M: float = SkaterMeshBuilder.TORSO_SIDE_HEIGHT_M
const BACK_GIRTH_M: float = 1.32
const PX_PER_M: Vector2 = Vector2(IMG_W / BACK_GIRTH_M, SIDE_V_MAX_PX / BACK_HEIGHT_M)

# Layout down the back, in metres: the name hangs just under the yoke, as it
# does under a real sweater's shoulder panel, and the number under it. Sizes are
# font ems; the glyphs are about 0.7 of that.
const NAME_GAP_M: float = 0.02
const NAME_EM_M: float = 0.075
const NUMBER_GAP_M: float = 0.012
const NUMBER_EM_M: float = 0.25
# The skater's back between the armholes at the name's height, less a margin:
# 0.45 m shows on the posed rig, and a name wider than this runs onto the
# sleeves.
const NAME_MAX_WIDTH_M: float = 0.40
# A long name is set narrower, as a real sweater's is, but no narrower than
# this; past it the name is set smaller as well, so it stays readable.
const NAME_MIN_SQUEEZE: float = 0.7
# A kit's lettering stroke: draw_string_outline's size, in ems of the text it
# borders. It reaches about a sixth of that past the glyph's edge (measured on
# the kit sheet), so 1 cm round a back number, a real sweater's twill border.
const STROKE_SIZE_EM: float = 0.24
const YOKE_BOTTOM_PX: int = roundi(SkaterMeshBuilder.TORSO_YOKE_SIDE_FRACTION * SIDE_V_MAX_PX)

# The chest crest (TeamCrest), half a turn from the back: 28 cm across, about a
# real sweater's, hung under the yoke.
const FRONT_CENTER_X: int = BACK_CENTER_X + IMG_W / 2
const CREST_RADIUS_M: float = 0.14
# Clear air between the yoke line and the crest's top, keylines included, so a
# kit's trim under its yoke (Pineapple's) never meets the crest.
const CREST_YOKE_GAP_M: float = 0.02
# How far above its centre a crest reaches, in radii: the fruit fills the unit
# circle and its two keylines stand outside it.
const _CREST_REACH: float = 1.0 + 2.0 * TeamCrest.KEYLINE_WIDTH

var jersey_color: Color = Color.WHITE
var yoke_color: Color = Color.WHITE
var collar_color: Color = Color.WHITE
var stripes: Array[Dictionary] = []       # [{pos, width, color}]
var player_name: String = ""
var jersey_number: int = 0
var text_color: Color = Color.BLACK
# Transparent for unbordered lettering.
var text_stroke: Color = Color.TRANSPARENT
# The team's fruit (TeamCrest.fruit_for), or "" for a plain chest.
var crest_fruit: String = ""
var crest_preset: Dictionary = {}


func _draw() -> void:
	# Base fill across the whole texture so cap disks aren't transparent.
	draw_rect(Rect2(0, 0, IMG_W, IMG_H), jersey_color, true)
	draw_rect(TOP_CAP_RECT, collar_color, true)
	draw_rect(Rect2(0, 0, IMG_W, YOKE_BOTTOM_PX), yoke_color, true)
	# Stripes paint in array order, clipped to the side region so none reaches
	# the caps below it.
	var side_px := Vector2(IMG_W, SIDE_V_MAX_PX)
	var side_rect := PackedVector2Array([Vector2.ZERO, Vector2(side_px.x, 0.0), side_px,
			Vector2(0.0, side_px.y)])
	var back_u: float = float(BACK_CENTER_X) / IMG_W
	for stripe: Dictionary in stripes:
		var side: Dictionary = UniformPaint.jersey_side_stripe(stripe)
		if stripe.has("fill_below"):
			_fill_side(StripeOutline.below(side, back_u), side_px, side_rect, stripe.fill_below)
		for piece: PackedVector2Array in StripeOutline.of(side, BACK_HEIGHT_M, BACK_GIRTH_M,
				back_u):
			_fill_side(piece, side_px, side_rect, stripe.color)

	var yoke_bottom_m: float = float(YOKE_BOTTOM_PX) / PX_PER_M.y
	draw_back_lettering(self, player_name, jersey_number, text_color, text_stroke,
			float(BACK_CENTER_X), PX_PER_M, yoke_bottom_m, NAME_MAX_WIDTH_M)
	if not crest_fruit.is_empty():
		draw_chest_crest(self, crest_fruit, crest_preset, float(FRONT_CENTER_X), PX_PER_M,
				yoke_bottom_m)


# A polygon in side UV, filled where it lies on the side region.
func _fill_side(uv: PackedVector2Array, side_px: Vector2, side_rect: PackedVector2Array,
		color: Color) -> void:
	for i: int in uv.size():
		uv[i] *= side_px
	for clipped: PackedVector2Array in Geometry2D.intersect_polygons(uv, side_rect):
		draw_colored_polygon(clipped, color)


# A chest's crest, centred on `center_x` px with its top CREST_YOKE_GAP_M under
# the yoke line (`yoke_bottom_m` down from the top), drawn in metres through
# `px_per_m` so it lands round on a texture whose texels are not square. The
# goalie's chest draws through this too.
static func draw_chest_crest(canvas: CanvasItem, fruit: String, preset: Dictionary,
		center_x: float, px_per_m: Vector2, yoke_bottom_m: float) -> void:
	var r: Vector2 = px_per_m * CREST_RADIUS_M
	var center_m: float = yoke_bottom_m + CREST_YOKE_GAP_M + CREST_RADIUS_M * _CREST_REACH
	TeamCrest.draw(canvas, fruit, Transform2D(Vector2(r.x, 0.0), Vector2(0.0, r.y),
			Vector2(center_x, center_m * px_per_m.y)), preset)


# A back's name and number, laid out in metres down from the top of the back
# (`yoke_bottom_m` is where the yoke ends) and centred on `center_x` px, the name
# fitted to `name_max_m` across. The goalie's back letters through this too, so
# every player's back reads alike.
static func draw_back_lettering(canvas: CanvasItem, p_name: String, number: int, color: Color,
		stroke: Color, center_x: float, px_per_m: Vector2, yoke_bottom_m: float,
		name_max_m: float) -> void:
	var name_top_m: float = yoke_bottom_m + NAME_GAP_M
	if not p_name.is_empty():
		_draw_centered(canvas, NAME_FONT, p_name.to_upper(), NAME_EM_M, name_top_m,
				center_x, px_per_m, color, stroke, name_max_m)
	_draw_centered(canvas, FONT, str(number), NUMBER_EM_M,
			name_top_m + NAME_EM_M + NUMBER_GAP_M, center_x, px_per_m, color, stroke, INF)


# How `s` is set to fit `max_px` across at `font_size`: x the size to set it at,
# y the horizontal squeeze. A string that fits is (font_size, 1); a longer one
# is squeezed, and past NAME_MIN_SQUEEZE made smaller too.
static func fit_lettering(font: Font, s: String, font_size: int, max_px: float) -> Vector2:
	var width: float = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if width <= max_px:
		return Vector2(font_size, 1.0)
	var squeeze: float = max_px / width
	if squeeze >= NAME_MIN_SQUEEZE:
		return Vector2(font_size, squeeze)
	var smaller: int = maxi(1, floori(font_size * squeeze / NAME_MIN_SQUEEZE))
	width = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, smaller).x
	return Vector2(smaller, minf(1.0, max_px / width))


# A string at `pos` (its baseline), bordered by `stroke` when that is not
# transparent. Every sweater's lettering draws through here, so a stroke is the
# same weight relative to its glyphs on the back, the name and the shoulders.
static func draw_lettering(canvas: CanvasItem, font: Font, pos: Vector2, s: String,
		font_size: int, color: Color, stroke: Color) -> void:
	if stroke.a > 0.0:
		# The fill drawn after it covers the outline's inner side.
		canvas.draw_string_outline(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
				roundi(STROKE_SIZE_EM * font_size), stroke)
	canvas.draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


# `em_m` tall with its em box's top `top_m` below the top of the back. The text
# is set at the vertical texel density and squeezed or widened to the
# horizontal one, so it is the shape the font draws once on the body, its
# stroke included; then fitted to `max_width_m` (fit_lettering), a smaller
# setting centred in the em box it would have filled.
static func _draw_centered(canvas: CanvasItem, font: Font, s: String, em_m: float,
		top_m: float, center_x: float, px_per_m: Vector2, color: Color, stroke: Color,
		max_width_m: float) -> void:
	var em_px: int = roundi(em_m * px_per_m.y)
	var fit: Vector2 = fit_lettering(font, s, em_px, max_width_m * px_per_m.y)
	var size: int = int(fit.x)
	var stretch: float = px_per_m.x / px_per_m.y * fit.y
	var width: float = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pos := Vector2(center_x / stretch - width * 0.5,
			top_m * px_per_m.y + (em_px - size) * 0.5 + font.get_ascent(size))
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2(stretch, 1.0))
	draw_lettering(canvas, font, pos, s, size, color, stroke)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)


func update_jersey(
		j_color: Color, j_yoke: Color, j_collar: Color, j_stripes: Array[Dictionary],
		p_name: String, p_number: int, t_color: Color, t_stroke: Color) -> void:
	jersey_color = j_color
	yoke_color = j_yoke
	collar_color = j_collar
	stripes = j_stripes
	player_name = p_name
	jersey_number = p_number
	text_color = t_color
	text_stroke = t_stroke
	queue_redraw()


# The torso's material over a JerseyDecal viewport's texture. The torso's rings
# start U=0 at +Z, turned by its half-facet phase, and runs CCW; UV_OFFSET_X
# lands the decal's back-centre column on the skater's back.
static func torso_material(tex: Texture2D) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.roughness = UniformPaint.ROUGH_CLOTH
	mat.uv1_offset = Vector3(UV_OFFSET_X, 0.0, 0.0)
	BodyRim.apply(mat)
	return mat


func update_crest(fruit: String, preset: Dictionary) -> void:
	crest_fruit = fruit
	crest_preset = preset
	queue_redraw()
