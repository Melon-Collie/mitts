extends GutTest

# The goalie paints a kit's jersey stripes flat (KeeperGearView._jersey_stripes):
# a peaked stripe at its pos, and its fill below as a band from it past the hem.


func test_a_fill_below_is_a_band_from_the_stripe_past_the_hem() -> void:
	var height_m: float = UniformPaint.JERSEY_STRIPE_DESIGN_HEIGHT_M
	var stripes: Array = KeeperGearView._jersey_stripes([{"pos": 0.8, "width": 0.1,
			"color": Color.GREEN, "fill_below": Color.RED,
			"peak": {"depth": -0.1, "count": 4, "u": 0.0}}], height_m)
	assert_eq(stripes.size(), 2, "the fill, then the stripe over it")
	var fill: Dictionary = stripes[0]
	assert_eq(fill.color, Color.RED)
	assert_almost_eq(float(fill.pos) - float(fill.width) * 0.5, 0.8, 1e-6, "from the stripe")
	assert_gt(float(fill.pos) + float(fill.width) * 0.5, 1.0, "past the hem")
	assert_eq(stripes[1].color, Color.GREEN)
	assert_almost_eq(float(stripes[1].pos), 0.8, 1e-6, "the stripe flat at its pos")
