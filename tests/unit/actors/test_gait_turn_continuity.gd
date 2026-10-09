extends GutTest

# A turn's legs move continuously through the keyboard's hard reversals, upright
# and in the stance. Once the travel has come round to a held key the stick sits
# on alternate sides of it from tick to tick; a turning pose keyed to that side
# swapped its leading skate every frame (0.41–0.44 rad steps on a hip, measured),
# where the stroke itself never moves a joint more than ~0.1 rad a frame.

const DT: float = 1.0 / 120.0
const LegBone = SkaterMeshBuilder.LegBone
const PIVOTS: Array[int] = [LegBone.LEG_L, LegBone.SHIN_L, LegBone.LEG_R, LegBone.SHIN_R]
const MAX_STEP_RAD: float = 0.2
const UP := Vector2(0.0, -1.0)
const KEY_D := Vector2(1.0, 0.0)
const KEY_A := Vector2(-1.0, 0.0)
const KEY_WD := Vector2(0.70710678, -0.70710678)
const KEY_WA := Vector2(-0.70710678, -0.70710678)


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _skater: Skater = null
var _controller: SkaterController = null


func before_each() -> void:
	var puck: Puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	add_child_autofree(puck)
	puck.global_position = Vector3(400.0, 0.0, 400.0)
	_skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(_skater)
	_skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	_skater.set_process(false)
	_skater.set_physics_process(false)
	var state := StubGameState.new()
	add_child_autofree(state)
	_controller = SkaterController.new()
	add_child_autofree(_controller)
	_controller.setup(_skater, puck, state)
	_controller.set_process(false)
	_controller.set_physics_process(false)
	# Facing up-ice, as a spawn leaves it; from the default facing the cursor
	# ahead sits in the frozen wedge and the skater skates backward.
	_controller._pose.facing = UP
	_skater.set_facing(UP)


# Skates each [ticks, move, stance] segment with the cursor leading the travel,
# and returns the largest per-frame change of any leg pivot's euler angle.
func _worst_step(segments: Array) -> float:
	var input := InputState.new()
	var last: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	var worst: float = 0.0
	var tick: int = 0
	for seg: Array in segments:
		for _t: int in int(seg[0]):
			_step(input, seg[1], seg[2])
			tick += 1
			for k: int in PIVOTS.size():
				var e: Vector3 = _skater.leg_bone_euler(PIVOTS[k])
				if tick > 1:
					var d: Vector3 = (e - last[k]).abs()
					worst = maxf(worst, maxf(d.x, maxf(d.y, d.z)))
				last[k] = e
	return worst


func _step(input: InputState, move: Vector2, stance: bool) -> void:
	var v := Vector2(_skater.velocity.x, _skater.velocity.z)
	var travel: Vector2 = v.normalized() if v.length() > 0.5 else UP
	input.move_vector = move
	input.stance_held = stance
	input.mouse_world_pos = _skater.global_position + Vector3(travel.x, 0.0, travel.y) * 4.0
	input.mouse_world_pos.y = 0.0
	input.delta = DT
	_controller._process_input(input, DT)
	_skater._physics_process(DT)
	_skater._process(DT)


func test_stance_key_reversals_never_swap_the_legs() -> void:
	var worst: float = _worst_step([[200, UP, false], [90, KEY_D, true], [90, KEY_A, true],
			[90, KEY_D, true]])
	assert_lt(worst, MAX_STEP_RAD, "worst per-frame leg step %.3f rad" % worst)


func test_stance_diagonal_reversals_never_swap_the_legs() -> void:
	var worst: float = _worst_step([[200, UP, false], [60, KEY_WD, true], [60, KEY_WA, true],
			[60, KEY_WD, true]])
	assert_lt(worst, MAX_STEP_RAD, "worst per-frame leg step %.3f rad" % worst)


func test_upright_key_reversals_never_swap_the_legs() -> void:
	var worst: float = _worst_step([[200, UP, false], [90, KEY_D, false], [90, KEY_A, false],
			[90, KEY_D, false]])
	assert_lt(worst, MAX_STEP_RAD, "worst per-frame leg step %.3f rad" % worst)


func test_upright_diagonal_reversals_never_swap_the_legs() -> void:
	var worst: float = _worst_step([[200, UP, false], [60, KEY_WD, false], [60, KEY_WA, false],
			[60, KEY_WD, false]])
	assert_lt(worst, MAX_STEP_RAD, "worst per-frame leg step %.3f rad" % worst)


# The inside the legs are posed on is the way the travel curves: a right-hand
# turn is skated on the right.
func test_the_turn_inside_is_the_curve() -> void:
	var input := InputState.new()
	for _t: int in 200:
		_step(input, UP, false)
	for _t: int in 30:
		_step(input, KEY_D, true)
	var m: LocomotionRules.Mix = _controller._skating.locomotion_mix()
	assert_gt(m.tight, 0.3, "the stance turns on dug edges")
	assert_eq(m.side, 1.0, "turning right")
	for _t: int in 60:
		_step(input, KEY_A, true)
	assert_eq(_controller._skating.locomotion_mix().side, -1.0, "turning left")
