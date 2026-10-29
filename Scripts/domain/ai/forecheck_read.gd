class_name AIForecheckRead

# Can we pressure their puck in their zone? The one read that picks the shape
# when they have it deep: a forecheck (FORECHECK, the 1-2-2 / 3v3 1-1-1) while
# our first forechecker gets a stick on the puck before its carrier can move it,
# else the set neutral-zone shape (TRANS_DEFENSE, the 1-1-3 / 3v3 1-2). A man
# with time to make his first play makes the stretch pass past an aggressive
# forecheck, so the forecheck is priced on that time and nothing else. See
# Scripts/domain/ai/CLAUDE.md → "Forecheck or set up".
#
# His first play is away a release window (AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S,
# decision to puck off the blade) after he has read it (CARRIER_READ_S from the
# moment the puck is his, less what he has already held it); a man picking up a
# loose puck also has to reach it and settle it (AIFeedReception.receiver_settle_s
# at the pace it meets him). Our soonest forechecker's blade
# (AILoosePuckChase.reach_eta, momentum-aware, at his own build) must be on the
# puck before that. A loose
# puck is raced on its path (the chase election's walk), so a dump in flight is
# met where it is played, not where it is now, and winning it outright is a
# forecheck too. It is no forecheck unless that first touch is in their zone.

# Hysteresis on the continuous margin, not on the shape it picks (the same reason
# AIRushRead.TRACK_ENTER_MARGIN_S sits on the recovery race): a forecheck starts
# only with a stride in hand, and is given up only once he is clearly free.
const ENTER_MARGIN_S: float = 0.2
const HOLD_MARGIN_S: float = -0.2
# A carrier's choice reaction: with the puck on his stick, the look up and the
# pick of his play among his options before he starts it.
const CARRIER_READ_S: float = 0.5

const _PATH_STEP_S: float = AILoosePuckChase.RACE_LOOKAHEAD_S / float(AILoosePuckChase.RACE_STEPS)


# The time (s) our first forechecker's stick is on their puck before its carrier
# can have his first play away: positive, we are on him with that much in hand.
# -INF when the puck is not theirs to move in their zone (not in it, ours, a
# loose puck first played outside it, or nobody of ours may forecheck); INF for a
# loose puck with none of theirs on the ice.
#
# `forwards_only`: the 5v5 D pair holds the line in a forecheck, so a D gets on
# him only as far down the wall as the strong D's pinch goes
# (AIRoleDefenseman.PINCH_MAX_DEPTH_M); `position_by_peer` names who is a D.
# `carrier_held_s`: how long their carrier has had the puck.
static func pressure_margin_s(snapshot: WorldSnapshot, team_id: int,
		own_goal_z: float, team_id_by_peer: Dictionary, caps_by_peer: Dictionary,
		position_by_peer: Dictionary, forwards_only: bool,
		carrier_held_s: float = 0.0) -> float:
	if snapshot == null or snapshot.puck_state == null:
		return -INF
	var puck: Vector3 = snapshot.puck_state.position
	var carrier: int = snapshot.puck_state.carrier_peer_id
	var window_s: float = AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S
	# Where his first play leaves from, and when it is away.
	var target: Vector3
	var away_s: float
	var best: float = -INF
	if carrier != -1:
		if not _in_their_zone(puck, own_goal_z) \
				or team_id_by_peer.get(carrier, -1) == team_id \
				or not snapshot.skater_states.has(carrier):
			return -INF   # out of their zone, or ours
		var cs: SkaterNetworkState = snapshot.skater_states[carrier]
		away_s = maxf(0.0, CARRIER_READ_S - carrier_held_s) + window_s
		target = cs.position + cs.velocity * away_s
	else:
		var vel: Vector3 = snapshot.puck_state.velocity
		var path: Array[Vector3] = AILoosePuckChase.race_trajectory(puck, vel)
		var setup_s: float = AILoosePuckChase.setup_margin(vel)
		var playable_s: float = AILoosePuckChase.race_playable_time(puck, vel)
		var theirs_s: float = _first_on_path(snapshot, team_id_by_peer, caps_by_peer,
				path, puck, setup_s, playable_s, team_id, false)
		if theirs_s == INF:
			return INF   # nobody of theirs to move it
		var ours_s: float = _first_on_path(snapshot, team_id_by_peer, caps_by_peer,
				path, puck, setup_s, playable_s, team_id, true)
		if not _in_their_zone(AILoosePuckChase.path_intercept_point(path, _PATH_STEP_S,
				puck, minf(ours_s, theirs_s)), own_goal_z):
			return -INF   # played before it is in their zone
		target = AILoosePuckChase.path_intercept_point(path, _PATH_STEP_S, puck, theirs_s)
		var meet_speed: float = target.distance_to(AILoosePuckChase.path_intercept_point(
				path, _PATH_STEP_S, puck, theirs_s + _PATH_STEP_S)) / _PATH_STEP_S
		away_s = theirs_s + AIFeedReception.receiver_settle_s(meet_speed) \
				+ CARRIER_READ_S + window_s
		best = theirs_s - ours_s
	var d_reach: bool = not forwards_only \
			or -signf(own_goal_z) * target.z - GameRules.BLUE_LINE_Z \
					<= AIRoleDefenseman.PINCH_MAX_DEPTH_M
	var on_s: float = _our_first_to(snapshot, team_id, team_id_by_peer, caps_by_peer,
			position_by_peer, not d_reach, target, away_s - best)
	if on_s != INF:
		best = maxf(best, away_s - on_s)
	# A loose puck we only tie for is a 50/50, and a 50/50 in their end is gone
	# after: its contest band is ours (AIActionScoring.arrival_race's).
	if carrier == -1:
		best += AIActionScoring.CHASE_CONTEST_MARGIN_S
	return best


# Whether to forecheck, from this tick's margin and last tick's answer.
static func can_forecheck(margin_s: float, was_forechecking: bool) -> bool:
	return margin_s > (HOLD_MARGIN_S if was_forechecking else ENTER_MARGIN_S)


# Our soonest forechecker's blade to `p`. Stops early once nobody can beat
# `bound` (s).
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
		best = minf(best, AILoosePuckChase.reach_eta(s.position, p, s.velocity, speed,
				caps.max_accel if caps != null else AIArrival.SHED_ACCEL_DEFAULT_M_S2, reach))
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
