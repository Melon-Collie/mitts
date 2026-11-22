extends GutTest

# ── How the shot field reads a breakaway, against the live keeper (#946) ──────
# A carrier driving straight in at breakaway pace, the keeper tracking him from
# far out, read at the decision (the charge's start, as the bot reads him) and
# released at each distance off the goal line. Per lane and distance: the keeper
# as read, the field's price and pick (AIShotOdds.pick_shot_now, the carried-in
# history) with the keeper's stance as read and as the shot meets it (down in
# tight), the cells it blended for the second, and what the live keeper does to
# that pick: the pick itself and the aims within the reference scatter of it, against
# the best the open set offered there. A price over what its own pick scores is
# the field reading the wrong keeper, or the right keeper's holes in the wrong
# place.

const Stager := preload("res://tests/unit/ai/shot_odds_stager.gd")
const Harness := preload("res://tests/unit/ai/real_goalie_shot_harness.gd")

const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const DRIVE_FROM_M: float = 25.0
const DRIVE_M_S: float = 9.0
const LANES_X: Array[float] = [0.0, -1.5]
const RELEASE_DISTS_M: Array[float] = [5.0, 4.0, 3.5, 3.0, 2.5, 2.0, 1.5]
const CHARGE_M: float = DRIVE_M_S * float(Stager.CHARGE_TICKS) * Stager.DT
# The aims either side of the pick inside the reference scatter at these ranges
# (about two aim steps, as the truth instrument's best window).
const PICK_WINDOW: int = 2
const TOP_CELLS: int = 4

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


# Drives in to the charge's start and returns the keeper as read there.
func _to_decision(lane_x: float, release_m: float) -> GoalieNetworkState:
	_h.settle_ready(Vector3(lane_x, 0.0, GOAL_Z + DRIVE_FROM_M))
	_h.drive_in(lane_x, DRIVE_FROM_M, release_m + CHARGE_M, DRIVE_M_S)
	return _s.read()


# One shot from a fresh drive: charged over the last CHARGE_M, saves played out.
func _scores(lane_x: float, release_m: float, aim: Vector3, loft: int) -> bool:
	_to_decision(lane_x, release_m)
	var at: Vector3 = _h.drive_in(lane_x, release_m + CHARGE_M, release_m, DRIVE_M_S, aim,
			loft, Stager.SHOT_SPEED)
	var vel: Vector3 = _h.shot_velocity_at(at, aim, loft, Stager.SHOT_SPEED, 0.0)
	_shooter.current_shot_state = SkaterStateMachine.State.FOLLOW_THROUGH
	_puck.clear_carrier()
	_puck.global_position = Vector3(at.x, _puck.ice_height, at.z)
	_puck.apply_release_velocity(vel)
	_puck.puck_released.emit()
	var r: int = _h.fire_tracking_rebound(at, aim, loft, Stager.SHOT_SPEED, 0.0)
	return r == Harness.GOAL or _h.rebound_goal


func _aim_index(aim: Vector3) -> int:
	var best: int = 0
	for i: int in Stager.AIM_POINTS:
		if absf(Stager.aim_x(i) - aim.x) < absf(Stager.aim_x(best) - aim.x):
			best = i
	return best


func test_report_breakaway_field_read() -> void:
	var lines: PackedStringArray = [
		"drive %.0f m/s from %.0f m, read at the charge's start; the field's pick against the live keeper" % [
				DRIVE_M_S, DRIVE_FROM_M]]
	for lane: float in LANES_X:
		for d: float in RELEASE_DISTS_M:
			_row(lines, lane, d)
	gut.p("\n" + "\n".join(lines))
	assert_true(true)


func _row(lines: PackedStringArray, lane: float, d: float) -> void:
	var goal := Vector3(0.0, 0.0, GOAL_Z)
	var release := Vector3(lane, 0.0, GOAL_Z + d)
	var gs: GoalieNetworkState = _to_decision(lane, d)
	var keeper := Vector3(gs.position_x, 0.0, gs.position_z)
	var read_stance: int = AIShotOdds.stance_of(gs, goal)
	var as_read := AIShotOdds.Pick.new()
	AIShotOdds.pick_shot_now(release, goal, keeper, gs.velocity_x, read_stance, as_read,
			gs.rotation_y, null, AIShotOdds.History.CARRIED)
	# The stance the shot meets him in: down in tight, where he drops for the
	# carrier over the charge (AIGoalieModel.down_in_tight).
	var stance: int = AIShotOdds.Stance.DOWN if AIGoalieModel.down_in_tight(release, goal) \
			else read_stance
	var q := AIShotOdds.Query.new()
	q.use_native = false
	var pick := AIShotOdds.Pick.new()
	AIShotOdds.pick_shot_now(release, goal, keeper, gs.velocity_x, stance, pick,
			gs.rotation_y, q, AIShotOdds.History.CARRIED)
	lines.append("lane %+.1f, release %.1f m | keeper depth %.2f x %+.2f vel %+.2f stance read %d, met %d | priced as read %.2f; as met %.2f at aim %+.2f loft %d" % [
			lane, d, keeper.z - GOAL_Z, keeper.x, gs.velocity_x, read_stance, stance,
			as_read.odds, pick.odds, pick.aim.x if pick.aim.is_finite() else NAN, pick.loft])
	_cells(lines, q)
	if not pick.aim.is_finite():
		return
	var at_pick: int = 0
	var around: int = 0
	var n_around: int = 0
	var pi: int = _aim_index(pick.aim)
	for k: int in range(pi - PICK_WINDOW, pi + PICK_WINDOW + 1):
		if k < 0 or k >= Stager.AIM_POINTS:
			continue
		var g: bool = _scores(lane, d, Vector3(Stager.aim_x(k), 0.0, GOAL_Z), pick.loft)
		n_around += 1
		around += 1 if g else 0
		if k == pi:
			at_pick = 1 if g else 0
	var row: String = ""
	for i: int in Stager.AIM_POINTS:
		row += "G" if _scores(lane, d, Vector3(Stager.aim_x(i), 0.0, GOAL_Z), pick.loft) else "."
	lines.append("    live: pick %s, around the pick %d/%d | pick's loft post to post %s" % [
			"G" if at_pick == 1 else ".", around, n_around, row])


# The TOP_CELLS cells carrying the most weight: kind, spot, the keeper measured
# there and its odds.
func _cells(lines: PackedStringArray, q: AIShotOdds.Query) -> void:
	var order: Array[int] = []
	for j: int in q.cells.size():
		order.append(j)
	order.sort_custom(func(a: int, b: int) -> bool: return q.weights[a] > q.weights[b])
	for r: int in mini(TOP_CELLS, order.size()):
		var c: int = q.cells[order[r]]
		var t: PackedStringArray = AIShotFieldData.ROWS[c].split("\t")
		lines.append("    w %.2f %s %s spot (%s, %s) from %s | keeper off %+.2f vel %+.2f depth %.2f square %+.2f stance %d | odds %.2f" % [
				q.weights[order[r]], t[3], t[4], t[1], t[2], t[5], AIShotOdds._offset[c],
				AIShotOdds._velocity[c], AIShotOdds._depth[c], AIShotOdds._square[c],
				AIShotOdds._stance[c], AIShotOdds._odds[c]])
	lines.append("    (%d cells)" % q.cells.size())
