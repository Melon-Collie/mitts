extends GutTest

# The strip odds (AIStripOdds) against our defending bots
# (docs/defender-race-plan.md). tests/unit/ai/data/strip_odds_truth.txt is a
# scripted carrier, protecting the puck as a bot does, skating fixed paths past
# a real defender bot — when he lost the puck, if he did — measured by
# tests/instruments/ai/test_defender_race_truth.gd. Each run is read from its
# defenders' start along the puck's path, as a planner reads a path.
#
# Two ratchets: how often, at each loss, the run that lost the puck had read
# riskier up to then than a run still in play may not fall; and the losses the
# model expects, against those that happened, may not stray further from one.
# Both bank when the model improves.

const TRUTH_PATH: String = "res://tests/unit/ai/data/strip_odds_truth.txt"
const SAMPLE_S: float = 0.1

# The ratchets. Tighten when a change wins by more than BANK_MARGIN.
const MIN_RANKING: float = 0.765
const MAX_EXPECTED_RATIO_ERR: float = 0.12
const BANK_MARGIN: float = 0.02


class Run:
	var lost_at: float = -1.0
	var watched_to: float = 0.0
	var defenders: Array[Vector3] = []
	var vels: Array[Vector3] = []
	var points: Array[Vector3] = []
	var times: Array[float] = []
	# Expected strips up to each sample.
	var risk: Array[float] = []


func _runs() -> Array[Run]:
	var out: Array[Run] = []
	var f := FileAccess.open(TRUTH_PATH, FileAccess.READ)
	assert_not_null(f, "the truth table exists: %s" % TRUTH_PATH)
	if f == null:
		return out
	while not f.eof_reached():
		var line: String = f.get_line()
		if line.is_empty() or line.begins_with("#"):
			continue
		var t: PackedStringArray = line.split("\t")
		var run := Run.new()
		run.lost_at = float(t[1])
		run.watched_to = float(t[2])
		var nd: int = int(t[3])
		for i: int in nd:
			var b: int = 4 + i * 4
			run.defenders.append(Vector3(float(t[b]), 0, float(t[b + 1])))
			run.vels.append(Vector3(float(t[b + 2]), 0, float(t[b + 3])))
		for k: int in range(4 + nd * 4, t.size(), 3):
			run.times.append(float(t[k]))
			run.points.append(Vector3(float(t[k + 1]), 0, float(t[k + 2])))
		out.append(run)
	return out


func _read(run: Run) -> void:
	var total: float = 0.0
	for k: int in run.points.size():
		if k > 0:
			total += AIStripOdds.stretch_strips(run.points[k - 1], run.points[k],
					run.times[k] - run.times[k - 1], run.times[k], run.defenders, run.vels)
		run.risk.append(total)


# The run's expected strips up to `t`: at its last sample by then.
func _risk_at(run: Run, t: float) -> float:
	var k: int = mini(int(t / SAMPLE_S + 1e-4) - 1, run.risk.size() - 1)
	return run.risk[k] if k >= 0 else 0.0


func test_the_strip_odds_read_our_defenders() -> void:
	var runs: Array[Run] = _runs()
	assert_gt(runs.size(), 0)
	var lost: float = 0.0
	var expected: float = 0.0
	for run: Run in runs:
		_read(run)
		expected += run.risk[run.risk.size() - 1]
		lost += 1.0 if run.lost_at >= 0.0 else 0.0
	var concordant: float = 0.0
	var pairs: float = 0.0
	for a: Run in runs:
		if a.lost_at < 0.0:
			continue
		var ra: float = a.risk[a.risk.size() - 1]
		for b: Run in runs:
			if b == a or b.watched_to <= a.lost_at:
				continue
			var rb: float = _risk_at(b, a.lost_at)
			pairs += 1.0
			concordant += 1.0 if ra > rb else (0.5 if ra == rb else 0.0)
	var ranking: float = concordant / pairs
	var ratio: float = lost / expected
	gut.p("%d runs, %d losses against %.1f expected (%.2f); ranking %.3f" % [runs.size(),
			int(lost), expected, ratio, ranking])
	assert_gte(ranking, MIN_RANKING, "the losses read riskier than the runs still in play")
	assert_lte(absf(ratio - 1.0), MAX_EXPECTED_RATIO_ERR, "the losses it expects are the losses")
	if ranking > MIN_RANKING + BANK_MARGIN:
		gut.p("ranking %.3f beats its ratchet by more than %.2f: bank it" % [ranking, BANK_MARGIN])
