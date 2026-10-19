extends GutTest

# The board pin's escape is a read, and the network alone never decides it
# (BoardPinRules.PIN_ESCAPE_OFFSET_M against PIN_LAG_BUDGET_S): on the real
# controllers (PinRaceHarness), a pinner who answers a reversal within the lag
# budget holds it, one who answers it a human reaction later loses it, and one
# who matches a straight slide holds it to the cap however hard he drives into
# the boards. tests/instruments/game/test_pin_escape_race.gd prints the sweep.

# A typical visual reaction on top of the network's share of the read.
const HUMAN_REACTION_S: float = 0.2
const JUKE_AT_S: float = 0.5


func _race(lag_s: float, juke_at_s: float, drive: float = 0.7) -> PinRaceHarness.Race:
	var h := PinRaceHarness.new(self)
	h.setup(0, 0)
	return h.race(lag_s, juke_at_s, drive)


func test_a_reversal_read_within_the_lag_budget_is_held() -> void:
	var r: PinRaceHarness.Race = _race(BoardPinRules.PIN_LAG_BUDGET_S, JUKE_AT_S)
	assert_eq(r.ended, "cap", "peak offset %.2f m" % r.peak_offset_m)


func test_a_reversal_read_a_human_reaction_late_is_lost() -> void:
	var r: PinRaceHarness.Race = _race(BoardPinRules.PIN_LAG_BUDGET_S + HUMAN_REACTION_S,
			JUKE_AT_S)
	assert_eq(r.ended, "escaped")


func test_a_matched_straight_slide_is_held_to_the_cap() -> void:
	for drive: float in [0.0, 0.7, 1.0]:
		var r: PinRaceHarness.Race = _race(0.0, INF, drive)
		assert_eq(r.ended, "cap", "driving into the boards at %.1f" % drive)
