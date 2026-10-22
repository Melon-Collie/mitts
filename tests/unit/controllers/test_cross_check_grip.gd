extends GutTest

# The cross-check holds the stick the way the skater always holds it: the top
# hand on its own shoulder's side of the chest, the shaft running across to the
# blade side with the bottom hand on the bottom shoulder's side. A hand posed
# across the chest from its shoulder crosses the arms. Measured on the live rig,
# square and aimed, for both shots.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const DT: float = 1.0 / 120.0
# Into the push, past the third of the way out where the pose is fully on.
const PUSH_TICKS: int = 8


class GameStateStub:
	extends Node

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


func _shoving(lefty: bool, aim: Vector3) -> SkaterController:
	var skater: Skater = SKATER_SCENE.instantiate() as Skater
	skater.is_left_handed = lefty
	add_child_autofree(skater)
	skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	skater.set_process(false)
	skater.set_physics_process(false)
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	puck.global_position = Vector3(30.0, 0.0, 30.0)
	var gs := GameStateStub.new()
	add_child_autofree(gs)
	var controller := SkaterController.new()
	add_child_autofree(controller)
	controller.setup(skater, puck, gs)
	controller.apply_attributes(PlayerAttributes.neutral())
	var input := InputState.new()
	for i: int in 40 + PUSH_TICKS:
		input.delta = DT
		input.host_timestamp += DT
		input.mouse_world_pos = skater.global_position + (Vector3(0.0, 0.0, -3.0) if i < 40 else aim)
		input.hit_held = i >= 40
		input.stick_check_pressed = i == 40
		controller._process_input(input, DT)
		skater._physics_process(DT)
		skater._process(DT)
	return controller


func test_the_hands_hold_the_shaft_on_their_own_sides() -> void:
	for lefty: bool in [true, false]:
		for aim: Vector3 in [Vector3(0.0, 0.0, -3.0), Vector3(2.3, 0.0, -1.93)]:
			var c: SkaterController = _shoving(lefty, aim)
			var skater: Skater = c.skater
			var label: String = "%s, aim %s" % ["lefty" if lefty else "righty", aim]
			assert_eq(skater.cross_check_phase, CrossCheckRules.Phase.THROW, label)
			var top_side: float = signf(skater.shoulder.position.x)
			var bottom_side: float = signf(skater.bottom_shoulder.position.x)
			assert_eq(top_side, -bottom_side, "%s: the shoulders are either side" % label)
			assert_gt(skater.top_hand.position.x * top_side, 0.0,
					"%s: the top hand on its own shoulder's side" % label)
			assert_gt(skater.bottom_hand.position.x * bottom_side, 0.0,
					"%s: the bottom hand on its own shoulder's side" % label)
			assert_gt(skater.get_blade_position().x * bottom_side, 0.0,
					"%s: the shaft runs across to the blade side" % label)
