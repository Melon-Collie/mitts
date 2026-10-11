extends GutTest

# A turn's legs move continuously through the keyboard's hard reversals, upright
# and in the stance. Once the travel has come round to a held key the stick sits
# on alternate sides of it from tick to tick; a turning pose keyed to that side
# swapped its leading skate every frame (0.41–0.44 rad steps on a hip, measured),
# where the stroke itself never moves a joint more than ~0.1 rad a frame. The
# same swap happened once wherever travel crossed the hips' lateral axis, which
# a joint bound is too coarse for, so that case is held on the skate's path.

const DT: float = 1.0 / 120.0
const LegBone = SkaterMeshBuilder.LegBone
const PIVOTS: Array[int] = [LegBone.LEG_L, LegBone.SHIN_L, LegBone.LEG_R, LegBone.SHIN_R]
const MAX_STEP_RAD: float = 0.2
# Largest change in a skate's per-frame travel (body-relative) between two
# frames. The swap measured 0.044 m; the stroke and every key press stay ≤ 0.031.
const MAX_SKATE_JERK_M: float = 0.025
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


# The user's repro: the cursor held straight ahead, the stance held, W → W+A → A
# → A+S. The hips turn toward the sideways travel; as A+S takes the momentum
# behind, they square back up and travel crosses their lateral axis.
func test_momentum_swinging_behind_the_hips_never_jumps_a_skate() -> void:
	var input := InputState.new()
	var segments: Array = [[120, UP], [60, KEY_WA], [60, KEY_A], [90, Vector2(-0.70710678, 0.70710678)]]
	var last: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	var moved: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	var worst: float = 0.0
	var tick: int = 0
	for seg: Array in segments:
		for _t: int in int(seg[0]):
			input.move_vector = seg[1]
			input.stance_held = true
			input.mouse_world_pos = _skater.global_position + Vector3(UP.x, 0.0, UP.y) * 6.0
			input.mouse_world_pos.y = 0.0
			input.delta = DT
			_controller._process_input(input, DT)
			_skater._physics_process(DT)
			_skater._process(DT)
			tick += 1
			for side: int in 2:
				var p: Vector3 = _skate_offset(side)
				var d: Vector3 = p - last[side]
				if tick > 3:
					worst = maxf(worst, (d - moved[side]).length())
				moved[side] = d
				last[side] = p
	assert_lt(worst, MAX_SKATE_JERK_M, "worst skate jerk %.3f m/frame" % worst)


func _skate_offset(side: int) -> Vector3:
	var sk: Skeleton3D = _skater._legs._skeleton
	var bone: int = LegBone.SKATE_L if side == 0 else LegBone.SKATE_R
	var t: Transform3D = sk.global_transform * sk.get_bone_global_pose(SkaterLegRig._OFFSET + bone)
	return t.origin - _skater.global_position


# The turning states lead along travel, so the lead is continuous in the hips'
# forward speed: just ahead of the lateral axis and just behind it pose alike.
func test_the_turning_lead_is_continuous_across_the_hips() -> void:
	var loco: SkaterLocomotion = _controller._skating._locomotion
	loco.mix.clear()
	loco.mix.tight = 0.5
	loco._tight_signed = -0.5
	loco.mix.carve = 0.4
	loco._carve_signed = 0.4
	loco._ground_speed = 5.0
	loco.strokes(DT, Vector2(0.0, 0.05))
	var ahead := Vector4(loco.l_dx, loco.l_dz, loco.r_dx, loco.r_dz)
	loco.strokes(DT, Vector2(0.0, -0.05))
	var behind := Vector4(loco.l_dx, loco.l_dz, loco.r_dx, loco.r_dz)
	for i: int in 4:
		assert_almost_eq(ahead[i], behind[i], 0.01, "channel %d" % i)
