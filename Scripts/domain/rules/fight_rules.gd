class_name FightRules
extends RefCounted

# Who may fight whom, and when a fight is over. Pure; the host's FightTracker
# applies it. A fight needs both men: the first press of the fight button
# challenges the opponent nearest in front of the presser, and it is on only
# when that opponent presses it back inside the window. Design of record:
# docs/fighting-plan.md.

# Centre to centre, metres: two bodies touching are ~0.7 m apart, so this is an
# arm's length of room either side of that.
const CHALLENGE_RANGE_M: float = 2.5
# The challenger has to be squared up to his man: within 60° of his facing.
const CHALLENGE_MIN_FACING_DOT: float = 0.5
# The challenged man answers from a little further, and from any side: he may
# be turning to face the man who called him out.
const ACCEPT_RANGE_M: float = 4.0
const CHALLENGE_WINDOW_S: float = 2.0
# After a challenge lapses, before the same man may challenge again: the button
# is not an alarm to sound every couple of seconds.
const CHALLENGE_COOLDOWN_S: float = 3.0
# The pair have let each other go once they have been this far apart for this
# long.
const DISENGAGE_M: float = 4.0
const DISENGAGE_S: float = 1.5
# The linesmen step in.
const FIGHT_MAX_S: float = 20.0

enum End { NONE, DISENGAGED, LINESMEN }


# Whether this match fights at all. Never in practice (free play, the tutorial,
# drills) and never in the OFF set, which has no whistles to stop play with.
static func allowed(rule_set: int, enabled: bool, practice: bool) -> bool:
	return enabled and not practice and rule_set != GameRules.RuleSet.OFF


# The phases a challenge can be made and answered in: live play, and the
# faceoff before the drop, where two men lined up across the dot can drop the
# gloves. Not the goal celebration: it ends in the goal's replay (and in
# overtime, the game), which a fight would have to hold off.
static func phase_allows(phase: int) -> bool:
	return phase == GamePhase.Phase.PLAYING \
			or phase == GamePhase.Phase.FACEOFF \
			or phase == GamePhase.Phase.FACEOFF_PREP


# Whether a man at `from` facing `facing` (XZ, need not be unit) is squared up
# to one at `to` closely enough to challenge him.
static func can_challenge(from: Vector2, facing: Vector2, to: Vector2) -> bool:
	var off: Vector2 = to - from
	var dist: float = off.length()
	if dist > CHALLENGE_RANGE_M:
		return false
	if dist < 0.001 or facing.length_squared() < 0.000001:
		return true
	return facing.normalized().dot(off / dist) >= CHALLENGE_MIN_FACING_DOT


static func can_accept(from: Vector2, to: Vector2) -> bool:
	return from.distance_to(to) <= ACCEPT_RANGE_M


# How long the pair have been apart, carried tick to tick: grows while they are
# past DISENGAGE_M, and starts over the moment they close again.
static func step_apart(apart_s: float, dist: float, delta: float) -> float:
	return apart_s + delta if dist > DISENGAGE_M else 0.0


static func end_of(elapsed_s: float, apart_s: float) -> End:
	if apart_s >= DISENGAGE_S:
		return End.DISENGAGED
	if elapsed_s >= FIGHT_MAX_S:
		return End.LINESMEN
	return End.NONE
