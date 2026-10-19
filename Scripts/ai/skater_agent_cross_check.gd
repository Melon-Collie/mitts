class_name SkaterAgentCrossCheck
extends RefCounted

# One bot's cross-check (AICrossCheckRead), every physics tick after dispatch and
# the other stick passes:
# - covering a man at our net who hides the release from our goalie, shove him
#   when the push would clear the sightline;
# - on a loose puck, shove the man in reach who beats us to it, when the push
#   turns the race;
# - screening their goalie, set against a defender who could shove us (the
#   stance: across the blades the edges hold twice as hard).
# A stick already busy — a lift, a tie, a pin reach, a block — throws nothing,
# and neither does a carrier (his Ctrl is the brace). Owns nothing between ticks;
# a press only throws from an idle phase, so it is sent only then.

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
# the tier's PACE physicality knob (0 never shoves); `sets_against_shoves` the
# cognition gate on the screener's answer.
func apply(input: InputState, snapshot: WorldSnapshot, own_goal_dir: float,
		locked_man_pid: int, check_aggression: float, sets_against_shoves: bool) -> void:
	if snapshot == null or snapshot.puck_state == null:
		return
	var me: SkaterNetworkState = snapshot.skater_states.get(_peer_id)
	if me == null or me.knockdown_timer > 0.0 or me.pin_role != BoardPinRules.Role.NONE \
			or snapshot.puck_state.carrier_peer_id == _peer_id:
		return
	if check_aggression > 0.0 and not input.stick_check_held and not input.block_held \
			and me.cross_check_phase == CrossCheckRules.Phase.IDLE \
			and (_clears_a_screen(snapshot, me, own_goal_dir, locked_man_pid)
					or _turns_a_race(snapshot, me)):
		input.hit_pressed = true
		return
	if sets_against_shoves:
		_set_against_a_shove(input, snapshot, me, own_goal_dir)


func _in_reach(me: SkaterNetworkState, man: SkaterNetworkState) -> bool:
	return CrossCheckRules.in_reach(me.position, me.facing, GameRules.OFFSIDE_LINE_SLACK,
			man.position, GameRules.OFFSIDE_LINE_SLACK)


func _push(me: SkaterNetworkState, man: SkaterNetworkState) -> Vector2:
	return Vector2(man.position.x - me.position.x, man.position.z - me.position.z).normalized()


func _dv(me: SkaterNetworkState, man: SkaterNetworkState, man_pid: int) -> float:
	var caps: AISkaterCaps = _caps_by_peer.get(_peer_id)
	return AICrossCheckRead.predicted_dv(caps.weight if caps != null else 1.0,
			AICrossCheckRead.man_thrust(caps), man, _caps_by_peer.get(man_pid), _push(me, man))


# The man we cover, at our net, hiding the release from our goalie, and the push
# would move him off the sightline.
func _clears_a_screen(snapshot: WorldSnapshot, me: SkaterNetworkState, own_goal_dir: float,
		man_pid: int) -> bool:
	if man_pid == -1 or man_pid == snapshot.puck_state.carrier_peer_id:
		return false
	var man: SkaterNetworkState = snapshot.skater_states.get(man_pid)
	var goalie: GoalieNetworkState = snapshot.goalie_states.get(_team_id)
	if man == null or goalie == null or man.is_ghost or man.pin_role != BoardPinRules.Role.NONE \
			or own_goal_dir * man.position.z < GameRules.BLUE_LINE_Z or not _in_reach(me, man):
		return false
	var dv: float = _dv(me, man, man_pid)
	return AICrossCheckRead.clears_screen(man.position, _push(me, man),
			AICrossCheckRead.displacement_m(dv,
					AICrossCheckRead.man_thrust(_caps_by_peer.get(man_pid))),
			Vector3(goalie.position_x, 0.0, goalie.position_z), snapshot.puck_state.position,
			_screen_cfg)


# A loose puck, and an opponent in reach who beats us to it and would not once
# shoved (his displaced body, carrying the push, on the stride the stagger
# leaves him, against our arrival).
func _turns_a_race(snapshot: WorldSnapshot, me: SkaterNetworkState) -> bool:
	var puck: PuckNetworkState = snapshot.puck_state
	if puck.carrier_peer_id != -1:
		return false
	var caps: AISkaterCaps = _caps_by_peer.get(_peer_id)
	var ours: float = AIArrival.time_to_arrive(me.position, puck.position, me.velocity,
			caps.max_speed if caps != null else GameRules.DEFAULT_SKATER_MAX_SPEED_M_S,
			AICrossCheckRead.man_thrust(caps))
	for pid: int in snapshot.skater_states:
		if _team_id_by_peer.get(pid, -1) == _team_id:
			continue
		var man: SkaterNetworkState = snapshot.skater_states[pid]
		if man.is_ghost or man.knockdown_timer > 0.0 \
				or man.pin_role != BoardPinRules.Role.NONE or not _in_reach(me, man):
			continue
		var man_caps: AISkaterCaps = _caps_by_peer.get(pid)
		var top: float = man_caps.max_speed if man_caps != null \
				else GameRules.DEFAULT_SKATER_MAX_SPEED_M_S
		var thrust: float = AICrossCheckRead.man_thrust(man_caps)
		var his_now: float = AIArrival.time_to_arrive(man.position, puck.position, man.velocity,
				top, thrust)
		var dir: Vector2 = _push(me, man)
		var dv: float = _dv(me, man, pid)
		var kick := Vector3(dir.x, 0.0, dir.y) * dv
		var his_after: float = AIArrival.time_to_arrive(
				man.position + kick * AICrossCheckRead.PUSHED_REACTION_S, puck.position,
				man.velocity + kick, top, AICrossCheckRead.staggered_thrust(dv, thrust))
		if AICrossCheckRead.takes_the_race(ours, his_now, his_after):
			return true
	return false


# Screening their goalie with an opponent in reach who has us in front of him and
# his stick free: load up, so a push across our blades meets doubled edges.
func _set_against_a_shove(input: InputState, snapshot: WorldSnapshot,
		me: SkaterNetworkState, own_goal_dir: float) -> void:
	if own_goal_dir * me.position.z > -GameRules.BLUE_LINE_Z or input.hit_held:
		return
	var their_goalie: GoalieNetworkState = snapshot.goalie_states.get(1 - _team_id)
	if their_goalie == null or not AICrossCheckRead.hides_release(me.position,
			Vector3(their_goalie.position_x, 0.0, their_goalie.position_z),
			snapshot.puck_state.position, _screen_cfg):
		return
	for pid: int in snapshot.skater_states:
		if _team_id_by_peer.get(pid, -1) == _team_id:
			continue
		var opp: SkaterNetworkState = snapshot.skater_states[pid]
		if opp.cross_check_phase == CrossCheckRules.Phase.IDLE and not opp.is_ghost \
				and _in_reach(opp, me):
			input.stance_held = true
			return
