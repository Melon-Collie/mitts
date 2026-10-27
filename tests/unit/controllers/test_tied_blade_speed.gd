extends GutTest

# Two tied sticks push against each other: a tied skater's blade chases its
# cursor at StickCheckRules.TIE_BLADE_SPEED_M_S rather than the free cap, on the
# native dangle and the GDScript one alike. It reads only the skater's own input
# and the replicated stick_tied bit, so a tied client predicts its own blade.

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
	return controller


# The fastest the smoothed blade travels in a tick over a sweep from one side
# of the body to the other.
func _fastest_step(c: SkaterController) -> float:
	var input := InputState.new()
	var pos: Vector3 = c.skater.global_position
	input.mouse_world_pos = pos + Vector3(-1.2, 0.0, -1.0)
	for _i: int in 30:
		c._ik.apply_blade_from_mouse(input, DT)
	input.mouse_world_pos = pos + Vector3(1.2, 0.0, -1.0)
	var fastest: float = 0.0
	var prev: Vector3 = c._ik._smoothed_blade_world
	for _i: int in 60:
		c._ik.apply_blade_from_mouse(input, DT)
		fastest = maxf(fastest, c._ik._smoothed_blade_world.distance_to(prev))
		prev = c._ik._smoothed_blade_world
	return fastest


func test_a_tied_blade_chases_at_the_ties_speed() -> void:
	var c: SkaterController = _make_controller()
	var free_step: float = _fastest_step(c)
	assert_gt(free_step, StickCheckRules.TIE_BLADE_SPEED_M_S * DT * 2.0,
			"the control: a free blade sweeps far faster")
	c.skater.stick_tied = true
	var tied_step: float = _fastest_step(c)
	assert_lte(tied_step, StickCheckRules.TIE_BLADE_SPEED_M_S * DT + 1e-4)
	assert_gt(tied_step, StickCheckRules.TIE_BLADE_SPEED_M_S * DT * 0.9, "and does move")


func test_untying_gives_the_free_blade_back() -> void:
	var c: SkaterController = _make_controller()
	c.skater.stick_tied = true
	_fastest_step(c)
	c.skater.stick_tied = false
	assert_gt(_fastest_step(c), StickCheckRules.TIE_BLADE_SPEED_M_S * DT * 2.0)
