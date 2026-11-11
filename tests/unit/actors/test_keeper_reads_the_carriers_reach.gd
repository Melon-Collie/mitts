extends GutTest

# The keeper reads a carrier's reach (KeeperPlayRead.CARRIER_REACH_M): how
# far across from his body the live skater gets the puck pulling it from one
# side to the other, either hand, at a dangle's pace and at speed. Driven
# through the real controller, the blade's contact point read off the rig.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
# The reach he plays is the skater's furthest pull on average, to within
# MEAN_TOLERANCE_M, and no pull falls further than SPREAD_M from it.
const MEAN_TOLERANCE_M: float = 0.05
const SPREAD_M: float = 0.25
const HEADING := Vector3(0.0, 0.0, -1.0)


class GameStateStub:
	extends Node

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


func _make_carrier(left: bool) -> SkaterController:
	var skater: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(skater)
	skater.set_process(false)
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	var gs := GameStateStub.new()
	add_child_autofree(gs)
	var c := SkaterController.new()
	add_child_autofree(c)
	c.setup(skater, puck, gs)
	skater.is_left_handed = left
	c.apply_attributes(PlayerAttributes.neutral())
	skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	puck.set_carrier(skater)
	c.on_puck_picked_up_network()
	return c


# A tick skating ahead (`push`), the cursor ahead of him and `aim` across.
func _step(c: SkaterController, input: InputState, aim: float, push: bool) -> void:
	var sk: Skater = c.skater
	input.delta = DT
	input.host_timestamp += DT
	input.move_vector = Vector2(0.0, -1.0) if push else Vector2.ZERO
	var across := Vector3(-HEADING.z, 0.0, HEADING.x)
	input.mouse_world_pos = sk.global_position + HEADING * 1.5 + across * aim * 3.0
	input.mouse_world_pos.y = 0.0
	c._process_input(input, DT)
	sk._physics_process(DT)
	sk._process(DT)


# The blade's contact across from his body, square to where he skates.
func _across(c: SkaterController) -> float:
	var sk: Skater = c.skater
	var v: Vector3 = Vector3(sk.velocity.x, 0.0, sk.velocity.z)
	var d: Vector3 = v.normalized() if v.length() > 0.5 else HEADING
	return (sk.get_blade_contact_global() - sk.global_position).dot(Vector3(-d.z, 0.0, d.x))


func test_a_pull_across_gets_the_puck_the_reach_he_plays() -> void:
	var total: float = 0.0
	var pulls: int = 0
	for ramp_ticks: int in [60, 120]:
		for left: bool in [true, false]:
			for side: float in [-1.0, 1.0]:
				var c := _make_carrier(left)
				var input := InputState.new()
				for t: int in ramp_ticks:
					_step(c, input, 0.0, true)
				for t: int in 120:
					_step(c, input, side, ramp_ticks >= 120)
				var furthest: float = 0.0
				for t: int in 90:
					_step(c, input, -side, ramp_ticks >= 120)
					furthest = maxf(furthest, -side * _across(c))
				total += furthest
				pulls += 1
				assert_almost_eq(furthest, KeeperPlayRead.CARRIER_REACH_M, SPREAD_M,
						"%s, %.1f m/s, pulled to %+.0f" % ["left" if left else "right", c.skater.velocity.length(),
						-side])
	assert_almost_eq(total / pulls, KeeperPlayRead.CARRIER_REACH_M, MEAN_TOLERANCE_M, "on average")
