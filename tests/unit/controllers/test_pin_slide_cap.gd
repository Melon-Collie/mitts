extends GutTest

# A skater locked in a board pin slides along the wall no faster than his role's
# cap (SkaterController._apply_pin_slide_cap, after the movement kernel). It reads
# only the replicated role and strength, so the live step and the reconcile replay
# both reproduce it; unlocked, the same stride runs free.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION


class GameStateStub:
	extends Node

	func is_host() -> bool:
		return false

	func is_movement_locked() -> bool:
		return false


func _make_controller() -> SkaterController:
	var skater: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(skater)
	skater.set_physics_process(false)
	skater.set_process(false)
	var puck: Puck = (preload("res://Scenes/Puck.tscn").instantiate()) as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	puck.global_position = Vector3(20.0, 0.0, 20.0)
	var gs := GameStateStub.new()
	add_child_autofree(gs)
	var controller := SkaterController.new()
	add_child_autofree(controller)
	controller.setup(skater, puck, gs)
	skater.global_position = Vector3(GameRules.INNER_HALF_WIDTH - skater.collision_radius() - 0.05,
			GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	return controller


# The fastest along-wall (z) speed over a second of striding along the +x boards.
func _fastest_slide(c: SkaterController) -> float:
	var input := InputState.new()
	input.move_vector = Vector2(0.0, 1.0)
	var fastest: float = 0.0
	for _i: int in 120:
		c._apply_movement(input, DT)
		fastest = maxf(fastest, absf(c.skater.velocity.z))
	return fastest


func test_a_pinned_skater_slides_no_faster_than_his_cap() -> void:
	var c: SkaterController = _make_controller()
	assert_gt(_fastest_slide(c), 3.0, "the control: free, he strides away along the wall")
	c.skater.velocity = Vector3.ZERO
	c.skater.pin_role = BoardPinRules.Role.PINNED
	c.skater.pin_strength = 0.5
	var cap: float = BoardPinRules.slide_cap(BoardPinRules.Role.PINNED, 0.5)
	var slide: float = _fastest_slide(c)
	assert_lte(slide, cap + 1e-4)
	assert_gt(slide, cap * 0.9, "and does slide")


func test_neither_side_of_a_pin_commits_and_the_pinned_one_takes_no_stance() -> void:
	var c: SkaterController = _make_controller()
	c.skater.pin_role = BoardPinRules.Role.PINNED
	var input := InputState.new()
	input.hit_held = true
	input.stance_held = true
	c._apply_movement(input, DT)
	assert_false(c.skater.hit_committed, "pressed into the glass")
	assert_false(c.stance_active)
	c.skater.pin_role = BoardPinRules.Role.PINNER
	c._apply_movement(input, DT)
	assert_false(c.skater.hit_committed, "the pin is held on the stick button")
	assert_true(c.stance_active, "the pinner may still load up")
