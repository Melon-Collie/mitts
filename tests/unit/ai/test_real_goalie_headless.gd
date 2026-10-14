extends GutTest

# The REAL GoalieController ticks headless from the real Goalie / Puck scenes
# and challenges a slot threat: no physics or contact is needed for positioning.

const GOAL_Z: float = -GameRules.GOAL_LINE_Z   # goalie defends the -Z net

var _goalie: Node = null
var _puck: Node = null
var _ctrl: GoalieController = null
# A REAL Skater for the goalie's world view: its typed scan reads only Skater
# nodes, and every read that needs other bodies (screens, the backdoor cap,
# contest pressure) sees nobody without one.
var _shooter: Skater = null


func before_each() -> void:
	_goalie = load("res://Scenes/Goalie.tscn").instantiate()
	_puck = load("res://Scenes/Puck.tscn").instantiate()
	_shooter = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(_goalie)
	add_child_autofree(_puck)
	add_child_autofree(_shooter)
	_shooter.set_physics_process(false)
	_shooter.set_process(false)
	_ctrl = GoalieController.new()
	add_child_autofree(_ctrl)


func _tick_with_puck_at(puck_pos: Vector3, ticks: int) -> Vector3:
	# Drive the puck node to a scripted threat spot each tick and step the
	# controller; return the goalie's resulting world position.
	for _i: int in ticks:
		_puck.global_position = puck_pos
		_shooter.global_position = puck_pos
		_ctrl._physics_process(1.0 / 120.0)
	return _goalie.global_position


func test_real_goalie_ticks_and_challenges() -> void:
	# An opposing shooter with the puck in the slot; the goalie should come OUT
	# (challenge) toward it rather than sit on the goal line.
	var shooter := Vector3(0.0, 0.0, GOAL_Z + 7.0)
	_puck.global_position = shooter
	_shooter.global_position = shooter
	_ctrl.set_skater_getter(func() -> Array: return [_shooter])
	_ctrl.setup(_goalie, _puck, GOAL_Z, true)

	var settled: Vector3 = _tick_with_puck_at(shooter, 240)   # 2 s to settle
	gut.p("goalie settled at x=%.2f z=%.2f (goal line z=%.2f)" % [
			settled.x, settled.z, GOAL_Z])
	var depth: float = absf(settled.z - GOAL_Z)
	assert_gt(depth, 0.3, "the real goalie CHALLENGES the slot threat (comes off his line)")
	assert_lt(absf(settled.x), 0.5, "…and squares up centred on a centred shooter")
