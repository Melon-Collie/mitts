extends GutTest

# The rocked hit, through the real controller: a full check (stagger_ref_impulse
# and up) jars his stick off the ice and takes his stance and commit until the
# stagger timer comes back down to the full stagger, and a cross-check never
# puts him there (BodyCheckRules' rocked band).

const DT: float = 1.0 / 120.0


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


# A full check short of the knockdown line.
func _rocks_him_on_his_feet() -> float:
	return 0.5 * (_controller.stagger_ref_impulse + _controller.knockdown_impulse)


func _tick(input: InputState) -> void:
	input.delta = DT
	_controller._process_input(input, DT)


func _loaded() -> InputState:
	var input := InputState.new()
	input.stance_held = true
	return input


func _committed() -> InputState:
	var input := InputState.new()
	input.hit_held = true
	return input


func test_a_full_check_jars_his_stick_off_the_ice() -> void:
	_controller._on_body_check_received(Vector3(_controller.stagger_ref_impulse + 0.1, 0.0, 0.0))
	_tick(InputState.new())
	assert_true(_skater.stick_jarred)
	assert_true(_skater.is_forced_lift_active(), "every forced-lift gate closes: pickup, deflect, lift, tie")
	assert_true(_skater.blade_up)


func test_rocked_he_can_neither_load_nor_commit() -> void:
	_controller._on_body_check_received(Vector3(_controller.stagger_ref_impulse + 0.1, 0.0, 0.0))
	_tick(_loaded())
	assert_false(_controller.stance_active)
	_tick(_committed())
	assert_false(_controller.hit_active)
	assert_false(_skater.hit_committed, "the resolver sees no commit and no brace")


func test_he_gets_his_stick_and_his_legs_back_at_the_full_stagger() -> void:
	_controller._on_body_check_received(Vector3(_rocks_him_on_his_feet(), 0.0, 0.0))
	while _controller.stagger_timer > _controller.stagger_max_seconds:
		_tick(InputState.new())
	_tick(_loaded())
	assert_false(_skater.stick_jarred)
	assert_true(_controller.stance_active, "staggered, not rocked: the stance is his again")
	assert_gt(_controller.stagger_timer, 0.0, "the stagger's tail still runs")


func test_a_knockdown_leaves_his_stick_to_the_fall() -> void:
	_controller._on_body_check_received(Vector3(_controller.knockdown_impulse + 0.2, 0.0, 0.0))
	_tick(InputState.new())
	assert_true(_skater.is_knocked_down)
	assert_false(_skater.stick_jarred, "down, not rocked")


func test_a_hit_short_of_a_full_check_never_rocks() -> void:
	_controller._on_body_check_received(Vector3(_controller.stagger_ref_impulse - 0.05, 0.0, 0.0))
	_tick(_loaded())
	assert_false(_skater.stick_jarred)
	assert_true(_controller.stance_active)


func test_a_cross_check_never_rocks() -> void:
	var dv: float = _controller.take_cross_check(3.0, 100.0, Vector2(1.0, 0.0))
	assert_gt(dv, _controller.stagger_ref_impulse, "a shove past a full check's strength")
	assert_lte(_controller.stagger_timer, _controller.stagger_max_seconds)
	_tick(InputState.new())
	assert_false(_skater.stick_jarred)


func test_a_cross_check_on_a_rocked_man_leaves_his_window_alone() -> void:
	_controller._on_body_check_received(Vector3(_rocks_him_on_his_feet(), 0.0, 0.0))
	var rocked: float = _controller.stagger_timer
	assert_gt(rocked, _controller.stagger_max_seconds)
	_controller.take_cross_check(3.0, 100.0, Vector2(1.0, 0.0))
	assert_almost_eq(_controller.stagger_timer, rocked, 1e-6)


# BodyCheckRules.Config's defaults are read where no controller is at hand (the
# bots' commit bar, the domain tests), so they are the controller's own values.
func test_the_rules_defaults_are_the_controllers_tuning() -> void:
	var live: BodyCheckRules.Config = _controller.get_body_check_config()
	var defaults := BodyCheckRules.Config.new()
	for field: String in ["min_impulse", "ref_impulse", "max_stagger_seconds",
			"max_thrust_penalty", "max_grip_penalty", "rocked_ref_impulse",
			"rocked_min_seconds", "rocked_max_seconds", "rocked_grip_penalty",
			"knockdown_impulse", "knockdown_ref_impulse", "min_knockdown_seconds",
			"max_knockdown_seconds"]:
		assert_eq(live.get(field), defaults.get(field), field)
