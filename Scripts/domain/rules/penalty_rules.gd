class_name PenaltyRules

# What the referee calls on a body check, and what it costs
# (docs/penalties-plan.md). Every input is something the hitter could see
# before he committed: who had the puck, where the boards were, which way his
# man was facing.

enum Foul { NONE, BOARDING, INTERFERENCE, FIGHTING }

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

# A check already on its way when a goal stops the play is let go: the same
# beat a finished check gets on a man who has just moved the puck.
const WHISTLE_GRACE_S: float = HitRules.JUST_RELEASED_GRACE_S

# A minor is the share of a period two minutes is of twenty.
const MINOR_PERIOD_SHARE: float = 0.1
const MINOR_MIN_S: float = 15.0
# A team is never put below this many skaters: a further minor waits its turn.
const MIN_SKATERS: int = 3
# What a minor is in the book, whatever it lasts on this match's clock.
const MINOR_PIM: int = 2


# Fouls are called under NHL rules.
static func calls_fouls(rule_set: int, practice: bool) -> bool:
	return rule_set == GameRules.RuleSet.NHL and not practice


# Whether a contact is the referee's to judge: while the puck is in play (a
# dropped faceoff included), and in the celebration after a goal once
# WHISTLE_GRACE_S of it has gone. Every other stoppage holds the skaters.
static func judges_contact(phase: int, seconds_in_phase: float) -> bool:
	if PhaseRules.is_puck_live_phase(phase):
		return true
	return phase == GamePhase.Phase.GOAL_CELEBRATION and seconds_in_phase >= WHISTLE_GRACE_S


# A fight costs each fighter a minor where a foul is a minor. In 3v3 it costs
# nothing: both would sit, and two-on-two is not the game.
static func penalizes_fights(rule_set: int, team_size: int, practice: bool) -> bool:
	return calls_fouls(rule_set, practice) and not awards_penalty_shot(team_size)


# Whether a goal against the shorter team can end a minor for this foul. A
# fight's minors are served in full: both teams sit a man for it, so neither
# is short because of it.
static func ends_on_a_goal(foul: int) -> bool:
	return foul != Foul.FIGHTING


# What a foul costs: a minor in 5v5, and a penalty shot for the man fouled in
# 3v3, where a team a man short is close to an automatic goal.
static func awards_penalty_shot(team_size: int) -> bool:
	return team_size < 5


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
# it, and while he is playing a loose one. `puck_is_loose` is false with the
# play dead: nobody is playing a puck that is not in play.
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


# What a goal was scored in, for the scorer's stats.
enum GoalSituation { EVEN, POWER_PLAY, SHORT_HANDED, PENALTY_SHOT }


# `short_handed_team_id` is the team with fewer skaters on the ice as the goal
# goes in, -1 at even strength (four on four included).
static func goal_situation(scoring_team_id: int, short_handed_team_id: int,
		on_a_penalty_shot: bool) -> GoalSituation:
	if on_a_penalty_shot:
		return GoalSituation.PENALTY_SHOT
	if short_handed_team_id == -1:
		return GoalSituation.EVEN
	return GoalSituation.SHORT_HANDED if short_handed_team_id == scoring_team_id \
			else GoalSituation.POWER_PLAY


# Locale key for the foul's name; the UI calls tr() on it.
static func name_key(foul: int) -> String:
	match foul:
		Foul.BOARDING:
			return "PENALTY_BOARDING"
		Foul.INTERFERENCE:
			return "PENALTY_INTERFERENCE"
		Foul.FIGHTING:
			return "PENALTY_FIGHTING"
	return ""
