class_name SkaterAgentSkateKick
extends RefCounted

# One bot about to take a loose puck in its skates (AISkateKickRead), every
# physics tick after dispatch: the brake held as it arrives, so the skate kicks
# it to the stick. Owns no state but its scratch.

var _peer_id: int = -1
var _team_id: int = -1
var _contact := SkateContactRules.Contact.new()


func setup(peer_id: int, team_id: int) -> void:
	_peer_id = peer_id
	_team_id = team_id


# `opponent_ids` is the other team's peer ids (the roster cache).
func apply(input: InputState, snapshot: WorldSnapshot, opponent_ids: Array) -> void:
	if snapshot == null or snapshot.puck_state == null \
			or snapshot.real_puck_carrier_peer_id != -1:
		return
	var me: SkaterNetworkState = snapshot.skater_states.get(_peer_id)
	if me == null or me.is_ghost or me.diving or me.knockdown_timer > 0.0:
		return
	var puck: PuckNetworkState = snapshot.puck_state
	# The opponents are read only once the rest of the kick is on.
	if AISkateKickRead.should_kick(me.position, me.velocity, me.facing, me.stance_active,
			me.blade_contact_world, PuckController.PICKUP_RADIUS, puck.position, puck.velocity,
			snapshot.loose_puck_touch_team, _team_id, _stick_free(me), false, _contact) \
			and not _pressured(me, snapshot, opponent_ids):
		input.brake = true


# The blade down on the ice and nothing else holding the stick, as far as the
# replicated state shows it; the host's own gate has the last word.
static func _stick_free(me: SkaterNetworkState) -> bool:
	if me.blade_up or me.stick_tied or me.hit_committed or me.pin_role != BoardPinRules.Role.NONE:
		return false
	if StickCheckRules.is_stick_busy(me.stick_check_phase):
		return false
	return me.shot_state != SkaterStateMachine.State.FOLLOW_THROUGH \
			and me.shot_state != SkaterStateMachine.State.SHOT_BLOCKING


func _pressured(me: SkaterNetworkState, snapshot: WorldSnapshot, opponent_ids: Array) -> bool:
	for pid: int in opponent_ids:
		var other: SkaterNetworkState = snapshot.skater_states.get(pid)
		if other == null or other.is_ghost or other.knockdown_timer > 0.0:
			continue
		if SkateContactRules.pressures(me.position, other.position):
			return true
	return false
