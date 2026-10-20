extends GutTest

# PlayerLook: the lobby roster's look fields round-trip, an older or forged
# entry lands on a legal look, and a bot's look comes from its card the way its
# skater's does.


func _entry_with(look: PlayerLook) -> Array:
	return [7, 0, 1, "Name", false, 12, true] + look.cosmetics_to_wire()


func test_cosmetics_round_trip_through_a_roster_entry() -> void:
	var sent := PlayerLook.new()
	sent.attributes = PlayerAttributes.new(PlayerAttributes.HEIGHT_MAX, 230, 0, 2, 0, 2)
	sent.skin_tone = SkinToneRegistry.TONES.size() - 1
	sent.tape_code = StickTapeConfig.from_code(12345).to_code()
	sent.gear_style_code = GearStyleConfig.from_code(98765).to_code()
	var got := PlayerLook.new()
	got.cosmetics_from_wire(_entry_with(sent), 7)
	assert_true(got.attributes.equals(sent.attributes))
	assert_eq(got.skin_tone, sent.skin_tone)
	assert_eq(got.tape_code, sent.tape_code)
	assert_eq(got.gear_style_code, sent.gear_style_code)


# A v76 entry stops at is_ready: everyone seats in the default look.
func test_an_entry_without_cosmetics_keeps_the_default_look() -> void:
	var got := PlayerLook.new()
	got.cosmetics_from_wire([7, 0, 1, "Name", false, 12, true], 7)
	assert_true(got.attributes.equals(PlayerAttributes.neutral()))
	assert_eq(got.skin_tone, SkinToneRegistry.DEFAULT_INDEX)
	assert_eq(got.gear_style_code, GearStyleConfig.DEFAULT_CODE)


func test_forged_cosmetics_land_on_a_legal_look() -> void:
	var got := PlayerLook.new()
	got.cosmetics_from_wire([7, 0, 1, "Name", false, 12, true,
			{"height": 999, "weight": -5}, 999, -1, -1], 7)
	assert_eq(got.skin_tone, SkinToneRegistry.clamp_index(999))
	assert_eq(got.tape_code, StickTapeConfig.from_code(-1).to_code())
	assert_eq(got.gear_style_code, GearStyleConfig.from_code(-1).to_code())
	assert_eq(got.attributes.height, PlayerAttributes.coerce_height(999))


func test_a_bot_without_a_card_is_numbered_by_its_id() -> void:
	var look: PlayerLook = PlayerLook.for_bot({}, 3, 1)
	assert_eq(look.player_name, "Bot 4")
	assert_eq(look.jersey_number, 83)
	assert_true(look.is_left_handed, "odd slots shoot left")
	assert_true(look.attributes.equals(PlayerAttributes.neutral()))


func test_a_bots_card_pins_its_look() -> void:
	var gear: int = GearStyleConfig.from_code(4242).to_code()
	var look: PlayerLook = PlayerLook.for_bot({"name": "Kowalski", "number": 44,
			"is_left_handed": false, "height": PlayerAttributes.HEIGHT_MAX, "skin": 2,
			"gear_style_code": gear}, 0, 1)
	assert_eq(look.player_name, "Kowalski")
	assert_eq(look.jersey_number, 44)
	assert_false(look.is_left_handed)
	assert_eq(look.attributes.height, PlayerAttributes.HEIGHT_MAX)
	assert_eq(look.skin_tone, 2)
	assert_eq(look.gear_style_code, gear)
	# Unpinned, the tape derives from the name, as it does when the bot spawns.
	assert_eq(look.tape_code, StickTapeConfig.from_code(
			BotIdentityRegistry.fallback_tape_code("Kowalski")).to_code())


func test_a_record_reports_its_look() -> void:
	var record := PlayerRecord.new(5, 0, false, null)
	record.player_name = "Ada"
	record.jersey_number = 9
	record.skin_tone = 3
	record.gear_style_code = GearStyleConfig.from_code(777).to_code()
	var look: PlayerLook = record.look()
	assert_eq(look.player_name, "Ada")
	assert_eq(look.jersey_number, 9)
	assert_eq(look.skin_tone, 3)
	assert_eq(look.gear_style_code, record.gear_style_code)
