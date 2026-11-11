extends GutTest

# A bot hunting a man to fight him (SkaterAgentStateMachine._hunt, the man set
# by FightHunts through AIController): it skates at him, faces him, and leaves a
# loose puck it would otherwise chase to the rest of the team.

const Agent := preload("res://Scripts/ai/skater_agent_state_machine.gd")

const SELF_ID := 1
const MAN_ID := 11
var _team_map := {1: 0, 2: 0, 11: 1, 12: 1}

var sm: SkaterAgentStateMachine


func before_each() -> void:
	sm = Agent.new()
	sm.setup(SELF_ID, 0, TeamBrain.new(0, _team_map), _team_map, false)


func _snap(me: Vector3, man: Vector3, puck: Vector3) -> WorldSnapshot:
	var s := WorldSnapshot.new()
	s.puck_state = PuckNetworkState.new()
	s.puck_state.position = puck
	s.puck_state.carrier_peer_id = -1
	s.real_puck_carrier_peer_id = -1
	for pair: Array in [[SELF_ID, me], [MAN_ID, man]]:
		var st := SkaterNetworkState.new()
		st.position = pair[1]
		s.skater_states[pair[0]] = st
	return s


func _off_puck(s: WorldSnapshot, me: Vector3) -> InputState:
	var input := InputState.new()
	sm._loose_elapsed_s = 10.0
	sm._state_off_puck(input, s, me, false)
	return input


func test_a_hunter_skates_at_the_man_and_faces_him() -> void:
	var me := Vector3(0.0, 0.0, 0.0)
	var man := Vector3(10.0, 0.0, 0.0)
	sm.set_hunt_peer(MAN_ID)
	var input: InputState = _off_puck(_snap(me, man, Vector3(-20.0, 0.0, 20.0)), me)
	assert_gt(input.move_vector.x, 0.5, "toward him")
	assert_gt(input.mouse_world_pos.x, me.x, "the cursor on him, so he faces him")


func test_a_hunter_leaves_the_loose_puck() -> void:
	var me := Vector3(0.0, 0.0, 0.0)
	var s: WorldSnapshot = _snap(me, Vector3(10.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0))
	assert_true(sm._should_chase_loose_puck(s, me), "a puck he would chase")
	sm.set_hunt_peer(MAN_ID)
	_off_puck(s, me)
	assert_eq(sm.get_state(), SkaterAgentStateMachine.State.OFF_PUCK)


func test_with_no_hunt_the_role_steers_as_before() -> void:
	var me := Vector3(0.0, 0.0, 0.0)
	var s: WorldSnapshot = _snap(me, Vector3(10.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0))
	_off_puck(s, me)
	assert_eq(sm.get_state(), SkaterAgentStateMachine.State.CHASE_PUCK)
