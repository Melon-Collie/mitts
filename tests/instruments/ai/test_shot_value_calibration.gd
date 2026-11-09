extends GutTest

# What a bot shot is worth, measured: real bots rush the real goalie
# (bot_vs_goalie_harness.gd: the bot's own shot, the keeper's posed collision,
# the rebound marched after), and every shot's PREDICTED value is set beside
# what happened. Two predictions:
#
#   priced   what the carrier's compete fired on (_phase_shoot_score: the value
#            seam at the winning hold, before hysteresis or pings)
#   xG       the game's xG stat at the same release (AIActionScoring
#            .expected_goals, at the shot's context spread)
#
# Read the reliability tables: a prediction on the right scale scores, in each
# bin, about as often as it says. The O-zone instruments showed the compete
# firing sharp-angle shots it priced at 15-20%; this is where that price meets
# the ice. Outcomes are first contact and, separately, a rebound buried by the
# same bot; nobody else is on the ice, so traffic and screens are absent.

const BotGoalie := preload("res://tests/unit/ai/bot_vs_goalie_harness.gd")
const GoalieScene: PackedScene = preload("res://Scenes/Goalie.tscn")
const PuckScene: PackedScene = preload("res://Scenes/Puck.tscn")
const SkaterScene: PackedScene = preload("res://Scenes/Skater.tscn")
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const ANGLES_DEG: Array[float] = [-85.0, -75.0, -60.0, -45.0, -30.0, -15.0, 0.0,
		15.0, 30.0, 45.0, 60.0, 75.0, 85.0]
const START_RADIUS: Array[float] = [6.0, 9.0, 12.0, 16.0, 20.0]
const RUSH_SPEEDS: Array[float] = [2.0, 4.0, 6.0]
const BINS: Array[float] = [0.0, 0.05, 0.10, 0.20, 0.35, 0.50, 2.0]

var _goalie: Node = null
var _puck: Node = null
var _shooter: Skater = null
var _ctrl: GoalieController = null
var _bg: RefCounted = null


func before_all() -> void:
	_goalie = GoalieScene.instantiate()
	_puck = PuckScene.instantiate()
	_shooter = SkaterScene.instantiate() as Skater
	_ctrl = KeeperController.new()
	for n: Node in [_goalie, _puck, _shooter, _ctrl]:
		add_child(n)
	_shooter.set_physics_process(false)
	_shooter.set_process(false)
	_bg = BotGoalie.new()
	_bg.setup(_goalie, _puck, _ctrl, _shooter)


func after_all() -> void:
	for n: Node in [_goalie, _puck, _shooter, _ctrl]:
		n.queue_free()


# Every rush of the grid for one tier: the shots, each with its two predictions.
func _shots(profile: BotSkillProfile) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var net := Vector3(0.0, 0.0, GOAL_Z)
	for radius: float in START_RADIUS:
		for deg: float in ANGLES_DEG:
			for speed: float in RUSH_SPEEDS:
				var a: float = deg_to_rad(deg)
				var start: Vector3 = net + Vector3(sin(a), 0.0, cos(a)) * radius
				if not AIStationSearch.is_legal_position(start):
					continue
				_ctrl.reset_to_crease()
				var r: Dictionary = _bg.run_rush(start, (net - start).normalized() * speed,
						profile)
				if r["outcome"] == BotGoalie.NO_SHOT:
					continue
				var keeper: Vector3 = r["goalie_pos"]
				r["xg"] = AIActionScoring.expected_goals(r["release"], net, keeper,
						AIActionScoring.xg_release_spread(false, r["shooter_speed"]),
						maxi(int(r["keeper_stance"]), 0))
				out.append(r)
	return out


static func _bin(v: float) -> int:
	for i: int in BINS.size() - 1:
		if v < BINS[i + 1]:
			return i
	return BINS.size() - 2


func _reliability(shots: Array[Dictionary], key: String) -> void:
	var n: Array[int] = []
	var sum: Array[float] = []
	var goals: Array[int] = []
	var reb: Array[int] = []
	for _i: int in BINS.size() - 1:
		n.append(0)
		sum.append(0.0)
		goals.append(0)
		reb.append(0)
	for r: Dictionary in shots:
		var b: int = _bin(float(r[key]))
		n[b] += 1
		sum[b] += float(r[key])
		if r["outcome"] == BotGoalie.GOAL:
			goals[b] += 1
		elif r["rebound_goal"]:
			reb[b] += 1
	gut.p("   by %s:     shots   says   scored  (+rebound)" % key)
	for b: int in BINS.size() - 1:
		if n[b] == 0:
			continue
		gut.p("     %.2f-%.2f   %4d   %5.3f   %5.3f   (%5.3f)" % [BINS[b], minf(BINS[b + 1], 1.0),
				n[b], sum[b] / n[b], float(goals[b]) / n[b], float(goals[b] + reb[b]) / n[b]])


func _zones(shots: Array[Dictionary]) -> void:
	var rows: Dictionary = {}
	for r: Dictionary in shots:
		var z: Dictionary = BotGoalie.zone_of(r["release"])
		var k: String = "%s  %s" % [z["angle_band"], z["dist_band"]]
		if not rows.has(k):
			rows[k] = [0, 0.0, 0.0, 0, 0]
		var row: Array = rows[k]
		row[0] += 1
		row[1] += float(r["priced"])
		row[2] += float(r["xg"])
		if r["outcome"] == BotGoalie.GOAL:
			row[3] += 1
		elif r["rebound_goal"]:
			row[4] += 1
	var keys: Array = rows.keys()
	keys.sort()
	gut.p("   zone (angle, distance)       shots  priced    xG   scored (+rebound)")
	for k: String in keys:
		var v: Array = rows[k]
		gut.p("     %-26s %4d   %5.3f  %5.3f  %5.3f  (%5.3f)" % [k, v[0], v[1] / v[0],
				v[2] / v[0], float(v[3]) / v[0], float(v[3] + v[4]) / v[0]])


func test_report_shot_value_against_outcomes() -> void:
	for tier: Array in [["NORMAL", BotSkillProfile.normal()], ["HARD", BotSkillProfile.hard()]]:
		var shots: Array[Dictionary] = _shots(tier[1])
		var goals: int = 0
		for r: Dictionary in shots:
			if r["outcome"] == BotGoalie.GOAL:
				goals += 1
		gut.p("── %s ── %d shots, %d first-contact goals (%.1f%%)" % [tier[0], shots.size(),
				goals, 100.0 * goals / maxf(shots.size(), 1)])
		_reliability(shots, "priced")
		_reliability(shots, "xg")
		_zones(shots)
	assert_true(true)


# ── The spots the O-zone bots fired from, measured ───────────────────────────
# A keeper who tracked the carry in, settled square on it (shot_odds_stager.gd,
# as the shot field and its truth table stage him), then every aim across the
# mouth fired at three lofts: his open set. From it, the odds a shooter of any
# scatter scores at the field's own pick, set beside what the field reads.

const Stager := preload("res://tests/unit/ai/shot_odds_stager.gd")
# Lateral scatters (radians) the open set is read at: the field's reference (the
# Normal hand), Hard's hand, and the xG stat's settled-shot context spread.
const SCATTERS: Array[float] = [AIShotOdds.REFERENCE_SPREAD_RAD, 0.01,
		AIActionScoring.XG_BASE_SPREAD_RAD]


static func _spots() -> Array[Vector2]:
	return [Vector2(-10.0, 2.2), Vector2(-8.1, 4.7), Vector2(-7.0, 1.8), Vector2(-6.0, 2.5),
			Vector2(-6.0, 1.5), Vector2(-4.0, 2.5), Vector2(0.0, 6.0), Vector2(0.0, 10.0),
			Vector2(-4.0, 19.0)]


# The odds of the open set (`patterns`: the stager's sweeps, then each loft's
# goal intervals) at aim index `i` of loft `li`, for a shooter scattering
# `spread` radians from `release`.
static func _odds_at(patterns: PackedStringArray, li: int, i: int, spread: float,
		release: Vector3, goal: Vector3) -> float:
	var sigma_m: float = spread * maxf(Vector2(release.x, release.z - goal.z).length(), 0.5)
	return AIShotOdds.interval_odds(
			AIShotOdds.decode_intervals(patterns[AIShotOdds.LOFTS.size() + li]),
			AIShotOdds.aim_x(i), sigma_m)


func test_report_the_shot_value_at_the_spots_bots_fire_from() -> void:
	var goalie: Node = GoalieScene.instantiate()
	var puck: Node = PuckScene.instantiate()
	var shooter: Skater = SkaterScene.instantiate() as Skater
	var ctrl := KeeperController.new()
	for n: Node in [goalie, puck, shooter, ctrl]:
		add_child_autofree(n)
	var s: RefCounted = Stager.new(goalie, puck, ctrl, shooter)
	var goal := Vector3(0.0, 0.0, GOAL_Z)
	gut.p("   spot (x, out)   field: live   set |  measured: pick@ref  pick@hard  pick@xG  best@ref | goals/72")
	for p: Vector2 in _spots():
		for mirror: float in [1.0, -1.0]:
			if p.x == 0.0 and mirror < 0.0:
				continue
			var spot := Vector3(p.x * mirror, 0.0, GOAL_Z + p.y)
			var stage: Callable = func() -> Vector3: return s.stage_set(spot)
			var release: Vector3 = stage.call()
			var gs: GoalieNetworkState = s.read()
			var keeper := Vector3(gs.position_x, 0.0, gs.position_z)
			var stance: int = AIShotOdds.stance_of(gs, goal)
			var live: float = AIShotValue.now(release, goal, keeper, gs.velocity_x, stance,
					gs.rotation_y)
			var pick := AIShotOdds.Pick.new()
			AIShotOdds.pick_shot_now(release, goal, keeper, gs.velocity_x, stance, pick,
					gs.rotation_y)
			var patterns: PackedStringArray = s.open_set(stage, false, false)
			var li: int = maxi(AIShotOdds.LOFTS.find(pick.loft), 0)
			var pi: int = 0
			for i: int in AIShotFieldData.AIM_POINTS:
				if absf(Stager.aim_x(i) - pick.aim.x) < absf(Stager.aim_x(pi) - pick.aim.x):
					pi = i
			var at_pick: Array[float] = []
			for spread: float in SCATTERS:
				at_pick.append(_odds_at(patterns, li, pi, spread, release, goal))
			var best: float = 0.0
			var goals: int = 0
			for l: int in AIShotOdds.LOFTS.size():
				goals += patterns[l].count("G")
				for i: int in AIShotFieldData.AIM_POINTS:
					best = maxf(best, _odds_at(patterns, l, i, SCATTERS[0], release, goal))
			gut.p("   (%5.1f, %4.1f)        %5.3f  %5.3f |        %5.3f      %5.3f    %5.3f     %5.3f |   %2d" % [
					spot.x, p.y, live, AIShotValue.set_keeper(release, goal), at_pick[0],
					at_pick[1], at_pick[2], best, goals])
	assert_true(true)
