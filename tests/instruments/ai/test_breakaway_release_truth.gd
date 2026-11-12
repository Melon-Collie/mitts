extends GutTest

# ── Where a breakaway SHOULD be released: the live keeper's answer (#943) ─────
# A carrier driving straight in at breakaway pace, the keeper tracking him from
# far out, the wrister charged over the last stretch of the drive with its
# wind-up published, released at each distance off the goal line and fired at
# every aim and lift, saves played out (a goal in off him counts). Per release
# distance: the keeper's depth and the gap to him at the release, whether his
# poke was out, and the share of aims that score — the open net there — overall
# and by lift. The shot field never staged this carrier (its cells skate in
# from 4 m at 4 m/s and let the keeper settle), so this is what the bots'
# in-tight breakaway prices are compared against.

const Stager := preload("res://tests/unit/ai/shot_odds_stager.gd")
const Harness := preload("res://tests/unit/ai/real_goalie_shot_harness.gd")

const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const DRIVE_FROM_M: float = 25.0
const DRIVE_M_S: float = 9.0
const RELEASE_DISTS_M: Array[float] = [12.0, 10.0, 8.0, 7.0, 6.0, 5.0, 4.0, 3.0, 2.5, 2.0]
# The charge, skated: the wind-up is published over the last this-many metres.
const CHARGE_M: float = DRIVE_M_S * float(Stager.CHARGE_TICKS) * Stager.DT

var _s: RefCounted = null
var _h: RefCounted = null
var _ctrl: KeeperController = null
var _goalie: Node = null
var _puck: Node = null
var _shooter: Skater = null


func before_each() -> void:
	_goalie = load("res://Scenes/Goalie.tscn").instantiate()
	_puck = load("res://Scenes/Puck.tscn").instantiate()
	_shooter = load("res://Scenes/Skater.tscn").instantiate() as Skater
	_ctrl = KeeperController.new()
	for n: Node in [_goalie, _puck, _shooter, _ctrl]:
		add_child_autofree(n)
	_s = Stager.new(_goalie, _puck, _ctrl, _shooter)
	_h = _s._h


# Drives in cold, then charges over the last CHARGE_M; returns the release spot.
func _drive(lane_x: float, release_m: float, aim: Vector3, loft: int) -> Vector3:
	_h.settle_ready(Vector3(lane_x, 0.0, GOAL_Z + DRIVE_FROM_M))
	_h.drive_in(lane_x, DRIVE_FROM_M, release_m + CHARGE_M, DRIVE_M_S)
	return _h.drive_in(lane_x, release_m + CHARGE_M, release_m, DRIVE_M_S, aim, loft,
			Stager.SHOT_SPEED)


func _fire(at: Vector3, aim: Vector3, loft: int) -> bool:
	var vel: Vector3 = _h.shot_velocity_at(at, aim, loft, Stager.SHOT_SPEED, 0.0)
	_shooter.current_shot_state = SkaterStateMachine.State.FOLLOW_THROUGH
	_puck.clear_carrier()
	_puck.global_position = Vector3(at.x, _puck.ice_height, at.z)
	_puck.apply_release_velocity(vel)
	_puck.puck_released.emit()
	var r: int = _h.fire_tracking_rebound(at, aim, loft, Stager.SHOT_SPEED, 0.0)
	return r == Harness.GOAL or _h.rebound_goal


# The best aim's odds at the model's reference scatter (AIShotOdds
# .REFERENCE_SPREAD_RAD, about two aim steps either side at these ranges): the
# best mean over five neighbouring aims.
static func _best_window(hits: Array[int]) -> float:
	var best: float = 0.0
	for i: int in range(2, hits.size() - 2):
		var sum: int = 0
		for k: int in range(i - 2, i + 3):
			sum += hits[k]
		best = maxf(best, sum / 5.0)
	return best


func test_report_breakaway_release_truth() -> void:
	var lines: PackedStringArray = [
		"lane 0, driving %.0f m/s, charged over the last %.2f m, %d aims × %d lifts" % [
				DRIVE_M_S, CHARGE_M, Stager.AIM_POINTS, Stager.LOFTS.size()],
		"release off line | keeper depth  gap   poke | priced  best-aim | scores: all   FLAT   LOW   HIGH | FLAT post to post"]
	for d: float in RELEASE_DISTS_M:
		var goals: int = 0
		var shots: int = 0
		var by_loft: PackedStringArray = []
		var flat_row: String = ""
		var depth: float = NAN
		var gap: float = NAN
		var poking: int = 0
		var priced: float = NAN
		var best: float = 0.0
		for loft: int in Stager.LOFTS:
			var lg: int = 0
			var hits: Array[int] = []
			for i: int in Stager.AIM_POINTS:
				var aim := Vector3(Stager.aim_x(i), 0.0, GOAL_Z)
				var at: Vector3 = _drive(0.0, d, aim, loft)
				var keeper: Vector3 = (_goalie as Node3D).global_position
				depth = keeper.z - GOAL_Z
				gap = Vector2(at.x - keeper.x, at.z - keeper.z).length()
				if _ctrl._poking:
					poking += 1
				if is_nan(priced):
					var goal := Vector3(0.0, 0.0, GOAL_Z)
					priced = AIShotValue.now(at, goal, keeper, 0.0, AIShotOdds.Stance.UPRIGHT,
							atan2(keeper.x - at.x, keeper.z - at.z), AIShotOdds.History.CARRIED)
				var scored: bool = _fire(at, aim, loft)
				shots += 1
				hits.append(1 if scored else 0)
				if scored:
					goals += 1
					lg += 1
				if loft == ShotMechanics.ELEVATION_FLAT:
					flat_row += "G" if scored else "."
			by_loft.append("%.2f" % (float(lg) / Stager.AIM_POINTS))
			best = maxf(best, _best_window(hits))
		lines.append("%6.1f m        |   %4.2f m  %4.2f m  %3d |  %.2f    %.2f   | %.2f   %s | %s" % [
				d, depth, gap, poking, priced, best, float(goals) / maxf(shots, 1),
				"  ".join(by_loft), flat_row])
	gut.p("\n" + "\n".join(lines))
	assert_true(true)
