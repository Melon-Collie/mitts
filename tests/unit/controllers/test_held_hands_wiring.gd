extends GutTest

# Held hands (docs/held-hands-plan.md, SkaterIKCoordinator.held_top_hand): every
# read of the shaft goes through Skater.shaft_hand, which is the marker with the
# switch off; with it on, a carry the body cannot hold is held a stick's length
# from the same blade, the drawn hand comes to it, and a skater who is down keeps
# the marker.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION


class GameStateStub:
	extends Node

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _skater: Skater
var _controller: SkaterController
var _was: bool


func before_each() -> void:
	_was = SkaterIKCoordinator.held_hands


func after_each() -> void:
	SkaterIKCoordinator.held_hands = _was


# A standing carrier settled with the cursor close in front: a carry the
# anchor holds with the fist in the jersey (tests/instruments/actors/test_hold_map.gd).
func _carry() -> void:
	_skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(_skater)
	_skater.set_process(false)
	_skater.set_physics_process(false)
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	var gs := GameStateStub.new()
	add_child_autofree(gs)
	_controller = SkaterController.new()
	add_child_autofree(_controller)
	_controller.setup(_skater, puck, gs)
	_controller.apply_attributes(PlayerAttributes.neutral())
	_controller.set_process(false)
	_controller.set_physics_process(false)
	_skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	_skater._process(DT)
	puck.set_carrier(_skater)
	_controller.on_puck_picked_up_network()
	var input := InputState.new()
	for _i: int in 120:
		input.delta = DT
		input.host_timestamp += DT
		_controller._pose.facing = Vector2(0.0, -1.0)
		_skater.set_facing(_controller._pose.facing)
		input.mouse_world_pos = _skater.global_position + Vector3(0.0, 0.0, -0.8)
		input.mouse_world_pos.y = 0.0
		_skater.capture_prev_blade_contact()
		_controller._process_input(input, DT)
		_skater._physics_process(DT)
		_skater._process(DT)


func test_off_the_shaft_is_the_marker() -> void:
	SkaterIKCoordinator.held_hands = false
	_carry()
	assert_eq(_skater.shaft_hand(), _skater.top_hand.position)


func test_on_an_unheld_carry_is_held_round_the_same_blade() -> void:
	SkaterIKCoordinator.held_hands = true
	_carry()
	var marker: Vector3 = _skater.top_hand.position
	var blade: Vector3 = _skater.blade.position
	var held: Vector3 = _skater.shaft_hand()
	assert_gt(held.distance_to(marker), 0.02, "the hand moved off the marker")
	assert_almost_eq(held.distance_to(blade), marker.distance_to(blade), 0.0005,
			"a stick's length from the same blade")
	var body := SkaterHoldModel.Body.new()
	var report := SkaterHoldModel.Report.new()
	_controller._ik.fill_hold_body(body)
	SkaterHoldModel.evaluate(body, marker, blade, report)
	var before: float = report.total()
	SkaterHoldModel.evaluate(body, held, blade, report)
	assert_lt(report.total(), before * 0.1, "and held: %.0f mm past the limits from %.0f" % [
			report.total() * 1000.0, before * 1000.0])


func test_the_drawn_hand_comes_to_the_held_one() -> void:
	SkaterIKCoordinator.held_hands = true
	_carry()
	var drawn: Vector3 = _skater.drawn_top_hand()
	assert_lt(drawn.distance_to(_skater.shaft_hand()), 0.03,
			"within the shaft clearance's few centimetres")


func test_a_skater_who_is_down_keeps_the_marker() -> void:
	SkaterIKCoordinator.held_hands = true
	_carry()
	_skater.is_knocked_down = true
	assert_eq(_skater.shaft_hand(), _skater.top_hand.position)
