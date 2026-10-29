class_name AILoosePuckChase

# Pure-function loose-puck race reads: the per-team chaser election, the
# incidental reach band and the teammate yield (Scripts/domain/ai/CLAUDE.md →
# "Loose-puck retrieval is two reads"). The election is momentum-aware (a bot
# nearer the puck but coasting AWAY is not the one arriving first) and
# incumbent-hysteretic. Stateless: the caller owns the per-team `prev_elected`
# and feeds it back each frame.

# Incumbent keeps the chase unless a challenger's intercept time beats it by
# more than this margin (s) — ≈ 1 m at the calibrated ETA's close-range
# standing-start rate. Equal to AIRoleSlots.HYSTERESIS_PENALTY_S (see there).
const HYSTERESIS_S: float = 0.2
# Default for teammate_first_to_puck's tag_up_peers — a shared empty map, so
# callers that omit it allocate nothing.
const _NO_PEERS: Dictionary = {}

# ── Path race ────────────────────────────────────────────────────────────────
# EVERY loose puck races on its friction + board-aware predicted path: at each
# step T of the walk, a skater makes the intercept iff his calibrated ETA to
# that point fits inside T. Never gate the walk on puck speed: on 0.05-friction
# ice a slow roller's path is not approximately its position.
const RACE_LOOKAHEAD_S: float = 3.0
# 0.25 s steps. The race read interpolates within the step it crosses in
# (path_intercept_time), so this is the resolution of the PATH, not of the
# answer — a coarser walk costs geometric fidelity, never race margin.
const RACE_STEPS: int = 12

# Above this the puck must be met EARLY — blade swung to the gate and the body
# set — so its intercept is judged with KILL_SETUP_MARGIN_S of arrival slack.
# Below it a skater can meet the puck exactly. A statement about the RECEPTION
# only; every puck's path is walked regardless.
const FAST_PUCK_SPEED_M_S: float = 4.0

# ── Race commitment (is that body actually going for the puck?) ─────────────
# First-stride floor (m/s): a skater actually running a race for a loose puck
# exceeds this closing speed toward it within his first strides; below it the
# body is not a collector, whatever his hypothetical ETA says. Two consumers:
#   - the election (below): a HUMAN teammate can't be assigned by election,
#     so he only suppresses the bots while demonstrably playing the puck;
#   - the chase decline (AILoosePuckChase.loose_puck_race_lost): an opponent
#     who is NOT running the race must not talk our chaser out of it, or both
#     teams decline on hypothetical winners and nobody goes.
const RACE_COMMIT_MIN_CLOSING_M_S: float = 1.0


# On the point (inside the physical contest band — standing there IS the play,
# no motion needed) or genuinely closing on it.
static func committed_to_point(s: SkaterNetworkState, point: Vector3) -> bool:
	var dx: float = point.x - s.position.x
	var dz: float = point.z - s.position.z
	var d: float = sqrt(dx * dx + dz * dz)
	if d <= AIActionScoring.CHASE_CONTEST_MARGIN_M:
		return true
	return (s.velocity.x * dx + s.velocity.z * dz) / d \
			>= RACE_COMMIT_MIN_CLOSING_M_S


# On the puck (inside the physical contest band) or genuinely closing on it.
static func committed_to_race(s: SkaterNetworkState, puck_pos: Vector3) -> bool:
	return committed_to_point(s, puck_pos)


# Arrival slack (s) a fast-puck intercept must clear: the reception setup time
# to swing the blade to the gate and get set. Zero slack is a treadmill —
# execution slop misses the exact meeting point by a hair and the read
# re-solves to a new one further along.
const KILL_SETUP_MARGIN_S: float = 0.25


static func is_fast_puck(puck_vel: Vector3) -> bool:
	return puck_vel.x * puck_vel.x + puck_vel.z * puck_vel.z \
			> FAST_PUCK_SPEED_M_S * FAST_PUCK_SPEED_M_S


# Arrival slack a race read must leave itself against this puck — the one
# definition every race read uses.
static func setup_margin(puck_vel: Vector3) -> float:
	return KILL_SETUP_MARGIN_S if is_fast_puck(puck_vel) else 0.0


# Race cap for one candidate: his top speed from caps (league default when
# unset). Every race read prices with it, so they cannot disagree about who has
# the extra gear.
static func race_vmax(caps: AISkaterCaps) -> float:
	return caps.max_speed if caps != null else AIArrival.SKATER_REF_SPEED_M_S


# Blade reach for one candidate's reach band: his blade span from caps plus the
# agent's buffer (SkaterAgentStateMachine._blade_reach), league when unset.
static func race_reach(caps: AISkaterCaps) -> float:
	return caps.blade_span + AIBotMechanics.BLADE_REACH_BUFFER_M if caps != null \
			else AIBotMechanics.BLADE_REACH_M


# The predicted path one race is run over, freshly walked.
static func walk_race(puck_pos: Vector3, puck_vel: Vector3) -> Array[Vector3]:
	return AITrajectory.predict_puck(puck_pos, puck_vel, RACE_STEPS,
			RACE_LOOKAHEAD_S / float(RACE_STEPS))


# The AI worker's memo of walk_race, keyed on the exact puck state so every bot
# racing the same puck in a batch — each chaser's race-lost decline, every
# reach-band read — shares one walk. Callers must treat the returned array as
# read-only. WORKER THREAD ONLY: the host's per-frame election runs on the main
# thread while a batch is in flight, and two threads replacing one static array
# can free it under a reader, so elect walks its own
# (test_loose_puck_chase.gd holds that).
static var _traj_cache_pos: Vector3 = Vector3.INF
static var _traj_cache_vel: Vector3 = Vector3.INF
static var _traj_cache: Array[Vector3] = []


static func race_trajectory(puck_pos: Vector3, puck_vel: Vector3) -> Array[Vector3]:
	if puck_pos == _traj_cache_pos and puck_vel == _traj_cache_vel:
		return _traj_cache
	_traj_cache_pos = puck_pos
	_traj_cache_vel = puck_vel
	_traj_cache = walk_race(puck_pos, puck_vel)
	return _traj_cache


# Earliest time (s) this skater can meet the puck ON its predicted path,
# arriving with `margin` of slack (see setup_margin) so a fast contact is a
# set-and-corral instead of a dead heat. `puck_pos` is the walk's origin — the
# path point at t=0, which the sub-step solve below needs as its left endpoint.
# When no step is makeable the race resolves at the settled end of the walk: the
# skater collects the puck where it stops (or exits the horizon), arriving no
# earlier than the horizon itself.
#
# `accel` is the redirect authority the ETA prices the cross-momentum shed at.
# Cross-player callers (the election, which must rank every bot on one shared
# baseline) leave it at the league default; a bot solving its OWN chase passes
# its attribute-scaled max_accel, exactly as time_to_arrive documents.
#
# `reach` lets the SELF read steer to where the blade, not the body, meets the
# puck. The comparative reads (the election, best_intercept_time, the race-lost
# decline) must leave it at 0: every body within a stick would solve to t = 0
# and the election would fall through to its peer-id tie-break. A puck coming to
# the stick is puck_comes_to_reach's read; the election counts it as the puck's
# own time to the band (reach_meet_time), never the body's.
#
# `playable_from` (race_playable_time) is when the puck is back down where a
# grounded blade can play it: nothing earlier on the path is makeable, so a
# popped or flipped puck is met where it lands rather than under its flight.
static func path_intercept_time(traj: Array[Vector3], step_dt: float,
		puck_pos: Vector3, skater_pos: Vector3, skater_vel: Vector3,
		max_speed: float, margin: float = KILL_SETUP_MARGIN_S,
		accel: float = AIArrival.SHED_ACCEL_DEFAULT_M_S2,
		reach: float = 0.0, playable_from: float = 0.0) -> float:
	if traj.is_empty():
		return INF
	for i: int in traj.size():
		var t_step: float = (i + 1) * step_dt
		var t_set: float = t_step - margin
		if t_set <= 0.0 or t_step < playable_from:
			continue
		# Exact prune: even at a flying top-speed start, ETA ≥ (dist − reach) /
		# v_max — skip the full phase-model call when that bound alone misses T.
		# The blade span widens the bound; leaving it off the prune would drop
		# steps the reach-aware ETA below would have made.
		var dx: float = traj[i].x - skater_pos.x
		var dz: float = traj[i].z - skater_pos.z
		var span: float = max_speed * t_set + reach
		if dx * dx + dz * dz > span * span:
			continue
		var eta: float = _reach_eta(
				skater_pos, traj[i], skater_vel, max_speed, accel, reach)
		if eta > t_set:
			continue
		# Crossing found — now solve WHERE in the step it happens. Returning
		# t_step would quantize every race read to the walk's grid, ~2 m of
		# skating at 0.25 s, so bots separated by less than a step read as tied
		# and the election falls through to its peer-id tie-break.
		# Linear-interpolate the arrival slack s(t) = (t − margin) − ETA(t)
		# across the step it changes sign in. Exact for a settled puck: s is
		# then linear in t, so the crossing IS the skater's ETA. The step's
		# left end is pulled up to the landing when the puck comes down in it.
		var prev_t: float = i * step_dt
		var prev_point: Vector3 = traj[i - 1] if i > 0 else puck_pos
		if playable_from > prev_t:
			prev_t = playable_from
			prev_point = path_intercept_point(traj, step_dt, puck_pos, prev_t)
		var prev_slack: float = (prev_t - margin) - _reach_eta(
				skater_pos, prev_point, skater_vel, max_speed, accel, reach)
		if prev_slack >= 0.0:
			return prev_t   # already makeable at the left endpoint
		return prev_t + (t_step - prev_t) * (-prev_slack / (t_set - eta - prev_slack))
	var horizon: float = maxf(traj.size() * step_dt, playable_from)
	return maxf(horizon, _reach_eta(
			skater_pos, traj[-1], skater_vel, max_speed, accel, reach))


# The `playable_from` every race read of this puck passes: when it is back on
# the blade plane (AITrajectory.time_until_on_blade_plane). The walk itself is
# planar; the flight only decides how early the path can be met.
static func race_playable_time(puck_pos: Vector3, puck_vel: Vector3) -> float:
	return AITrajectory.time_until_on_blade_plane(puck_pos, puck_vel)


# ETA for the BLADE to touch `point`, rather than for the body to land on it.
# The destination is the nearest spot on the reach circle around `point` — the
# path point pulled `reach` back along the approach line — so the last stick-
# length is never charged as travel. Already inside reach is 0: the stick is on
# it now.
static func _reach_eta(from_pos: Vector3, point: Vector3, vel: Vector3,
		max_speed: float, accel: float, reach: float) -> float:
	if reach <= 0.0:
		return AIArrival.time_to_arrive(from_pos, point, vel, max_speed, accel)
	var dx: float = point.x - from_pos.x
	var dz: float = point.z - from_pos.z
	var d: float = sqrt(dx * dx + dz * dz)
	if d <= reach:
		return 0.0
	var f: float = (d - reach) / d
	return AIArrival.time_to_arrive(from_pos,
			Vector3(from_pos.x + dx * f, point.y, from_pos.z + dz * f),
			vel, max_speed, accel)


# The path point a path_intercept_time result names — the spot on the walk the
# skater actually meets the puck at. Callers that need to ask something ABOUT
# the intercept (is that body committed to going there? where do I steer?) map
# the time back through this so they can never disagree with the race read that
# produced it. Times past the horizon resolve at the settled end of the walk.
#
# Interpolated, never snapped to the nearest sample: the time it maps is a
# sub-step solve, and snapping is up to ~1 m of aim error at rim speeds.
# `puck_pos` is the walk's origin (the path point at t=0), so an intercept
# inside the first step — the whole near-puck regime — resolves between the
# puck's spot NOW and traj[0].
static func path_intercept_point(traj: Array[Vector3], step_dt: float,
		puck_pos: Vector3, t: float) -> Vector3:
	if traj.is_empty():
		return Vector3.INF
	# traj[i] is the path at (i+1)*step_dt, so time t sits at index t/step_dt − 1;
	# index −1 is the origin.
	var idx: float = t / step_dt - 1.0
	var hi: int = clampi(int(ceil(idx)), 0, traj.size() - 1)
	var lo: int = hi - 1
	var from: Vector3 = traj[lo] if lo >= 0 else puck_pos
	return from.lerp(traj[hi], clampf(idx - float(lo), 0.0, 1.0))


# ── Incidental reach (a free puck at your feet is yours) ─────────────────────
# One stride beyond the blade — the band inside which the election does not
# apply, because whoever the puck comes to plays it. Bounded to reach + a stride
# so it stays "extend the stick", never a second chaser abandoning his job.
const INCIDENTAL_STRIDE_M: float = 1.5


# True when the loose puck's own predicted path crosses inside this skater's
# reach band early enough for him to meet it there. Two physical quantities and
# nothing else: the band is his blade reach plus one stride, and the timing test
# is his calibrated ETA against the puck's own time to the crossing point.
# The body is timed to the crossing itself, not to a blade off it: this read
# overrides the race-lost decline and the one-timer camp, so it holds out for
# a puck the body can get onto, and a feed leaving his own blade is never his.
#
# Segment-wise (closest approach along each step of the walk, not the sampled
# endpoints): at rim speeds the puck covers ~3.75 m per 0.25 s step, so a
# point-sampled band test would step clean OVER a skater the puck passes a
# metre from. No KILL_SETUP_MARGIN_S here — that margin buys the setup skate for
# a kill you have to travel to, and a puck arriving inside your own reach needs
# no travel, just the stick out.
static func puck_comes_to_reach(
		puck_pos: Vector3, puck_vel: Vector3,
		self_pos: Vector3, self_vel: Vector3,
		max_speed: float, reach: float) -> bool:
	return reach_meet_time(race_trajectory(puck_pos, puck_vel), puck_pos, puck_vel,
			self_pos, self_vel, max_speed, reach, false) < INF


# When the puck on `traj` first meets this skater's reach band, by
# puck_comes_to_reach's rule; INF if it never does. `approaching_only` drops a
# meeting at the very start of a path the puck is leaving him along — the
# passer's own blade as the feed goes. `stick_out` times the body only to
# within a blade of the meet, the stick taking the rest: whose a feed is, not
# whether to break off for it.
static func reach_meet_time(traj: Array[Vector3], puck_pos: Vector3, puck_vel: Vector3,
		self_pos: Vector3, self_vel: Vector3, max_speed: float, reach: float,
		approaching_only: bool, stick_out: bool = false) -> float:
	var band: float = reach + INCIDENTAL_STRIDE_M
	var band2: float = band * band
	var step_dt: float = RACE_LOOKAHEAD_S / float(RACE_STEPS)
	# A puck flying through the band is over the stick, not in it: only the
	# path from its landing on counts.
	var t_play: float = race_playable_time(puck_pos, puck_vel)
	var prev: Vector3 = puck_pos
	for i: int in traj.size():
		var t0: float = i * step_dt
		var start: Vector3 = prev
		prev = traj[i]
		if t0 + step_dt < t_play:
			continue
		if t0 < t_play:
			start = path_intercept_point(traj, step_dt, puck_pos, t_play)
		var seg_t0: float = maxf(t0, t_play)
		var f: float = _segment_meet_fraction(start, traj[i], self_pos)
		if approaching_only and i == 0 and f <= 0.0:
			continue
		var meet := Vector3(start.x + (traj[i].x - start.x) * f, 0.0,
				start.z + (traj[i].z - start.z) * f)
		var dx: float = meet.x - self_pos.x
		var dz: float = meet.z - self_pos.z
		var d2: float = dx * dx + dz * dz
		if d2 > band2:
			continue
		var t_meet: float = seg_t0 + (t0 + step_dt - seg_t0) * f
		var stand: Vector3 = meet
		if stick_out:
			var d: float = sqrt(d2)
			if d <= reach:
				return t_meet
			stand = Vector3(meet.x - dx / d * reach, 0.0, meet.z - dz / d * reach)
		if AIArrival.time_to_arrive(self_pos, stand, self_vel, max_speed) <= t_meet:
			return t_meet
	return INF


# ── Teammate yield (Scripts/domain/ai/CLAUDE.md → "Teammates don't stab") ───
# Yielding requires the OTHER blade to be nearer the puck by more than this, a
# relation that cannot hold in both directions, so two bots never both yield.
const YIELD_MARGIN_M: float = 0.25
# How near a teammate's blade must be to the puck to be "on it" at all. Outside
# this he isn't about to take anything, so he can't make anyone yield. Sized
# just past the pickup radius (PuckController.PICKUP_RADIUS, 0.5 m) so it covers
# the blade that is about to make contact and nothing further out.
const YIELD_CONTEST_M: float = 0.7


# Is a teammate's blade clearly first to this loose puck? Reads the host-only
# `blade_contact_world` (the AI runs host-side, so it is populated); a zero
# blade means the field is absent and we simply don't yield.
static func teammate_first_to_puck(
		skater_states: Dictionary, teammate_ids: Array, self_pid: int,
		self_blade: Vector3, puck_pos: Vector3,
		tag_up_peers: Dictionary = _NO_PEERS) -> bool:
	var mine: float = _xz_dist(self_blade, puck_pos)
	for pid: int in teammate_ids:
		if pid == self_pid:
			continue
		var s: SkaterNetworkState = skater_states.get(pid)
		if s == null or s.is_ghost or tag_up_peers.has(pid):
			continue
		var blade: Vector3 = s.blade_contact_world
		if blade == Vector3.ZERO:
			continue
		var theirs: float = _xz_dist(blade, puck_pos)
		if theirs <= YIELD_CONTEST_M and theirs < mine - YIELD_MARGIN_M:
			return true
	return false


static func _xz_dist(a: Vector3, b: Vector3) -> float:
	var dx: float = a.x - b.x
	var dz: float = a.z - b.z
	return sqrt(dx * dx + dz * dz)


# Geometry only: does the walk ever bring the puck inside `band` of `pos`?
# The "does he even have to MOVE to play this?" half of puck_comes_to_reach,
# without the timing test — which is the right question for a body whose
# commitment we're judging rather than our own arrival.
static func path_enters_band(traj: Array[Vector3], puck_pos: Vector3,
		pos: Vector3, band: float) -> bool:
	var band2: float = band * band
	var prev: Vector3 = puck_pos
	for i: int in traj.size():
		var f: float = _segment_meet_fraction(prev, traj[i], pos)
		var dx: float = prev.x + (traj[i].x - prev.x) * f - pos.x
		var dz: float = prev.z + (traj[i].z - prev.z) * f - pos.z
		prev = traj[i]
		if dx * dx + dz * dz <= band2:
			return true
	return false


# Fraction along segment a→b (clamped to the segment) closest to `pos`, XZ only.
static func _segment_meet_fraction(a: Vector3, b: Vector3, pos: Vector3) -> float:
	var seg_x: float = b.x - a.x
	var seg_z: float = b.z - a.z
	var seg_len2: float = seg_x * seg_x + seg_z * seg_z
	if seg_len2 <= 0.000001:
		return 0.0
	return clampf(((pos.x - a.x) * seg_x + (pos.z - a.z) * seg_z) / seg_len2,
			0.0, 1.0)


# Returns the peer_id that should chase the loose puck for this team, or
# -1 if the team has no eligible skater.
#   skater_states  — peer_id -> SkaterNetworkState (the full snapshot map)
#   teammate_ids   — this team's peer_ids
#   puck_pos/_vel  — loose puck world position and velocity (XZ used)
#   prev_elected   — last frame's elected chaser for this team (-1 if none)
#   puck_playable  — false for a DEAD loose puck (goalie smother / phase lock:
#                    pickup_locked with no carrier). Nobody is elected, so every
#                    bot plays its positional role around a covered puck.
#   human_ids      — teammate_ids under HUMAN control. Election can't make a
#                    human skate, so he suppresses the bots only while he is
#                    demonstrably playing the puck (committed_to_race).
#   camped_ids     — teammates opted out of loose-puck work (the one-timer
#                    camp veto). Skipped, so the next-best teammate goes and
#                    a camper cannot be elected into a chase it will refuse.
#                    If the filters exclude EVERYONE the raw election runs
#                    instead — someone must own the read, and the camper's
#                    own veto still governs its behavior.
static func elect(
		skater_states: Dictionary,
		teammate_ids: Array,
		puck_pos: Vector3,
		puck_vel: Vector3,
		prev_elected: int,
		caps_by_peer: Dictionary = {},
		puck_playable: bool = true,
		human_ids: Array = [],
		camped_ids: Array = []) -> int:
	if not puck_playable:
		return -1
	var traj: Array[Vector3] = walk_race(puck_pos, puck_vel)
	var step_dt: float = RACE_LOOKAHEAD_S / float(RACE_STEPS)
	var margin: float = setup_margin(puck_vel)
	var t_play: float = race_playable_time(puck_pos, puck_vel)
	var best_pid: int = -1
	var best_t: float = INF
	for pid: int in teammate_ids:
		var s: SkaterNetworkState = skater_states.get(pid)
		if s == null:
			continue
		if not camped_ids.is_empty() and camped_ids.has(pid):
			continue
		if not human_ids.is_empty() and human_ids.has(pid) \
				and not committed_to_race(s, puck_pos):
			continue
		var caps: AISkaterCaps = caps_by_peer.get(pid)
		var max_speed: float = race_vmax(caps)
		var t: float = path_intercept_time(traj, step_dt, puck_pos,
				s.position, s.velocity, max_speed, margin,
				AIArrival.SHED_ACCEL_DEFAULT_M_S2, 0.0, t_play)
		# A puck coming to his stick is his: the race counts it, the stick taking
		# the last reach, or a pass reaching its man elects someone else to chase
		# it too.
		t = minf(t, reach_meet_time(traj, puck_pos, puck_vel, s.position, s.velocity,
				max_speed, race_reach(caps), true, true))
		if pid != prev_elected:
			t += HYSTERESIS_S
		# Tie-break on the lower peer_id, never iteration order.
		if t < best_t or (t == best_t and (best_pid == -1 or pid < best_pid)):
			best_t = t
			best_pid = pid
	if best_pid == -1 and (not camped_ids.is_empty() or not human_ids.is_empty()):
		# Filters excluded every teammate — fall back to the raw election.
		return elect(skater_states, teammate_ids, puck_pos, puck_vel,
				prev_elected, caps_by_peer)
	return best_pid


# Raw best intercept time (seconds) among `ids` to the loose puck — the
# election's race read with no hysteresis and no winner identity, so a caller can
# compare OUR best against THEIRS through the same model. INF when no eligible
# skater.
static func best_intercept_time(
		skater_states: Dictionary,
		ids: Array,
		puck_pos: Vector3,
		puck_vel: Vector3,
		caps_by_peer: Dictionary = {}) -> float:
	var traj: Array[Vector3] = race_trajectory(puck_pos, puck_vel)
	var step_dt: float = RACE_LOOKAHEAD_S / float(RACE_STEPS)
	var margin: float = setup_margin(puck_vel)
	var t_play: float = race_playable_time(puck_pos, puck_vel)
	var best_t: float = INF
	for pid: int in ids:
		var s: SkaterNetworkState = skater_states.get(pid)
		if s == null:
			continue
		var max_speed: float = race_vmax(caps_by_peer.get(pid))
		var t: float = path_intercept_time(traj, step_dt, puck_pos,
				s.position, s.velocity, max_speed, margin,
				AIArrival.SHED_ACCEL_DEFAULT_M_S2, 0.0, t_play)
		if t < best_t:
			best_t = t
	return best_t


# Should I decline a loose puck? True when a committed opponent reaches it a
# clear contest band (CHASE_CONTEST_MARGIN_M) ahead of me AND nobody else contains
# the counter. Inside the band it is a live 50/50 worth racing.
#
# `own_goal_dir` (+1 = our net at +Z) enables the containment read; 0.0 (unit
# tests only) claims no containment.
static func loose_puck_race_lost(
		snapshot: WorldSnapshot, self_pos: Vector3, self_vel: Vector3,
		self_max_speed: float, team_id: int, team_id_by_peer: Dictionary,
		caps_by_peer: Dictionary, self_pid: int = -1,
		own_goal_dir: float = 0.0) -> bool:
	if snapshot == null or snapshot.puck_state == null:
		return false
	var puck_pos: Vector3 = snapshot.puck_state.position
	# Race the puck's predicted path, never its current position, on the chase
	# election's own walk so the decline cannot contradict it.
	var puck_vel: Vector3 = snapshot.puck_state.velocity
	var traj: Array[Vector3] = AILoosePuckChase.race_trajectory(puck_pos, puck_vel)
	var step_dt: float = AILoosePuckChase.RACE_LOOKAHEAD_S \
			/ float(AILoosePuckChase.RACE_STEPS)
	var margin: float = AILoosePuckChase.setup_margin(puck_vel)
	var t_play: float = AILoosePuckChase.race_playable_time(puck_pos, puck_vel)
	var self_vmax: float = maxf(self_max_speed, 1.0)
	var my_eta: float = AILoosePuckChase.path_intercept_time(
			traj, step_dt, puck_pos, self_pos, self_vel, self_vmax, margin,
			AIArrival.SHED_ACCEL_DEFAULT_M_S2, 0.0, t_play)
	var best_opp_eta: float = INF
	var best_opp_meet: Vector3 = puck_pos
	for pid: int in snapshot.skater_states:
		if team_id_by_peer.get(pid, -1) == team_id:
			continue
		var s: SkaterNetworkState = snapshot.skater_states[pid]
		# Lost only to an opponent RUNNING it: the ETA prices a hypothetical run,
		# so a flat-footed body off the line would otherwise veto the chase. A
		# downstream interceptor whose band the puck's path enters counts.
		var speed: float = AILoosePuckChase.race_vmax(caps_by_peer.get(pid))
		var t: float = AILoosePuckChase.path_intercept_time(
				traj, step_dt, puck_pos, s.position, s.velocity, speed, margin,
				AIArrival.SHED_ACCEL_DEFAULT_M_S2, 0.0, t_play)
		var meet: Vector3 = AILoosePuckChase.path_intercept_point(
				traj, step_dt, puck_pos, t)
		var committed: bool = AILoosePuckChase.path_enters_band(traj, puck_pos,
				s.position, AIActionScoring.CHASE_CONTEST_MARGIN_M) \
				or AILoosePuckChase.committed_to_point(s, meet)
		if not committed:
			continue
		if t < best_opp_eta:
			best_opp_eta = t
			best_opp_meet = meet
	if best_opp_eta == INF:
		return false
	var contest_window: float = AIActionScoring.CHASE_CONTEST_MARGIN_M \
			/ maxf(self_max_speed, 1.0)
	if my_eta <= best_opp_eta + contest_window:
		return false
	# Declining buys a pre-contain body, worth it only when nobody else contains.
	return not _has_containment_behind(snapshot, team_id, team_id_by_peer,
			self_pid, best_opp_meet, own_goal_dir)


# Is someone else covering the counter, so that leaving to chase is free? A live
# teammate qualifies if he is GOAL-SIDE of the pickup, or can reach the HOUSE GATE
# inside AIRushRead.LATE_MAN_WINDOW_S — the second because nothing can be
# goal-side of a puck behind our own goal line.
#
# Never re-phrase this as a race to the pickup: behind our goal line the pickup
# IS our net, so the collector is already home and nobody beats him there.
static func _has_containment_behind(snapshot: WorldSnapshot, team_id: int,
		team_id_by_peer: Dictionary, self_pid: int, pickup: Vector3,
		own_goal_dir: float) -> bool:
	if own_goal_dir == 0.0:
		return false
	var gate := Vector3(0.0, 0.0, own_goal_dir
			* (GameRules.GOAL_LINE_Z - AIZoneCoverage.HOUSE_TOP_DEPTH_M))
	for pid: int in snapshot.skater_states:
		if pid == self_pid or team_id_by_peer.get(pid, -1) != team_id:
			continue
		var mate: SkaterNetworkState = snapshot.skater_states[pid]
		if mate.is_ghost:
			continue
		if own_goal_dir * (mate.position.z - pickup.z) \
				> AIActionScoring.CHASE_CONTEST_MARGIN_M:
			return true
		if AIArrival.time_to_arrive(mate.position, gate, mate.velocity) \
				<= AIRushRead.LATE_MAN_WINDOW_S:
			return true
	return false
