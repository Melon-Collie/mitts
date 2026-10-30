class_name AIBodyCheck

# Pure decision: should an on-puck defensive bot COMMIT to a body check on the
# carrier right now, and where's the body-intercept to drive at?
#
# There is no "throw a hit" action: a bot delivers one by driving its body into
# the intercept while holding the Hit button (input.hit_held), and
# Skater._resolve_player_collisions turns the closing velocity into the impulse
# exactly as for a human. Holding Hit is what delivers the FULL transfer
# predicted_impulse assumes; an uncommitted drive lands only the passive
# fraction.
#
# Committing abandons containment, so only roles with support behind them ask:
# PRESSURE (in-zone pressurer and forecheck F1) and NZ_F1 once goal-side of
# the carrier — never the last-man gap defender.
#
# A heavy build's predicted impulse clears the bar at lower closing speeds, so it
# hunts hits; a light one won't commit to checks it would bounce off. The
# victim's active brace is not modelled: it only bites when the victim is
# committing a check of his own, which a carrier rarely is.

# Only hunt a hit when the carrier is this close — beyond it, contain instead.
const CHECK_RANGE_M: float = 6.0

# Lead-solve horizon for the body intercept, seconds.
const MAX_LEAD_S: float = 0.6

# Predicted victim impulse (m/s velocity delta) required to commit: a check that
# rocks and strips him (BodyCheckRules' rocked band and the puck-strip threshold,
# both at stagger_ref_impulse 1.35) with a little margin, and short of what
# floors a square, upright man (BodyBalanceRules.balance_ref_dv): the knockdown
# is the angle's and the moment's. At equal mass a committed drive kicks the
# victim ~0.325 × closing, so a baseline bot commits from ~5 m/s closing.
const COMMIT_IMPULSE_M_S: float = 1.6

# League-average victim mass (Skater.weight default), for a carrier whose build
# isn't wired.
const LEAGUE_VICTIM_WEIGHT: float = 1.0

# Slack on the reachability test so a borderline-reachable intercept isn't
# rejected by float noise.
const REACH_SLACK_M: float = 0.5


class Result:
	var commit: bool = false
	var target: Vector3 = Vector3.ZERO


# `self_*` describe the checker; `carrier_*` the puck carrier it might hit.
# `self_max_speed` is the closing-speed proxy. Returns commit=false with a
# zero target when no hit should be committed.
static func evaluate(
		self_pos: Vector3,
		self_max_speed: float,
		self_weight: float,
		self_body_check_transfer: float,
		self_stagger_timer: float,
		carrier_pos: Vector3,
		carrier_vel: Vector3,
		commit_impulse_threshold: float = COMMIT_IMPULSE_M_S,
		victim_weight: float = LEAGUE_VICTIM_WEIGHT) -> Result:
	var r := Result.new()

	if self_stagger_timer > 0.0:
		return r
	if self_max_speed <= 0.0:
		return r

	# 1. Range.
	if self_pos.distance_to(carrier_pos) > CHECK_RANGE_M:
		return r

	# 2. Reachable intercept. Solve the lead against the carrier's motion, then
	# check I can cover the gap to that point at my top speed within the solved
	# time (a fleeing carrier saturates the solve → gap exceeds my reach).
	var t: float = AITrajectory.intercept_time(
			self_pos, carrier_pos, carrier_vel, Vector3.ZERO, self_max_speed, MAX_LEAD_S)
	var intercept: Vector3 = AITrajectory.predict_at(carrier_pos, carrier_vel, t, 6)
	var gap: float = self_pos.distance_to(intercept)
	if gap > self_max_speed * t + REACH_SLACK_M:
		return r

	# 3. Real hit, predicted through the resolver's own delivery function
	# (SkaterCollisionRules.victim_kick), so prediction and physics are one
	# formula.
	var approach: float = _predicted_approach(self_pos, self_max_speed, intercept, carrier_vel)
	var predicted_impulse: float = SkaterCollisionRules.victim_kick(
			approach, self_weight, victim_weight, self_body_check_transfer)
	if predicted_impulse < commit_impulse_threshold:
		return r

	r.commit = true
	r.target = intercept
	return r


# Closing speed (m/s) along the checker→intercept line: the bot drives at the
# intercept at `self_speed`, the carrier moves at `carrier_vel`; the approach is
# the relative velocity projected onto the closing direction, clamped to >= 0.
static func _predicted_approach(self_pos: Vector3, self_speed: float,
		intercept: Vector3, carrier_vel: Vector3) -> float:
	var dir: Vector3 = intercept - self_pos
	dir.y = 0.0
	var l: float = dir.length()
	if l < 0.001:
		return self_speed
	dir /= l
	var rel: Vector3 = dir * self_speed - carrier_vel
	return maxf(rel.x * dir.x + rel.z * dir.z, 0.0)
