extends "res://tests/instruments/ai/test_nz_entry_drill.gd"

# The dump-in against a stacked line (docs/possession-floor-plan.md, step 5):
# three real bots come up the ice at speed at three defenders standing on their
# blue line. How often the carrier takes the line, dumps it in or turns it over,
# and how often a dump comes back to us (dump-won), goes to them (dump-lost) or
# is touched by nobody in the drill's time. The outcomes are the entry drill's.


func test_neutral_zone_entries() -> void:
	pending("the entry sweep is test_nz_entry_drill.gd's own")


# Our carrier at `carrier_x` with two wingers, all at `speed`; their three on the
# line, the middle man `gap` metres off it.
func _stacked(carrier_x: float, speed: float, gap: float) -> Object:
	var duel: Object = Duel.new()
	duel.team_size = 3
	duel.add_skater(101, 0, Vector3(carrier_x, 0, 4.0), null, Vector3(0, 0, -speed))
	duel.add_skater(102, 0, Vector3(-9.0 if carrier_x >= 0.0 else 9.0, 0, 6.0), null,
			Vector3(0, 0, -speed))
	duel.add_skater(103, 0, Vector3(-carrier_x * 0.3, 0, 9.0), null, Vector3(0, 0, -speed * 0.8))
	duel.add_skater(201, 1, Vector3(-8.0, 0, _line() - 0.5))
	duel.add_skater(202, 1, Vector3(0.0, 0, _line() + gap))
	duel.add_skater(203, 1, Vector3(8.0, 0, _line() - 0.5))
	duel.start(101)
	return duel


func test_dump_ins_against_a_stacked_line() -> void:
	for mode: String in ["as the field stands", "point shots worth nothing"]:
		if mode != "as the field stands":
			PointOff.apply()
		var tally: Dictionary = {}
		var runs: int = 0
		var row: String = "   "
		for x: float in [0.0, -4.0, 6.0]:
			for speed: float in [5.0, 7.5]:
				for gap: float in [0.5, 2.5]:
					var r: Array = _run(_stacked(x, speed, gap))
					runs += 1
					tally[r[0]] = int(tally.get(r[0], 0)) + 1
					row += " %s@%.1f" % [str(r[0]).left(8), r[1]]
		var dumps: int = int(tally.get("dump-won", 0)) + int(tally.get("dump-lost", 0)) \
				+ int(tally.get("dump-loose", 0))
		gut.p("%s: %s over %d runs | dumps won back %d of %d" % [mode, str(tally), runs,
				int(tally.get("dump-won", 0)), dumps])
		gut.p(row)
		PointOff.restore()
	assert_true(true)
