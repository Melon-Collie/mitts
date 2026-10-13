extends GutTest

# ── HE GETS UP OFF A REBOUND NOBODY CAN REACH ────────────────────────────────
# `_recovery_loses_the_crossing_race` holds the butterfly while the threat's
# lateral travel through the rise would beat his standing reach. With no carrier
# it reads the loose puck, and a rebound steered to the corner keeps its pace to
# the boards — the ice takes ~0.5 m/s² off it — so it held him down 3.7-5 s with
# nobody near the puck. A loose puck is a threat only once a stick reaches it:
# one no opponent can reach before he is back up loses him nothing.

const Harness := preload("res://tests/unit/ai/real_goalie_shot_harness.gd")
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const DT: float = 1.0 / 120.0
const DECEL: float = GameRules.PUCK_ICE_DECEL_M_S2
const SLOT := Vector3(0.0, 0.0, GOAL_Z + 8.0)
const TIGHT := Vector3(0.0, 0.0, GOAL_Z + 3.5)

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
	for n: Node in [_goalie, _puck, _shooter, _ctrl]:
		add_child_autofree(n)
	_h = Harness.new()
	_h.setup(_goalie, _puck, _ctrl, _shooter)


# Down off a save against a shooter at `shooter_pos`, the rebound leaves his pads
# at `reb_vel` and slides on the ice. Seconds until he starts to rise, -1 if he
# is still down after 3 s.
func _seconds_down(shooter_pos: Vector3, reb_vel: Vector3) -> float:
	_ctrl.reset_to_crease()
	_h.settle(shooter_pos, 240)
	_shooter.current_shot_state = SkaterStateMachine.State.FOLLOW_THROUGH
	_puck.clear_carrier()
	_ctrl._enter_butterfly()
	var pos: Vector3 = _goalie.global_position + Vector3(0.0, 0.0, 0.5)
	pos.y = _puck.ice_height
	_puck.global_position = pos
	_puck.linear_velocity = reb_vel
	_puck.puck_touched_goalie.emit(_goalie)
	var vel: Vector3 = reb_vel
	for i: int in 360:
		vel = vel.normalized() * maxf(vel.length() - DECEL * DT, 0.0)
		pos += vel * DT
		_puck.global_position = pos
		_puck.linear_velocity = vel
		_ctrl._physics_process(DT)
		if _ctrl._sm.current == GoalieController.State.RECOVERING:
			return i * DT
	return -1.0


func test_a_rebound_to_the_corner_with_nobody_on_it_lets_him_up() -> void:
	for reb: Vector3 in [Vector3(6.0, 0.0, 1.0), Vector3(3.0, 0.0, 0.5), Vector3(3.0, 0.0, 3.0)]:
		var t: float = _seconds_down(SLOT, reb)
		assert_gte(t, 0.0, "%s: he got up" % reb)
		assert_lt(t, _ctrl.butterfly_min_hold_time + 0.05,
				"%s: at the end of the butterfly's own hold, not when it reaches the boards" % reb)


func test_a_rebound_a_stick_can_reach_still_holds_him() -> void:
	var t: float = _seconds_down(TIGHT, Vector3(6.0, 0.0, 1.0))
	assert_gt(t, _ctrl.butterfly_min_hold_time + 0.1,
			"a shooter 3 m off it can play it before he is up")


func test_a_carrier_crossing_in_front_still_holds_him() -> void:
	_ctrl.reset_to_crease()
	_h.settle(TIGHT, 240)
	_shooter.velocity = Vector3(4.0, 0.0, 0.0)
	assert_true(_ctrl._recovery_loses_the_crossing_race(),
			"the walkaround is the race this clause exists for")
