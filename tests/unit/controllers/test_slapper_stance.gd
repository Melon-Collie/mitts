extends GutTest

# A slapshot is set up, not teleported into (docs/slapshot-realism-plan.md,
# Phase 1). Pressed with the puck on the backhand, the blade carries it across
# to the strike spot at the dangle's own speed while the hips turn side-on at the
# facing rule's rate; the backswing starts once both have arrived, with the puck
# pinned where it lies. Driven through the real controller and rig.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const State = SkaterStateMachine.State
const DT: float = 1.0 / 120.0  # a fixed step: the script below is timed in it


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
	var pinned: Vector3 = _skater.to_local(_puck())
	_tick(Vector3(0.0, 0.0, -12.0), true)
	var held: Vector3 = _skater.to_local(_puck())
	assert_almost_eq(Vector2(held.x, held.z).distance_to(Vector2(pinned.x, pinned.z)), 0.0, 0.001,
			"the pin holds the puck where the set-up left it, in the hips' frame")
	for i: int in 30:
		_tick(Vector3(0.0, 0.0, -12.0), true)
	assert_gt(_controller._aiming.slapper_charge_timer, 0.2, "the backswing is charging")


# The aim arrow comes up once the shot is set, from where the puck was pinned:
# drawn through the set-up it swung round with the hips and the puck.
func test_the_aim_arrow_waits_for_the_puck_to_be_set() -> void:
	_controller.show_one_timer_indicator = true
	_press_from_backhand()
	var hud: SkaterHUDCoordinator = _skater._hud
	var shown_early: bool = false
	var ticks: int = 0
	while not _controller._aiming.slapper_setup_done and ticks < 240:
		shown_early = shown_early or hud.slapper_arrow_visible()
		_tick(Vector3(0.0, 0.0, -12.0), true)
		ticks += 1
	assert_false(shown_early, "no arrow while the puck is carried to the strike spot")
	_tick(Vector3(0.0, 0.0, -12.0), true)
	assert_true(hud.slapper_arrow_visible(), "the arrow is up once the puck is set")
	var pin: Vector2 = _skater.slapshot_pin_local()
	assert_almost_eq(Vector2(hud._slapper_offset_local.x, hud._slapper_offset_local.z), pin,
			Vector2.ONE * 0.0001, "drawn from where the puck lies")


# Without the puck, the arrow comes up once the hips have pivoted into the
# stance.
func test_the_one_timer_arrow_waits_for_the_stance() -> void:
	_controller.show_one_timer_indicator = true
	_controller.on_puck_released_network()
	for i: int in 30:
		_tick(Vector3(-6.0, 0.0, 6.0), false)
	_tick(Vector3(0.0, 0.0, -12.0), true, true)
	var hud: SkaterHUDCoordinator = _skater._hud
	assert_false(hud.slapper_arrow_visible(), "no arrow on the press")
	var ticks: int = 0
	while _stance_error() > deg_to_rad(_controller.slapper_setup_facing_tol_deg) and ticks < 120:
		assert_false(hud.slapper_arrow_visible(), "no arrow while the hips pivot")
		_tick(Vector3(0.0, 0.0, -12.0), true)
		ticks += 1
	assert_gt(ticks, 3, "the hips had a turn to make")
	_tick(Vector3(0.0, 0.0, -12.0), true)
	assert_true(hud.slapper_arrow_visible(), "the arrow is up once the stance is set")


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


func test_the_bots_default_slapshot_is_the_default_skaters() -> void:
	var strike: Vector2 = _controller.slapper_strike_local()
	var side: float = -1.0 if _skater.is_left_handed else 1.0
	var caps_default: Vector2 = AISkaterCaps.new().slapper_strike_local
	assert_almost_eq(Vector2(strike.x * side, strike.y).distance_to(caps_default), 0.0, 0.02,
			"AISkaterCaps' default is the default build's spot (%s)" % Vector2(strike.x * side, strike.y))
	var caps := AISkaterCaps.new()
	assert_almost_eq(caps.slapper_stance_open_rad,
			deg_to_rad(_controller.slapper_stance_open_deg), 0.0001)
	assert_almost_eq(caps.slapper_stance_turn_rad_s,
			deg_to_rad(_controller.slapper_stance_turn_deg_s), 0.0001)
	assert_almost_eq(caps.slapper_power_min, _controller.min_slapper_power, 0.0001)
	assert_almost_eq(caps.slapper_power_max, _controller.max_slapper_power, 0.0001)
	assert_almost_eq(caps.slapper_max_charge_s, _controller.max_slapper_charge_time, 0.0001)
	assert_almost_eq(caps.one_timer_min_windup_s, _controller.one_timer_min_windup_time, 0.0001)
	assert_almost_eq(caps.one_timer_feed_grip, _controller.one_timer_feed_grip, 0.0001)


# The stick turns as one piece through the swing (Skater._swing_rigid): from the
# backswing through the release to the end of the finish, neither the blade nor
# the shaft rolls about the shaft line, frame to frame, in the shoulders' frame
# the arms swing it in, by more than a sliver of a downswing that sweeps the
# shaft 15–20° a frame. Solved fresh from the shaft's bearing, the blade spun
# ~20° a frame through the downswing.
func test_the_stick_does_not_roll_through_the_swing() -> void:
	var aim := Vector3(0.0, 0.0, -12.0)
	for i: int in 60:
		_frame(Vector3(0.4, 0.0, -2.0), false)
	_frame(aim, true, true)
	while not _controller._aiming.slapper_setup_done:
		_frame(aim, true)
	var prev_blade: Basis = _in_shoulders(_skater._blade_mesh_instance.global_transform.basis)
	var prev_shaft: Basis = _in_shoulders(_skater.stick_mesh.global_transform.basis)
	var worst_blade: float = 0.0
	var worst_shaft: float = 0.0
	var t: int = 0
	while t < 100 or not (_skater.current_shot_state == State.SKATING_WITH_PUCK
			or _skater.current_shot_state == State.SKATING_WITHOUT_PUCK):
		_frame(aim, t < 100)
		var blade: Basis = _in_shoulders(_skater._blade_mesh_instance.global_transform.basis)
		var shaft: Basis = _in_shoulders(_skater.stick_mesh.global_transform.basis)
		worst_blade = maxf(worst_blade, _roll_deg(prev_blade, blade, -shaft.z))
		worst_shaft = maxf(worst_shaft, _roll_deg(prev_shaft, shaft, -shaft.z))
		prev_blade = blade
		prev_shaft = shaft
		t += 1
	assert_gt(t, 160, "measured through the release and the whole finish (%d frames)" % t)
	assert_lt(worst_blade, 3.0, "the blade turns with the shaft (worst %.1f° a frame)" % worst_blade)
	assert_lt(worst_shaft, 3.0, "the shaft does not spin (worst %.1f° a frame)" % worst_shaft)


func _frame(aim_local: Vector3, slap: bool, press: bool = false) -> void:
	_tick(aim_local, slap, press)
	_skater._process(DT)


func _in_shoulders(b: Basis) -> Basis:
	return (_skater.upper_body.global_transform.basis.orthonormalized().inverse()
			* b.orthonormalized()).orthonormalized()


# The part of the turn from `a` to `b` that is a roll about `axis`: what is left
# once the axis's own swing (the shortest arc) is taken out.
func _roll_deg(a: Basis, b: Basis, axis: Vector3) -> float:
	var turn: Quaternion = (b * a.inverse()).get_rotation_quaternion()
	var axis_before: Vector3 = (turn.inverse() * axis).normalized()
	var roll: float = rad_to_deg((turn * Quaternion(axis_before, axis.normalized()).inverse()).get_angle())
	return 360.0 - roll if roll > 180.0 else roll
