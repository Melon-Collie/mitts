class_name SkaterAgentDiscipline
extends RefCounted

# One bot's last word on the Hit button, every physics tick after the passes
# that press it: the button comes up when the check it is about to land would
# be a foul (AIFoulRead). The carrier it reads is the snapshot's, which the
# host delays by the tier's reaction to a change of possession, so a slower
# tier finishes a check on a man who has already moved the puck and is called
# for it.

# AISkaterCaps.body_radius's default, for a man whose caps have not landed.
const _LEAGUE_BODY_RADIUS_M: float = 0.35

var _peer_id: int = -1
var _team_id: int = -1
var _team_id_by_peer: Dictionary = {}
var _caps_by_peer: Dictionary = {}
# The last man this bot saw lose the puck, and when (snapshot time).
var _seen_carrier_pid: int = -1
var _lost_puck_pid: int = -1
var _lost_puck_at: float = -INF


func setup(peer_id: int, team_id: int, team_id_by_peer: Dictionary,
		caps_by_peer: Dictionary) -> void:
	_peer_id = peer_id
	_team_id = team_id
	_team_id_by_peer = team_id_by_peer
	_caps_by_peer = caps_by_peer


func apply(input: InputState, snapshot: WorldSnapshot) -> void:
	if snapshot == null or snapshot.puck_state == null:
		return
	var carrier_pid: int = snapshot.puck_state.carrier_peer_id
	if carrier_pid != _seen_carrier_pid:
		if _seen_carrier_pid != -1:
			_lost_puck_pid = _seen_carrier_pid
			_lost_puck_at = snapshot.host_timestamp
		_seen_carrier_pid = carrier_pid
	if not snapshot.fouls_called or not input.hit_held:
		return
	var me: SkaterNetworkState = snapshot.skater_states.get(_peer_id)
	if me == null or SkaterStateMachine.state_has_puck(me.shot_state):
		return
	var caps: AISkaterCaps = _caps_by_peer.get(_peer_id)
	var weight: float = caps.weight if caps != null else 1.0
	for pid: int in snapshot.skater_states:
		if _team_id_by_peer.get(pid, _team_id) == _team_id:
			continue
		var man: SkaterNetworkState = snapshot.skater_states[pid]
		if man.is_ghost:
			continue
		var man_caps: AISkaterCaps = _caps_by_peer.get(pid)
		var since_lost: float = snapshot.host_timestamp - _lost_puck_at \
				if pid == _lost_puck_pid else INF
		if AIFoulRead.would_foul(me.position, me.velocity, weight, man,
				man_caps.body_radius if man_caps != null else _LEAGUE_BODY_RADIUS_M,
				pid == carrier_pid, since_lost, carrier_pid == -1,
				snapshot.puck_state.position, snapshot.puck_in_play):
			input.hit_held = false
			return
