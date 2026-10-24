extends GutTest

# ── The shot-odds TRUTH TABLE (docs/shot-currency-plan.md, step 1) ───────────
# What a shot is worth is its odds against the live keeper. This
# measures them: for each cell (a release spot × a keeper state) it fires the
# bot's real release at the real goalie through real_goalie_shot_harness and
# records
#
#   outcomes — FLAT / LOW / HIGH, each a string of AIM_POINTS characters across
#              the mouth post to post: what that shot does, fired clean at full
#              wrister pace (G goal, s save, P post, w wide). The release is
#              deterministic, so this IS the goalie's open set; the odds for a
#              shooter of any scatter are this spread by his placement
#              distribution (test_shot_odds_vs_truth.gd does that).
#   picked   — the shot the field itself picks (AIShotOdds.pick_shot_now) from
#              the same read, and what it did.
#   read     — the replicated GoalieNetworkState at DECISION time: what a bot
#              sees when it decides whether to shoot from here; and for a feed,
#              the read square on the passer before it left.
#
# Run with MITTS_WRITE_SHOT_ODDS=1 to rewrite tests/unit/ai/data/shot_odds_truth.txt;
# without it the table is only printed. test_shot_odds_vs_truth.gd scores the
# model against that file with no live goalie. Re-run when the goalie changes.
#
# What it does not model: rebounds (first contact is the outcome, #785), screens,
# the shooter's own motion at release, and the passer (a feed is a loose puck
# arriving at the receiver).

const Stager := preload("res://tests/unit/ai/shot_odds_stager.gd")

const OUT_PATH: String = "res://tests/unit/ai/data/shot_odds_truth.txt"
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const FEED_SPEED_M_S: float = 16.0
const DEKE_ACROSS_M: float = 2.0

enum Scenario { SET, FEED_3_ONE_TIMER, FEED_3_CATCH, FEED_6_ONE_TIMER, FEED_6_CATCH, DEKE }
const SCENARIO_NAMES: Array[String] = ["SET", "FEED3_OT", "FEED3_CS", "FEED6_OT",
		"FEED6_CS", "DEKE"]

var _goal := Vector3(0.0, 0.0, GOAL_Z)
var _s: RefCounted = null


func before_each() -> void:
	var goalie: Node = load("res://Scenes/Goalie.tscn").instantiate()
	var puck: Node = load("res://Scenes/Puck.tscn").instantiate()
	var shooter: Skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	var ctrl := KeeperController.new()
	add_child_autofree(goalie)
	add_child_autofree(puck)
	add_child_autofree(shooter)
	add_child_autofree(ctrl)
	_s = Stager.new(goalie, puck, ctrl, shooter)


# Release spots as (lateral, metres out from the goal line).
func _spots() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for fwd: float in [2.5, 4.5, 7.0, 10.0]:
		for x: float in [-6.0, -3.0, 0.0, 3.0, 6.0]:
			out.append(Vector3(x, 0.0, GOAL_Z + fwd))
	return out


func _feed_distance(scenario: int) -> float:
	match scenario:
		Scenario.FEED_3_ONE_TIMER, Scenario.FEED_3_CATCH:
			return 3.0
		Scenario.FEED_6_ONE_TIMER, Scenario.FEED_6_CATCH:
			return 6.0
	return 0.0


# Toward the middle of the ice from `spot`.
func _inward(spot: Vector3) -> float:
	return -signf(spot.x) if absf(spot.x) > 0.1 else 1.0


# Re-stages `scenario` for a release at `spot` and returns the release point.
func _stager_for(spot: Vector3, scenario: int) -> Callable:
	var feed: float = _feed_distance(scenario)
	if feed > 0.0:
		var passer := Vector3(spot.x + _inward(spot) * feed, 0.0, spot.z)
		return func() -> Vector3: return _s.stage_feed(spot, passer, FEED_SPEED_M_S)
	if scenario == Scenario.DEKE:
		var across: float = _inward(spot) * DEKE_ACROSS_M
		return func() -> Vector3: return _s.stage_deke(spot, across)
	return func() -> Vector3: return _s.stage_set(spot)


func _row(spot: Vector3, scenario: int) -> String:
	var stage: Callable = _stager_for(spot, scenario)
	var one_timer: bool = scenario == Scenario.FEED_3_ONE_TIMER \
			or scenario == Scenario.FEED_6_ONE_TIMER
	var caught: bool = scenario == Scenario.FEED_3_CATCH or scenario == Scenario.FEED_6_CATCH
	var release: Vector3 = stage.call()
	var gs: GoalieNetworkState = _s.read()
	var keeper := Vector3(gs.position_x, 0.0, gs.position_z)
	var pick := AIShotOdds.Pick.new()
	AIShotOdds.pick_shot_now(release, _goal, keeper, gs.velocity_x,
			AIShotOdds.stance_of(gs, _goal), pick)
	var picked_aim: Vector3 = pick.aim if pick.aim.is_finite() else _goal
	var picked_loft: int = pick.loft
	var picked: String = _s.outcome(stage, one_timer, caught, picked_aim, picked_loft)
	var pre: GoalieNetworkState = gs
	if _feed_distance(scenario) > 0.0:
		pre = GoalieNetworkState.new()
		pre.copy_from(_s.pre_feed_read)
	var patterns: PackedStringArray = _s.open_set(stage, one_timer, caught)
	return "%.2f\t%.2f\t%s\t%.3f\t%.3f\t%s\t%s\t%s\t%.3f\t%d\t%s\t%s\t%s" % [
			release.x, release.z - GOAL_Z, SCENARIO_NAMES[scenario], spot.x, spot.z - GOAL_Z,
			patterns[0], patterns[1], patterns[2], picked_aim.x, picked_loft, picked,
			Stager.read_fields(gs), Stager.read_fields(pre)]


func test_measure_the_shot_odds() -> void:
	var lines: PackedStringArray = [
		"# Generated by tests/instruments/ai/test_shot_odds_truth.gd with "
				+ "MITTS_WRITE_SHOT_ODDS=1; never hand-edit.",
		"# release_x\trelease_fwd\tscenario\tspot_x\tspot_fwd\tflat\tlow\thigh"
				+ "\tpicked_aim_x\tpicked_loft\tpicked\tread(21: pos_x pos_z rot state five"
				+ " vel_x vel_z glove xyz blocker xyz lpad xyz lroll rpad xyz rroll)"
				+ "\tread before the feed left (21, = read when there is no feed)",
	]
	for spot: Vector3 in _spots():
		for scenario: int in SCENARIO_NAMES.size():
			var row: String = _row(spot, scenario)
			lines.append(row)
			gut.p(row.substr(0, 120))
	if OS.get_environment("MITTS_WRITE_SHOT_ODDS") == "1":
		var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
		assert_not_null(f, "can write %s" % OUT_PATH)
		if f != null:
			f.store_string("\n".join(lines) + "\n")
			f.close()
	assert_eq(lines.size(), 2 + _spots().size() * SCENARIO_NAMES.size())
