extends GutTest

# UniformPaint.h_stripes paints the bands every cylindrical uniform part wears.
# It ran as two copies until this commit, and the copies had diverged — the
# skater's grew a top-cap fill and the goalie's never did.
#
# The layout is a convention nothing else states: Godot's CylinderMesh gives the
# curved side V ∈ [0, 0.5] and both end caps [0.5, 1.0], so a stripe authored at
# pos 0.5 must land at the middle of the SIDE, not the middle of the image. Get
# that wrong and every uniform in the game shifts its bands, which no assertion
# anywhere else would notice.

func _img(tex: ImageTexture) -> Image:
	return tex.get_image()


func _row(tex: ImageTexture, y: int) -> Color:
	return _img(tex).get_pixel(0, y)


func test_no_stripes_is_the_base_colour_everywhere() -> void:
	var tex: ImageTexture = UniformPaint.h_stripes(Color.RED, [])
	assert_eq(_row(tex, 0), Color.RED)
	assert_eq(_row(tex, UniformPaint.STRIPE_TEX_HEIGHT_PX - 1), Color.RED)


# The convention that matters. A band centred at 0.5 belongs at the middle of
# the side region — a quarter of the way down the image — not the middle of it.
func test_a_centred_band_lands_mid_side_region_not_mid_image() -> void:
	var tex: ImageTexture = UniformPaint.h_stripes(
			Color.RED, [{"pos": 0.5, "width": 0.2, "color": Color.BLUE}])
	var side_px: int = int(round(UniformPaint.CYLINDER_SIDE_V_FRACTION
			* float(UniformPaint.STRIPE_TEX_HEIGHT_PX)))
	assert_eq(_row(tex, side_px / 2), Color.BLUE, "centre of the band")
	assert_eq(_row(tex, 0), Color.RED, "the top of the side is still base")
	assert_eq(_row(tex, side_px - 1), Color.RED, "and so is the bottom of the side")
	assert_eq(_row(tex, side_px + 4), Color.RED,
			"the cap region is untouched without a top_cap")


func test_bands_are_painted_in_array_order_so_stacks_overprint() -> void:
	var tex: ImageTexture = UniformPaint.h_stripes(Color.RED, [
		{"pos": 0.5, "width": 0.4, "color": Color.BLUE},
		{"pos": 0.5, "width": 0.1, "color": Color.GREEN},
	])
	var side_px: int = int(round(UniformPaint.CYLINDER_SIDE_V_FRACTION
			* float(UniformPaint.STRIPE_TEX_HEIGHT_PX)))
	assert_eq(_row(tex, side_px / 2), Color.GREEN,
			"the later, narrower band sits on top — concentric shrink stacks")


func test_a_band_running_off_the_side_is_clipped_not_wrapped() -> void:
	var tex: ImageTexture = UniformPaint.h_stripes(
			Color.RED, [{"pos": 1.0, "width": 0.6, "color": Color.BLUE}])
	var side_px: int = int(round(UniformPaint.CYLINDER_SIDE_V_FRACTION
			* float(UniformPaint.STRIPE_TEX_HEIGHT_PX)))
	assert_eq(_row(tex, side_px - 1), Color.BLUE, "the part that fits is painted")
	assert_eq(_row(tex, side_px + 4), Color.RED,
			"the overflow must not bleed into the end caps")


# Both material builders go through BodyRim so a skater and a goalie catch the
# arena lights identically — the reason BodyRim exists.
func test_materials_carry_the_shared_rim() -> void:
	for mat: StandardMaterial3D in [UniformPaint.solid(Color.RED),
			UniformPaint.textured(UniformPaint.h_stripes(Color.RED, []))]:
		assert_true(mat.rim_enabled, "every body material is rim-lit")
		assert_almost_eq(mat.rim, BodyRim.STRENGTH, 1e-6)
		assert_almost_eq(mat.rim_tint, BodyRim.TINT, 1e-6)


func test_roughness_defaults_to_cloth_and_is_overridable() -> void:
	assert_almost_eq(UniformPaint.solid(Color.RED).roughness, UniformPaint.ROUGH_CLOTH, 1e-6)
	assert_almost_eq(UniformPaint.solid(Color.RED, UniformPaint.ROUGH_HELMET).roughness,
			UniformPaint.ROUGH_HELMET, 1e-6)


# The top of a sweater: the collar falls back to the yoke, the yoke to the body,
# so a kit that names neither is one color to the neck.
func test_collar_and_yoke_fall_back_down_the_sweater() -> void:
	var plain := {"base": Color.RED, "yoke": null, "collar": null}
	assert_eq(UniformPaint.yoke_color(plain), Color.RED)
	assert_eq(UniformPaint.collar_color(plain), Color.RED)
	var yoked := {"base": Color.RED, "yoke": Color.BLUE, "collar": null}
	assert_eq(UniformPaint.collar_color(yoked), Color.BLUE, "the collar follows the yoke")
	var collared := {"base": Color.RED, "yoke": Color.BLUE, "collar": Color.GREEN}
	assert_eq(UniformPaint.collar_color(collared), Color.GREEN)


# The decal's yoke ends at the torso's shoulder line, to a pixel.
func test_the_decal_yoke_ends_at_the_shoulder_line() -> void:
	assert_almost_eq(float(JerseyDecal.YOKE_BOTTOM_PX) / float(JerseyDecal.SIDE_V_MAX_PX),
			SkaterMeshBuilder.TORSO_YOKE_SIDE_FRACTION, 1.0 / float(JerseyDecal.SIDE_V_MAX_PX))


# Kits author stripe fractions against a 0.55 m sweater; on a sweater of any
# length a hem band stays as far above the hem, a collar band as far under the
# collar, and both as wide, in metres.
func test_jersey_stripes_keep_their_place_on_the_edge_they_trim() -> void:
	var design: float = UniformPaint.JERSEY_STRIPE_DESIGN_HEIGHT_M
	var side: float = SkaterMeshBuilder.TORSO_SIDE_HEIGHT_M
	var hem: Dictionary = UniformPaint.jersey_side_stripe(
			{"pos": 0.9, "width": 0.1, "color": Color.GREEN})
	assert_almost_eq((1.0 - hem.pos) * side, 0.1 * design, 1e-6, "as far above the hem")
	assert_almost_eq(hem.width * side, 0.1 * design, 1e-6, "as wide")
	var collar: Dictionary = UniformPaint.jersey_side_stripe(
			{"pos": 0.07, "width": 0.02, "color": Color.GREEN})
	assert_almost_eq(collar.pos * side, 0.07 * design, 1e-6, "as far under the collar")
	assert_almost_eq(collar.width * side, 0.02 * design, 1e-6, "as wide")
