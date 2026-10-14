extends GutTest

# ── The shot-odds TRUTH TABLE (docs/shot-currency-plan.md, step 1) ───────────
# What a shot is worth is its odds against the live GoalieController. This
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
#   picked   — the shot the planner itself chooses (best_shot_aim /
#              best_shot_loft) from the same read, and what it did.
#   read     — the replicated GoalieNetworkState at DECISION time: what a bot
#              sees when it decides whether to shoot from here.
#
# Run with MITTS_WRITE_SHOT_ODDS=1 to rewrite tests/unit/ai/data/shot_odds_truth.txt;
# without it the table is only printed. test_shot_odds_vs_truth.gd scores the
# model against that file with no live goalie. Re-run when the goalie changes.
#
# What it does not model: rebounds (first contact is the outcome, #785), screens,
# the shooter's own motion at release, and the passer (a feed is a loose puck
# arriving at the receiver).

const Harness := preload("res://tests/unit/ai/real_goalie_shot_harness.gd")

const OUT_PATH: String = "res://tests/unit/ai/data/shot_odds_truth.txt"
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const DT: float = 1.0 / 120.0
const SHOT_SPEED: float = AIBotMechanics.WRISTER_SHOT_SPEED_M_S
const CHARGE_TICKS: int = AIBotMechanics.BOT_WRISTER_CHARGE_TICKS
# The planner's own pick is solved at the Hard hand's spread.
const REF_SPREAD_RAD: float = 0.01
# Post to post at ~6.5 cm.
const AIM_POINTS: int = 24
const LOFTS: Array[int] = [ShotMechanics.ELEVATION_FLAT, ShotMechanics.ELEVATION_LOW,
		ShotMechanics.ELEVATION_HIGH]
const FEED_SPEED_M_S: float = 16.0
# The deke: the carrier comes across this far onto the spot, over this long, at
# this forward pace, then charges the release.
const DEKE_ACROSS_M: float = 2.0
const DEKE_S: float = 0.4
const DEKE_FORWARD_M_S: float = 3.0
const OUTCOME_CHARS: String = "GsPw"

enum Scenario { SET, FEED_3_ONE_TIMER, FEED_3_CATCH, FEED_6_ONE_TIMER, FEED_6_CATCH, DEKE }
const SCENARIO_NAMES: Array[String] = ["SET", "FEED3_OT", "FEED3_CS", "FEED6_OT",
		"FEED6_CS", "DEKE"]

var _goal := Vector3(0.0, 0.0, GOAL_Z)
var _goalie: Node = null
var _puck: Node = null
var _shooter: Skater = null
var _ctrl: GoalieController = null
var _h: RefCounted = null


func before_each() -> void:
	_goalie = load("res://Scenes/Goalie.tscn").instantiate()
	_puck = load("res://Scenes/Puck.tscn").instantiate()
	_shooter = load("res://Scenes/Skater.tscn").instantiate() as Skater
	_ctrl = GoalieController.new()
	add_child_autofree(_goalie)
	add_child_autofree(_puck)
	add_child_autofree(_shooter)
	add_child_autofree(_ctrl)
	_h = Harness.new()
	_h.setup(_goalie, _puck, _ctrl, _shooter)


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


# Where a feed to `spot` comes from: across, toward the middle of the ice.
func _passer_for(spot: Vector3, dist: float) -> Vector3:
	var side: float = -signf(spot.x) if absf(spot.x) > 0.1 else 1.0
	return Vector3(spot.x + side * dist, 0.0, spot.z)


# Puts the keeper in `scenario`'s state for a release at `spot`, up to the moment
# the bot would decide, and returns where the puck is released from.
func _stage(spot: Vector3, scenario: int) -> Vector3:
	var feed: float = _feed_distance(scenario)
	if feed > 0.0:
		var from: Vector3 = _passer_for(spot, feed)
		_h.settle_ready(from)
		# The receiver waits at the spot; the puck travels to him loose.
		_shooter.global_position = spot
		_shooter.velocity = Vector3.ZERO
		_shooter.current_shot_state = SkaterStateMachine.State.SKATING_WITHOUT_PUCK
		_puck.clear_carrier()
		var ticks: int = maxi(int(feed / FEED_SPEED_M_S / DT), 1)
		var vel: Vector3 = (spot - from).normalized() * FEED_SPEED_M_S
		for i: int in ticks:
			_puck.global_position = from.lerp(spot, float(i + 1) / float(ticks))
			_puck.linear_velocity = vel
			_ctrl._physics_process(DT)
		return spot
	if scenario == Scenario.DEKE:
		var side: float = -signf(spot.x) if absf(spot.x) > 0.1 else 1.0
		_h.settle_ready(Vector3(spot.x - side * DEKE_ACROSS_M, 0.0,
				spot.z + DEKE_FORWARD_M_S * DEKE_S))
		return _h.deke_across(spot.x, DEKE_S, DEKE_FORWARD_M_S)
	_h.settle_ready(spot)
	return spot


# The bot's release from the staged state: a one-timer leaves cold off the feed;
# everything else charges the wrister first, publishing its aim as it does.
func _release(release: Vector3, scenario: int, aim: Vector3, loft: int) -> int:
	match scenario:
		Scenario.FEED_3_ONE_TIMER, Scenario.FEED_6_ONE_TIMER:
			return _h.fire_at(release, aim, loft, SHOT_SPEED, 0.0)
		Scenario.FEED_3_CATCH, Scenario.FEED_6_CATCH:
			_puck.set_carrier(_shooter)
	_h.hold_windup_at(release, aim, loft, SHOT_SPEED, CHARGE_TICKS)
	return _h.fire_release_at(release, aim, loft, SHOT_SPEED, 0.0)


func _outcome(spot: Vector3, scenario: int, aim: Vector3, loft: int) -> String:
	var release: Vector3 = _stage(spot, scenario)
	return OUTCOME_CHARS[_release(release, scenario, aim, loft)]


func _aim_x(i: int) -> float:
	var reach: float = GameRules.NET_HALF_WIDTH - GameRules.NET_POST_RADIUS \
			- GameRules.PUCK_COLLISION_RADIUS
	return lerpf(-reach, reach, float(i) / float(AIM_POINTS - 1))


func _read_fields(gs: GoalieNetworkState) -> String:
	var v: Array[float] = [gs.position_x, gs.position_z, gs.rotation_y,
			float(gs.state_enum), gs.five_hole_openness, gs.velocity_x, gs.velocity_z,
			gs.glove_offset.x, gs.glove_offset.y, gs.glove_offset.z,
			gs.blocker_offset.x, gs.blocker_offset.y, gs.blocker_offset.z,
			gs.left_pad_offset.x, gs.left_pad_offset.y, gs.left_pad_offset.z,
			gs.left_pad_roll,
			gs.right_pad_offset.x, gs.right_pad_offset.y, gs.right_pad_offset.z,
			gs.right_pad_roll]
	var parts: PackedStringArray = []
	for f: float in v:
		parts.append("%.4f" % f)
	return "\t".join(parts)


func _row(spot: Vector3, scenario: int) -> String:
	var release: Vector3 = _stage(spot, scenario)
	var gs := GoalieNetworkState.new()
	_ctrl.fill_state(gs)
	var read: String = _read_fields(gs)
	var keeper := Vector3(gs.position_x, 0.0, gs.position_z)
	var down: bool = gs.is_down()
	var five: float = GoalieBehaviorRules.five_hole_gap_m(down, gs.five_hole_openness)
	var hands: Vector4 = gs.hands_read(GOAL_Z)
	var pads: Vector4 = gs.pads_read(GOAL_Z)
	var seal_x: float = gs.post_seal_x_sign(GOAL_Z)
	var seal_tall: bool = gs.is_post_seal_tall()
	var picked_aim: Vector3 = AIActionScoring.best_shot_aim(release, _goal, keeper,
			GameRules.NET_HALF_WIDTH, SHOT_SPEED, 0.0, five, down, REF_SPREAD_RAD,
			seal_x, seal_tall, 0.0, hands, pads)
	var picked_loft: int = AIActionScoring.best_shot_loft(release, _goal, keeper,
			GameRules.NET_HALF_WIDTH, SHOT_SPEED, 0.0, five, down, seal_x, seal_tall,
			REF_SPREAD_RAD, 0.0, hands, pads)
	var picked: String = _outcome(spot, scenario, picked_aim, picked_loft)
	var patterns: PackedStringArray = []
	for loft: int in LOFTS:
		var p: String = ""
		for i: int in AIM_POINTS:
			p += _outcome(spot, scenario, Vector3(_aim_x(i), 0.0, GOAL_Z), loft)
		patterns.append(p)
	return "%.2f\t%.2f\t%s\t%.3f\t%.3f\t%s\t%s\t%s\t%.3f\t%d\t%s\t%s" % [
			release.x, release.z - GOAL_Z, SCENARIO_NAMES[scenario], spot.x, spot.z - GOAL_Z,
			patterns[0], patterns[1], patterns[2], picked_aim.x, picked_loft, picked, read]


func test_measure_the_shot_odds() -> void:
	var lines: PackedStringArray = [
		"# Generated by tests/instruments/ai/test_shot_odds_truth.gd with "
				+ "MITTS_WRITE_SHOT_ODDS=1; never hand-edit.",
		"# release_x\trelease_fwd\tscenario\tspot_x\tspot_fwd\tflat\tlow\thigh"
				+ "\tpicked_aim_x\tpicked_loft\tpicked\tread(21: pos_x pos_z rot state five"
				+ " vel_x vel_z glove xyz blocker xyz lpad xyz lroll rpad xyz rroll)",
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
