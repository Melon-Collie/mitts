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


# `puck_at` is where the blade has the puck now; INF reads it as already where
# the target holds it.
func _safe(body: Vector3, vel: Vector3, facing: Vector2, target: Vector3,
		own: float = OWN, puck_at: Vector3 = Vector3.INF) -> Vector3:
	if not puck_at.is_finite():
		puck_at = _held(body, facing, target, FLOOR.x)
	return AINetObstacle.own_mouth_safe_blade_target(body, vel, facing, target, FLOOR, own,
			HORIZON_S, puck_at)


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
	for i: int in 12:
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


# ── The keep-out: a carrier's routes stay wide of our own posts ─────────────

func _depth(p: Vector3, own: float = OWN) -> float:
	return AINetObstacle.own_mouth_keep_out_depth(p, own)


func test_the_keep_out_is_a_carry_ring_off_the_mouth_and_round_the_post_behind_it() -> void:
	var k: float = AINetObstacle.OWN_MOUTH_KEEP_OUT_M
	var w: float = AINetObstacle.OWN_MOUTH_HALF_WIDTH_M
	assert_almost_eq(_depth(Vector3(0.0, 0.0, _line_z() - OWN * 1.0)), k, 1e-4, "in the crease")
	assert_almost_eq(_depth(Vector3(w + k, 0.0, _line_z() - OWN * 0.5)), 0.0, 1e-4,
			"a carry ring past the post, in front of the line")
	assert_almost_eq(_depth(Vector3(0.0, 0.0,
			_line_z() - OWN * (AINetObstacle.OWN_MOUTH_DEPTH_M + k))), 0.0, 1e-4,
			"a carry ring above the crease")
	assert_lte(_depth(Vector3(w + 0.3, 0.0, _line_z() + OWN * 0.3)), 0.0,
			"behind the line the cage shields the mouth: he may hug it")
	assert_gt(_depth(Vector3(w + 0.3, 0.0, _line_z() - OWN * 0.1)), 0.0,
			"coming out past the post tight to it")
	assert_lt(_depth(Vector3(0.0, 0.0, -_line_z() + OWN * 1.0)), 0.0, "never their mouth")


func test_a_route_hugging_our_post_enters_the_keep_out_and_a_wide_one_does_not() -> void:
	var behind := Vector3(2.0, 0.0, _line_z() + OWN * 1.6)
	var up_tight := Vector3(1.8, 0.0, _line_z() - OWN * 3.0)
	var up_wide := Vector3(5.0, 0.0, _line_z() - OWN * 3.0)
	assert_true(AINetObstacle.carry_path_enters_own_keep_out(behind, up_tight, OWN))
	assert_false(AINetObstacle.carry_path_enters_own_keep_out(behind, up_wide, OWN))
	assert_false(AINetObstacle.carry_path_enters_own_keep_out(
			Vector3(2.0, 0.0, -behind.z), Vector3(1.8, 0.0, -up_tight.z), OWN),
			"at their net it is no keep-out of ours")
	var inside := Vector3(1.5, 0.0, _line_z() - OWN * 1.0)
	assert_false(AINetObstacle.carry_path_enters_own_keep_out(inside, up_wide, OWN),
			"one already in it may skate out")


func test_a_carrier_round_our_cage_takes_the_waypoints_at_the_keep_out() -> void:
	var cases: Array = [
		[Vector3(-2.5, 0.0, _line_z() + OWN * 1.5), Vector3(4.0, 0.0, _line_z() - OWN * 6.0)],
		[Vector3(3.0, 0.0, _line_z() + OWN * 0.6), Vector3(-3.0, 0.0, _line_z() + OWN * 0.6)],
		[Vector3(-3.0, 0.0, _line_z() - OWN * 1.0), Vector3(3.0, 0.0, _line_z() - OWN * 1.0)],
	]
	for c: Array in cases:
		var from: Vector3 = c[0]
		var to: Vector3 = c[1]
		var wp: Vector3 = AIArrival.cage_waypoint(from, to, Vector3.ZERO, 8.0, 5.0, 1.0, OWN)
		assert_lte(_depth(wp), 1e-3, "%s -> %s: waypoint %s outside the keep-out" % [from, to, wp])
		var theirs: Vector3 = AIArrival.cage_waypoint(Vector3(from.x, 0.0, -from.z),
				Vector3(to.x, 0.0, -to.z), Vector3.ZERO, 8.0, 5.0, 1.0, OWN)
		assert_eq(theirs, AIArrival.cage_waypoint(Vector3(from.x, 0.0, -from.z),
				Vector3(to.x, 0.0, -to.z), Vector3.ZERO, 8.0, 5.0, 1.0),
				"round their cage the route is the usual one")


func test_a_walkout_from_behind_our_net_is_wide_of_our_posts() -> void:
	var ctx := RoleContext.new()
	ctx.own_goal_dir = OWN
	ctx.attacking_goal_pos = Vector3(0.0, 0.0, -_line_z())
	ctx.defending_goal_pos = Vector3(0.0, 0.0, _line_z())
	ctx.team_size = 3
	ctx.self_pos = Vector3(0.5, 0.0, _line_z() + OWN * 1.8)
	var ours := AICarrierDestinations.new()
	ours.fill(ctx)
	ctx.self_pos = Vector3(0.5, 0.0, -_line_z() - OWN * 1.8)
	var theirs := AICarrierDestinations.new()
	theirs.fill(ctx)
	for kind: int in [AICarrierDestinations.Kind.WALKOUT_LEFT,
			AICarrierDestinations.Kind.WALKOUT_RIGHT]:
		var spot: Vector3 = ours.spots[ours.kinds.find(kind)]
		assert_lte(_depth(spot), 1e-3, "ours at %s" % spot)
		var tight: Vector3 = theirs.spots[theirs.kinds.find(kind)]
		assert_almost_eq(absf(tight.x), GameRules.NET_HALF_WIDTH
				+ AICarrierDestinations.WALKOUT_POST_CLEARANCE_M, 1e-4,
				"behind their net he walks out tight to the post")


func test_a_rolled_move_ends_where_it_first_goes_deeper_into_the_keep_out() -> void:
	var roll := AICarryRollout.new()
	var from := Vector3(1.9, 0.0, _line_z() + OWN * 0.8)
	roll.roll_all(from, Vector3(-1.0, 0.0, -OWN * 5.0), Vector2(-0.2, -OWN).normalized(),
			Vector2(-0.4, -OWN).normalized(), AISkaterCaps.new(), true)
	var start: float = maxf(_depth(from), 0.0)
	var cut: int = 0
	for m: int in AICarryRollout.MOVE_COUNT:
		var reach: int = roll.reach_short_of_net(m, INF, from, OWN)
		for k: int in reach:
			assert_lte(_depth(roll.sample(m, k)), start + 1e-6, "move %d sample %d" % [m, k])
		if reach < AICarryRollout.SAMPLES:
			cut += 1
	assert_gt(cut, 0, "skating up past his post, some move cuts across the mouth")


# ── Where the puck is, and the way it goes ──────────────────────────────────

func test_a_puck_already_in_the_mouth_is_taken_out_whatever_the_target() -> void:
	var body := Vector3(1.8, 0.0, _line_z() - OWN * 0.3)
	var target := Vector3(3.5, 0.0, _line_z() - OWN * 1.0)
	var out: Vector3 = _safe(body, Vector3.ZERO, Vector2(1.0, 0.0), target, OWN,
			Vector3(0.8, 0.0, _line_z() - OWN * 0.6))
	assert_almost_eq(out.x, AINetObstacle.OWN_MOUTH_EXIT_HALF_WIDTH_M, 1e-4,
			"swept out wide of the post on his side")


func test_a_puck_taken_round_our_cage_goes_round_the_post_not_through_the_mouth() -> void:
	# Measured: behind our net at the back corner, the puck ridden round the
	# post onto the front of the line, the target behind the cage. Straight
	# there, the blade drags it along the front of the mouth and over the line.
	var body := Vector3(-1.23, 0.0, _line_z() + OWN * 1.48)
	var puck := Vector3(-1.37, 0.0, _line_z() - OWN * 0.22)
	var target := Vector3(-0.65, 0.0, _line_z() + OWN * 1.63)
	var out: Vector3 = _safe(body, Vector3.ZERO, Vector2(0.0, -OWN), target, OWN, puck)
	assert_almost_eq(out.x, -AINetObstacle.OWN_MOUTH_EXIT_HALF_WIDTH_M, 1e-4,
			"round the post on the puck's side")
	assert_almost_eq(out.z, target.z, 1e-4, "at the target's depth")
	var on: Vector3 = _safe(body, Vector3.ZERO, Vector2(0.0, -OWN), target, OWN, out)
	assert_eq(on, target, "and from there straight on behind the cage")


func test_a_carrier_behind_our_net_never_takes_the_puck_through_the_mouth() -> void:
	var me_pos := Vector3(-1.23, 0.0, _line_z() + OWN * 1.48)
	var facing := Vector2(-0.01, -OWN).normalized()
	var s: WorldSnapshot = _carrying_beside_our_goalie(me_pos, Vector3(1.9, 0.0, OWN * 3.1),
			facing, 0.0)
	var puck := Vector3(-1.37, 0.0, _line_z() - OWN * 0.22)
	s.puck_state.position = puck
	s.skater_states[SELF_ID].blade_contact_world = puck
	var agent := SkaterAgent.new()
	agent.setup(SELF_ID, 0, TeamBrain.new(0, _team_map), _team_map, false)
	for i: int in 20:
		var input: InputState = agent.tick(s, 1.0 / 90.0, float(i) / 90.0)
		var m: Vector3 = input.mouse_world_pos
		assert_false(AINetObstacle.carried_puck_in_own_mouth(m, Vector3.ZERO, OWN, 0.0),
				"tick %d: cursor at %s" % [i, m])
		# The blade follows the cursor; the puck rides it.
		s.skater_states[SELF_ID].blade_contact_world = m


func test_beside_our_goalie_the_puck_goes_on_the_far_side_of_him() -> void:
	var me_pos := Vector3(1.73, 0.0, _line_z() - OWN * 0.32)
	var facing := Vector2(0.03, OWN).normalized()
	var s: WorldSnapshot = _carrying_beside_our_goalie(me_pos, Vector3(1.3, 0.0, OWN * 2.0),
			facing, 0.3)
	var input: InputState = _tick_carrier(s)
	var goalie := Vector3(0.3, 0.0, _line_z() - OWN * 0.5)
	assert_gt(input.mouse_world_pos.distance_to(goalie), me_pos.distance_to(goalie),
			"the cursor is past him from our goalie: %s" % input.mouse_world_pos)
	_assert_held_clear(me_pos, facing, input.mouse_world_pos, "beside our goalie")


func test_a_puck_in_front_of_the_line_goes_out_in_front_of_it() -> void:
	# Measured: the carrier behind the line, the puck in front of it in the
	# mouth; sent out beside the net behind the line, the straight way there
	# crossed the line inside the post.
	var body := Vector3(-1.37, 0.0, _line_z() + OWN * 0.8)
	var puck := Vector3(-0.56, 0.0, _line_z() - OWN * 0.76)
	var target := Vector3(-0.8, 0.0, _line_z() + OWN * 0.3)
	var out: Vector3 = _safe(body, Vector3(0.0, 0.0, OWN * 4.0), Vector2(1.0, 0.0), target, OWN,
			puck)
	assert_gte((_line_z() - out.z) * OWN, AINetObstacle.OWN_MOUTH_EXIT_FRONT_M - 1e-4,
			"in front of the line: %s" % out)
	assert_gte(absf(out.x), AINetObstacle.OWN_MOUTH_HALF_WIDTH_M, "and wide of the mouth")


func test_a_release_through_our_own_mouth_is_refused_and_others_are_not() -> void:
	var line: float = _line_z()
	var at := Vector3(-0.34, 0.0, line - OWN * 0.66)
	# Measured: a feed behind the net to the partner, let go from in the crease.
	assert_true(AINetObstacle.release_into_own_net(at, Vector3(26.5, 0.0, OWN * 13.8).normalized(),
			OWN))
	assert_false(AINetObstacle.release_into_own_net(at, Vector3(1.0, 0.0, -OWN * 0.3).normalized(),
			OWN), "up and across the ice")
	assert_false(AINetObstacle.release_into_own_net(Vector3(3.0, 0.0, line - OWN * 1.0),
			Vector3(0.3, 0.0, OWN).normalized(), OWN), "down the boards side, wide of the post")
	assert_false(AINetObstacle.release_into_own_net(Vector3(-1.5, 0.0, line + OWN * 1.5),
			Vector3(1.0, 0.0, 0.0), OWN), "behind the cage: it meets the back of it")
	assert_false(AINetObstacle.release_into_own_net(Vector3(0.0, 0.0, -line + OWN * 1.0),
			Vector3(0.0, 0.0, -OWN), OWN), "at their net it is a shot")


func test_a_loose_puck_beside_our_post_is_come_to_round_the_keep_out() -> void:
	# Measured: from the corner at pace straight to a puck just behind our post,
	# the pickup carried it on across our goal line with the body.
	var puck := Vector3(1.3, 0.0, _line_z() + OWN * 0.2)
	var me := Vector3(5.0, 0.0, _line_z() - OWN * 3.0)
	var vel: Vector3 = (puck - me).normalized() * 5.0
	var s := WorldSnapshot.new()
	s.skater_states[SELF_ID] = _skater(me, vel, Vector2(vel.x, vel.z).normalized())
	s.skater_states[OPP_ID] = _skater(Vector3(-4.0, 0.0, 0.0), Vector3.ZERO, Vector2(0.0, OWN))
	s.puck_state = PuckNetworkState.new()
	s.puck_state.position = puck
	s.puck_state.carrier_peer_id = -1
	s.real_puck_carrier_peer_id = -1
	s.teammate_ids_by_team[0] = [SELF_ID]
	s.teammate_ids_by_team[1] = [OPP_ID]
	s.closest_to_puck_by_team[0] = SELF_ID
	s.closest_to_puck_by_team[1] = OPP_ID
	var agent := SkaterAgent.new()
	agent.setup(SELF_ID, 0, TeamBrain.new(0, _team_map), _team_map, false)
	var input: InputState = null
	for i: int in 3:
		input = agent.tick(s, 1.0 / 90.0, float(i) / 90.0)
	assert_eq(agent.get_state(), SkaterAgentStateMachine.State.CHASE_PUCK)
	var move := Vector3(input.move_vector.x, 0.0, input.move_vector.y)
	var straight: Vector3 = (puck - me).normalized()
	var wide: Vector3 = (AINetObstacle.own_post_side_waypoint(puck.x, OWN) - me).normalized()
	assert_gt(move.dot(wide), move.dot(straight),
			"steering for the wide way round: move %s, wide %s, straight %s" % [move, wide, straight])


func test_a_loose_puck_behind_our_post_is_not_come_to_down_the_middle() -> void:
	# Measured: from the slot at pace to a puck just behind our post, the chase
	# lined up on the crease top and came straight down at our net.
	var puck := Vector3(-1.3, 0.0, _line_z() + OWN * 0.2)
	var me := Vector3(0.3, 0.0, _line_z() - OWN * 6.0)
	var vel := Vector3(0.0, 0.0, OWN * 5.0)
	var s := WorldSnapshot.new()
	s.skater_states[SELF_ID] = _skater(me, vel, Vector2(0.0, OWN))
	s.skater_states[OPP_ID] = _skater(Vector3(4.0, 0.0, 0.0), Vector3.ZERO, Vector2(0.0, OWN))
	s.puck_state = PuckNetworkState.new()
	s.puck_state.position = puck
	s.puck_state.carrier_peer_id = -1
	s.real_puck_carrier_peer_id = -1
	s.teammate_ids_by_team[0] = [SELF_ID]
	s.teammate_ids_by_team[1] = [OPP_ID]
	s.closest_to_puck_by_team[0] = SELF_ID
	s.closest_to_puck_by_team[1] = OPP_ID
	var agent := SkaterAgent.new()
	agent.setup(SELF_ID, 0, TeamBrain.new(0, _team_map), _team_map, false)
	var input: InputState = null
	for i: int in 3:
		input = agent.tick(s, 1.0 / 90.0, float(i) / 90.0)
	assert_lt(input.move_vector.x, -0.3,
			"out toward the puck's post side, not down at the crease: %s" % input.move_vector)
