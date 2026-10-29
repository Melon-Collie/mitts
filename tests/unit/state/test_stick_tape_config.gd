extends GutTest

# StickTapeConfig is wire data (the packed code rides the join and spawn
# payloads), so the invariants worth pinning are the wire ones: every legal
# pick round-trips through the code exactly, garbage coerces to a legal job
# instead of being trusted, the all-default job IS code 0 (so payloads that
# omit the field decode to the pre-customization look), a code packed before
# the strip existed decodes to the same job, and the span table stays inside
# the blade the mesh builder will be handed.


func test_default_is_code_zero() -> void:
	var config := StickTapeConfig.new()
	assert_eq(config.to_code(), StickTapeConfig.DEFAULT_CODE, "untouched job packs to 0")
	assert_eq(config.blade_color, TapeColorRegistry.TEAM_INDEX)
	assert_eq(config.span, StickTapeConfig.Span.HEEL_TO_MID)
	assert_eq(config.knob_color, TapeColorRegistry.TEAM_INDEX)
	assert_eq(config.knob_style, StickTapeConfig.KnobStyle.KNOB)
	assert_eq(config.strip_color, TapeColorRegistry.TEAM_INDEX)


func test_every_legal_pick_round_trips() -> void:
	for blade_color: int in TapeColorRegistry.count():
		for span: int in StickTapeConfig.Span.size():
			for knob_color: int in TapeColorRegistry.count():
				for style: int in StickTapeConfig.KnobStyle.size():
					var config := StickTapeConfig.new(blade_color, span, knob_color, style)
					var back: StickTapeConfig = StickTapeConfig.from_code(config.to_code())
					assert_eq(back.blade_color, blade_color)
					assert_eq(back.span, span)
					assert_eq(back.knob_color, knob_color)
					assert_eq(back.knob_style, style)


func test_the_strip_color_round_trips_beside_every_span() -> void:
	for strip_color: int in TapeColorRegistry.count():
		for span: int in StickTapeConfig.Span.size():
			var config := StickTapeConfig.new(1, span, 2, StickTapeConfig.KnobStyle.FULL,
					strip_color)
			var back: StickTapeConfig = StickTapeConfig.from_code(config.to_code())
			assert_eq(back.strip_color, strip_color)
			assert_eq(back.span, span)
			assert_eq(back.blade_color, 1)
			assert_eq(back.knob_color, 2)
			assert_eq(back.knob_style, StickTapeConfig.KnobStyle.FULL)


# The layout every code had before the strip: blade 0–4, span 5–7, knob 8–12,
# style 13–14. Saved prefs and recorded replays hold codes packed this way.
func test_codes_packed_before_the_strip_decode_unchanged() -> void:
	for span: int in StickTapeConfig.Span.MID_TO_TOE + 1:
		var legacy: int = 3 | (span << 5) | (7 << 8) \
				| (StickTapeConfig.KnobStyle.CANDY_CANE << 13)
		var config: StickTapeConfig = StickTapeConfig.from_code(legacy)
		assert_eq(config.blade_color, 3)
		assert_eq(config.span, span)
		assert_eq(config.knob_color, 7)
		assert_eq(config.knob_style, StickTapeConfig.KnobStyle.CANDY_CANE)
		assert_eq(config.strip_color, TapeColorRegistry.TEAM_INDEX)
		assert_eq(config.to_code(), legacy, "re-packs to the same code")


func test_garbage_codes_coerce_to_legal_jobs() -> void:
	for code: int in [-1, -999, 1 << 20, 0x7FFFFFFF]:
		var config: StickTapeConfig = StickTapeConfig.from_code(code)
		assert_true(TapeColorRegistry.is_valid(config.blade_color), "blade color legal")
		assert_true(TapeColorRegistry.is_valid(config.knob_color), "knob color legal")
		assert_true(TapeColorRegistry.is_valid(config.strip_color), "strip color legal")
		assert_between(config.span, 0, StickTapeConfig.Span.size() - 1, "span legal")
		assert_between(config.knob_style, 0, StickTapeConfig.KnobStyle.size() - 1, "style legal")
		# And the coerced job re-packs stably (idempotent coercion).
		var code2: int = config.to_code()
		assert_eq(StickTapeConfig.from_code(code2).to_code(), code2)


func test_span_ranges_stay_on_the_blade() -> void:
	for span: int in StickTapeConfig.Span.size():
		var config := StickTapeConfig.new(0, span, 0)
		var r: Vector2 = config.span_range()
		assert_between(r.x, -0.02, 1.0, "span start on the blade (heel overhang allowed)")
		assert_between(r.y, 0.0, 1.0, "span end on the blade")
		assert_gte(config.wrap_count(), 0)
		if config.has_wraps():
			assert_gt(r.y, r.x, "wrapped spans run heel→toe")
		else:
			assert_eq(config.wrap_count(), 0, "no wraps to count on a bare span")
			assert_true(span == StickTapeConfig.Span.NONE or config.has_strip(),
					"only NONE leaves the blade bare")
		if config.has_strip():
			var s: Vector2 = config.strip_range()
			assert_between(s.x, -0.02, 1.0, "strip start on the blade")
			assert_between(s.y, 0.0, 1.0, "strip end on the blade")
			assert_gt(s.y, s.x, "the strip runs heel→toe")


# Counted wraps are laid edge to edge with gaps between them, so the span has
# to hold them all.
func test_counted_wraps_fit_their_span() -> void:
	var width_u: float = StickBladeMeshBuilder.TAPE_WRAP_WIDTH_M \
			/ GameRules.DEFAULT_BLADE_LENGTH_M
	var counted: int = 0
	for span: int in StickTapeConfig.Span.size():
		var config := StickTapeConfig.new(0, span, 0)
		if config.wrap_count() > 0:
			counted += 1
			var r: Vector2 = config.span_range()
			assert_gt(r.y - r.x, width_u * config.wrap_count(), "room for every wrap")
	assert_gt(counted, 0, "some span lays counted wraps")


func test_team_and_invalid_indices_resolve_to_accent() -> void:
	var accent := Color(0.2, 0.6, 0.9)
	assert_eq(TapeColorRegistry.resolve(TapeColorRegistry.TEAM_INDEX, accent), accent,
			"TEAM resolves to the team accent")
	assert_eq(TapeColorRegistry.resolve(99, accent), accent, "out-of-range falls back")
	assert_eq(TapeColorRegistry.resolve(-3, accent), accent, "negative falls back")
	var white: Color = TapeColorRegistry.resolve(1, accent)
	assert_ne(white, accent, "a real palette pick ignores the accent")


func test_palette_and_name_keys_stay_in_lockstep() -> void:
	assert_eq(TapeColorRegistry.NAME_KEYS.size(), TapeColorRegistry.count(),
			"every palette entry has a display key")
