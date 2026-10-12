extends GutTest

# The bots on the boards (SkaterAgentStateMachine.apply_board_play): a pinned bot
# works along the wall away from the man holding it, and a bot with a man pinned
# keeps driving him in while a teammate can get to the puck.

const Agent := preload("res://Scripts/ai/skater_agent_state_machine.gd")

const SELF_ID := 1
const MATE_ID := 2
const OPP_ID := 11
var _team_map := {1: 0, 2: 0, 11: 1}
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


func test_a_pinned_bot_works_along_the_wall_away_from_its_checker() -> void:
	var s: WorldSnapshot = _snap(Vector3(0.0, 0.0, 10.0))
	var me: SkaterNetworkState = _state(Vector3(_wall_x, 0.0, 0.0))
	me.pin_timer = 0.1
	s.skater_states[SELF_ID] = me
	s.skater_states[OPP_ID] = _state(Vector3(_wall_x - 0.5, 0.0, -0.3))
	var input := InputState.new()
	sm.apply_board_play(input, s)
	assert_almost_eq(absf(input.move_vector.y), 1.0, 1e-5, "along the wall")
	assert_gt(input.move_vector.y, 0.0, "away from the checker")


func test_a_bot_holds_the_pin_while_a_teammate_can_get_to_the_puck() -> void:
	var s: WorldSnapshot = _snap(Vector3(_wall_x + 0.2, 0.0, 0.5))
	var man: SkaterNetworkState = _state(Vector3(_wall_x, 0.0, 0.0))
	man.pin_timer = 0.1
	s.skater_states[OPP_ID] = man
	s.skater_states[SELF_ID] = _state(Vector3(_wall_x - 0.7, 0.0, 0.0))
	s.skater_states[MATE_ID] = _state(Vector3(_wall_x - 6.0, 0.0, 3.0))
	var input := InputState.new()
	sm.apply_board_play(input, s)
	assert_true(input.hit_held, "keeps the commit")
	assert_gt(input.move_vector.x, 0.9, "and keeps driving him into the wall")


func test_no_support_means_no_pin_to_hold() -> void:
	var s: WorldSnapshot = _snap(Vector3(_wall_x + 0.2, 0.0, 0.5))
	var man: SkaterNetworkState = _state(Vector3(_wall_x, 0.0, 0.0))
	man.pin_timer = 0.1
	s.skater_states[OPP_ID] = man
	s.skater_states[SELF_ID] = _state(Vector3(_wall_x - 0.7, 0.0, 0.0))
	s.skater_states[MATE_ID] = _state(Vector3(-_wall_x, 0.0, -28.0))
	var input := InputState.new()
	sm.apply_board_play(input, s)
	assert_false(input.hit_held, "nobody can get there before the pin is up")


func test_the_beginner_tier_never_holds_a_pin() -> void:
	sm._check_aggression = 0.0
	var s: WorldSnapshot = _snap(Vector3(_wall_x + 0.2, 0.0, 0.5))
	var man: SkaterNetworkState = _state(Vector3(_wall_x, 0.0, 0.0))
	man.pin_timer = 0.1
	s.skater_states[OPP_ID] = man
	s.skater_states[SELF_ID] = _state(Vector3(_wall_x - 0.7, 0.0, 0.0))
	s.skater_states[MATE_ID] = _state(Vector3(_wall_x - 6.0, 0.0, 3.0))
	var input := InputState.new()
	sm.apply_board_play(input, s)
	assert_false(input.hit_held)
