class_name AICarrierDumpSearch
extends RefCounted

# The dump-in: the puck released into their zone with nobody's tape to aim at,
# priced as the race for where it is played. See Scripts/domain/ai/CLAUDE.md →
# "A dump-in is a race for where it is played".
#
# Searched as releases — an aim point in their zone × a pace, chipped — each
# walked on the puck's path (AITrajectory.step_puck_3d, the host's own step, at
# the chase election's resolution)
# and raced by the soonest body of each side on that path, by the election's own
# rule: the body that can settle it first, or the one whose stick the path comes
# to (a man standing in the dump's way plays it there). Every dump is a chip (the
# charged LOW release, the shot ladder's set angle): over every stick while it is
# above the blade plane, where only a body in its way stops it, and raced from
# where it lands, as the election races a puck in the air. Priced flat as well,
# it never measured worse (test_dump_in_race.gd: by 0.0005 at most) and lost to
# any stick in its way. The side that meets it first plays it there:
#
#   value = p · ours(meet) − (1 − p) · theirs(meet)
#
# with p the arrival race in the contest band AIActionScoring.arrival_race
# prices with (widened by the arrival clock's own error over the trip; their
# keeper races it too, for any of the path in front of his goal line he can push
# and reach out to), ours the
# possession of the spot on arrival (AIPossessionValue) or the feed it opens to
# the support arriving with the dump, its reception raced (_support_from),
# their keeper's cover a faceoff in his zone when it is whistled (_cover_value),
# theirs a turnover there when their collector's first play is away, with the
# dumper where his skate has him then (AICarrierField.turnover_cost + the 5v5
# counter exposure), less the share our forechecker wins back off him before
# then (_regain_odds), ours there with him still on it. An iced puck (NHL,
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
# A stick on their man before his first play is away contests the puck, not
# wins it: a tie for it, as the forecheck read counts one (AIForecheckRead).
const BATTLE_SHARE: float = 0.5
# Puck.release seats a lofted release this far above where it rests on the ice.
const LOFT_SEAT_M: float = 0.1

# Walk resolution — the chase election's own, so who the dump is priced to reach
# first is who the election sends.
const STEPS: int = AILoosePuckChase.RACE_STEPS
const STEP_DT: float = AILoosePuckChase.RACE_LOOKAHEAD_S / float(AILoosePuckChase.RACE_STEPS)

# Never priced (each price is a possession read on both sides): a launch we
# never win while their possession never pays us (see _race), or one we would
# play before it is in their zone — a chip to ourselves is a carry's business,
# not a dump-in.
const _MAX_LAUNCHES: int = 10   # AIM_POINTS × PACE_FRACS (test_carrier_dump_search.gd)

# ── Results (valid after search) ─────────────────────────────────────────────
# The best release's value, −INF when there is none to make.
var best_score: float = -INF
var best_dir: Vector3 = Vector3.ZERO
var best_pace: float = 0.0
# Where and when our side plays the best release, on our win.
var best_meet: Vector3 = Vector3.INF
var best_meet_s: float = INF
# The best release's race, for instruments (nothing decides on it): the odds we
# play it first, our side's and theirs's time to it (their keeper's included),
# their keeper's alone; where theirs meets it; and the release point.
var debug_race := Vector4(-1.0, INF, INF, INF)
var debug_meet_theirs: Vector3 = Vector3.INF
var debug_origin: Vector3 = Vector3.INF

var _field: AICarrierField
var _path: Array[Vector3] = []
# Our skaters at the release (the carrier carried on through his windup) and
# their velocities and caps, index-matched; refilled each search.
var _our_pos: Array[Vector3] = []
var _our_vel: Array[Vector3] = []
var _our_caps: Array[AISkaterCaps] = []
# The carrier's own index in _our_pos: the puck leaves his blade, so it never
# comes to his stick.
var _self_index: int = -1
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
var _origin: Array[Vector3] = []
var _rival: Array[Vector3] = []
var _rival_caps: Array[AISkaterCaps] = []
# Which of the opponents is the rival (-1: their keeper, or nobody).
var _racer: Array[int] = []
var _p: Array[float] = []
var _meet_ours: Array[Vector3] = []
var _meet_theirs: Array[Vector3] = []
var _t_ours: Array[float] = []
var _t_theirs: Array[float] = []
var _t_keeper: Array[float] = []
# Whether their keeper, first to it, can cover it there (AIGoalieModel
# .COVER_STOPS_M_S): slow enough under his glove, rather than a save.
var _keeper_covers: Array[bool] = []
# Lost: when their man's first play is away (AIForecheckRead's clock; their
# keeper's: when he has it), the odds we win it back before then (_regain_odds),
# and the dumper where his skate has him then (INF: no dumper on the ice).
var _away: Array[float] = []
var _regain: Array[float] = []
var _dumper_then: Array[Vector3] = []
var _ours_vel: Array[Vector3] = []
var _iced: Array[bool] = []
var _skip: Array[bool] = []


func _init(field: AICarrierField) -> void:
	_field = field
	_path.resize(STEPS)
	_dir.resize(_MAX_LAUNCHES)
	_pace.resize(_MAX_LAUNCHES)
	_origin.resize(_MAX_LAUNCHES)
	_rival.resize(_MAX_LAUNCHES)
	_rival_caps.resize(_MAX_LAUNCHES)
	_racer.resize(_MAX_LAUNCHES)
	_p.resize(_MAX_LAUNCHES)
	_meet_ours.resize(_MAX_LAUNCHES)
	_meet_theirs.resize(_MAX_LAUNCHES)
	_t_ours.resize(_MAX_LAUNCHES)
	_t_theirs.resize(_MAX_LAUNCHES)
	_t_keeper.resize(_MAX_LAUNCHES)
	_keeper_covers.resize(_MAX_LAUNCHES)
	_away.resize(_MAX_LAUNCHES)
	_regain.resize(_MAX_LAUNCHES)
	_dumper_then.resize(_MAX_LAUNCHES)
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
	debug_race = Vector4(-1.0, INF, INF, INF)
	_count = 0
	if ctx.snapshot == null or ctx.snapshot.puck_state == null:
		return
	var origin: Vector3 = AICarrierField.pass_origin(ctx)
	if not is_on(ctx, origin):
		return
	_fill_ours(ctx)
	# Each dump leaves from its own release: the hold its pace needs
	# (AIShotHolds.solve_pass, as the carrier locks it for the press), the puck
	# pulled there first unless it already carries the pace where it sits,
	# braking, so a carrier at speed a stride short of their line releases inside
	# it, where there is no dump-in to make.
	var holds: AIShotHolds = _field.holds
	holds.configure_from(ctx)
	var self_state: SkaterNetworkState = ctx.snapshot.skater_states[ctx.peer_id]
	var body_vel := Vector2(ctx.self_velocity.x, ctx.self_velocity.z)
	var puck_off := Vector2(ctx.snapshot.puck_state.position.x - ctx.self_pos.x,
			ctx.snapshot.puck_state.position.z - ctx.self_pos.z)
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
			holds.solve_pass(Vector2(dir.x, dir.z), puck_off, body_vel, self_state.facing,
					pace / maxf(ctx.self_wrister_shot_speed, 0.001))
			var pull_s: float = holds.pass_pull_s
			var release: Vector3 = AICarrierField.pass_origin(ctx, pull_s,
					holds.pass_from - puck_off)
			if not is_on(ctx, release):
				continue
			if not _walk(release, launch_vel(dir, pace)):
				break   # a leg through a net here is one at every harder pace
			_race(ctx, release, dir, pace, pull_s)

	var support_filled: bool = false
	for k: int in _count:
		if _skip[k]:
			continue
		var v: float
		if _iced[k]:
			v = _icing_value(ctx, _origin[k])
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
			debug_race = Vector4(_p[k], _t_ours[k], _t_theirs[k], _t_keeper[k])
			debug_meet_theirs = _meet_theirs[k]
			debug_origin = _origin[k]


# Races the release just walked and records it (see the per-launch arrays). Our
# side first: a launch we would play short of their line is a chip to ourselves
# (see _MAX_LAUNCHES), and theirs is not raced for it.
# `lead_s`: the pull before the windup, over which everybody skates on.
func _race(ctx: RoleContext, origin: Vector3, dir: Vector3, pace: float, lead_s: float) -> void:
	var margin: float = AILoosePuckChase.setup_margin(dir * pace)
	var walk_s: float = float(STEPS) * STEP_DT
	var t_ours: float = INF
	var ours_vel := Vector3.ZERO
	var retriever: int = -1
	var from: Vector3 = launch_pos(origin)
	var vel: Vector3 = launch_vel(dir, pace)
	for i: int in _our_pos.size():
		var t: float = _meet_time(from, vel, _our_pos[i] + _our_vel[i] * lead_s, _our_vel[i],
				_our_caps[i], margin, i != _self_index)
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
	_origin[k] = origin
	_retriever[k] = retriever
	_skip[k] = not AIActionScoring.in_offensive_zone(meet_ours, ctx.attacking_goal_pos)
	if _skip[k]:
		return
	var t_theirs: float = INF
	var racer: int = -1
	for i: int in _field.opponents_release.size():
		var t: float = _meet_time(from, vel,
				_field.opponents_release[i] + _field.opponent_vels[i] * lead_s,
				_field.opponent_vels[i], _field.opponent_caps[i], margin, true)
		if t < t_theirs:
			t_theirs = t
			racer = i
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
	_t_theirs[k] = t_theirs
	_t_keeper[k] = keeper_t
	_keeper_covers[k] = false
	if keeper_t <= t_theirs and is_finite(keeper_t):
		var after: Vector3 = AILoosePuckChase.path_intercept_point(_path, STEP_DT, origin,
				keeper_t + STEP_DT)
		_keeper_covers[k] = meet_theirs.distance_to(after) / STEP_DT <= AIGoalieModel.COVER_STOPS_M_S
	# Whoever races us for it, their keeper too, where he is when ours gets
	# there: on his way to the meet, that share of his trip in.
	_rival[k] = Vector3.INF
	_rival_caps[k] = null
	_racer[k] = -1
	if is_finite(t_theirs):
		var at: Vector3 = AICarrierField.goalie_now(ctx)
		if keeper_t > t_theirs and racer != -1:
			at = _field.opponents_release[racer] + _field.opponent_vels[racer] * lead_s
			_rival_caps[k] = _field.opponent_caps[racer]
			_racer[k] = racer
		_rival[k] = at.lerp(meet_theirs, clampf(t_ours / maxf(t_theirs, 0.001), 0.0, 1.0))
	_away[k] = t_theirs
	_regain[k] = 0.0
	if is_finite(t_theirs) and keeper_t > t_theirs:
		var next: Vector3 = AILoosePuckChase.path_intercept_point(_path, STEP_DT, origin,
				t_theirs + STEP_DT)
		_away[k] = t_theirs + AIFeedReception.receiver_settle_s(
				meet_theirs.distance_to(next) / STEP_DT) \
				+ AIForecheckRead.CARRIER_READ_S + AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S
		_regain[k] = _regain_odds(meet_theirs, _away[k], lead_s)
	_dumper_then[k] = Vector3.INF
	if _self_index != -1 and is_finite(_away[k]):
		var d: Vector3 = _our_pos[_self_index] + _our_vel[_self_index] * (lead_s + _away[k])
		var on_ice: Vector2 = GameRules.clamp_to_rink_inner(Vector2(d.x, d.z),
				AIStationSearch.RINK_INSET_M)
		_dumper_then[k] = Vector3(on_ice.x, 0.0, on_ice.y)
	_ours_vel[k] = ours_vel
	_iced[k] = ctx.icing_enforced and _ices(ctx, origin, minf(t_ours, t_theirs))
	# A launch we never win is worth only what their puck at the meet pays us,
	# which is nothing while no possession reads below zero.
	_skip[k] = _p[k] <= 0.0 and AIPossessionValue.LEAST_VALUE >= 0.0


# When a body at `pos` moving at `body_vel` first plays the release just walked
# (from `from` at `vel`), as the chase election times him: settled on its path
# once it is down on the ice, or, `stick` true (not the carrier, whose blade it
# leaves), the path coming to his stick; and a body in its way stops it in the air.
func _meet_time(from: Vector3, vel: Vector3, pos: Vector3, body_vel: Vector3,
		caps: AISkaterCaps, margin: float, stick: bool) -> float:
	var vmax: float = AILoosePuckChase.race_vmax(caps)
	var t_play: float = AILoosePuckChase.race_playable_time(from, vel)
	var t: float = AILoosePuckChase.path_intercept_time(_path, STEP_DT, from, pos, body_vel,
			vmax, margin, AIArrival.SHED_ACCEL_DEFAULT_M_S2, 0.0, t_play)
	if stick:
		t = minf(t, AILoosePuckChase.reach_meet_time(_path, from, vel, pos, body_vel, vmax,
				AILoosePuckChase.race_reach(caps), true, true))
		t = minf(t, _body_block_time(from, pos, body_vel, t_play))
	return t


# The first time before `t_air` that the walked path passes within a body of a
# man at `pos` skating at `body_vel` (INF: it never does): a chip in the air goes
# over his stick, not through him.
func _body_block_time(from: Vector3, pos: Vector3, body_vel: Vector3, t_air: float) -> float:
	var r: float = AIPuckLane.LANE_DEFENDER_BODY_RADIUS_M
	var a: Vector3 = from
	for i: int in STEPS:
		var t0: float = float(i) * STEP_DT
		if t0 >= t_air:
			return INF
		var b: Vector3 = _path[i]
		# The puck and the body move linearly over the step: their closest approach.
		var b0: Vector3 = pos + body_vel * t0
		var rel0 := Vector2(a.x - b0.x, a.z - b0.z)
		var drel := Vector2(b.x - a.x - body_vel.x * STEP_DT, b.z - a.z - body_vel.z * STEP_DT)
		var dd: float = drel.length_squared()
		var f: float = clampf(-rel0.dot(drel) / dd, 0.0, 1.0) if dd > 1e-9 else 0.0
		var t: float = t0 + f * STEP_DT
		if t < t_air and (rel0 + drel * f).length() <= r:
			return t
		a = b
	return INF


# Where the chip leaves the blade: seated above the ice.
static func launch_pos(origin: Vector3) -> Vector3:
	return Vector3(origin.x, AITrajectory.PUCK_REST_HEIGHT_M + LOFT_SEAT_M, origin.z)


# The chip at `pace` along the ice: the charged LOW release's set angle, whose rise
# scales with the pace (ReleaseMomentum's shot rule).
static func launch_vel(dir: Vector3, pace: float) -> Vector3:
	return Vector3(dir.x * pace, pace * GameRules.DEFAULT_LOFT_TAN_LOW, dir.z * pace)


# Launch `k`'s value (see the header).
func _value(ctx: RoleContext, k: int) -> float:
	var lost: float = 1.0 - _p[k]
	var ours: float = maxf(_field.possession_at(_meet_ours[k], _t_ours[k], _ours_vel[k],
			_rival[k], _rival_caps[k]),
			_support_from(ctx, k) \
					* AIActionScoring.delay_discount(_t_ours[k]))
	var v: float = _p[k] * ours
	if _keeper_covers[k] and ctx.covers_whistled:
		return v + lost * _cover_value(ctx, _meet_theirs[k])
	var won_back: float = lost * _regain[k]
	var kept: float = lost - won_back
	if won_back > 0.0:
		# Won back off their man where he played it, him still on it.
		v += won_back * _field.possession_at(_meet_theirs[k], _away[k], Vector3.ZERO,
				_meet_theirs[k], _rival_caps[k])
	var self_caps: AISkaterCaps = _our_caps[_self_index] if _self_index != -1 else null
	return v - _field.turnover_cost(_meet_theirs[k], kept, _away[k], _dumper_then[k], self_caps) \
			- _field.counter_exposure_cost(ctx, _meet_theirs[k], kept, ctx.self_pos,
					AIRoleReads.resolve_our_goalie_pos(ctx))


# The odds we win back a dump their man plays at `meet`, his first play away at
# `away_s`: our soonest forechecker's stick on him before then, by the forecheck
# read's clock (AILoosePuckChase.reach_eta, from where the windup's `lead_s` has
# him), in arrival_race's contest band widened by the clock's error over the
# trip; then a battle for it (BATTLE_SHARE).
func _regain_odds(meet: Vector3, away_s: float, lead_s: float) -> float:
	var on_s: float = INF
	for i: int in _our_pos.size():
		var c: AISkaterCaps = _our_caps[i]
		on_s = minf(on_s, AILoosePuckChase.reach_eta(_our_pos[i] + _our_vel[i] * lead_s, meet,
				_our_vel[i], AILoosePuckChase.race_vmax(c),
				c.max_accel if c != null else AIArrival.SHED_ACCEL_DEFAULT_M_S2,
				c.max_blade_reach if c != null else AIBotMechanics.BLADE_REACH_M))
	if not is_finite(on_s):
		return 0.0
	var band: float = AIActionScoring.CHASE_CONTEST_MARGIN_S \
			+ AIArrival.ERROR_FRAC * maxf(on_s, away_s)
	return BATTLE_SHARE * clampf(0.5 + (away_s - on_s) / (2.0 * band), 0.0, 1.0)


# When their keeper first gets a piece of the path just walked: a point in front
# of his goal line inside what his push and his stick reach by then (INF: none).
# One slowing at his feet he covers (_keeper_covers), one going by he saves;
# he skates out to play neither, and nothing behind his net. Unreplicated, he is home on his
# crease.
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


# A puck their keeper covers, the cover whistled (ctx.covers_whistled): the
# faceoff in his zone at the dot on its side (GameRules.icing_faceoff_dot),
# priced as an icing's is: the coin flip (AIIcingRead.FACEOFF_LOSS_SHARE) for
# their possession of the dot, and nothing for ours — no faceoff is credited to
# the side that wins it.
func _cover_value(ctx: RoleContext, at: Vector3) -> float:
	var dot2: Vector2 = GameRules.icing_faceoff_dot(1 - ctx.team_id, at.x)
	return -_field.turnover_cost(Vector3(dot2.x, 0.0, dot2.y), AIIcingRead.FACEOFF_LOSS_SHARE)


# Whether the release just walked ices (AIIcingRead), first played at
# `touched_s`.
func _ices(ctx: RoleContext, origin: Vector3, touched_s: float) -> bool:
	var attack_z: float = signf(ctx.attacking_goal_pos.z)
	var crossed_s: float = AIIcingRead.crossing_s(_path, STEP_DT, attack_z)
	if crossed_s >= touched_s:
		return false
	return AIIcingRead.ices(origin.z, attack_z, crossed_s, touched_s,
			AIIcingRead.first_to_dots(attack_z, _our_pos, _our_vel, _our_caps),
			AIIcingRead.first_to_dots(attack_z, _field.opponents_release,
					_field.opponent_vels, _field.opponent_caps))


# An icing called: a faceoff at our end's dot.
func _icing_value(ctx: RoleContext, origin: Vector3) -> float:
	return -_field.turnover_cost(AIIcingRead.faceoff_spot(ctx.team_id, origin.x),
			AIIcingRead.FACEOFF_LOSS_SHARE)


# Our side and the defence dead-reckoned to the race's horizon, and the shot each
# of ours who is in their zone by then would get there (0 for one who is not),
# off the feed out from the won puck: the keeper set on it (History.FED).
# A won dump is worth the support that arrives with it when that beats our
# possession of the meet, which a puck behind their goal line holds at the
# zone's floor.
func _fill_support(ctx: RoleContext) -> void:
	var horizon: float = float(STEPS) * STEP_DT
	# The defence goes back for the puck once it is in: each man on at his
	# momentum, not held on the line as a carry holds him (project_opponents).
	_opp_then.clear()
	for i: int in _field.opponents.size():
		_opp_then.append(AITrajectory.predict_at(_field.opponents[i], _field.opponent_vels[i],
				horizon))
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
				AIBotMechanics.WRISTER_SHOT_SPEED_M_S, _field.opponent_caps, -1.0, NAN, -1.0,
				AIShotOdds.History.FED)
				if AIActionScoring.in_offensive_zone(p, ctx.attacking_goal_pos) else 0.0)


# The best feed launch `k`'s retriever has from where he plays it, to the
# support (_fill_support): its shot × the lane against the defence then × the
# pass landing × the flight × the race for the reception, as a future action
# (AICarrierField.PASS_OPTION_DISCOUNT, the carry's pass option). The reception's
# race is their first body from the release against the feed arriving with our
# man there; the man who raced us for the puck is where we won it from him, and
# starts from there.
func _support_from(ctx: RoleContext, k: int) -> float:
	var meet: Vector3 = _meet_ours[k]
	var meet_s: float = _t_ours[k]
	var racer: int = _racer[k]
	var racer_then: Vector3 = Vector3.INF
	if racer != -1:
		racer_then = _opp_then[racer]
		_opp_then[racer] = _rival[k]
	var best: float = 0.0
	for i: int in _our_then.size():
		if i == _retriever[k] or _our_then_val[i] * AICarrierField.PASS_OPTION_DISCOUNT <= best:
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
		option *= _reception_race(to, received_s, racer, _rival[k], meet_s)
		best = maxf(best, option)
	if racer != -1:
		_opp_then[racer] = racer_then
	return best


# AIActionScoring.arrival_race for our man at `to` at `our_t`, their bodies from
# the release but the racer (index `racer`, -1: none), who sets off from `rival`
# at `rival_s`.
func _reception_race(to: Vector3, our_t: float, racer: int, rival: Vector3,
		rival_s: float) -> float:
	var opp_t: float = INF
	for j: int in _field.opponents_release.size():
		if j == racer:
			opp_t = minf(opp_t, rival_s + AIArrival.time_to_arrive(rival, to, Vector3.ZERO))
		else:
			opp_t = minf(opp_t, AIArrival.time_to_arrive(_field.opponents_release[j], to,
					_field.opponent_vels[j]))
	if not is_finite(opp_t):
		return 1.0
	var band: float = AIActionScoring.CHASE_CONTEST_MARGIN_S \
			+ AIArrival.ERROR_FRAC * minf(maxf(our_t, opp_t), 1e6)
	return clampf(0.5 + (opp_t - our_t) / (2.0 * band), 0.0, 1.0)


# Our side at the release: the teammates who may play the puck, read where their
# momentum has them through the windup, and the carrier carried on through it.
func _fill_ours(ctx: RoleContext) -> void:
	_our_pos.clear()
	_our_vel.clear()
	_our_caps.clear()
	_self_index = -1
	var lead: float = AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S
	for pid: int in ctx.snapshot.skater_states:
		if ctx.team_id_by_peer.get(pid, -1) != ctx.team_id:
			continue
		if pid != ctx.peer_id and ctx.snapshot.is_out_of_play(pid):
			continue
		var s: SkaterNetworkState = ctx.snapshot.skater_states[pid]
		if pid == ctx.peer_id:
			_self_index = _our_pos.size()
		_our_pos.append(AITrajectory.predict_at(s.position, s.velocity, lead))
		_our_vel.append(s.velocity)
		_our_caps.append(ctx.caps_by_peer.get(pid))


# The chip's path from `origin` at `vel`, into _path. False when a leg runs
# through a net, which the walk itself does not model.
func _walk(origin: Vector3, vel: Vector3) -> bool:
	var p: Vector3 = launch_pos(origin)
	var v: Vector3 = vel
	for i: int in STEPS:
		var stepped: Transform3D = AITrajectory.step_puck_3d(p, v, STEP_DT)
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
