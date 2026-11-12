extends GutTest

# TeamColorRegistry.get_ui_colors — the canonical 3-color UI palette rule.
# Loads the bundled res://data/team_colors.json on first access.
#
#   Home (team_id 0): primary body, secondary stripe, light lettering.
#   Away (team_id 1): light body, primary stripe, primary lettering.
#   A preset's optional ui_ink replaces the lettering on both sides.

const _HOME_SLOT: int = TeamColorRegistry.DEFAULT_HOME_SLOT


func test_home_uses_primary_body_secondary_stripe() -> void:
	var ui: Dictionary = TeamColorRegistry.get_ui_colors(_HOME_SLOT, 0)
	var preset: Dictionary = TeamColorRegistry.get_preset(_HOME_SLOT)
	assert_eq(ui.base, preset.primary, "home body is primary")
	assert_eq(ui.stripe, preset.secondary, "home stripe is secondary")
	assert_eq(ui.text, preset.light, "home lettering is light")


func test_away_uses_light_body_primary_stripe() -> void:
	var ui: Dictionary = TeamColorRegistry.get_ui_colors(_HOME_SLOT, 1)
	var preset: Dictionary = TeamColorRegistry.get_preset(_HOME_SLOT)
	assert_eq(ui.base, preset.light, "away body is light")
	assert_eq(ui.stripe, preset.primary, "away stripe is primary")
	assert_eq(ui.text, preset.primary, "away lettering is primary")


func test_get_colors_exposes_ui_keys_matching_get_ui_colors() -> void:
	for team_id: int in [0, 1]:
		var colors: Dictionary = TeamColorRegistry.get_colors(_HOME_SLOT, team_id)
		var ui: Dictionary = TeamColorRegistry.get_ui_colors(_HOME_SLOT, team_id)
		assert_eq(colors.ui_base, ui.base)
		assert_eq(colors.ui_stripe, ui.stripe)
		assert_eq(colors.ui_text, ui.text)


func test_light_mirrors_away_jersey_base() -> void:
	# light is authored to match the away kit's jersey base so the UI away
	# card matches the 3D away sweater. Verify across all teams.
	for slot: int in TeamColorRegistry.get_all_slots():
		var preset: Dictionary = TeamColorRegistry.get_preset(slot)
		assert_true(preset.has("light"), "slot %d carries a light color" % slot)
		assert_eq(preset.light, preset.away.jersey.base,
			"slot %d light matches away jersey base" % slot)


func test_ui_ink_letters_both_sides() -> void:
	var inked: Array[int] = []
	for slot: int in TeamColorRegistry.get_all_slots():
		var ink: Variant = TeamColorRegistry.get_preset(slot).ui_ink
		if ink == null:
			continue
		inked.append(slot)
		for team_id: int in 2:
			assert_eq(TeamColorRegistry.get_ui_colors(slot, team_id).text, ink,
					"%s side %d letters in its ink" % [TeamColorRegistry.get_preset_name(slot), team_id])
	assert_false(inked.is_empty(), "the bundled file inks at least one team")


# WCAG 2 contrast floor for large/bold text: the HUD's team lettering is a 16px
# display face, read in a glance at the screen corner.
const _MIN_UI_TEXT_CONTRAST: float = 3.0

func test_every_preset_ui_lettering_contrasts_with_its_body() -> void:
	for slot: int in TeamColorRegistry.get_all_slots():
		for team_id: int in 2:
			var ui: Dictionary = TeamColorRegistry.get_ui_colors(slot, team_id)
			var ratio: float = _contrast(ui.text, ui.base)
			assert_gte(ratio, _MIN_UI_TEXT_CONTRAST, "%s side %d lettering contrast %.2f"
					% [TeamColorRegistry.get_preset_name(slot), team_id, ratio])


func _contrast(a: Color, b: Color) -> float:
	var la: float = a.srgb_to_linear().get_luminance()
	var lb: float = b.srgb_to_linear().get_luminance()
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func test_unknown_slot_still_returns_valid_ui_colors() -> void:
	# Out-of-range slot falls back to default preset rather than crashing.
	var ui: Dictionary = TeamColorRegistry.get_ui_colors(9999, 0)
	assert_true(ui.has("base") and ui.has("stripe") and ui.has("text"))


# ── Score-surface stripe pair (scorebug + period summary) ────────────────────
# Each team always wears its own primary, independent of its opponent's colors.

func test_score_stripe_pair_home_is_primary() -> void:
	var pair: Dictionary = TeamColorRegistry.get_score_stripe_pair(_HOME_SLOT, 1)
	assert_eq(pair.home, TeamColorRegistry.get_preset(_HOME_SLOT).primary,
			"home stripe is its primary")

func test_score_stripe_pair_away_is_primary() -> void:
	var pair: Dictionary = TeamColorRegistry.get_score_stripe_pair(_HOME_SLOT, 1)
	assert_eq(pair.away, TeamColorRegistry.get_preset(1).primary,
			"away stripe is its primary")


# A glove design's second color has to differ from the glove body, and MOST
# presets dress their gloves in the secondary — so reaching for the secondary
# again would paint those teams a monochrome glove. get_colors derives
# glove_accent as whichever team color the body is not; every shipped preset
# has to come out with two distinguishable glove colors or the catalogue's
# contrast designs collapse on that team.
func test_every_preset_has_a_contrasting_glove_accent() -> void:
	for slot: int in TeamColorRegistry.get_all_slots():
		for team_id: int in 2:
			var colors: Dictionary = TeamColorRegistry.get_colors(slot, team_id)
			var body: Color = colors.gloves
			var accent: Color = colors.glove_accent
			assert_false(body.is_equal_approx(accent),
					"%s side %d: glove body and accent must differ"
					% [TeamColorRegistry.get_preset_name(slot), team_id])
			# And it is one of the team's OWN two colors, not an invention.
			assert_true(accent.is_equal_approx(colors.primary)
					or accent.is_equal_approx(colors.secondary),
					"%s side %d: the glove accent is a team color"
					% [TeamColorRegistry.get_preset_name(slot), team_id])


# The collar and the yoke are optional; a kit that omits them parses them null,
# which the painters read as "fall back" (UniformPaint.collar_color / yoke_color).
func test_collar_and_yoke_are_optional_and_parse_null() -> void:
	var bare: Dictionary = TeamColorRegistry._parse_kit({"jersey": {"base": "#FF0000"}})
	assert_true(bare.jersey.has("collar"), "every kit carries the collar key")
	assert_null(bare.jersey.collar, "an unnamed collar parses null")
	assert_null(bare.jersey.yoke, "and so does an unnamed yoke")
	var named: Dictionary = TeamColorRegistry._parse_kit(
			{"jersey": {"base": "#FF0000", "yoke": "#00FF00", "collar": "#0000FF"}})
	assert_eq(named.jersey.yoke, Color("#00FF00"))
	assert_eq(named.jersey.collar, Color("#0000FF"))


# A yoke is cut off at the armhole's seam unless the kit names it round: the
# shoulders' caps are the sleeve's, so a round one is carried over them by a
# stripe at the sleeve's top, under the kit's own sleeve stripes.
func test_only_a_round_yoke_runs_on_over_the_sleeves_top() -> void:
	var sleeve := {"base": "#FF0000", "stripes": [{"pos": 0.7, "width": 0.1, "color": "#0000FF"}]}
	var square: Dictionary = TeamColorRegistry._parse_kit(
			{"jersey": {"base": "#FF0000", "yoke": "#00FF00"}, "sleeve": sleeve})
	assert_eq(square.jersey.yoke_shape, SleevePaint.YOKE_SQUARE, "a yoke is square unless named round")
	assert_eq(square.sleeve.stripes.size(), 1, "and leaves the sleeve as the kit wrote it")
	var round_yoke: Dictionary = TeamColorRegistry._parse_kit(
			{"jersey": {"base": "#FF0000", "yoke": "#00FF00", "yoke_shape": "round"},
			"sleeve": sleeve})
	assert_eq(round_yoke.sleeve.stripes.size(), 2)
	assert_eq(round_yoke.sleeve.stripes[0], SleevePaint.yoke_cap(Color("#00FF00")),
			"painted first, so the kit's own stripes lie over it")
	assert_eq(round_yoke.sleeve.stripes[1].color, Color("#0000FF"))
	var no_yoke: Dictionary = TeamColorRegistry._parse_kit(
			{"jersey": {"base": "#FF0000", "yoke_shape": "round"}, "sleeve": sleeve})
	assert_eq(no_yoke.sleeve.stripes.size(), 1, "a shape with no yoke to shape adds nothing")


# A lettering stroke is optional; a kit that omits one parses transparent, which
# every lettering painter reads as unbordered.
func test_lettering_strokes_are_optional_and_parse_transparent() -> void:
	var bare: Dictionary = TeamColorRegistry._parse_kit({"text": {"color": "#FFFFFF"}})
	assert_eq(bare.text.stroke, Color.TRANSPARENT, "an unnamed back stroke is none")
	assert_eq(bare.shoulders.stroke, Color.TRANSPARENT, "and so is a shoulder one")
	var named: Dictionary = TeamColorRegistry._parse_kit({
		"text": {"color": "#FFFFFF", "stroke": "#00FF00"},
		"shoulders": {"color": "#000000", "text": "#FFFFFF", "stroke": "#0000FF"}})
	assert_eq(named.text.stroke, Color("#00FF00"))
	assert_eq(named.shoulders.stroke, Color("#0000FF"))


# With no JSON at all the registry falls back to two hardcoded presets, and they
# stand for the bundled file's first two slots: same team, same solid colors
# (the fallback carries no stripes, yoke or collar).
func test_hardcoded_fallback_mirrors_the_bundled_first_slots() -> void:
	var raw: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string("res://data/team_colors.json"))
	var fallbacks: Array[Dictionary] = [
		TeamColorRegistry._hardcoded_pomegranate(), TeamColorRegistry._hardcoded_blueberry()]
	for slot: int in fallbacks.size():
		var entry: Dictionary = raw.teams[slot]
		var preset: Dictionary = fallbacks[slot]
		assert_eq(preset.name, entry.name, "slot %d fallback is the bundled team" % slot)
		for key: String in ["primary", "secondary", "light"]:
			assert_eq(preset[key], Color(entry[key]), "%s %s" % [entry.name, key])
		for side: String in ["home", "away"]:
			var bundled: Dictionary = TeamColorRegistry._parse_kit(entry[side])
			var kit: Dictionary = preset[side]
			var label: String = "%s %s" % [entry.name, side]
			assert_eq(kit.helmet, bundled.helmet, label + " helmet")
			assert_eq(kit.gloves, bundled.gloves, label + " gloves")
			assert_eq(kit.goalie_pads, bundled.goalie_pads, label + " goalie pads")
			assert_eq(kit.shoulders, bundled.shoulders, label + " shoulders")
			assert_eq(kit.text.color, bundled.text.color, label + " lettering")
			for region: String in ["jersey", "pants", "socks"]:
				assert_eq(kit[region].base, bundled[region].base, "%s %s" % [label, region])
			assert_eq(kit.sleeve.base, bundled.sleeve.base, label + " sleeve")


# Every shipped kit dresses its goalie in white pads; a user file may change
# them per side.
func test_every_bundled_kit_ships_white_goalie_pads() -> void:
	var raw: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string("res://data/team_colors.json"))
	for entry: Dictionary in raw.teams:
		for side: String in ["home", "away"]:
			assert_eq(Color(entry[side].goalie_pads), Color.WHITE,
					"%s %s goalie pads" % [entry.name, side])


# The goalie's trim is the team's primary unless it is too faint on his pads,
# and then the stronger of its two colours.
func test_the_goalie_accent_reads_on_the_pads() -> void:
	for slot: int in TeamColorRegistry.get_all_slots():
		for team_id: int in 2:
			var colors: Dictionary = TeamColorRegistry.get_colors(slot, team_id)
			var label: String = "%s side %d" % [TeamColorRegistry.get_preset_name(slot), team_id]
			var pads: Color = colors.goalie_pads
			var accent: Color = colors.goalie_accent
			var p: float = TeamColorRegistry.contrast_ratio(colors.primary, pads)
			var s: float = TeamColorRegistry.contrast_ratio(colors.secondary, pads)
			if p >= TeamColorRegistry._GOALIE_ACCENT_MIN_CONTRAST:
				assert_eq(accent, colors.primary, label + ": the primary reads, so it trims")
			else:
				assert_almost_eq(TeamColorRegistry.contrast_ratio(accent, pads), maxf(p, s), 0.001,
						label + ": the stronger team colour trims")


# A kit that dresses the pads in its own primary is trimmed in the other colour.
func test_pads_in_the_primary_are_trimmed_in_the_secondary() -> void:
	var preset: Dictionary = TeamColorRegistry.get_preset(_HOME_SLOT)
	assert_eq(TeamColorRegistry._goalie_accent(preset, preset.primary), preset.secondary)


func test_contrast_ratio_spans_one_to_twenty_one() -> void:
	assert_almost_eq(TeamColorRegistry.contrast_ratio(Color.WHITE, Color.WHITE), 1.0, 0.001)
	assert_almost_eq(TeamColorRegistry.contrast_ratio(Color.BLACK, Color.WHITE), 21.0, 0.01)


# ── Team colour as ink on a surface ──────────────────────────────────────────
# Properties of the rule, not of any one palette: every team's ink reads on the
# dark panel, one that already reads is left alone, and lifting keeps the hue.

const _PANEL: Color = MenuStyle.BROADCAST_BG


func test_every_teams_ink_reads_on_the_panel() -> void:
	for slot: int in TeamColorRegistry.get_all_slots():
		var pair: Dictionary = TeamColorRegistry.get_score_ink_pair(slot, slot, _PANEL)
		assert_gte(TeamColorRegistry.contrast_ratio(pair.home, _PANEL),
				TeamColorRegistry.INK_MIN_CONTRAST - 0.01,
				TeamColorRegistry.get_preset_name(slot))


func test_a_primary_that_already_reads_is_its_own_ink() -> void:
	for slot: int in TeamColorRegistry.get_all_slots():
		var primary: Color = TeamColorRegistry.get_preset(slot).primary
		if TeamColorRegistry.contrast_ratio(primary, _PANEL) < TeamColorRegistry.INK_MIN_CONTRAST:
			continue
		var pair: Dictionary = TeamColorRegistry.get_score_ink_pair(slot, slot, _PANEL)
		assert_eq(pair.home, primary, TeamColorRegistry.get_preset_name(slot))


func test_lifting_keeps_the_hue_and_only_goes_as_far_as_it_must() -> void:
	var navy := Color("#1E2A5A")
	var ink: Color = TeamColorRegistry.readable_on(navy, _PANEL)
	assert_almost_eq(ink.ok_hsl_h, navy.ok_hsl_h, 0.01, "same hue")
	assert_gt(ink.ok_hsl_l, navy.ok_hsl_l, "lightened on a dark surface")
	assert_almost_eq(TeamColorRegistry.contrast_ratio(ink, _PANEL),
			TeamColorRegistry.INK_MIN_CONTRAST, 0.05, "no lighter than it needs")


func test_on_a_light_surface_ink_darkens() -> void:
	var pale := Color("#F5D028")
	var ink: Color = TeamColorRegistry.readable_on(pale, Color.WHITE)
	assert_lt(ink.ok_hsl_l, pale.ok_hsl_l)
	assert_gte(TeamColorRegistry.contrast_ratio(ink, Color.WHITE),
			TeamColorRegistry.INK_MIN_CONTRAST - 0.01)


# A near-black primary lifts to a grey, which reads as the UI's own neutral text;
# its secondary carries the team instead.
func test_a_hueless_primary_inks_in_its_secondary() -> void:
	var preset: Dictionary = {"primary": Color("#161618"), "secondary": Color("#5E2457")}
	var ink: Color = TeamColorRegistry._ink_for(preset, _PANEL)
	assert_almost_eq(ink.ok_hsl_h, (preset.secondary as Color).ok_hsl_h, 0.01)
	assert_gte(ink.s, TeamColorRegistry._INK_MIN_SATURATION)
