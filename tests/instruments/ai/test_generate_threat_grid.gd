extends GutTest

# ── THE THREAT GRID GENERATOR (docs/xt-plan.md, Step 3) ──────────────────────
# Measures each grid state's next macro event off the real bots and the live
# keepers (threat_rollout.gd's run_macro, from threat_stager.gd's stagings at
# the cell), solves the grid (AIThreatGrid.solve), and writes
# Scripts/domain/ai/generated/threat_grid_data.gd. Run it through
# .claude/hooks/generate-threat-grid.sh, which shards the cells over processes
# and then merges; never hand-edit the output.
#
# A sample is staged at a cell's centre in each template context, and lands in
# the state of the context it reads as (AIThreatGrid.context_of), so a state's
# samples are the stagings that look like it. It ends where the macro event
# does: our possession on (a move), theirs (a turnover, read in their frame), a
# goal (±1) or a held or timed-out puck (0). Its weight is e^(−t/τ) over its
# state's samples.
#
#   MITTS_GRID_SHARD=i MITTS_GRID_SHARDS=n   measure every n-th cell from i
#   MITTS_GRID_MERGE=1                       merge the shards, solve, write
#   MITTS_GRID_SEEDS=k                       k stagings a template (default SEEDS)

const Rollout := preload("res://tests/unit/ai/threat_rollout.gd")
const Stager := preload("res://tests/unit/ai/threat_stager.gd")
const Duel := preload("res://tests/unit/ai/duel_harness.gd")
const OUT_PATH: String = "res://Scripts/domain/ai/generated/threat_grid_data.gd"
const SHARD_PATH: String = "user://threat_grid_shard_%d.txt"
const TAU_S: float = AIActionScoring.READ_VALIDITY_TAU_S
const TEAM_SIZE: int = 3
const SEEDS: int = 16
# A macro event's clock while the same side keeps the puck, and its cap.
const MOVE_S: float = 1.0
const CAP_S: float = 8.0
const GOAL_OURS := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z)
const GOAL_THEIRS := Vector3(0.0, 0.0, GameRules.GOAL_LINE_Z)

var _rollout: RefCounted = null


func before_all() -> void:
	_rollout = Rollout.new(self)


func _world(local: Vector2) -> Vector3:
	return Vector3(local.x, 0.0, GOAL_OURS.z + local.y)


static func _context(positions: Dictionary, team_map: Dictionary, puck: Vector3,
		attacking: int) -> int:
	var attackers: Array[Vector3] = []
	var defenders: Array[Vector3] = []
	for p: int in positions:
		if team_map[p] == attacking:
			attackers.append(positions[p])
		else:
			defenders.append(positions[p])
	return AIThreatGrid.context_of(puck, attackers, defenders,
			GOAL_OURS if attacking == 0 else GOAL_THEIRS)


# One sample's line: the state it was staged in, then where it went (state, or
# −1), whether that is the other side's, the terminal value, and the duration.
func _sample(cell: int, template: String, rng: RandomNumberGenerator) -> String:
	var rows: Array = Stager.stage(_world(AIThreatGrid.centre(cell)), template, TEAM_SIZE, rng)
	var duel := Duel.new()
	duel.team_size = TEAM_SIZE
	var start_pos: Dictionary = {}
	for r: Array in rows:
		duel.add_skater(r[0], r[1], r[2], null, r[3])
		start_pos[r[0]] = r[2]
	duel.start(1)
	var from: int = AIThreatGrid.state(cell, _context(start_pos, duel.team_map, rows[0][2], 0))
	var m: RefCounted = _rollout.run_macro(duel, MOVE_S, CAP_S)
	var to: int = -1
	var theirs: int = 0
	var terminal: float = 0.0
	match m.end:
		Rollout.Macro.GOAL:
			terminal = 1.0 if m.scorer_team == 0 else -1.0
		Rollout.Macro.MOVED:
			to = AIThreatGrid.state(AIThreatGrid.cell_of(AIThreatGrid.local(m.puck, GOAL_OURS)),
					_context(m.positions, duel.team_map, m.puck, 0))
		Rollout.Macro.TURNED_OVER:
			theirs = 1
			to = AIThreatGrid.state(AIThreatGrid.cell_of(AIThreatGrid.local(m.puck, GOAL_THEIRS)),
					_context(m.positions, duel.team_map, m.puck, 1))
	return "%d\t%d\t%d\t%.1f\t%.3f" % [from, to, theirs, terminal, m.t]


func test_measure_a_shard() -> void:
	var shard: int = int(OS.get_environment("MITTS_GRID_SHARD"))
	var shards: int = maxi(int(OS.get_environment("MITTS_GRID_SHARDS")), 1)
	var seeds: int = int(OS.get_environment("MITTS_GRID_SEEDS")) \
			if OS.has_environment("MITTS_GRID_SEEDS") else SEEDS
	var f := FileAccess.open(SHARD_PATH % shard, FileAccess.WRITE)
	var rng := RandomNumberGenerator.new()
	for cell: int in range(shard, AIThreatGrid.cell_count(), shards):
		var t0: int = Time.get_ticks_msec()
		for template: String in Stager.CONTEXTS:
			for k: int in seeds:
				rng.seed = hash([cell, template, k])
				f.store_line(_sample(cell, template, rng))
		f.flush()
		gut.p("cell %d/%d (%d s)" % [cell, AIThreatGrid.cell_count(), (Time.get_ticks_msec() - t0) / 1000])
	f.close()
	assert_true(true)


func test_merge_the_shards() -> void:
	if OS.get_environment("MITTS_GRID_MERGE") != "1":
		pass_test("not merging")
		return
	var shards: int = maxi(int(OS.get_environment("MITTS_GRID_SHARDS")), 1)
	var n: int = AIThreatGrid.state_count()
	var samples: Array = []
	samples.resize(n)
	for s: int in n:
		samples[s] = []
	for i: int in shards:
		var f := FileAccess.open(SHARD_PATH % i, FileAccess.READ)
		assert_not_null(f, "shard %d" % i)
		if f == null:
			return
		while not f.eof_reached():
			var line: String = f.get_line()
			if line.is_empty():
				continue
			var t: PackedStringArray = line.split("\t")
			samples[int(t[0])].append(t)
	var outcomes: Array = []
	var counts := PackedInt32Array()
	for s: int in n:
		var list: Array = []
		var count: int = samples[s].size()
		counts.append(count)
		for t: PackedStringArray in samples[s]:
			var o := AIThreatGrid.Outcome.new()
			o.weight = exp(-float(t[4]) / TAU_S) / float(count)
			o.to = int(t[1])
			o.theirs = t[2] == "1"
			o.terminal = float(t[3])
			list.append(o)
		outcomes.append(list)
	var v: PackedFloat32Array = AIThreatGrid.solve(outcomes)
	_write(v, counts)


func _write(v: PackedFloat32Array, counts: PackedInt32Array) -> void:
	var out := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	out.store_line("class_name AIThreatGridData")
	out.store_line("")
	out.store_line("# GENERATED by tests/instruments/ai/test_generate_threat_grid.gd through")
	out.store_line("# .claude/hooks/generate-threat-grid.sh — never hand-edit. Per AIThreatGrid")
	out.store_line("# state (cell × context): the attacking side's possession there, signed next")
	out.store_line("# goal discounted by e^(-t/%.1f s); and how many samples measured it." % TAU_S)
	out.store_line("")
	var vals: PackedStringArray = []
	for x: float in v:
		vals.append("%.4f" % x)
	var cnts: PackedStringArray = []
	for c: int in counts:
		cnts.append(str(c))
	out.store_line("const VALUES: Array[float] = [%s]" % ", ".join(vals))
	out.store_line("const SAMPLES: Array[int] = [%s]" % ", ".join(cnts))
	out.close()
