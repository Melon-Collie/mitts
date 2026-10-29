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
