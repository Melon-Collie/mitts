class_name AIBodyCheck

# Pure decision: should an on-puck defensive bot COMMIT to a body check on the
# carrier right now, and where's the body-intercept to drive at?
#
# A bot drives its body at the intercept with Hit held, its stick off the ice
# for the whole hunt, and re-presses as the contact comes once its drive has
# re-armed (SkaterAgentStandUp, inside AIStandUpRead.THROW_S). predicted_impulse
# is the shoulder's delivery at the full transfer and does not model the drive
# (CheckDriveRules): a contact inside one lands the legs' kick on top, and one
# between the first press's drive and its re-arm lands the held share.
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

# Horizon (s) a hunt is priced over: a contact later than this is not hunted.
const MAX_LEAD_S: float = 0.6
# The hunt's clock is read this many times across MAX_LEAD_S.
const LEAD_STEPS: int = 12

# Predicted victim impulse (m/s velocity delta) required to commit: a check that
# rocks and strips him (BodyCheckRules' rocked band and the puck-strip threshold,
# both at stagger_ref_impulse 1.35) with a little margin, and short of what
# floors a square, upright man (BodyBalanceRules.balance_ref_dv): the knockdown
# is the angle's and the moment's. At equal mass a committed shoulder kicks the
# victim ~0.325 × closing, so it takes ~5 m/s of closing at contact.
const COMMIT_IMPULSE_M_S: float = 1.6

# League-average victim mass (Skater.weight default), for a carrier whose build
# isn't wired.
const LEAGUE_VICTIM_WEIGHT: float = 1.0


class Result:
	var commit: bool = false
	var target: Vector3 = Vector3.ZERO


# `self_*` describe the checker; `carrier_*` the puck carrier it might hit.
# The hit lands where the checker's body first meets the carrier's, `contact_m`
# apart, on his arrival clock (AIArrival.time_to_arrive: his momentum, his
# build's top speed and push), the carrier carried on at his velocity; it is
# priced at the speed his stride has built along the line by then
# (AIStrideRamp), less the carrier's own along it. Returns commit=false with a
# zero target when no hit should be committed.
static func evaluate(
		self_pos: Vector3,
		self_vel: Vector3,
		self_max_speed: float,
		self_max_accel: float,
		self_weight: float,
		self_body_check_transfer: float,
		self_stagger_timer: float,
		carrier_pos: Vector3,
		carrier_vel: Vector3,
		contact_m: float,
		commit_impulse_threshold: float = COMMIT_IMPULSE_M_S,
		victim_weight: float = LEAGUE_VICTIM_WEIGHT) -> Result:
	var r := Result.new()
	if self_stagger_timer > 0.0 or self_max_speed <= 0.0:
		return r
	if self_pos.distance_to(carrier_pos) > CHECK_RANGE_M:
		return r
	var t_hit: float = _meet_time(self_pos, self_vel, self_max_speed, self_max_accel,
			carrier_pos, carrier_vel, contact_m)
	if not is_finite(t_hit):
		return r
	var intercept: Vector3 = carrier_pos + carrier_vel * t_hit
	var dir := Vector3(intercept.x - self_pos.x, 0.0, intercept.z - self_pos.z)
	if dir.length_squared() < 1e-6:
		return r
	dir = dir.normalized()
	var speed: float = AIStrideRamp.signed_speed_at(self_vel.dot(dir), t_hit, self_max_speed,
			self_max_accel, GameRules.DEFAULT_SKATER_STOP_DECEL_M_S2)
	var approach: float = maxf(speed - carrier_vel.dot(dir), 0.0)
	var predicted_impulse: float = SkaterCollisionRules.victim_kick(
			approach, self_weight, victim_weight, self_body_check_transfer)
	if predicted_impulse < commit_impulse_threshold:
		return r
	r.commit = true
	r.target = intercept
	return r


# The first time (s) within MAX_LEAD_S the checker's body can be `within_m` of
# `target_pos` carried on at `target_vel`, on his arrival clock; INF when never.
static func _meet_time(self_pos: Vector3, self_vel: Vector3, vmax: float, accel: float,
		target_pos: Vector3, target_vel: Vector3, within_m: float) -> float:
	for i: int in LEAD_STEPS + 1:
		var t: float = MAX_LEAD_S * float(i) / float(LEAD_STEPS)
		var at: Vector3 = target_pos + target_vel * t
		var to := Vector3(at.x - self_pos.x, 0.0, at.z - self_pos.z)
		var gap: float = to.length() - within_m
		if gap <= 0.0:
			return t
		var stop: Vector3 = self_pos + to * (gap / to.length())
		if AIArrival.time_to_arrive(self_pos, stop, self_vel, vmax, accel) <= t:
			return t
	return INF
