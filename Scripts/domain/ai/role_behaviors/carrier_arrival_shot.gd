class_name AICarrierArrivalShot
extends RefCounted

# The carrier's shot on arriving somewhere: what a carry's candidate and his own
# drive in are worth by the shot he takes there. One read for both, so neither
# out-prices the shot now on a release the other would not credit.
#
# The candidate's shot is taken ARRIVING AT PACE (carry steps are skated at
# speed; the arrival brake skips carry waypoints), so it is the same
# moving-release wrister the shoot-now eval prices. Two-phase keeper:
#   1. TRACK: he follows the whole carry to the candidate's arc-square
#      (generous to him: he never falls behind en route).
#   2. FINAL RACE: from that square he races the wind-up + flight against a
#      release still sliding at the arrival speed — the race a hard lateral
#      cut in tight genuinely wins.
# Phase 2 is what gives a STANDSTILL 1v1 a gradient toward building the
# lateral speed that opens the window; a static release would score every
# one-step spot against a set keeper ~0. Because he is SQUARE at every
# candidate before the final race, a further cut never prices more than the
# last-quarter-second window, so the cut cannot recede forever.
#
# The arrival UNSETTLE is read from the TRACKED keeper over the FINAL window
# only: the carry never catches him, only the re-square the release demands
# can. Never measure it from his CURRENT position over the whole carry — that
# charges him for a swing his tracking already covers and makes every
# doorstep drive a phantom caught-moving goalie.
#
# Released from where the hands let it go — the hold, over the hands' hold
# (AIBotMechanics.shot_hold_sample_s), through the shot now's line gate — and
# against the keeper in the stance that release meets him in: down in tight,
# where he goes down for the carrier as he comes (AICarrierField.keeper_stance_at).

# best_on_path's where and when (s from the move's start); INF when no read on
# the way scores.
var best_pos: Vector3 = Vector3.INF
var best_t: float = INF
# best_on_path's read at the move's end, before the delay to it; NAN when the
# end is out of range. The same read the move's end worth makes.
var end_value: float = NAN
# The shot from where every first move starts, read once a search (begin_search).
var _start_value: float = NAN


# `candidate` reached at `arrive_vel` after `local_time`, read from `from_pos`
# against the defence `opps` projected to then.
static func value(field: AICarrierField, ctx: RoleContext, candidate: Vector3,
		arrive_vel: Vector3, local_time: float, from_pos: Vector3,
		opps: Array[Vector3]) -> float:
	# The shot on arrival is held as the shoot-now sweep would hold it
	# (arrival_hold_wait): at that hold's pace and keep odds, with any pull the
	# carry is too short for waited out in the wind-up the keeper races.
	var cand_wait: float = 0.0
	var cand_keep: float = 1.0
	var cand_hold := Vector3.ZERO
	if AICarrierField.shot_reads(ctx, from_pos,
			candidate + arrive_vel * ctx.self_shot_lookahead_s):
		cand_wait = field.arrival_hold_wait(ctx, candidate, arrive_vel, local_time)
		cand_keep = field.holds.arrival_keep
		cand_hold = Vector3(field.holds.arrival_offset.x, 0.0, field.holds.arrival_offset.y)
	# The keeper backs in at the pace the carry closes on him at arrival.
	var to_goal: Vector3 = ctx.attacking_goal_pos - candidate
	to_goal.y = 0.0
	var carry_closing: float = maxf(arrive_vel.dot(to_goal.normalized()), 0.0) \
			if to_goal.length_squared() > 0.0001 else 0.0
	var tracked_goalie: Vector3 = AIGoalieModel.predict_goalie_pos(
			AICarrierField.goalie_now(ctx), ctx.attacking_goal_pos, local_time, candidate,
			carry_closing)
	var unsettled: float = AICarrierField.goalie_unsettled_at(ctx, local_time, candidate,
			carry_closing)
	# A release behind the line gate is left there: the jam clamp would carry it
	# out in front.
	var samples: int = AIBotMechanics.shot_hold_samples(ctx.self_shot_timing_error_s)
	var score: float = 0.0
	for j: int in samples:
		var cand_windup: float = AIBotMechanics.shot_hold_sample_s(
				ctx.self_shot_timing_error_s, j, samples) + cand_wait
		var released_at: Vector3 = candidate + cand_hold + arrive_vel * cand_windup
		var cand_release: Vector3 = released_at
		if AICarrierField.leaves_ahead_of_line(released_at, ctx.attacking_goal_pos):
			cand_release = AIGoalieModel.release_ahead_of_goalie(released_at,
					ctx.attacking_goal_pos, tracked_goalie)
		# Decided on ARRIVAL, against the keeper then: one the carry outran still
		# pushing to his square (goalie_unsettled).
		var lag: float = AIGoalieModel.goalie_arc_match_x(
				tracked_goalie, ctx.attacking_goal_pos, cand_release) - tracked_goalie.x
		var keeper_vel_x: float = signf(lag) * AIGoalieModel.GOALIE_MAX_LATERAL_SPEED_MPS \
				* unsettled
		# Having tracked the carry he faces the shot, as the shoot-now read will see
		# him there. Left unread, the field blends in keepers turned to a decoy or a
		# feed, which in tight promise odds the shot on arrival never has.
		score += field.value_at(ctx, cand_release, from_pos, opps, tracked_goalie,
				keeper_vel_x, cand_keep,
				field.keeper_stance_at(local_time + cand_windup, released_at,
						ctx.attacking_goal_pos),
				atan2(tracked_goalie.x - cand_release.x, tracked_goalie.z - cand_release.z),
				local_time, arrive_vel, AIShotOdds.History.CARRIED)
	return score / samples


# The best shot on the way along rolled move `m` of `roll` from `from` (moving at
# `from_vel`, `t_from` s from now), over its first `reach` samples, decayed to the
# move's start, against the defence projected into `opps`; where and when in
# best_pos / best_t: the carrier plans where on the way he releases, so a move
# is worth the best shot it passes, not its end's alone. Read every `step_m` in tight (inside PATH_SHOT_RANGE_M of
# their net), where the odds change within a metre and the samples are a
# horizon's third apart; from where the move starts too, for the first move.
# The when is the peak of the parabola through the best read and its
# neighbours: the release is planned to a point, not to the nearest read of a
# grid that moves with the carrier.
const PATH_SHOT_STEP_M: float = 1.0
const PATH_SHOT_RANGE_M: float = 8.0


func best_on_path(field: AICarrierField, ctx: RoleContext, roll: AICarryRollout, m: int,
		from: Vector3, from_vel: Vector3, t_from: float, reach: int,
		opps: Array[Vector3], step_m: float = PATH_SHOT_STEP_M) -> float:
	var goal: Vector3 = ctx.attacking_goal_pos
	var best: float = 0.0
	best_t = INF
	best_pos = Vector3.INF
	end_value = NAN
	# The reads either side of the best, for the parabola (NAN: none in the run).
	var prev_read_t: float = NAN
	var prev_read_v: float = 0.0
	var prev_read_q := Vector3.ZERO
	var left_t: float = NAN
	var left_v: float = 0.0
	var left_q := Vector3.ZERO
	var right_t: float = NAN
	var right_v: float = 0.0
	var right_q := Vector3.ZERO
	var best_is_last: bool = false
	if t_from == 0.0 and _in_range(from, goal):
		if is_nan(_start_value):
			field.project_opponents(0.0, opps)
			_start_value = value(field, ctx, from, from_vel, 0.0, ctx.self_pos, opps)
		best = _start_value
		best_t = 0.0
		best_pos = from
		prev_read_t = 0.0
		prev_read_v = best
		prev_read_q = from
		best_is_last = true
	var prev: Vector3 = from
	var prev_vel: Vector3 = from_vel
	var prev_t: float = 0.0
	for k: int in range(1, reach + 1):
		var p: Vector3 = roll.reach_pos(m, k)
		var v: Vector3 = roll.reach_vel(m, k, from)
		var t: float = AICarryRollout.HORIZON_S * k / AICarryRollout.SAMPLES
		var subs: int = maxi(1, ceili(prev.distance_to(p) / step_m))
		for i: int in range(1, subs + 1):
			var f: float = float(i) / subs
			var q: Vector3 = prev.lerp(p, f)
			if not _in_range(q, goal):
				prev_read_t = NAN
				best_is_last = false
				continue
			var tq: float = lerpf(prev_t, t, f)
			field.project_opponents(t_from + tq, opps)
			var raw: float = value(field, ctx, q, prev_vel.lerp(v, f), t_from + tq, ctx.self_pos,
					opps)
			if k == reach and i == subs:
				end_value = raw
			var at_q: float = raw * AIActionScoring.delay_discount(tq)
			if best_is_last:
				right_t = tq
				right_v = at_q
				right_q = q
			best_is_last = false
			if at_q > best:
				best = at_q
				best_t = tq
				best_pos = q
				left_t = prev_read_t
				left_v = prev_read_v
				left_q = prev_read_q
				right_t = NAN
				best_is_last = true
			prev_read_t = tq
			prev_read_v = at_q
			prev_read_q = q
		prev = p
		prev_vel = v
		prev_t = t
	if is_finite(best_t) and not is_nan(left_t) and not is_nan(right_t):
		_refine(left_t, left_v, left_q, best, right_t, right_v, right_q)
	return best


# A new search: the first moves' start is read afresh.
func begin_search() -> void:
	_start_value = NAN


# Inside PATH_SHOT_RANGE_M of the net, in the zone.
static func _in_range(q: Vector3, goal: Vector3) -> bool:
	return Vector2(q.x - goal.x, q.z - goal.z).length_squared() \
			<= PATH_SHOT_RANGE_M * PATH_SHOT_RANGE_M \
			and AIActionScoring.in_offensive_zone(q, goal)


# Moves best_t / best_pos to the peak of the parabola through the
# best read (value `best` there) and the reads either side of it, kept between them.
func _refine(lt: float, lv: float, lq: Vector3, best: float, rt: float,
		rv: float, rq: Vector3) -> void:
	var bt: float = best_t
	var bq: Vector3 = best_pos
	var den: float = (bt - lt) * (best - rv) - (bt - rt) * (best - lv)
	if absf(den) < 1e-9:
		return
	var num: float = (bt - lt) * (bt - lt) * (best - rv) - (bt - rt) * (bt - rt) * (best - lv)
	var peak: float = clampf(bt - 0.5 * num / den, lt, rt)
	if peak < bt:
		best_pos = lq.lerp(bq, (peak - lt) / maxf(bt - lt, 1e-6))
	else:
		best_pos = bq.lerp(rq, (peak - bt) / maxf(rt - bt, 1e-6))
	best_t = peak
