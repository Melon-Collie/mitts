extends GutTest

# How much of the net the live keeper gives up to a slower shot, and whether
# that is only the extra time the slower flight gives him (#921). The shot field
# is measured at the full wrister pace, so the shot value cannot tell a share of
# it from the whole; this decides how to give it the pace.
#
# Per staged keeper (the field's own staging, shot_odds_stager.gd) and release
# spot, the share of the field's aims (post to post × FLAT / LOW / HIGH) that
# score:
#
#   full     at the full wrister pace;
#   slow f   at that share of it;
#   +dt f    at the full pace, the keeper given the slow shot's extra flight
#            time (distance to the goal line / its pace, less the full shot's)
#            before the release.
#
# `+dt` is what reading the full-pace field with the keeper advanced by the extra
# flight prices. Where `slow` matches it, the cheap fix is honest; where `slow`
# concedes much less, his reach on the puck in flight does the saving and the
# field needs measuring per pace. Prints a table; asserts nothing.
#
#   MITTS_PACE_KINDS=SET,DEKE   narrow the staged keepers

const Stager := preload("res://tests/unit/ai/shot_odds_stager.gd")

const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const FULL: float = Stager.SHOT_SPEED
# A backhand's share and the arms-only share: the paces the holds release at.
const SHARES: Array[float] = [0.75, 0.55]
# Release spots (x, metres out from the goal line): in tight, the slot, range,
# a wide angle.
const SPOTS: Array[Vector2] = [Vector2(0.0, 2.5), Vector2(-2.0, 3.5), Vector2(3.0, 4.5),
		Vector2(0.0, 6.0), Vector2(-6.0, 6.0), Vector2(2.0, 9.5), Vector2(0.0, 12.0)]
const KINDS: Array[String] = ["SET", "DEKE", "DECOY", "FEED"]
const DEKE_ACROSS_M: float = 2.0
const DECOY_ACROSS_M: float = 3.0
const FEED_ACROSS_M: float = 3.5
const FEED_SPEED_M_S: float = 16.0

var _s: RefCounted = null
var _puck: Node = null
var _shooter: Skater = null
var _ctrl: KeeperController = null


func before_each() -> void:
	var goalie: Node = load("res://Scenes/Goalie.tscn").instantiate()
	_puck = load("res://Scenes/Puck.tscn").instantiate()
	_shooter = load("res://Scenes/Skater.tscn").instantiate() as Skater
	_ctrl = KeeperController.new()
	add_child_autofree(goalie)
	add_child_autofree(_puck)
	add_child_autofree(_shooter)
	add_child_autofree(_ctrl)
	_s = Stager.new(goalie, _puck, _ctrl, _shooter)


func _stage(kind: String, spot: Vector3) -> Callable:
	match kind:
		"DEKE":
			return func() -> Vector3: return _s.stage_deke(spot, DEKE_ACROSS_M)
		"DECOY":
			var decoy := Vector3(spot.x + DECOY_ACROSS_M, 0.0, spot.z)
			return func() -> Vector3: return _s.stage_decoy(spot, decoy)
		"FEED":
			var side: float = -1.0 if spot.x > 0.0 else 1.0
			var passer := Vector3(spot.x + side * FEED_ACROSS_M, 0.0, spot.z)
			return func() -> Vector3: return _s.stage_feed(spot, passer, FEED_SPEED_M_S)
	return func() -> Vector3: return _s.stage_set(spot)


# One release from a fresh staging: a feed one-timed cold, everything else
# charged first. `wait_s` more of the keeper reading it before it leaves.
func _shoot(stage: Callable, one_timer: bool, aim: Vector3, loft: int, speed: float,
		wait_s: float) -> int:
	var at: Vector3 = stage.call()
	var h: RefCounted = _s._h
	var wait_ticks: int = roundi(wait_s / DT)
	if one_timer:
		for _i: int in wait_ticks:
			_puck.global_position = at
			_puck.linear_velocity = Vector3.ZERO
			_ctrl._physics_process(DT)
		return h.fire_at(at, aim, loft, speed, 0.0)
	h.hold_windup_at(at, aim, loft, speed, Stager.CHARGE_TICKS + wait_ticks)
	return h.fire_release_at(at, aim, loft, speed, 0.0)


# The share of the field's aims that score.
func _goal_share(stage: Callable, one_timer: bool, speed: float, wait_s: float) -> float:
	var goals: int = 0
	var shots: int = 0
	for loft: int in Stager.LOFTS:
		for i: int in Stager.AIM_POINTS:
			var aim := Vector3(Stager.aim_x(i), 0.0, GOAL_Z)
			if Stager.OUTCOME_CHARS[_shoot(stage, one_timer, aim, loft, speed, wait_s)] == "G":
				goals += 1
			shots += 1
	return float(goals) / float(shots)


func test_report_the_keeper_against_a_slower_shot() -> void:
	var kinds: Array[String] = KINDS.duplicate()
	var only: String = OS.get_environment("MITTS_PACE_KINDS")
	if not only.is_empty():
		kinds.assign(only.split(","))
	var header: String = "%-6s %-14s %6s" % ["kind", "spot (x, out)", "full"]
	for f: float in SHARES:
		header += "   slow %.2f  +dt %.2f (dt s)" % [f, f]
	gut.p(header)
	for kind: String in kinds:
		for s: Vector2 in SPOTS:
			var spot := Vector3(s.x, 0.0, GOAL_Z + s.y)
			var stage: Callable = _stage(kind, spot)
			var one_timer: bool = kind == "FEED"
			var dist: float = Vector2(s.x, s.y).length()
			var line: String = "%-6s (%+5.1f, %4.1f)  %6.3f" % [kind, s.x, s.y,
					_goal_share(stage, one_timer, FULL, 0.0)]
			for f: float in SHARES:
				var extra_s: float = dist / (FULL * f) - dist / FULL
				line += "   %9.3f  %8.3f (%.2f)" % [
						_goal_share(stage, one_timer, FULL * f, 0.0),
						_goal_share(stage, one_timer, FULL, extra_s), extra_s]
			gut.p(line)
	assert_true(true)
