extends GutTest

# CosmeticUnlocks — a colour slot offers the team's two colours, white and black
# for free, anything else only as a per-slot reward, and an unavailable pick is
# worn as the team colour.

const _FREE: Array[int] = [TapeColorRegistry.TEAM_INDEX, TapeColorRegistry.WHITE_INDEX,
		TapeColorRegistry.BLACK_INDEX, TapeColorRegistry.TEAM_SECOND_INDEX]
const _RED: int = 3


func test_every_colour_slot_offers_exactly_the_free_four_without_rewards() -> void:
	var none: Array[String] = []
	var want: Array[int] = _FREE.duplicate()
	want.sort()
	for slot: String in CosmeticUnlocks.COLOR_SLOTS:
		var listed: Array[int] = CosmeticUnlocks.available(slot, none)
		listed.sort()
		assert_eq(listed, want, "%s offers the free four" % slot)


func test_a_colour_without_a_reward_is_never_available() -> void:
	var every: Array[String] = CosmeticUnlocks.every_banner()
	for slot: String in CosmeticUnlocks.COLOR_SLOTS:
		for option: int in TapeColorRegistry.count():
			if _FREE.has(option) or not CosmeticUnlocks.reward_banner(slot, option).is_empty():
				continue
			assert_false(CosmeticUnlocks.is_available(slot, option, every),
					"%s %d has no reward and is not free" % [slot, option])


func test_reward_rows_name_a_slot_a_colour_and_a_banner() -> void:
	var banners: Array[String] = CosmeticUnlocks.every_banner()
	var seen: Dictionary = {}
	for row: Dictionary in CosmeticUnlocks.REWARDS:
		var slot: String = String(row["slot"])
		var option: int = int(row["option"])
		assert_has(CosmeticUnlocks.SLOTS, slot)
		assert_between(option, 0, CosmeticUnlocks.option_count(slot) - 1,
				"%s option %d" % [slot, option])
		assert_false(CosmeticUnlocks.is_free(slot, option), "a reward must not already be free")
		assert_has(banners, String(row["banner"]))
		var key: String = "%s/%d" % [slot, option]
		assert_false(seen.has(key), "two rewards for %s" % key)
		seen[key] = true
	assert_eq(seen.size(), CosmeticUnlocks.REWARDS.size(), "every reward row was checked")


func test_an_unavailable_tape_pick_is_worn_as_the_team_colour() -> void:
	var none: Array[String] = []
	var tape := StickTapeConfig.new(_RED, StickTapeConfig.Span.TOE,
			TapeColorRegistry.WHITE_INDEX, StickTapeConfig.KnobStyle.FULL)
	var worn := StickTapeConfig.from_code(CosmeticUnlocks.worn_tape_code(tape.to_code(), none))
	assert_eq(worn.blade_color, TapeColorRegistry.TEAM_INDEX)
	assert_eq(worn.knob_color, TapeColorRegistry.WHITE_INDEX, "a free pick is kept")
	assert_eq(worn.span, StickTapeConfig.Span.TOE, "the rest of the job is kept")
	assert_eq(worn.knob_style, StickTapeConfig.KnobStyle.FULL)


func test_unavailable_laces_are_worn_as_the_team_colour() -> void:
	var none: Array[String] = []
	var gear := GearStyleConfig.from_code(GearStyleConfig.DEFAULT_CODE)
	gear.lace_color = _RED
	gear.hair_style = HairStyleRegistry.HAIR_SHORT
	gear.helmet_face = GearModelRegistry.FACE_NONE + 1
	var worn := GearStyleConfig.from_code(CosmeticUnlocks.worn_gear_code(gear.to_code(), none))
	assert_eq(worn.lace_color, TapeColorRegistry.TEAM_INDEX)
	assert_eq(worn.helmet_face, gear.helmet_face, "the rest of the gear is kept")
	gear.lace_color = TapeColorRegistry.BLACK_INDEX
	assert_eq(CosmeticUnlocks.worn_gear_code(gear.to_code(), none), gear.to_code())


func test_the_second_team_slot_resolves_to_the_kit_secondary() -> void:
	var primary := Color.RED
	var secondary := Color.BLUE
	assert_eq(TapeColorRegistry.resolve(TapeColorRegistry.TEAM_SECOND_INDEX, primary, secondary), secondary)
	assert_eq(TapeColorRegistry.resolve(TapeColorRegistry.TEAM_INDEX, primary, secondary), primary)
	assert_eq(TapeColorRegistry.resolve(999, primary, secondary), primary, "out of range reads as team")
	assert_eq(TapeColorRegistry.NAME_KEYS.size(), TapeColorRegistry.count())


func test_the_signature_tape_jobs_are_banner_rewards() -> void:
	var none: Array[String] = []
	var spans: Array[int] = CosmeticUnlocks.available(CosmeticUnlocks.TAPE_SPAN, none)
	assert_eq(spans.size(), CosmeticUnlocks.FREE_SPANS.size(), "the original six are free")
	assert_does_not_have(spans, StickTapeConfig.Span.SPACED)
	assert_eq(CosmeticUnlocks.reward_banner(CosmeticUnlocks.TAPE_SPAN,
			StickTapeConfig.Span.SPACED), "sniper")
	assert_eq(CosmeticUnlocks.reward_banner(CosmeticUnlocks.TAPE_SPAN,
			StickTapeConfig.Span.BOTTOM_STRIP), "playmaker")
	var sniper: Array[String] = ["sniper"]
	assert_has(CosmeticUnlocks.available(CosmeticUnlocks.TAPE_SPAN, sniper),
			StickTapeConfig.Span.SPACED)
	assert_eq(CosmeticUnlocks.locked(CosmeticUnlocks.TAPE_SPAN, sniper),
			[StickTapeConfig.Span.BOTTOM_STRIP] as Array[int])


func test_an_unearned_tape_job_is_worn_heel_to_mid() -> void:
	var job := StickTapeConfig.new(TapeColorRegistry.BLACK_INDEX,
			StickTapeConfig.Span.BOTTOM_STRIP, TapeColorRegistry.TEAM_INDEX,
			StickTapeConfig.KnobStyle.KNOB, TapeColorRegistry.WHITE_INDEX)
	var none: Array[String] = []
	var worn := StickTapeConfig.from_code(CosmeticUnlocks.worn_tape_code(job.to_code(), none))
	assert_eq(worn.span, StickTapeConfig.Span.HEEL_TO_MID)
	assert_eq(worn.blade_color, TapeColorRegistry.BLACK_INDEX)
	var playmaker: Array[String] = ["playmaker"]
	var earned := StickTapeConfig.from_code(
			CosmeticUnlocks.worn_tape_code(job.to_code(), playmaker))
	assert_eq(earned.span, StickTapeConfig.Span.BOTTOM_STRIP)
	assert_eq(earned.toe_color, TapeColorRegistry.WHITE_INDEX)
	job.toe_color = 3
	assert_eq(StickTapeConfig.from_code(CosmeticUnlocks.worn_tape_code(job.to_code(),
			playmaker)).toe_color, TapeColorRegistry.TEAM_INDEX, "the toe follows the colour rules")


func test_unavailable_stick_paint_is_worn_as_the_team_colour() -> void:
	var none: Array[String] = []
	var tape := StickTapeConfig.new()
	tape.set_paint([_RED, TapeColorRegistry.WHITE_INDEX, TapeColorRegistry.TEAM_SECOND_INDEX,
			_RED, TapeColorRegistry.BLACK_INDEX])
	var worn := StickTapeConfig.from_code(CosmeticUnlocks.worn_tape_code(tape.to_code(), none))
	var expected: Array[int] = [TapeColorRegistry.TEAM_INDEX, TapeColorRegistry.WHITE_INDEX,
			TapeColorRegistry.TEAM_SECOND_INDEX, TapeColorRegistry.TEAM_INDEX,
			TapeColorRegistry.BLACK_INDEX]
	assert_true(worn.paint_custom)
	assert_eq(worn.paint, expected)
	var unpainted := StickTapeConfig.new()
	assert_eq(CosmeticUnlocks.worn_tape_code(unpainted.to_code(), none), unpainted.to_code(),
			"an unpainted stick stays on its pattern's defaults")
