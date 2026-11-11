class_name FightGrudgeRules
extends RefCounted

# How much a bot wants to fight a man (docs/fighting-plan.md, "The grudge"): one
# level per bot per opponent, raised by the opponent's body checks and draining
# while he leaves the bot's team alone. At ACCEPT_LEVEL the bot answers his
# challenge; at CHALLENGE_LEVEL it calls him out. Every number here is a feel
# tunable — how many hits a bot takes before it wants to go — not a measurement.

const ACCEPT_LEVEL: float = 1.0
const CHALLENGE_LEVEL: float = 2.0
# So a barrage does not bank a grudge that outlasts the match.
const MAX_LEVEL: float = 3.0
# A full-strength check on the bot itself: two answer the bell, four call it.
const GAIN_PER_FULL_CHECK: float = 0.5
# Each of the hit man's teammates takes this share of his gain.
const TEAMMATE_SHARE: float = 0.25
# A whole accept level drains in three minutes without a hit.
const DECAY_PER_S: float = ACCEPT_LEVEL / 180.0
# What a hunter's challenge refused spends of the grudge that sent him: from the
# challenge level, the third refusal takes it under the accept level and the
# hunt is called off.
const REFUSAL_COST: float = 0.35
# How much further from the man the team's biggest bot may be than its maddest
# and still be the one who goes: about a second of skating at pace.
const ENFORCER_DETOUR_M: float = 8.0


# What a check of `force` (HitRules' impact scale) adds to the hit man's own
# grudge against the hitter. Linear in force, so a check hard enough to floor a
# man counts for more than a full one without a knockdown term.
static func victim_gain(force: float) -> float:
	return maxf(force, 0.0) / HitRules.FULL_CHECK_IMPULSE * GAIN_PER_FULL_CHECK


static func teammate_gain(force: float) -> float:
	return victim_gain(force) * TEAMMATE_SHARE


static func decayed(level: float, elapsed_s: float) -> float:
	return maxf(level - DECAY_PER_S * maxf(elapsed_s, 0.0), 0.0)


# Whether the biggest goes rather than the maddest, by their distances to him.
static func enforcer_goes(biggest_d: float, maddest_d: float) -> bool:
	return biggest_d <= maddest_d + ENFORCER_DETOUR_M


static func raised(level: float, gain: float) -> float:
	return clampf(level + gain, 0.0, MAX_LEVEL)
