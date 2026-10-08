extends GutTest

# ── THE PUSH TO A REBOUND ────────────────────────────────────────────────────
# He has made the save from his knees and the puck sits loose in the slot, off
# to one side, with a shooter on it. A real goalie pushes as far as it takes to
# be square to the puck and no further, at the depth he is at.
#
# ── WHAT IT MEASURED (2026-10) ───────────────────────────────────────────────
# Put-backs at 25 m/s from four rebound spots, 7 aims x flat/low/high, 84 shots.
#
#   shooter releases after   knee shuffle only   push to square
#   0.4 s                    60                  33
#   0.8 s                    42                  21
#
# Before, a rebound inside his pad's reach got the 0.7 m/s knee shuffle and a
# wider one a slide that retreated to the post; either way the second shot met
# him off his angle. A quick put-back still beats him mid-push, which is how
# rebounds score.

const Harness := preload("res://tests/unit/ai/real_goalie_shot_harness.gd")
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const DT: float = 1.0 / 120.0
const MAX_AIM: float = GameRules.NET_HALF_WIDTH \
		- GameRules.NET_POST_RADIUS - GameRules.PUCK_COLLISION_RADIUS
const LOFTS: Array[int] = [
	ShotMechanics.ELEVATION_FLAT, ShotMechanics.ELEVATION_LOW, ShotMechanics.ELEVATION_HIGH,
]
const SPOTS: Array[Vector3] = [
	Vector3(1.2, 0.0, GOAL_Z + 2.0), Vector3(-1.2, 0.0, GOAL_Z + 2.0),
	Vector3(2.0, 0.0, GOAL_Z + 2.5), Vector3(0.7, 0.0, GOAL_Z + 1.6),
]

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


# Down at the centre after the save, the puck loose at `spot` with the shooter
# on it for `wait_s`.
func _rebound(spot: Vector3, wait_s: float) -> void:
	_h.settle_ready(Vector3(0.0, 0.0, GOAL_Z + 6.0))
	_ctrl._enter_butterfly()
	_puck.clear_carrier()
	_puck.global_position = spot
	_puck.linear_velocity = Vector3.ZERO
	# The teleport reads as a puck in flight for a tick; the save that left it
	# there is what resolves it.
	for _i: int in 2:
		_ctrl._physics_process(DT)
	_ctrl._on_puck_contact(_goalie)
	_shooter.global_position = spot + Vector3(0.0, 0.0, 0.4)
	_shooter.velocity = Vector3.ZERO
	_shooter.current_shot_state = SkaterStateMachine.State.SKATING_WITHOUT_PUCK
	for _i: int in int(wait_s / DT):
		_puck.global_position = spot
		_puck.linear_velocity = Vector3.ZERO
		_ctrl._physics_process(DT)


func _square_x(spot: Vector3) -> float:
	return _ctrl._square_x_at_body_radius(spot)


func _goals(wait_s: float) -> int:
	var goals: int = 0
	for spot: Vector3 in SPOTS:
		for loft: int in LOFTS:
			for ai: int in 7:
				_rebound(spot, wait_s)
				var aim := Vector3(lerpf(-MAX_AIM, MAX_AIM, ai / 6.0), 0.0, GOAL_Z)
				if _h.fire_at(spot, aim, loft, 25.0, 0.0) == Harness.GOAL:
					goals += 1
	return goals


func test_he_pushes_to_square_not_to_the_post() -> void:
	for spot: Vector3 in SPOTS:
		_rebound(spot, 0.8)
		var off: float = absf(_ctrl._current_x - _square_x(spot))
		var covered: bool = _ctrl._sm.current == GoalieStateMachine.State.COVERING
		gut.p("rebound at %s: %.2f m off square, covered %s" % [spot, off, covered])
		# One inside his reach he smothers instead, which ends the play.
		assert_true(off < 0.12 or covered, "square to the rebound at %s" % spot)


func test_report_put_backs() -> void:
	for wait_s: float in [0.4, 0.8]:
		var row: Array[int] = []
		for flag: bool in [false, true]:
			_ctrl.rebound_push = flag
			row.append(_goals(wait_s))
		gut.p("put-back after %.1f s: knee shuffle %d, push to square %d of %d"
				% [wait_s, row[0], row[1], SPOTS.size() * LOFTS.size() * 7])
	assert_true(true)
