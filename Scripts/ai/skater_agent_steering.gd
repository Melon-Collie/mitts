class_name SkaterAgentSteering
extends RefCounted

# Lead time for the carrier endpoint of the shot-lane repel: off-puck bots step
# out of the lane as it will be when steering has moved them. Long leads put the
# lane in the wrong zone entirely.
const SHOT_LANE_LEAD_TIME_S: float = 0.25

# One bot's body steering toward an anchor: the potential field (teammate,
# opponent and shot-lane repels, the velocity-matched or moving-frame seek), the
# brake-pivot, the arrival brake and the stance carve. Owns their hysteresis
# and its scratch; the anchor and the bot's own numbers come in per call. The
# offside brake is the agent's, applied on top.

var _peer_id: int = -1
var _team_id: int = -1
var _team_id_by_peer: Dictionary = {}
# Previous tick's brake-pivot decision — the hysteresis memory for
# AISteering.should_brake (engage at BRAKE_PIVOT_ANGLE_DEG, hold until
# BRAKE_PIVOT_RELEASE_ANGLE_DEG or the speed floor). Self-corrects within a
# tick of any teleport (the speed gate releases it at a standstill), so it
# needs no faceoff reset.
var _pivot_braking: bool = false
# Arrival-brake hysteresis (AISteering.should_arrival_brake) — held across
# ticks so the brake key doesn't strobe while speed sheds on approach.
var _arrival_braking: bool = false
# Stance-turn hysteresis (AISteering.stance_carves_to).
var _stance_turning: bool = false
# Reused buffer for steering's teammate-position list. Cleared at the top
# of each _apply_steering call.
var _scratch_teammates: Array[Vector3] = []
# Reused buffer for steering's opponent-position list. Cleared at the
# top of _apply_steering. The CARRIER role behavior owns its own
# scratch buffers for action scoring.
var _scratch_opponents: Array[Vector3] = []
# Opponent velocities index-matched to _scratch_opponents — steering's
# carrier threat-gated repel reads defender MOMENTUM, not proximity
# (AISteering._carrier_threat_repel). Filled alongside the positions.
var _scratch_opponent_steer_vels: Array[Vector3] = []
# Teammate velocities index-matched to _scratch_teammates — steering's
# teammate repel reads their SWEPT PATH (where they're skating into) so
# crossing routes bend apart before the bodies meet. Filled alongside the
# teammate positions in _apply_steering.
var _scratch_teammate_steer_vels: Array[Vector3] = []
# Shared empty fallback so the per-tick cache reads don't allocate a `[]`
# default literal (Dictionary.get evaluates its default eagerly). Never mutated.
var _empty_ids: Array = []
# Shared empty velocity list — passed to steering for off-puck bots (plain
# proximity repel) so the per-tick call doesn't allocate a literal. Never mutated.
var _empty_vels: Array[Vector3] = []


func setup(peer_id: int, team_id: int, team_id_by_peer: Dictionary) -> void:
	_peer_id = peer_id
	_team_id = team_id
	_team_id_by_peer = team_id_by_peer


# `arrive` opts into the arrival brake (AISteering.should_arrival_brake):
# station-keeping callers (off-puck role destinations) brake to STOP at the
# anchor instead of overshooting a target that slowed down. Waypoint-style
# callers (carry steps, puck chase, check commits, tag-up) leave it false —
# they either re-pick the anchor continuously or WANT to arrive at speed.
#
# Writes move_vector, brake and stance_held. `attacking_goal_pos` ends the shot
# lane kept clear for a teammate carrier; `upright_lateral_accel` and
# `blade_reach` are this bot's own.
func steer(input: InputState, snapshot: WorldSnapshot, self_pos: Vector3,
		anchor: Vector3, arrive: bool, velocity_match_speed: float,
		anchor_velocity: Vector3, engaged_peer_id: int,
		retreat_floor_center: Vector3, retreat_floor_radius: float,
		attacking_goal_pos: Vector3, upright_lateral_accel: float,
		blade_reach: float, advance_cap: float = INF) -> void:
	# Standard potential-field steering with brake-pivot.
	# Use the per-team roster published by GameManager._enrich_snapshot_for_ai
	# instead of re-partitioning snapshot.skater_states every physics tick.
	# Fall back to a live partition when the cache is empty (unit tests).
	_scratch_teammates.clear()
	_scratch_teammate_steer_vels.clear()
	_scratch_opponents.clear()
	_scratch_opponent_steer_vels.clear()
	if not snapshot.teammate_ids_by_team.is_empty():
		var team_ids: Array = snapshot.teammate_ids_by_team[_team_id] \
				if snapshot.teammate_ids_by_team.has(_team_id) else _empty_ids
		for peer_id: int in team_ids:
			if peer_id == _peer_id:
				continue
			_scratch_teammates.append(snapshot.skater_states[peer_id].position)
			_scratch_teammate_steer_vels.append(snapshot.skater_states[peer_id].velocity)
		for other_team: int in snapshot.teammate_ids_by_team:
			if other_team == _team_id:
				continue
			var opp_ids: Array = snapshot.teammate_ids_by_team[other_team]
			for peer_id: int in opp_ids:
				if peer_id == engaged_peer_id:
					continue   # the man we were told to close on — see engaged_peer_id
				_scratch_opponents.append(snapshot.skater_states[peer_id].position)
				_scratch_opponent_steer_vels.append(snapshot.skater_states[peer_id].velocity)
	else:
		for peer_id: int in snapshot.skater_states:
			if peer_id == _peer_id:
				continue
			if _team_id_by_peer.get(peer_id, -1) == _team_id:
				_scratch_teammates.append(snapshot.skater_states[peer_id].position)
				_scratch_teammate_steer_vels.append(snapshot.skater_states[peer_id].velocity)
			elif peer_id != engaged_peer_id:
				_scratch_opponents.append(snapshot.skater_states[peer_id].position)
				_scratch_opponent_steer_vels.append(snapshot.skater_states[peer_id].velocity)

	# Shot-lane endpoints: only set when a teammate (not us, not opp) is
	# the carrier — keeps off-puck bots out of the carrier's lane to the
	# attacking goal. Carrier-side bots pass zero (they aren't repelled
	# from their own lane).
	var lane_start: Vector3 = Vector3.ZERO
	var lane_end: Vector3 = Vector3.ZERO
	var carrier: int = snapshot.puck_state.carrier_peer_id
	if carrier != -1 and carrier != _peer_id:
		if _team_id_by_peer.get(carrier, -1) == _team_id:
			var carrier_state: SkaterNetworkState = snapshot.skater_states.get(carrier)
			if carrier_state != null:
				# Lead the carrier — the lane we want to clear is where
				# they'll shoot from, not where they are right now.
				lane_start = AITrajectory.predict_at(
						carrier_state.position, carrier_state.velocity,
						SHOT_LANE_LEAD_TIME_S)
				lane_end = attacking_goal_pos

	# Carrier-specific repel: when WE have the puck, defender avoidance runs
	# threat-gated and route-around (momentum-reach instead of raw proximity,
	# never pushed backwards off the carry line — see
	# AISteering._carrier_threat_repel), at the heavier carry weight. Off-puck
	# bots keep the plain proximity field (velocities withheld).
	var opp_repel: float = AISteering.OPPONENT_REPEL_WEIGHT
	var steer_vels: Array[Vector3] = _empty_vels
	if carrier == _peer_id:
		opp_repel = AISteering.OPPONENT_REPEL_WEIGHT_CARRY
		steer_vels = _scratch_opponent_steer_vels
	# Velocity-matched seek to the anchor when the caller opts in
	# (velocity_match_speed > 0 — the carrier path): the anchor pull cancels
	# cross-momentum so the bot redirects onto the line instead of orbiting past
	# it. Read our own velocity from the snapshot for the match.
	# Also the carrier's threat repel frame (defenders are swept relative to us).
	var match_self_vel: Vector3 = Vector3.ZERO
	if velocity_match_speed > 0.0 or carrier == _peer_id:
		var self_st: SkaterNetworkState = snapshot.skater_states.get(_peer_id)
		if self_st != null:
			match_self_vel = self_st.velocity
	# A stand that RIDES A MAN is flown in its own frame: the anchor term
	# tracks a velocity rather than visiting a point, and the arrival brake
	# stands down (it is an actuator on our own speed and cannot slow an
	# approaching anchor). See AISteering's moving-frame pursuit.
	var moving_anchor: bool = velocity_match_speed > 0.0 \
			and Vector2(anchor_velocity.x, anchor_velocity.z).length() \
					> AISteering.MOVING_FRAME_MIN_SPEED \
			and AISteering.is_rideable_anchor(anchor)
	var desired: Vector2 = AISteering.compute_move_vector(
			self_pos, anchor, _scratch_teammates, _scratch_opponents,
			lane_start, lane_end,
			GameRules.RINK_HALF_WIDTH, GameRules.RINK_HALF_LENGTH,
			opp_repel, steer_vels, _scratch_teammate_steer_vels,
			match_self_vel, velocity_match_speed, anchor_velocity,
			retreat_floor_center, retreat_floor_radius, advance_cap)

	# Brake-pivot: if our current velocity is far off the desired direction,
	# carving a wide arc loses. The bot keeps move_vector on the exit direction —
	# the input shape a human uses — and either digs the turn in the stance
	# (exit still in front, AISteering.pivot_cuts_in_stance) or presses the REAL
	# brake key for a hockey stop (exit behind), so the cosmetic layer reads a
	# genuine cut or a genuine stop into a dig-in restart. The stride resumes
	# toward the exit once the pivot releases (hysteresis + speed floor in
	# AISteering.should_brake). Short of a pivot, any turn onto the anchor the
	# upright edges can't make is carved in the stance (stance_carves_to).
	var self_state: SkaterNetworkState = snapshot.skater_states.get(_peer_id)
	if self_state != null:
		var v: Vector3 = self_state.velocity
		_pivot_braking = AISteering.should_brake(desired, Vector2(v.x, v.z), _pivot_braking)
		# Arrival brake (opt-in per call site): stop AT a station target
		# instead of overshooting one that slowed down and doubling back.
		# The pivot brake wins when both would fire (it already implies
		# maximal braking). A MOVING anchor never takes it — see
		# AISteering.should_arrival_brake; there the closing profile is the
		# arrival law and the pivot brake is the only actuator needed.
		if arrive and not _pivot_braking and not moving_anchor:
			_arrival_braking = AISteering.should_arrival_brake(
					self_pos, anchor, Vector2(v.x, v.z), _arrival_braking)
		else:
			_arrival_braking = false
		var pivot_cut: bool = _pivot_braking \
				and AISteering.pivot_cuts_in_stance(desired, Vector2(v.x, v.z))
		input.brake = (_pivot_braking and not pivot_cut) or _arrival_braking
		_stance_turning = not input.brake and AISteering.stance_carves_to(
				self_pos, anchor, desired, Vector2(v.x, v.z), upright_lateral_accel,
				blade_reach, _stance_turning)
		input.stance_held = pivot_cut or _stance_turning
	input.move_vector = desired
