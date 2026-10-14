extends GutTest

# ── THE PASS OUT FROM BEHIND THE NET ─────────────────────────────────────────
# A carrier behind the net or on the goal line feeds a receiver in the slot, who
# one-times it. The goalie starts sealed on his post (RVH / VH) and has the
# pass's flight to get square to the receiver.
#
# The goalie reads the pass's LINE (GoaliePassRead), plays the one-timer from
# the reception, and — when a shot from there will be a block anyway — drops and
# slides to the receiver's angle instead of blocking from wherever the deadline
# catches him.
#
# A square, sealed goalie takes the bottom of the net away, and the pass-out
# one-timer beats him upstairs — a lower blocker concedes more over a
# butterfly, which is that stance's real trade. The counts per loft are the
# reviewed snapshot, snapshots/goalie_pass_out.txt.
#
# The receiver is loaded for the one-timer through the feed: the drop-and-slide
# answers a one-timer and waits for one (test_goalie_pass_is_not_a_shot.gd holds
# the receiver who is not loaded, and is played standing).
#
# The block-or-react clock prices the pass from where it will be received, not
# from where the puck is, so he is square at the release rather than dropped
# mid-push off the angle.
#
# The doorstep feed (goal line -> 1.8 m) is the cross-crease race and is lost
# on every row; the high-slot feed (8 m) is a standing read, and he
# stays on his feet for it.

const Snapshot := preload("res://tests/snapshot.gd")
const Harness := preload("res://tests/unit/ai/real_goalie_shot_harness.gd")
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const DT: float = 1.0 / 120.0
const MAX_AIM: float = GameRules.NET_HALF_WIDTH \
		- GameRules.NET_POST_RADIUS - GameRules.PUCK_COLLISION_RADIUS
const PASS_SPEED: float = GameRules.DEFAULT_QUICK_PASS_POWER_M_S
const SWING_S: float = 0.15
const SHOT_SPEED: float = 30.0
const LOFTS: Array[int] = [
	ShotMechanics.ELEVATION_FLAT, ShotMechanics.ELEVATION_LOW,
	ShotMechanics.ELEVATION_MID, ShotMechanics.ELEVATION_HIGH,
]

const BEHIND_R := Vector3(1.6, 0.0, GOAL_Z - 1.2)
const CORNER_R := Vector3(4.0, 0.0, GOAL_Z + 0.3)
const SLOT_C := Vector3(0.3, 0.0, GOAL_Z + 5.0)
const SLOT_L := Vector3(-1.5, 0.0, GOAL_Z + 4.5)
const SLOT_C_DEEP := Vector3(0.0, 0.0, GOAL_Z + 5.5)
const HIGH_SLOT := Vector3(0.5, 0.0, GOAL_Z + 8.0)
const PASSES: Array = [[BEHIND_R, SLOT_C], [BEHIND_R, SLOT_L], [CORNER_R, SLOT_C_DEEP]]
const PASS_NAMES: Array[String] = ["behind-R -> slot C", "behind-R -> slot L",
		"corner-R -> slot C deep"]
const LOFT_NAMES: Array[String] = ["FLAT", "LOW", "MID", "HIGH"]

var _goalie: Node = null
var _puck: Node = null
var _shooter: Skater = null
var _ctrl: GoalieController = null
var _h: RefCounted = null
# Each row is deterministic (every trial resets the keeper), so a row one test
# measured is reused by the next instead of re-run.
var _rows: Dictionary = {}


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


# Settle him on the post against a carrier at `passer`, then march a pass to a
# receiver at `receiver`, loaded for the one-timer, and hold through the swing.
# One skater plays both parts: the passer's body leaves with the puck, the
# receiver's arrives.
func _pass_out(passer: Vector3, receiver: Vector3) -> void:
	_ctrl.reset_to_crease()
	_h.settle(passer, 240)
	_puck.clear_carrier()
	_shooter.global_position = receiver
	_shooter.velocity = Vector3.ZERO
	_shooter.current_shot_state = SkaterStateMachine.State.SLAPPER_CHARGE_WITHOUT_PUCK
	var vel: Vector3 = (receiver - passer).normalized() * PASS_SPEED
	var flight_ticks: int = int(passer.distance_to(receiver) / PASS_SPEED / DT)
	var pos: Vector3 = passer
	for i: int in flight_ticks + int(SWING_S / DT):
		if i < flight_ticks:
			pos += vel * DT
			_puck.global_position = pos
			_puck.linear_velocity = vel
		else:
			_puck.global_position = receiver
			_puck.linear_velocity = Vector3.ZERO
		_ctrl._physics_process(DT)


func _square_x(receiver: Vector3) -> float:
	var cfg := GoalieBehaviorRules.ArcConfig.new()
	cfg.net_half_width = _ctrl.net_half_width
	cfg.seal_inset = _ctrl.post_seal_inset
	cfg.seal_depth = _ctrl.rvh_depth
	cfg.post_integration_angle_deg = _ctrl.rvh_early_angle
	return GoalieBehaviorRules.target_arc_position(receiver, GOAL_Z, 0.0, 1,
			_ctrl._current_depth, cfg).x


# Goals per loft row, one-timing from `receiver` at seven aims.
func _goals_by_loft(passer: Vector3, receiver: Vector3) -> Array[int]:
	var key: String = "%s %s" % [passer, receiver]
	if _rows.has(key):
		return _rows[key]
	var rows: Array[int] = []
	for loft: int in LOFTS:
		var goals: int = 0
		for ai: int in 7:
			_pass_out(passer, receiver)
			var aim := Vector3(lerpf(-MAX_AIM, MAX_AIM, ai / 6.0), 0.0, GOAL_Z)
			if _h.fire_at(receiver, aim, loft, SHOT_SPEED, 0.0) == Harness.GOAL:
				goals += 1
		rows.append(goals)
	_rows[key] = rows
	return rows


func test_he_is_square_to_the_receiver_at_the_release() -> void:
	for c: Array in PASSES:
		_pass_out(c[0], c[1])
		var off: float = absf(_ctrl._current_x - _square_x(c[1]))
		assert_false(_ctrl._sm.is_post_integrated(), "the pass pulled him off the post")
		assert_lt(off, 0.08, "%s -> %s: %.3f m off square at the release" % [c[0], c[1], off])


func test_the_low_net_is_sealed_and_the_top_is_where_it_scores() -> void:
	for c: Array in PASSES:
		var rows: Array[int] = _goals_by_loft(c[0], c[1])
		assert_lte(rows[0] + rows[1], rows[2] + rows[3],
				"%s -> %s: the low net concedes no more than the top" % [c[0], c[1]])


func test_a_high_slot_reception_is_read_on_his_feet() -> void:
	_pass_out(BEHIND_R, HIGH_SLOT)
	assert_true(_ctrl._sm.is_upright(), "8 m out is a reaction save, not a block")
	assert_lt(absf(_ctrl._current_x - _square_x(HIGH_SLOT)), 0.03)


func test_a_pass_nobody_can_reach_leaves_him_on_his_post() -> void:
	_ctrl.reset_to_crease()
	_h.settle(BEHIND_R, 240)
	var stance: int = _ctrl._sm.current
	_puck.clear_carrier()
	# The only skater is far off the pass's line.
	_shooter.global_position = Vector3(-6.0, 0.0, GOAL_Z + 10.0)
	var vel := Vector3(-PASS_SPEED, 0.0, 0.0)
	var pos: Vector3 = BEHIND_R
	for _i: int in 12:
		pos += vel * DT
		_puck.global_position = pos
		_puck.linear_velocity = vel
		_ctrl._physics_process(DT)
	assert_eq(_ctrl._sm.current, stance, "a rim behind the net is not a pass to the slot")


# Rewrite with MITTS_UPDATE_SNAPSHOTS=1 (tests/snapshot.gd) and review the diff.
func test_goalie_pass_out_snapshot() -> void:
	var snap := Snapshot.new("res://tests/slow/ai/snapshots/goalie_pass_out.txt")
	for i: int in PASSES.size():
		var rows: Array[int] = _goals_by_loft(PASSES[i][0], PASSES[i][1])
		for l: int in rows.size():
			snap.record("%s, %s: goals of 7" % [PASS_NAMES[i], LOFT_NAMES[l]], rows[l])
	snap.verify(self)
