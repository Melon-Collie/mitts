extends GutTest

# ── THE HALF-BUTTERFLY ───────────────────────────────────────────────────────
# A converged low read wide of one standing pad, but inside a flat pad's reach,
# is answered by that pad alone; the other leg stays loaded on its skate. The
# loaded leg is the payoff: a push without the coil, shuffle pace while down, and
# half the rise.
#
# ── WHAT IT MEASURED (2026-09) ───────────────────────────────────────────────
# 28 m/s flat and low shots at six aims just outside the pads, from 9 m and 12 m
# centre and 11 m at 2.5 m wide; cold release, telegraphed wind-up, and a wind-up
# declared at the opposite side (late swing). 108 shots each way.
#
#                     goals   half-butterflies   mean time back on his feet
#   always full        4           0                  0.49 s
#   half-butterfly     4          42                  0.42 s
#
# Only flat shots go half: a low-loft shot passes above a flat pad's 0.28 m, so
# it still gets the full butterfly. From 9 m a wind-up read has not converged by
# the drop, so telegraphed and late-swing shots there get the full butterfly
# too; the late swing reads exactly as the telegraphed shot at every spot.

const Harness := preload("res://tests/unit/ai/real_goalie_shot_harness.gd")
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const DT: float = 1.0 / 120.0
const SPEED: float = 28.0
const State := GoalieStateMachine.State
const WIDE_AIM: float = 0.6
const SPOT_12 := Vector3(0.0, 0.0, GOAL_Z + 12.0)

var _goalie: Node = null
var _puck: Node = null
var _shooter: Skater = null
var _other: Skater = null
var _ctrl: GoalieController = null
var _h: RefCounted = null
var _entered: Array[int] = []


func before_each() -> void:
	_goalie = load("res://Scenes/Goalie.tscn").instantiate()
	_puck = load("res://Scenes/Puck.tscn").instantiate()
	var skater_scene: PackedScene = load("res://Scenes/Skater.tscn")
	_shooter = skater_scene.instantiate() as Skater
	_other = skater_scene.instantiate() as Skater
	_ctrl = GoalieController.new()
	add_child_autofree(_goalie)
	add_child_autofree(_puck)
	add_child_autofree(_shooter)
	add_child_autofree(_other)
	add_child_autofree(_ctrl)
	_other.set_physics_process(false)
	_other.set_process(false)
	_h = Harness.new()
	_h.setup(_goalie, _puck, _ctrl, _shooter)
	_ctrl._sm.transitioned.connect(func(_p: int, n: int) -> void: _entered.append(n))


func _went_half() -> bool:
	return State.HALF_BUTTERFLY_LEFT in _entered or State.HALF_BUTTERFLY_RIGHT in _entered


func _cold(spot: Vector3, aim_x: float, loft: int = ShotMechanics.ELEVATION_FLAT) -> int:
	_h.settle_ready(spot)
	_entered.clear()
	return _h.fire_release_at(spot, Vector3(aim_x, 0.0, GOAL_Z), loft, SPEED, 0.0)


func test_a_converged_flat_shot_wide_of_a_pad_is_played_with_that_pad() -> void:
	for aim_x: float in [-WIDE_AIM, WIDE_AIM]:
		assert_eq(_cold(SPOT_12, aim_x), Harness.SAVE)
		assert_true(_went_half(), "aim %.2f: one pad down" % aim_x)
		# The -Z goalie is turned PI: world +x is his local left.
		var down: int = State.HALF_BUTTERFLY_LEFT if aim_x > 0.0 else State.HALF_BUTTERFLY_RIGHT
		assert_true(down in _entered, "the pad on the shot's side")


func test_the_five_hole_the_pad_face_and_a_rising_shot_are_not_half_saves() -> void:
	_cold(SPOT_12, 0.0)
	assert_false(_went_half(), "five-hole: both pads")
	_cold(SPOT_12, 0.25)
	assert_false(_went_half(), "on the pad face: he stays up")
	_cold(SPOT_12, WIDE_AIM, ShotMechanics.ELEVATION_LOW)
	assert_false(_went_half(), "above a flat pad: the full butterfly")


func test_a_late_swing_is_a_full_butterfly() -> void:
	var spot := Vector3(0.0, 0.0, GOAL_Z + 9.0)
	_h.settle_ready(spot)
	_h.hold_windup_at(spot, Vector3(-WIDE_AIM, 0.0, GOAL_Z), ShotMechanics.ELEVATION_FLAT,
			SPEED, 60)
	_entered.clear()
	_h.fire_release_at(spot, Vector3(WIDE_AIM, 0.0, GOAL_Z), ShotMechanics.ELEVATION_FLAT,
			SPEED, 0.0)
	assert_false(_went_half(), "a stale read hedges with both pads")


func test_a_man_on_the_far_side_keeps_both_pads_down() -> void:
	_ctrl.set_skater_getter(func() -> Array: return [_shooter, _other])
	# Shot to world +x; the up leg would be on world -x.
	_other.global_position = Vector3(-3.0, 0.0, GOAL_Z + 3.0)
	_cold(SPOT_12, WIDE_AIM)
	assert_false(_went_half(), "a live rebound on the up-leg side needs both pads")
	_other.global_position = Vector3(3.0, 0.0, GOAL_Z + 3.0)
	_cold(SPOT_12, WIDE_AIM)
	assert_true(_went_half(), "the same man on the down-pad side does not")


func test_the_loaded_leg_rises_in_half_the_time() -> void:
	_cold(SPOT_12, WIDE_AIM)
	assert_true(_ctrl._sm.is_half_butterfly())
	var t: float = 0.0
	while not _ctrl._sm.is_upright() and t < 2.0:
		_puck.global_position = Vector3(8.0, 0.0, GOAL_Z + 20.0)
		_puck.linear_velocity = Vector3.ZERO
		_ctrl._physics_process(DT)
		t += DT
	assert_almost_eq(_ctrl._recovery_needed,
			_ctrl.recovery_duration * GoalieController.HALF_BUTTERFLY_RISE_SHARE, 0.001)


func test_a_slide_from_the_half_pushes_without_the_coil() -> void:
	_cold(SPOT_12, WIDE_AIM)
	assert_true(_ctrl._sm.is_half_butterfly())
	_entered.clear()
	_ctrl._commit_slide_to(-0.15 if _ctrl._current_x > 0.0 else 0.15)
	assert_eq(_ctrl._sm.current, State.SLIDING, "straight into the push")
	assert_false(State.COILING in _entered)
	assert_gt(absf(_ctrl._slide.velocity_x), 0.0)


# The half-butterfly must not open anything the full butterfly closed.
func test_it_concedes_nothing_the_full_butterfly_stopped() -> void:
	var goals := {false: 0, true: 0}
	for flag: bool in [false, true]:
		_ctrl.half_butterfly_saves = flag
		for spot: Vector3 in [Vector3(0.0, 0.0, GOAL_Z + 9.0), SPOT_12,
				Vector3(2.5, 0.0, GOAL_Z + 11.0)]:
			for aim_x: float in [-0.75, -0.6, -0.45, 0.45, 0.6, 0.75]:
				for loft: int in [ShotMechanics.ELEVATION_FLAT, ShotMechanics.ELEVATION_LOW]:
					if _cold(spot, aim_x, loft) == Harness.GOAL:
						goals[flag] += 1
	gut.p("goals: full %d, half %d" % [goals[false], goals[true]])
	assert_lte(goals[true], goals[false])


func test_the_wire_reads_the_half_as_down() -> void:
	var s := GoalieNetworkState.new()
	for st: int in [State.HALF_BUTTERFLY_LEFT, State.HALF_BUTTERFLY_RIGHT]:
		s.state_enum = st
		assert_true(s.is_down())
		var body_y: float = GoalieBodyConfigBuilder.resting_body_position_for_state(st).y
		assert_lt(body_y, GoalieBodyConfigBuilder.resting_body_position_for_state(State.READY).y)
		assert_gt(body_y, GoalieBodyConfigBuilder.resting_body_position_for_state(State.BUTTERFLY).y)
