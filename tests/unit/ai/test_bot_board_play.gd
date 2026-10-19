extends GutTest

# The bots on the boards (SkaterAgentStateMachine.apply_board_play): a pinned bot
# slides along the wall and reverses when its pinner commits to following; a
# pinning bot holds the stick button only while the pin is worth it — support
# that beats theirs, or its own end to kill the play, never as the last man back —
# and mirrors the slide through the network lag; a bot driving a check that won't
# knock its man down reaches for the pin instead; a carrier at the wall gets out
# of the line of a checker reaching with his stick when it can beat him there,
# and braces when it can't.

const Agent := preload("res://Scripts/ai/skater_agent_state_machine.gd")
const Role = BoardPinRules.Role

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


# ── Pinned ───────────────────────────────────────────────────────────────────

func _pinned_snap() -> WorldSnapshot:
	var s: WorldSnapshot = _snap(Vector3(0.0, 0.0, 10.0))
	var me: SkaterNetworkState = _state(Vector3(_wall_x, 0.0, 0.0))
	me.pin_role = Role.PINNED
	me.pin_strength = 0.5
	s.skater_states[SELF_ID] = me
	s.skater_states[OPP_ID] = _state(Vector3(_wall_x - 0.7, 0.0, -0.1))
	return s


func test_a_pinned_bot_slides_along_the_wall_away_from_its_pinner() -> void:
	var s: WorldSnapshot = _pinned_snap()
	var input := InputState.new()
	sm.apply_board_play(input, s)
	assert_almost_eq(absf(input.move_vector.y), 1.0, 1e-5, "along the wall")
	assert_gt(input.move_vector.y, 0.0, "away from the pinner")


func test_a_pinned_bot_reverses_when_the_pinner_commits_to_following() -> void:
	var s: WorldSnapshot = _pinned_snap()
	var input := InputState.new()
	sm.apply_board_play(input, s)
	var first: float = input.move_vector.y
	s.skater_states[OPP_ID].velocity = Vector3(0.0, 0.0, signf(first) * 0.8)
	sm.apply_board_play(input, s)
	assert_eq(signf(input.move_vector.y), -signf(first), "the pinner bit: cut back")
	s.skater_states[OPP_ID].velocity = Vector3(0.0, 0.0, -signf(first) * 0.8)
	sm.apply_board_play(input, s)
	assert_eq(signf(input.move_vector.y), -signf(first),
			"a reversal lands before the next one")


# ── Pinning ──────────────────────────────────────────────────────────────────

# Us pinning OPP against the +x boards in the neutral zone; MATE behind us (so we
# are not the last man back) and near the puck; OPP_MATE far from it.
func _pinning_snap() -> WorldSnapshot:
	var s: WorldSnapshot = _snap(Vector3(_wall_x + 0.2, 0.0, 0.5))
	var man: SkaterNetworkState = _state(Vector3(_wall_x, 0.0, 0.0))
	man.pin_role = Role.PINNED
	s.skater_states[OPP_ID] = man
	var me: SkaterNetworkState = _state(Vector3(_wall_x - 0.7, 0.0, 0.0))
	me.pin_role = Role.PINNER
	s.skater_states[SELF_ID] = me
	s.skater_states[MATE_ID] = _state(Vector3(_wall_x - 4.0, 0.0, 3.0))
	s.skater_states[OPP_MATE_ID] = _state(Vector3(-_wall_x, 0.0, -20.0))
	return s


func test_a_bot_holds_the_pin_while_its_support_wins_the_puck() -> void:
	var input := InputState.new()
	sm.apply_board_play(input, _pinning_snap())
	assert_true(input.stick_check_held, "keeps the stick on him")
	assert_gt(input.move_vector.x, 0.5, "and keeps driving him into the wall")


func test_a_bot_lets_go_when_their_support_gets_there_first() -> void:
	var s: WorldSnapshot = _pinning_snap()
	s.skater_states[OPP_MATE_ID].position = Vector3(_wall_x - 1.0, 0.0, 1.0)
	s.skater_states[MATE_ID].position = Vector3(_wall_x - 4.0, 0.0, 12.0)
	var input := InputState.new()
	input.stick_check_held = true   # the dispatch was still holding the button
	sm.apply_board_play(input, s)
	assert_false(input.stick_check_held, "the pin would hand them the puck")


func test_the_last_man_back_does_not_pin_outside_his_own_end() -> void:
	var s: WorldSnapshot = _pinning_snap()
	s.skater_states[MATE_ID].position = Vector3(0.0, 0.0, -10.0)   # ahead of us
	var input := InputState.new()
	sm.apply_board_play(input, s)
	assert_false(input.stick_check_held)


func test_in_his_own_end_a_bot_pins_to_kill_the_play() -> void:
	var s: WorldSnapshot = _pinning_snap()
	var deep: float = GameRules.BLUE_LINE_Z + 4.0     # team 0 defends +z
	for pid: int in s.skater_states:
		s.skater_states[pid].position.z += deep
	s.puck_state.position.z += deep
	s.skater_states[OPP_MATE_ID].position = Vector3(_wall_x - 1.0, 0.0, deep + 1.0)
	var input := InputState.new()
	sm.apply_board_play(input, s)
	assert_true(input.stick_check_held, "a whistle is worth more than the puck here")


func test_the_beginner_tier_never_holds_a_pin() -> void:
	sm._check_aggression = 0.0
	var input := InputState.new()
	sm.apply_board_play(input, _pinning_snap())
	assert_false(input.stick_check_held)


func test_the_pinner_follows_a_slide_late() -> void:
	var s: WorldSnapshot = _pinning_snap()
	var input := InputState.new()
	sm.apply_board_play(input, s)
	assert_almost_eq(input.move_vector.y, 0.0, 0.05, "lined up: no slide")
	s.skater_states[OPP_ID].position.z = 0.4
	sm.apply_board_play(input, s)
	var first: float = input.move_vector.y
	assert_gt(first, 0.0, "he slides after the man")
	for _i: int in roundi(BoardPinRules.PIN_LAG_BUDGET_S * 120.0):
		sm.apply_board_play(input, s)
	assert_gt(input.move_vector.y, first, "but reads the full move only over the lag")


func test_the_pinner_matches_a_steady_slide() -> void:
	var s: WorldSnapshot = _pinning_snap()
	s.skater_states[OPP_ID].velocity = Vector3(0.0, 0.0, 1.0)
	var input := InputState.new()
	for _i: int in roundi(BoardPinRules.PIN_LAG_BUDGET_S * 4.0 * 120.0):
		sm.apply_board_play(input, s)
	assert_gt(input.move_vector.y, 0.5, "lined up but standing: goes with him")
	s.skater_states[SELF_ID].velocity = Vector3(0.0, 0.0, 1.0)
	sm.apply_board_play(input, s)
	assert_almost_eq(input.move_vector.y, 0.0, 0.05, "lined up and matched: holds it")


# ── Reaching for a pin ───────────────────────────────────────────────────────

# The dispatch driving a check at OPP against the +x boards, closing at `closing`
# from `gap` metres off touching; support as in _pinning_snap.
func _reach_snap(closing: float, gap: float) -> WorldSnapshot:
	var s: WorldSnapshot = _snap(Vector3(_wall_x + 0.2, 0.0, 0.5))
	s.skater_states[OPP_ID] = _state(Vector3(_wall_x, 0.0, 0.0))
	var me: SkaterNetworkState = _state(Vector3(_wall_x - AIPinThreatRead.TOUCHING_M - gap,
			0.0, 0.0))
	me.velocity = Vector3(closing, 0.0, 0.0)
	s.skater_states[SELF_ID] = me
	s.skater_states[MATE_ID] = _state(Vector3(_wall_x - 4.0, 0.0, 3.0))
	s.skater_states[OPP_MATE_ID] = _state(Vector3(-_wall_x, 0.0, -20.0))
	return s


func _checking() -> InputState:
	var input := InputState.new()
	input.hit_held = true
	return input


func test_a_slow_drive_at_a_man_on_the_wall_reaches_for_the_pin() -> void:
	var input: InputState = _checking()
	sm.apply_board_play(input, _reach_snap(1.5, 0.1))
	assert_true(input.stick_check_held, "the stick goes out")
	assert_true(input.stick_check_pressed, "from an idle stick")
	assert_false(input.hit_held, "the check and the pin are two buttons")


func test_a_drive_that_would_knock_him_down_stays_a_check() -> void:
	var input: InputState = _checking()
	sm.apply_board_play(input, _reach_snap(6.0, 0.1))
	assert_true(input.hit_held)
	assert_false(input.stick_check_held)


func test_no_reach_until_contact_is_near_or_while_he_is_braced() -> void:
	var input: InputState = _checking()
	sm.apply_board_play(input, _reach_snap(1.5, 1.5))
	assert_true(input.hit_held, "still out of reach: keep skating the check in")
	var s: WorldSnapshot = _reach_snap(1.5, 0.1)
	s.skater_states[OPP_ID].hit_committed = true
	input = _checking()
	sm.apply_board_play(input, s)
	assert_true(input.hit_held, "braced, he can be hit but not pinned")


func test_no_reach_where_the_pin_is_not_worth_it_or_without_a_check() -> void:
	var s: WorldSnapshot = _reach_snap(1.5, 0.1)
	s.skater_states[OPP_MATE_ID].position = Vector3(_wall_x - 1.0, 0.0, 1.0)
	s.skater_states[MATE_ID].position = Vector3(_wall_x - 4.0, 0.0, 12.0)
	var input: InputState = _checking()
	sm.apply_board_play(input, s)
	assert_true(input.hit_held, "their support gets there first")
	input = InputState.new()
	sm.apply_board_play(input, _reach_snap(1.5, 0.1))
	assert_false(input.stick_check_held, "not driving a check")


# ── Bracing ──────────────────────────────────────────────────────────────────

func _carrier_snap(checker_vel: Vector3, reaching: bool) -> WorldSnapshot:
	var s: WorldSnapshot = _snap(Vector3(_wall_x, 0.0, -0.8))
	s.puck_state.carrier_peer_id = SELF_ID
	s.skater_states[SELF_ID] = _state(Vector3(_wall_x, 0.0, 0.0))
	var opp: SkaterNetworkState = _state(Vector3(_wall_x - 1.5, 0.0, 0.0))
	opp.velocity = checker_vel
	opp.stick_check_phase = StickCheckRules.Phase.TIE if reaching \
			else StickCheckRules.Phase.IDLE
	s.skater_states[OPP_ID] = opp
	sm._state = SkaterAgentStateMachine.State.CARRY
	return s


func test_a_carrier_caught_by_a_fast_square_drive_braces() -> void:
	var input := InputState.new()
	sm.apply_board_play(input, _carrier_snap(Vector3(4.0, 0.0, 0.0), true))
	assert_true(input.hit_held, "no time to get out: braced, he can be hit but not pinned")


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


func test_no_brace_against_a_checker_without_his_stick_out_or_a_glancing_one() -> void:
	var input := InputState.new()
	sm.apply_board_play(input, _carrier_snap(Vector3(4.0, 0.0, 0.0), false))
	assert_false(input.hit_held, "no stick out: a hit, not a pin")
	var s: WorldSnapshot = _carrier_snap(Vector3(0.0, 0.0, 4.0), true)
	s.skater_states[OPP_ID].position = Vector3(_wall_x - 0.3, 0.0, -1.5)
	sm.apply_board_play(input, s)
	assert_false(input.hit_held, "running along the wall at him is not a pin")


func test_the_beginner_tier_does_not_brace() -> void:
	sm._protects_the_puck = false
	var input := InputState.new()
	sm.apply_board_play(input, _carrier_snap(Vector3(4.0, 0.0, 0.0), true))
	assert_false(input.hit_held)
