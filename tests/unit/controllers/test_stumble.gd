extends GutTest

# The stumble, through the real controller: a hit past his balance and short of
# flat takes him down onto a knee on the knockdown's rail and has him up in well
# under a second, where one past the flat line still lays him out
# (BodyCheckRules.flat_overshoot, docs/hit-outcomes-plan.md Phase 6).

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _skater: Skater = null
var _controller: SkaterController = null


func before_each() -> void:
	var puck: Puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	add_child_autofree(puck)
	puck.global_position = Vector3(20.0, 0.0, 20.0)
	_skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(_skater)
	_skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	_skater.set_process(false)
	_skater.set_physics_process(false)
	var state := StubGameState.new()
	add_child_autofree(state)
	_controller = SkaterController.new()
	add_child_autofree(_controller)
	_controller.setup(_skater, puck, state)
	_controller.set_process(false)
	_controller.set_physics_process(false)


# What an upright man rides across his blades (he faces +z, so +x is his side).
func _side_budget() -> float:
	return BodyBalanceRules.budget(Vector2(1.0, 0.0), Vector2(0.0, 1.0),
			BodyBalanceRules.Posture.UPRIGHT, 1.0, _controller.get_balance_config())


# A shove across his blades `overshoot` times that.
func _shove(overshoot: float) -> void:
	_controller._on_body_check_received(Vector3(overshoot * _side_budget(), 0.0, 0.0))


func _tick(n: int = 1) -> void:
	for _i: int in n:
		var input := InputState.new()
		input.delta = DT
		_controller._process_input(input, DT)


func _flat_line() -> float:
	return _controller.get_body_check_config().flat_overshoot


func test_just_past_his_balance_he_stumbles() -> void:
	_shove(1.05)
	_tick()
	assert_true(_skater.is_knocked_down, "down: no stride, no stick")
	assert_true(_skater.is_stumbling)
	assert_between(_controller.knockdown_timer, _controller.stumble_min_seconds - DT - 1e-4,
			_controller.stumble_max_seconds)
	assert_false(_skater.stick_jarred, "down, not rocked")


func test_a_stumbling_man_never_lies_down() -> void:
	_shove(0.5 * (1.0 + _flat_line()))
	var ticks: int = ceili(_controller.stumble_max_seconds / DT) + 2
	for _i: int in ticks:
		_tick()
		assert_eq(_controller.knockdown_fall_tilt(), 0.0)
	assert_false(_skater.is_knocked_down, "up within the longest stumble")
	assert_false(_skater.is_stumbling)


func test_he_is_down_on_the_knee_then_up_off_it() -> void:
	_shove(0.5 * (1.0 + _flat_line()))
	_tick(ceili(KnockdownFallRules.STUMBLE_ENTRY_S / DT) + 1)
	assert_almost_eq(_controller.knockdown_pose_weight(), 1.0, 1e-3, "on the knee")
	assert_almost_eq(KnockdownFallRules.step_share(_controller.knockdown_getup_left()), 1.0, 1e-5)
	var prev: float = 1.0
	while _skater.is_knocked_down:
		_tick()
		var w: float = _controller.knockdown_pose_weight()
		assert_lte(w, prev + 1e-6, "once down he only comes up")
		prev = w
	assert_almost_eq(prev, 0.0, 0.05)


func test_up_off_the_knee_he_finds_his_legs() -> void:
	_shove(1.05)
	while _controller.knockdown_timer > 0.0:
		_tick()
	assert_almost_eq(_controller.stagger_timer, _controller.knockdown_getup_stagger_seconds, DT + 1e-4)
	assert_false(BodyCheckRules.is_rocked(_controller.stagger_timer,
			_controller.get_body_check_config()))


func test_past_the_flat_line_he_is_laid_out() -> void:
	_shove(_flat_line() + 0.1)
	_tick()
	assert_true(_skater.is_knocked_down)
	assert_false(_skater.is_stumbling)
	assert_gt(_controller.knockdown_timer, _controller.stumble_max_seconds)
	_tick(40)
	assert_gt(_controller.knockdown_fall_tilt(), 0.5, "going over")


func test_a_stumbling_man_hit_flat_is_floored_from_the_knee() -> void:
	_shove(1.05)
	_tick(10)
	assert_true(_skater.is_stumbling)
	_shove(_flat_line() + 0.3)
	_tick()
	assert_false(_skater.is_stumbling)
	assert_almost_eq(_controller.knockdown_elapsed(), DT, 1e-4, "the fall starts on its own clock")


func test_a_man_lying_flat_is_not_stood_up_onto_a_knee() -> void:
	_shove(_flat_line() + 0.3)
	_tick(10)
	var left: float = _controller.knockdown_timer
	_shove(1.05)
	_tick()
	assert_false(_skater.is_stumbling)
	assert_almost_eq(_controller.knockdown_timer, left - DT, 1e-4)


func test_the_longest_stumble_is_shorter_than_the_quickest_knockdown() -> void:
	var quickest: float = KnockdownFallRules.first_impact_time(100.0, _controller._fall_config()) \
			+ _controller.knockdown_lie_min_seconds + _controller.knockdown_getup_seconds
	assert_lt(_controller.stumble_max_seconds, quickest)


# BodyCheckRules.Config's defaults are read where no controller is at hand.
func test_the_rules_defaults_are_the_controllers_tuning() -> void:
	var live: BodyCheckRules.Config = _controller.get_body_check_config()
	var defaults := BodyCheckRules.Config.new()
	for field: String in ["flat_overshoot", "stumble_min_seconds", "stumble_max_seconds"]:
		assert_eq(live.get(field), defaults.get(field), field)
	var fall: KnockdownFallRules.Config = _controller._fall_config()
	var fall_defaults := KnockdownFallRules.Config.new()
	for field: String in ["restitution", "pivot_height"]:
		assert_almost_eq(fall.get(field) as float, fall_defaults.get(field) as float, 1e-6, field)
