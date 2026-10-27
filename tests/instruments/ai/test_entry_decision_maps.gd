extends "res://tests/instruments/ai/test_nz_entry_drill.gd"

# The entry drill's decision moments, for drawing: every half second while our
# carrier has the puck short of their line, the play (carrier, mates, defenders),
# what the carrier decided and its values, and the defenders' coverage — the odds
# one of them is within his stick (AIStripOdds) of each spot of the ice 0.3 s,
# 1 s and 2 s on — beside where each defender really was then. Writes
# .preview/decision_maps/moments.jsonl; tools/decision_maps.py draws it. Reports
# only.

const MOMENT_S: float = 0.5
const AHEAD_S: Array[float] = [0.3, 1.0, 2.0]
const RUN_S: float = 5.0
const GRID_M: float = 0.5
const GRID_X: float = 13.0
const GRID_Z_NEAR: float = 14.0
const GRID_Z_FAR: float = -22.0
const OUT_DIR: String = "res://.preview/decision_maps"
# [carrier x, his speed, defenders] per run, from the drill's spread of starts.
const RUNS: Array = [[0.0, 6.0, 2], [-6.0, 4.0, 2], [6.0, 7.0, 3], [0.0, 4.0, 3]]


func test_neutral_zone_entries() -> void:
	pass


func test_entry_decision_maps() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var f := FileAccess.open(OUT_DIR + "/moments.jsonl", FileAccess.WRITE)
	var written: int = 0
	for run: int in RUNS.size():
		var cfg: Array = RUNS[run]
		var duel: Object = _setup(cfg[0], cfg[1], cfg[2])
		var moments: Array[Dictionary] = []
		var every: int = int(MOMENT_S / Duel.DT)
		for i: int in int((RUN_S + AHEAD_S[-1]) / Duel.DT):
			duel.step()
			var t: float = (i + 1) * Duel.DT
			for m: Dictionary in moments:
				for j: int in AHEAD_S.size():
					if m["actual"][j].is_empty() and t >= m["t"] + AHEAD_S[j] - 1e-6:
						m["actual"][j] = _defender_spots(duel)
			if t <= RUN_S and (i + 1) % every == 0:
				var m: Dictionary = _moment(duel, run, t)
				if not m.is_empty():
					moments.append(m)
		for m: Dictionary in moments:
			f.store_line(JSON.stringify(m))
			written += 1
	gut.p("wrote %d moments to %s/moments.jsonl" % [written, OUT_DIR])
	assert_true(true)


# The moment now, if our carrier has the puck short of their line, else empty.
func _moment(duel: Object, run: int, t: float) -> Dictionary:
	var c: int = duel.carrier()
	if c == -1 or duel.team_map[c] != 0 or duel.puck_pos.z < _line():
		return {}
	var s: Object = duel._skater(c)
	var agent: SkaterAgentStateMachine = s.agent
	var car: AIRoleCarrier = agent._carrier
	var mates: Array = []
	var defs: Array[Vector3] = []
	var vels: Array[Vector3] = []
	var caps: Array = []
	for o: Object in duel.skaters:
		if o.peer_id == c:
			continue
		if duel.team_map[o.peer_id] == 0:
			mates.append([o.peer_id, o.pos.x, o.pos.z])
		else:
			defs.append(o.pos)
			vels.append(o.vel)
			caps.append(duel.caps_by_peer[o.peer_id])
	var grids: Array = []
	for ahead: float in AHEAD_S:
		grids.append(_coverage(defs, vels, caps, ahead))
	var defenders: Array = []
	for i: int in defs.size():
		defenders.append([defs[i].x, defs[i].z, vels[i].x, vels[i].z])
	var actual: Array = []
	for _j: int in AHEAD_S.size():
		actual.append([])
	return {"run": run, "t": t, "carrier": [c, s.pos.x, s.pos.z, s.vel.x, s.vel.z],
			"mates": mates, "defenders": defenders, "decision": agent.debug_winner(),
			"carry": car.debug_carry_score, "carry_to": [car.debug_carry_pos.x, car.debug_carry_pos.z],
			"pass": car.debug_pass_score, "pass_to": car.debug_pass_peer_id,
			"ahead": AHEAD_S, "grid": [GRID_X, GRID_Z_NEAR, GRID_Z_FAR, GRID_M], "coverage": grids,
			"actual": actual}


# The odds one of the defenders is within his stick of each grid spot `ahead`
# from now, the defenders' odds summed: rows from the near end, columns across.
func _coverage(defs: Array[Vector3], vels: Array[Vector3], caps: Array, ahead: float) -> Array:
	var rows: Array = []
	var z: float = GRID_Z_NEAR
	while z >= GRID_Z_FAR - 1e-6:
		var row: Array = []
		var x: float = -GRID_X
		while x <= GRID_X + 1e-6:
			var p := Vector3(x, 0.0, z)
			var sum: float = 0.0
			for i: int in defs.size():
				sum += AIStripOdds.odds_within(defs[i], vels[i], caps[i], p, ahead)
			row.append(snappedf(sum, 0.001))
			x += GRID_M
		rows.append(row)
		z -= GRID_M
	return rows


func _defender_spots(duel: Object) -> Array:
	var out: Array = []
	for o: Object in duel.skaters:
		if duel.team_map[o.peer_id] == 1:
			out.append([o.pos.x, o.pos.z])
	return out
