extends GutTest

# A kit's sleeve (SleevePaint) is the one place an arm's paint is authored. The
# two-segment form older kits wrote is read into it with every stripe where it
# physically sat (the forearm's group brought up to the elbow).


func _legacy() -> Dictionary:
	return {
		"upper": {"base": Color.RED, "stripes": [
			{"pos": 0.5, "width": 0.2, "color": Color.BLUE}]},
		"lower": {"base": Color.GREEN, "stripes": [
			{"pos": 0.5, "width": 0.2, "color": Color.WHITE}]},
	}


func test_a_legacy_kit_keeps_its_upper_stripe_where_it_sat() -> void:
	var sleeve: Dictionary = SleevePaint.from_legacy(_legacy(), Color.RED)
	var upper_mid: float = SleevePaint.pos_of(SleevePaint.ELBOW_M * 0.5)
	assert_eq(SleevePaint.color_at(sleeve, upper_mid), Color.BLUE,
			"the upper arm's centred stripe stays at the upper arm's middle")
	assert_eq(sleeve.base, Color.RED, "the sleeve's base is the upper arm's")


func test_a_legacy_forearm_is_a_band_and_its_stripes_come_up_to_the_elbow() -> void:
	var sleeve: Dictionary = SleevePaint.from_legacy(_legacy(), Color.RED)
	assert_eq(SleevePaint.color_at(sleeve, SleevePaint.pos_of(SleevePaint.LENGTH_M - 0.02)),
			Color.GREEN, "a forearm of its own color is a band to the cuff")
	assert_eq(SleevePaint.color_at(sleeve, SleevePaint.pos_of(SleevePaint.ELBOW_M + 0.03)),
			Color.WHITE, "the forearm's stripes centre just below the elbow")


func test_a_shoulder_of_its_own_color_is_a_band_under_the_number() -> void:
	var sleeve: Dictionary = SleevePaint.from_legacy(_legacy(), Color.YELLOW)
	assert_eq(SleevePaint.color_at(sleeve, SleevePaint.pos_of(SleevePaint.NUMBER_CENTER_M)),
			Color.YELLOW)
	var plain: Dictionary = SleevePaint.from_legacy(_legacy(), Color.RED)
	assert_eq(SleevePaint.color_at(plain, SleevePaint.pos_of(SleevePaint.NUMBER_CENTER_M)),
			Color.RED, "a shoulder the sleeve's color adds no band")


func test_every_bundled_kit_is_a_sleeve() -> void:
	var data: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string("res://data/team_colors.json"))
	for team: Dictionary in data.teams:
		for side: String in ["home", "away"]:
			var kit: Dictionary = team[side]
			assert_true(kit.has("sleeve"), "%s %s paints its arm as one sleeve" % [team.name, side])
			assert_false(kit.has("arms"), "%s %s has no two-segment arms left" % [team.name, side])


func test_the_registry_reads_a_sleeve_stripes_peak() -> void:
	var kit: Dictionary = TeamColorRegistry._parse_kit({"sleeve": {"base": "#FFFFFF",
			"stripes": [{"pos": 0.0, "width": 0.4, "color": "#000000", "peak": {"depth": 0.2}},
					{"pos": 0.6, "width": 0.1, "color": "#000000"}]}})
	var stripes: Array = kit.sleeve.stripes
	assert_eq(stripes[0].peak, {"depth": 0.2, "count": 1, "u": 0.5},
			"count and u default to one peak on the outside")
	assert_false(stripes[1].has("peak"), "a flat stripe carries no peak")


func test_the_registry_reads_a_jersey_stripes_shape_but_not_a_socks() -> void:
	var peaked := [{"pos": 0.9, "width": 0.1, "color": "#000000", "fill_below": "#FF0000",
			"peak": {"depth": -0.1, "count": 2, "u": 0.0}}]
	var kit: Dictionary = TeamColorRegistry._parse_kit({
			"jersey": {"base": "#FFFFFF", "stripes": peaked},
			"socks": {"base": "#FFFFFF", "stripes": peaked}})
	assert_eq(kit.jersey.stripes[0].peak, {"depth": -0.1, "count": 2, "u": 0.0})
	assert_eq(kit.jersey.stripes[0].fill_below, Color.RED)
	assert_false(kit.socks.stripes[0].has("peak"), "nothing paints a sock's peak")
	assert_false(kit.socks.stripes[0].has("fill_below"), "or its fill")
	var wave: Dictionary = TeamColorRegistry._parse_kit({"jersey": {"base": "#FFFFFF",
			"stripes": [{"pos": 0.9, "width": 0.1, "color": "#000000",
					"peak": {"depth": 0.1, "count": 3, "shape": "sine"}}]}})
	assert_eq(wave.jersey.stripes[0].peak.shape, "sine")


# Whether `stripe` paints the sleeve at (u round the arm, `down_m` down it).
func _painted(stripe: Dictionary, u: float, down_m: float) -> bool:
	var at := Vector2(u, SleevePaint.pos_of(down_m))
	for piece: PackedVector2Array in SleevePaint.stripe_polygons(stripe):
		if Geometry2D.is_point_in_polygon(at, piece):
			return true
	return false


func test_a_yoke_covers_the_caps_top_and_a_round_one_runs_over_its_edge() -> void:
	var square: Dictionary = SleevePaint.yoke_cap(SleevePaint.YOKE_SQUARE, Color.RED)
	var round_cap: Dictionary = SleevePaint.yoke_cap(SleevePaint.YOKE_ROUND, Color.RED)
	# The cap's top is drawn at the sleeve's top texel (SleeveDecal.TOP_V).
	var cap_top_m: float = SleeveDecal.TOP_V * SleevePaint.LENGTH_M
	for u: float in [0.05, 0.25, 0.5, 0.75]:
		assert_true(_painted(square, u, cap_top_m), "u %.2f: a square yoke has the cap's top" % u)
		assert_false(_painted(square, u, 0.01), "u %.2f: and none of the arm under its edge" % u)
		assert_true(_painted(round_cap, u, cap_top_m), "u %.2f: a round one has it too" % u)
		assert_true(_painted(round_cap, u, 0.02), "u %.2f: and runs on over the edge" % u)
		assert_false(_painted(round_cap, u, SleevePaint.YOKE_ROUND_M + 0.004),
				"u %.2f: no further than its depth" % u)
	# The number's glyphs stand about 0.7 of their em.
	assert_lt(SleevePaint.YOKE_ROUND_M, SleevePaint.NUMBER_CENTER_M - 0.35 * SleeveDecal.NUMBER_EM_M,
			"the number sits on the sleeve below either")
