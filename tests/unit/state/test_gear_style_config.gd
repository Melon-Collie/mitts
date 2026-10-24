extends GutTest

# GearStyleConfig is wire data (the packed code rides the join and spawn
# payloads), so the invariants worth pinning are the wire ones: every legal
# pick round-trips through the code exactly, garbage coerces to a legal look
# instead of being trusted, the default code decodes to the pre-customization
# kit (stock black skates, kit-colored gloves), and a save written before
# models existed lands on a design rather than on stock gear.


func test_default_decodes_to_the_kit_look() -> void:
	var config := GearStyleConfig.new()
	assert_eq(config.to_code(), GearStyleConfig.DEFAULT_CODE, "untouched look packs to default")
	assert_eq(config.skate_model, GearModelRegistry.SKATE_BLACKOUT, "skates default all-black")
	assert_eq(config.glove_model, GearModelRegistry.GLOVE_TEAM, "gloves default to the kit")
	assert_eq(config.lace_color, GearStyleConfig.LACE_DEFAULT_INDEX, "laces default white")
	assert_eq(config.stick_model, StickModelRegistry.STICK_STEALTH,
			"the stick defaults to the house model")
	assert_eq(config.helmet_face, GearModelRegistry.FACE_NONE, "the face defaults bare")
	assert_eq(config.hair_style, HairStyleRegistry.HAIR_SHORT, "hair defaults short")
	assert_eq(config.facial_hair, HairStyleRegistry.FACIAL_NONE, "and no facial hair")
	assert_eq(config.hair_color, 0, "in the first palette colour")
	assert_eq(config.jersey_tuck, GearModelRegistry.TUCK_NONE, "the jersey defaults loose")


func test_every_legal_pick_round_trips() -> void:
	for skate: int in GearModelRegistry.skate_count():
		for glove: int in GearModelRegistry.glove_count():
			for lace: int in TapeColorRegistry.count():
				for stick: int in StickModelRegistry.count():
					for face: int in GearModelRegistry.face_count():
						var config := GearStyleConfig.new(skate, glove, lace, stick, face)
						var back: GearStyleConfig = GearStyleConfig.from_code(config.to_code())
						assert_eq(back.skate_model, skate)
						assert_eq(back.glove_model, glove)
						assert_eq(back.lace_color, lace)
						assert_eq(back.stick_model, stick)
						assert_eq(back.helmet_face, face)


func test_every_hair_pick_round_trips_beside_the_gear() -> void:
	for hair: int in HairStyleRegistry.hair_count():
		for facial: int in HairStyleRegistry.facial_count():
			for color: int in HairStyleRegistry.color_count():
				var config := GearStyleConfig.new(GearModelRegistry.SKATE_RETRO,
						GearModelRegistry.GLOVE_PRO, 3, StickModelRegistry.count() - 1,
						GearModelRegistry.FACE_CAGE, hair, facial, color)
				var back: GearStyleConfig = GearStyleConfig.from_code(config.to_code())
				assert_eq(back.hair_style, hair)
				assert_eq(back.facial_hair, facial)
				assert_eq(back.hair_color, color)
				assert_eq(back.helmet_face, GearModelRegistry.FACE_CAGE,
						"the hair fields leave the gear fields alone")
				assert_eq(back.stick_model, StickModelRegistry.count() - 1)


# A code saved before the hair fields existed has zeros above the face field,
# and has to come back as the stock look rather than as anything a player chose.
func test_a_pre_hair_code_decodes_to_the_stock_hair() -> void:
	var old_code: int = GearModelRegistry.FACE_VISOR << 20 | GearStyleConfig.DEFAULT_CODE
	var config: GearStyleConfig = GearStyleConfig.from_code(old_code)
	assert_eq(config.helmet_face, GearModelRegistry.FACE_VISOR)
	assert_eq(config.hair_style, HairStyleRegistry.HAIR_SHORT)
	assert_eq(config.facial_hair, HairStyleRegistry.FACIAL_NONE)
	assert_eq(config.hair_color, 0)


func test_every_tuck_round_trips() -> void:
	for tuck: int in GearModelRegistry.tuck_count():
		var config := GearStyleConfig.new(GearModelRegistry.SKATE_PRO,
				GearModelRegistry.GLOVE_PRO, 3, 1, GearModelRegistry.FACE_VISOR,
				HairStyleRegistry.hair_count() - 1, 1, HairStyleRegistry.color_count() - 1, tuck)
		var back: GearStyleConfig = GearStyleConfig.from_code(config.to_code())
		assert_eq(back.jersey_tuck, tuck)
		assert_eq(back.hair_color, HairStyleRegistry.color_count() - 1,
				"the tuck field leaves the hair fields alone")


# Every code saved before the tuck existed has zeros above the hair colour, and
# those players wore the jersey loose.
func test_a_pre_tuck_code_decodes_loose() -> void:
	var old_code: int = GearStyleConfig.new(GearModelRegistry.SKATE_RETRO, 0,
			GearStyleConfig.LACE_DEFAULT_INDEX, 0, GearModelRegistry.FACE_CAGE,
			HairStyleRegistry.HAIR_SHORT, HairStyleRegistry.FACIAL_NONE,
			HairStyleRegistry.color_count() - 1).to_code()
	assert_eq(GearStyleConfig.from_code(old_code).jersey_tuck, GearModelRegistry.TUCK_NONE)


func test_garbage_codes_coerce_to_legal_looks() -> void:
	for code: int in [-1, -999, 1 << 20, 0x7FFFFFFF, 0x7FFFFFFFFF]:
		var config: GearStyleConfig = GearStyleConfig.from_code(code)
		assert_true(GearModelRegistry.is_valid_skate(config.skate_model), "skate model legal")
		assert_true(GearModelRegistry.is_valid_glove(config.glove_model), "glove model legal")
		assert_true(TapeColorRegistry.is_valid(config.lace_color), "lace color legal")
		assert_true(StickModelRegistry.is_valid(config.stick_model), "stick model legal")
		assert_true(GearModelRegistry.is_valid_face(config.helmet_face), "face option legal")
		assert_true(HairStyleRegistry.is_valid_hair(config.hair_style), "hair style legal")
		assert_true(HairStyleRegistry.is_valid_facial(config.facial_hair), "facial hair legal")
		assert_true(HairStyleRegistry.is_valid_color(config.hair_color), "hair colour legal")
		assert_true(GearModelRegistry.is_valid_tuck(config.jersey_tuck), "tuck option legal")
		# And the coerced look re-packs stably (idempotent coercion).
		var code2: int = config.to_code()
		assert_eq(GearStyleConfig.from_code(code2).to_code(), code2)
