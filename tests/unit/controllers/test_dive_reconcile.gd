extends GutTest

# A downed skater through reconcile. Two things the tick does while he is down
# feed the next tick's upper-body twist, which the reconcile threshold compares
# against the host's: the fall tilt (MeshRoot is the ancestor of the gameplay
# frame the blade hangs from) and the down pose's stick (the twist follows the
# blade). A replay that skips either turns the shoulders where the host's never
# went, so the next ack reconciles again. And the reconcile's final blade write
# has to leave the down pose's stick where the tick put it, or it pops to the
# cursor until the next tick.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION


class StubGameState extends Node:
	var host: bool = true

	func is_host() -> bool:
		return host

	func is_movement_locked() -> bool:
		return false


func _make(controller: SkaterController, host: bool) -> SkaterController:
	var puck: Puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	puck.global_position = Vector3(20.0, 0.0, 20.0)
	var skater: Skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(skater)
	skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	# The reconcile re-applies the facing it snaps to, so start the stored facing
	# and the node's yaw in agreement.
	skater.set_facing(Vector2(0.0, -1.0))
	skater.set_process(false)
	skater.set_physics_process(false)
	var state := StubGameState.new()
	state.host = host
	add_child_autofree(state)
	add_child_autofree(controller)
	controller.setup(skater, puck, state)
	controller.set_process(false)
	controller.set_physics_process(false)
	return controller


# Skate up, dive with the cursor off to the side, lie there on the block, let
# go and get up. The cursor keeps moving so the twist has something to follow.
func _script() -> Array[InputState]:
	var inputs: Array[InputState] = []
	var down_at: int = 60
	var release_at: int = down_at + ceili(DiveRules.DOWN_S / DT)
	var end: int = release_at + ceili(0.8 / DT) + 30
	for i: int in end:
		var input := InputState.new()
		input.delta = DT
		input.move_vector = Vector2(0.0, -1.0) if i < down_at else Vector2.ZERO
		input.stance_held = i >= down_at and i < release_at
		input.block_held = input.stance_held
		var a: float = float(i) * 0.03
		input.mouse_world_pos = Vector3(3.0 * cos(a), 0.0, -4.0 + 2.0 * sin(a))
		inputs.append(input)
	return inputs


func test_a_replay_reproduces_the_live_twist_through_the_fall_and_the_get_up() -> void:
	var live: SkaterController = _make(SkaterController.new(), true)
	var replay: SkaterController = _make(SkaterController.new(), true)
	replay.is_replaying = true
	var worst: float = 0.0
	var worst_tick: int = -1
	var was_down: bool = false
	var inputs: Array[InputState] = _script()
	for i: int in inputs.size():
		# Inputs are positions relative to the skater; both start in one place.
		var input: InputState = inputs[i]
		input.mouse_world_pos += Vector3(live.skater.global_position.x, 0.0,
				live.skater.global_position.z)
		live._process_input(input, DT)
		replay._process_input(input, DT)
		was_down = was_down or live.knockdown_timer > 0.0
		var d: float = absf(angle_difference(live._pose.upper_body_angle,
				replay._pose.upper_body_angle))
		if d > worst:
			worst = d
			worst_tick = i
	assert_true(was_down, "the control: he went down")
	assert_false(live.skater.is_knocked_down, "the control: and got back up")
	assert_lt(worst, 1e-4,
			"replayed ticks twist as the live ones did (worst %.4f rad at tick %d)" % [worst, worst_tick])


func test_a_reconcile_leaves_a_divers_stick_laid_out() -> void:
	var c: LocalController = _make(
			load("res://Scenes/LocalController.tscn").instantiate() as LocalController,
			false) as LocalController
	var dive := InputState.new()
	dive.stance_held = true
	dive.block_held = true
	dive.delta = DT
	for _i: int in 60:
		dive.mouse_world_pos = c.skater.global_position + Vector3(3.0, 0.0, 0.0)
		c._process_input(dive, DT)
	assert_true(c.skater.dive_laid_out, "the control: lying laid out")
	var before: Vector3 = _blade_off_drawn_body(c.skater)
	assert_gt(before.x, c.stick_length, "the control: the stick lies out along the layout")
	# The host's state here, far enough off to force the snap.
	var server := SkaterNetworkState.new()
	c.fill_network_state(server)
	server.position += Vector3(0.0, 0.0, 0.5)
	server.last_processed_host_timestamp = 1.0
	server.shot_state = c.skater.current_shot_state
	c.reconcile(server)
	assert_almost_eq(c.skater.global_position.z, server.position.z, 0.001, "the reconcile snapped")
	var after: Vector3 = _blade_off_drawn_body(c.skater)
	assert_lt(after.distance_to(before), 0.05,
			"the stick stays laid out through the reconcile (%s vs %s)" % [after, before])


# The blade off the body as drawn: the snap's visual_offset carries MeshRoot,
# and the blade with it, back to where the body was.
func _blade_off_drawn_body(skater: Skater) -> Vector3:
	return skater.get_blade_contact_global() - (skater.global_position + skater.visual_offset)
