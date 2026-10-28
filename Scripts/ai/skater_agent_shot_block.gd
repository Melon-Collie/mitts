class_name SkaterAgentShotBlock
extends RefCounted

# One bot's shot block (AIShotBlockRead), every physics tick after dispatch:
# - as a 2-on-1's last defender, dive across the pass the carrier has to make,
#   when the lane is past what he reaches on his feet before the pass does;
# - otherwise, drop into the block while a low shot's lane runs through him, and
#   stay down while the released shot is still coming through.
# Owns only whether it is blocking; everything else is read off the snapshot.

var _peer_id: int = -1
var _team_id: int = -1
var _team_id_by_peer: Dictionary = {}
var _caps_by_peer: Dictionary = {}
var _screen_cfg := GoalieScreenRules.ScreenConfig.new()
var _blocking: bool = false


func setup(peer_id: int, team_id: int, team_id_by_peer: Dictionary,
		caps_by_peer: Dictionary) -> void:
	_peer_id = peer_id
	_team_id = team_id
	_team_id_by_peer = team_id_by_peer
	_caps_by_peer = caps_by_peer


# `stick_reach` and `accel` are this bot's own; `rush` the team's rush read.
func apply(input: InputState, snapshot: WorldSnapshot, own_goal_dir: float,
		rush: AIRushRead, stick_reach: float, accel: float) -> void:
	var was_blocking: bool = _blocking
	_blocking = false
	if snapshot == null or snapshot.puck_state == null:
		return
	var me: SkaterNetworkState = snapshot.skater_states.get(_peer_id)
	var puck: PuckNetworkState = snapshot.puck_state
	if me == null or me.knockdown_timer > 0.0 or me.pin_role != BoardPinRules.Role.NONE \
			or puck.carrier_peer_id == _peer_id:
		return
	var goal := Vector3(0.0, 0.0, own_goal_dir * GameRules.GOAL_LINE_Z)
	var dive: Vector3 = _dive_point(snapshot, me, own_goal_dir, rush, stick_reach, accel)
	if dive.is_finite():
		input.stance_held = true
		input.block_held = true
		input.mouse_world_pos = dive
		return
	if _shot_coming(snapshot, me, goal, own_goal_dir) or (was_blocking
			and puck.carrier_peer_id == -1
			and AIShotBlockRead.puck_coming_through(me.position, puck.position, puck.velocity)):
		_blocking = true
		input.block_held = true
		input.stance_held = false


# An opponent winding up in our end with us in his lane, low enough to block,
# and us not in our goalie's eyes.
func _shot_coming(snapshot: WorldSnapshot, me: SkaterNetworkState, goal: Vector3,
		own_goal_dir: float) -> bool:
	var goalie: GoalieNetworkState = snapshot.goalie_states.get(_team_id)
	if goalie != null and AIShotBlockRead.screens_own_goalie(me.position,
			Vector3(goalie.position_x, 0.0, goalie.position_z), _screen_cfg):
		return false
	var puck: PuckNetworkState = snapshot.puck_state
	for pid: int in snapshot.skater_states:
		if _team_id_by_peer.get(pid, -1) == _team_id:
			continue
		var shooter: SkaterNetworkState = snapshot.skater_states[pid]
		if not _winding_up(shooter.shot_state):
			continue
		# A one-timer's release is his blade, where the feed meets it.
		var release: Vector3 = puck.position if puck.carrier_peer_id == pid else shooter.position
		if own_goal_dir * release.z < GameRules.BLUE_LINE_Z:
			continue
		var caps: AISkaterCaps = _caps_by_peer.get(pid)
		var speed: float = caps.wrister_shot_speed if caps != null \
				else GameRules.DEFAULT_WRISTER_POWER_MAX_M_S
		if AIShotBlockRead.in_lane(me.position, release, goal) \
				and AIShotBlockRead.stays_low(me.position, release, shooter.elevation_level, speed):
			return true
	return false


static func _winding_up(shot_state: int) -> bool:
	return shot_state == SkaterStateMachine.State.WRISTER_AIM \
			or shot_state == SkaterStateMachine.State.SLAPPER_CHARGE_WITH_PUCK \
			or shot_state == SkaterStateMachine.State.SLAPPER_CHARGE_WITHOUT_PUCK


# A man down on the rush, the carrier inside shooting range: the first pass lane
# to one of his men that we can only take away by diving, and that no teammate is
# nearer to. INF when there is none.
func _dive_point(snapshot: WorldSnapshot, me: SkaterNetworkState, own_goal_dir: float,
		rush: AIRushRead, stick_reach: float, accel: float) -> Vector3:
	if rush == null or not rush.is_live or rush.numbers != AIRushRead.Numbers.DOWN_ONE:
		return Vector3.INF
	var carrier_pid: int = snapshot.puck_state.carrier_peer_id
	if carrier_pid == -1 or carrier_pid != rush.carrier_peer:
		return Vector3.INF
	var carrier: SkaterNetworkState = snapshot.skater_states.get(carrier_pid)
	if carrier == null or own_goal_dir * carrier.position.z < AIShotBlockRead.SHOOTING_RANGE_Z:
		return Vector3.INF
	for pid: int in rush.attackers:
		if pid == carrier_pid or not snapshot.skater_states.has(pid):
			continue
		var q: Vector3 = AIShotBlockRead.dive_point(me.position, me.velocity, carrier.position,
				snapshot.skater_states[pid].position, stick_reach, accel,
				AIPuckLane.PASS_SPEED_M_S)
		if q.is_finite() and _nearest_of_ours(snapshot, me, q):
			return q
	return Vector3.INF


func _nearest_of_ours(snapshot: WorldSnapshot, me: SkaterNetworkState, at: Vector3) -> bool:
	var mine: float = Vector2(me.position.x - at.x, me.position.z - at.z).length_squared()
	for pid: int in snapshot.skater_states:
		if pid == _peer_id or _team_id_by_peer.get(pid, -1) != _team_id:
			continue
		var p: Vector3 = snapshot.skater_states[pid].position
		if Vector2(p.x - at.x, p.z - at.z).length_squared() < mine:
			return false
	return true
