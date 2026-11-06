extends GutTest

# The shot field's LIVE read (AIShotValue.now / .feed: the keeper as a bot reads
# him at its decision) against the keeper's measured open set, for the keeper in
# motion as well as set: fed across (3 m and 6 m, one-timed or caught), set on a
# decoy, tracking a deke, sealed on a wrap. Staged as the truth table stages
# them (shot_odds_stager.gd), at release spots on the field's grid, between its
# points and beyond it (past x = ±8 m, past 15 m out).
#
# Per cell: the live read after the play the staging stands for, the same read
# blind to the play (History.ANY), the field's own SET read, the measured best
# aim at the field's reference scatter (the quantity the live read estimates;
# for a feed, averaged over feeds like it: FEED_JITTER_M),
# and for the shots a carrier fires himself what the aim the field picks
# actually does. Rebounds and screens are out, as in the truth table.

const Stager := preload("res://tests/unit/ai/shot_odds_stager.gd")
const GoalieScene: PackedScene = preload("res://Scenes/Goalie.tscn")
const PuckScene: PackedScene = preload("res://Scenes/Puck.tscn")
const SkaterScene: PackedScene = preload("res://Scenes/Skater.tscn")
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const FEED_SPEED_M_S: float = 16.0
# A feed's measured best is averaged over these changes to its length and pace:
# at a sharp angle what the keeper concedes jumps with a metre of feed or a few
# m/s, and a bot prices a feed like the one it makes, not that one exactly.
const FEED_JITTER_M: Array[float] = [-0.5, 0.0, 0.5]
const FEED_JITTER_M_S: Array[float] = [-2.0, 0.0, 2.0]
const DEKE_ACROSS_M: float = 2.0
# Wraps only from in close: the release a carrier coming round the post makes.
const WRAP_MAX_OUT_M: float = 3.5

const SCENARIOS: Array[String] = ["SET", "FEED3_OT", "FEED3_CS", "FEED6_OT", "FEED6_CS",
		"DECOY", "DEKE", "WRAP"]

# The play a shooter saw before each staging (AIShotOdds.History).
const HISTORY: Dictionary = {
	"SET": AIShotOdds.History.CARRIED, "DEKE": AIShotOdds.History.CARRIED,
	"FEED3_CS": AIShotOdds.History.FED, "FEED6_CS": AIShotOdds.History.FED,
	"DECOY": AIShotOdds.History.FED, "WRAP": AIShotOdds.History.WRAPPED,
}

var _goal := Vector3(0.0, 0.0, GOAL_Z)
var _s: RefCounted = null


func before_all() -> void:
	var goalie: Node = GoalieScene.instantiate()
	var puck: Node = PuckScene.instantiate()
	var shooter: Skater = SkaterScene.instantiate() as Skater
	var ctrl := KeeperController.new()
	for n: Node in [goalie, puck, shooter, ctrl]:
		add_child_autofree(n)
	_s = Stager.new(goalie, puck, ctrl, shooter)


# Release spots as (lateral, metres out), by where they sit against the field's
# grid (AIShotFieldData: x in [-8, 8], 0.6 to 15 m out).
static func _spots() -> Dictionary:
	return {
		"on": [Vector2(-6, 2.5), Vector2(-4, 4.5), Vector2(0, 6.0), Vector2(2, 9.5),
				Vector2(6, 3.5), Vector2(-8, 1.5)],
		"between": [Vector2(-5, 3.0), Vector2(-3, 5.25), Vector2(1, 8.5), Vector2(5, 2.0),
				Vector2(-7, 6.75), Vector2(3, 1.0)],
		"beyond": [Vector2(-10, 2.2), Vector2(10, 1.5), Vector2(-9, 4.0), Vector2(9.5, 6.0),
				Vector2(-4, 17.0), Vector2(0, 18.0)],
	}


static func _inward(spot: Vector3) -> float:
	return -signf(spot.x) if absf(spot.x) > 0.1 else 1.0


static func _feed_m(scenario: String) -> float:
	if scenario.begins_with("FEED3"):
		return 3.0
	if scenario.begins_with("FEED6"):
		return 6.0
	return 0.0


# Re-stages `scenario` for a release at `spot`, returning the release point;
# an invalid Callable when the scenario does not apply there.
func _stager_for(spot: Vector3, scenario: String) -> Callable:
	var feed: float = _feed_m(scenario)
	if feed > 0.0:
		var passer := Vector3(spot.x + _inward(spot) * feed, 0.0, spot.z)
		return func() -> Vector3: return _s.stage_feed(spot, passer, FEED_SPEED_M_S)
	match scenario:
		"DECOY":
			var decoy := Vector3(-spot.x, 0.0, spot.z) if absf(spot.x) > 1.5 \
					else Vector3(spot.x + 4.0, 0.0, spot.z)
			return func() -> Vector3: return _s.stage_decoy(spot, decoy)
		"DEKE":
			return func() -> Vector3: return _s.stage_deke(spot, _inward(spot) * DEKE_ACROSS_M)
		"WRAP":
			if spot.z - GOAL_Z > WRAP_MAX_OUT_M:
				return Callable()
			var side: float = signf(spot.x) if absf(spot.x) > 0.1 else 1.0
			var behind := Vector3(side * 1.6, 0.0, GOAL_Z - 1.4)
			return func() -> Vector3: return _s.stage_wrap(spot, behind)
	return func() -> Vector3: return _s.stage_set(spot)


static func _sigma_m(release: Vector3) -> float:
	return AIShotOdds.REFERENCE_SPREAD_RAD \
			* maxf(Vector2(release.x, release.z - GOAL_Z).length(), 0.5)


# One cell: { live, blind (the read with no history), set, best, pick (what the
# picked aim scores; -1 for a one-timer), stance, seal (release inside the seal
# zone), matched (cells weighed), goals }, or {} when the scenario does not apply
# at `spot`.
func _cell(spot: Vector3, scenario: String) -> Dictionary:
	var stage: Callable = _stager_for(spot, scenario)
	if not stage.is_valid():
		return {}
	var one_timer: bool = scenario.ends_with("_OT")
	var caught: bool = scenario.ends_with("_CS")
	var release: Vector3 = stage.call()
	var gs: GoalieNetworkState = _s.read()
	var keeper := Vector3(gs.position_x, 0.0, gs.position_z)
	var stance: int = AIShotOdds.stance_of(gs, _goal)
	var live: float
	var blind: float
	var matched: int = 0
	var pick := AIShotOdds.Pick.new()
	if one_timer:
		var pre: GoalieNetworkState = _s.pre_feed_read
		var passer := Vector3(spot.x + _inward(spot) * _feed_m(scenario), 0.0, spot.z)
		live = AIShotValue.feed(passer, spot, FEED_SPEED_M_S, _goal,
				Vector3(pre.position_x, 0.0, pre.position_z), true)
		blind = live
	else:
		var history: int = HISTORY[scenario]
		live = AIShotValue.now(release, _goal, keeper, gs.velocity_x, stance, gs.rotation_y,
				history)
		blind = AIShotValue.now(release, _goal, keeper, gs.velocity_x, stance, gs.rotation_y)
		AIShotOdds.pick_shot_now(release, _goal, keeper, gs.velocity_x, stance, pick,
				gs.rotation_y, null, history)
		matched = AIShotOdds._worker.count
	var patterns: PackedStringArray = _s.open_set(stage, one_timer, caught)
	var sigma: float = _sigma_m(release)
	var intervals: Array[PackedFloat32Array] = []
	for li: int in AIShotOdds.LOFTS.size():
		intervals.append(AIShotOdds.decode_intervals(patterns[AIShotOdds.LOFTS.size() + li]))
	var goals: int = 0
	for li: int in AIShotOdds.LOFTS.size():
		goals += patterns[li].count("G")
	var at_pick: float = -1.0
	if not one_timer and pick.aim.is_finite():
		var pi: int = 0
		for i: int in AIShotFieldData.AIM_POINTS:
			if absf(Stager.aim_x(i) - pick.aim.x) < absf(Stager.aim_x(pi) - pick.aim.x):
				pi = i
		at_pick = AIShotOdds.interval_odds(intervals[maxi(AIShotOdds.LOFTS.find(pick.loft), 0)],
				AIShotOdds.aim_x(pi), sigma)
	var best: float = AIShotOdds.best_odds(intervals, sigma)
	if _feed_m(scenario) > 0.0:
		best = _jittered_best(spot, scenario, one_timer, caught, sigma)
	return {"live": live, "blind": blind, "set": AIShotValue.set_keeper(release, _goal),
			"best": best, "pick": at_pick, "goals": goals,
			"stance": stance, "seal": AIGoalieModel.in_post_seal_zone(release, _goal),
			"matched": matched}


# A feed staging's measured best aim, averaged over FEED_JITTER_M ×
# FEED_JITTER_M_S around its own length and pace.
func _jittered_best(spot: Vector3, scenario: String, one_timer: bool, caught: bool,
		sigma: float) -> float:
	var total: float = 0.0
	for dm: float in FEED_JITTER_M:
		for dv: float in FEED_JITTER_M_S:
			var passer := Vector3(spot.x + _inward(spot) * (_feed_m(scenario) + dm), 0.0, spot.z)
			var speed: float = FEED_SPEED_M_S + dv
			var stage: Callable = func() -> Vector3: return _s.stage_feed(spot, passer, speed)
			var patterns: PackedStringArray = _s.open_set(stage, one_timer, caught)
			var intervals: Array[PackedFloat32Array] = []
			for li: int in AIShotOdds.LOFTS.size():
				intervals.append(AIShotOdds.decode_intervals(
						patterns[AIShotOdds.LOFTS.size() + li]))
			total += AIShotOdds.best_odds(intervals, sigma)
	return total / float(FEED_JITTER_M.size() * FEED_JITTER_M_S.size())


static func _concordance(model: Array[float], truth: Array[float]) -> float:
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


func test_report_the_live_read_against_the_measured_keeper() -> void:
	var spots: Dictionary = _spots()
	var worst: Array = []
	gut.p("   scenario  where     cells  live   meas  |err|   bias   conc | at-pick  set  | blind  b-bias  b-conc")
	for scenario: String in SCENARIOS:
		for where: String in ["on", "between", "beyond"]:
			var live: Array[float] = []
			var meas: Array[float] = []
			var picks: Array[float] = []
			var sets: Array[float] = []
			var blinds: Array[float] = []
			for p: Vector2 in spots[where]:
				var spot := Vector3(p.x, 0.0, GOAL_Z + p.y)
				var c: Dictionary = _cell(spot, scenario)
				if c.is_empty():
					continue
				live.append(c["live"])
				meas.append(c["best"])
				sets.append(c["set"])
				blinds.append(c["blind"])
				if c["pick"] >= 0.0:
					picks.append(c["pick"])
				worst.append([absf(c["live"] - c["best"]), scenario, where, p, c])
			if live.is_empty():
				continue
			var err: float = 0.0
			var bias: float = 0.0
			var blind_bias: float = 0.0
			for i: int in live.size():
				err += absf(live[i] - meas[i])
				bias += live[i] - meas[i]
				blind_bias += blinds[i] - meas[i]
			var mean := func(a: Array[float]) -> float:
				var t: float = 0.0
				for v: float in a:
					t += v
				return t / maxf(a.size(), 1)
			gut.p("   %-9s %-8s  %3d   %5.3f  %5.3f  %5.3f  %+5.3f  %4.2f |  %s  %5.3f | %5.3f  %+5.3f   %4.2f" % [
					scenario, where, live.size(), mean.call(live), mean.call(meas),
					err / live.size(), bias / live.size(), _concordance(live, meas),
					"%5.3f" % mean.call(picks) if not picks.is_empty() else "  -  ",
					mean.call(sets), mean.call(blinds), blind_bias / live.size(),
					_concordance(blinds, meas)])
	worst.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	gut.p("   worst cells (|live - measured best|):")
	for w: Array in worst.slice(0, 12):
		var c: Dictionary = w[4]
		gut.p("     %-9s %-8s (%5.1f, %4.1f)  live %5.3f  measured %5.3f  at pick %5.3f  blind %5.3f  goals %2d/72  stance %d seal %s cells %d" % [
				w[1], w[2], w[3].x, w[3].y, c["live"], c["best"], c["pick"], c["blind"],
				c["goals"], c["stance"], str(c["seal"]), c["matched"]])
	assert_true(true)
