extends GutTest

# The bots on the boards (SkaterAgentStateMachine.apply_board_play): a pinned bot
# slides along the wall and reverses when its pinner commits to following; a
# pinning bot holds the commit only while the pin is worth it — support that
# beats theirs, or its own end to kill the play, never as the last man back — and
# mirrors the slide through the network lag; a carrier at the wall braces against
# a committed checker closing square.

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
	assert_true(input.hit_held, "keeps the commit")
	assert_gt(input.move_vector.x, 0.5, "and keeps driving him into the wall")


func test_a_bot_lets_go_when_their_support_gets_there_first() -> void:
	var s: WorldSnapshot = _pinning_snap()
	s.skater_states[OPP_MATE_ID].position = Vector3(_wall_x - 1.0, 0.0, 1.0)
	s.skater_states[MATE_ID].position = Vector3(_wall_x - 4.0, 0.0, 12.0)
	var input := InputState.new()
	input.hit_held = true   # the dispatch was still committed to a hit
	sm.apply_board_play(input, s)
	assert_false(input.hit_held, "the pin would hand them the puck")


func test_the_last_man_back_does_not_pin_outside_his_own_end() -> void:
	var s: WorldSnapshot = _pinning_snap()
	s.skater_states[MATE_ID].position = Vector3(0.0, 0.0, -10.0)   # ahead of us
	var input := InputState.new()
	sm.apply_board_play(input, s)
	assert_false(input.hit_held)


func test_in_his_own_end_a_bot_pins_to_kill_the_play() -> void:
	var s: WorldSnapshot = _pinning_snap()
	var deep: float = GameRules.BLUE_LINE_Z + 4.0     # team 0 defends +z
	for pid: int in s.skater_states:
		s.skater_states[pid].position.z += deep
	s.puck_state.position.z += deep
	s.skater_states[OPP_MATE_ID].position = Vector3(_wall_x - 1.0, 0.0, deep + 1.0)
	var input := InputState.new()
	sm.apply_board_play(input, s)
	assert_true(input.hit_held, "a whistle is worth more than the puck here")


func test_the_beginner_tier_never_holds_a_pin() -> void:
	sm._check_aggression = 0.0
	var input := InputState.new()
	sm.apply_board_play(input, _pinning_snap())
	assert_false(input.hit_held)


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


# ── Bracing ──────────────────────────────────────────────────────────────────

func _carrier_snap(checker_vel: Vector3, committed: bool) -> WorldSnapshot:
	var s: WorldSnapshot = _snap(Vector3(_wall_x, 0.0, -0.8))
	s.puck_state.carrier_peer_id = SELF_ID
	s.skater_states[SELF_ID] = _state(Vector3(_wall_x, 0.0, 0.0))
	var opp: SkaterNetworkState = _state(Vector3(_wall_x - 1.5, 0.0, 0.0))
	opp.velocity = checker_vel
	opp.hit_committed = committed
	s.skater_states[OPP_ID] = opp
	sm._state = SkaterAgentStateMachine.State.CARRY
	return s


func test_a_carrier_at_the_wall_braces_against_a_committed_checker_closing_square() -> void:
	var input := InputState.new()
	sm.apply_board_play(input, _carrier_snap(Vector3(4.0, 0.0, 0.0), true))
	assert_true(input.hit_held, "braced, he can be hit but not pinned")


func test_no_brace_against_an_uncommitted_or_glancing_checker() -> void:
	var input := InputState.new()
	sm.apply_board_play(input, _carrier_snap(Vector3(4.0, 0.0, 0.0), false))
	assert_false(input.hit_held, "not committed")
	var s: WorldSnapshot = _carrier_snap(Vector3(0.0, 0.0, 4.0), true)
	s.skater_states[OPP_ID].position = Vector3(_wall_x - 0.3, 0.0, -1.5)
	sm.apply_board_play(input, s)
	assert_false(input.hit_held, "running along the wall at him is not a pin")


func test_the_beginner_tier_does_not_brace() -> void:
	sm._protects_the_puck = false
	var input := InputState.new()
	sm.apply_board_play(input, _carrier_snap(Vector3(4.0, 0.0, 0.0), true))
	assert_false(input.hit_held)
