extends GutTest

# The rocked hit, through the real controller: a full check (stagger_ref_impulse
# and up) jars his stick off the ice and takes his stance and commit until the
# stagger timer comes back down to the full stagger (BodyCheckRules' rocked
# band).

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


# A full check square from the front (he faces +z), which he rides on his feet.
func _rocks_him_on_his_feet() -> Vector3:
	return Vector3(0.0, 0.0, -0.5 * (_controller.stagger_ref_impulse + _controller.rocked_ref_impulse))


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
	_controller._on_body_check_received(_rocks_him_on_his_feet())
	while _controller.stagger_timer > _controller.stagger_max_seconds:
		_tick(InputState.new())
	_tick(_loaded())
	assert_false(_skater.stick_jarred)
	assert_true(_controller.stance_active, "staggered, not rocked: the stance is his again")
	assert_gt(_controller.stagger_timer, 0.0, "the stagger's tail still runs")


func test_a_knockdown_leaves_his_stick_to_the_fall() -> void:
	_controller._on_body_check_received(Vector3(3.0, 0.0, 0.0))
	_tick(InputState.new())
	assert_true(_skater.is_knocked_down)
	assert_false(_skater.stick_jarred, "down, not rocked")


func test_a_hit_short_of_a_full_check_never_rocks() -> void:
	_controller._on_body_check_received(Vector3(_controller.stagger_ref_impulse - 0.05, 0.0, 0.0))
	_tick(_loaded())
	assert_false(_skater.stick_jarred)
	assert_true(_controller.stance_active)


# BodyCheckRules.Config's defaults are read where no controller is at hand (the
# bots' commit bar, the domain tests), so they are the controller's own values.
func test_the_rules_defaults_are_the_controllers_tuning() -> void:
	var live: BodyCheckRules.Config = _controller.get_body_check_config()
	var defaults := BodyCheckRules.Config.new()
	for field: String in ["min_impulse", "ref_impulse", "max_stagger_seconds",
			"max_thrust_penalty", "max_grip_penalty", "rocked_ref_impulse",
			"rocked_min_seconds", "rocked_max_seconds", "rocked_grip_penalty",
			"knockdown_ref_overshoot", "min_lie_seconds", "max_lie_seconds"]:
		assert_eq(live.get(field), defaults.get(field), field)
	var balance: BodyBalanceRules.Config = _controller.get_balance_config()
	var balance_defaults := BodyBalanceRules.Config.new()
	for field: String in ["balance_ref_dv", "along_share", "sight_behind", "vulnerable_mult",
			"stance_base_ratio"]:
		assert_almost_eq(balance.get(field) as float, balance_defaults.get(field) as float, 1e-6, field)


func test_square_on_he_rides_what_floors_him_from_the_side() -> void:
	_controller._on_body_check_received(Vector3(0.0, 0.0, -3.0))
	assert_eq(_controller.knockdown_timer, 0.0, "square from the front: rocked, on his feet")
	assert_true(BodyCheckRules.is_rocked(_controller.stagger_timer, _controller.get_body_check_config()))
	before_each()
	_controller._on_body_check_received(Vector3(3.0, 0.0, 0.0))
	assert_gt(_controller.knockdown_timer, 0.0, "across his blades: down")


func test_in_the_stance_he_rides_the_side_hit() -> void:
	var input := InputState.new()
	input.stance_held = true
	_tick(input)
	assert_true(_controller.stance_active)
	_controller._on_body_check_received(Vector3(3.0, 0.0, 0.0))
	assert_eq(_controller.knockdown_timer, 0.0)


# Committed without the puck, he leans into the hit he lands: a full-speed check
# on a stationary equal man (3.25 m/s back the way he faces) staggers him.
func test_a_checker_rides_his_own_full_speed_check() -> void:
	_tick(_committed())
	assert_true(_skater.delivers_checks())
	_controller._on_body_check_received(Vector3(0.0, 0.0, -3.25))
	assert_false(BodyCheckRules.is_rocked(_controller.stagger_timer,
			_controller.get_body_check_config()))
	assert_gt(_controller.stagger_timer, 0.0, "slowed and staggered")


func test_uncommitted_the_same_hit_rocks_him() -> void:
	_controller._on_body_check_received(Vector3(0.0, 0.0, -3.25))
	assert_true(BodyCheckRules.is_rocked(_controller.stagger_timer,
			_controller.get_body_check_config()))


# He is on the ice before the get-up starts: the window is the fall, a lie and
# the get-up, however softly he goes down.
func test_the_get_up_waits_for_the_ice() -> void:
	for dv: float in [1.93, 3.0, 6.0]:
		before_each()
		_controller._on_body_check_received(Vector3(dv, 0.0, 0.0))
		var landing: float = KnockdownFallRules.first_impact_time(dv, _controller._fall_config())
		assert_gte(_controller.knockdown_timer - _controller.knockdown_getup_seconds,
				landing + _controller.knockdown_lie_min_seconds - 1e-4, "shoved at %.2f m/s" % dv)


func test_the_longest_knockdown_fits_the_wire() -> void:
	var longest: float = KnockdownFallRules.first_impact_time(0.0, _controller._fall_config()) \
			+ _controller.knockdown_lie_max_seconds + _controller.knockdown_getup_seconds
	assert_lt(longest, 2.55, "knockdown_timer travels as a u8 at 0.01 s (WorldStateCodec)")
