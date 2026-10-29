class_name AIForecheckRead

# Can we get on their puck while it is still in their zone? The one read that
# picks the shape when they have it deep: a forecheck (FORECHECK, the 1-2-2 /
# 3v3 1-1-1) if our first forechecker meets the carrier on his way out, else the
# set neutral-zone shape (TRANS_DEFENSE, the 1-1-3 / 3v3 1-2). See
# Scripts/domain/ai/CLAUDE.md → "Forecheck or set up".
#
# It is a race along the carrier's way out: his route is the straight line from
# where he stands to the exit on his blue line his lateral drift takes him to,
# and at each point of it his arrival is raced against our soonest forechecker's
# stick (momentum-aware, each at his own build, a blade's reach short of the
# point). The margin is the best lead we hold at any point up to the line.
#
# A loose puck is a carrier nobody holds yet. It is raced on its path (the chase
# election's walk), so a dump in flight is met where it is played, not where it
# is now: our lead is the better of winning it outright and getting on their
# man after he plays it, his clock starting there from rest. It is no forecheck
# unless that first touch is in their zone.

# Route intervals raced; the exit is the last point — a stick on him at his line
# still keeps him in.
const ROUTE_SAMPLES: int = 8
# Hysteresis on the continuous race, not on the shape it picks (the same reason
# AIRushRead.TRACK_ENTER_MARGIN_S sits on the recovery race): a forecheck starts
# only with a stride in hand, and is given up only once he is clearly away.
const ENTER_MARGIN_S: float = 0.2
const HOLD_MARGIN_S: float = -0.2
# How far inside the boards his exit lane is kept, so the route never ends on
# the wall itself.
const EXIT_WALL_INSET_M: float = 1.5

# Their skater in his own zone does not ice the race by standing still: below
# this he is read as a man who will start up the ice, his clock from rest.
const _MIN_SPEED: float = 0.1
const _PATH_STEP_S: float = AILoosePuckChase.RACE_LOOKAHEAD_S / float(AILoosePuckChase.RACE_STEPS)


# The best lead (s) our first forechecker holds over their puck on its way out of
# their zone: positive, we meet it inside the zone with that much time in hand.
# -INF when the puck is not theirs to bring out of their zone (not in it, ours,
# a loose puck first played outside it, or nobody of ours may forecheck); INF
# for a loose puck with none of theirs on the ice.
#
# `forwards_only`: the 5v5 D pair holds the line in a forecheck, so a D gets on
# him only as far down the wall as the strong D's pinch goes
# (AIRoleDefenseman.PINCH_MAX_DEPTH_M); `position_by_peer` names who is a D.
static func pressure_margin_s(snapshot: WorldSnapshot, team_id: int,
		own_goal_z: float, team_id_by_peer: Dictionary, caps_by_peer: Dictionary,
		position_by_peer: Dictionary, forwards_only: bool) -> float:
	if snapshot == null or snapshot.puck_state == null:
		return -INF
	var puck: Vector3 = snapshot.puck_state.position
	var carrier: int = snapshot.puck_state.carrier_peer_id
	var origin: Vector3 = puck
	var origin_vel: Vector3 = Vector3.ZERO
	var their_caps: AISkaterCaps = null
	var their_start_s: float = 0.0
	var best: float = -INF
	if carrier != -1:
		if not _in_their_zone(puck, own_goal_z) \
				or team_id_by_peer.get(carrier, -1) == team_id \
				or not snapshot.skater_states.has(carrier):
			return -INF   # out of their zone, or ours
		var cs: SkaterNetworkState = snapshot.skater_states[carrier]
		origin = cs.position
		origin_vel = cs.velocity
		their_caps = caps_by_peer.get(carrier)
	else:
		var vel: Vector3 = snapshot.puck_state.velocity
		var path: Array[Vector3] = AILoosePuckChase.race_trajectory(puck, vel)
		var setup_s: float = AILoosePuckChase.setup_margin(vel)
		var playable_s: float = AILoosePuckChase.race_playable_time(puck, vel)
		their_start_s = _first_on_path(snapshot, team_id_by_peer, caps_by_peer, path,
				puck, setup_s, playable_s, team_id, false)
		if their_start_s == INF:
			return INF   # nobody of theirs to bring it out
		var ours_s: float = _first_on_path(snapshot, team_id_by_peer, caps_by_peer,
				path, puck, setup_s, playable_s, team_id, true)
		if not _in_their_zone(AILoosePuckChase.path_intercept_point(path, _PATH_STEP_S,
				puck, minf(ours_s, their_start_s)), own_goal_z):
			return -INF   # played before it is in their zone
		origin = AILoosePuckChase.path_intercept_point(path, _PATH_STEP_S, puck,
				their_start_s)
		best = their_start_s - ours_s
	var their_speed: float = their_caps.max_speed if their_caps != null \
			else AIArrival.SKATER_REF_SPEED_M_S
	var their_accel: float = their_caps.max_accel if their_caps != null \
			else AIArrival.SHED_ACCEL_DEFAULT_M_S2

	var exit: Vector3 = exit_point(origin, origin_vel, own_goal_z, their_speed)
	for i: int in ROUTE_SAMPLES + 1:
		var p: Vector3 = origin.lerp(exit, float(i) / float(ROUTE_SAMPLES))
		var their_t: float = their_start_s + AIArrival.time_to_arrive(
				origin, p, origin_vel, their_speed, their_accel)
		var d_reach: bool = not forwards_only \
				or -signf(own_goal_z) * p.z - GameRules.BLUE_LINE_Z <= AIRoleDefenseman.PINCH_MAX_DEPTH_M
		var ours_t: float = _our_first_to(snapshot, team_id, team_id_by_peer,
				caps_by_peer, position_by_peer, not d_reach, p, their_t - best)
		if ours_t == INF:
			continue
		best = maxf(best, their_t - ours_t)
	# A loose puck we only tie for is a 50/50, and a 50/50 in their end is gone
	# after: its contest band is ours (AIActionScoring.arrival_race's).
	if carrier == -1:
		best += AIActionScoring.CHASE_CONTEST_MARGIN_S
	return best


# Whether to forecheck, from this tick's margin and last tick's answer.
static func can_forecheck(margin_s: float, was_forechecking: bool) -> bool:
	return margin_s > (HOLD_MARGIN_S if was_forechecking else ENTER_MARGIN_S)


# Where a puck at `origin`, moving at `vel`, leaves their zone: on their blue
# line, drifted across by his lateral pace over his trip there at `speed`.
static func exit_point(origin: Vector3, vel: Vector3, own_goal_z: float,
		speed: float) -> Vector3:
	var line_z: float = -signf(own_goal_z) * GameRules.BLUE_LINE_Z
	var trip_s: float = absf(origin.z - line_z) / maxf(speed, AIArrival.MIN_TRAVEL_SPEED_M_S)
	var drift_x: float = vel.x if absf(vel.x) > _MIN_SPEED else 0.0
	var half: float = GameRules.INNER_HALF_WIDTH - EXIT_WALL_INSET_M
	return Vector3(clampf(origin.x + drift_x * trip_s, -half, half), 0.0, line_z)


# Our soonest forechecker to `p`. Stops early once nobody can beat `bound` (s).
static func _our_first_to(snapshot: WorldSnapshot, team_id: int,
		team_id_by_peer: Dictionary, caps_by_peer: Dictionary,
		position_by_peer: Dictionary, forwards_only: bool, p: Vector3,
		bound: float) -> float:
	var best: float = INF
	for pid: int in snapshot.skater_states:
		if team_id_by_peer.get(pid, -1) != team_id:
			continue
		if forwards_only and PlayerRules.is_defense_slot(position_by_peer.get(pid, 0)):
			continue
		if snapshot.is_out_of_play(pid):
			continue
		var s: SkaterNetworkState = snapshot.skater_states[pid]
		var caps: AISkaterCaps = caps_by_peer.get(pid)
		var speed: float = caps.max_speed if caps != null else AIArrival.SKATER_REF_SPEED_M_S
		var reach: float = caps.max_blade_reach if caps != null else AIBotMechanics.BLADE_REACH_M
		# time_to_arrive only adds to distance / top speed: an exact prune.
		if s.position.distance_to(p) - reach >= minf(best, bound) * speed:
			continue
		best = minf(best, AIArrival.time_to_arrive(s.position, p, s.velocity, speed,
				caps.max_accel if caps != null else AIArrival.SHED_ACCEL_DEFAULT_M_S2)
				- reach / speed)
	return best


# One side's soonest body to a loose puck on `path` (walked from `puck`), at the
# election's resolution: ours when `ours`, else theirs.
static func _first_on_path(snapshot: WorldSnapshot, team_id_by_peer: Dictionary,
		caps_by_peer: Dictionary, path: Array[Vector3], puck: Vector3, setup_s: float,
		playable_s: float, team_id: int, ours: bool) -> float:
	var best: float = INF
	for pid: int in snapshot.skater_states:
		var t: int = team_id_by_peer.get(pid, -1)
		if t == -1 or (t == team_id) != ours or snapshot.is_out_of_play(pid):
			continue
		var s: SkaterNetworkState = snapshot.skater_states[pid]
		var caps: AISkaterCaps = caps_by_peer.get(pid)
		best = minf(best, AILoosePuckChase.path_intercept_time(path, _PATH_STEP_S, puck,
				s.position, s.velocity, AILoosePuckChase.race_vmax(caps), setup_s,
				AIArrival.SHED_ACCEL_DEFAULT_M_S2, 0.0, playable_s))
	return best


static func _in_their_zone(p: Vector3, own_goal_z: float) -> bool:
	return -signf(own_goal_z) * p.z > GameRules.BLUE_LINE_Z
