extends GutTest

# ── GROUND GIVEN TO A CARRIER IN TIGHT IS NOT RETAKEN ────────────────────────
# The rush backflow retreats him as a carrier closes. It used to switch off as
# soon as the carrier's CLOSING speed fell under `rush_min_closing_speed`, and
# then depth fell back to the standoff — 0.6 m off the puck — so he skated OUT
# at a man in tight. Two ways a carrier stops closing, both measured on a rush
# from 10 m at 7 m/s:
#
#   cut across the crease from 2.5 m   radius 0.75 -> 1.37 m, then the seal
#   stop at 2.8 m for 0.6 s            radius 0.78 -> 1.65 m
#
# and the walkaround after the stop at 3.5 m opened 1 aim point of 7 against 0
# with no stop. Held, he stays where the backflow put him. The cost is the
# honest one: a carrier who rushes, stops at 3-3.5 m and shoots now finds a
# corner (1/14, from 0/14 against a keeper a metre in front of him). Only the
# carrier who backed him in is held off: one who walked in slowly and stopped
# still gets the challenge, and outside the hash marks a stopped carrier is a set
# shooter and gets it too.

const Harness := preload("res://tests/unit/ai/human_wraparound_harness.gd")
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const DT: float = 1.0 / 120.0

var _h: RefCounted = null
var _ctrl: GoalieController = null
var _puck: Node = null
var _shooter: Skater = null


func before_each() -> void:
	var goalie: Node = load("res://Scenes/Goalie.tscn").instantiate()
	_puck = load("res://Scenes/Puck.tscn").instantiate()
	_shooter = load("res://Scenes/Skater.tscn").instantiate() as Skater
	_ctrl = GoalieController.new()
	for n: Node in [goalie, _puck, _shooter, _ctrl]:
		add_child_autofree(n)
	_h = Harness.new()
	_h.setup(goalie, _puck, _ctrl, _shooter)


func _rush_to(dist: float) -> float:
	_h.settle_ready(Vector3(0.0, 0.0, GOAL_Z + 10.0))
	_h.begin_trial()
	_h.bait_commit(0.0, 10.0, dist, 7.0)
	assert_true(_ctrl._sm.is_upright(), "precondition: the straight drive keeps him up")
	return _ctrl.challenge_radius()


func test_a_carrier_cutting_across_does_not_draw_him_out() -> void:
	var start_r: float = _rush_to(2.5)
	_h.trace_enabled = true
	_h.wrap_around(-1.6, 0.5, 1.5)
	var max_r: float = start_r
	for row: Array in _h.trace:
		var st: int = row[1]
		if st == GoalieStateMachine.State.READY or st == GoalieStateMachine.State.STANDING:
			max_r = maxf(max_r, row[3])
	gut.p("cut from radius %.2f, furthest-out upright radius %.2f" % [start_r, max_r])
	assert_lt(max_r, start_r + 0.05, "he does not step out toward a carrier crossing him")


func test_a_carrier_stopping_in_tight_does_not_draw_him_out() -> void:
	var start_r: float = _rush_to(2.8)
	var body: Vector3 = _shooter.global_position
	_shooter.velocity = Vector3.ZERO
	for _i: int in int(0.6 / DT):
		_puck.global_position = body
		_puck.linear_velocity = Vector3.ZERO
		_ctrl._physics_process(DT)
	gut.p("stopped at 2.8 m: radius %.2f -> %.2f" % [start_r, _ctrl.challenge_radius()])
	assert_lt(_ctrl.challenge_radius(), start_r + 0.05,
			"he holds the ground he gave a carrier who stopped in tight")


func test_a_carrier_who_never_rushed_him_is_still_challenged() -> void:
	_h.settle_ready(Vector3(0.0, 0.0, GOAL_Z + 3.0))
	assert_gt(_ctrl.challenge_radius(), 1.6, "a settled carrier in tight still meets A depth")
	_h.settle_ready(Vector3(0.0, 0.0, GOAL_Z + 6.1))
	assert_gt(_ctrl.challenge_radius(), 1.6, "and so does the dot-line shooter")
