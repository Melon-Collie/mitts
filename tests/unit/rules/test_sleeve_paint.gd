extends GutTest

# A kit's sleeve (SleevePaint) is the one place an arm's paint is authored. The
# two-segment form older kits wrote is read into it with every stripe where it
# physically sat (the forearm's group brought up to the elbow), and the sleeve
# is cut back into segments for the bodies that paint the arm in two.


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


func test_segments_paint_each_stripe_where_the_sleeve_has_it() -> void:
	# A stripe straddling the elbow shows on both segments, each its own part.
	var sleeve := {"base": Color.RED, "stripes": [{
		"pos": SleevePaint.pos_of(SleevePaint.ELBOW_M), "width": 0.1, "color": Color.BLUE}]}
	var upper: Dictionary = SleevePaint.segment(sleeve, true)
	var lower: Dictionary = SleevePaint.segment(sleeve, false)
	assert_eq(upper.stripes.size(), 1)
	assert_eq(lower.stripes.size(), 1)
	assert_gt(float(upper.stripes[0].pos), 0.5, "the upper arm's part is at its elbow end")
	assert_lt(float(lower.stripes[0].pos), 0.5, "the forearm's part is at its elbow end")
	assert_eq(upper.base, Color.RED)


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


func test_a_fill_below_reaches_the_forearm_as_a_band() -> void:
	var sleeve := {"base": Color.WHITE, "stripes": [{"pos": SleevePaint.pos_of(0.35),
			"width": 0.03, "color": Color.BLUE, "fill_below": Color.RED,
			"peak": {"depth": -0.09, "count": 2, "u": 0.5}}]}
	var lower: Dictionary = SleevePaint.segment(sleeve, false)
	assert_eq(lower.stripes.size(), 2, "the fill, then the stripe over it")
	assert_eq(lower.stripes[0].color, Color.RED)
	assert_gt(float(lower.stripes[0].pos) + float(lower.stripes[0].width) * 0.5, 1.0,
			"the fill runs to the segment's end")
	assert_eq(SleevePaint.segment(sleeve, true).stripes.size(), 0,
			"and none of it reaches the upper arm")
