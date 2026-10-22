extends GutTest

# A slapshot's aim is live until the swing commits (docs/slapshot-realism-plan.md,
# Phase 3): free while the hips are still setting, which chase it; once the feet
# have set, the shoulders turn it no more than slapper_aim_arc_deg off their line
# and the hips hold; and the shot leaves along wherever it was on the release
# tick. Driven through the real controller and rig.

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


# `target`: the cursor, world XZ.
func _tick(target: Vector2, slap: bool, press: bool = false) -> void:
	_input.delta = DT
	_input.host_timestamp += DT
	_input.move_vector = Vector2.ZERO
	_input.mouse_world_pos = Vector3(target.x, 0.0, target.y)
	_input.slap_held = slap
	_input.slap_pressed = press
	_controller._process_input(_input, DT)
	_skater._physics_process(DT)


func _here() -> Vector2:
	return Vector2(_skater.global_position.x, _skater.global_position.z)


# A cursor 12 m out from the pinned puck, `deg` off `line`.
func _off_line(line: Vector2, deg: float) -> Vector2:
	var puck: Vector3 = _skater.get_carry_target_global()
	return Vector2(puck.x, puck.z) + line.rotated(deg_to_rad(deg)) * 12.0


func _set_up() -> Vector2:
	var ahead: Vector2 = _here() + Vector2(0.0, -12.0)
	for i: int in 60:
		_tick(_here() + Vector2(0.4, -2.0), false)
	_tick(ahead, true, true)
	while not _controller._aiming.slapper_setup_done:
		_tick(ahead, true)
	return _controller._aiming.slapper_stance_line


func test_the_aim_follows_the_cursor_inside_the_arc() -> void:
	var line: Vector2 = _set_up()
	assert_ne(line, Vector2.ZERO, "the feet set up on a line")
	for i: int in 10:
		_tick(_off_line(line, 12.0), true)
	assert_almost_eq(rad_to_deg(line.angle_to(_controller._sm.locked_slapper_dir)), 12.0, 0.5)


func test_the_aim_holds_at_the_edge_of_the_arc_and_the_hips_hold() -> void:
	var line: Vector2 = _set_up()
	var stance: Vector2 = _controller.slapper_stance_facing()
	for i: int in 30:
		_tick(_off_line(line, -50.0), true)
	assert_almost_eq(rad_to_deg(line.angle_to(_controller._sm.locked_slapper_dir)),
			-_controller.slapper_aim_arc_deg, 0.01, "held at the edge, on the side pointed")
	assert_almost_eq(stance.angle_to(_controller.slapper_stance_facing()), 0.0, 0.0001,
			"the feet stay set")


func test_the_shot_leaves_along_the_aim_on_the_release_tick() -> void:
	var line: Vector2 = _set_up()
	for i: int in 40:
		_tick(_off_line(line, -15.0), true)
	_tick(_off_line(line, 10.0), false)
	assert_eq(_skater.current_shot_state, State.FOLLOW_THROUGH, "released")
	var shot := Vector2(_controller._sm.shot_dir.x, _controller._sm.shot_dir.z).normalized()
	assert_almost_eq(rad_to_deg(line.angle_to(shot)), 10.0, 0.5,
			"fired where the release tick aimed, not the press or the wind-up")


func test_while_the_hips_are_setting_they_chase_the_aim() -> void:
	for i: int in 60:
		_tick(_here() + Vector2(0.4, -2.0), false)
	_tick(_here() + Vector2(0.0, -12.0), true, true)
	var first: Vector2 = _controller.slapper_stance_facing()
	_tick(_here() + Vector2(-12.0, -6.0), true)
	assert_false(_controller._aiming.slapper_setup_done, "still setting up")
	assert_gt(absf(rad_to_deg(first.angle_to(_controller.slapper_stance_facing()))), 20.0,
			"the stance follows the aim before the feet are set")


func test_a_puckless_wind_up_keeps_turning_with_the_aim() -> void:
	_controller.on_puck_released_network()
	_tick(_here() + Vector2(0.0, -12.0), true, true)
	for i: int in 30:
		_tick(_here() + Vector2(0.0, -12.0), true)
	var first: Vector2 = _controller.slapper_stance_facing()
	for i: int in 30:
		_tick(_here() + Vector2(-10.0, -8.0), true)
	assert_eq(_skater.current_shot_state, State.SLAPPER_CHARGE_WITHOUT_PUCK)
	assert_gt(absf(rad_to_deg(first.angle_to(_controller.slapper_stance_facing()))), 20.0,
			"waiting on a feed, the hips open to wherever the aim goes")
	assert_almost_eq(_controller._pose.facing.angle_to(_controller.slapper_stance_facing()), 0.0, 0.05,
			"and get there")
