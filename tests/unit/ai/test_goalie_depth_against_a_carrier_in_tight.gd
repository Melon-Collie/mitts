extends GutTest

# ── GROUND GIVEN TO A CARRIER IN TIGHT IS NOT RETAKEN ────────────────────────
# The rush backflow retreats him as a carrier closes. When the carrier stops
# closing — a cut across the crease, or a stop in tight — he holds where the
# backflow put him instead of falling back to the standoff and skating out at a
# man in tight. Only the carrier who backed him in is held off: one who walked
# in and stopped still gets the challenge, and outside the hash marks a stopped
# carrier is a set shooter and gets it too.

const Snapshot := preload("res://tests/snapshot.gd")
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
	# Only the carrier who backed him in is held off. One who settles in tight
	# without a rush meets a keeper further out than the rush left him, past
	# the crease top; and so does a set shooter at the dot line.
	for dist: float in [3.0, 6.1]:
		var rushed: float = _rush_to(dist)
		_h.settle_ready(Vector3(0.0, 0.0, GOAL_Z + dist))
		var settled: float = _ctrl.challenge_radius()
		assert_gt(settled, rushed,
				"%.1f m: a settled carrier draws more depth than one who rushed him there" % dist)
		assert_gt(settled, CreaseRules.STRAIGHT_DEPTH,
				"%.1f m: a settled carrier is challenged past the crease top" % dist)


# Rewrite with MITTS_UPDATE_SNAPSHOTS=1 (tests/snapshot.gd) and review the diff.
func test_depth_in_tight_calibration_snapshot() -> void:
	var snap := Snapshot.new("res://tests/unit/ai/snapshots/goalie_depth_in_tight.txt")
	for dist: float in [3.0, 6.1]:
		snap.record("rushed from 10 m at 7 m/s to %.1f m: radius" % dist, _rush_to(dist))
		_h.settle_ready(Vector3(0.0, 0.0, GOAL_Z + dist))
		snap.record("settled carrier at %.1f m: radius" % dist, _ctrl.challenge_radius())
	snap.verify(self)
