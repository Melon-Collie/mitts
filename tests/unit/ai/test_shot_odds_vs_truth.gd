extends GutTest

# The bots' shot odds against the live goalie's measured odds
# (docs/shot-currency-plan.md). tests/unit/ai/data/shot_odds_truth.txt is the
# goalie's open set per cell, measured by tests/instruments/ai/test_shot_odds_truth.gd
# at spots, feed distances and paces the shot field (AIShotOdds) was NOT
# generated at, so this is a held-out check of how the field generalises.
#
# Truth and model are priced at the same placement scatter
# (AIShotOdds.REFERENCE_SPREAD_RAD). A settled or deked keeper is a shot_now
# query on the read at decision time; a feed is a feed query from the passer,
# the keeper as he stood square on him.
#
# Three ratchets: mean |model − truth| may not grow, concordance (does it order
# two cells the way the goalie does) may not fall, and neither may the share of
# the best odds the field's own pick keeps (AIShotOdds.pick_shot_now, the shot a
# bot fires). All bank when the field improves.

const TRUTH_PATH: String = "res://tests/unit/ai/data/shot_odds_truth.txt"
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const FEED_SPEED_M_S: float = 16.0

# The ratchets. Tighten when a change wins by more than BANK_MARGIN.
const MAX_MEAN_ABS_ERR: float = 0.109
const MIN_CONCORDANCE: float = 0.919
const MIN_PICK_SHARE: float = 0.801
const BANK_MARGIN: float = 0.02


class Cell:
	var release: Vector3
	var spot: Vector3
	var scenario: String
	var patterns := PackedStringArray()
	var keeper: GoalieNetworkState = GoalieNetworkState.new()
	var pre_keeper: GoalieNetworkState = GoalieNetworkState.new()


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
		c.spot = Vector3(float(t[3]), 0.0, GOAL_Z + float(t[4]))
		c.patterns = PackedStringArray([t[5], t[6], t[7]])
		_fill_read(c.keeper, t, 11)
		_fill_read(c.pre_keeper, t, 18)
		out.append(c)
	return out


# The stager's 7-field read starting at column `at`.
func _fill_read(g: GoalieNetworkState, t: PackedStringArray, at: int) -> void:
	var r: Array[float] = []
	for i: int in range(at, at + 7):
		r.append(float(t[i]))
	g.position_x = r[0]
	g.position_z = r[1]
	g.rotation_y = r[2]
	g.state_enum = int(r[3])
	g.five_hole_openness = r[4]
	g.velocity_x = r[5]
	g.velocity_z = r[6]


func _sigma_m(c: Cell) -> float:
	return AIShotOdds.REFERENCE_SPREAD_RAD \
			* maxf(Vector2(c.release.x, c.release.z - GOAL_Z).length(), 0.5)


func _truth(c: Cell) -> float:
	return AIShotOdds.best_odds(c.patterns, _sigma_m(c))


# The measured odds of firing at `aim_x` (the net's frame) on `loft`.
func _truth_at(c: Cell, aim_x: float, loft: int) -> float:
	var n: int = AIShotFieldData.AIM_POINTS
	var reach: float = GameRules.NET_HALF_WIDTH - GameRules.NET_POST_RADIUS \
			- GameRules.PUCK_COLLISION_RADIUS
	var i: int = clampi(roundi((aim_x + reach) / (2.0 * reach) * float(n - 1)), 0, n - 1)
	return AIShotOdds.aim_odds(c.patterns[AIShotOdds.LOFTS.find(loft)], i, _sigma_m(c))


# The cells a bot fires from its own carry: settled, deked, and caught off a feed.
func _fires_from_the_carry(c: Cell) -> bool:
	return not c.scenario.ends_with("_OT")


func _feed_distance(c: Cell) -> float:
	if c.scenario.begins_with("FEED3"):
		return 3.0
	if c.scenario.begins_with("FEED6"):
		return 6.0
	return 0.0


func _model(c: Cell) -> float:
	var goal := Vector3(0.0, 0.0, GOAL_Z)
	var feed: float = _feed_distance(c)
	if feed <= 0.0:
		return AIShotOdds.shot_now(c.release, goal, _pos(c.keeper), c.keeper.velocity_x,
				AIShotOdds.stance_of(c.keeper, goal))
	var inward: float = -signf(c.spot.x) if absf(c.spot.x) > 0.1 else 1.0
	var passer := Vector3(c.spot.x + inward * feed, 0.0, c.spot.z)
	return AIShotOdds.feed(passer, c.spot, FEED_SPEED_M_S, goal, _pos(c.pre_keeper),
			c.scenario.ends_with("_OT"))


func _pos(g: GoalieNetworkState) -> Vector3:
	return Vector3(g.position_x, 0.0, g.position_z)


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


func test_the_shot_field_against_the_measured_odds() -> void:
	var cells: Array[Cell] = _cells()
	assert_gt(cells.size(), 0, "the table has cells")
	var model: Array[float] = []
	var truth: Array[float] = []
	var by_scenario: Dictionary = {}
	for c: Cell in cells:
		var m: float = _model(c)
		var t: float = _truth(c)
		model.append(m)
		truth.append(t)
		var s: Array = by_scenario.get(c.scenario, [0.0, 0.0, 0.0, 0])
		s[0] += m
		s[1] += t
		s[2] += absf(m - t)
		s[3] += 1
		by_scenario[c.scenario] = s
	var err: float = 0.0
	for i: int in cells.size():
		err += absf(model[i] - truth[i])
	err /= float(cells.size())
	var concordance: float = _concordance(model, truth)
	var best_sum: float = 0.0
	var pick_sum: float = 0.0
	var pick := AIShotOdds.Pick.new()
	for c: Cell in cells:
		if not _fires_from_the_carry(c):
			continue
		AIShotOdds.pick_shot_now(c.release, Vector3(0.0, 0.0, GOAL_Z), _pos(c.keeper),
				c.keeper.velocity_x,
				AIShotOdds.stance_of(c.keeper, Vector3(0.0, 0.0, GOAL_Z)), pick)
		best_sum += _truth(c)
		if pick.aim.is_finite():
			pick_sum += _truth_at(c, pick.aim.x, pick.loft)
	var pick_share: float = pick_sum / maxf(best_sum, 0.0001)
	gut.p("scenario     field   truth   |err|   (%d cells)" % cells.size())
	for scenario: String in by_scenario:
		var s: Array = by_scenario[scenario]
		var n: float = float(s[3])
		gut.p("%-10s  %6.3f  %6.3f  %6.3f" % [scenario, s[0] / n, s[1] / n, s[2] / n])
	gut.p("field: mean |err| %.3f, concordance %.1f%%" % [err, concordance * 100.0])
	gut.p("firing from the carry, the pick keeps %.0f%% of the best odds"
			% [100.0 * pick_share])
	assert_gte(pick_share, MIN_PICK_SHARE, "the field's pick keeps less of the best odds")
	assert_false(pick_share > MIN_PICK_SHARE + BANK_MARGIN,
			"the pick keeps %.3f of the best odds, up from %.3f: bank it in MIN_PICK_SHARE"
			% [pick_share, MIN_PICK_SHARE])
	assert_lte(err, MAX_MEAN_ABS_ERR, "the field drifted further from the goalie")
	assert_gte(concordance, MIN_CONCORDANCE, "the field orders cells worse than it did")
	assert_false(err < MAX_MEAN_ABS_ERR - BANK_MARGIN,
			"mean error is down to %.3f from %.3f: bank it in MAX_MEAN_ABS_ERR"
			% [err, MAX_MEAN_ABS_ERR])
	assert_false(concordance > MIN_CONCORDANCE + BANK_MARGIN,
			"concordance is up to %.3f from %.3f: bank it in MIN_CONCORDANCE"
			% [concordance, MIN_CONCORDANCE])
