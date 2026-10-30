class_name UniformPaint
extends Object

# Shared paint for player-body materials — the sibling of BodyRim. The skater and
# the goalie coordinators both build their solid materials, their textured ones,
# and the horizontal stripe texture every cylindrical part wears through here, so
# a change to any of the three reaches both bodies.

# Surface roughness by material, so a jersey and a helmet catch the arena lights
# the way cloth and hard plastic do.
const ROUGH_CLOTH: float = 0.9
const ROUGH_HELMET: float = 0.28   # glossy hard plastic
const ROUGH_SKATE: float = 0.42    # synthetic boot leather
const ROUGH_NYLON: float = 0.55    # the breezers' satin shell
const ROUGH_GLOVE: float = 0.6     # glove leather and nylon

# Stripe-texture layout. Godot's cylinder UV puts the curved side in the lower
# half of V and the two end caps in the upper half, so a stripe pattern is
# painted into that lower fraction and the caps are filled separately. Four
# pixels wide is enough for a horizontally-uniform band.
const CYLINDER_SIDE_V_FRACTION: float = 0.5
const STRIPE_TEX_HEIGHT_PX: int = 128
const STRIPE_TEX_WIDTH_PX: int = 4


static func solid(color: Color, roughness: float = ROUGH_CLOTH) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	BodyRim.apply(mat)
	return mat


static func textured(tex: Texture2D, roughness: float = ROUGH_CLOTH) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.roughness = roughness
	BodyRim.apply(mat)
	return mat


# The top of a sweater is three colors, each falling back to the one below it:
# the collar ring (the torso's top cap) to the yoke, and the yoke (the top of
# the shoulders) to the jersey body.
static func yoke_color(jersey: Dictionary) -> Color:
	var yoke: Variant = jersey.get("yoke")
	return yoke if yoke is Color else jersey.base


static func collar_color(jersey: Dictionary) -> Color:
	var collar: Variant = jersey.get("collar")
	return collar if collar is Color else yoke_color(jersey)


# The side height the kits' jersey stripe fractions are authored against. A band
# above the first of _STRIPE_TRIMS trims the collar and keeps its place under
# it; one below the second trims the hem and keeps its place above it; between
# them its place blends from one to the other, so a band across the chest can
# sit at any height. A sweater of another length moves each band with the edge
# it trims, at the same width.
const JERSEY_STRIPE_DESIGN_HEIGHT_M: float = 0.55
const _STRIPE_TRIMS: Vector2 = Vector2(0.25, 0.75)


# Metres down a jersey side `side_m` tall that a kit stripe's `pos` centres at.
static func jersey_stripe_centre_m(pos: float, side_m: float) -> float:
	var hem_share: float = clampf(inverse_lerp(_STRIPE_TRIMS.x, _STRIPE_TRIMS.y, pos), 0.0, 1.0)
	return pos * JERSEY_STRIPE_DESIGN_HEIGHT_M + hem_share * (side_m - JERSEY_STRIPE_DESIGN_HEIGHT_M)


# A kit jersey stripe {pos, width, color, peak?, fill_below?} as fractions of the torso side
# it paints on; a peak's depth is a height like the width.
static func jersey_side_stripe(stripe: Dictionary) -> Dictionary:
	var side_m: float = SkaterMeshBuilder.TORSO_SIDE_HEIGHT_M
	var scale: float = JERSEY_STRIPE_DESIGN_HEIGHT_M / side_m
	var centre_m: float = jersey_stripe_centre_m(float(stripe.pos), side_m)
	var side := {"pos": centre_m / side_m, "width": float(stripe.width) * scale,
			"color": stripe.color}
	if stripe.has("fill_below"):
		side.fill_below = stripe.fill_below
	if stripe.has("peak"):
		var peak: Dictionary = stripe.peak.duplicate()
		peak.depth = float(peak.depth) * scale
		side.peak = peak
	return side


# A kit polygon filled with its slanted edges anti-aliased, as canvas polygons
# are not on any renderer: a smooth hairline over each. Over an edge inside a
# stripe, between two of its pieces, the line is the stripe's own color and
# vanishes. Level and upright edges do not step and stay hard, which keeps a
# flat band crisp and a clip's straight cut from bleeding past it.
static func fill_smooth(canvas: CanvasItem, polygon: PackedVector2Array, color: Color) -> void:
	canvas.draw_colored_polygon(polygon, color)
	var n: int = polygon.size()
	for i: int in n:
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i + 1) % n]
		if absf(a.x - b.x) > 0.01 and absf(a.y - b.y) > 0.01:
			canvas.draw_line(a, b, color, 1.0, true)


# Horizontal bands across a cylinder's curved side. Each stripe is `pos` (centre,
# as a fraction of the side region) and `width` (also a fraction), so a uniform
# authored once lands at the same proportion of every part regardless of its
# real length.
static func h_stripes(base: Color, stripes: Array) -> ImageTexture:
	var img := Image.create(STRIPE_TEX_WIDTH_PX, STRIPE_TEX_HEIGHT_PX, false, Image.FORMAT_RGBA8)
	img.fill(base)
	var side_px: int = int(round(CYLINDER_SIDE_V_FRACTION * float(STRIPE_TEX_HEIGHT_PX)))
	for s: Dictionary in stripes:
		var center_px: float = float(s.pos) * float(side_px)
		var half_px: float = float(s.width) * float(side_px) * 0.5
		var y0: int = clampi(int(round(center_px - half_px)), 0, side_px)
		var y1: int = clampi(int(round(center_px + half_px)), 0, side_px)
		if y1 > y0:
			img.fill_rect(Rect2i(0, y0, STRIPE_TEX_WIDTH_PX, y1 - y0), s.color)
	return ImageTexture.create_from_image(img)
