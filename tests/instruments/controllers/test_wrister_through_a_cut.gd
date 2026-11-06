extends GutTest

# Instrument: a full-speed flick wrister taken while skating, with the skate
# keys changing direction during the wind-up. Prints each factor of the release.

const DT: float = 1.0 / 90.0


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _skater: Skater = null
var _controller: SkaterController = null
var _input := InputState.new()
var _released: Array[Vector3] = []
var _vel_at_release := Vector3.ZERO


func before_each() -> void:
	var puck: Puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	add_child_autofree(puck)
	puck.global_position = Vector3(20.0, 0.0, 20.0)
	_skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
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
	_controller.puck_release_requested.connect(_on_release)
	_input = InputState.new()
	_input.host_timestamp = 10.0
	_released.clear()
	_controller.on_puck_picked_up_network(0)


func _on_release(direction: Vector3, power: float, _is_slapper: bool) -> void:
	_released.append(direction * power)
	_vel_at_release = _skater.velocity


func _tick(move: Vector2, cursor_rel: Vector3, screen_step: float) -> void:
	_input.delta = DT
	_input.host_timestamp += DT
	_input.move_vector = move
	_input.mouse_world_pos = _skater.global_position + cursor_rel
	_input.mouse_screen_pos += Vector2(screen_step, 0.0)
	_controller._process_input(_input, DT)
	_skater._physics_process(DT)
	_input.shoot_pressed = false


func _bearing_deg(v: Vector3) -> float:
	var l: Vector3 = _skater.global_transform.basis.inverse() * v
	return rad_to_deg(atan2(-l.x, -l.z))


# Skates `move_in` for a second and a half, presses the wrister, holds it
# `hold_ticks` with the keys on `move_aim`, flicks hard for the last few ticks.
func _run(label: String, move_in: Vector2, move_aim: Vector2, cursor_rel: Vector3,
		stance: bool, hold_ticks: int) -> void:
	_input.stance_held = stance
	for i: int in 135:
		_tick(move_in, cursor_rel, 0.0)
	var v0 := _skater.velocity
	var face0 := _skater.global_transform.basis.z * -1.0
	_input.shoot_pressed = true
	_input.shoot_held = true
	for i: int in hold_ticks:
		var step: float = 80.0 if i >= hold_ticks - 6 else 0.0
		_tick(move_aim, cursor_rel, step)
	var pin: Vector3 = _controller._aiming.wrister_origin_world - _controller._aiming.wrister_origin_skater_pos
	var aim: Vector3 = _controller._wrister_aim_dir(_input)
	_controller._solve_wrister_load(_input)
	var ld := _controller.wrister_load
	var t: float = ShotMechanics.wrister_power_t(_controller._wrister_sweep_speed(_input),
			_controller._wrister_config())
	var cap: float = _controller._wrister_load_cap(ld.is_backhand)
	var v1 := _skater.velocity
	var puck_now: Vector3 = _skater.get_blade_contact_global()
	var true_aim := Vector3(_input.mouse_world_pos.x - puck_now.x, 0.0, _input.mouse_world_pos.z - puck_now.z)
	var aim_err: float = rad_to_deg(Vector2(aim.x, aim.z).angle_to(Vector2(true_aim.x, true_aim.z)))
	var drift: float = Vector2(puck_now.x - _controller._aiming.wrister_origin_world.x, puck_now.z - _controller._aiming.wrister_origin_world.z).length()
	gut.p("    origin left %.2f m behind the puck; aim off puck->cursor by %.1f deg" % [drift, aim_err])
	_input.shoot_held = false
	_tick(move_aim, cursor_rel, 0.0)
	var out: float = _released[0].length() if not _released.is_empty() else -1.0
	gut.p("%-34s v_in=(%.1f,%.1f) v_rel=(%.1f,%.1f) face=(%.2f,%.2f) puck_brg=%.0f aim_brg=%.0f %s load=%.2f arm=%.2f power_t=%.2f cap=%.1f/%.1f released=%.1f" % [
		label, v0.x, v0.z, v1.x, v1.z, face0.x, face0.z,
		_bearing_deg(Vector3(pin.x, 0.0, pin.z)), _bearing_deg(aim),
		"BH" if ld.is_backhand else "FH", ld.load_share, ld.arm_share, t, cap,
		_controller.max_wrister_power, out])
	assert_true(true)


const FWD := Vector2(0.0, -1.0)
const LEFT := Vector2(-1.0, 0.0)
const RIGHT := Vector2(1.0, 0.0)
const BACK := Vector2(0.0, 1.0)
const NET_AHEAD := Vector3(0.0, 0.0, -12.0)
const NET_LEFT := Vector3(-12.0, 0.0, -3.0)
const NET_RIGHT := Vector3(12.0, 0.0, -3.0)


func test_straight() -> void:
	_run("fwd, shoot ahead", FWD, FWD, NET_AHEAD, false, 30)

func test_stance_straight() -> void:
	_run("stance fwd, shoot ahead", FWD, FWD, NET_AHEAD, true, 30)

func test_cut_left() -> void:
	_run("stance fwd->cut L, ahead", FWD, LEFT, NET_AHEAD, true, 30)

func test_cut_right() -> void:
	_run("stance fwd->cut R, ahead", FWD, RIGHT, NET_AHEAD, true, 30)

func test_cut_back() -> void:
	_run("stance fwd->back, ahead", FWD, BACK, NET_AHEAD, true, 30)

func test_side_left_cut_right() -> void:
	_run("stance L->R, shoot L-side", LEFT, RIGHT, NET_AHEAD, true, 30)

func test_side_left_cut_left() -> void:
	_run("stance R->L, shoot ahead", RIGHT, LEFT, NET_AHEAD, true, 30)

func test_cursor_left_cut() -> void:
	_run("stance fwd->cut R, net left", FWD, RIGHT, NET_LEFT, true, 30)

func test_cursor_right_cut() -> void:
	_run("stance fwd->cut L, net right", FWD, LEFT, NET_RIGHT, true, 30)

func test_long_hold_cut() -> void:
	_run("stance fwd->cut L, ahead, long", FWD, LEFT, NET_AHEAD, true, 70)

func test_long_hold_cut_r() -> void:
	_run("stance fwd->cut R, ahead, long", FWD, RIGHT, NET_AHEAD, true, 70)
