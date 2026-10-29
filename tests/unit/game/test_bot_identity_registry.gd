extends GutTest

# BotIdentityRegistry — the curated AI roster loaded from
# res://data/bot_identities.json (with an optional editable user:// override).
# Bots spawn from these picks, so a malformed entry would either crash spawning
# or field an impossible body. Bots are host-authoritative online, so the
# host's roster is exactly what every machine plays against — which is why the
# loader COERCES every entry (normalize_entry → the PlayerAttributes
# constructor): under attributes v4 all axes are lateral, so validation is a
# clamp into the body bands rather than a legal-shape rejection.

const _RES_JSON_PATH: String = "res://data/bot_identities.json"


# Parse the bundled file directly rather than going through the registry's
# static cache so a prior test that called ensure_loaded() can't mask a
# malformed file behind a stale parse.
func _bundled_entries() -> Array:
	var file := FileAccess.open(_RES_JSON_PATH, FileAccess.READ)
	assert_not_null(file, "bundled %s must exist" % _RES_JSON_PATH)
	if file == null:
		return []
	var text: String = file.get_as_text()
	file.close()
	var data: Variant = JSON.parse_string(text)
	assert_true(data is Dictionary and data.has("identities"),
			"%s must be a Dictionary with an 'identities' array" % _RES_JSON_PATH)
	return (data as Dictionary).get("identities", [])


func test_bundled_file_has_a_full_roster() -> void:
	# Sanity floor: the lobby toggles through these without repeating, so a
	# healthy pool needs comfortably more than one 3v3 worth of bots.
	assert_gt(_bundled_entries().size(), 12,
			"expected a sizeable curated bot pool")


func test_every_bundled_body_is_inside_its_band() -> void:
	# The curated roster should be authored exactly, not silently coerced: every
	# height is a real inches value and every weight sits inside that height's
	# BMI band.
	for entry: Dictionary in _bundled_entries():
		var h: int = int(entry.get("height", PlayerAttributes.HEIGHT_MEDIUM))
		assert_between(h, PlayerAttributes.HEIGHT_MIN, PlayerAttributes.HEIGHT_MAX,
				"bot '%s' height out of range" % entry.get("name", "?"))
		var w: int = int(entry.get("weight", 0))
		assert_between(w, PlayerAttributes.weight_min(h), PlayerAttributes.weight_max(h),
				"bot '%s' weight %d outside the %d\" band" % [entry.get("name", "?"), w, h])


func test_names_and_numbers_are_unique() -> void:
	# pick_for_slot() dedupes by name, and jersey numbers should be distinct so
	# two bots on the ice never collide visually.
	var seen_names: Dictionary = {}
	var seen_numbers: Dictionary = {}
	for entry: Dictionary in _bundled_entries():
		var entry_name: String = entry.get("name", "")
		assert_false(seen_names.has(entry_name),
				"duplicate bot name '%s'" % entry_name)
		seen_names[entry_name] = true
		var number: int = int(entry.get("number", 0))
		assert_false(seen_numbers.has(number),
				"duplicate jersey number %d (%s)" % [number, entry_name])
		seen_numbers[number] = true


func test_bodies_are_distinct() -> void:
	# Identical builds make bots feel samey on the ice. The continuous body
	# plane gives the roster plenty of room for every bot to own its
	# (height, weight, gear) card.
	var seen: Dictionary = {}
	for entry: Dictionary in _bundled_entries():
		var attrs := PlayerAttributes.from_dict(entry)
		var key: String = "%d/%d/%d%d%d%d" % [attrs.height, attrs.weight,
				attrs.profile, attrs.curve, attrs.flex, attrs.length]
		assert_false(seen.has(key),
				"bot '%s' duplicates the build %s" % [entry.get("name", "?"), key])
		seen[key] = true


# ── normalize_entry: the coercion seam for editable rosters ──────────────────

func test_normalize_keeps_an_in_band_build_intact() -> void:
	var norm: Dictionary = BotIdentityRegistry.normalize_entry({
			"name": "Sniper", "number": 9, "is_left_handed": true,
			"height": 70, "weight": 172, "curve": 2})
	assert_eq(norm.name, "Sniper")
	assert_eq(norm.number, 9)
	assert_true(norm.is_left_handed)
	assert_eq(int(norm.height), 70, "in-range height must not be altered")
	assert_eq(int(norm.weight), 172, "in-band weight must not be altered")
	assert_eq(int(norm.curve), PlayerAttributes.CURVE_OPEN)


func test_normalize_coerces_out_of_band_body() -> void:
	# The old cheat vector was an illegal tier shape; the v4 equivalent is an
	# impossible body — it clamps to the nearest legal one, keeping the identity.
	var norm: Dictionary = BotIdentityRegistry.normalize_entry({
			"name": "Tank", "number": 1, "height": 99, "weight": 500})
	assert_eq(norm.name, "Tank", "identity is preserved")
	assert_eq(int(norm.height), PlayerAttributes.HEIGHT_MAX)
	assert_eq(int(norm.weight), PlayerAttributes.weight_max(PlayerAttributes.HEIGHT_MAX))
	var stringbean: Dictionary = BotIdentityRegistry.normalize_entry({
			"name": "Bean", "height": 79, "weight": 150})
	assert_eq(int(stringbean.weight), PlayerAttributes.weight_min(79),
			"underweight clamps to the band floor")


func test_normalize_defaults_missing_attributes_to_neutral() -> void:
	# A name-only entry (the "rename your bots" shape) loads as the neutral build.
	var norm: Dictionary = BotIdentityRegistry.normalize_entry({"name": "NameOnly"})
	assert_eq(int(norm.height), PlayerAttributes.HEIGHT_MEDIUM)
	assert_eq(int(norm.weight), int(PlayerAttributes.NEUTRAL_WEIGHT_LBS))
	for slot: String in ["profile", "curve", "flex", "length"]:
		assert_eq(int(norm[slot]), PlayerAttributes.GEAR_BALANCED)


func test_every_bundled_entry_has_a_valid_position() -> void:
	# 5v5 casting: each identity declares the lineup slot it suits.
	for entry: Dictionary in _bundled_entries():
		var position: String = String(entry.get("position", ""))
		assert_true(position in PlayerRules.POSITION_NAMES,
				"bot '%s' has invalid position '%s'" % [entry.get("name", "?"), position])


func test_bundled_pool_covers_every_position() -> void:
	# A full 5v5 bot game casts 10 bots across 5 positions per team; the pool
	# needs at least two of each so pick_for_slot never runs a position dry
	# on the first team.
	var counts: Dictionary = {}
	for entry: Dictionary in _bundled_entries():
		var position: String = String(entry.get("position", ""))
		counts[position] = int(counts.get(position, 0)) + 1
	for position: String in PlayerRules.POSITION_NAMES:
		assert_gte(int(counts.get(position, 0)), 2,
				"need at least two bundled '%s' identities" % position)


func test_normalize_validates_position() -> void:
	var with_pos: Dictionary = BotIdentityRegistry.normalize_entry(
			{"name": "T", "position": "ld"})
	assert_eq(with_pos.position, "LD", "position is case-normalized")
	var junk: Dictionary = BotIdentityRegistry.normalize_entry(
			{"name": "T", "position": "GOALIE"})
	assert_eq(junk.position, "", "unknown position clears to fill-any")
	var missing: Dictionary = BotIdentityRegistry.normalize_entry({"name": "T"})
	assert_eq(missing.position, "", "missing position defaults to fill-any")


func test_pick_for_slot_prefers_matching_position() -> void:
	# Slot key 3 = home LD. With the whole pool available the pick must come
	# from the LD-tagged identities.
	var used: Array[String] = []
	for _i: int in 20:
		var picked: Dictionary = BotIdentityRegistry.pick_for_slot(3, used)
		assert_eq(picked.get("position", ""), "LD",
				"slot 3 should cast an LD archetype while any remain")
		used.clear()


# ── Cosmetics: pinned looks and the name-hash fallback ───────────────────────

func test_normalize_packs_pinned_cosmetics() -> void:
	var norm: Dictionary = BotIdentityRegistry.normalize_entry({
			"name": "Flash", "tape_blade": 3, "tape_span": StickTapeConfig.Span.STRIP_AND_TOE,
			"tape_knob": 2, "knob_style": StickTapeConfig.KnobStyle.CANDY_CANE, "tape_strip": 2,
			"skate_model": GearModelRegistry.SKATE_RETRO,
			"glove_model": GearModelRegistry.GLOVE_TRICOLOR,
			"lace_color": 3, "stick_model": StickModelRegistry.STICK_VOLT,
			"stick_shaft": 1, "stick_primary": 0, "stick_secondary": 2,
			"helmet_face": GearModelRegistry.FACE_CAGE})
	var tape: StickTapeConfig = StickTapeConfig.from_code(int(norm.tape_code))
	assert_eq(tape.blade_color, 3)
	assert_eq(tape.span, StickTapeConfig.Span.STRIP_AND_TOE)
	assert_eq(tape.knob_color, 2)
	assert_eq(tape.knob_style, StickTapeConfig.KnobStyle.CANDY_CANE)
	assert_eq(tape.strip_color, 2)
	var gear: GearStyleConfig = GearStyleConfig.from_code(int(norm.gear_style_code))
	assert_eq(gear.skate_model, GearModelRegistry.SKATE_RETRO)
	assert_eq(gear.glove_model, GearModelRegistry.GLOVE_TRICOLOR)
	assert_eq(gear.lace_color, 3)
	assert_eq(gear.stick_shaft, 1)
	assert_eq(gear.stick_primary, 0)
	assert_eq(gear.stick_secondary, 2)
	assert_eq(gear.stick_model, StickModelRegistry.STICK_VOLT)
	assert_eq(gear.helmet_face, GearModelRegistry.FACE_CAGE)


func test_normalize_coerces_out_of_range_cosmetics() -> void:
	var norm: Dictionary = BotIdentityRegistry.normalize_entry({
			"name": "Forged", "tape_blade": 99, "skate_model": -3, "stick_model": 42,
			"helmet_face": 77})
	var tape: StickTapeConfig = StickTapeConfig.from_code(int(norm.tape_code))
	assert_true(TapeColorRegistry.is_valid(tape.blade_color), "blade tape coerces legal")
	var gear: GearStyleConfig = GearStyleConfig.from_code(int(norm.gear_style_code))
	assert_true(GearModelRegistry.is_valid_skate(gear.skate_model), "skate model coerces legal")
	assert_true(StickModelRegistry.is_valid(gear.stick_model), "stick model coerces legal")
	assert_true(GearModelRegistry.is_valid_face(gear.helmet_face), "face option coerces legal")


# A negative pin packed raw would sign-extend across every field above it.
func test_a_forged_pin_does_not_bleed_into_its_neighbours() -> void:
	var norm: Dictionary = BotIdentityRegistry.normalize_entry({"name": "Forged",
			"skate_model": -3, "helmet_face": GearModelRegistry.FACE_CAGE,
			"hair_style": HairStyleRegistry.HAIR_MULLET, "facial_hair": -1, "hair_color": 6})
	var gear: GearStyleConfig = GearStyleConfig.from_code(int(norm.gear_style_code))
	assert_eq(gear.helmet_face, GearModelRegistry.FACE_CAGE, "the face pin survives")
	assert_eq(gear.hair_style, HairStyleRegistry.HAIR_MULLET, "the hair pin survives")
	assert_eq(gear.hair_color, 6, "the colour pin survives")
	assert_eq(gear.facial_hair, HairStyleRegistry.FACIAL_NONE, "the forged one coerces")


func test_normalize_omits_unpinned_cosmetic_groups() -> void:
	# No pins → no codes, which is how spawn_bot knows to derive the fallback.
	var norm: Dictionary = BotIdentityRegistry.normalize_entry({"name": "Plain"})
	assert_false(norm.has("tape_code"), "unpinned tape group writes no code")
	assert_false(norm.has("gear_style_code"), "unpinned gear group writes no code")
	# One pinned field claims its whole group; the other group stays derived.
	var half: Dictionary = BotIdentityRegistry.normalize_entry(
			{"name": "Half", "stick_model": 1})
	assert_false(half.has("tape_code"))
	assert_true(half.has("gear_style_code"))


# Hair shares the gear code but is its own group: dressing a card in a visor
# must not also give it the stock haircut, or every curated bot looks alike.
func test_gear_pins_leave_the_hair_to_the_name_hash() -> void:
	var norm: Dictionary = BotIdentityRegistry.normalize_entry(
			{"name": "Visor Guy", "helmet_face": GearModelRegistry.FACE_VISOR})
	var gear: GearStyleConfig = GearStyleConfig.from_code(int(norm.gear_style_code))
	var rolled: GearStyleConfig = GearStyleConfig.from_code(
			BotIdentityRegistry.fallback_gear_style_code("Visor Guy"))
	assert_eq(gear.helmet_face, GearModelRegistry.FACE_VISOR, "the pinned face holds")
	assert_eq(gear.hair_style, rolled.hair_style, "the hair is the name's own roll")
	assert_eq(gear.facial_hair, rolled.facial_hair)
	assert_eq(gear.hair_color, rolled.hair_color)


func test_hair_pins_claim_the_hair_group_and_coerce() -> void:
	var norm: Dictionary = BotIdentityRegistry.normalize_entry({"name": "Mullet",
			"hair_style": HairStyleRegistry.HAIR_MULLET, "hair_color": 99})
	var gear: GearStyleConfig = GearStyleConfig.from_code(int(norm.gear_style_code))
	assert_eq(gear.hair_style, HairStyleRegistry.HAIR_MULLET)
	assert_eq(gear.facial_hair, HairStyleRegistry.FACIAL_NONE,
			"an unpinned field of a pinned group sits at the stock default")
	assert_true(HairStyleRegistry.is_valid_color(gear.hair_color), "a forged colour coerces")
	# The gear group was not pinned, so it is the name's roll, not stock.
	var rolled: GearStyleConfig = GearStyleConfig.from_code(
			BotIdentityRegistry.fallback_gear_style_code("Mullet"))
	assert_eq(gear.skate_model, rolled.skate_model)
	assert_eq(gear.helmet_face, rolled.helmet_face)


# Generic names share a prefix, which is the case a slice of the plain name hash
# gets wrong; every style has to be reachable from the fallback.
func test_fallback_hair_reaches_every_style() -> void:
	var hair: Dictionary = {}
	var facial: Dictionary = {}
	var colors: Dictionary = {}
	for i: int in 200:
		var gear: GearStyleConfig = GearStyleConfig.from_code(
				BotIdentityRegistry.fallback_gear_style_code("Bot %d" % i))
		hair[gear.hair_style] = true
		facial[gear.facial_hair] = true
		colors[gear.hair_color] = true
	assert_eq(hair.size(), HairStyleRegistry.pickable_hair().size(),
			"every pickable hair style is rolled")
	for style: int in hair:
		assert_false(HairStyleRegistry.is_retired_hair(style), "and no retired one")
	assert_eq(facial.size(), HairStyleRegistry.facial_count(), "every facial style is rolled")
	assert_gt(colors.size(), 4, "the colours vary")


func test_fallback_looks_are_stable_legal_and_varied() -> void:
	var tape_codes: Dictionary = {}
	var gear_codes: Dictionary = {}
	for entry: Dictionary in _bundled_entries():
		var bot_name: String = String(entry.get("name", ""))
		var tape_code: int = BotIdentityRegistry.fallback_tape_code(bot_name)
		assert_eq(tape_code, BotIdentityRegistry.fallback_tape_code(bot_name),
				"fallback tape must be deterministic for '%s'" % bot_name)
		assert_eq(StickTapeConfig.from_code(tape_code).to_code(), tape_code,
				"fallback tape for '%s' must already be legal" % bot_name)
		tape_codes[tape_code] = true
		var gear_code: int = BotIdentityRegistry.fallback_gear_style_code(bot_name)
		assert_eq(gear_code, BotIdentityRegistry.fallback_gear_style_code(bot_name),
				"fallback gear must be deterministic for '%s'" % bot_name)
		assert_eq(GearStyleConfig.from_code(gear_code).to_code(), gear_code,
				"fallback gear for '%s' must already be legal" % bot_name)
		gear_codes[gear_code] = true
	# The whole point is variety: across the roster's names the hash tables
	# should land on comfortably more than a couple of distinct looks.
	assert_gt(tape_codes.size(), 4, "roster-wide fallback tape should vary")
	assert_gt(gear_codes.size(), 4, "roster-wide fallback gear should vary")


func test_every_bundled_card_pins_its_cosmetics() -> void:
	# The bundled roster is fully curated — every card owns a deliberate look;
	# the fallback tables exist for user rosters and generic "Bot N" bots.
	for entry: Dictionary in _bundled_entries():
		var norm: Dictionary = BotIdentityRegistry.normalize_entry(entry)
		assert_true(norm.has("tape_code"),
				"bot '%s' should pin a tape job" % entry.get("name", "?"))
		assert_true(norm.has("gear_style_code"),
				"bot '%s' should pin gear" % entry.get("name", "?"))


# The roster's face mix is authored intent: visors are the pro-lineup default,
# with bare heads, cages and fishbowls sprinkled in so a bot game shows the
# whole catalogue. Every option present + visor plurality pins the mix without
# pinning per-card picks.
func test_bundled_roster_wears_a_visor_heavy_face_mix() -> void:
	var counts: Dictionary = {}
	for entry: Dictionary in _bundled_entries():
		assert_true(entry.has("helmet_face"),
				"bot '%s' should pin a face option" % entry.get("name", "?"))
		var face: int = int(entry.get("helmet_face", -1))
		assert_true(GearModelRegistry.is_valid_face(face),
				"bot '%s' face option legal" % entry.get("name", "?"))
		counts[face] = int(counts.get(face, 0)) + 1
	for option: int in GearModelRegistry.face_count():
		assert_gt(int(counts.get(option, 0)), 0,
				"some bundled card wears face option %d" % option)
	for option: int in [GearModelRegistry.FACE_NONE, GearModelRegistry.FACE_CAGE,
			GearModelRegistry.FACE_FISHBOWL]:
		assert_gt(int(counts.get(GearModelRegistry.FACE_VISOR, 0)),
				int(counts.get(option, 0)), "visors are the plurality look")


func test_fallback_faces_lean_visor() -> void:
	# The hash table is weighted like the curated roster — mostly visors. Counted
	# over many generic names (deterministic: String.hash is stable), the visor
	# must beat every other option, and the spread must still reach them all.
	var counts: Dictionary = {}
	for i: int in 200:
		var gear: GearStyleConfig = GearStyleConfig.from_code(
				BotIdentityRegistry.fallback_gear_style_code("Bot %d" % i))
		counts[gear.helmet_face] = int(counts.get(gear.helmet_face, 0)) + 1
	for option: int in GearModelRegistry.face_count():
		assert_gt(int(counts.get(option, 0)), 0,
				"the fallback table reaches face option %d" % option)
		if option != GearModelRegistry.FACE_VISOR:
			assert_gt(int(counts.get(GearModelRegistry.FACE_VISOR, 0)),
					int(counts.get(option, 0)), "visor outnumbers option %d" % option)


# Most of a bench wears the sweater loose; every tuck is still reachable.
func test_fallback_tucks_lean_loose() -> void:
	var counts: Dictionary = {}
	for i: int in 200:
		var gear: GearStyleConfig = GearStyleConfig.from_code(
				BotIdentityRegistry.fallback_gear_style_code("Bot %d" % i))
		counts[gear.jersey_tuck] = int(counts.get(gear.jersey_tuck, 0)) + 1
	for option: int in GearModelRegistry.tuck_count():
		assert_gt(int(counts.get(option, 0)), 0,
				"the fallback table reaches tuck option %d" % option)
	assert_gt(int(counts.get(GearModelRegistry.TUCK_NONE, 0)), 100,
			"most bots wear the jersey loose")


func test_a_tuck_pin_holds_beside_the_rolled_hair() -> void:
	var norm: Dictionary = BotIdentityRegistry.normalize_entry(
			{"name": "Tucker", "jersey_tuck": GearModelRegistry.TUCK_RIGHT})
	var gear: GearStyleConfig = GearStyleConfig.from_code(int(norm.gear_style_code))
	assert_eq(gear.jersey_tuck, GearModelRegistry.TUCK_RIGHT)
	var hair_only: GearStyleConfig = GearStyleConfig.from_code(int(BotIdentityRegistry
			.normalize_entry({"name": "Tucker", "hair_style": HairStyleRegistry.HAIR_MULLET})
			.gear_style_code))
	var rolled: GearStyleConfig = GearStyleConfig.from_code(
			BotIdentityRegistry.fallback_gear_style_code("Tucker"))
	assert_eq(hair_only.jersey_tuck, rolled.jersey_tuck,
			"pinning the hair leaves the tuck to the name's roll")


func test_pick_for_slot_falls_back_when_position_pool_exhausted() -> void:
	# Consume every LD identity; the next LD pick must still return someone.
	var used: Array[String] = []
	for entry: Dictionary in BotIdentityRegistry.get_all():
		if entry.get("position", "") == "LD":
			used.append(String(entry.name))
	var picked: Dictionary = BotIdentityRegistry.pick_for_slot(3, used)
	assert_false(String(picked.get("name", "")).is_empty())
	assert_ne(picked.get("position", ""), "LD",
			"all LDs were used; fallback casts across positions")
