class_name SkaterAgentPress
extends RefCounted

# One bot's press (AIPressRead), every physics tick after dispatch and the other
# body and stick passes:
# - covering a man at our net who hides the release from our goalie, leaned on
#   him: drive into him (Ctrl, the stick toward him) when the press moves him
#   off the sightline;
# - screening their goalie with an opponent on us: dig in (the brake in the
#   stance), the stop's edges anchored by the stance's base.
# A held tie keeps its stick through the press: the commit takes the stick off
# the ice, and the tie holds while the button does. Owns nothing between ticks.

var _peer_id: int = -1
var _team_id: int = -1
var _team_id_by_peer: Dictionary = {}
var _caps_by_peer: Dictionary = {}
var _screen_cfg := GoalieBehaviorRules.ScreenConfig.new()


func setup(peer_id: int, team_id: int, team_id_by_peer: Dictionary,
		caps_by_peer: Dictionary) -> void:
	_peer_id = peer_id
	_team_id = team_id
	_team_id_by_peer = team_id_by_peer
	_caps_by_peer = caps_by_peer


# `locked_man_pid` is the man our role covers (-1 for none); `check_aggression`
# the tier's PACE physicality knob (0 never presses); `digs_in` the cognition
# gate on the screener's answer. True when it took the body this tick.
func apply(input: InputState, snapshot: WorldSnapshot, own_goal_dir: float,
		locked_man_pid: int, check_aggression: float, digs_in: bool) -> bool:
	if snapshot == null or snapshot.puck_state == null:
		return false
	var me: SkaterNetworkState = snapshot.skater_states.get(_peer_id)
	if me == null or me.knockdown_timer > 0.0 or me.pin_role != BoardPinRules.Role.NONE \
			or me.is_ghost or snapshot.puck_state.carrier_peer_id == _peer_id \
			or input.block_held:
		return false
	if check_aggression > 0.0 and _press_the_screen(input, snapshot, me, own_goal_dir,
			locked_man_pid):
		return true
	return digs_in and _dig_in(input, snapshot, me, own_goal_dir)


# The man we cover, at our net, hiding the release from our goalie, leaned on:
# drive into him when the press moves him off the sightline in AIPressRead.READ_S.
func _press_the_screen(input: InputState, snapshot: WorldSnapshot, me: SkaterNetworkState,
		own_goal_dir: float, man_pid: int) -> bool:
	if man_pid == -1 or man_pid == snapshot.puck_state.carrier_peer_id:
		return false
	var man: SkaterNetworkState = snapshot.skater_states.get(man_pid)
	var goalie: GoalieNetworkState = snapshot.goalie_states.get(_team_id)
	if man == null or goalie == null or man.is_ghost or man.pin_role != BoardPinRules.Role.NONE \
			or own_goal_dir * man.position.z < GameRules.BLUE_LINE_Z \
			or AIPressRead.gap_m(me.position, man.position) > AIPressRead.STEP_IN_M:
		return false
	var goalie_pos := Vector3(goalie.position_x, 0.0, goalie.position_z)
	var n := Vector2(man.position.x - me.position.x, man.position.z - me.position.z).normalized()
	var moved: float = AIPressRead.displacement_m(me, _caps_by_peer.get(_peer_id), man,
			_caps_by_peer.get(man_pid))
	if not AIScreenRead.clears_screen(man.position, n, moved, goalie_pos,
			snapshot.puck_state.position, _screen_cfg):
		return false
	input.hit_held = true
	input.brake = false
	input.stance_held = false
	input.move_vector = n
	return true


# Screening their goalie, slow, with an opponent on us: brake in the stance.
func _dig_in(input: InputState, snapshot: WorldSnapshot, me: SkaterNetworkState,
		own_goal_dir: float) -> bool:
	if own_goal_dir * me.position.z > -GameRules.BLUE_LINE_Z or input.hit_held \
			or Vector2(me.velocity.x, me.velocity.z).length() > SkaterMovementRules.SHUFFLE_MAX_SPEED:
		return false
	var their_goalie: GoalieNetworkState = snapshot.goalie_states.get(1 - _team_id)
	if their_goalie == null or not AIScreenRead.hides_release(me.position,
			Vector3(their_goalie.position_x, 0.0, their_goalie.position_z),
			snapshot.puck_state.position, _screen_cfg):
		return false
	for pid: int in snapshot.skater_states:
		if _team_id_by_peer.get(pid, -1) == _team_id:
			continue
		var opp: SkaterNetworkState = snapshot.skater_states[pid]
		if not opp.is_ghost and AIPressRead.gap_m(me.position, opp.position) <= AIPressRead.STEP_IN_M:
			input.brake = true
			input.stance_held = true
			return true
	return false
