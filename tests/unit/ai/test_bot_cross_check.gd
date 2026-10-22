extends GutTest

# The bots' cross-check (SkaterAgentStateMachine.apply_cross_check): a coverer
# shoves the man he covers off our goalie's sightline when an aim would clear it,
# and aims it there on the cursor; a bot shoves the man who beats it to a loose
# puck when the push turns the race. Never while the stick is busy, from a
# rearming throw, as a carrier, or on the beginner tier. A screener's answer is
# the press's dig-in (test_bot_press.gd).

const Agent := preload("res://Scripts/ai/skater_agent_state_machine.gd")

const SELF_ID := 1
const MATE_ID := 2
const OPP_ID := 11
const OPP_MATE_ID := 12
var _team_map := {1: 0, 2: 0, 11: 1, 12: 1}
# Team 0 defends +z.
var _goal_z: float = GameRules.GOAL_LINE_Z

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
# little off the line, facing the boards, and we stand beside him facing him.
func _screen_snap() -> WorldSnapshot:
	var s := WorldSnapshot.new()
	s.puck_state = PuckNetworkState.new()
	s.puck_state.position = Vector3(0.0, 0.02, _goal_z - 10.0)
	s.puck_state.carrier_peer_id = OPP_MATE_ID
	s.skater_states[OPP_MATE_ID] = _state(s.puck_state.position, Vector2(0.0, 1.0))
	s.skater_states[OPP_ID] = _state(Vector3(0.2, 0.85, _goal_z - 3.0), Vector2(1.0, 0.0))
	s.skater_states[SELF_ID] = _state(Vector3(-0.55, 0.85, _goal_z - 3.0), Vector2(1.0, 0.0))
	s.goalie_states[0] = _goalie(_goal_z - 0.6)
	var cover := RoleDecision.new()
	cover.locked_man_pid = OPP_ID
	sm._cached_role_decision = cover
	return s


func test_a_coverer_shoves_a_screen_off_the_sightline() -> void:
	var input := InputState.new()
	sm.apply_cross_check(input, _screen_snap())
	assert_true(input.hit_held and input.stick_check_pressed, "the chord: Ctrl held, F pressed")


func test_the_shove_is_aimed_off_the_sightline_not_along_the_line_to_him() -> void:
	var s: WorldSnapshot = _screen_snap()
	# Goal-side of him on the diagonal: straight at him runs partly up the sightline.
	var me: SkaterNetworkState = s.skater_states[SELF_ID]
	me.position = Vector3(-0.45, 0.85, _goal_z - 2.6)
	me.facing = Vector2(0.65, -0.4).normalized()
	var input := InputState.new()
	sm.apply_cross_check(input, s)
	assert_true(input.stick_check_pressed)
	var aim := Vector2(input.mouse_world_pos.x - me.position.x,
			input.mouse_world_pos.z - me.position.z).normalized()
	assert_almost_eq(aim.angle_to(Vector2(1.0, 0.0)), 0.0, 1e-3,
			"square across the sightline, the way he already stands off it")


func test_no_shove_that_leaves_him_screening() -> void:
	var s: WorldSnapshot = _screen_snap()
	s.skater_states[OPP_ID].facing = Vector2(0.0, -1.0)   # side-on: the push meets his edges
	var input := InputState.new()
	sm.apply_cross_check(input, s)
	assert_false(input.stick_check_pressed)


func test_no_shove_with_the_stick_busy_rearming_or_on_the_beginner_tier() -> void:
	var input := InputState.new()
	input.stick_check_held = true
	sm.apply_cross_check(input, _screen_snap())
	assert_false(input.stick_check_pressed, "the stick is on a lift or a tie")
	input = InputState.new()
	var s: WorldSnapshot = _screen_snap()
	s.skater_states[SELF_ID].cross_check_phase = CrossCheckRules.Phase.REARM
	sm.apply_cross_check(input, s)
	assert_false(input.stick_check_pressed, "still rearming")
	sm._check_aggression = 0.0
	input = InputState.new()
	sm.apply_cross_check(input, _screen_snap())
	assert_false(input.stick_check_pressed, "no physicality on the beginner tier")


func test_a_loose_puck_race_the_shove_turns() -> void:
	var s := WorldSnapshot.new()
	s.puck_state = PuckNetworkState.new()
	s.puck_state.position = Vector3(3.0, 0.02, 0.0)
	s.puck_state.carrier_peer_id = -1
	# He is a step nearer the puck, facing along the push: it slides him off his line.
	s.skater_states[OPP_ID] = _state(Vector3(1.2, 0.85, 0.0), Vector2(0.0, 1.0))
	s.skater_states[SELF_ID] = _state(Vector3(1.2, 0.85, -0.75), Vector2(0.0, 1.0))
	var input := InputState.new()
	sm.apply_cross_check(input, s)
	assert_true(input.stick_check_pressed)
	s.puck_state.position = Vector3(1.2, 0.02, -6.0)   # behind us: we are there first
	input = InputState.new()
	sm.apply_cross_check(input, s)
	assert_false(input.stick_check_pressed)

