extends GutTest

# A slapshot is set up, not teleported into (docs/slapshot-realism-plan.md,
# Phase 1). Pressed with the puck on the backhand, the blade carries it across
# to the strike spot at the dangle's own speed while the hips turn side-on at the
# facing rule's rate; the backswing starts once both have arrived, with the puck
# pinned where it lies. Driven through the real controller and rig.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const State = SkaterStateMachine.State
const DT: float = 1.0 / 120.0


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _skater: Skater = null
var _controller: SkaterController = null
var _input := InputState.new()


func before_each() -> void:
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	puck.global_position = Vector3(20.0, 0.0, 20.0)
	_skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(_skater)
	_skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 10.0)
	_skater.set_process(false)
	_skater.set_physics_process(false)
	var state := StubGameState.new()
	add_child_autofree(state)
	_controller = SkaterController.new()
	add_child_autofree(_controller)
	_controller.setup(_skater, puck, state)
	_controller.set_process(false)
	_controller.set_physics_process(false)
	puck.set_carrier(_skater)
	_controller.on_puck_picked_up_network()


func _tick(aim_local: Vector3, slap: bool, press: bool = false) -> void:
	_input.delta = DT
	_input.host_timestamp += DT
	_input.move_vector = Vector2.ZERO
	_input.mouse_world_pos = _skater.global_position + aim_local
	_input.mouse_world_pos.y = 0.0
	_input.slap_held = slap
	_input.slap_pressed = press
	_controller._process_input(_input, DT)
	_skater._physics_process(DT)


func _puck() -> Vector3:
	return _skater.get_carry_target_global()


func _stance_error() -> float:
	return absf(_controller._pose.facing.angle_to(_controller.slapper_stance_facing()))


# The puck on the backhand, then the press with the target straight ahead.
func _press_from_backhand() -> void:
	var backhand: float = 1.0 if _skater.is_left_handed else -1.0
	for i: int in 60:
		_tick(Vector3(backhand * 1.3, 0.0, -0.9), false)
	_tick(Vector3(0.0, 0.0, -12.0), true, true)


func test_the_press_moves_neither_the_puck_nor_the_hips_in_one_tick() -> void:
	var backhand: float = 1.0 if _skater.is_left_handed else -1.0
	for i: int in 60:
		_tick(Vector3(backhand * 1.3, 0.0, -0.9), false)
	var puck_before: Vector3 = _puck()
	var facing_before: Vector2 = _controller._pose.facing
	_tick(Vector3(0.0, 0.0, -12.0), true, true)
	assert_eq(_skater.current_shot_state, State.SLAPPER_CHARGE_WITH_PUCK)
	var step: float = Vector2(_puck().x - puck_before.x, _puck().z - puck_before.z).length()
	assert_lt(step, _controller.max_blade_speed * DT * 1.5,
			"the puck moves no faster than the blade can carry it (%.3f m)" % step)
	assert_lt(rad_to_deg(absf(facing_before.angle_to(_controller._pose.facing))), 3.0,
			"the hips start turning, they do not snap")


func test_the_blade_carries_the_puck_to_the_strike_spot_before_the_backswing() -> void:
	_press_from_backhand()
	assert_false(_controller._aiming.slapper_setup_done, "the press starts the set-up")
	var prev: Vector3 = _puck()
	var worst_step: float = 0.0
	var ticks: int = 0
	var charged_in_setup: bool = false
	while not _controller._aiming.slapper_setup_done and ticks < 240:
		_tick(Vector3(0.0, 0.0, -12.0), true)
		worst_step = maxf(worst_step, Vector2(_puck().x - prev.x, _puck().z - prev.z).length())
		prev = _puck()
		ticks += 1
		if not _controller._aiming.slapper_setup_done:
			charged_in_setup = charged_in_setup or _controller._aiming.slapper_charge_timer > 0.0
	assert_false(charged_in_setup, "no charge through the set-up")
	assert_true(_controller._aiming.slapper_setup_done, "set within two seconds (%d ticks)" % ticks)
	assert_gt(ticks, 6, "a puck on the backhand takes time to bring across")
	assert_lt(worst_step, _controller.max_blade_speed * DT * 1.5,
			"carried at the blade's speed the whole way (%.3f m/tick)" % worst_step)
	assert_lt(rad_to_deg(_stance_error()), _controller.slapper_setup_facing_tol_deg + 0.01,
			"the hips have opened side-on")
	var pinned: Vector3 = _puck()
	_tick(Vector3(0.0, 0.0, -12.0), true)
	assert_almost_eq(Vector2(_puck().x, _puck().z).distance_to(Vector2(pinned.x, pinned.z)), 0.0, 0.01,
			"the pin holds the puck where the set-up left it")
	for i: int in 30:
		_tick(Vector3(0.0, 0.0, -12.0), true)
	assert_gt(_controller._aiming.slapper_charge_timer, 0.2, "the backswing is charging")


func test_letting_go_before_the_puck_is_set_shoots_nothing() -> void:
	_press_from_backhand()
	_tick(Vector3(0.0, 0.0, -12.0), true)
	_tick(Vector3(0.0, 0.0, -12.0), false)
	assert_eq(_skater.current_shot_state, State.SKATING_WITH_PUCK, "back to carrying")
	assert_true(_controller.has_puck, "the puck never left")


func test_the_shot_line_runs_from_the_strike_spot_to_the_cursor() -> void:
	_press_from_backhand()
	var target: Vector3 = _input.mouse_world_pos
	var strike: Vector2 = _controller.slapper_strike_local()
	var spot: Vector2 = Vector2(_skater.global_position.x, _skater.global_position.z) \
			+ SlapperRules.strike_offset(_controller._sm.locked_slapper_dir, strike,
					-1.0 if _skater.is_left_handed else 1.0,
					deg_to_rad(_controller.slapper_stance_open_deg))
	assert_almost_eq(_controller._sm.locked_slapper_dir.angle_to(Vector2(target.x, target.z) - spot),
			0.0, deg_to_rad(0.5))


func test_the_one_timer_circle_is_the_strike_spot() -> void:
	_controller.on_puck_released_network()
	_tick(Vector3(0.0, 0.0, -12.0), true, true)
	assert_eq(_skater.current_shot_state, State.SLAPPER_CHARGE_WITHOUT_PUCK)
	var strike: Vector2 = _controller.slapper_strike_local()
	var expected: Vector3 = _skater.to_global(Vector3(strike.x, 0.0, strike.y))
	var zone: Vector3 = _skater.get_slapper_zone_global_position()
	assert_almost_eq(Vector2(zone.x, zone.z).distance_to(Vector2(expected.x, expected.z)), 0.0, 0.001)


func test_the_bots_default_body_strikes_where_the_default_skater_does() -> void:
	var strike: Vector2 = _controller.slapper_strike_local()
	var side: float = -1.0 if _skater.is_left_handed else 1.0
	var caps_default: Vector2 = AISkaterCaps.new().slapper_strike_local
	assert_almost_eq(Vector2(strike.x * side, strike.y).distance_to(caps_default), 0.0, 0.02,
			"AISkaterCaps' default is the default build's spot (%s)" % Vector2(strike.x * side, strike.y))
	assert_almost_eq(AISkaterCaps.new().slapper_stance_open_rad,
			deg_to_rad(_controller.slapper_stance_open_deg), 0.0001)
