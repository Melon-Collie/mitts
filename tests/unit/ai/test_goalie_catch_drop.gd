extends GutTest

# A glove catch played on: he holds it, sets it down, and the crease sweep clears
# it. The set-down spot has to be past the blade's face. Put between blade and
# skates, the first step back toward his line drives the blade's back face into
# the puck and rakes it goalward through his pads — measured, 0.9 m of drag at
# zero puck velocity over one recovery, ending in his feet on the goal line.
#
# Drives the real controller and the real puck drive (goalie contact included)
# from the catch to the sweep.

const Harness := preload("res://tests/unit/ai/real_goalie_shot_harness.gd")
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const DT: float = 1.0 / 120.0
const TRACK_TICKS: int = 360
# Contact resolution leaves the odd millimetre of depenetration; a rake is tens
# of centimetres.
const GOALWARD_TOLERANCE_M: float = 0.02
const SHOOTERS: Array[Vector3] = [
	Vector3(0.0, 0.0, GOAL_Z + 8.0),
	Vector3(4.0, 0.0, GOAL_Z + 5.0),
	Vector3(-4.0, 0.0, GOAL_Z + 5.0),
	Vector3(2.0, 0.0, GOAL_Z + 3.0),
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
	_puck.set_physics_process(false)
	_h = Harness.new()
	_h.setup(_goalie, _puck, _ctrl, _shooter)
	_puck.set_server_mode(true)
	_puck.set_goalie_provider(func() -> Array: return [_goalie])


# Catch at the glove from `shooter`, unpressured, then run the drop, the
# recovery and the sweep. Returns [goalward drag past the drop spot (m),
# crossed the line, was swept].
func _catch_and_drop(shooter: Vector3, down: bool) -> Array:
	_h.settle_ready(shooter)
	if down:
		_ctrl._enter_butterfly()
		for _i: int in 40:
			_ctrl._physics_process(DT)
	_puck.clear_carrier()
	_puck.global_position = _goalie.get_glove_world_position()
	_puck.linear_velocity = Vector3.ZERO
	# Far enough off that the catch is a look-and-drop, not a freeze.
	_shooter.global_position = shooter + Vector3(0.0, 0.0, 4.0)
	_shooter.current_shot_state = SkaterStateMachine.State.SKATING_WITHOUT_PUCK
	_ctrl._on_puck_caught(_goalie)
	var drop_depth: float = INF
	var max_drag: float = 0.0
	var crossed: bool = false
	var swept: bool = false
	for _i: int in TRACK_TICKS:
		_ctrl._physics_process(DT)
		_puck._drive_analytic(DT)
		_puck.drain_contact_events()
		if _ctrl._sm.is_catching():
			continue
		var depth: float = _puck.global_position.z - GOAL_Z
		if drop_depth == INF:
			drop_depth = depth
		if depth < 0.0:
			crossed = true
		if _puck.linear_velocity.z > 1.0:
			swept = true
			break
		max_drag = maxf(max_drag, drop_depth - depth)
	return [max_drag, crossed, swept]


func test_a_dropped_catch_is_not_raked_into_his_own_net() -> void:
	for shooter: Vector3 in SHOOTERS:
		for down: bool in [false, true]:
			var r: Array = _catch_and_drop(shooter, down)
			var label: String = "%s from %s" % ["down" if down else "upright", shooter]
			gut.p("%s: goalward drag %.3f m, crossed %s, swept %s" % [label, r[0], r[1], r[2]])
			assert_lt(r[0], GOALWARD_TOLERANCE_M,
					"%s: the dropped puck was dragged goalward" % label)
			assert_false(r[1], "%s: the dropped puck crossed his goal line" % label)
			assert_true(r[2], "%s: the dropped puck was never swept clear" % label)
