class_name SkaterAgentBoardPlay
extends RefCounted

# One bot's board play, every physics tick after dispatch. A man is held on the
# boards by the press (BoardWallRules' squeeze), so all of it is the body:
# - leaned on a man at the wall who has the puck or stands over it, from his
#   open-ice side, where holding him is worth it (_worth_holding): put the body
#   into him (Ctrl, the stick toward him), which follows him along the wall too;
# - held there ourselves by an engaged opponent: push back into him and slide
#   out along the wall, which unloads the squeeze, shoving him each time the
#   legs have another drive in them;
# - carrying at the wall with an engaged checker coming square: get out of his
#   line along the wall if that beats him there, else brace (AIPinThreatRead).
# Owns nothing between ticks.

# How close a checker has to be before a carrier answers him.
const THREAT_RANGE_M: float = 2.5
# A loose puck this close to a man at the wall is his to play: the body on him
# is a battle for it.
const PUCK_AT_FEET_M: float = 1.5

var _peer_id: int = -1
var _team_id: int = -1
var _team_id_by_peer: Dictionary = {}
var _caps_by_peer: Dictionary = {}


func setup(peer_id: int, team_id: int, team_id_by_peer: Dictionary,
		caps_by_peer: Dictionary) -> void:
	_peer_id = peer_id
	_team_id = team_id
	_team_id_by_peer = team_id_by_peer
	_caps_by_peer = caps_by_peer


# `check_aggression` is the tier's PACE physicality knob (0 never holds a man
# or fights a hold); `answers_threats` is a carrier with the protects_the_puck
# gate open; `max_accel` this bot's own.
func apply(input: InputState, snapshot: WorldSnapshot, own_goal_dir: float,
		check_aggression: float, answers_threats: bool, max_accel: float) -> void:
	if snapshot == null or snapshot.puck_state == null:
		return
	var me: SkaterNetworkState = snapshot.skater_states.get(_peer_id)
	if me == null or me.knockdown_timer > 0.0 or me.is_ghost:
		return
	var carrying: bool = snapshot.puck_state.carrier_peer_id == _peer_id
	if (answers_threats if carrying else check_aggression > 0.0) \
			and _push_back(input, snapshot, me):
		return
	if not carrying and check_aggression > 0.0 and _hold_on_the_wall(input, snapshot, me,
			own_goal_dir):
		return
	if answers_threats:
		_answer_threat(input, snapshot, me, max_accel)


# An opponent against the boards with the puck on his stick or at his feet,
# leaned on from his open-ice side, square to the wall: put the body into him
# while holding him there is worth it.
func _hold_on_the_wall(input: InputState, snapshot: WorldSnapshot, me: SkaterNetworkState,
		own_goal_dir: float) -> bool:
	if input.block_held:
		return false
	var puck: PuckNetworkState = snapshot.puck_state
	for pid: int in snapshot.skater_states:
		if _team_id_by_peer.get(pid, -1) == _team_id:
			continue
		var man: SkaterNetworkState = snapshot.skater_states[pid]
		if man.is_ghost or man.knockdown_timer > 0.0 \
				or AIPressRead.gap_m(me.position, man.position) > AIPressRead.STEP_IN_M:
			continue
		var out: Vector2 = BoardWallRules.wall_normal(man.position, GameRules.OFFSIDE_LINE_SLACK,
				BoardWallRules.SQUEEZE_MARGIN_M)
		var to_man := Vector2(man.position.x - me.position.x,
				man.position.z - me.position.z).normalized()
		if out == Vector2.ZERO or to_man.dot(out) < BoardWallRules.BACKSTOP_MIN_INTO_WALL:
			continue
		var his_puck: bool = puck.carrier_peer_id == pid or (puck.carrier_peer_id == -1
				and puck.position.distance_to(man.position) <= PUCK_AT_FEET_M)
		if not his_puck or not _worth_holding(snapshot, me, pid, own_goal_dir):
			continue
		input.hit_held = true
		input.brake = false
		input.stance_held = false
		input.move_vector = to_man
		return true
	return false


# What is taught: hold a man on the wall while our support beats theirs to the
# puck, or in our own end to kill the play; never as the last skater back
# outside our own end.
func _worth_holding(snapshot: WorldSnapshot, me: SkaterNetworkState, man_pid: int,
		own_goal_dir: float) -> bool:
	var own_end: bool = own_goal_dir * me.position.z > GameRules.BLUE_LINE_Z
	if not own_end and _last_back(snapshot, me, own_goal_dir):
		return false
	var puck_pos: Vector3 = snapshot.puck_state.position
	var ours: float = _team_arrival_s(snapshot, puck_pos, _team_id, man_pid)
	var theirs: float = _team_arrival_s(snapshot, puck_pos,
			_team_id_by_peer.get(man_pid, -1), man_pid)
	return ours <= theirs or own_end


# No teammate stands between us and our own net.
func _last_back(snapshot: WorldSnapshot, me: SkaterNetworkState, own_goal_dir: float) -> bool:
	var net := Vector3(0.0, 0.0, own_goal_dir * GameRules.GOAL_LINE_Z)
	var mine: float = me.position.distance_to(net)
	for pid: int in snapshot.skater_states:
		if pid == _peer_id or _team_id_by_peer.get(pid, -1) != _team_id:
			continue
		if snapshot.skater_states[pid].position.distance_to(net) < mine:
			return false
	return true


# The soonest a skater of `team` (not us, not the held man) reaches `at` at top
# speed: the momentum-blind bound, the same for both sides.
func _team_arrival_s(snapshot: WorldSnapshot, at: Vector3, team: int, man_pid: int) -> float:
	var best: float = INF
	for pid: int in snapshot.skater_states:
		if pid == _peer_id or pid == man_pid or _team_id_by_peer.get(pid, -1) != team:
			continue
		var caps: AISkaterCaps = _caps_by_peer.get(pid)
		var top: float = caps.max_speed if caps != null else GameRules.DEFAULT_SKATER_MAX_SPEED_M_S
		best = minf(best, snapshot.skater_states[pid].position.distance_to(at) / maxf(top, 0.1))
	return best


# Against the boards with an engaged opponent leaned on us from the open ice,
# square to the wall: the body into him (Ctrl, which a carrier holds as the
# brace), skating back into him and out along the wall in equal parts. The push
# back is what lets the slide go.
func _push_back(input: InputState, snapshot: WorldSnapshot, me: SkaterNetworkState) -> bool:
	var out: Vector2 = BoardWallRules.wall_normal(me.position, GameRules.OFFSIDE_LINE_SLACK,
			BoardWallRules.SQUEEZE_MARGIN_M)
	if out == Vector2.ZERO or input.block_held:
		return false
	for pid: int in snapshot.skater_states:
		if _team_id_by_peer.get(pid, -1) == _team_id:
			continue
		var opp: SkaterNetworkState = snapshot.skater_states[pid]
		if opp.is_ghost or opp.knockdown_timer > 0.0 or not opp.hit_committed \
				or AIPressRead.gap_m(me.position, opp.position) > AIPressRead.STEP_IN_M:
			continue
		var to_me := Vector2(me.position.x - opp.position.x,
				me.position.z - opp.position.z).normalized()
		if to_me.dot(out) < BoardWallRules.BACKSTOP_MIN_INTO_WALL:
			continue
		var along := Vector2(-out.y, out.x)
		var slide: float = AIPinThreatRead.escape_sign(
				BoardWallRules.along_wall_offset(me.position, opp.position, out),
				Vector2(me.velocity.x, me.velocity.z).dot(along))
		# A spent drive re-arms with the button up (CheckDriveRules): let go
		# for the tick, and the next press is a fresh shove.
		input.hit_held = not (me.check_drive_phase == CheckDriveRules.Phase.SPENT
				and me.check_drive_elapsed >= CheckDriveRules.REARM_S - 1e-3)
		input.brake = false
		input.stance_held = false
		input.move_vector = (along * slide - to_me).normalized()
		return true
	return false


# The most urgent engaged opponent coming square into the boards we are
# against, answered: skate out of his line along the wall if that is done
# before he arrives, else brace. Nothing when there is none.
func _answer_threat(input: InputState, snapshot: WorldSnapshot,
		me: SkaterNetworkState, max_accel: float) -> void:
	var out: Vector2 = BoardWallRules.wall_normal(me.position, GameRules.OFFSIDE_LINE_SLACK,
			BoardWallRules.SQUEEZE_MARGIN_M)
	if out == Vector2.ZERO:
		return
	var threat: SkaterNetworkState = null
	var ttc: float = INF
	for pid: int in snapshot.skater_states:
		if _team_id_by_peer.get(pid, -1) == _team_id:
			continue
		var opp: SkaterNetworkState = snapshot.skater_states[pid]
		if not opp.hit_committed:
			continue
		var to_me := Vector2(me.position.x - opp.position.x, me.position.z - opp.position.z)
		var dist: float = to_me.length()
		if dist > THREAT_RANGE_M or dist < 1e-4 \
				or (to_me / dist).dot(out) < BoardWallRules.BACKSTOP_MIN_INTO_WALL:
			continue
		var t: float = AIPinThreatRead.time_to_contact(me.position, me.velocity,
				opp.position, opp.velocity)
		if threat == null or t < ttc:
			threat = opp
			ttc = t
	if threat == null:
		return
	var along := Vector2(-out.y, out.x)
	var offset: float = BoardWallRules.along_wall_offset(me.position, threat.position, out)
	var along_vel: float = Vector2(me.velocity.x, me.velocity.z).dot(along)
	var dir_sign: float = AIPinThreatRead.escape_sign(offset, along_vel)
	var escape_s: float = AIPinThreatRead.escape_time(offset, along_vel, max_accel,
			dir_sign)
	if AIPinThreatRead.answer(ttc, escape_s) == AIPinThreatRead.Answer.ESCAPE:
		input.move_vector = along * dir_sign
	else:
		input.hit_held = true
