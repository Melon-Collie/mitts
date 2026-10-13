extends GutTest

# The bots' shot block (SkaterAgentShotBlock, through
# SkaterAgentStateMachine.apply_shot_block): a defender in a low shot's lane
# drops into the block and stays down while the released shot comes through;
# not for a shot over its seal, not on its goalie's doorstep, not on Easy. A
# 2-on-1's last defender dives across a pass lane he cannot reach on his feet.

const Agent := preload("res://Scripts/ai/skater_agent_state_machine.gd")
const State = SkaterStateMachine.State

const SELF_ID := 1
const MATE_ID := 2
const OPP_ID := 11
const OPP_MATE_ID := 12
var _team_map := {1: 0, 2: 0, 11: 1, 12: 1}

var sm: SkaterAgentStateMachine


func before_each() -> void:
	sm = Agent.new()
	sm.setup(SELF_ID, 0, TeamBrain.new(0, _team_map), _team_map, false)


func _state(pos: Vector3) -> SkaterNetworkState:
	var s := SkaterNetworkState.new()
	s.position = pos
	return s


# Team 0 defends +z. OPP winds up a wrister at z 12 with us 6 m out in his lane
# and our goalie at home.
func _shot_snap(me_pos: Vector3, elevation: int) -> WorldSnapshot:
	var s := WorldSnapshot.new()
	s.puck_state = PuckNetworkState.new()
	s.puck_state.position = Vector3(0.0, 0.0, 12.3)
	s.puck_state.carrier_peer_id = OPP_ID
	var shooter: SkaterNetworkState = _state(Vector3(0.0, 0.0, 12.0))
	shooter.shot_state = State.WRISTER_AIM
	shooter.elevation_level = elevation
	s.skater_states[OPP_ID] = shooter
	s.skater_states[SELF_ID] = _state(me_pos)
	var goalie := GoalieNetworkState.new()
	goalie.position_z = 25.5
	s.goalie_states[0] = goalie
	return s


func _block(s: WorldSnapshot) -> InputState:
	var input := InputState.new()
	sm.apply_shot_block(input, s)
	return input


func test_a_bot_in_a_low_shots_lane_blocks_it() -> void:
	var input: InputState = _block(_shot_snap(Vector3(0.3, 0.0, 18.0), ShotMechanics.ELEVATION_FLAT))
	assert_true(input.block_held)
	assert_false(input.stance_held, "a standing block, not a dive")


func test_out_of_the_lane_it_stays_up() -> void:
	assert_false(_block(_shot_snap(Vector3(3.0, 0.0, 18.0), ShotMechanics.ELEVATION_FLAT)).block_held)


func test_a_shot_going_over_it_is_left_to_the_goalie() -> void:
	var me := Vector3(0.0, 0.0, 24.0)
	var s: WorldSnapshot = _shot_snap(me, ShotMechanics.ELEVATION_HIGH)
	s.goalie_states[0].position_z = 26.4
	assert_false(_block(s).block_held, "12 m out the top rung is over the seal")
	s.skater_states[OPP_ID].elevation_level = ShotMechanics.ELEVATION_FLAT
	assert_true(_block(s).block_held, "the control: the same lane, flat")


func test_it_does_not_block_on_its_goalies_doorstep() -> void:
	assert_false(_block(_shot_snap(Vector3(0.0, 0.0, 24.8), ShotMechanics.ELEVATION_FLAT)).block_held)


func test_easy_never_blocks() -> void:
	sm.apply_profile(BotSkillProfile.easy())
	assert_false(_block(_shot_snap(Vector3(0.3, 0.0, 18.0), ShotMechanics.ELEVATION_FLAT)).block_held)


func test_it_stays_down_while_the_shot_comes_through() -> void:
	var s: WorldSnapshot = _shot_snap(Vector3(0.3, 0.0, 18.0), ShotMechanics.ELEVATION_FLAT)
	assert_true(_block(s).block_held)
	s.skater_states[OPP_ID].shot_state = State.FOLLOW_THROUGH
	s.puck_state.carrier_peer_id = -1
	s.puck_state.position = Vector3(0.0, 0.0, 14.0)
	s.puck_state.velocity = Vector3(0.0, 0.0, 30.0)
	assert_true(_block(s).block_held, "released, and on its way through us")
	s.puck_state.velocity = Vector3(0.0, 0.0, -30.0)
	assert_false(_block(s).block_held, "the puck went the other way: up again")


# ── The dive ────────────────────────────────────────────────────────────────

# A 2-on-1 into our end: OPP carries at (-3, 19), OPP_MATE is open at (4, 21),
# MATE is far up ice. Driven on the collaborator with a filled rush read.
func _rush_snap(me_pos: Vector3, carrier_z: float) -> WorldSnapshot:
	var s := WorldSnapshot.new()
	s.puck_state = PuckNetworkState.new()
	s.puck_state.position = Vector3(-3.0, 0.0, carrier_z + 0.5)
	s.puck_state.carrier_peer_id = OPP_ID
	s.skater_states[OPP_ID] = _state(Vector3(-3.0, 0.0, carrier_z))
	s.skater_states[OPP_MATE_ID] = _state(Vector3(4.0, 0.0, carrier_z + 2.0))
	s.skater_states[SELF_ID] = _state(me_pos)
	s.skater_states[MATE_ID] = _state(Vector3(0.0, 0.0, -10.0))
	return s


func _rush(numbers: int) -> AIRushRead:
	var r := AIRushRead.new()
	r.is_live = true
	r.numbers = numbers
	r.carrier_peer = OPP_ID
	r.attackers.append(OPP_ID)
	r.attackers.append(OPP_MATE_ID)
	return r


func _dive(s: WorldSnapshot, rush: AIRushRead) -> InputState:
	var b := SkaterAgentShotBlock.new()
	b.setup(SELF_ID, 0, _team_map, {})
	var input := InputState.new()
	b.apply(input, s, 1.0, rush, 1.5, 10.0)
	return input


func test_the_last_defender_dives_across_a_pass_he_cannot_reach() -> void:
	var input: InputState = _dive(_rush_snap(Vector3(0.5, 0.0, 17.0), 19.0),
			_rush(AIRushRead.Numbers.DOWN_ONE))
	assert_true(input.stance_held and input.block_held, "the dive chord")
	assert_gt(input.mouse_world_pos.z, 19.0, "laid out across the lane, toward it")


func test_no_dive_outside_shooting_range() -> void:
	var input: InputState = _dive(_rush_snap(Vector3(0.5, 0.0, 10.0), 12.0),
			_rush(AIRushRead.Numbers.DOWN_ONE))
	assert_false(input.block_held)


func test_no_dive_at_even_numbers() -> void:
	var input: InputState = _dive(_rush_snap(Vector3(0.5, 0.0, 17.0), 19.0),
			_rush(AIRushRead.Numbers.EVEN_OR_UP))
	assert_false(input.block_held)


func test_no_dive_when_a_teammate_is_nearer_the_lane() -> void:
	var s: WorldSnapshot = _rush_snap(Vector3(0.5, 0.0, 17.0), 19.0)
	s.skater_states[MATE_ID].position = Vector3(0.0, 0.0, 19.0)
	assert_false(_dive(s, _rush(AIRushRead.Numbers.DOWN_ONE)).block_held)


func test_a_downed_bot_does_nothing() -> void:
	var s: WorldSnapshot = _rush_snap(Vector3(0.5, 0.0, 17.0), 19.0)
	s.skater_states[SELF_ID].knockdown_timer = 0.5
	assert_false(_dive(s, _rush(AIRushRead.Numbers.DOWN_ONE)).block_held)
