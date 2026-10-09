class_name AIRimPass

# The rim pass: a puck fired into the near boards so the boards carry it to a
# teammate — up the wall to the half-wall winger, around the end boards to the
# weak side, behind the net to the partner D. A straight pass prices a line; a
# rim's lane IS the boards, so it is searched as a RELEASE (bearing at the
# quick-pass pace) and walked on the puck's predicted path — friction and board
# caroms, the same walk the chase election races on, at the same resolution, so
# the receiver the rim is priced to reach is the one the election will send.
#
# Rims are fired HARD — the boards and the corner arcs bleed pace on every
# contact — so the search runs a pace ladder up to the passer's own wrister max
# and keeps only arrivals the receiver can catch: the puck's speed in his frame
# under the deflect threshold.
#
# This file is the path half: which launches are rims, where each one goes, and
# who reaches it first. What a rim is WORTH stays in the carrier's pass EV
# (AIRoleCarrier._rim_variant_ev), so it competes with the flat feed and the
# saucer in one currency.
#
# A launch is a rim when its first board contact is near the passer and
# glancing, so the boards carry it rather than turning it back into the middle.
# Both are sampling bounds — which bearings to walk — not evaluation: whatever
# survives is priced on the race along its own path.

# Bearings sampled around the passer, and the pace ladder (fractions of the
# passer's wrister max) each surviving bearing is walked at.
const BEARINGS: int = 16
const PACE_FRACS: Array[float] = [0.7, 1.0]
# The bank must come within this distance of the release: a rim is fired INTO
# the boards beside the passer, not a long dump that happens to find them.
const BANK_MAX_M: float = 10.0
# Incidence off the boards' tangent beyond which the carom throws the puck back
# into the middle (a bank pass across the zone, not a rim).
const GLANCE_MAX_RAD: float = deg_to_rad(40.0)
# At most this many launches survive the bounds (scratch is preallocated).
const MAX_LAUNCHES: int = 12
# Aim distance handed to the release: the quick release fires toward a point,
# and any point down the bearing is the same release.
const AIM_DISTANCE_M: float = 20.0

# Their keeper's behind-net rim stop, mirrored from GoalieController's puck-play
# defaults (test_rim_pass.gd holds the two together): the rim pace window he
# will stop, how early he must be set, the beat he takes stopping it, and the
# sprint he assumes of the nearest of us. His GO margin is tiered and lives on
# AIActionScoring.goalie_puck_play_go_margin_s.
const KEEPER_RIM_MIN_SPEED_M_S: float = 4.0
const KEEPER_RIM_MAX_SPEED_M_S: float = 22.0
const KEEPER_SET_BEAT_S: float = 0.15
const KEEPER_STOP_BEAT_S: float = 0.25
const KEEPER_PRESSURE_SPEED_M_S: float = 11.0

# Walk resolution — the chase election's own, so "who meets it" here and "who
# is elected to go" can never disagree.
const STEPS: int = AILoosePuckChase.RACE_STEPS
const STEP_DT: float = AILoosePuckChase.RACE_LOOKAHEAD_S / float(AILoosePuckChase.RACE_STEPS)

# ── Scratch (filled by build, read until the next build) ─────────────────────
static var count: int = 0
static var origin: Vector3 = Vector3.ZERO
static var dirs: Array[Vector3] = []
static var paces: Array[float] = []
# Path per launch: paths[k][i] is the puck at (i+1)·STEP_DT, speeds[k][i] its
# speed there.
static var paths: Array = []
static var speeds: Array = []
# Soonest opponent arrival on each launch's path — their keeper included, who
# plays a rim behind his net — and where he meets it. Raced LAZILY (opp_time):
# only a launch some receiver can actually meet pays for it.
static var opp_t: Array[float] = []
static var opp_meet: Array[Vector3] = []
static var _opp_raced: Array[bool] = []
# The race inputs, held by reference from build() for the lazy race — the
# caller's arrays, live for the compete that called build().
static var _opp_positions: Array[Vector3] = []
static var _opp_vels: Array[Vector3] = []
static var _opp_caps: Array[AISkaterCaps] = []
static var _keeper_pos: Vector3 = Vector3.INF
static var _ours: Array[Vector3] = []


static func _ensure_scratch() -> void:
	if paths.size() == MAX_LAUNCHES:
		return
	dirs.resize(MAX_LAUNCHES)
	paces.resize(MAX_LAUNCHES)
	opp_t.resize(MAX_LAUNCHES)
	opp_meet.resize(MAX_LAUNCHES)
	_opp_raced.resize(MAX_LAUNCHES)
	paths.clear()
	speeds.clear()
	for _k: int in MAX_LAUNCHES:
		var p: Array[Vector3] = []
		p.resize(STEPS)
		paths.append(p)
		var v: Array[float] = []
		v.resize(STEPS)
		speeds.append(v)


# Searches the rim launches from `from` up to `max_pace` and races every
# opponent on each one. Returns the number of launches (0 when the passer is nowhere near
# the boards). A launch survives only if no leg of its path runs through a net
# or across our own slot (`own_goal_z`), which the puck walk itself does not
# model. `opp_*` are index-matched; caps may be null (league default).
# `keeper_pos` is their goalie (INF = none), and `ours` our other skaters, whom
# he races home against before he leaves his net.
static func build(from: Vector3, max_pace: float, own_goal_z: float,
		opp_positions: Array[Vector3], opp_vels: Array[Vector3],
		opp_caps: Array[AISkaterCaps], keeper_pos: Vector3 = Vector3.INF,
		ours: Array[Vector3] = AIActionScoring.EMPTY_VEC3) -> int:
	_ensure_scratch()
	count = 0
	origin = Vector3(from.x, 0.0, from.z)
	_opp_positions = opp_positions
	_opp_vels = opp_vels
	_opp_caps = opp_caps
	_keeper_pos = keeper_pos
	_ours = ours
	if AICarrySpace.board_gap_m(origin) > BANK_MAX_M:
		return 0
	var o2 := Vector2(origin.x, origin.z)
	var sin_glance: float = sin(GLANCE_MAX_RAD)
	for b: int in BEARINGS:
		if count >= MAX_LAUNCHES:
			break
		var a: float = TAU * float(b) / float(BEARINGS)
		var d2 := Vector2(cos(a), sin(a))
		var bank: float = GameRules.ray_to_rink_inner(
				o2, d2, GameRules.PUCK_COLLISION_RADIUS)
		if bank > BANK_MAX_M:
			continue
		var hit: Vector2 = o2 + d2 * bank
		if absf(d2.dot(_inward_normal(hit))) > sin_glance:
			continue
		var dir := Vector3(d2.x, 0.0, d2.y)
		for frac: float in PACE_FRACS:
			if count >= MAX_LAUNCHES:
				break
			if not _walk(count, dir * (max_pace * frac), own_goal_z):
				break   # a leg through a net or our slot is so at every pace
			dirs[count] = dir
			paces[count] = max_pace * frac
			_opp_raced[count] = false
			count += 1
	return count


# The receiver's (or anyone's) meet time on launch `k`, at the race read the
# election uses. INF when he never makes it inside the walk.
static func meet_time(k: int, pos: Vector3, vel: Vector3, max_speed: float) -> float:
	var path: Array[Vector3] = paths[k]
	var t: float = AILoosePuckChase.path_intercept_time(path, STEP_DT, origin,
			pos, vel, max_speed, AILoosePuckChase.setup_margin(dirs[k] * paces[k]))
	return t if t < float(STEPS) * STEP_DT else INF


static func meet_point(k: int, t: float) -> Vector3:
	return AILoosePuckChase.path_intercept_point(paths[k], STEP_DT, origin, t)


# Can a receiver moving at `recv_vel` catch launch `k` at time `t`: the puck's
# speed in his frame under the deflect threshold (Puck.deflect_min_speed's
# domain mirror)? The heading is the walked segment the meet falls in.
static func catchable(k: int, t: float, recv_vel: Vector3) -> bool:
	var path: Array[Vector3] = paths[k]
	var spd: Array[float] = speeds[k]
	var i: int = clampi(int(ceil(t / STEP_DT)) - 1, 0, STEPS - 1)
	var from: Vector3 = path[i - 1] if i > 0 else origin
	var seg := Vector3(path[i].x - from.x, 0.0, path[i].z - from.z)
	if seg.length_squared() < 0.000001:
		return true
	var v: Vector3 = seg.normalized() * spd[i]
	var rel := Vector2(v.x - recv_vel.x, v.z - recv_vel.z)
	return rel.length() < AIActionScoring.TIP_DEFLECT_MIN_SPEED_M_S


# Path length up to time `t` — the distance the passer's aim error is spread over.
static func path_length(k: int, t: float) -> float:
	var path: Array[Vector3] = paths[k]
	var length: float = 0.0
	var prev: Vector3 = origin
	for i: int in STEPS:
		var t_i: float = float(i + 1) * STEP_DT
		if t_i >= t:
			var f: float = clampf((t - float(i) * STEP_DT) / STEP_DT, 0.0, 1.0)
			return length + AIRoleHelpers.xz_distance(prev, path[i]) * f
		length += AIRoleHelpers.xz_distance(prev, path[i])
		prev = path[i]
	return length


# True when launch `k`'s path stays on the attacking side of the blue line
# (`buffer` inside it) up to time `t` — a rim must not take the puck out of the
# zone on its way to the receiver.
static func stays_in_zone(k: int, t: float, attacking_goal: Vector3,
		buffer: float) -> bool:
	var path: Array[Vector3] = paths[k]
	for i: int in STEPS:
		if float(i) * STEP_DT > t:
			break
		if not AIActionScoring.in_offensive_zone(path[i], attacking_goal, buffer):
			return false
	return true


# Race completion: the receiver against the soonest opponent on the same path,
# in the contest band the dump's chase_recovery prices with — one currency for
# "who gets to a loose puck first".
static func race_completion(k: int, receiver_t: float) -> float:
	var t_opp: float = opp_time(k)
	if t_opp == INF:
		return 1.0
	return clampf(0.5 + (t_opp - receiver_t)
			/ (2.0 * AIActionScoring.CHASE_CONTEST_MARGIN_S), 0.0, 1.0)


# The soonest opponent arrival on launch `k` (INF = nobody), raced on first ask.
static func opp_time(k: int) -> float:
	if not _opp_raced[k]:
		_opp_raced[k] = true
		_race_opponents(k, _opp_positions, _opp_vels, _opp_caps, _keeper_pos, _ours)
	return opp_t[k]


static func _walk(k: int, vel: Vector3, own_goal_z: float) -> bool:
	var path: Array[Vector3] = paths[k]
	var spd: Array[float] = speeds[k]
	var p: Vector3 = origin
	var v: Vector3 = vel
	for i: int in STEPS:
		var stepped: Transform3D = AITrajectory.step_puck(p, v, STEP_DT)
		if _leg_near_middle(p, stepped.origin) \
				and (AIActionScoring.pass_lane_blocked_by_net(p, stepped.origin)
				or AIActionScoring.pass_crosses_own_slot(p, stepped.origin, own_goal_z)):
			return false
		p = stepped.origin
		v = stepped.basis.x
		path[i] = p
		spd[i] = Vector2(v.x, v.z).length()
	return true


# Can the leg a→b touch the middle lane the nets and our slot sit in? Exact
# prune for the two segment tests: a leg with both ends on the same side,
# outside the wider of the two, cannot reach either.
static func _leg_near_middle(a: Vector3, b: Vector3) -> bool:
	var half_w: float = maxf(AIActionScoring.OWN_DZ_SLOT_HALF_WIDTH_M,
			GameRules.NET_BACK_HALF_WIDTH + GameRules.PUCK_COLLISION_RADIUS)
	return not ((a.x > half_w and b.x > half_w) or (a.x < -half_w and b.x < -half_w))


static func _race_opponents(k: int, opp_positions: Array[Vector3],
		opp_vels: Array[Vector3], opp_caps: Array[AISkaterCaps],
		keeper_pos: Vector3, ours: Array[Vector3]) -> void:
	var path: Array[Vector3] = paths[k]
	var margin: float = AILoosePuckChase.setup_margin(dirs[k] * paces[k])
	var best: float = INF
	for i: int in opp_positions.size():
		var caps: AISkaterCaps = opp_caps[i] if i < opp_caps.size() else null
		var speed: float = caps.max_speed if caps != null \
				else AIActionScoring.SKATER_REF_SPEED_M_S
		var vel: Vector3 = opp_vels[i] if i < opp_vels.size() else Vector3.ZERO
		var t: float = AILoosePuckChase.path_intercept_time(path, STEP_DT, origin,
				opp_positions[i], vel, speed, margin)
		if t < best:
			best = t
	best = minf(best, _keeper_time(k, keeper_pos, ours))
	opp_t[k] = best if best < float(STEPS) * STEP_DT else INF
	opp_meet[k] = meet_point(k, best) if opp_t[k] < INF else Vector3.INF


# Earliest walk step behind his own goal line where their keeper stops the rim,
# by the live trip's own gates: a pace he will stop, set there before it arrives
# (leaving the paint from rest at a keeper's puck-play build), and the whole trip
# — out, stop, back — inside his GO margin of the nearest of us sprinting to the
# spot. INF when he stays home, which is every rim for a tier that never plays
# the puck.
static func _keeper_time(k: int, keeper_pos: Vector3, ours: Array[Vector3]) -> float:
	var margin: float = AIActionScoring.goalie_puck_play_go_margin_s
	if not keeper_pos.is_finite() or is_inf(margin):
		return INF
	var path: Array[Vector3] = paths[k]
	var spd: Array[float] = speeds[k]
	for i: int in STEPS:
		var p: Vector3 = path[i]
		if absf(p.z) < GameRules.GOAL_LINE_Z or signf(p.z) != signf(keeper_pos.z):
			continue
		if spd[i] < KEEPER_RIM_MIN_SPEED_M_S or spd[i] > KEEPER_RIM_MAX_SPEED_M_S:
			continue
		var t_out: float = GoalieBehaviorRules.travel_time_from_rest(
				maxf(AIRoleHelpers.xz_distance(keeper_pos, p)
						- AIActionScoring.GOALIE_PUCK_PLAY_REACH_M, 0.0),
				AIActionScoring.GOALIE_PUCK_PLAY_SPEED_M_S,
				AIActionScoring.GOALIE_PUCK_PLAY_ACCEL_M_S2)
		var t_i: float = float(i + 1) * STEP_DT
		if t_out + KEEPER_SET_BEAT_S > t_i:
			continue
		var nearest: float = AIRoleHelpers.xz_distance(origin, p)
		for q: Vector3 in ours:
			nearest = minf(nearest, AIRoleHelpers.xz_distance(q, p))
		if nearest / KEEPER_PRESSURE_SPEED_M_S \
				> 2.0 * t_out + KEEPER_STOP_BEAT_S + margin:
			return t_i
	return INF


# Inward unit normal of the boards at a point on them: the corner arc's radius
# in a corner quadrant, the straight wall's axis elsewhere.
static func _inward_normal(hit: Vector2) -> Vector2:
	var ax: float = absf(hit.x)
	var az: float = absf(hit.y)
	if ax > GameRules.CORNER_CENTER_X and az > GameRules.CORNER_CENTER_Z:
		var c := Vector2(signf(hit.x) * GameRules.CORNER_CENTER_X,
				signf(hit.y) * GameRules.CORNER_CENTER_Z)
		return (c - hit).normalized()
	if GameRules.INNER_HALF_WIDTH - ax < GameRules.INNER_HALF_LENGTH - az:
		return Vector2(-signf(hit.x), 0.0)
	return Vector2(0.0, -signf(hit.y))
