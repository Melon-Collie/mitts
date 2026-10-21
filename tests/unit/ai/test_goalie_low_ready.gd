extends GutTest

# ── THE LOW READY ─────────────────────────────────────────────────────────────
# A shooter in tight, inside the range where a hard release beats his drop from
# READY, gets the low ready: skates in, knees together, the paddle stood in the
# five-hole. It shrinks the five-hole to a window over the blade and buys a
# shorter drop, and pays for both with a slower push. It never changes while he
# reads a shot.

const Harness := preload("res://tests/unit/ai/real_goalie_shot_harness.gd")
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const State := GoalieStateMachine.State
const IN_TIGHT := Vector3(0.0, 0.0, GOAL_Z + 4.0)
const SLOT_FAR := Vector3(0.0, 0.0, GOAL_Z + 12.0)
# Heights a lifted shot from the slot crosses him at, just over the blade.
const FIVE_HOLE_YS: Array[float] = [0.16, 0.20, 0.24, 0.28]

var _goalie: Node = null
var _puck: Node = null
var _shooter: Skater = null
var _ctrl: GoalieController = null
var _h: RefCounted = null
var _entered: Array[int] = []


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
	_ctrl._sm.transitioned.connect(func(_p: int, n: int) -> void: _entered.append(n))


func _settle(spot: Vector3) -> void:
	_ctrl.reset_to_crease()
	_h.settle(spot, 120)


func test_the_race_is_the_release_against_the_drop() -> void:
	assert_true(GoalieBehaviorRules.release_beats_the_drop(6.0, 33.0, 0.2))
	assert_false(GoalieBehaviorRules.release_beats_the_drop(7.0, 33.0, 0.2))
	assert_true(GoalieBehaviorRules.release_beats_the_drop(7.0, 33.0, 0.2, 0.5),
			"the margin is extra range")
	assert_false(GoalieBehaviorRules.release_beats_the_drop(6.0, 33.0, 0.15),
			"a quicker drop wins from closer in")


func test_a_shooter_in_tight_gets_the_low_ready_and_one_in_the_slot_does_not() -> void:
	_settle(IN_TIGHT)
	assert_eq(_ctrl._sm.current, State.LOW_READY)
	_settle(SLOT_FAR)
	assert_eq(_ctrl._sm.current, State.READY)


func test_a_teammate_in_tight_is_no_shot() -> void:
	_ctrl.team_id = 0
	_shooter.set_team_id_resolver(func() -> int: return 0)
	_settle(IN_TIGHT)
	assert_ne(_ctrl._sm.current, State.LOW_READY)


# Read at one instant so the goalie's own depth cannot move the boundary.
func test_he_rises_only_past_the_deadband() -> void:
	_settle(IN_TIGHT)
	var g: Vector3 = (_goalie as Node3D).global_position
	var boundary: float = GameRules.DEFAULT_WRISTER_POWER_MAX_M_S * _ctrl.butterfly_drop_speed
	var inside_deadband: float = boundary + _ctrl.low_ready_exit_deadband_m * 0.5
	_puck.global_position = Vector3(g.x, 0.0, g.z + inside_deadband)
	_ctrl._sm.current = State.LOW_READY
	assert_true(_ctrl._release_beats_the_drop(), "low stays low inside the deadband")
	_ctrl._sm.current = State.READY
	assert_false(_ctrl._release_beats_the_drop(), "READY does not go low out there")


func test_the_stance_holds_under_a_shot() -> void:
	_settle(IN_TIGHT)
	_entered.clear()
	_h.fire_at(IN_TIGHT, Vector3(0.0, 0.0, GOAL_Z), ShotMechanics.ELEVATION_LOW, 30.0, 0.0)
	assert_false(State.READY in _entered, "never up into READY under the shot")
	assert_false(State.STANDING in _entered, "never up at all under the shot")


func test_the_five_hole_is_a_window_not_a_wall() -> void:
	_settle(SLOT_FAR)
	assert_eq(_ctrl._sm.current, State.READY)
	var ready_area: float = 0.0
	for y: float in FIVE_HOLE_YS:
		ready_area += _h.five_hole_width_at(y)
	_settle(IN_TIGHT)
	assert_eq(_ctrl._sm.current, State.LOW_READY)
	var low_area: float = 0.0
	for y: float in FIVE_HOLE_YS:
		low_area += _h.five_hole_width_at(y)
	assert_lt(low_area, ready_area * 0.5, "the low ready closes most of READY's five-hole")
	assert_gt(low_area, 0.0, "and leaves a window over the blade")


func test_the_drop_from_low_is_shorter_and_rides_into_the_butterfly() -> void:
	_settle(IN_TIGHT)
	var share: float = GoalieBodyConfigBuilder.low_ready_drop_share()
	assert_lt(share, 1.0)
	assert_almost_eq(_ctrl._drop_time(), _ctrl.butterfly_drop_speed * share, 1e-6)
	_ctrl._enter_butterfly()
	assert_almost_eq(_ctrl._slide.butterfly_drop_speed,
			_ctrl.butterfly_drop_speed * share, 1e-6, "the drop he started is the one he gets")
	_settle(SLOT_FAR)
	_ctrl._enter_butterfly()
	assert_almost_eq(_ctrl._slide.butterfly_drop_speed, _ctrl.butterfly_drop_speed, 1e-6)


func test_every_race_prices_the_low_push() -> void:
	_settle(IN_TIGHT)
	var share: float = _ctrl.low_ready_push_share
	assert_lt(share, 1.0)
	assert_almost_eq(_ctrl._beaten_wide_cfg.goalie_lateral_speed, _ctrl.t_push_speed * share, 1e-6)
	assert_almost_eq(_ctrl._backdoor_cfg.goalie_lateral_accel, _ctrl.lateral_accel * share, 1e-6)
	_settle(SLOT_FAR)
	assert_almost_eq(_ctrl._beaten_wide_cfg.goalie_lateral_speed, _ctrl.t_push_speed, 1e-6)
	assert_almost_eq(_ctrl._backdoor_cfg.goalie_lateral_accel, _ctrl.lateral_accel, 1e-6)


# A rigid pad rolled past its partner draws the two crossing in an X.
func test_the_knees_meet_and_never_cross() -> void:
	var builder := GoalieBodyConfigBuilder.new()
	var inputs := GoalieBodyConfigBuilder.Inputs.new()
	inputs.state = State.LOW_READY
	var c: GoalieBodyConfig = builder.build(inputs)
	var half := Vector3(GoalieAnatomy.PAD_BOX_WIDTH_M, GoalieAnatomy.PAD_BOX_HEIGHT_M,
			GoalieAnatomy.PAD_BOX_DEPTH_M) * 0.5
	for corner_z: float in [-half.z, half.z]:
		var right: Vector3 = c.right_pad_pos + Basis.from_euler(c.right_pad_rot * (PI / 180.0)) \
				* Vector3(-half.x, half.y, corner_z)
		var left: Vector3 = c.left_pad_pos + Basis.from_euler(c.left_pad_rot * (PI / 180.0)) \
				* Vector3(half.x, half.y, corner_z)
		assert_gt(right.x, -0.01, "right knee stays on its side")
		assert_lt(left.x, 0.01, "left knee stays on its side")


# The network pose rests the trunk and head from the state alone.
func test_the_resting_lookup_is_the_pose() -> void:
	var builder := GoalieBodyConfigBuilder.new()
	var inputs := GoalieBodyConfigBuilder.Inputs.new()
	inputs.state = State.LOW_READY
	var c: GoalieBodyConfig = builder.build(inputs)
	assert_eq(GoalieBodyConfigBuilder.resting_body_position_for_state(State.LOW_READY),
			Vector3(0.0, c.body_pos.y, c.body_pos.z))
	assert_eq(GoalieBodyConfigBuilder.resting_head_position_for_state(State.LOW_READY).y,
			c.head_pos.y)
	assert_true(GoalieStateMachine.is_on_his_feet(State.LOW_READY))
