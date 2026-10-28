extends GutTest

# The pass lane reads (AIPuckLane.lane_clear, lane_clear_saucer, AIRimPass.lane:
# each defender's one chance at the puck's path, AILaneReach) against a
# worst-case interceptor (docs/strip-interception-plan.md).
# tests/unit/ai/data/pass_lane_truth.txt is flat feeds, saucers and rims to a bot
# receiver past a defender who reads the windup and knows where the puck is
# going — whether he intercepted it — measured by
# tests/instruments/ai/test_pass_truth.gd (passes nobody caught are the
# reception's, and left out). Each pass is read from the defender's start, as
# the passer reads it.
#
# Ratchets on the flat feeds and rims together: how often an intercepted pass
# read riskier than a completed one may not fall, and the interceptions the
# reads expect, against those that happened, may not stray further from one. The
# saucers' ranking is held too; their level is not yet — every read expects
# about three times the interceptions a saucer suffers.

const TRUTH_PATH: String = "res://tests/unit/ai/data/pass_lane_truth.txt"

const MIN_RANKING: float = 0.85
const MAX_EXPECTED_RATIO_ERR: float = 0.15
const MIN_SAUCER_RANKING: float = 0.82
const BANK_MARGIN: float = 0.02


func test_the_lane_reads_read_a_worst_case_interceptor() -> void:
	var f := FileAccess.open(TRUTH_PATH, FileAccess.READ)
	assert_not_null(f, "the truth table exists: %s" % TRUTH_PATH)
	if f == null:
		return
	var risk: Array[float] = []
	var lost: Array[bool] = []
	var saucer_risk: Array[float] = []
	var saucer_lost: Array[bool] = []
	while not f.eof_reached():
		var line: String = f.get_line()
		if line.is_empty() or line.begins_with("#"):
			continue
		var t: PackedStringArray = line.split("\t")
		var o := Vector3(float(t[2]), 0, float(t[3]))
		var r := Vector3(float(t[4]), 0, float(t[5]))
		var launch := Vector3(float(t[6]), float(t[7]), float(t[8]))
		var defs: Array[Vector3] = [Vector3(float(t[9]), 0, float(t[10]))]
		var vels: Array[Vector3] = [Vector3(float(t[11]), 0, float(t[12]))]
		var lane: float = _lane(t[0], o, r, launch, defs, vels)
		if lane < 0.0:
			continue
		if t[0] == "saucer":
			saucer_risk.append(1.0 - lane)
			saucer_lost.append(t[1] == "1")
		else:
			risk.append(1.0 - lane)
			lost.append(t[1] == "1")
	var expected: float = 0.0
	var n_lost: int = 0
	for i: int in risk.size():
		expected += risk[i]
		n_lost += 1 if lost[i] else 0
	var ranking: float = _ranking(risk, lost)
	var ratio: float = n_lost / expected
	var saucer_ranking: float = _ranking(saucer_risk, saucer_lost)
	gut.p("flat and rim: %d passes, %d intercepted against %.1f expected (%.2f); ranking %.3f" % [
			risk.size(), n_lost, expected, ratio, ranking])
	gut.p("saucer: %d passes, ranking %.3f" % [saucer_risk.size(), saucer_ranking])
	assert_gte(ranking, MIN_RANKING, "the interceptions read riskier than the passes completed")
	assert_lte(absf(ratio - 1.0), MAX_EXPECTED_RATIO_ERR, "the interceptions it expects are the interceptions")
	assert_gte(saucer_ranking, MIN_SAUCER_RANKING, "the saucers' interceptions read riskier")
	if ranking > MIN_RANKING + BANK_MARGIN:
		gut.p("ranking %.3f beats its ratchet by more than %.2f: bank it" % [ranking, BANK_MARGIN])


# The lane the bots read for a `kind` pass from `o` to `r` launched at `launch`;
# -1 for a rim launch the search does not produce.
func _lane(kind: String, o: Vector3, r: Vector3, launch: Vector3, defs: Array[Vector3],
		vels: Array[Vector3]) -> float:
	var pace: float = Vector2(launch.x, launch.z).length()
	if kind == "flat":
		return AIPuckLane.lane_clear(o, r, defs, pace, vels, [], true)
	if kind == "saucer":
		return AIPuckLane.lane_clear_saucer(o, r, defs, pace, vels, [])
	var no_caps: Array[AISkaterCaps] = []
	AIRimPass.build(o, AIBotMechanics.WRISTER_SHOT_SPEED_M_S, signf(o.z) * GameRules.GOAL_LINE_Z,
			defs, vels, no_caps)
	var dir := Vector3(launch.x, 0, launch.z) / pace
	for k: int in AIRimPass.count:
		if AIRimPass.dirs[k].distance_to(dir) < 0.01 and absf(AIRimPass.paces[k] - pace) < 0.05:
			return AIRimPass.lane(k, AIRimPass.meet_time(k, r, Vector3.ZERO, null))
	return -1.0


# How often a lost pass read riskier than a kept one.
func _ranking(risk: Array[float], lost: Array[bool]) -> float:
	var concordant: float = 0.0
	var pairs: float = 0.0
	for a: int in risk.size():
		if not lost[a]:
			continue
		for b: int in risk.size():
			if lost[b]:
				continue
			pairs += 1.0
			concordant += 1.0 if risk[a] > risk[b] else (0.5 if risk[a] == risk[b] else 0.0)
	return concordant / pairs if pairs > 0.0 else 0.0
