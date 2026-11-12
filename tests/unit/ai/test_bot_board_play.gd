extends GutTest

# The bots on the boards (SkaterAgentStateMachine.apply_board_play): a bot leaned
# on a man at the wall who has the puck puts the body into him only while holding
# him there is worth it — support that beats theirs, or its own end to kill the
# play, never as the last man back; a bot held there pushes back into the man and
# slides out along the wall; a carrier at the wall gets out of the line of an
# engaged checker when it can beat him there, and braces when it can't.

const Agent := preload("res://Scripts/ai/skater_agent_state_machine.gd")

const SELF_ID := 1
const MATE_ID := 2
const OPP_ID := 11
const OPP_MATE_ID := 12
var _team_map := {1: 0, 2: 0, 11: 1, 12: 1}
var _wall_x: float = GameRules.INNER_HALF_WIDTH - GameRules.OFFSIDE_LINE_SLACK - 0.05

var sm: SkaterAgentStateMachine


func before_each() -> void:
	sm = Agent.new()
	sm.setup(SELF_ID, 0, TeamBrain.new(0, _team_map), _team_map, false)


func _state(pos: Vector3) -> SkaterNetworkState:
	var s := SkaterNetworkState.new()
	s.position = pos
	return s


func _snap(puck_pos: Vector3) -> WorldSnapshot:
	var s := WorldSnapshot.new()
	s.puck_state = PuckNetworkState.new()
	s.puck_state.position = puck_pos
	s.puck_state.carrier_peer_id = -1
	return s


# ── Held ─────────────────────────────────────────────────────────────────────

# Us against the +x boards, an engaged OPP leaned on us from the open ice, a
# little behind us along the wall.
func _held_snap() -> WorldSnapshot:
	var s: WorldSnapshot = _snap(Vector3(0.0, 0.0, 10.0))
	s.skater_states[SELF_ID] = _state(Vector3(_wall_x, 0.0, 0.0))
	var opp: SkaterNetworkState = _state(Vector3(_wall_x - 0.7, 0.0, -0.1))
	opp.hit_committed = true
	s.skater_states[OPP_ID] = opp
	return s


func test_a_held_bot_pushes_back_and_slides_out_along_the_wall() -> void:
	var input := InputState.new()
	sm.apply_board_play(input, _held_snap())
	assert_true(input.hit_held, "the body into him")
	assert_lt(input.move_vector.x, -0.5, "back into the man, off the wall")
	assert_gt(input.move_vector.y, 0.5, "and out along it, away from him")


func test_a_held_bot_keeps_sliding_the_way_it_is_going() -> void:
	var s: WorldSnapshot = _held_snap()
	s.skater_states[SELF_ID].velocity = Vector3(0.0, 0.0, -1.0)
	var input := InputState.new()
	sm.apply_board_play(input, s)
	assert_lt(input.move_vector.y, -0.5)


func test_a_held_bot_lets_the_button_up_to_shove_again() -> void:
	var s: WorldSnapshot = _held_snap()
	var me: SkaterNetworkState = s.skater_states[SELF_ID]
	me.check_drive_phase = CheckDriveRules.Phase.SPENT
	me.check_drive_elapsed = 0.5 * CheckDriveRules.REARM_S
	var input := InputState.new()
	sm.apply_board_play(input, s)
	assert_true(input.hit_held, "the last drive has not re-armed")
	me.check_drive_elapsed = CheckDriveRules.REARM_S
	sm.apply_board_play(input, s)
	assert_false(input.hit_held, "up for the tick: the next press is a shove")
	assert_lt(input.move_vector.x, -0.5, "still pushing back")


func test_a_man_who_is_not_engaged_holds_nobody() -> void:
	var s: WorldSnapshot = _held_snap()
	s.skater_states[OPP_ID].hit_committed = false
	var input := InputState.new()
	sm.apply_board_play(input, s)
	assert_false(input.hit_held)
	assert_eq(input.move_vector, Vector2.ZERO)


func test_a_man_beside_us_along_the_wall_holds_nobody() -> void:
	var s: WorldSnapshot = _held_snap()
	s.skater_states[OPP_ID].position = Vector3(_wall_x, 0.0, -0.7)
	var input := InputState.new()
	sm.apply_board_play(input, s)
	assert_false(input.hit_held)


# ── Holding ──────────────────────────────────────────────────────────────────

# Us leaned on OPP, who carries against the +x boards in the neutral zone; MATE
# behind us (so we are not the last man back) and near the puck; OPP_MATE far
# from it.
func _holding_snap() -> WorldSnapshot:
	var s: WorldSnapshot = _snap(Vector3(_wall_x + 0.2, 0.0, 0.5))
	s.puck_state.carrier_peer_id = OPP_ID
	s.skater_states[OPP_ID] = _state(Vector3(_wall_x, 0.0, 0.0))
	s.skater_states[SELF_ID] = _state(Vector3(_wall_x - 0.7, 0.0, 0.0))
	s.skater_states[MATE_ID] = _state(Vector3(_wall_x - 4.0, 0.0, 3.0))
	s.skater_states[OPP_MATE_ID] = _state(Vector3(-_wall_x, 0.0, -20.0))
	return s


func test_a_bot_holds_a_carrier_on_the_wall_while_its_support_wins_the_puck() -> void:
	var input := InputState.new()
	sm.apply_board_play(input, _holding_snap())
	assert_true(input.hit_held, "the body into him")
	assert_false(input.brake)
	assert_gt(input.move_vector.x, 0.9, "driving him into the wall")


func test_the_hold_follows_him_along_the_wall() -> void:
	var s: WorldSnapshot = _holding_snap()
	s.skater_states[OPP_ID].position.z = 0.3
	var input := InputState.new()
	sm.apply_board_play(input, s)
	assert_gt(input.move_vector.y, 0.0)
	assert_gt(input.move_vector.x, 0.7)


func test_a_loose_puck_at_his_feet_is_held_for_too() -> void:
	var s: WorldSnapshot = _holding_snap()
	s.puck_state.carrier_peer_id = -1
	var input := InputState.new()
	sm.apply_board_play(input, s)
	assert_true(input.hit_held)
	s.puck_state.position = Vector3(0.0, 0.0, 10.0)
	input = InputState.new()
	sm.apply_board_play(input, s)
	assert_false(input.hit_held, "the puck is elsewhere: nothing to hold him for")


func test_a_bot_lets_go_when_their_support_gets_there_first() -> void:
	var s: WorldSnapshot = _holding_snap()
	s.skater_states[OPP_MATE_ID].position = Vector3(_wall_x - 1.0, 0.0, 1.0)
	s.skater_states[MATE_ID].position = Vector3(_wall_x - 4.0, 0.0, 12.0)
	var input := InputState.new()
	sm.apply_board_play(input, s)
	assert_false(input.hit_held, "the hold would hand them the puck")


func test_the_last_man_back_does_not_hold_outside_his_own_end() -> void:
	var s: WorldSnapshot = _holding_snap()
	s.skater_states[MATE_ID].position = Vector3(0.0, 0.0, -10.0)   # ahead of us
	var input := InputState.new()
	sm.apply_board_play(input, s)
	assert_false(input.hit_held)


func test_in_his_own_end_a_bot_holds_to_kill_the_play() -> void:
	var s: WorldSnapshot = _holding_snap()
	var deep: float = GameRules.BLUE_LINE_Z + 4.0     # team 0 defends +z
	for pid: int in s.skater_states:
		s.skater_states[pid].position.z += deep
	s.puck_state.position.z += deep
	s.skater_states[OPP_MATE_ID].position = Vector3(_wall_x - 1.0, 0.0, deep + 1.0)
	var input := InputState.new()
	sm.apply_board_play(input, s)
	assert_true(input.hit_held, "a whistle is worth more than the puck here")


func test_no_hold_from_beside_him_or_off_the_wall() -> void:
	var s: WorldSnapshot = _holding_snap()
	s.skater_states[SELF_ID].position = Vector3(_wall_x, 0.0, -0.7)
	var input := InputState.new()
	sm.apply_board_play(input, s)
	assert_false(input.hit_held, "beside him along the wall there is nothing to push him into")
	s = _holding_snap()
	for pid: int in [SELF_ID, OPP_ID]:
		s.skater_states[pid].position.x -= 3.0
	input = InputState.new()
	sm.apply_board_play(input, s)
	assert_false(input.hit_held, "open ice")


func test_the_beginner_tier_never_holds_a_man_or_fights_a_hold() -> void:
	sm._check_aggression = 0.0
	var input := InputState.new()
	sm.apply_board_play(input, _holding_snap())
	assert_false(input.hit_held)
	input = InputState.new()
	sm.apply_board_play(input, _held_snap())
	assert_false(input.hit_held)


# ── Bracing ──────────────────────────────────────────────────────────────────

func _carrier_snap(checker_vel: Vector3, engaged: bool) -> WorldSnapshot:
	var s: WorldSnapshot = _snap(Vector3(_wall_x, 0.0, -0.8))
	s.puck_state.carrier_peer_id = SELF_ID
	s.skater_states[SELF_ID] = _state(Vector3(_wall_x, 0.0, 0.0))
	var opp: SkaterNetworkState = _state(Vector3(_wall_x - 1.5, 0.0, 0.0))
	opp.velocity = checker_vel
	opp.hit_committed = engaged
	s.skater_states[OPP_ID] = opp
	sm._state = SkaterAgentStateMachine.State.CARRY
	return s


func test_a_carrier_caught_by_a_fast_square_drive_braces() -> void:
	var input := InputState.new()
	sm.apply_board_play(input, _carrier_snap(Vector3(4.0, 0.0, 0.0), true))
	assert_true(input.hit_held, "no time to get out")


func test_a_carrier_with_time_skates_out_of_a_slow_drive_instead() -> void:
	var input := InputState.new()
	sm.apply_board_play(input, _carrier_snap(Vector3(0.5, 0.0, 0.0), true))
	assert_false(input.hit_held, "bracing costs the legs; he doesn't pay it")
	assert_almost_eq(absf(input.move_vector.y), 1.0, 1e-5, "along the wall, out of the line")


func test_a_carrier_already_moving_along_the_wall_keeps_going_out_of_it() -> void:
	var s: WorldSnapshot = _carrier_snap(Vector3(4.0, 0.0, 0.0), true)
	s.skater_states[SELF_ID].velocity = Vector3(0.0, 0.0, 3.0)
	var input := InputState.new()
	sm.apply_board_play(input, s)
	assert_false(input.hit_held, "his speed along the wall beats the drive")
	assert_gt(input.move_vector.y, 0.9, "the way he was already going")


func test_no_brace_against_a_checker_who_is_not_engaged_or_a_glancing_one() -> void:
	var input := InputState.new()
	sm.apply_board_play(input, _carrier_snap(Vector3(4.0, 0.0, 0.0), false))
	assert_false(input.hit_held, "not engaged: a bump")
	var s: WorldSnapshot = _carrier_snap(Vector3(0.0, 0.0, 4.0), true)
	s.skater_states[OPP_ID].position = Vector3(_wall_x - 0.3, 0.0, -1.5)
	sm.apply_board_play(input, s)
	assert_false(input.hit_held, "running along the wall at him is not into it")


func test_the_beginner_tier_does_not_brace() -> void:
	sm._protects_the_puck = false
	var input := InputState.new()
	sm.apply_board_play(input, _carrier_snap(Vector3(4.0, 0.0, 0.0), true))
	assert_false(input.hit_held)
