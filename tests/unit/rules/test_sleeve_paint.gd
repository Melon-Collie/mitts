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


func _peaked(depth: float, count: int, first_u: float) -> Dictionary:
	return {"pos": 0.3, "width": 0.1, "color": Color.BLUE,
			"peak": {"depth": depth, "count": count, "u": first_u}}


# The outline's top or bottom edge at `u`, by its straight runs.
func _edge_at(outline: PackedVector2Array, u: float, top: bool) -> float:
	var half: int = outline.size() / 2
	var edge: PackedVector2Array = outline.slice(0, half) if top else outline.slice(half)
	if not top:
		edge.reverse()
	for i: int in edge.size() - 1:
		if u >= edge[i].x and u <= edge[i + 1].x:
			return lerpf(edge[i].y, edge[i + 1].y, (u - edge[i].x) / (edge[i + 1].x - edge[i].x))
	return NAN


func test_a_flat_stripe_is_a_band_round_the_whole_arm() -> void:
	var outline: PackedVector2Array = SleevePaint.stripe_outline(
			{"pos": 0.3, "width": 0.1, "color": Color.BLUE})
	assert_eq(outline, PackedVector2Array([Vector2(0.0, 0.25), Vector2(1.0, 0.25),
			Vector2(1.0, 0.35), Vector2(0.0, 0.35)]))


func test_a_peaked_stripe_drops_its_depth_at_each_peak_and_none_between() -> void:
	var outline: PackedVector2Array = SleevePaint.stripe_outline(_peaked(0.2, 2, 0.5))
	var at_peak: float = (_edge_at(outline, 0.5, true) + _edge_at(outline, 0.5, false)) * 0.5
	var between: float = (_edge_at(outline, 0.25, true) + _edge_at(outline, 0.25, false)) * 0.5
	assert_almost_eq(at_peak, 0.5, 1e-4, "the centre line is depth below pos on the outside")
	assert_almost_eq(between, 0.3, 1e-4, "and back at pos midway to the next peak")
	var wrapped: float = (_edge_at(outline, 0.0, true) + _edge_at(outline, 0.0, false)) * 0.5
	assert_almost_eq(wrapped, 0.5, 1e-4, "the second peak sits half way round, on the seam")


func test_a_peaked_stripe_holds_its_width_square_to_the_line() -> void:
	var stripe: Dictionary = _peaked(0.25, 1, 0.5)
	var outline: PackedVector2Array = SleevePaint.stripe_outline(stripe)
	# Down a slope, in metres: the vertical gap times the cosine of the slope.
	var run_m: float = 0.5 * SleevePaint.GIRTH_M
	var drop_m: float = 0.25 * SleevePaint.LENGTH_M
	var gap_m: float = (_edge_at(outline, 0.3, false) - _edge_at(outline, 0.3, true)) \
			* SleevePaint.LENGTH_M
	assert_almost_eq(gap_m * run_m / sqrt(run_m * run_m + drop_m * drop_m),
			0.1 * SleevePaint.LENGTH_M, 1e-5)


func test_the_registry_reads_a_sleeve_stripes_peak() -> void:
	var kit: Dictionary = TeamColorRegistry._parse_kit({"sleeve": {"base": "#FFFFFF",
			"stripes": [{"pos": 0.0, "width": 0.4, "color": "#000000", "peak": {"depth": 0.2}},
					{"pos": 0.6, "width": 0.1, "color": "#000000"}]}})
	var stripes: Array = kit.sleeve.stripes
	assert_eq(stripes[0].peak, {"depth": 0.2, "count": 1, "u": 0.5},
			"count and u default to one peak on the outside")
	assert_false(stripes[1].has("peak"), "a flat stripe carries no peak")
