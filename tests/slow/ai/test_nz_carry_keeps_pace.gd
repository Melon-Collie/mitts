extends GutTest

# A carrier leaving his own blue line at pace, one defender gapping up ahead and
# a path to the line, carries the puck in without pulling up.
#
# Real bot against real bot (duel_harness). Each run must cross the attacking
# blue line inside the window, keep the puck, and never bleed below half the
# pace it started with. Two reads made the carrier stall short of the line: his
# rolled move flipped between near-equal cuts every re-plan, each turn spending
# the speed neither priced; and the defence he priced was carried on at its
# retreat, so every delay of the entry read as a blue line the defender had
# left, and pulling up to wait for it won.

const Duel := preload("res://tests/unit/ai/duel_harness.gd")
const DT: float = 1.0 / 120.0
const CARRIER := 1
const DEFENDER := 201
const WINDOW_S: float = 3.5
const START_Z: float = 8.0
const PACE_M_S: float = 7.5


func _carry(gap: float, offset_x: float) -> Dictionary:
	var duel := Duel.new()
	duel.add_skater(CARRIER, 0, Vector3(-1.0, 0, START_Z), null, Vector3(0, 0, -PACE_M_S))
	duel.add_skater(DEFENDER, 1, Vector3(-1.0 + offset_x, 0, START_Z - gap),
			null, Vector3(0, 0, -2.0))
	duel.start(CARRIER)
	var out := {"entered": false, "lost": false, "min_speed": INF, "t": WINDOW_S}
	for t: int in int(WINDOW_S / DT):
		duel.step()
		if duel.carrier_id != CARRIER:
			out["lost"] = true
			out["t"] = t * DT
			return out
		var s: Object = duel._skater(CARRIER)
		out["min_speed"] = minf(out["min_speed"], Vector2(s.vel.x, s.vel.z).length())
		if duel.puck_pos.z < -GameRules.BLUE_LINE_Z - 1.0:
			out["entered"] = true
			out["t"] = t * DT
			return out
	return out


func _assert_carries_in(gap: float, offset_x: float) -> void:
	var label: String = "gap %.0f m, defender %.1f m across" % [gap, offset_x]
	var r: Dictionary = _carry(gap, offset_x)
	gut.p("%s: entered %s, lost %s at %.2f s, slowest %.1f m/s" % [
			label, r["entered"], r["lost"], r["t"], r["min_speed"]])
	assert_false(r["lost"], "%s: he keeps the puck" % label)
	assert_true(r["entered"], "%s: he carries it in inside %.1f s" % [label, WINDOW_S])
	assert_gt(r["min_speed"], 0.5 * PACE_M_S, "%s: he does not pull up" % label)


func test_defender_square_with_a_long_gap() -> void:
	_assert_carries_in(13.0, 0.0)


func test_defender_square_with_a_mid_gap() -> void:
	_assert_carries_in(10.0, 0.0)


func test_defender_off_his_line_close() -> void:
	_assert_carries_in(7.0, 2.5)


func test_defender_off_his_line_far() -> void:
	_assert_carries_in(13.0, 2.5)
