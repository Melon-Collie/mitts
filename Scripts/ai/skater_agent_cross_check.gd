class_name SkaterAgentCrossCheck
extends RefCounted

# One bot's cross-check (AICrossCheckRead), every physics tick after dispatch and
# the other stick passes:
# - covering a man at our net who hides the release from our goalie, shove him
#   off the sightline when an aim the chest can turn to clears it;
# - on a loose puck, shove the man in reach who beats us to it, away from it,
#   when an aim turns the race.
# A man we are leaned on is the press's (SkaterAgentPress), which runs first.
# The press is a human's chord, Ctrl held and the stick button pressed, with its
# aim on the cursor. A stick already
# busy — a lift, a tie, a pin reach, a block — throws nothing, and neither does a
# carrier (his Ctrl is the brace). Owns nothing between ticks; a press only
# throws from an idle phase, so it is sent only then.

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
# the tier's PACE physicality knob (0 never shoves).
func apply(input: InputState, snapshot: WorldSnapshot, own_goal_dir: float,
		locked_man_pid: int, check_aggression: float) -> void:
	if snapshot == null or snapshot.puck_state == null:
		return
	var me: SkaterNetworkState = snapshot.skater_states.get(_peer_id)
	if me == null or me.knockdown_timer > 0.0 or me.pin_role != BoardPinRules.Role.NONE \
			or snapshot.puck_state.carrier_peer_id == _peer_id:
		return
	var aim := Vector2.ZERO
	if check_aggression > 0.0 and not input.stick_check_held and not input.block_held \
			and me.cross_check_phase == CrossCheckRules.Phase.IDLE:
		aim = _screen_aim(snapshot, me, own_goal_dir, locked_man_pid)
		if aim == Vector2.ZERO:
			aim = _race_aim(snapshot, me)
	if aim != Vector2.ZERO:
		input.hit_held = true
		input.stick_check_pressed = true
		input.mouse_world_pos = me.position \
				+ Vector3(aim.x, 0.0, aim.y) * AIBotMechanics.CARRY_BLADE_AIM_FORWARD_M


# The aim `body`'s chest can turn to nearest `want` (unit XZ).
func _aim_toward(body: SkaterNetworkState, want: Vector2) -> Vector2:
	return CrossCheckRules.aim_dir(body.facing, want, AIBotMechanics.UPPER_BODY_MAX_TWIST_RAD)


# Where the two of them will be when the push lands, past the load: a shove
# thrown at a man in reach now reaches the man as he will be.
func _in_reach(me: SkaterNetworkState, man: SkaterNetworkState, aim: Vector2) -> bool:
	return CrossCheckRules.in_reach(me.position + me.velocity * CrossCheckRules.LOAD_S, aim,
			GameRules.OFFSIDE_LINE_SLACK, man.position + man.velocity * CrossCheckRules.LOAD_S,
			GameRules.OFFSIDE_LINE_SLACK)


# Whether any aim reaches him: the one turned straight at him is the nearest the
# shaft can come.
func _reachable(me: SkaterNetworkState, man: SkaterNetworkState) -> bool:
	return _in_reach(me, man, _aim_toward(me,
			Vector2(man.position.x - me.position.x, man.position.z - me.position.z)))


func _dv(man: SkaterNetworkState, man_pid: int, aim: Vector2) -> float:
	var caps: AISkaterCaps = _caps_by_peer.get(_peer_id)
	return AICrossCheckRead.predicted_dv(caps.weight if caps != null else 1.0,
			AICrossCheckRead.man_thrust(caps), man, _caps_by_peer.get(man_pid), aim)


# The man we cover, at our net, hiding the release from our goalie: the first
# aim off the sightline that moves him off it (ZERO for none).
func _screen_aim(snapshot: WorldSnapshot, me: SkaterNetworkState, own_goal_dir: float,
		man_pid: int) -> Vector2:
	if man_pid == -1 or man_pid == snapshot.puck_state.carrier_peer_id:
		return Vector2.ZERO
	var man: SkaterNetworkState = snapshot.skater_states.get(man_pid)
	var goalie: GoalieNetworkState = snapshot.goalie_states.get(_team_id)
	if man == null or goalie == null or man.is_ghost or man.pin_role != BoardPinRules.Role.NONE \
			or own_goal_dir * man.position.z < GameRules.BLUE_LINE_Z or not _reachable(me, man):
		return Vector2.ZERO
	var goalie_pos := Vector3(goalie.position_x, 0.0, goalie.position_z)
	var puck_pos: Vector3 = snapshot.puck_state.position
	if not AICrossCheckRead.hides_release(man.position, goalie_pos, puck_pos, _screen_cfg):
		return Vector2.ZERO
	var want: Vector2 = AICrossCheckRead.off_sightline_dir(man.position, goalie_pos, puck_pos)
	var thrust: float = AICrossCheckRead.man_thrust(_caps_by_peer.get(man_pid))
	for i: int in AICrossCheckRead.AIM_TRIES:
		var aim: Vector2 = _aim_toward(me, want.rotated(AICrossCheckRead.aim_turn(i)))
		if not _in_reach(me, man, aim):
			continue
		var moved: float = AICrossCheckRead.displacement_m(_dv(man, man_pid, aim), thrust)
		if AICrossCheckRead.clears_screen(man.position, aim, moved, goalie_pos, puck_pos,
				_screen_cfg):
			return aim
	return Vector2.ZERO


# A loose puck, and an opponent in reach who beats us to it: the first aim away
# from it that turns the race (his displaced body, carrying the push, on the
# stride the stagger leaves him, against our arrival), ZERO for none.
func _race_aim(snapshot: WorldSnapshot, me: SkaterNetworkState) -> Vector2:
	var puck: PuckNetworkState = snapshot.puck_state
	if puck.carrier_peer_id != -1:
		return Vector2.ZERO
	var caps: AISkaterCaps = _caps_by_peer.get(_peer_id)
	var ours: float = AIArrival.time_to_arrive(me.position, puck.position, me.velocity,
			caps.max_speed if caps != null else GameRules.DEFAULT_SKATER_MAX_SPEED_M_S,
			AICrossCheckRead.man_thrust(caps))
	for pid: int in snapshot.skater_states:
		if _team_id_by_peer.get(pid, -1) == _team_id:
			continue
		var man: SkaterNetworkState = snapshot.skater_states[pid]
		if man.is_ghost or man.knockdown_timer > 0.0 \
				or man.pin_role != BoardPinRules.Role.NONE or not _reachable(me, man):
			continue
		var man_caps: AISkaterCaps = _caps_by_peer.get(pid)
		var top: float = man_caps.max_speed if man_caps != null \
				else GameRules.DEFAULT_SKATER_MAX_SPEED_M_S
		var thrust: float = AICrossCheckRead.man_thrust(man_caps)
		var his_now: float = AIArrival.time_to_arrive(man.position, puck.position, man.velocity,
				top, thrust)
		if his_now >= ours:
			continue
		var want: Vector2 = Vector2(man.position.x - puck.position.x,
				man.position.z - puck.position.z).normalized()
		for i: int in AICrossCheckRead.AIM_TRIES:
			var aim: Vector2 = _aim_toward(me, want.rotated(AICrossCheckRead.aim_turn(i)))
			if not _in_reach(me, man, aim):
				continue
			var dv: float = _dv(man, pid, aim)
			var kick := Vector3(aim.x, 0.0, aim.y) * dv
			var his_after: float = AIArrival.time_to_arrive(
					man.position + kick * AICrossCheckRead.PUSHED_REACTION_S, puck.position,
					man.velocity + kick, top, AICrossCheckRead.staggered_thrust(dv, thrust))
			if AICrossCheckRead.takes_the_race(ours, his_now, his_after):
				return aim
	return Vector2.ZERO

