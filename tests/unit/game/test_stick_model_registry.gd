extends GutTest

# The stick-pattern catalogue is wire data — the pattern index rides the packed
# GearStyleConfig code and the zone colours the tape code. Worth pinning: every
# band is a well-formed span that fits a shader slot and the shortest cut, a
# pattern's bands match the band zones it paints, its defaults are colours the
# player may wear, a forged index reads as the house stick, and the white alias
# draws the same as Solid painted white.

# The flex shader carries two band slots; a third band would silently not
# render, so the catalogue must never author one.
const _SHADER_BAND_SLOTS: int = 2
# Bands are placed in metres from an anchor end, so a span must end within
# the shortest cut's shaft (a 5'7" short-stick build renders ≈1.1 m) or the
# design silently loses its band on small builds.
const _SHORTEST_SHAFT_M: float = 1.0


func test_every_band_is_well_formed() -> void:
	for pattern: int in StickModelRegistry.count():
		var bands: Array = StickModelRegistry.bands(pattern)
		assert_lte(bands.size(), _SHADER_BAND_SLOTS, "pattern %d fits the shader" % pattern)
		for band: Dictionary in bands:
			assert_lt(float(band["from_m"]), float(band["to_m"]), "pattern %d band runs forward" % pattern)
			assert_lte(float(band["to_m"]), _SHORTEST_SHAFT_M,
					"pattern %d band fits the shortest cut" % pattern)
			assert_true(int(band["anchor"]) in [StickModelRegistry.ANCHOR_BUTT,
					StickModelRegistry.ANCHOR_BLADE], "pattern %d band anchor is an end" % pattern)


func test_band_zones_match_the_bands() -> void:
	var band_zones: Array[int] = [StickModelRegistry.Zone.BAND1, StickModelRegistry.Zone.BAND2]
	for pattern: int in StickModelRegistry.count():
		var bands: int = StickModelRegistry.bands(pattern).size()
		for i: int in band_zones.size():
			assert_eq(StickModelRegistry.has_zone(pattern, band_zones[i]), i < bands,
					"pattern %d paints band %d only if it has one" % [pattern, i + 1])


func test_defaults_are_colours_the_player_may_wear() -> void:
	var none: Array[String] = []
	for pattern: int in StickModelRegistry.count():
		var defaults: Array[int] = StickModelRegistry.default_zones(pattern)
		assert_eq(defaults.size(), StickModelRegistry.ZONE_COUNT)
		for zone: int in StickModelRegistry.ZONE_COUNT:
			assert_true(CosmeticUnlocks.is_available(CosmeticUnlocks.STICK_PAINT,
					defaults[zone], none), "pattern %d zone %d default is free" % [pattern, zone])


func test_the_house_stick_is_black_with_a_white_wordmark() -> void:
	var solid: Array[int] = StickModelRegistry.default_zones(StickModelRegistry.PATTERN_SOLID)
	assert_eq(solid[StickModelRegistry.Zone.SHAFT], TapeColorRegistry.BLACK_INDEX)
	assert_eq(solid[StickModelRegistry.Zone.WORDMARK], TapeColorRegistry.WHITE_INDEX)
	assert_eq(solid[StickModelRegistry.Zone.BLADE], TapeColorRegistry.BLACK_INDEX)


func test_the_white_alias_is_not_listed_and_unaliases_to_painted_solid() -> void:
	assert_does_not_have(StickModelRegistry.listed(), StickModelRegistry.PATTERN_SOLID_WHITE)
	var gear := GearStyleConfig.new()
	gear.stick_model = StickModelRegistry.PATTERN_SOLID_WHITE
	var tape := StickTapeConfig.new()
	StickModelRegistry.unalias(gear, tape)
	assert_eq(gear.stick_model, StickModelRegistry.PATTERN_SOLID)
	assert_true(tape.paint_custom)
	assert_eq(tape.paint[StickModelRegistry.Zone.SHAFT], TapeColorRegistry.WHITE_INDEX)
	var plain := GearStyleConfig.new()
	var untouched := StickTapeConfig.new()
	StickModelRegistry.unalias(plain, untouched)
	assert_false(untouched.paint_custom, "any other pattern is left alone")


func test_zone_colours_follow_the_paint_once_painted() -> void:
	var tape := StickTapeConfig.new()
	assert_eq(StickModelRegistry.zone_colors(StickModelRegistry.PATTERN_KICK, tape),
			StickModelRegistry.default_zones(StickModelRegistry.PATTERN_KICK))
	var painted: Array[int] = [TapeColorRegistry.WHITE_INDEX, TapeColorRegistry.TEAM_SECOND_INDEX,
			0, TapeColorRegistry.BLACK_INDEX, TapeColorRegistry.WHITE_INDEX]
	tape.set_paint(painted)
	assert_eq(StickModelRegistry.zone_colors(StickModelRegistry.PATTERN_KICK, tape), painted)


func test_every_pattern_has_a_name_and_some_paint() -> void:
	for pattern: int in StickModelRegistry.count():
		assert_true(String(StickModelRegistry.name_key(pattern)).begins_with("STICK_PATTERN_"))
		var paints_something: bool = false
		for zone: int in StickModelRegistry.ZONE_COUNT:
			paints_something = paints_something or StickModelRegistry.has_zone(pattern, zone)
		assert_true(paints_something, "pattern %d has a zone to paint" % pattern)
	assert_eq(StickModelRegistry.ZONE_NAME_KEYS.size(), StickModelRegistry.ZONE_COUNT)


func test_a_forged_index_reads_as_the_house_stick() -> void:
	assert_false(StickModelRegistry.is_valid(-1))
	assert_false(StickModelRegistry.is_valid(StickModelRegistry.count()))
	for pattern: int in [-1, StickModelRegistry.count(), 99]:
		assert_eq(StickModelRegistry.default_zones(pattern),
				StickModelRegistry.default_zones(StickModelRegistry.PATTERN_SOLID))
		assert_eq(StickModelRegistry.bands(pattern).size(), 0)
