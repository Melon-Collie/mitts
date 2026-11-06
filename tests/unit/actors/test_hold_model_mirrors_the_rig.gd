extends GutTest

# SkaterHoldModel measures the body from tick state (SkaterIKCoordinator.
# fill_hold_body), and the rig draws it from the frames and the trunk texture.
# They must be the same body, or the model judges a pose the drawing does not
# hold: a live carrier settled round the body, standing and skating, and at each
# the model's shoulders and jersey against the drawn ones, in UpperBody's frame.
#
# Up to where the trunk sits: the gait seats the hips on the blades under its
# crouch at render rate, which carries the drawn trunk 3-10 cm under the tick's
# (printed per cell). Past that offset they must agree, and the model given the
# drawn trunk (SkaterArmRig.fill_drawn_trunk) must draw the rig's own elbow.
# docs/held-hands-plan.md §5 and its phase 1 record.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const UpperBone = SkaterMeshBuilder.UpperBone
const SETTLE_TICKS: int = 120
const SKATE_WARMUP_TICKS: int = 180
const SKATE_START_Z: float = 26.0
const CELLS: Array[Vector2] = [Vector2(-120.0, 1.2), Vector2(-60.0, 1.0), Vector2(0.0, 1.2),
		Vector2(45.0, 1.0), Vector2(100.0, 1.3), Vector2(140.0, 1.1)]
# Points on the jersey, torso-local: round the chest and the waist.
const PROBES: Array[Vector3] = [Vector3(0.22, 0.13, 0.0), Vector3(-0.22, 0.13, 0.0),
		Vector3(0.0, 0.13, -0.17), Vector3(0.0, 0.13, 0.17), Vector3(0.21, -0.1, 0.0),
		Vector3(0.0, -0.1, -0.18)]


class GameStateStub:
	extends Node

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _skater: Skater
var _controller: SkaterController


func test_the_model_is_the_body_the_rig_draws_standing() -> void:
	var worst: Vector3 = _sweep(false)
	assert_lt(worst.x, 0.005, "shoulders within 5 mm, past the trunk's offset")
	assert_lt(worst.y, 0.005, "the jersey within 5 mm, past the trunk's offset")
	assert_lt(worst.z, 0.005, "on the drawn trunk, the drawn elbow within 5 mm")


func test_the_model_is_the_body_the_rig_draws_skating() -> void:
	# Skating, the drawn trunk also carries the stride's texture, which the tick
	# does not see, and the drawn elbow eases behind a hand the stride pumps
	# where the model solves it afresh.
	var worst: Vector3 = _sweep(true)
	assert_lt(worst.x, 0.01, "shoulders within 1 cm, past the trunk's offset")
	assert_lt(worst.y, 0.035, "the jersey within 3.5 cm, past the trunk's offset")
	assert_lt(worst.z, 0.03, "on the drawn trunk, the drawn elbow within 3 cm")


# The worst gap over the cells, past the trunk's offset: (shoulders, jersey,
# the model's elbow on the drawn trunk against the drawn elbow), metres.
func _sweep(skating: bool) -> Vector3:
	var worst := Vector3.ZERO
	var tick := SkaterHoldModel.Body.new()
	var drawn := SkaterHoldModel.Body.new()
	var report := SkaterHoldModel.Report.new()
	for cell: Vector2 in CELLS:
		_build(skating)
		var input := InputState.new()
		for _i: int in SETTLE_TICKS:
			_step(input, _aim(cell.x, cell.y), skating)
		_controller._ik.fill_hold_body(tick)
		_controller._ik.fill_hold_body(drawn)
		_skater.fill_drawn_trunk(drawn)
		var offset: Vector3 = (drawn.shoulders[0] + drawn.shoulders[1]
				- tick.shoulders[0] - tick.shoulders[1]) * 0.5
		var gap := Vector3.ZERO
		for arm: int in 2:
			gap.x = maxf(gap.x, (tick.shoulders[arm] + offset).distance_to(drawn.shoulders[arm]))
		for p: Vector3 in PROBES:
			gap.y = maxf(gap.y, (tick.torso * p + offset).distance_to(drawn.torso * p))
		var frame_inv: Transform3D = _skater.drawn_upper_body().affine_inverse()
		var skel: Skeleton3D = _skater._arms._skeleton
		var hand: Vector3 = frame_inv * skel.get_bone_global_pose(UpperBone.TOP_HAND).origin
		SkaterHoldModel.evaluate(drawn, hand, _skater.drawn_blade().origin, report)
		var drawn_elbow: Vector3 = frame_inv * skel.get_bone_global_pose(UpperBone.TOP_ELBOW).origin
		gap.z = report.top.elbow.distance_to(drawn_elbow)
		gut.p("%s %+4.0f° %.1f m: trunk offset %s mm; past it shoulders %.1f mm, jersey %.1f mm; elbow %.1f mm" % [
				"skating" if skating else "standing", cell.x, cell.y, offset * 1000.0,
				gap.x * 1000.0, gap.y * 1000.0, gap.z * 1000.0])
		worst = Vector3(maxf(worst.x, gap.x), maxf(worst.y, gap.y), maxf(worst.z, gap.z))
		_skater.get_parent().remove_child(_skater)
		_skater.queue_free()
	return worst


func _aim(deg: float, r: float) -> Vector3:
	var a: float = deg_to_rad(deg)
	var fh: float = signf(_skater.bottom_shoulder.position.x)
	return Vector3(sin(a) * r * fh, 0.0, -cos(a) * r)


func _build(skating: bool) -> void:
	_skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(_skater)
	_skater.set_process(false)
	_skater.set_physics_process(false)
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	puck.global_position = Vector3(20.0, 0.0, 20.0)
	var gs := GameStateStub.new()
	add_child_autofree(gs)
	_controller = SkaterController.new()
	add_child_autofree(_controller)
	_controller.setup(_skater, puck, gs)
	_controller.apply_attributes(PlayerAttributes.neutral())
	_controller.set_process(false)
	_controller.set_physics_process(false)
	_skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT,
			SKATE_START_Z if skating else 0.0)
	_skater._process(DT)
	puck.set_carrier(_skater)
	_controller.on_puck_picked_up_network()
	if skating:
		var input := InputState.new()
		for _i: int in SKATE_WARMUP_TICKS:
			_step(input, Vector3(0.0, 0.0, -1.2), true)


func _step(input: InputState, aim: Vector3, skating: bool) -> void:
	input.delta = DT
	input.host_timestamp += DT
	input.move_vector = Vector2(0.0, -1.0) if skating else Vector2.ZERO
	if not skating:
		_skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
		_skater.velocity = Vector3.ZERO
		_controller._pose.facing = Vector2(0.0, -1.0)
		_skater.set_facing(_controller._pose.facing)
	input.mouse_world_pos = _skater.global_position + _skater.global_transform.basis * aim
	input.mouse_world_pos.y = 0.0
	_skater.capture_prev_blade_contact()
	_controller._process_input(input, DT)
	_skater._physics_process(DT)
	_skater._process(DT)
