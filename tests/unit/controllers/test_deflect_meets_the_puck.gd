extends GutTest

# Pressing deflect reads the incoming puck and brings the blade to its height,
# in DeflectReachRules' time, through the real controller (SkaterController →
# Skater's lift blend → the IK); the host's contact test
# (PuckController._check_interactions) tips it there in the direction the loft
# level names. Held from before a release, the blade does not follow.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const DT: float = 1.0 / 120.0  # a fixed step: the script below is timed in it
const SPEED: float = 20.0


class GameStateStub:
	extends Node

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _c: SkaterController = null
var _puck: Puck = null
var _pc: PuckController = null
var _cursor := Vector3.ZERO
var _vel := Vector3.ZERO


func before_each() -> void:
	var skater: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(skater)
	skater.set_physics_process(false)
	skater.set_process(false)
	_puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(_puck)
	_puck.set_physics_process(false)
	_puck.set_process(false)
	_puck.global_position = Vector3(20.0, _puck.ice_height, 20.0)
	var gs := GameStateStub.new()
	add_child_autofree(gs)
	_c = SkaterController.new()
	add_child_autofree(_c)
	_c.setup(skater, _puck, gs)
	skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	_cursor = skater.global_position + Vector3(0.0, 0.0, -1.2)
	_pc = PuckController.new()
	add_child_autofree(_pc)
	_pc.set_physics_process(false)
	_pc.set_process(false)
	_pc.setup(_puck, true)
	_pc.set_team_id_by_skater({skater: 0})
	_pc.set_skater_getter(func() -> Array: return [skater])
	_pc.set_peer_id_resolver(func(_s: Skater) -> int: return 1)
	_tick(false, ShotMechanics.ELEVATION_FLAT, 30)


func _tick(deflect: bool, level: int, ticks: int, fly: bool = false) -> void:
	for _i: int in ticks:
		var input := InputState.new()
		input.stick_lift_held = deflect
		input.elevation_level = level
		input.mouse_world_pos = _cursor
		input.delta = DT
		_c._process_input(input, DT)
		_c.skater._update_blade_lift(DT)
		if fly:
			_pc._prev_puck_pos = _puck.global_position
			_vel.y -= GameRules.GRAVITY_M_S2 * DT
			_puck.global_position += _vel * DT
			_puck.linear_velocity = _vel
			_pc._check_interactions()
			_vel = _puck.linear_velocity


# A puck flying across the blade's line from `dist` m out, crossing at `height`.
func _launch(height: float, dist: float = 4.0, airborne: bool = true) -> void:
	var blade: Vector3 = _c.skater.get_blade_contact_global()
	var t: float = dist / SPEED
	var y0: float = height + 0.5 * GameRules.GRAVITY_M_S2 * t * t if airborne else _puck.ice_height
	_puck.global_position = Vector3(blade.x + dist, y0, blade.z)
	_vel = Vector3(-SPEED, 0.0, 0.0)
	_puck.linear_velocity = _vel


func _blade_y() -> float:
	return _c.skater.get_blade_contact_global().y


func test_the_press_takes_the_blade_to_where_the_puck_will_be() -> void:
	_launch(0.4)
	_tick(true, ShotMechanics.ELEVATION_MID, 1)
	assert_true(_c.skater.blade_up)
	assert_lt(_blade_y(), 0.1, "it does not get there at once")
	_tick(true, ShotMechanics.ELEVATION_MID, 40)
	assert_almost_eq(_blade_y(), 0.4, 0.02,
			"the blade waits at the puck's crossing height, not where it is now")


func test_a_full_rise_takes_its_time() -> void:
	_launch(1.0)
	_tick(true, ShotMechanics.ELEVATION_MID, int(0.15 / DT))
	var top: float = _c.blade_height + _c.blade_lift_height
	assert_lt(_blade_y(), top - 0.15, "half way through the rise it is half way up")
	_tick(true, ShotMechanics.ELEVATION_MID, int(0.2 / DT))
	assert_almost_eq(_blade_y(), top, 0.01, "and it stops at a full lift")


func test_a_press_held_from_before_the_release_does_not_follow() -> void:
	_tick(true, ShotMechanics.ELEVATION_LOW, 5)
	_launch(0.3, 8.0)
	_tick(true, ShotMechanics.ELEVATION_LOW, 60, true)
	assert_almost_eq(_blade_y(), _c.blade_height, 0.01, "the blade stayed on the ice")
	assert_almost_eq(_vel.x, -SPEED, 0.01, "and the puck went over it")


func test_pressing_again_reads_again() -> void:
	_tick(true, ShotMechanics.ELEVATION_LOW, 5)
	_launch(0.3, 8.0)
	_tick(false, ShotMechanics.ELEVATION_LOW, 1)
	_tip(ShotMechanics.ELEVATION_LOW, 0.3, 8.0, false)
	assert_lt(_vel.y, 0.0, "re-pressed after the release, it knocks the puck down")


func test_a_late_press_is_a_blade_still_on_its_way() -> void:
	_launch(0.4, 1.5)
	_tick(true, ShotMechanics.ELEVATION_MID, 40, true)
	assert_almost_eq(_vel.x, -SPEED, 0.01, "the puck beat the blade up")


func test_a_puck_on_the_ice_keeps_the_blade_down() -> void:
	_launch(0.0, 4.0, false)
	_tick(true, ShotMechanics.ELEVATION_MID, 40)
	assert_false(_c.skater.blade_up)
	assert_almost_eq(_blade_y(), _c.blade_height, 0.01)


func test_letting_go_brings_the_blade_back_to_the_ice() -> void:
	_launch(0.6)
	_tick(true, ShotMechanics.ELEVATION_MID, 40)
	_tick(false, ShotMechanics.ELEVATION_MID, 30)
	assert_false(_c.skater.blade_up)
	assert_almost_eq(_blade_y(), _c.blade_height, 0.01)


func _tip(level: int, height: float = 0.3, dist: float = 8.0, launch: bool = true) -> void:
	if launch:
		_launch(height, dist)
	_tick(true, level, 80, true)
	assert_gt(_vel.x, -SPEED + 1.0, "the blade met the puck in the air")


func test_mid_tips_an_air_puck_up() -> void:
	_tip(ShotMechanics.ELEVATION_MID)
	assert_gt(_vel.y, 0.0)


func test_low_knocks_an_air_puck_down() -> void:
	_tip(ShotMechanics.ELEVATION_LOW)
	assert_lt(_vel.y, 0.0)


func test_a_puck_over_the_full_lift_goes_past() -> void:
	_launch(1.0, 8.0)
	_tick(true, ShotMechanics.ELEVATION_MID, 80, true)
	assert_almost_eq(_vel.x, -SPEED, 0.01, "a blade at full lift cannot reach up to it")
