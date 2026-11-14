class_name AIReboundValue

# What a shot's rebound is worth to the shooter's team: the second chance it
# leaves, won by whoever gets to it first (docs/bot-net-front-offense-plan.md,
# step 3a). Read from the rebound field (AIReboundField) at the release's
# nearest measured spot, over its shots that did not score on first contact.
#
# Each live rebound is touched first at one of two moments the field measured
# the second chance at, from the puck there at the keeper as he then was: its
# contest sample (the first a stick can play in front of the net) and the late
# one (LATE_SAMPLES on). Each side's first touch is its soonest body
# (AIActionScoring.first_arrival, momentum-honest) at either point, never
# before the puck; the two are raced in the contest band. Ours, it is worth the
# shot from where we touched it, or the late one too when we touched it at the
# contest and nobody of theirs can be on it before then (he holds it for it).
# A covered shot and a miss leave nothing, and so does a rebound the keeper
# covered before its late sample, once nobody reaches it inside LATE_SAMPLES
# of its contest.
#
# Reads AIActionScoring from above, as AIPossessionValue does, so it may not
# read this.
#
# An instance holds one release's race (fill), so a man added at a station
# (value_with) is priced against it without racing everyone again.

# How far after the contest the field measured the second chance again, in
# samples (rebound_shot_harness.gd's LATE_SAMPLES; test_rebound_value holds them
# together).
const LATE_SAMPLES: int = 2


# The live rebounds of the release filled, per row: where and when each moment
# can first be played, the scores there, their first touch at each, and ours
# without the man value_with adds.
var _at := PackedVector3Array()
var _at_late := PackedVector3Array()
var _t0 := PackedFloat32Array()
var _t_late := PackedFloat32Array()
var _cover_by := PackedFloat32Array()
var _scored := PackedFloat32Array()
var _scored_late := PackedFloat32Array()
var _their_t0 := PackedFloat32Array()
var _their_late := PackedFloat32Array()
var _our_t0 := PackedFloat32Array()
var _our_late := PackedFloat32Array()
var _saved: int = 0
static var _scratch: AIReboundValue = null


# The rebound's worth for a shot released at `release` on the net at
# `attacking_goal`, once it is not a goal on first contact. `ours` / `ours_vel`
# are every body of the shooter's team (him included), `theirs` / `theirs_vel`
# the defence.
static func credit(release: Vector3, attacking_goal: Vector3,
		ours: Array[Vector3], ours_vel: Array[Vector3],
		theirs: Array[Vector3], theirs_vel: Array[Vector3]) -> float:
	if _scratch == null:
		_scratch = AIReboundValue.new()
	_scratch.fill(release, attacking_goal, ours, ours_vel, theirs, theirs_vel)
	return _scratch.value_with(Vector3.INF)


# Races a release's rebounds (credit's arguments) for value_with.
func fill(release: Vector3, attacking_goal: Vector3,
		ours: Array[Vector3], ours_vel: Array[Vector3],
		theirs: Array[Vector3], theirs_vel: Array[Vector3]) -> void:
	_at.clear()
	_at_late.clear()
	_t0.clear()
	_t_late.clear()
	_cover_by.clear()
	_scored.clear()
	_scored_late.clear()
	_their_t0.clear()
	_their_late.clear()
	_our_t0.clear()
	_our_late.clear()
	_saved = 0
	var spot: int = AIReboundField.spot_of(release, attacking_goal)
	var flight_s: float = release.distance_to(attacking_goal) \
			/ AIBotMechanics.WRISTER_SHOT_SPEED_M_S
	for j: int in AIReboundField.shot_count(spot):
		var row: int = AIReboundField.shot(spot, j)
		if AIReboundField.outcome(row) == AIReboundField.Outcome.GOAL:
			continue
		_saved += 1
		var k0: int = AIReboundField.contest_sample(row)
		if k0 < 0:
			continue
		var at: Vector3 = AIReboundField.sample_pos(row, k0, attacking_goal)
		var late: int = AIReboundField.late_sample(row)
		_at.append(at)
		_t0.append(flight_s + k0 * AIReboundField.SAMPLE_S)
		_scored.append(AIReboundField.contest_scored(row))
		_our_t0.append(AIActionScoring.first_arrival(at, ours, ours_vel))
		_their_t0.append(AIActionScoring.first_arrival(at, theirs, theirs_vel))
		# A rebound the keeper covers before its late sample is gone once nobody
		# is on it by then.
		_cover_by.append(flight_s + (k0 + LATE_SAMPLES) * AIReboundField.SAMPLE_S \
				if late < 0 else INF)
		if late < 0:
			_at_late.append(Vector3.INF)
			_t_late.append(INF)
			_scored_late.append(0.0)
			_our_late.append(INF)
			_their_late.append(INF)
			continue
		var at_l: Vector3 = AIReboundField.sample_pos(row, late, attacking_goal)
		_at_late.append(at_l)
		_t_late.append(flight_s + late * AIReboundField.SAMPLE_S)
		_scored_late.append(AIReboundField.late_scored(row))
		_our_late.append(AIActionScoring.first_arrival(at_l, ours, ours_vel))
		_their_late.append(AIActionScoring.first_arrival(at_l, theirs, theirs_vel))


# The filled release's rebound credit with one more of ours standing at `body`
# (INF: none), as credit prices it.
func value_with(body: Vector3) -> float:
	var sum: float = 0.0
	for i: int in _at.size():
		var our_t0: float = _our_t0[i]
		var our_l: float = _our_late[i]
		if body.is_finite():
			our_t0 = minf(our_t0, AIArrival.time_to_arrive(body, _at[i], Vector3.ZERO))
			if _at_late[i].is_finite():
				our_l = minf(our_l, AIArrival.time_to_arrive(body, _at_late[i], Vector3.ZERO))
		var t0: float = _t0[i]
		var their_first: float = maxf(_their_t0[i], t0)
		if minf(our_t0, their_first) > _cover_by[i]:
			continue
		var our_first: float = maxf(our_t0, t0)
		var scored: float = _scored[i]
		if _at_late[i].is_finite():
			var t_l: float = _t_late[i]
			our_l = maxf(our_l, t_l)
			their_first = minf(their_first, maxf(_their_late[i], t_l))
			if our_l < our_first:
				our_first = our_l
				scored = _scored_late[i]
			elif their_first >= t_l:
				scored = maxf(scored, _scored_late[i])
		sum += AIActionScoring.race_against(their_first, our_first) * scored
	return sum / _saved if _saved > 0 else 0.0
