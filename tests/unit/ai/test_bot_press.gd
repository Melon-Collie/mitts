extends GutTest

# The bots' press (SkaterAgentStateMachine.apply_press): a coverer leaned on the
# man screening our goalie drives into him when the press moves him off the
# sightline; a screener with a defender on him digs in. Never from a step away,
# against a man who holds it, as a carrier, or on the beginner tier.

const Agent := preload("res://Scripts/ai/skater_agent_state_machine.gd")

const SELF_ID := 1
const MATE_ID := 2
const OPP_ID := 11
const OPP_MATE_ID := 12
var _team_map := {1: 0, 2: 0, 11: 1, 12: 1}
# Team 0 defends +z.
var _goal_z: float = GameRules.GOAL_LINE_Z
const TOUCHING_M: float = 2.0 * GameRules.OFFSIDE_LINE_SLACK

var sm: SkaterAgentStateMachine


func before_each() -> void:
	sm = Agent.new()
	sm.setup(SELF_ID, 0, TeamBrain.new(0, _team_map), _team_map, false)


func _state(pos: Vector3, facing: Vector2) -> SkaterNetworkState:
	var s := SkaterNetworkState.new()
	s.position = pos
	s.facing = facing
	return s


func _goalie(z: float) -> GoalieNetworkState:
	var g := GoalieNetworkState.new()
	g.position_x = 0.0
	g.position_z = z
	return g


# A point shot coming down the middle at our net; OPP screens our goalie a
# little off the line, facing the boards, and we are on his side, touching him.
func _screen_snap() -> WorldSnapshot:
	var s := WorldSnapshot.new()
	s.puck_state = PuckNetworkState.new()
	s.puck_state.position = Vector3(0.0, 0.02, _goal_z - 10.0)
	s.puck_state.carrier_peer_id = OPP_MATE_ID
	s.skater_states[OPP_MATE_ID] = _state(s.puck_state.position, Vector2(0.0, 1.0))
	s.skater_states[OPP_ID] = _state(Vector3(0.2, 0.85, _goal_z - 3.0), Vector2(1.0, 0.0))
	s.skater_states[SELF_ID] = _state(Vector3(0.2 - TOUCHING_M, 0.85, _goal_z - 3.0),
			Vector2(1.0, 0.0))
	s.goalie_states[0] = _goalie(_goal_z - 0.6)
	var cover := RoleDecision.new()
	cover.locked_man_pid = OPP_ID
	sm._cached_role_decision = cover
	return s


func test_a_coverer_leaned_on_a_screen_presses_him_off() -> void:
	var input := InputState.new()
	assert_true(sm.apply_press(input, _screen_snap()))
	assert_true(input.hit_held, "Ctrl: the drive")
	assert_almost_eq(input.move_vector.angle_to(Vector2(1.0, 0.0)), 0.0, 1e-3, "into him")


func test_no_press_against_a_man_who_holds_it() -> void:
	var s: WorldSnapshot = _screen_snap()
	var man: SkaterNetworkState = s.skater_states[OPP_ID]
	man.brake_intent = true
	man.stance_active = true
	var input := InputState.new()
	assert_false(sm.apply_press(input, s), "dug in, he does not move")
	assert_false(input.hit_held)


func test_no_press_from_a_step_away() -> void:
	var s: WorldSnapshot = _screen_snap()
	s.skater_states[SELF_ID].position.x -= AIPressRead.STEP_IN_M + 0.1
	assert_false(sm.apply_press(InputState.new(), s))


func test_no_press_on_the_beginner_tier() -> void:
	sm._check_aggression = 0.0
	assert_false(sm.apply_press(InputState.new(), _screen_snap()))


# Us in front of their goalie (they defend -z), a defender on our side.
func _screener_snap() -> WorldSnapshot:
	var s := WorldSnapshot.new()
	s.puck_state = PuckNetworkState.new()
	s.puck_state.position = Vector3(0.0, 0.02, -_goal_z + 10.0)
	s.puck_state.carrier_peer_id = MATE_ID
	s.skater_states[MATE_ID] = _state(s.puck_state.position, Vector2(0.0, -1.0))
	s.skater_states[SELF_ID] = _state(Vector3(0.0, 0.85, -_goal_z + 3.0), Vector2(0.0, 1.0))
	s.skater_states[OPP_ID] = _state(Vector3(-TOUCHING_M, 0.85, -_goal_z + 3.0), Vector2(1.0, 0.0))
	s.goalie_states[1] = _goalie(-_goal_z + 0.6)
	return s


func test_a_screener_with_a_defender_on_him_digs_in() -> void:
	var input := InputState.new()
	assert_true(sm.apply_press(input, _screener_snap()))
	assert_true(input.brake and input.stance_held, "the stop's edges, in the stance")
	sm._protects_the_puck = false
	input = InputState.new()
	assert_false(sm.apply_press(input, _screener_snap()), "the beginner tier does not read it")
	assert_false(input.brake)


func test_a_screener_on_the_move_does_not_dig_in() -> void:
	var s: WorldSnapshot = _screener_snap()
	s.skater_states[SELF_ID].velocity = Vector3(0.0, 0.0, 4.0)
	var input := InputState.new()
	assert_false(sm.apply_press(input, s), "at speed the brake is a stop, not an anchor")
