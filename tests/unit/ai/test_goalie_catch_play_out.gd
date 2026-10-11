extends GutTest

# ── A CAUGHT PUCK IS PLAYED, NEVER DROPPED ───────────────────────────────────
# When a glove catch's hold runs out (ARCADE and free play have no whistle), the
# puck must leave the crease already moving out of it. Set down loose at his
# skates, it sat in the blue paint through the stand-up and the crease clear's
# dwell: a free put-back for whoever was nearest, and turned toward a shooter
# the drop landed against his own pad, which pushed it toward the line.
#
# Two invariants, from the first tick the glove lets go:
#
#   IT IS ALREADY MOVING OUT. Every tick it gets further from the goal line,
#   and it starts at a speed only the sweep gives it.
#
#   NOTHING OF HIS TOUCHES IT. A sweep that runs back across his body (the
#   far-corner exit off a blade turned along the line) meets his pads.

const Harness := preload("res://tests/unit/ai/real_goalie_shot_harness.gd")
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const DT: float = 1.0 / 120.0
const RADIUS: float = GameRules.PUCK_COLLISION_RADIUS
const HOLD_TICKS_MAX: int = 240
const WATCH_TICKS: int = 60
# The shooter spots the goalie is settled against: square, off-angle both ways,
# and the sharp angle that turns him along the line.
const SPOTS: Array[Vector3] = [
	Vector3(0.0, 0.0, GOAL_Z + 6.0), Vector3(3.0, 0.0, GOAL_Z + 5.0),
	Vector3(-4.0, 0.0, GOAL_Z + 3.0), Vector3(6.0, 0.0, GOAL_Z + 1.5),
	Vector3(-1.5, 0.0, GOAL_Z + 3.0),
]

var _goalie: Node = null
var _puck: Node = null
var _shooter: Skater = null
var _ctrl: GoalieController = null
var _h: RefCounted = null
var _scratch := SweptDiscOBB.Result.new()
var _contact := GoalieContactDetector.Contact.new()


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
	# The real analytic drive, ticked in step with the controller.
	_puck.set_physics_process(false)
	_puck.set_server_mode(true)
	_puck.set_goalie_provider(func() -> Array: return [_goalie])


func _tick() -> void:
	_ctrl._physics_process(DT)
	_puck._physics_process(DT)


# Settle against `spot`, optionally drop him, then hand him the puck in the
# glove. Returns false when the stance he settled into cannot catch.
func _catch(spot: Vector3, down: bool) -> bool:
	_h.settle_ready(spot)
	if down:
		_ctrl._enter_butterfly()
		for _i: int in 40:
			_puck.global_position = spot
			_ctrl._physics_process(DT)
	_puck.clear_carrier()
	_shooter.current_shot_state = SkaterStateMachine.State.SKATING_WITHOUT_PUCK
	_puck.global_position = _goalie.get_glove_world_position()
	_puck.linear_velocity = Vector3.ZERO
	_ctrl._on_puck_caught(_goalie)
	return _ctrl._sm.is_catching()


func _out_of_crease(p: Vector3) -> float:
	return p.z - GOAL_Z


func _check_play_out(spot: Vector3, down: bool) -> void:
	var label: String = "%s %s" % [spot, "down" if down else "upright"]
	if not _catch(spot, down):
		fail_test("%s: no catch" % label)
		return
	_tick()  # the first squeeze tick pins it into the glove
	assert_true(_puck.motion_pinned, "%s: pinned in the glove" % label)
	var held: int = 0
	while _puck.motion_pinned and held < HOLD_TICKS_MAX:
		_tick()
		held += 1
	assert_false(_puck.motion_pinned, "%s: the hold ends" % label)
	assert_gt(_puck.linear_velocity.length(), _ctrl.clear_max_puck_speed,
			"%s: it leaves the glove swept, not dropped" % label)
	var prev_out: float = _out_of_crease(_puck.global_position)
	var touched: String = ""
	var retreated: bool = false
	for _i: int in WATCH_TICKS:
		var prev: Vector3 = _puck.global_position
		_tick()
		var p: Vector3 = _puck.global_position
		if touched == "" and GoalieContactDetector.nearest(
				[_goalie], prev, p, RADIUS, _scratch, _contact):
			touched = String((_contact.part as Node).name)
		var out: float = _out_of_crease(p)
		if out < prev_out - 0.001:
			retreated = true
		prev_out = out
	assert_eq(touched, "", "%s: the swept puck never meets him" % label)
	assert_false(retreated, "%s: it only ever moves away from the line" % label)


func test_upright_catch_is_played_out() -> void:
	for spot: Vector3 in SPOTS:
		_check_play_out(spot, false)


func test_butterfly_catch_is_played_out() -> void:
	for spot: Vector3 in SPOTS:
		_check_play_out(spot, true)
