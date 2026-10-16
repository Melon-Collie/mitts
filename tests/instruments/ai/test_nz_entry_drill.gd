extends GutTest

# Three real bots bring the puck from their own half into the offensive zone
# against a defence standing up at its blue line, on the duel harness: how many
# carry it in, how many turn it over, how many passes it takes (and how many go
# backward), and how long the carrier stalls by the line. Team 0 attacks -Z;
# their blue line is z = -BLUE_LINE_Z. Not modelled: offside, real boards, a
# live goalie.

const Duel := preload("res://tests/unit/ai/duel_harness.gd")
const SECS: float = 8.0
# Stalled: the carrier within STALL_BAND_M of the line, slower than STALL_SPEED.
const STALL_BAND_M: float = 4.0
const STALL_SPEED_M_S: float = 3.0


func _line() -> float:
	return -GameRules.BLUE_LINE_Z


# [outcome, seconds, passes, backward passes, stall seconds]. Outcomes:
# "carried" (team 0 carries across), "dump-won" / "dump-lost" (a release crosses
# loose and that team touches it next), "turnover", "none".
func _run(duel: Object) -> Array:
	var dumped: bool = false
	var passes: int = 0
	var back: int = 0
	var stall: float = 0.0
	for i: int in int(SECS / Duel.DT):
		var before: int = duel.releases.size()
		duel.step()
		var t: float = (i + 1) * Duel.DT
		if duel.releases.size() > before and duel.team_map[int(duel.releases[-1]["peer"])] == 0 \
				and duel.puck_pos.z > _line():
			passes += 1
			if duel.puck_vel.z > 0.5:
				back += 1
		var c: int = duel.carrier()
		if c != -1:
			var team: int = duel.team_map[c]
			if dumped:
				return ["dump-won" if team == 0 else "dump-lost", t, passes, back, stall]
			if team == 1:
				return ["turnover", t, passes, back, stall]
			if duel.puck_pos.z < _line():
				return ["carried", t, passes, back, stall]
			var s: Object = duel._skater(c)
			if s.pos.z - _line() < STALL_BAND_M \
					and Vector2(s.vel.x, s.vel.z).length() < STALL_SPEED_M_S:
				stall += Duel.DT
		elif duel.puck_pos.z < _line() and not dumped:
			dumped = true
	return ["dump-loose" if dumped else "none", SECS, passes, back, stall]


# The carrier deep in his own half with two wingers; two defenders standing up at
# their line, and with `n_def` 3 a backchecker on the play.
func _setup(carrier_x: float, speed: float, n_def: int) -> Object:
	var duel: Object = Duel.new()
	duel.team_size = 3
	duel.add_skater(101, 0, Vector3(carrier_x, 0, 12.0), null, Vector3(0, 0, -speed))
	duel.add_skater(102, 0, Vector3(7.0 if carrier_x <= 0.0 else -7.0, 0, 10.0), null,
			Vector3(0, 0, -speed))
	duel.add_skater(103, 0, Vector3(-carrier_x * 0.3, 0, 16.0), null, Vector3(0, 0, -speed * 0.5))
	duel.add_skater(201, 1, Vector3(-3.0, 0, -8.5), null, Vector3.ZERO)
	duel.add_skater(202, 1, Vector3(3.0, 0, -8.5), null, Vector3.ZERO)
	if n_def >= 3:
		duel.add_skater(203, 1, Vector3(carrier_x * 0.5, 0, 6.0), null, Vector3(0, 0, -3.0))
	duel.start(101)
	return duel


func test_neutral_zone_entries() -> void:
	var tally: Dictionary = {}
	var t_carried: float = 0.0
	var n_carried: int = 0
	var passes: int = 0
	var back: int = 0
	var stall: float = 0.0
	var runs: int = 0
	for n_def: int in [2, 3]:
		var row: String = "  3v%d :" % n_def
		for x: float in [0.0, 3.0, 5.0, -6.0, -9.0]:
			for v: float in [1.0, 3.0, 5.0]:
				var r: Array = _run(_setup(x, v, n_def))
				runs += 1
				tally[r[0]] = int(tally.get(r[0], 0)) + 1
				if r[0] == "carried":
					t_carried += r[1]
					n_carried += 1
				passes += r[2]
				back += r[3]
				stall += r[4]
				row += " %s@%.1f/p%d/b%d" % [r[0].left(4), r[1], r[2], r[3]]
		gut.p(row)
	gut.p("%s | carried-entry time %.2f s | passes %d (backward %d) | stall %.1f s over %d runs"
			% [str(tally), t_carried / maxf(n_carried, 1), passes, back, stall, runs])
	assert_true(true)
