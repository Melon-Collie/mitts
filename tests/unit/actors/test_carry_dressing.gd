extends GutTest

# The carry's cosmetic dressing: the shaft bows under a stroke (Skater
# .carry_bow_m) and a carrier's head nods down to the puck as the hands work it
# and as it comes in tight, less at speed (SkaterPoseCoordinator._puck_nod).
# Driven through the real controller.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION


class GameStateStub:
	extends Node

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


func _make_carrier() -> SkaterController:
	var skater: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(skater)
	skater.set_process(false)
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	puck.global_position = Vector3(20.0, 0.0, 20.0)
	var gs := GameStateStub.new()
	add_child_autofree(gs)
	var c := SkaterController.new()
	add_child_autofree(c)
	c.setup(skater, puck, gs)
	c.apply_attributes(PlayerAttributes.neutral())
	skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 25.0)
	puck.set_carrier(skater)
	c.on_puck_picked_up_network()
	return c


# Ticks `ticks` with the cursor at `cursor(t)` off the body and the stick held
# at `move`, calling `each` after every tick.
func _run(c: SkaterController, ticks: int, cursor: Callable, move: Vector2,
		each: Callable) -> void:
	var sk: Skater = c.skater
	var input := InputState.new()
	for t: int in ticks:
		input.delta = DT
		input.host_timestamp += DT
		input.move_vector = move
		input.mouse_world_pos = sk.global_position + (cursor.call(t) as Vector3)
		input.mouse_world_pos.y = 0.0
		c._process_input(input, DT)
		sk._physics_process(DT)
		sk._process(DT)
		c._pose.apply_head_tracking(DT)
		each.call(t)


func test_a_stroke_bows_the_shaft_both_ways_and_no_further_than_its_cap() -> void:
	var c: SkaterController = _make_carrier()
	var sk: Skater = c.skater
	var seen: Array[float] = [0.0, 0.0]
	_run(c, 300, func(t: int) -> Vector3: return Vector3(
			0.35 * sin(TAU * 2.0 * maxf(t - 60, 0) * DT), 0.0, -1.1), Vector2.ZERO,
			func(_t: int) -> void:
				seen[0] = minf(seen[0], sk.carry_bow_m())
				seen[1] = maxf(seen[1], sk.carry_bow_m()))
	assert_lt(seen[0], -0.5 * sk.carry_bow_max_m, "pushed one way, it bows that way")
	assert_gt(seen[1], 0.5 * sk.carry_bow_max_m, "and back the other")
	assert_gte(seen[0], -sk.carry_bow_max_m - 1e-6)
	assert_lte(seen[1], sk.carry_bow_max_m + 1e-6)


func test_a_still_carry_leaves_the_shaft_straight() -> void:
	var c: SkaterController = _make_carrier()
	_run(c, 200, func(_t: int) -> Vector3: return Vector3(0.0, 0.0, -1.0), Vector2.ZERO,
			func(_t: int) -> void: pass)
	assert_almost_eq(c.skater.carry_bow_m(), 0.0, 0.002)


func _settled_nod(cursor: Vector3, move: Vector2) -> float:
	var c: SkaterController = _make_carrier()
	_run(c, 240, func(_t: int) -> Vector3: return cursor, move, func(_t: int) -> void: pass)
	return rad_to_deg(c._pose.head_nod)


func test_the_head_comes_down_to_a_puck_in_tight() -> void:
	var out: float = _settled_nod(Vector3(0.0, 0.0, -1.1), Vector2.ZERO)
	var tight: float = _settled_nod(Vector3(0.0, 0.0, -0.45), Vector2.ZERO)
	assert_almost_eq(out, 0.0, 1.0, "a puck held out, still: eyes up")
	assert_gt(tight, 15.0, "in tight, the head is down on it")


# A client draws another player's carry from the replicated shot state alone and
# never sets has_puck on that player's controller.
func test_the_nod_reads_the_replicated_carry_not_the_controller_flag() -> void:
	var c: SkaterController = _make_carrier()
	_run(c, 240, func(_t: int) -> Vector3: return Vector3(0.0, 0.0, -0.45), Vector2.ZERO,
			func(_t: int) -> void: pass)
	c.has_puck = false
	for _i: int in 120:
		c._pose.apply_head_tracking(DT)
	assert_eq(c.skater.current_shot_state, SkaterStateMachine.State.SKATING_WITH_PUCK)
	assert_gt(rad_to_deg(c._pose.head_nod), 15.0)


func test_skating_puts_the_eyes_up() -> void:
	var standing: float = _settled_nod(Vector3(0.0, 0.0, -0.45), Vector2.ZERO)
	var skating: float = _settled_nod(Vector3(0.0, 0.0, -0.45), Vector2(0.0, -1.0))
	assert_lt(skating, standing * 0.5, "at speed the head comes up off the puck")
