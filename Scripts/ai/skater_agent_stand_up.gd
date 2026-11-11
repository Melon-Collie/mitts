class_name SkaterAgentStandUp
extends RefCounted

# One bot's timing of the Hit button, every physics tick after dispatch: a check
# the dispatch is hunting is thrown as the contact comes, and a carrier about to
# skate into the bot is met the same way (AIStandUpRead), so either contact lands
# inside the bot's drive (CheckDriveRules). Owns no state.

static var _check_cfg := BodyCheckRules.Config.new()

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


# `check_aggression` is the tier's PACE physicality knob (0 never meets him).
func apply(input: InputState, snapshot: WorldSnapshot, check_aggression: float) -> void:
	if check_aggression <= 0.0 or snapshot == null or snapshot.puck_state == null:
		return
	var carrier_pid: int = snapshot.puck_state.carrier_peer_id
	if carrier_pid == -1 or _team_id_by_peer.get(carrier_pid, _team_id) == _team_id:
		return
	var me: SkaterNetworkState = snapshot.skater_states.get(_peer_id)
	var man: SkaterNetworkState = snapshot.skater_states.get(carrier_pid)
	if me == null or man == null or me.pin_role != BoardPinRules.Role.NONE \
			or SkaterStateMachine.state_has_puck(me.shot_state):
		return
	if input.hit_held and AIPinThreatRead.time_to_contact(me.position, me.velocity,
			man.position, man.velocity) > AIStandUpRead.THROW_S:
		input.hit_held = false
	var caps: AISkaterCaps = _caps_by_peer.get(_peer_id)
	var man_caps: AISkaterCaps = _caps_by_peer.get(carrier_pid)
	if AIStandUpRead.meets(me.position, me.velocity, caps.weight if caps != null else 1.0,
			man.position, man.velocity, man_caps.weight if man_caps != null else 1.0,
			caps.body_check_transfer if caps != null else 0.65, _check_cfg.ref_impulse,
			caps.max_accel if caps != null else GameRules.DEFAULT_SKATER_THRUST_M_S2):
		input.hit_held = true
