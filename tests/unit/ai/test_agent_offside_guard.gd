extends GutTest

# The offside brake is the LAST write to a bot's move (SkaterAgent.tick →
# apply_offside_guard), so nothing that moves the body after the dispatch — the
# board play here, the carrier's deke inside it — can carry a bot over the
# attacking blue line before the puck. Driven through the real tick.

# Team 0 attacks -Z, so its attacking blue line is at z = -BLUE_LINE_Z.
const SELF_ID := 1
const TEAMMATE_ID := 2
const PINNER_ID := 11
const LINE_Z: float = -GameRules.BLUE_LINE_Z
var _team_map := {SELF_ID: 0, TEAMMATE_ID: 0, PINNER_ID: 1}


func _agent() -> SkaterAgent:
	var agent := SkaterAgent.new()
	agent.setup(SELF_ID, 0, TeamBrain.new(0, _team_map), _team_map, false)
	return agent


func _skater(pos: Vector3, vel: Vector3 = Vector3.ZERO) -> SkaterNetworkState:
	var s := SkaterNetworkState.new()
	s.position = pos
	s.velocity = vel
	s.facing = Vector2(0.0, -1.0)
	s.blade_contact_world = pos + Vector3(0.0, 0.0, -1.0)
	return s


# Pinned on the +X wall a metre short of the line, skating at it, with the pinner
# on our own-end side, so the pinned slide runs along the wall straight at the
# line. The puck is loose at centre ice unless `puck_in`.
func _pinned_at_the_line(puck_in: bool) -> WorldSnapshot:
	var s := WorldSnapshot.new()
	var me: SkaterNetworkState = _skater(
			Vector3(GameRules.INNER_HALF_WIDTH - 0.4, 0.0, LINE_Z + 1.0),
			Vector3(0.0, 0.0, -4.0))
	me.pin_role = BoardPinRules.Role.PINNED
	s.skater_states[SELF_ID] = me
	s.skater_states[TEAMMATE_ID] = _skater(Vector3(-5.0, 0.0, 5.0))
	s.skater_states[PINNER_ID] = _skater(
			Vector3(GameRules.INNER_HALF_WIDTH - 1.2, 0.0, LINE_Z + 1.8))
	s.puck_state = PuckNetworkState.new()
	s.puck_state.position = Vector3(0.0, 0.0, LINE_Z - 6.0) if puck_in else Vector3.ZERO
	s.puck_state.carrier_peer_id = -1
	s.real_puck_carrier_peer_id = -1
	return s


func test_a_pinned_slide_does_not_carry_a_bot_offside() -> void:
	var input: InputState = _agent().tick(_pinned_at_the_line(false), 1.0 / 120.0, 0.0)
	assert_gte(input.move_vector.y, 0.0,
			"the slide toward the line is braked: got %s" % input.move_vector)


func test_the_same_slide_runs_once_the_puck_is_in() -> void:
	var input: InputState = _agent().tick(_pinned_at_the_line(true), 1.0 / 120.0, 0.0)
	assert_lt(input.move_vector.y, -0.5,
			"no offside to guard, so the pinned slide stands: got %s" % input.move_vector)


func test_a_carrier_holds_the_puck_out_while_a_teammate_owes_a_tag_up() -> void:
	# NHL delayed offside: the teammate is still in the zone, so carrying the puck
	# in is an immediate whistle whatever the carry decided.
	var s := WorldSnapshot.new()
	var me: SkaterNetworkState = _skater(Vector3(0.0, 0.0, LINE_Z + 1.5),
			Vector3(0.0, 0.0, -6.0))
	s.skater_states[SELF_ID] = me
	s.skater_states[TEAMMATE_ID] = _skater(Vector3(-4.0, 0.0, LINE_Z - 5.0))
	s.skater_states[PINNER_ID] = _skater(Vector3(6.0, 0.0, LINE_Z - 8.0))
	s.puck_state = PuckNetworkState.new()
	s.puck_state.position = me.blade_contact_world
	s.puck_state.carrier_peer_id = SELF_ID
	s.real_puck_carrier_peer_id = SELF_ID
	s.tag_up_peers[TEAMMATE_ID] = true
	s.teammate_ids_by_team[0] = [SELF_ID, TEAMMATE_ID]
	s.teammate_ids_by_team[1] = [PINNER_ID]
	var input: InputState = _agent().tick(s, 1.0 / 120.0, 0.0)
	assert_gte(input.move_vector.y, 0.0,
			"the carrier stops short of the line: got %s" % input.move_vector)
