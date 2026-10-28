extends GutTest

# The release contest (AIPuckLane.release_contest_clean: each defender's one
# chance at the puck held on the blade through the windup) against a worst-case
# defender on the passer (docs/strip-interception-plan.md).
# tests/unit/ai/data/release_contest_truth.txt is the windup runs of
# tests/instruments/ai/test_pass_truth.gd: a passer holding the puck through the
# windup, a defender at a ring of distances round him, standing or closing,
# playing him from its start — whether he stripped it before the release.
#
# Ratchets: how often a strip read riskier than a clean release may not fall,
# and the strips the read expects, against those that happened, may not stray
# further from one.

const TRUTH_PATH: String = "res://tests/unit/ai/data/release_contest_truth.txt"
const Duel := preload("res://tests/unit/ai/duel_harness.gd")

const MIN_RANKING: float = 0.76
const MAX_EXPECTED_RATIO_ERR: float = 0.10
const BANK_MARGIN: float = 0.02


func test_the_release_contest_reads_a_worst_case_defender() -> void:
	var f := FileAccess.open(TRUTH_PATH, FileAccess.READ)
	assert_not_null(f, "the truth table exists: %s" % TRUTH_PATH)
	if f == null:
		return
	var caps: Array = [Duel.match_caps()]
	var risk: Array[float] = []
	var stripped: Array[bool] = []
	var expected: float = 0.0
	var n_stripped: int = 0
	while not f.eof_reached():
		var line: String = f.get_line()
		if line.is_empty() or line.begins_with("#"):
			continue
		var t: PackedStringArray = line.split("\t")
		var o := Vector3(float(t[1]), 0, float(t[2]))
		var r := Vector3(float(t[3]), 0, float(t[4]))
		var defs: Array[Vector3] = [Vector3(float(t[5]), 0, float(t[6]))]
		var vels: Array[Vector3] = [Vector3(float(t[7]), 0, float(t[8]))]
		var p: float = 1.0 - AIPuckLane.release_contest_clean(
				AIPuckLane.release_point_toward(o, r), defs, caps, vels)
		risk.append(p)
		stripped.append(t[0] == "1")
		expected += p
		n_stripped += 1 if t[0] == "1" else 0
	var ranking: float = _ranking(risk, stripped)
	var ratio: float = n_stripped / expected
	gut.p("%d windups, %d stripped against %.1f expected (%.2f); ranking %.3f" % [
			risk.size(), n_stripped, expected, ratio, ranking])
	assert_gte(ranking, MIN_RANKING, "the strips read riskier than the clean releases")
	assert_lte(absf(ratio - 1.0), MAX_EXPECTED_RATIO_ERR, "the strips it expects are the strips")
	if ranking > MIN_RANKING + BANK_MARGIN:
		gut.p("ranking %.3f beats its ratchet by more than %.2f: bank it" % [ranking, BANK_MARGIN])


# How often a stripped windup read riskier than a clean one.
func _ranking(risk: Array[float], stripped: Array[bool]) -> float:
	var concordant: float = 0.0
	var pairs: float = 0.0
	for a: int in risk.size():
		if not stripped[a]:
			continue
		for b: int in risk.size():
			if stripped[b]:
				continue
			pairs += 1.0
			concordant += 1.0 if risk[a] > risk[b] else (0.5 if risk[a] == risk[b] else 0.0)
	return concordant / pairs if pairs > 0.0 else 0.0
