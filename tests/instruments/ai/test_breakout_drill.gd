extends GutTest

# Real bots breaking out of their own zone under a two-man forecheck, on the
# duel harness: clean exits, own-zone turnovers, time to exit and passes. Team 0
# defends +Z; its blue line is z = +BLUE_LINE_Z. Not modelled: offside, real
# boards, a live goalie.

const Duel := preload("res://tests/unit/ai/duel_harness.gd")
const SECS: float = 8.0


# [outcome, seconds, passes]: "exit" (team 0 carries it past its line),
# "turnover" (team 1 gets it in our zone), "lost-nz", "none".
func _run(duel: Object) -> Array:
	var passes: int = 0
	for i: int in int(SECS / Duel.DT):
		var before: int = duel.releases.size()
		duel.step()
		var t: float = (i + 1) * Duel.DT
		if duel.releases.size() > before and duel.team_map[int(duel.releases[-1]["peer"])] == 0:
			passes += 1
		var c: int = duel.carrier()
		if c == -1:
			continue
		if duel.team_map[c] == 1:
			return ["turnover" if duel.puck_pos.z > GameRules.BLUE_LINE_Z else "lost-nz", t, passes]
		if duel.puck_pos.z < GameRules.BLUE_LINE_Z:
			return ["exit", t, passes]
	return ["none", SECS, passes]


# The carrier deep with wingers on both walls; F1 on him, F2 high in the slot.
func _setup(carrier: Vector3, f1: Vector3, f2: Vector3) -> Object:
	var duel: Object = Duel.new()
	duel.team_size = 3
	duel.add_skater(101, 0, carrier)
	duel.add_skater(102, 0, Vector3(10.0, 0, 16.0))
	duel.add_skater(103, 0, Vector3(-10.0, 0, 14.0))
	duel.add_skater(201, 1, f1, null, (carrier - f1).normalized() * 4.0)
	duel.add_skater(202, 1, f2, null, Vector3(0, 0, 2.0))
	duel.start(101)
	return duel


func test_breakouts() -> void:
	var tally: Dictionary = {}
	var t_exit: float = 0.0
	var n_exit: int = 0
	var passes: int = 0
	var runs: int = 0
	for cx: float in [-8.0, -3.0, 0.0, 4.0, 9.0]:
		for cz: float in [20.0, 24.0]:
			for f1_gap: float in [4.0, 7.0]:
				var carrier := Vector3(cx, 0, cz)
				var f1 := carrier + Vector3(-signf(cx + 0.1), 0, -f1_gap)
				var r: Array = _run(_setup(carrier, f1, Vector3(-cx * 0.5, 0, 12.0)))
				runs += 1
				tally[r[0]] = int(tally.get(r[0], 0)) + 1
				passes += r[2]
				if r[0] == "exit":
					t_exit += r[1]
					n_exit += 1
	gut.p("%s | exit time %.2f s | passes %d over %d runs"
			% [str(tally), t_exit / maxf(n_exit, 1), passes, runs])
	assert_true(true)
