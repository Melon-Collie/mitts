class_name AICarrierDumpSearch
extends RefCounted

# The dump-in: the puck released into their zone with nobody's tape to aim at,
# priced as the race for where it is played. See Scripts/domain/ai/CLAUDE.md →
# "A dump-in is a race for where it is played".
#
# Searched as releases — an aim point in their zone × a pace — each walked on the
# puck's path (AITrajectory.step_puck, the chase election's walk and resolution)
# and raced by the soonest body of each side on that path. The side that meets
# it first plays it there:
#
#   value = p · ours(meet) − (1 − p) · theirs(meet)
#
# with p the arrival race in the contest band AIActionScoring.arrival_race
# prices with (widened by the arrival clock's own error over the trip; their
# keeper races it too, for any of the path in front of his goal line he can push
# and reach out to), ours the
# possession of the spot on arrival (AIPossessionValue) or the feed it opens to
# the support arriving with the dump, its reception raced (_support_from),
# theirs a turnover there
# (AICarrierField.turnover_cost + the 5v5 counter exposure). An iced puck (NHL,
# released from our half, untouched past their goal line) whose dot race their
# side wins is a faceoff at our end, a coin flip there.
#
# Reads the field, writes only its own results; never names AIRoleCarrier
# (test_carrier_collaborator_seams.gd).

# Aim points in their zone, as (x as a share of the inner half-width, depth off
# their goal line in metres; negative is behind it): the two corners, the end
# boards behind the net (a rim round), and each wall at the top of the circles
# (a chip in off the boards). The strong-side mirror is taken by x's sign.
const AIM_POINTS: Array[Vector2] = [
	Vector2(0.85, -2.0), Vector2(-0.85, -2.0),
	Vector2(0.0, -3.0),
	Vector2(1.0, 8.0), Vector2(-1.0, 8.0),
]
# Paces, as shares of the carrier's wrister max: a soft dump that dies in the
# zone, and a hard rim round the boards.
const PACE_FRACS: Array[float] = [0.6, 1.0]

# Walk resolution — the chase election's own, so who the dump is priced to reach
# first is who the election sends.
const STEPS: int = AILoosePuckChase.RACE_STEPS
const STEP_DT: float = AILoosePuckChase.RACE_LOOKAHEAD_S / float(AILoosePuckChase.RACE_STEPS)

# Never priced (each price is a possession read on both sides): a launch we
# never win (its value is at most p · ours, so it cannot clear the bar), or one
# we would play before it is in their zone — a chip to ourselves is a carry's
# business, not a dump-in.
const _MAX_LAUNCHES: int = 10   # AIM_POINTS × PACE_FRACS (test_carrier_dump_search.gd)

# ── Results (valid after search) ─────────────────────────────────────────────
# The best release's value, −INF when there is none to make.
var best_score: float = -INF
var best_dir: Vector3 = Vector3.ZERO
var best_pace: float = 0.0
# Where and when our side plays the best release, on our win.
var best_meet: Vector3 = Vector3.INF
var best_meet_s: float = INF

var _field: AICarrierField
var _path: Array[Vector3] = []
# Our skaters at the release (the carrier carried on through his windup) and
# their velocities and caps, index-matched; refilled each search.
var _our_pos: Array[Vector3] = []
var _our_vel: Array[Vector3] = []
var _our_caps: Array[AISkaterCaps] = []
# Our side and the defence where they will be when the puck is played (the
# race's horizon), and the shot each of ours would get there; index-matched to
# _our_pos.
var _our_then: Array[Vector3] = []
var _our_then_val: Array[float] = []
var _opp_then: Array[Vector3] = []
# Which of _our_pos meets each raced launch first (its retriever).
var _retriever: Array[int] = []
# Per raced launch (index-matched, _count of them): its bearing and pace, the
# odds our side plays it first, who meets it where and when, whether it ices,
# and whether it goes unpriced (see _MAX_LAUNCHES).
var _count: int = 0
var _dir: Array[Vector3] = []
var _pace: Array[float] = []
var _p: Array[float] = []
var _meet_ours: Array[Vector3] = []
var _meet_theirs: Array[Vector3] = []
var _t_ours: Array[float] = []
var _ours_vel: Array[Vector3] = []
var _iced: Array[bool] = []
var _skip: Array[bool] = []


func _init(field: AICarrierField) -> void:
	_field = field
	_path.resize(STEPS)
	_dir.resize(_MAX_LAUNCHES)
	_pace.resize(_MAX_LAUNCHES)
	_p.resize(_MAX_LAUNCHES)
	_meet_ours.resize(_MAX_LAUNCHES)
	_meet_theirs.resize(_MAX_LAUNCHES)
	_t_ours.resize(_MAX_LAUNCHES)
	_ours_vel.resize(_MAX_LAUNCHES)
	_iced.resize(_MAX_LAUNCHES)
	_skip.resize(_MAX_LAUNCHES)
	_retriever.resize(_MAX_LAUNCHES)


# Whether a dump-in is a play at all: the puck in the neutral zone, and nothing
# owed at the line (a delayed offside keeps the puck out).
static func is_on(ctx: RoleContext, puck: Vector3) -> bool:
	return not ctx.zone_entry_blocked \
			and not AIActionScoring.in_offensive_zone(puck, ctx.attacking_goal_pos) \
			and not AIActionScoring.in_offensive_zone(puck, ctx.defending_goal_pos)


func search(ctx: RoleContext) -> void:
	best_score = -INF
	best_dir = Vector3.ZERO
	best_pace = 0.0
	best_meet = Vector3.INF
	best_meet_s = INF
	_count = 0
	if ctx.snapshot == null or ctx.snapshot.puck_state == null:
		return
	var origin: Vector3 = AICarrierField.pass_origin(ctx)
	if not is_on(ctx, origin):
		return
	_fill_ours(ctx)
	var attack_z: float = signf(ctx.attacking_goal_pos.z)
	var half: float = GameRules.INNER_HALF_WIDTH - GameRules.PUCK_COLLISION_RADIUS
	for aim2: Vector2 in AIM_POINTS:
		var aim := Vector3(aim2.x * half, 0.0,
				attack_z * (GameRules.GOAL_LINE_Z - aim2.y))
		var to_aim := Vector3(aim.x - origin.x, 0.0, aim.z - origin.z)
		if to_aim.length_squared() < 1.0:
			continue
		var dir: Vector3 = to_aim.normalized()
		for frac: float in PACE_FRACS:
			var pace: float = ctx.self_wrister_shot_speed * frac
			if not _walk(origin, dir * pace):
				break   # a leg through a net here is one at every harder pace
			_race(ctx, origin, dir, pace)

	var iced_value: float = INF
	var support_filled: bool = false
	for k: int in _count:
		if _skip[k]:
			continue
		var v: float
		if _iced[k]:
			if iced_value == INF:
				iced_value = _icing_value(ctx, origin)
			v = iced_value
		else:
			if not support_filled:
				_fill_support(ctx)
				support_filled = true
			v = _value(ctx, k)
		if v > best_score:
			best_score = v
			best_dir = _dir[k]
			best_pace = _pace[k]
			best_meet = _meet_ours[k]
			best_meet_s = _t_ours[k]


# Races the release just walked and records it (see the per-launch arrays). Our
# side first: a launch we would play short of their line is a chip to ourselves
# (see _MAX_LAUNCHES), and theirs is not raced for it.
func _race(ctx: RoleContext, origin: Vector3, dir: Vector3, pace: float) -> void:
	var margin: float = AILoosePuckChase.setup_margin(dir * pace)
	var walk_s: float = float(STEPS) * STEP_DT
	var t_ours: float = INF
	var ours_vel := Vector3.ZERO
	var retriever: int = -1
	for i: int in _our_pos.size():
		var caps: AISkaterCaps = _our_caps[i]
		var t: float = AILoosePuckChase.path_intercept_time(_path, STEP_DT, origin,
				_our_pos[i], _our_vel[i],
				caps.max_speed if caps != null else AIArrival.SKATER_REF_SPEED_M_S, margin)
		if t < t_ours:
			t_ours = t
			ours_vel = _our_vel[i]
			retriever = i
	var meet_ours: Vector3 = _path[STEPS - 1]
	if t_ours < walk_s:
		meet_ours = AILoosePuckChase.path_intercept_point(_path, STEP_DT, origin, t_ours)
	var k: int = _count
	_count += 1
	_dir[k] = dir
	_pace[k] = pace
	_retriever[k] = retriever
	_skip[k] = not AIActionScoring.in_offensive_zone(meet_ours, ctx.attacking_goal_pos)
	if _skip[k]:
		return
	var t_theirs: float = INF
	for i: int in _field.opponents_release.size():
		var caps: AISkaterCaps = _field.opponent_caps[i]
		t_theirs = minf(t_theirs, AILoosePuckChase.path_intercept_time(_path, STEP_DT,
				origin, _field.opponents_release[i], _field.opponent_vels[i],
				caps.max_speed if caps != null else AIArrival.SKATER_REF_SPEED_M_S,
				margin))
	var keeper_t: float = _keeper_time(ctx)
	t_theirs = minf(t_theirs, keeper_t)
	var meet_theirs: Vector3 = _path[STEPS - 1]
	if t_theirs < walk_s:
		meet_theirs = AILoosePuckChase.path_intercept_point(_path, STEP_DT, origin, t_theirs)
	if t_ours >= walk_s and t_theirs >= walk_s:
		# Nobody meets it in the walk: it is played where it comes to rest, by
		# their keeper too if he is on it there.
		t_ours = maxf(walk_s, _first_to(meet_ours, _our_pos, _our_vel, _our_caps))
		t_theirs = maxf(walk_s, minf(keeper_t, _first_to(meet_theirs,
				_field.opponents_release, _field.opponent_vels, _field.opponent_caps)))
	# The clock's error is a skate mis-timed seconds out; their keeper on his
	# crease is no such skate.
	var band: float = AIActionScoring.CHASE_CONTEST_MARGIN_S
	if keeper_t > t_theirs:
		band += AIArrival.ERROR_FRAC * minf(maxf(t_ours, t_theirs), 1e6)
	_p[k] = clampf(0.5 + (t_theirs - t_ours) / (2.0 * band), 0.0, 1.0)
	_meet_ours[k] = meet_ours
	_meet_theirs[k] = meet_theirs
	_t_ours[k] = t_ours
	_ours_vel[k] = ours_vel
	_iced[k] = ctx.icing_enforced and _ices(ctx, origin, minf(t_ours, t_theirs))
	_skip[k] = _p[k] <= 0.0


# Launch `k`'s value (see the header).
func _value(ctx: RoleContext, k: int) -> float:
	var lost: float = 1.0 - _p[k]
	var ours: float = maxf(_field.possession_at(_meet_ours[k], _t_ours[k], _ours_vel[k]),
			_support_from(ctx, _meet_ours[k], _retriever[k], _t_ours[k]) \
					* AIActionScoring.delay_discount(_t_ours[k]))
	return _p[k] * ours \
			- _field.turnover_cost(_meet_theirs[k], lost) \
			- _field.counter_exposure_cost(ctx, _meet_theirs[k], lost, ctx.self_pos,
					AIRoleReads.resolve_our_goalie_pos(ctx))


# When their keeper first gets a stick on the path just walked: a point in front
# of his goal line inside what his push and his stick reach by then (INF: none).
# Unreplicated, he is home on his crease. He plays no puck behind his net.
func _keeper_time(ctx: RoleContext) -> float:
	var goal: Vector3 = ctx.attacking_goal_pos
	var attack_z: float = signf(goal.z)
	var keeper := Vector3(goal.x, 0.0, goal.z - attack_z * AIGoalieModel.GOALIE_RESTING_DEPTH_M)
	var gs: GoalieNetworkState = ctx.snapshot.goalie_states.get(1 - ctx.team_id)
	if gs != null:
		keeper = Vector3(gs.position_x, 0.0, gs.position_z)
	for i: int in STEPS:
		var p: Vector3 = _path[i]
		if p.z * attack_z >= GameRules.GOAL_LINE_Z:
			continue
		var t: float = float(i + 1) * STEP_DT
		if AIRoleReads.xz_distance(p, keeper) <= AIGoalieModel.goalie_lateral_reach(t) \
				+ AIBotMechanics.BLADE_REACH_M:
			return t
	return INF


# Whether the release just walked ices: from our half and across their goal line
# before anyone plays it (`touched_s`), with our side not first to the end-zone
# dots by the clear margin.
func _ices(ctx: RoleContext, origin: Vector3, touched_s: float) -> bool:
	var attack_z: float = signf(ctx.attacking_goal_pos.z)
	if not InfractionRules.behind_red_line(origin.z, attack_z):
		return false
	var crossed_s: float = INF
	for i: int in STEPS:
		if _path[i].z * attack_z > GameRules.GOAL_LINE_Z:
			crossed_s = float(i + 1) * STEP_DT
			break
	if crossed_s >= touched_s:
		return false
	var dot_z: float = attack_z * GameRules.ICING_FACEOFF_DOT_Z
	var ours: float = _first_to_line(dot_z, _our_pos, _our_vel, _our_caps)
	var theirs: float = _first_to_line(dot_z, _field.opponents_release,
			_field.opponent_vels, _field.opponent_caps)
	return ours + GameRules.ICING_RACE_CLEAR_MARGIN_S > theirs


# An icing called: a faceoff at our end's dot — a coin flip for a possession
# that is theirs there.
func _icing_value(ctx: RoleContext, origin: Vector3) -> float:
	var dot2: Vector2 = GameRules.icing_faceoff_dot(ctx.team_id, origin.x)
	return -_field.turnover_cost(Vector3(dot2.x, 0.0, dot2.y), 0.5)


# Our side and the defence dead-reckoned to the race's horizon, and the shot each
# of ours who is in their zone by then would get there (0 for one who is not).
# A won dump is worth the support that arrives with it: in the shot currency a
# puck behind their goal line is otherwise worth nothing, as one man there
# carrying has no shot.
func _fill_support(ctx: RoleContext) -> void:
	var horizon: float = float(STEPS) * STEP_DT
	_field.project_opponents(horizon, _opp_then)
	_our_then.clear()
	_our_then_val.clear()
	var keeper: Vector3 = AICarrierField.goalie_now(ctx)
	var half: float = GameRules.INNER_HALF_WIDTH - AIStationSearch.RINK_INSET_M
	var deepest: float = GameRules.GOAL_LINE_Z - AIStationSearch.GOAL_LINE_BUFFER_M
	var attack_z: float = signf(ctx.attacking_goal_pos.z)
	for i: int in _our_pos.size():
		var p: Vector3 = AITrajectory.predict_at(_our_pos[i], _our_vel[i], horizon)
		p.x = clampf(p.x, -half, half)
		p.z = attack_z * minf(attack_z * p.z, deepest)
		_our_then.append(p)
		_our_then_val.append(AIActionScoring.score_shoot_value(p, ctx.attacking_goal_pos,
				keeper, _opp_then, 0.0, AIShotOdds.Stance.UPRIGHT,
				AIBotMechanics.WRISTER_SHOT_SPEED_M_S, _field.opponent_caps)
				if AIActionScoring.in_offensive_zone(p, ctx.attacking_goal_pos) else 0.0)


# The best feed the retriever (`retriever`, an index into _our_pos) has from
# `meet`, played `meet_s` from now, to the support (_fill_support): its shot ×
# the lane against the defence then × the pass landing × the flight × the race
# for the reception, as a future action (AICarrierField.PASS_OPTION_DISCOUNT,
# the carry's pass option). The reception's race is their first body from the
# release against the feed arriving with our man there.
func _support_from(ctx: RoleContext, meet: Vector3, retriever: int, meet_s: float) -> float:
	var best: float = 0.0
	for i: int in _our_then.size():
		if i == retriever or _our_then_val[i] * AICarrierField.PASS_OPTION_DISCOUNT <= best:
			continue
		var to: Vector3 = _our_then[i]
		if AINetObstacle.pass_lane_blocked_by_net(meet, to):
			continue
		var dist: float = meet.distance_to(to)
		var speed: float = AIPuckLane.expected_pass_speed(meet, to)
		var flight: float = dist / maxf(speed, 1.0)
		var received_s: float = maxf(meet_s + flight,
				AIArrival.time_to_arrive(_our_pos[i], to, _our_vel[i]))
		var option: float = _our_then_val[i] \
				* AIPuckLane.lane_clear(meet, to, _opp_then, speed,
						AIActionScoring.EMPTY_VEC3, _field.opponent_caps) \
				* (1.0 - AIPuckLane.pass_miss_prob(dist, ctx.self_pass_aim_error_rad)) \
				* AIActionScoring.delay_discount(flight) \
				* AICarrierField.PASS_OPTION_DISCOUNT
		if option <= best:
			continue
		option *= AIActionScoring.arrival_race(to, received_s, _field.opponents_release,
				_field.opponent_vels, true)
		best = maxf(best, option)
	return best


# Our side at the release: the teammates who may play the puck, read where their
# momentum has them through the windup, and the carrier carried on through it.
func _fill_ours(ctx: RoleContext) -> void:
	_our_pos.clear()
	_our_vel.clear()
	_our_caps.clear()
	var lead: float = AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S
	for pid: int in ctx.snapshot.skater_states:
		if ctx.team_id_by_peer.get(pid, -1) != ctx.team_id:
			continue
		if pid != ctx.peer_id and ctx.snapshot.is_out_of_play(pid):
			continue
		var s: SkaterNetworkState = ctx.snapshot.skater_states[pid]
		_our_pos.append(AITrajectory.predict_at(s.position, s.velocity, lead))
		_our_vel.append(s.velocity)
		_our_caps.append(ctx.caps_by_peer.get(pid))


# The puck's path from `origin` at `vel`, into _path. False when a leg runs
# through a net, which the walk itself does not model.
func _walk(origin: Vector3, vel: Vector3) -> bool:
	var p: Vector3 = origin
	var v: Vector3 = vel
	for i: int in STEPS:
		var stepped: Transform3D = AITrajectory.step_puck(p, v, STEP_DT)
		if AINetObstacle.pass_lane_blocked_by_net(p, stepped.origin):
			return false
		p = stepped.origin
		v = stepped.basis.x
		_path[i] = p
	return true


static func _first_to(target: Vector3, pos: Array[Vector3], vel: Array[Vector3],
		caps: Array[AISkaterCaps]) -> float:
	var best: float = INF
	for i: int in pos.size():
		var c: AISkaterCaps = caps[i]
		best = minf(best, AIArrival.time_to_arrive(pos[i], target, vel[i],
				c.max_speed if c != null else AIArrival.SKATER_REF_SPEED_M_S))
	return best


# Soonest of `pos` to the line z = `line_z`, straight down the ice.
static func _first_to_line(line_z: float, pos: Array[Vector3], vel: Array[Vector3],
		caps: Array[AISkaterCaps]) -> float:
	var best: float = INF
	for i: int in pos.size():
		var c: AISkaterCaps = caps[i]
		best = minf(best, AIArrival.time_to_arrive(pos[i], Vector3(pos[i].x, 0.0, line_z),
				vel[i], c.max_speed if c != null else AIArrival.SKATER_REF_SPEED_M_S))
	return best
