extends GutTest

# The stick catalogue is wire data — the model index rides the packed
# GearStyleConfig code — and rows are graphics painted in the player's three
# stick colors, never fixed hues. Worth pinning: the table stays index-aligned
# with its name keys, row 0 is still the house MITTS stick, every band is a
# well-formed span that fits a shader slot and the shortest cut and paints
# from a real slot, every retired row stands in a pickable one, a forged index
# reads as the house stick instead of crashing the paint seam, and no two
# pickable rows are the same design wearing two names.

# The flex shader carries two band slots; a third band would silently not
# render, so the catalogue must never author one.
const _SHADER_BAND_SLOTS: int = 2
# Bands are placed in metres from an anchor end, so a span must end within
# the shortest cut's shaft (a 5'7" short-stick build renders ≈1.1 m) or the
# design silently loses its band on small builds.
const _SHORTEST_SHAFT_M: float = 1.0
const _SLOTS: Array[int] = [StickModelRegistry.Slot.PRIMARY,
		StickModelRegistry.Slot.SECONDARY, StickModelRegistry.Slot.SHAFT]


func test_table_is_index_aligned_with_its_names() -> void:
	assert_eq(StickModelRegistry.NAME_KEYS.size(), StickModelRegistry.count(),
			"every stick model is named")


func test_row_zero_is_the_house_stick() -> void:
	var stealth: int = StickModelRegistry.STICK_STEALTH
	assert_eq(StickModelRegistry.brand_slot(stealth), StickModelRegistry.Slot.PRIMARY,
			"the stock wordmark is the graphic's primary")
	assert_eq(StickModelRegistry.bands(stealth).size(), 0, "the stock shaft has no bands")
	assert_true(stealth in StickModelRegistry.pickable())


func test_every_band_is_a_well_formed_span() -> void:
	for model: int in StickModelRegistry.count():
		var bands: Array = StickModelRegistry.bands(model)
		assert_true(bands.size() <= _SHADER_BAND_SLOTS,
				"model %d fits the shader's band slots" % model)
		assert_true(StickModelRegistry.brand_slot(model) in _SLOTS,
				"model %d wordmark paints from a slot" % model)
		for band: Dictionary in bands:
			assert_lt(float(band["from_m"]), float(band["to_m"]),
					"model %d band runs from before to" % model)
			assert_gte(float(band["from_m"]), 0.0, "model %d band starts on the shaft" % model)
			assert_lte(float(band["to_m"]), _SHORTEST_SHAFT_M,
					"model %d band fits the shortest cut" % model)
			assert_true(int(band["anchor"]) in [StickModelRegistry.ANCHOR_BUTT,
					StickModelRegistry.ANCHOR_BLADE], "model %d band anchor is an end" % model)
			assert_true(int(band["slot"]) in _SLOTS, "model %d band paints from a slot" % model)


# A band in the shaft's own color would be invisible, so bands paint only from
# the graphic's two colors.
func test_bands_never_paint_in_the_shaft_color() -> void:
	for model: int in StickModelRegistry.count():
		for band: Dictionary in StickModelRegistry.bands(model):
			assert_ne(int(band["slot"]), StickModelRegistry.Slot.SHAFT,
					"model %d band would vanish into the shaft" % model)


func test_slots_paint_their_own_color() -> void:
	var shaft := Color.BLACK
	var primary := Color.RED
	var secondary := Color.BLUE
	assert_eq(StickModelRegistry.slot_color(StickModelRegistry.Slot.PRIMARY,
			shaft, primary, secondary), primary)
	assert_eq(StickModelRegistry.slot_color(StickModelRegistry.Slot.SECONDARY,
			shaft, primary, secondary), secondary)
	assert_eq(StickModelRegistry.slot_color(StickModelRegistry.Slot.SHAFT,
			shaft, primary, secondary), shaft)


func test_uses_secondary_matches_the_layout() -> void:
	for model: int in StickModelRegistry.count():
		var swatch: Array[Color] = StickModelRegistry.swatch_colors(model,
				Color.BLACK, Color.RED, Color.BLUE)
		assert_eq(StickModelRegistry.uses_secondary(model), Color.BLUE in swatch,
				"model %d says whether the secondary shows" % model)


func test_swatches_lead_with_the_shaft() -> void:
	for model: int in StickModelRegistry.count():
		var swatch: Array[Color] = StickModelRegistry.swatch_colors(model,
				Color.BLACK, Color.RED, Color.BLUE)
		assert_gt(swatch.size(), 1, "model %d has a readable swatch strip" % model)
		assert_eq(swatch[0], Color.BLACK, "model %d swatch leads with the shaft" % model)


func test_retired_models_stand_in_a_pickable_one() -> void:
	var pickable: Array[int] = StickModelRegistry.pickable()
	for model: int in StickModelRegistry.count():
		if StickModelRegistry.is_retired(model):
			assert_false(model in pickable, "retired model %d is not offered" % model)
			assert_true(StickModelRegistry.worn(model) in pickable,
					"retired model %d stands in a pickable one" % model)
		else:
			assert_eq(StickModelRegistry.worn(model), model)
			assert_true(model in pickable, "model %d is offered" % model)


func test_no_two_pickable_models_are_the_same_design() -> void:
	var seen: Array[String] = []
	for model: int in StickModelRegistry.pickable():
		var key: String = "%s %s" % [StickModelRegistry.brand_slot(model),
				StickModelRegistry.bands(model)]
		assert_false(key in seen, "stick model %d is a duplicate design" % model)
		seen.append(key)


func test_forged_models_read_as_the_house_stick() -> void:
	assert_false(StickModelRegistry.is_valid(-1))
	assert_false(StickModelRegistry.is_valid(StickModelRegistry.count()))
	for model: int in [-1, -999, 99]:
		assert_eq(StickModelRegistry.brand_slot(model), StickModelRegistry.Slot.PRIMARY,
				"a forged model carries the house wordmark")
		assert_eq(StickModelRegistry.bands(model).size(), 0,
				"a forged model paints no bands")
