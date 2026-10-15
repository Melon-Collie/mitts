extends GutTest

# The shot model against the live goalie's measured odds
# (docs/shot-currency-plan.md, step 1). tests/unit/ai/data/shot_odds_truth.txt
# is the goalie's open set per cell, measured by
# tests/instruments/ai/test_shot_odds_truth.gd; this scores the per-hole model
# against it with no live goalie in the loop.
#
# The truth odds for a cell are the best aim and loft, with the measured
# outcome pattern spread by the placement scatter the model itself assumes
# (AIActionScoring.placement_spread at the Hard hand), so the two are compared
# on the same shooter. The model is fed exactly what the carrier feeds it from
# the replicated read at decision time.
#
# Two ratchets: mean |model − truth| may not grow, and concordance (does it
# order two cells the way the goalie does) may not fall. Both bank when step 2
# improves them.

const TRUTH_PATH: String = "res://tests/unit/ai/data/shot_odds_truth.txt"
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const SHOT_SPEED: float = AIBotMechanics.WRISTER_SHOT_SPEED_M_S
const REF_SPREAD_RAD: float = 0.01

# The ratchets. Tighten when a change wins by more than BANK_MARGIN.
const MAX_MEAN_ABS_ERR: float = 0.227
const MIN_CONCORDANCE: float = 0.79
const BANK_MARGIN: float = 0.02


class Cell:
	var release: Vector3
	var scenario: String
	var patterns: Array[String] = []
	var picked_aim_x: float
	var picked_loft: int
	var keeper: GoalieNetworkState = GoalieNetworkState.new()


func _cells() -> Array[Cell]:
	var out: Array[Cell] = []
	var f := FileAccess.open(TRUTH_PATH, FileAccess.READ)
	assert_not_null(f, "the truth table exists: %s" % TRUTH_PATH)
	if f == null:
		return out
	while not f.eof_reached():
		var line: String = f.get_line()
		if line.is_empty() or line.begins_with("#"):
			continue
		var t: PackedStringArray = line.split("\t")
		var c := Cell.new()
		c.release = Vector3(float(t[0]), 0.0, GOAL_Z + float(t[1]))
		c.scenario = t[2]
		c.patterns = [t[5], t[6], t[7]]
		c.picked_aim_x = float(t[8])
		c.picked_loft = int(t[9])
		var r: Array[float] = []
		for i: int in range(11, 32):
			r.append(float(t[i]))
		var g: GoalieNetworkState = c.keeper
		g.position_x = r[0]
		g.position_z = r[1]
		g.rotation_y = r[2]
		g.state_enum = int(r[3])
		g.five_hole_openness = r[4]
		g.velocity_x = r[5]
		g.velocity_z = r[6]
		g.glove_offset = Vector3(r[7], r[8], r[9])
		g.blocker_offset = Vector3(r[10], r[11], r[12])
		g.left_pad_offset = Vector3(r[13], r[14], r[15])
		g.left_pad_roll = r[16]
		g.right_pad_offset = Vector3(r[17], r[18], r[19])
		g.right_pad_roll = r[20]
		out.append(c)
	return out


func _aim_reach() -> float:
	return GameRules.NET_HALF_WIDTH - GameRules.NET_POST_RADIUS - GameRules.PUCK_COLLISION_RADIUS


func _phi(z: float) -> float:
	return 0.5 * (1.0 + AIActionScoring._erf(z / sqrt(2.0)))


# P(goal) aiming at sample `i` of `pattern`: the crossing scatters by `sigma_m`
# about the aim, and a crossing scores as the nearest measured aim did.
func _p_at(pattern: String, i: int, sigma_m: float) -> float:
	var n: int = pattern.length()
	var step: float = 2.0 * _aim_reach() / float(n - 1)
	var aim: float = -_aim_reach() + step * float(i)
	var p: float = 0.0
	for j: int in n:
		if pattern[j] != "G":
			continue
		var x: float = -_aim_reach() + step * float(j)
		p += _phi((x + 0.5 * step - aim) / sigma_m) - _phi((x - 0.5 * step - aim) / sigma_m)
	return p


func _sigma_m(c: Cell) -> float:
	var dist: float = Vector2(c.release.x, c.release.z - GOAL_Z).length()
	return AIActionScoring.placement_spread(REF_SPREAD_RAD) * maxf(dist, 0.5)


# The measured odds: the best aim on the best loft.
func _truth(c: Cell) -> float:
	var best: float = 0.0
	for pattern: String in c.patterns:
		for i: int in pattern.length():
			best = maxf(best, _p_at(pattern, i, _sigma_m(c)))
	return best


# The measured odds of the shot the planner picked from this read.
func _truth_of_pick(c: Cell) -> float:
	var pattern: String = c.patterns[clampi(c.picked_loft, 0, 2)]
	var step: float = 2.0 * _aim_reach() / float(pattern.length() - 1)
	var i: int = clampi(roundi((c.picked_aim_x + _aim_reach()) / step), 0, pattern.length() - 1)
	return _p_at(pattern, i, _sigma_m(c))


# What the carrier's shoot-now read scores this release at.
func _model(c: Cell) -> float:
	var g: GoalieNetworkState = c.keeper
	var goal := Vector3(0.0, 0.0, GOAL_Z)
	var down: bool = g.is_down()
	return AIActionScoring.open_net_danger(c.release, goal,
			Vector3(g.position_x, 0.0, g.position_z), GameRules.NET_HALF_WIDTH,
			SHOT_SPEED, 0.0, GoalieBehaviorRules.five_hole_gap_m(down, g.five_hole_openness),
			down, g.post_seal_x_sign(GOAL_Z), g.is_post_seal_tall(), 0.0, 0.0,
			g.hands_read(GOAL_Z), g.pads_read(GOAL_Z))


func _concordance(model: Array[float], truth: Array[float]) -> float:
	var ok: int = 0
	var total: int = 0
	for i: int in truth.size():
		for j: int in range(i + 1, truth.size()):
			if absf(truth[i] - truth[j]) < 0.05:
				continue
			total += 1
			if (truth[i] > truth[j]) == (model[i] > model[j]):
				ok += 1
	return float(ok) / maxf(float(total), 1.0)


func test_the_model_against_the_measured_odds() -> void:
	var cells: Array[Cell] = _cells()
	assert_gt(cells.size(), 0, "the table has cells")
	var model: Array[float] = []
	var truth: Array[float] = []
	var err_sum: float = 0.0
	var pick_sum: float = 0.0
	var best_sum: float = 0.0
	var by_scenario: Dictionary = {}
	for c: Cell in cells:
		var m: float = _model(c)
		var t: float = _truth(c)
		model.append(m)
		truth.append(t)
		err_sum += absf(m - t)
		pick_sum += _truth_of_pick(c)
		best_sum += t
		var s: Array = by_scenario.get(c.scenario, [0.0, 0.0, 0.0, 0])
		s[0] += m
		s[1] += t
		s[2] += absf(m - t)
		s[3] += 1
		by_scenario[c.scenario] = s
	var mean_err: float = err_sum / float(cells.size())
	var concordance: float = _concordance(model, truth)
	gut.p("scenario     model   truth   |err|   (means over %d cells)" % cells.size())
	for name: String in by_scenario:
		var s: Array = by_scenario[name]
		var n: float = float(s[3])
		gut.p("%-10s  %6.3f  %6.3f  %6.3f" % [name, s[0] / n, s[1] / n, s[2] / n])
	gut.p("mean |model − truth| %.3f   concordance %.1f%%   planner's pick keeps %.0f%% of the best odds"
			% [mean_err, concordance * 100.0, 100.0 * pick_sum / maxf(best_sum, 0.0001)])
	assert_lte(mean_err, MAX_MEAN_ABS_ERR, "the model drifted further from the goalie")
	assert_gte(concordance, MIN_CONCORDANCE, "the model orders cells worse than it did")
	assert_false(mean_err < MAX_MEAN_ABS_ERR - BANK_MARGIN,
			"mean error is down to %.3f from %.3f: bank it in MAX_MEAN_ABS_ERR"
			% [mean_err, MAX_MEAN_ABS_ERR])
	assert_false(concordance > MIN_CONCORDANCE + BANK_MARGIN,
			"concordance is up to %.3f from %.3f: bank it in MIN_CONCORDANCE"
			% [concordance, MIN_CONCORDANCE])
