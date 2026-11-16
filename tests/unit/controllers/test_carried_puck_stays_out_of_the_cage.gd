extends GutTest

# A carried puck is solid to the outside of the cage, at any speed the carrier
# skates into it. The controller resolves the pin against the twine
# (SkaterController._collide_pinned_puck_with_net) before Skater integrates the
# body, and Puck places itself after (priority 1), at the carry target the
# moved body now has plus the correction. Measured in a staged own goal
# (tools/own_goal_stage.gd): a defenseman skating at the side of his own net at
# 4.7 m/s, the puck between him and the side twine, was placed a tick's travel
# into it every tick, until a placement read as inside the cage and the twine
# held it in; it then slid out over his goal line from behind.
#
# Drives a real Skater + SkaterController and reads the puck where Puck places
# it: after the body's integration.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const G: float = GameRules.GOAL_LINE_Z
# How far into the twine the puck may sit: its outside surface is the plane at
# the post line, and the puck's centre rests a radius outside it.
const SINK_M: float = 0.01


class GameStateStub:
	extends Node

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


func test_carried_into_the_side_of_the_cage_the_puck_stays_outside_it() -> void:
	for speed: float in [2.0, 4.7, 7.0]:
		var deepest: float = _skate_at_the_side(speed)
		assert_lt(deepest, SINK_M, "at %.1f m/s: the puck %.3f m into the side twine" % [speed, deepest])


# A carrier behind the goal line beside the cage, skating across at it at
# `speed` with the cursor reaching into the net. The deepest the placed puck sat
# past the side twine's outside surface, while it was beside the cage.
func _skate_at_the_side(speed: float) -> float:
	var skater: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(skater)
	skater.set_process(false)
	skater.set_physics_process(false)
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	var gs := GameStateStub.new()
	add_child_autofree(gs)
	var c := SkaterController.new()
	add_child_autofree(c)
	c.setup(skater, puck, gs)
	c.apply_attributes(PlayerAttributes.neutral())
	var depth: float = 0.75
	skater.global_position = Vector3(3.2, GameRules.FACEOFF_SPAWN_HEIGHT, G + depth)
	skater.set_facing(Vector2(-1.0, 0.0))
	puck.global_position = Vector3(2.0, 0.0, G + depth)
	puck.set_carrier(skater)
	c.has_puck = true
	c._sm.set_state(SkaterStateMachine.State.SKATING_WITH_PUCK)
	var surface: float = NetGeometry.cavity_half_width() + GameRules.PUCK_COLLISION_RADIUS
	var deepest: float = 0.0
	var input := InputState.new()
	for i: int in 90:
		input.delta = DT
		input.host_timestamp += DT
		input.move_vector = Vector2(-1.0, 0.0)
		input.mouse_world_pos = Vector3(0.4, 0.0, G + depth)
		skater.capture_prev_blade_contact()
		c._process_input(input, DT)
		# The body at the pace the case is about, whatever the stride has built.
		if skater.velocity.length() > 0.1:
			skater.velocity = Vector3(-speed, 0.0, 0.0)
		skater._physics_process(DT)
		if not c.has_puck:
			break
		var placed: Vector3 = skater.get_carry_target_global()
		var behind: float = absf(placed.z) - G
		if behind > 0.0 and behind < GameRules.NET_DEPTH and placed.x > 0.0:
			deepest = maxf(deepest, surface - placed.x)
	return deepest
