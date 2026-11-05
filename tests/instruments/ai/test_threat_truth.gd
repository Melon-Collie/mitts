extends GutTest

# ── THE THREAT TRUTH TABLE (docs/xt-plan.md, Step 1) ─────────────────────────
# What possession of a spot is worth, measured: from the stager's states across
# the ice (threat_stager.gd), the real bots play the possession on in the duel
# harness against the live keeper in each net (threat_rollout.gd), and each
# rollout scores ±e^(−t/τ) for the next goal within the horizon. Per staged
# state the table holds the mean over seeded jitters of the staging, its
# standard error, and how the rollouts ended. Written to
# tests/unit/ai/data/threat_truth.txt, which test_threat_vs_truth.gd scores the
# bots' models against.
#
# Run through .claude/hooks/generate-threat-truth.sh, which shards the cells
# over processes and then merges:
#   MITTS_THREAT_SHARD=i MITTS_THREAT_SHARDS=n   measure every n-th cell from i
#   MITTS_THREAT_MERGE=1                         merge the shards into the table
#   MITTS_THREAT_SEEDS=k                         k rollouts a cell (default SEEDS)

const Rollout := preload("res://tests/unit/ai/threat_rollout.gd")
const Stager := preload("res://tests/unit/ai/threat_stager.gd")
const Duel := preload("res://tests/unit/ai/duel_harness.gd")
const OUT_PATH: String = "res://tests/unit/ai/data/threat_truth.txt"
const SHARD_PATH: String = "user://threat_truth_shard_%d.txt"
const TAU_S: float = AIActionScoring.READ_VALIDITY_TAU_S
const HORIZON_S: float = 3.0 * AIActionScoring.READ_VALIDITY_TAU_S
const TEAM_SIZES: Array[int] = [3]
# Metres out from their goal line, and across.
const SPOT_OUT: Array[float] = [3.0, 6.0, 9.0, 13.0, 18.0, 24.0, 32.0, 40.0, 48.0]
const SPOT_X: Array[float] = [-9.0, -4.5, 0.0, 4.5, 9.0]
const SEEDS: int = 40

var _rollout: RefCounted = null


func before_all() -> void:
	_rollout = Rollout.new(self)


# Every cell, in a fixed order: [team_size, context, x, out].
static func cells() -> Array:
	var out: Array = []
	for n: int in TEAM_SIZES:
		for context: String in Stager.CONTEXTS:
			for f: float in SPOT_OUT:
				for x: float in SPOT_X:
					out.append([n, context, x, f])
	return out


func _play(rows: Array, team_size: int) -> RefCounted:
	var duel := Duel.new()
	duel.team_size = team_size
	for r: Array in rows:
		duel.add_skater(r[0], r[1], r[2], null, r[3])
	duel.start(1)
	return _rollout.run(duel, HORIZON_S, TAU_S)


# One cell's row: team size, context, x, out, rollouts, mean, standard error,
# goals for, goals against, held.
func _measure(cell: Array) -> String:
	var rng := RandomNumberGenerator.new()
	var sum: float = 0.0
	var sum_sq: float = 0.0
	var ends := PackedInt32Array([0, 0, 0])
	var seeds: int = int(OS.get_environment("MITTS_THREAT_SEEDS")) if OS.has_environment("MITTS_THREAT_SEEDS") else SEEDS
	for k: int in seeds:
		rng.seed = hash([cell, k])
		var r: RefCounted = _play(Stager.stage(Stager.spot(cell[2], cell[3]), cell[1],
				cell[0], rng), cell[0])
		sum += r.value
		sum_sq += r.value * r.value
		if r.end == Rollout.End.GOAL:
			ends[0 if r.scorer_team == 0 else 1] += 1
		elif r.end == Rollout.End.HELD:
			ends[2] += 1
	var mean: float = sum / seeds
	var se: float = sqrt(maxf(sum_sq / seeds - mean * mean, 0.0) / maxi(seeds - 1, 1))
	return "%d\t%s\t%.1f\t%.1f\t%d\t%.4f\t%.4f\t%d\t%d\t%d" % [cell[0], cell[1], cell[2], cell[3],
			seeds, mean, se, ends[0], ends[1], ends[2]]


func test_measure_a_shard() -> void:
	var shard: int = int(OS.get_environment("MITTS_THREAT_SHARD"))
	var shards: int = maxi(int(OS.get_environment("MITTS_THREAT_SHARDS")), 1)
	var all: Array = cells()
	var f := FileAccess.open(SHARD_PATH % shard, FileAccess.WRITE)
	for i: int in range(shard, all.size(), shards):
		var t0: int = Time.get_ticks_msec()
		var row: String = _measure(all[i])
		f.store_line("%d\t%s" % [i, row])
		f.flush()
		gut.p("cell %d/%d %s (%d s)" % [i, all.size(), row, (Time.get_ticks_msec() - t0) / 1000])
	f.close()
	assert_true(true)


func test_merge_the_shards() -> void:
	if OS.get_environment("MITTS_THREAT_MERGE") != "1":
		pass_test("not merging")
		return
	var shards: int = maxi(int(OS.get_environment("MITTS_THREAT_SHARDS")), 1)
	var rows: Dictionary = {}
	for s: int in shards:
		var f := FileAccess.open(SHARD_PATH % s, FileAccess.READ)
		assert_not_null(f, "shard %d" % s)
		if f == null:
			return
		while not f.eof_reached():
			var line: String = f.get_line()
			if line.is_empty():
				continue
			var i: int = int(line.get_slice("\t", 0))
			rows[i] = line.substr(line.find("\t") + 1)
	var all: Array = cells()
	assert_eq(rows.size(), all.size(), "every cell measured")
	var out := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	out.store_line("# Threat truth: written by tests/instruments/ai/test_threat_truth.gd")
	out.store_line("# (.claude/hooks/generate-threat-truth.sh); never hand-edit. Next goal")
	out.store_line("# within %.0f s, ±e^(-t/%.1f s), team 0 (the staged attack) positive." % [
			HORIZON_S, TAU_S])
	out.store_line("# team_size\tcontext\tx\tout\tn\tmean\tse\tgoals_for\tgoals_against\theld")
	for i: int in all.size():
		out.store_line(rows[i])
	out.close()
