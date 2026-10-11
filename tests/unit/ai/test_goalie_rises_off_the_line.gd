extends GutTest

# ── HE STEPS OFF THE LINE, HE DOES NOT POP ───────────────────────────────────
# A catch made on the goal line plants him below `min_challenge_depth`,
# which only the shot-facing states enforce. When the hold ends and he recovers,
# the floor takes over again; it must bring him out at a pace he can skate. A
# one-tick clamp moved him 7 cm in 8 ms, a visible jump, and carried his pads
# into the puck he had just swept.
#
# The bound is his fastest standing movement, the T-push. The floor itself must
# still hold once he has stepped up to it.

const Harness := preload("res://tests/unit/ai/real_goalie_shot_harness.gd")
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const DT: float = 1.0 / 120.0
const WATCH_TICKS: int = 90
const HOLD_TICKS_MAX: int = 240
# Sharp angles: square to these he sits a few centimetres off the line.
const SPOTS: Array[Vector3] = [
	Vector3(6.0, 0.0, GOAL_Z + 1.5), Vector3(-6.0, 0.0, GOAL_Z + 1.5),
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
	_puck.set_physics_process(false)
	_puck.set_server_mode(true)
	_puck.set_goalie_provider(func() -> Array: return [_goalie])


func _tick() -> void:
	_ctrl._physics_process(DT)
	_puck._physics_process(DT)


func _depth() -> float:
	return (_goalie as Node3D).global_position.z - GOAL_Z


func _settle(spot: Vector3) -> void:
	_h.settle_ready(spot)
	_puck.clear_carrier()
	_shooter.current_shot_state = SkaterStateMachine.State.SKATING_WITHOUT_PUCK


# Tick through the hold, then watch the recovery: the largest single-tick move
# of his body, and where he ends up.
func _watch_recovery(label: String, start_depth: float) -> void:
	assert_lt(start_depth, _ctrl.min_challenge_depth - 0.03,
			"%s: planted below the floor, or this proves nothing" % label)
	var held: int = 0
	while _ctrl._sm.is_catching() and held < HOLD_TICKS_MAX:
		_tick()
		held += 1
	assert_false(_ctrl._sm.is_catching(), "%s: released" % label)
	var max_step: float = 0.0
	var prev := Vector2(_goalie.global_position.x, _goalie.global_position.z)
	for _i: int in WATCH_TICKS:
		_tick()
		var now := Vector2(_goalie.global_position.x, _goalie.global_position.z)
		max_step = maxf(max_step, now.distance_to(prev))
		prev = now
	assert_lte(max_step, _ctrl.t_push_speed * DT + 1e-4,
			"%s: no faster than a T-push (%.3f m in one tick)" % [label, max_step])
	assert_gte(_depth(), minf(_ctrl.rvh_depth, _ctrl.min_challenge_depth) - 1e-3,
			"%s: the floor still holds" % label)


func test_rising_from_a_catch_on_the_line() -> void:
	for spot: Vector3 in SPOTS:
		_settle(spot)
		var start: float = _depth()
		_puck.global_position = _goalie.get_glove_world_position()
		_puck.linear_velocity = Vector3.ZERO
		_ctrl._on_puck_caught(_goalie)
		_watch_recovery("catch vs %s" % spot, start)

