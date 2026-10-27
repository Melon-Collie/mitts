extends GutTest

# AICarryRollout against the live controller: each move held for the horizon on
# a real SkaterController + Skater, the body integrated and held off the boards
# and the cage as Skater._physics_process does, must end where the rollout says
# it ends. That is what lets the carrier price a move on where it leaves him.
# Then the properties any honest rollout has.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
# The rollout runs the controller's own functions on the same numbers, so the
# two agree to float noise; a few millimetres is room for evaluation order.
const POS_TOL_M: float = 0.005
const VEL_TOL_M_S: float = 0.01
const FACING_TOL_RAD: float = 0.005


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _skater: Skater = null
var _controller: SkaterController = null
var _roll := AICarryRollout.new()


func before_all() -> void:
	_roll.step_ticks = 1


func before_each() -> void:
	var puck: Puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	add_child_autofree(puck)
	puck.global_position = Vector3(40.0, 0.0, 40.0)
	_skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(_skater)
	_skater.set_process(false)
	_skater.set_physics_process(false)
	var state := StubGameState.new()
	add_child_autofree(state)
	_controller = SkaterController.new()
	add_child_autofree(_controller)
	_controller.setup(_skater, puck, state)
	_controller.set_process(false)
	_controller.set_physics_process(false)


func _place(pos: Vector3, vel: Vector3, facing: Vector2) -> void:
	_skater.global_position = pos
	_skater.velocity = vel
	_controller._pose.facing = facing
	_controller._pose.facing_turn_rate = 0.0
	_skater.set_facing(facing)


# The live tick for a held move: the controller's input step, then the body's
# integration and containment. The stance is pressed by the read the agent skates
# a rolled move on, from the live velocity.
func _skate_live(move: int, upright_lateral_accel: float) -> void:
	var stance: bool = false
	for _i: int in AICarryRollout.TICKS:
		var input := InputState.new()
		input.brake = _roll.brake[move]
		input.move_vector = AIBotMechanics.braked_stick(_roll.stick[move], input.brake,
				_skater.velocity)
		stance = not input.brake and AISteering.stance_cuts_onto(input.move_vector,
				Vector2(_skater.velocity.x, _skater.velocity.z), upright_lateral_accel,
				AICarryRollout.STANCE_TURN_WINDOW_S, stance)
		input.stance_held = stance
		var c: Vector2 = _roll.cursor[move]
		input.mouse_world_pos = _skater.global_position + Vector3(c.x, 0.0, c.y) * 6.0
		input.mouse_world_pos.y = 0.0
		input.delta = DT
		_controller._process_input(input, DT)
		_skater.velocity.y = 0.0
		_skater.global_position += _skater.velocity * DT
		_skater.clamp_body_to_rink()
		_skater.clamp_body_to_net()


func _assert_matches_live(label: String, pos: Vector3, vel: Vector3, facing: Vector2,
		toward: Vector2) -> void:
	for carrying: bool in [false, true]:
		_assert_matches_live_carrying("%s%s" % [label, ", carrying" if carrying else ""],
				pos, vel, facing, toward, carrying)


func _assert_matches_live_carrying(label: String, pos: Vector3, vel: Vector3,
		facing: Vector2, toward: Vector2, carrying: bool) -> void:
	_controller.has_puck = carrying
	var caps: AISkaterCaps = _controller.build_ai_caps()
	_roll.roll_all(pos, vel, facing, toward, caps, carrying)
	for m: int in AICarryRollout.MOVE_COUNT:
		_place(pos, vel, facing)
		_skate_live(m, caps.movement.turn_accel * caps.movement.lateral_grip)
		var live_pos: Vector3 = _skater.global_position
		var tag: String = "%s, %s" % [label, AICarryRollout.Move.keys()[m]]
		assert_lt(Vector2(live_pos.x - _roll.end_pos[m].x, live_pos.z - _roll.end_pos[m].z)
				.length(), POS_TOL_M, "%s: position (live %s, rolled %s)"
				% [tag, live_pos, _roll.end_pos[m]])
		assert_lt((_skater.velocity - _roll.end_vel[m]).length(), VEL_TOL_M_S,
				"%s: velocity" % tag)
		assert_lt(absf(_skater.get_facing().angle_to(_roll.end_facing[m])), FACING_TOL_RAD,
				"%s: facing" % tag)


func test_from_rest_every_move_ends_where_the_controller_skates_it() -> void:
	_assert_matches_live("from rest", Vector3(0, 0, 5), Vector3.ZERO, Vector2(0, -1),
			Vector2(0, -1))


func test_in_stride_every_move_ends_where_the_controller_skates_it() -> void:
	_assert_matches_live("in stride", Vector3(0, 0, 5), Vector3(0, 0, -7), Vector2(0, -1),
			Vector2(0, -1))


func test_crossing_the_destination_line_every_move_matches() -> void:
	# Travelling across the line to the destination at speed, facing the travel:
	# every turn starts against momentum.
	_assert_matches_live("across", Vector3(-3, 0, 2), Vector3(6, 0, -2).normalized() * 6.5,
			Vector2(6, -2).normalized(), Vector2(-0.3, -1))


func test_skating_into_the_boards_every_move_matches() -> void:
	_assert_matches_live("at the boards", Vector3(11.8, 0, 0), Vector3(5, 0, -4),
			Vector2(5, -4).normalized(), Vector2(1, -0.2))


func test_skating_at_the_cage_every_move_matches() -> void:
	_assert_matches_live("at the cage", Vector3(0.3, 0, -24.5), Vector3(0, 0, -6),
			Vector2(0, -1), Vector2(0, -1))


# ── Properties ───────────────────────────────────────────────────────────────

func _caps() -> AISkaterCaps:
	return AISkaterCaps.new()


func test_the_last_sample_is_the_end() -> void:
	_roll.roll_all(Vector3(0, 0, 5), Vector3(0, 0, -5), Vector2(0, -1), Vector2(0, -1), _caps())
	for m: int in AICarryRollout.MOVE_COUNT:
		assert_eq(_roll.sample(m, AICarryRollout.SAMPLES - 1), _roll.end_pos[m])


func test_left_and_right_are_mirror_images() -> void:
	_roll.roll_all(Vector3(0, 0, 5), Vector3(0, 0, -6), Vector2(0, -1), Vector2(0, -1), _caps())
	var pairs: Array = [[AICarryRollout.Move.SOFT_LEFT, AICarryRollout.Move.SOFT_RIGHT],
			[AICarryRollout.Move.HARD_LEFT, AICarryRollout.Move.HARD_RIGHT]]
	for pair: Array in pairs:
		var a: Vector3 = _roll.end_pos[pair[0]]
		var b: Vector3 = _roll.end_pos[pair[1]]
		assert_almost_eq(a.x, -b.x, 1e-4)
		assert_almost_eq(a.z, b.z, 1e-4)
	assert_lt(_roll.end_pos[AICarryRollout.Move.HARD_LEFT].x, 0.0, "left is −X skating up −Z")


func test_straight_goes_furthest_toward_the_destination() -> void:
	_roll.roll_all(Vector3(0, 0, 5), Vector3(0, 0, -6), Vector2(0, -1), Vector2(0, -1), _caps())
	var best: float = 5.0 - _roll.end_pos[AICarryRollout.Move.STRAIGHT].z
	for m: int in AICarryRollout.MOVE_COUNT:
		assert_lte(5.0 - _roll.end_pos[m].z, best + 1e-4, AICarryRollout.Move.keys()[m])


func test_the_brake_stops_shorter_than_a_coast_would() -> void:
	_roll.roll_all(Vector3(0, 0, 5), Vector3(0, 0, -8), Vector2(0, -1), Vector2(0, -1), _caps())
	var stopped: Vector3 = _roll.end_vel[AICarryRollout.Move.BRAKE]
	assert_lt(stopped.length(), 8.0 - 3.0, "a hockey stop held over the horizon sheds several m/s")


func test_the_cut_back_skates_away_still_facing_the_destination() -> void:
	_roll.roll_all(Vector3(0, 0, 5), Vector3.ZERO, Vector2(0, -1), Vector2(0, -1), _caps())
	var m: int = AICarryRollout.Move.CUT_BACK
	assert_gt(_roll.end_pos[m].z, 5.0, "it backs away from the destination")
	assert_lt(absf(_roll.end_facing[m].angle_to(Vector2(0, -1))), 0.1, "facing it")


func test_no_move_leaves_the_rink() -> void:
	_roll.roll_all(Vector3(12.0, 0, 0), Vector3(8, 0, 0), Vector2(1, 0), Vector2(1, 0), _caps())
	for m: int in AICarryRollout.MOVE_COUNT:
		var p: Vector3 = _roll.end_pos[m]
		var xz := Vector2(p.x, p.z)
		assert_true(GameRules.clamp_to_rink_inner(xz, 0.34).is_equal_approx(xz)
				or GameRules.clamp_to_rink_inner(xz, 0.35).distance_to(xz) < 0.02,
				"%s stays on the ice" % AICarryRollout.Move.keys()[m])
	assert_true(_roll.touched_boundary[AICarryRollout.Move.STRAIGHT], "and says it met the boards")


func test_the_coarse_step_stays_within_a_hand_of_the_tick() -> void:
	var caps := AISkaterCaps.new()
	var coarse := AICarryRollout.new()
	assert_eq(coarse.step_ticks, AICarryRollout.STEP_TICKS)
	var starts: Array = [
		[Vector3(0, 0, 5), Vector3.ZERO, Vector2(0, -1), Vector2(0, -1)],
		[Vector3(0, 0, 5), Vector3(0, 0, -7), Vector2(0, -1), Vector2(0, -1)],
		[Vector3(0, 0, 0), Vector3(0, 0, -9), Vector2(0, -1), Vector2(1, 0.2)],
		[Vector3(0, 0, 0), Vector3(3, 0, -3), Vector2(0, -1), Vector2(-1, 1)],
		[Vector3(11.8, 0, 0), Vector3(5, 0, -4), Vector2(5, -4).normalized(), Vector2(1, -0.2)],
	]
	for s: Array in starts:
		_roll.roll_all(s[0], s[1], s[2], s[3], caps)
		coarse.roll_all(s[0], s[1], s[2], s[3], caps)
		for m: int in AICarryRollout.MOVE_COUNT:
			for k: int in AICarryRollout.SAMPLES:
				assert_lt(_roll.sample(m, k).distance_to(coarse.sample(m, k)), 0.25,
						"%s from %s, sample %d" % [AICarryRollout.Move.keys()[m], s[0], k])
			assert_lt(_roll.end_vel[m].distance_to(coarse.end_vel[m]), 0.5,
					"%s from %s, velocity" % [AICarryRollout.Move.keys()[m], s[0]])
