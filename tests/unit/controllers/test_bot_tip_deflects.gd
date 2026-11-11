extends GutTest

# A bot holding the deflect button tips the puck, as a human does: the
# finisher's tip (AIRoleFinisher) holds it so a shot it would otherwise catch
# — a blade on the shot's line holds one to 30 m/s — is redirected. Through the
# real AIController input path and the host's present-time detection
# (PuckController._check_interactions).

const DT: float = 1.0 / 90.0


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false

	func allows_blade_aim_during_lock() -> bool:
		return false

	func is_in_goal_celebration() -> bool:
		return false


var _puck: Puck = null
var _skater: Skater = null
var _bot: AIController = null
var _pc: PuckController = null
var _input := InputState.new()


func before_each() -> void:
	_puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	add_child_autofree(_puck)
	_puck.set_physics_process(false)
	_puck.set_process(false)
	var state := StubGameState.new()
	add_child_autofree(state)
	_skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(_skater)
	_skater.global_position = Vector3(0.0, 0.0, -8.0)
	_skater.set_physics_process(false)
	_skater.set_process(false)
	_bot = AIController.new()
	add_child_autofree(_bot)
	_bot.setup(_skater, _puck, state)
	_skater.capture_prev_blade_contact()   # a still blade
	_pc = PuckController.new()
	add_child_autofree(_pc)
	_pc.set_physics_process(false)
	_pc.set_process(false)
	_pc.setup(_puck, true)
	_pc.set_team_id_by_skater({_skater: 0})
	_pc.set_skater_getter(func() -> Array: return [_skater])
	_pc.set_peer_id_resolver(func(_s: Skater) -> int: return 2)
	_input = InputState.new()
	_input.delta = DT


# Fires the puck at `speed` square onto the middle of the still blade.
func _fire(speed: float) -> void:
	var mid: Vector3 = _skater.get_blade_contact_global()
	var axis: Vector3 = PuckReceptionRules.blade_axis(mid,
			_skater.top_hand.global_position, Vector3.FORWARD)
	var normal := Vector3(-axis.z, 0.0, axis.x)
	var line := Vector3(mid.x, _puck.ice_height, mid.z)
	_pc._prev_puck_pos = line + normal * 0.8
	_puck.set_puck_position(line + normal * 0.05)
	_puck.set_puck_velocity(-normal * speed)
	_pc._check_interactions()


func test_a_bot_holding_the_button_deflects() -> void:
	_input.stick_lift_held = true
	_bot._process_input(_input, DT)
	assert_true(_skater.deflect_intent, "a bot's held button is the deflect, as a human's is")


func test_without_it_the_bot_catches_a_shot_on_its_line() -> void:
	_bot._process_input(_input, DT)
	_fire(20.0)
	assert_eq(_puck.carrier, _skater, "on the line at 20 m/s, the blade holds it")


func test_holding_it_the_bot_tips_the_same_shot() -> void:
	_input.stick_lift_held = true
	_bot._process_input(_input, DT)
	_fire(20.0)
	assert_null(_puck.carrier, "the deflect redirects it instead")
	assert_true(_puck.is_on_cooldown(_skater), "the tipper's own blade is off it")
