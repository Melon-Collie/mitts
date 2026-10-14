extends GutTest

# Put-backs off a rebound he saved from his knees: goals with the push to square
# on and off. The behaviour itself is held by tests/unit/ai/test_goalie_rebound_push.gd.
#
# ── WHAT IT MEASURED (2026-10) ───────────────────────────────────────────────
# Put-backs at 25 m/s from four rebound spots, 7 aims x flat/low/high, 84 shots.
#
#   shooter releases after   knee shuffle only   push to square
#   0.4 s                    60                  33
#   0.8 s                    42                  21

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


func test_report_put_backs() -> void:
	for wait_s: float in [0.4, 0.8]:
		var row: Array[int] = []
		for flag: bool in [false, true]:
			_ctrl.rebound_push = flag
			row.append(_goals(wait_s))
		gut.p("put-back after %.1f s: knee shuffle %d, push to square %d of %d"
				% [wait_s, row[0], row[1], SPOTS.size() * LOFTS.size() * 7])
	assert_true(true)
