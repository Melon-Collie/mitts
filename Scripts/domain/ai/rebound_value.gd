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

# How far after the contest the field measured the second chance again, in
# samples (rebound_shot_harness.gd's LATE_SAMPLES; test_rebound_value holds them
# together).
const LATE_SAMPLES: int = 2


# The rebound's worth for a shot released at `release` on the net at
# `attacking_goal`, once it is not a goal on first contact. `ours` / `ours_vel`
# are every body of the shooter's team (him included), `theirs` / `theirs_vel`
# the defence.
static func credit(release: Vector3, attacking_goal: Vector3,
		ours: Array[Vector3], ours_vel: Array[Vector3],
		theirs: Array[Vector3], theirs_vel: Array[Vector3]) -> float:
	var spot: int = AIReboundField.spot_of(release, attacking_goal)
	var n: int = AIReboundField.shot_count(spot)
	var flight_s: float = release.distance_to(attacking_goal) \
			/ AIBotMechanics.WRISTER_SHOT_SPEED_M_S
	var sum: float = 0.0
	var saved: int = 0
	for j: int in n:
		var row: int = AIReboundField.shot(spot, j)
		if AIReboundField.outcome(row) == AIReboundField.Outcome.GOAL:
			continue
		saved += 1
		var k0: int = AIReboundField.contest_sample(row)
		if k0 < 0:
			continue
		var at: Vector3 = AIReboundField.sample_pos(row, k0, attacking_goal)
		var t0: float = flight_s + k0 * AIReboundField.SAMPLE_S
		var our_t0: float = AIActionScoring.first_arrival(at, ours, ours_vel)
		var their_t0: float = maxf(AIActionScoring.first_arrival(at, theirs, theirs_vel), t0)
		var late: int = AIReboundField.late_sample(row)
		if late < 0 and minf(our_t0, their_t0) \
				> flight_s + (k0 + LATE_SAMPLES) * AIReboundField.SAMPLE_S:
			continue
		var our_first: float = maxf(our_t0, t0)
		var their_first: float = their_t0
		var scored: float = AIReboundField.contest_scored(row)
		if late >= 0:
			var at_l: Vector3 = AIReboundField.sample_pos(row, late, attacking_goal)
			var t_l: float = flight_s + late * AIReboundField.SAMPLE_S
			var our_l: float = maxf(AIActionScoring.first_arrival(at_l, ours, ours_vel), t_l)
			their_first = minf(their_first, maxf(
					AIActionScoring.first_arrival(at_l, theirs, theirs_vel), t_l))
			if our_l < our_first:
				our_first = our_l
				scored = AIReboundField.late_scored(row)
			elif their_first >= t_l:
				scored = maxf(scored, AIReboundField.late_scored(row))
		sum += AIActionScoring.race_against(their_first, our_first) * scored
	return sum / saved if saved > 0 else 0.0
