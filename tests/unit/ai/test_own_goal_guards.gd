extends GutTest

# A bot never puts the puck in its own net on its own stick: the carried puck is
# kept out of our goal mouth (AINetObstacle.own_mouth_safe_blade_target), and a
# carrier or loose-puck chaser whose stop would run into our own crease brakes
# (AISteering.stops_in_own_crease). The agent cases are own goals measured in
# all-bot matches (tools/own_goal_hunt.gd), mirrored onto team 0: a defender
# who collected a rebound on his goal line at speed, facing his net, beside his
# goalie, and one who walked the puck out from behind his net past the post.
# Both had the cursor parked on the body by the goalie cradle, so the puck was
# where the carry's floor holds it, straight ahead of him.

# Team 0 defends +Z.
const OWN: float = 1.0
const SELF_ID := 1
const OPP_ID := 11
const HORIZON_S: float = 0.3
const FLOOR := Vector2(AISkaterCaps.LEAGUE_CARRY_REACH_MIN_M,
		AISkaterCaps.LEAGUE_CARRY_REACH_MIN_M + AISkaterCaps.LEAGUE_CARRY_REACH_FOLD_M)
var _team_map := {SELF_ID: 0, OPP_ID: 1}


func _line_z() -> float:
	return OWN * GameRules.GOAL_LINE_Z


func _safe(body: Vector3, vel: Vector3, facing: Vector2, target: Vector3,
		own: float = OWN) -> Vector3:
	return AINetObstacle.own_mouth_safe_blade_target(body, vel, facing, target, FLOOR, own,
			HORIZON_S)


# Where the carry holds a puck aimed at `target`, at either end of the floor.
func _held(body: Vector3, facing: Vector2, target: Vector3, floor_m: float) -> Vector3:
	var off: Vector2 = CarryPostureRules.held_out_along(
			Vector2(target.x - body.x, target.z - body.z), facing, floor_m)
	return Vector3(body.x + off.x, 0.0, body.z + off.y)


func _assert_held_clear(body: Vector3, facing: Vector2, target: Vector3, why: String) -> void:
	for floor_m: float in [FLOOR.x, FLOOR.y]:
		var held: Vector3 = _held(body, facing, target, floor_m)
		assert_false(AINetObstacle.carried_puck_in_own_mouth(held, Vector3.ZERO, OWN, 0.0),
				"%s: puck held at %s" % [why, held])


func test_held_out_along_is_held_out_in_any_frame() -> void:
	assert_eq(CarryPostureRules.held_out_along(Vector2(0.3, 0.4), Vector2(0.0, 1.0), 1.0),
			CarryPostureRules.held_out(Vector2(0.3, 0.4), 1.0))
	assert_eq(CarryPostureRules.held_out_along(Vector2(2.0, 0.0), Vector2(0.0, 1.0), 1.0),
			Vector2(2.0, 0.0))
	assert_eq(CarryPostureRules.held_out_along(Vector2.ZERO, Vector2(0.0, -1.0), 1.0),
			CarryPostureRules.held_out(Vector2.ZERO, 1.0),
			"on his centre, ahead: the facing frame's -y")
	assert_eq(CarryPostureRules.held_out_along(Vector2.ZERO, Vector2(1.0, 0.0), 1.0),
			Vector2(1.0, 0.0))


func test_a_puck_held_in_the_mouth_goes_out_wide_of_the_post() -> void:
	var body := Vector3(-0.2, 0.0, _line_z() - OWN * 1.8)
	var target := Vector3(-0.3, 0.0, _line_z() - OWN * 0.5)
	var out: Vector3 = _safe(body, Vector3.ZERO, Vector2(0.0, OWN), target)
	assert_almost_eq(out.x, -AINetObstacle.OWN_MOUTH_EXIT_HALF_WIDTH_M, 1e-4,
			"out on the body's side, wide of the cage frame")
	assert_almost_eq(out.z, target.z, 1e-4, "at its own depth: the floor is met there")
	_assert_held_clear(body, Vector2(0.0, OWN), out, "wide")


func test_a_puck_held_clear_of_the_mouth_is_untouched() -> void:
	var cases: Array[Vector3] = [
		Vector3(0.0, 0.0, _line_z() - OWN * 4.0),            # the slot
		Vector3(3.0, 0.0, _line_z() - OWN * 0.5),            # beside the crease
		Vector3(0.0, 0.0, _line_z() + OWN * 2.6),            # behind the net
		Vector3(0.0, 0.0, -_line_z() + OWN * 0.5),           # THEIR mouth
	]
	for target: Vector3 in cases:
		var body: Vector3 = target - Vector3(0.0, 0.0, 1.2 * OWN)
		assert_eq(_safe(body, Vector3.ZERO, Vector2(0.0, OWN), target), target,
				"untouched: %s" % target)


func test_a_cursor_parked_on_the_body_is_read_where_the_floor_holds_the_puck() -> void:
	# The cradle beside our goalie: the cursor on the body, the body facing the
	# net, so the puck is a floor ahead of him, in the mouth.
	var body := Vector3(-0.3, 0.0, _line_z() - OWN * 1.0)
	var out: Vector3 = _safe(body, Vector3.ZERO, Vector2(0.0, OWN), body)
	assert_ne(out, body, "moved")
	_assert_held_clear(body, Vector2(0.0, OWN), out, "cradled")


func test_walking_out_past_the_post_beside_the_goalie_keeps_the_puck_wide() -> void:
	# The measured own goal: out from behind the net, on the line at the post,
	# facing up the ice and across the mouth, the cursor on the body.
	var body := Vector3(-1.37, 0.0, _line_z() - OWN * 0.0)
	var facing := Vector2(0.62, -0.79 * OWN).normalized()
	var out: Vector3 = _safe(body, Vector3(-2.2, 0.0, -1.1 * OWN), facing, body)
	_assert_held_clear(body, facing, out, "at the post")
	assert_lt(out.x, 0.0, "his own side")


func test_a_target_the_body_drags_into_the_mouth_is_moved_before_it_gets_there() -> void:
	# Clear of the crease now, but at 7 m/s at the line the puck is in the mouth
	# before the blade could sweep it out.
	var body := Vector3(0.4, 0.0, _line_z() - OWN * 3.6)
	var target := Vector3(0.2, 0.0, _line_z() - OWN * 2.5)
	var out: Vector3 = _safe(body, Vector3(0.0, 0.0, OWN * 7.0), Vector2(0.0, OWN), target)
	assert_almost_eq(out.x, AINetObstacle.OWN_MOUTH_EXIT_HALF_WIDTH_M, 1e-4)
	assert_eq(_safe(body, Vector3.ZERO, Vector2(0.0, OWN), target), target,
			"standing, the same target is clear")


func test_the_guard_reads_both_ends() -> void:
	var body := Vector3(0.3, 0.0, -_line_z() + OWN * 1.5)
	var target := Vector3(0.1, 0.0, -_line_z() + OWN * 0.4)
	var out: Vector3 = _safe(body, Vector3.ZERO, Vector2(0.0, -OWN), target, -OWN)
	assert_almost_eq(out.x, AINetObstacle.OWN_MOUTH_EXIT_HALF_WIDTH_M, 1e-4,
			"the other team's own mouth")


func test_a_body_driving_at_our_crease_brakes_and_one_leaving_it_does_not() -> void:
	var at := Vector3(0.36, 0.0, _line_z() - OWN * 2.6)
	assert_true(AISteering.stops_in_own_crease(at, Vector2(-2.8, OWN * 7.5), OWN),
			"the measured chase: 8 m/s at the line")
	assert_false(AISteering.stops_in_own_crease(at, Vector2(0.0, OWN * 2.0), OWN),
			"slow enough for the repel")
	assert_false(AISteering.stops_in_own_crease(at, Vector2(0.0, -OWN * 7.0), OWN),
			"skating out")
	assert_false(AISteering.stops_in_own_crease(Vector3(8.0, 0.0, at.z),
			Vector2(0.0, OWN * 7.0), OWN), "down the wing, wide of the paint")
	assert_false(AISteering.stops_in_own_crease(
			Vector3(-3.0, 0.0, _line_z() + OWN * 1.5), Vector2(7.0, 0.0), OWN),
			"behind the net is the detour's")
	assert_false(AISteering.stops_in_own_crease(
			Vector3(0.36, 0.0, -at.z), Vector2(0.0, -OWN * 7.5), OWN),
			"their crease is not ours to brake for")


func _skater(pos: Vector3, vel: Vector3, facing: Vector2) -> SkaterNetworkState:
	var s := SkaterNetworkState.new()
	s.position = pos
	s.velocity = vel
	s.facing = facing
	s.blade_contact_world = pos + Vector3(facing.x, 0.0, facing.y)
	return s


# Our carrier at `pos` beside our goalie, the puck on his stick.
func _carrying_beside_our_goalie(pos: Vector3, vel: Vector3, facing: Vector2,
		goalie_x: float) -> WorldSnapshot:
	var s := WorldSnapshot.new()
	s.skater_states[SELF_ID] = _skater(pos, vel, facing)
	s.skater_states[OPP_ID] = _skater(Vector3(-1.5, 0.0, _line_z() - OWN * 6.0),
			Vector3.ZERO, Vector2(0.0, OWN))
	var goalie := GoalieNetworkState.new()
	goalie.position_x = goalie_x
	goalie.position_z = _line_z() - OWN * 0.5
	s.goalie_states[0] = goalie
	s.puck_state = PuckNetworkState.new()
	s.puck_state.position = pos + Vector3(facing.x, 0.0, facing.y)
	s.puck_state.carrier_peer_id = SELF_ID
	s.real_puck_carrier_peer_id = SELF_ID
	s.teammate_ids_by_team[0] = [SELF_ID]
	s.teammate_ids_by_team[1] = [OPP_ID]
	return s


func _tick_carrier(s: WorldSnapshot) -> InputState:
	var agent := SkaterAgent.new()
	agent.setup(SELF_ID, 0, TeamBrain.new(0, _team_map), _team_map, false)
	var input: InputState = null
	for i: int in 4:
		input = agent.tick(s, 1.0 / 90.0, float(i) / 90.0)
	assert_eq(agent.get_state(), SkaterAgentStateMachine.State.CARRY)
	return input


func test_a_defender_who_collects_a_rebound_on_his_line_keeps_it_out_of_his_net() -> void:
	var me_pos := Vector3(-0.3, 0.0, _line_z() - OWN * 1.0)
	var facing := Vector2(0.0, OWN)
	var input: InputState = _tick_carrier(_carrying_beside_our_goalie(me_pos,
			Vector3(-3.8, 0.0, OWN * 6.4), facing, 0.0))
	_assert_held_clear(me_pos, facing, input.mouse_world_pos, "on the line")
	assert_true(input.brake, "and he stops short of the paint")


func test_a_carrier_walking_out_past_his_post_keeps_it_out_of_his_net() -> void:
	var me_pos := Vector3(-1.37, 0.0, _line_z())
	var facing := Vector2(0.62, -0.79 * OWN).normalized()
	var input: InputState = _tick_carrier(_carrying_beside_our_goalie(me_pos,
			Vector3(-2.2, 0.0, -1.1 * OWN), facing, -0.9))
	_assert_held_clear(me_pos, facing, input.mouse_world_pos, "at the post")
