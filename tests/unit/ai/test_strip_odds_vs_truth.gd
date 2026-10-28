extends GutTest

# The carry strip read (AIStripOdds.escape_margin) against an interceptor the
# carrier dodges (docs/strip-interception-plan.md).
# tests/unit/ai/data/strip_intercept_truth.txt is a scripted carrier skating
# fixed paths flat out, swerving away from a defender who re-aims every tick at
# where the carrier's momentum is taking him — whether he took the puck inside
# AIStripOdds.COMMIT_S — measured by
# tests/instruments/ai/test_reacting_interceptor_truth.gd and written by
# test_interception_export.gd. Each run is read from its defender's start along
# the carrier's planned path over its first COMMIT_S, as a planner reads it.
#
# Three ratchets: how often a run that lost the puck read riskier than one that
# kept it may not fall; the losses the read expects, against those that
# happened, may not stray further from one; and in no family of stagings may
# they stray by more than a share of its losses and of its runs, so a good total
# cannot hide a family the read is blind to. All bank when the read improves.

const TRUTH_PATH: String = "res://tests/unit/ai/data/strip_intercept_truth.txt"
const SAMPLE_S: float = 0.1

# The ratchets. Tighten when a change wins by more than BANK_MARGIN.
const MIN_RANKING: float = 0.94
const MAX_EXPECTED_RATIO_ERR: float = 0.05
const FAMILY_SLACK_LOST: float = 0.4
const FAMILY_SLACK_RUNS: float = 0.04
const BANK_MARGIN: float = 0.02


func test_the_strip_read_reads_an_interceptor_the_carrier_dodges() -> void:
	var lost_risk: Array[float] = []
	var kept_risk: Array[float] = []
	var expected: float = 0.0
	var families: Dictionary = {}
	var f := FileAccess.open(TRUTH_PATH, FileAccess.READ)
	assert_not_null(f, "the truth table exists: %s" % TRUTH_PATH)
	if f == null:
		return
	while not f.eof_reached():
		var line: String = f.get_line()
		if line.is_empty() or line.begins_with("#"):
			continue
		var t: PackedStringArray = line.split("\t")
		var nd: int = int(t[2])
		var defs: Array[Vector3] = []
		var vels: Array[Vector3] = []
		for i: int in nd:
			var b: int = 3 + i * 4
			defs.append(Vector3(float(t[b]), 0, float(t[b + 1])))
			vels.append(Vector3(float(t[b + 2]), 0, float(t[b + 3])))
		var points: Array[Vector3] = []
		var times: Array[float] = []
		for k: int in range(3 + nd * 4, t.size(), 2):
			if SAMPLE_S * (points.size() + 1) > AIStripOdds.COMMIT_S + 1e-6:
				break
			points.append(Vector3(float(t[k]), 0, float(t[k + 1])))
			times.append(SAMPLE_S * points.size())
		var risk: float = 1.0 - AIStripOdds.path_keep(points, times, defs, vels)
		expected += risk
		var fam: Vector3 = families.get(t[0], Vector3.ZERO)
		families[t[0]] = fam + Vector3(1.0, float(t[1]), risk)
		if t[1] == "1":
			lost_risk.append(risk)
		else:
			kept_risk.append(risk)
	assert_gt(lost_risk.size(), 0)
	assert_gt(kept_risk.size(), 0)
	var concordant: float = 0.0
	for a: float in lost_risk:
		for b: float in kept_risk:
			concordant += 1.0 if a > b else (0.5 if a == b else 0.0)
	var ranking: float = concordant / (lost_risk.size() * kept_risk.size())
	var ratio: float = lost_risk.size() / expected
	gut.p("%d runs, %d losses against %.1f expected (%.2f); ranking %.3f" % [
			lost_risk.size() + kept_risk.size(), lost_risk.size(), expected, ratio, ranking])
	assert_gte(ranking, MIN_RANKING, "the losses read riskier than the runs kept")
	assert_lte(absf(ratio - 1.0), MAX_EXPECTED_RATIO_ERR, "the losses it expects are the losses")
	for family: String in families:
		var fam: Vector3 = families[family]
		gut.p("  %-14s %4d runs, %3d losses against %5.1f expected" % [family, fam.x, fam.y, fam.z])
		assert_lte(absf(fam.z - fam.y), FAMILY_SLACK_LOST * fam.y + FAMILY_SLACK_RUNS * fam.x,
				"%s: the losses it expects are the family's" % family)
	if ranking > MIN_RANKING + BANK_MARGIN:
		gut.p("ranking %.3f beats its ratchet by more than %.2f: bank it" % [ranking, BANK_MARGIN])
