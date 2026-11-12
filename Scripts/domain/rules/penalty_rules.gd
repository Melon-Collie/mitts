class_name PenaltyRules

# What the referee calls on a body check, and what it costs
# (docs/penalties-plan.md). Every input is something the hitter could see
# before he committed: who had the puck, where the boards were, which way his
# man was facing.

enum Foul { NONE, BOARDING, INTERFERENCE }

# How far off the boards a man can be thrown into them (body edge to board).
const BOARDING_ZONE_M: float = 1.5
# The hitter is behind his man when the man faces within 45° of the way he is
# driven: the rear 90°.
const BOARDING_REAR_COS: float = 0.7071
# Boarding reads the victim's facing this long before the contact, so turning
# his back as the hit arrives draws nothing.
const BOARDING_TURN_GRACE_S: float = 0.3
# A man this close to a loose puck is playing it, and may be hit.
const INTERFERENCE_PUCK_REACH_M: float = 2.0

# A minor is the share of a period two minutes is of twenty.
const MINOR_PERIOD_SHARE: float = 0.1
const MINOR_MIN_S: float = 15.0
# A team is never put below this many skaters: a further minor waits its turn.
const MIN_SKATERS: int = 3


# Fouls are called under NHL rules in 5v5; a foul in 3v3 is a penalty shot,
# which is not built.
static func calls_fouls(rule_set: int, team_size: int, practice: bool) -> bool:
	return rule_set == GameRules.RuleSet.NHL and team_size >= 5 and not practice


static func minor_seconds(period_duration: float) -> float:
	return maxf(period_duration * MINOR_PERIOD_SHARE, MINOR_MIN_S)


# How many of a team's minors can run at once.
static func max_serving(team_size: int) -> int:
	return maxi(team_size - MIN_SKATERS, 0)


# `hit_dir` is the way the hit drives him (unit XZ); `wall_out` the outward
# normal of the boards he is within BOARDING_ZONE_M of, ZERO in open ice.
static func is_driven_into_boards(hit_dir: Vector2, wall_out: Vector2) -> bool:
	return wall_out != Vector2.ZERO \
			and hit_dir.dot(wall_out) >= BoardWallRules.BACKSTOP_MIN_INTO_WALL


# `victim_facing` is his facing BOARDING_TURN_GRACE_S before the contact.
static func is_hit_from_behind(victim_facing: Vector2, hit_dir: Vector2) -> bool:
	return victim_facing.dot(hit_dir) >= BOARDING_REAR_COS


# A man may be checked while he has the puck, just after he lost or released
# it, and while he is playing a loose one.
static func is_eligible_to_be_hit(victim_is_carrier: bool,
		seconds_since_victim_lost_possession: float,
		puck_is_loose: bool, victim_to_puck_m: float) -> bool:
	if victim_is_carrier:
		return true
	if seconds_since_victim_lost_possession <= HitRules.JUST_RELEASED_GRACE_S:
		return true
	return puck_is_loose and victim_to_puck_m <= INTERFERENCE_PUCK_REACH_M


# The foul one contact is, if any. Only a delivered check at full-check
# strength is judged: a bump, a lean and the press never reach it. Boarding
# outranks interference.
static func judge(impulse_magnitude: float, attacker_committed: bool,
		attacker_has_puck: bool, victim_eligible: bool,
		driven_into_boards: bool, hit_from_behind: bool) -> Foul:
	if not attacker_committed or attacker_has_puck:
		return Foul.NONE
	if impulse_magnitude < HitRules.FULL_CHECK_IMPULSE:
		return Foul.NONE
	if driven_into_boards and hit_from_behind:
		return Foul.BOARDING
	if not victim_eligible:
		return Foul.INTERFERENCE
	return Foul.NONE


# Locale key for the foul's name; the UI calls tr() on it.
static func name_key(foul: int) -> String:
	match foul:
		Foul.BOARDING:
			return "PENALTY_BOARDING"
		Foul.INTERFERENCE:
			return "PENALTY_INTERFERENCE"
	return ""
