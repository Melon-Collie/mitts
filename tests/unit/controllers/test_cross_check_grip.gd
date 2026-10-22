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


var _let_go_before: float = 0.0


func _shoving(lefty: bool, aim: Vector3, push_ticks: int = PUSH_TICKS,
		puck_at: Vector3 = Vector3(30.0, 0.0, 30.0), rest_ticks: int = 40) -> SkaterController:
	var skater: Skater = SKATER_SCENE.instantiate() as Skater
	skater.is_left_handed = lefty
	add_child_autofree(skater)
	skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	skater.set_process(false)
	skater.set_physics_process(false)
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	puck.global_position = puck_at
	var gs := GameStateStub.new()
	add_child_autofree(gs)
	var controller := SkaterController.new()
	add_child_autofree(controller)
	controller.setup(skater, puck, gs)
	controller.apply_attributes(PlayerAttributes.neutral())
	var input := InputState.new()
	for i: int in rest_ticks + push_ticks:
		if i == rest_ticks:
			_let_go_before = controller._ik._bh_release
		input.delta = DT
		input.host_timestamp += DT
		input.mouse_world_pos = skater.global_position + (Vector3(0.0, 0.0, -3.0) if i < rest_ticks else aim)
		input.hit_held = i >= rest_ticks
		input.stick_check_pressed = i == rest_ticks
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


# Stood reaching an empty stick at a loose puck, the bottom hand is off the
# shaft; the throw takes hold of it with both hands.
func test_both_hands_are_on_the_shaft_at_the_push() -> void:
	for ticks: int in [PUSH_TICKS + 4, 24]:
		var c: SkaterController = _shoving(true, Vector3(0.0, 0.0, -3.0), ticks,
				Vector3.ZERO, 160)
		var skater: Skater = c.skater
		assert_gt(_let_go_before, 0.5, "the hand starts off the stick")
		var top: Vector3 = skater.drawn_top_hand()
		var shaft: Vector3 = skater.drawn_blade().origin - top
		var rel: Vector3 = skater.bottom_hand.position - top
		var along: float = rel.dot(shaft) / shaft.length_squared()
		assert_between(along, 0.0, 1.0, "%d ticks in: the grip is on the shaft" % ticks)
		assert_lt((rel - shaft * along).length(), 0.01, "%d ticks in: and the hand is on it" % ticks)
