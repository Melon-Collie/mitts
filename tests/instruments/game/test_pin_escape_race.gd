extends GutTest

# Instrument: how a board pin ends against a human-style pinner, by weight
# pairing, the pinner's read lag and whether the victim jukes (PinRaceHarness).
# Prints a table; the property it motivated is test_pin_escape_race in
# tests/slow/game/.

const PAIRS: Array = [[0, 0], [170, 260], [260, 170]]
const LAGS: Array = [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6]


func test_the_race_table() -> void:
	gut.p("escape offset %.3f m, lag budget %.2f s" % [BoardPinRules.PIN_ESCAPE_OFFSET_M,
			BoardPinRules.PIN_LAG_BUDGET_S])
	for pair: Array in PAIRS:
		var h := PinRaceHarness.new(self)
		h.setup(pair[0], pair[1])
		var line := "victim %s / pinner %s:" % [_lbs(pair[0]), _lbs(pair[1])]
		line += "\n    one-way slide, no lag -> " + _row(h.race(0.0, INF))
		for lag: float in LAGS:
			h = PinRaceHarness.new(self)
			h.setup(pair[0], pair[1])
			line += "\n    juke at 0.5 s, read %.2f s late -> %s" % [lag, _row(h.race(lag, 0.5))]
		gut.p(line)
	assert_true(true)


func _lbs(lbs: int) -> String:
	return "neutral" if lbs == 0 else "%d lb" % lbs


func _row(r: PinRaceHarness.Race) -> String:
	return "%s at %.2f s (peak offset %.2f m)" % [r.ended, r.at_s, r.peak_offset_m]
