extends GutTest

# The drawn body against the boards. Skater.clamp_body_to_rink holds the body's
# disc off them, and the drawn body reaches past that disc in two ways the boards
# must still stop: the balance lean carries the shoulders over the skates
# (BalanceRules.wall_held_tilt), and a knockdown lays the figure out on the ice
# (Skater.board_clearance_radius). Measured on the live rig, every bone of the
# drawn body against the boards' inner face, and held inside them, or to what
# the same body reaches standing there: his elbows wing past his disc, and
# nothing here moves them.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
# Frame-to-frame give: the arms settle a centimetre or two as the pose eases.
const SLACK_M: float = 0.03
const FACINGS: Array[Vector2] = [Vector2(1.0, 0.0), Vector2(0.0, -1.0), Vector2(-1.0, 0.0)]


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
	puck.global_position = Vector3(-20.0, 0.0, 20.0)
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


# Stands him with his disc's edge on the +X boards, facing `facing`.
func _against_the_side_boards(facing: Vector2) -> void:
	var x: float = GameRules.INNER_HALF_WIDTH - _skater.collision_radius()
	_controller.teleport_to(Vector3(x, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0), facing)


# One live tick, looking along `facing`: the controller, the move step and its
# board clamp, the render.
func _tick(input: InputState, facing: Vector2) -> void:
	input.mouse_world_pos = _skater.global_position + Vector3(facing.x, 0.0, facing.y) * 4.0
	input.mouse_world_pos.y = 0.0
	_controller._process_input(input, DT)
	_skater.global_position += _skater.velocity * DT
	_skater.clamp_body_to_rink()
	_skater._process(DT)


# How far (m) the drawn body's deepest bone is past the boards' inner face.
func _depth_past_the_boards() -> float:
	var body: Skeleton3D = _skater.mesh_root.get_node("BodyRig") as Skeleton3D
	var to_world: Transform3D = _skater.global_transform * _skater.mesh_root.transform \
			* body.transform
	var deepest: float = -INF
	for bone: int in body.get_bone_count():
		var at: Vector3 = to_world * body.get_bone_global_pose(bone).origin
		deepest = maxf(deepest, -GameRules.distance_to_rink_inner(Vector2(at.x, at.z)))
	return deepest


# The deepest the body goes over `ticks` ticks of `input`, standing at the boards.
func _deepest_over(facing: Vector2, input: InputState, ticks: int) -> float:
	var deepest: float = -INF
	for _i: int in ticks:
		_tick(input, facing)
		deepest = maxf(deepest, _depth_past_the_boards())
	return deepest


# The most a body may go past the boards: none, or what it already does standing.
func _bound(standing: float) -> float:
	return maxf(standing, 0.0) + SLACK_M


func _standing(facing: Vector2) -> float:
	before_each()
	_against_the_side_boards(facing)
	return _deepest_over(facing, InputState.new(), 90)


func test_driving_into_the_boards_leans_no_further_than_the_glass() -> void:
	for facing: Vector2 in FACINGS:
		var standing: float = _standing(facing)
		before_each()
		_against_the_side_boards(facing)
		var drive := InputState.new()
		drive.move_vector = Vector2(1.0, 0.0)
		var driving: float = _deepest_over(facing, drive, 90)
		gut.p("facing %s: standing %+.3f m past the boards, driving into them %+.3f m"
				% [str(facing), standing, driving])
		assert_lt(driving, _bound(standing),
				"facing %s: the lean carries him into the glass" % str(facing))


func test_a_body_knocked_down_at_the_boards_lies_beside_them() -> void:
	var ride: float = _controller.balance_ref_dv
	for facing: Vector2 in FACINGS:
		var standing: float = _standing(facing)
		for shove: Vector2 in [Vector2(-1.0, 0.0), Vector2(0.0, 1.0),
				Vector2(0.7071, 0.7071), Vector2(-0.7071, 0.7071)]:
			before_each()
			_against_the_side_boards(facing)
			_controller._on_body_check_received(Vector3(shove.x, 0.0, shove.y) * 1.7 * ride)
			if _controller.knockdown_timer <= 0.0:
				continue
			var input := InputState.new()
			var deepest: float = -INF
			var ticks: int = 0
			while _controller.knockdown_timer > 0.0 and ticks < 600:
				_tick(input, facing)
				deepest = maxf(deepest, _depth_past_the_boards())
				ticks += 1
			gut.p("facing %s, shoved %s: %+.3f m past the boards (standing %+.3f)"
					% [str(facing), str(shove), deepest, standing])
			assert_lt(deepest, _bound(standing),
					"facing %s, shoved %s: the fallen body lies in the boards"
					% [str(facing), str(shove)])
