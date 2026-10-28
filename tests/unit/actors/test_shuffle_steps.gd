extends GutTest

# The shuffle, measured on the live rig: Space and a key pressed quickly from a
# standstill is one step-together (ShuffleStepShaper, SkaterLocomotion
# ._shuffle_path). Each skate lifts once —
# the leading one out, the trailing one in after it — and a blade pointed along
# the facing cannot glide across the travel, so whichever skate is down holds
# its place on the ice while the body moves over it. What slip is left (about a
# fifth of the body's speed to the side, a sixth back) is the
# planted boot rolling with the splayed leg, the lean carrying the hips past it,
# and a few millimetres as the stance drops into the shuffle's sit at the start.
# Both are counted only while the body moves: the blade seat's own settle after
# a sideways move (SkaterLegRig) is not a step.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const LegBone = SkaterMeshBuilder.LegBone
const SETTLE_TICKS: int = 60
const PRESS_TICKS: int = 6
const AFTER_TICKS: int = 120
# A boot this far above where it stood is off the ice; this close, on it. Metres.
const LIFTED_M: float = 0.02
const DOWN_M: float = 0.006


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _skater: Skater = null
var _controller: SkaterController = null
var _shaper: ShuffleStepShaper = null


func before_each() -> void:
	var puck: Puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	add_child_autofree(puck)
	puck.global_position = Vector3(40.0, 0.0, 40.0)
	_skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(_skater)
	_skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 20.0)
	_skater.set_process(false)
	_skater.set_physics_process(false)
	var state := StubGameState.new()
	add_child_autofree(state)
	_controller = SkaterController.new()
	add_child_autofree(_controller)
	_controller.setup(_skater, puck, state)
	_controller.set_process(false)
	_controller.set_physics_process(false)
	_controller._pose.facing = Vector2(0.0, -1.0)
	_skater.set_facing(Vector2(0.0, -1.0))
	_shaper = ShuffleStepShaper.new()


func _step(stick: Vector2, brake: bool = true) -> void:
	var input := InputState.new()
	input.move_vector = stick
	input.brake = brake
	input.mouse_world_pos = _skater.global_position + Vector3(0.0, 0.0, -6.0)
	input.mouse_world_pos.y = 0.0
	input.delta = DT
	_shaper.shape(input, _skater.velocity, _controller.shuffle_step_distance,
			_controller.stop_decel)
	_controller._process_input(input, DT)
	_skater.global_position += _skater.velocity * DT
	_skater._process(DT)


func _boot(left: bool) -> Vector3:
	var body: Skeleton3D = _skater.mesh_root.get_node("BodyRig") as Skeleton3D
	return (_skater.mesh_root.transform * body.transform * body.get_bone_global_pose(
			SkaterBodySkeleton.LEG_BONE_OFFSET + (LegBone.FOOT_L if left else LegBone.FOOT_R))).origin


# One press toward `stick`: how many times each boot lifts, how fast a boot on
# the ice slides over it against the body's own speed, and how far the body went.
func _press(stick: Vector2, press_ticks: int = PRESS_TICKS) -> void:
	for _i: int in SETTLE_TICKS:
		_step(Vector2.ZERO)
	var start: Vector3 = _skater.global_position
	var rest: Array[float] = [_boot(true).y, _boot(false).y]
	var prev: Array[Vector3] = [_skater.global_transform * _boot(true),
			_skater.global_transform * _boot(false)]
	var up: Array[bool] = [false, false]
	var lifts: Array[int] = [0, 0]
	var slid: float = 0.0
	var carried: float = 0.0
	for i: int in press_ticks + AFTER_TICKS:
		_step(stick if i < press_ticks else Vector2.ZERO)
		var body_move: float = _skater.velocity.length() * DT
		for k: int in 2:
			var local: Vector3 = _boot(k == 0)
			var world: Vector3 = _skater.global_transform * local
			var height: float = local.y - rest[k]
			if body_move < 0.0005:
				prev[k] = world
				continue
			if not up[k] and height > LIFTED_M:
				up[k] = true
				lifts[k] += 1
			elif up[k] and height < DOWN_M:
				up[k] = false
			if height < DOWN_M:
				slid += Vector2(world.x - prev[k].x, world.z - prev[k].z).length()
				carried += body_move
			prev[k] = world
	var moved := Vector2(_skater.global_position.x - start.x, _skater.global_position.z - start.z)
	var slip: float = slid / maxf(carried, 0.001)
	gut.p("step %s: moved %.3f m, lifts L%d R%d, planted skates slide at %.0f%% of the body"
			% [stick, moved.length(), lifts[0], lifts[1], slip * 100.0])
	var steps: int = maxi(roundi(moved.length() / _controller.shuffle_step_distance), 1)
	assert_almost_eq(moved.length(), steps * _controller.shuffle_step_distance, 0.02,
			"whole steps' distance")
	assert_eq(lifts, [steps, steps] as Array[int], "each skate steps once a step")
	assert_lt(slip, 0.25, "the skate on the ice holds it")


func test_a_press_to_the_side_is_one_step_together() -> void:
	_press(Vector2(1.0, 0.0))


func test_a_press_to_the_other_side_is_one_step_together() -> void:
	_press(Vector2(-1.0, 0.0))


func test_a_press_back_is_one_step_together() -> void:
	_press(Vector2(0.0, 1.0))


# Held, the shuffle keeps stepping, any way, and closes its step when let go.
func test_a_held_shuffle_keeps_stepping() -> void:
	for stick: Vector2 in [Vector2(1.0, 0.0), Vector2(0.0, -1.0)]:
		before_each()
		_press(stick, 100)


# Without the brake a push from rest is skated, never stepped: the shuffle is
# Space's alone.
func test_an_unbraked_push_never_shuffles() -> void:
	for stick: Vector2 in [Vector2(1.0, 0.0), Vector2(-1.0, 0.0), Vector2(0.0, 1.0)]:
		before_each()
		for _i: int in SETTLE_TICKS:
			_step(Vector2.ZERO, false)
		var most: float = 0.0
		for _i: int in 60:
			_step(stick, false)
			most = maxf(most, _controller._skating.locomotion_mix().shuffle)
		gut.p("push %s unbraked: shuffle weight peaked at %.3f" % [stick, most])
		assert_lt(most, 0.01, "a push %s without the brake is no shuffle" % stick)
