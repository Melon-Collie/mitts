extends GutTest

# ── Does a breakaway move beat the keeper? (#943) ─────────────────────────────
# A carrier driving straight in at a breakaway's pace, the keeper tracking him
# from far out, who then either releases straight (the baseline) or makes a
# move across the crease and releases from where it ends:
#   sweep — the body keeps driving straight while the puck is pulled across
#           (a forehand-backhand beat: real_goalie_shot_harness.sweep_across);
#   deke  — the body goes across with the puck leading it (deke_across).
# Each finish is fired at every aim and lift, saves played out, two ways that
# bracket a bot's: cold, the instant the move ends (no bot release is that
# quick), and charged in place, the wrister's whole charge held at the end spot
# (the keeper given that time back). Per case: where the puck ends, whether the
# keeper went down, and the share of aims that score.

const Stager := preload("res://tests/unit/ai/shot_odds_stager.gd")
const Harness := preload("res://tests/unit/ai/real_goalie_shot_harness.gd")

const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const DRIVE_FROM_M: float = 25.0
const DRIVE_M_S: float = 9.0
const CHARGE_M: float = DRIVE_M_S * float(Stager.CHARGE_TICKS) * Stager.DT
# The move: how long it takes, and the deke's forward pace (the lateral is
# bought out of the same legs).
const MOVE_S: float = 0.35
const DEKE_FORWARD_M_S: float = 4.0

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


# Stages one case and returns where the puck is released. `kind`: "straight"
# (charged in stride over the last CHARGE_M to `start_m`), "sweep" or "deke"
# (driven cold to `start_m`, then the move `width` across).
func _stage(kind: String, start_m: float, width: float, aim: Vector3, loft: int) -> Vector3:
	_h.settle_ready(Vector3(0.0, 0.0, GOAL_Z + DRIVE_FROM_M))
	if kind == "straight":
		_h.drive_in(0.0, DRIVE_FROM_M, start_m + CHARGE_M, DRIVE_M_S)
		return _h.drive_in(0.0, start_m + CHARGE_M, start_m, DRIVE_M_S, aim, loft,
				Stager.SHOT_SPEED)
	_h.drive_in(0.0, DRIVE_FROM_M, start_m, DRIVE_M_S)
	if kind == "sweep":
		return _h.sweep_across(width, MOVE_S, DRIVE_M_S)
	return _h.deke_across(width, MOVE_S, DEKE_FORWARD_M_S)


func _fire(at: Vector3, aim: Vector3, loft: int, charged: bool) -> bool:
	if charged:
		_h.hold_windup_at(at, aim, loft, Stager.SHOT_SPEED, Stager.CHARGE_TICKS)
	var vel: Vector3 = _h.shot_velocity_at(at, aim, loft, Stager.SHOT_SPEED, 0.0)
	_shooter.current_shot_state = SkaterStateMachine.State.FOLLOW_THROUGH
	_puck.clear_carrier()
	_puck.global_position = Vector3(at.x, _puck.ice_height, at.z)
	_puck.apply_release_velocity(vel)
	_puck.puck_released.emit()
	var r: int = _h.fire_tracking_rebound(at, aim, loft, Stager.SHOT_SPEED, 0.0)
	return r == Harness.GOAL or _h.rebound_goal


func _row(kind: String, start_m: float, width: float) -> String:
	var shares: PackedStringArray = []
	var end := Vector3.INF
	var down: int = 0
	var priced: float = NAN
	var flat_row: String = ""
	for charged: bool in [false, true]:
		if kind == "straight" and not charged:
			continue
		var goals: int = 0
		var shots: int = 0
		for loft: int in Stager.LOFTS:
			for i: int in Stager.AIM_POINTS:
				var aim := Vector3(Stager.aim_x(i), 0.0, GOAL_Z)
				var at: Vector3 = _stage(kind, start_m, width, aim, loft)
				end = at
				if not _ctrl._sm.is_upright():
					down += 1
				if is_nan(priced):
					priced = _priced(at)
				# The straight drive charged in stride; fire it as it leaves.
				var scored: bool = _fire(at, aim, loft, charged and kind != "straight")
				shots += 1
				goals += 1 if scored else 0
				if loft == ShotMechanics.ELEVATION_FLAT and charged:
					flat_row += "G" if scored else "."
		shares.append("%s %.2f" % ["charged" if charged else "cold", float(goals) / shots])
	return "%-8s from %.1f m, %.1f m across | ends (%5.2f, %.2f off) | keeper down %3d | priced %.2f | %-28s | %s" % [
			kind, start_m, width, end.x, end.z - GOAL_Z, down, priced, "  ".join(shares), flat_row]


# What the bots' shot model says of a shot from `at` against the keeper as he
# is now (AIShotValue.now, read off his replicated state as the carrier reads it).
func _priced(at: Vector3) -> float:
	var gs := GoalieNetworkState.new()
	_ctrl.fill_state(gs)
	var goal := Vector3(0.0, 0.0, GOAL_Z)
	return AIShotValue.now(at, goal, Vector3(gs.position_x, 0.0, gs.position_z), gs.velocity_x,
			AIShotOdds.stance_of(gs, goal), gs.rotation_y, AIShotOdds.History.CARRIED)


func test_report_breakaway_moves() -> void:
	var lines: PackedStringArray = [
		"drive %.0f m/s from %.0f m; a move takes %.2f s (deke forward %.0f m/s); %d aims × %d lifts; share of aims that score"
				% [DRIVE_M_S, DRIVE_FROM_M, MOVE_S, DEKE_FORWARD_M_S, Stager.AIM_POINTS,
				Stager.LOFTS.size()]]
	for d: float in [3.0, 2.5]:
		lines.append(_row("straight", d, 0.0))
	for kind: String in ["sweep", "deke"]:
		for start_m: float in [6.0, 5.0, 4.0]:
			for width: float in [1.0, 2.0]:
				lines.append(_row(kind, start_m, width))
	gut.p("\n" + "\n".join(lines))
	assert_true(true)
