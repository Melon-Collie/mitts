class_name GoalieSkillProfile
extends RefCounted

# Per-difficulty bundle of goalie tuning knobs — the goalie's counterpart to
# BotSkillProfile. The keeper takes them onto his reads, his hands and his drop
# (KeeperController._tier). Every lever must be a trait a real weaker goalie has
# (Scripts/domain/ai/CLAUDE.md → "The goalie is tiered, but only ever as a
# weaker goalie").
#
# AI MIRROR: the bots' model of him (AIGoalieModel) reads the same leg read,
# synced from the match's profile by set_goalie_profile; its default is Hard's,
# so unwired contexts (unit tests) plan against the Hard goalie.
#
# To add a tier: add a Difficulty enum value, a factory, and a for_difficulty arm.
# To add a knob: add a field + _init param, set it in all three factories, and
# consume it in KeeperController._tier. If the bots' model reads the same
# quantity, also sync it in AIGoalieModel.set_goalie_profile — otherwise the
# bots keep planning against the Hard goalie's version of it.

enum Difficulty {
	EASY = 0,     # the floor — a late read, slow arms, a slow drop
	NORMAL = 1,   # the middle — a fair fight, clearly softer than Hard
	HARD = 2,     # the ceiling
}

# Glove / blocker reach speed cap (m/s) during shot hand saves. Lower → can't
# pull the corner back.

var glove_react_max_speed_mps: float
var blocker_react_max_speed_mps: float
# His read's latency (s): when his legs, his drop and his hands start on a shot.
# One read drives them all: a hand reacts no slower than a foot, and the glove
# is the lighter limb. The single strongest "reacts, but slower" lever.
# AI-mirrored (AIGoalieModel.goalie_leg_delay_s).
var reaction_delay_s: float
# Primed (quiet-eye) read latency (s) after watching a visible windup — the
# floor his read shortcuts to when he is primed. Tiering it matters most at
# the bottom: beginners telegraph every shot, so an untiered prime makes Easy
# sharpest against exactly the shots newcomers take.
var prearmed_reaction_delay_s: float
# Pads-to-floor time (s) once the butterfly commits.
var butterfly_drop_s: float


func _init(p_glove_react_max_speed_mps: float, p_blocker_react_max_speed_mps: float,
		p_reaction_delay_s: float, p_prearmed_reaction_delay_s: float, p_butterfly_drop_s: float) -> void:
	glove_react_max_speed_mps = p_glove_react_max_speed_mps
	blocker_react_max_speed_mps = p_blocker_react_max_speed_mps
	reaction_delay_s = p_reaction_delay_s
	prearmed_reaction_delay_s = p_prearmed_reaction_delay_s
	butterfly_drop_s = p_butterfly_drop_s


static func hard() -> GoalieSkillProfile:
	return GoalieSkillProfile.new(5.0, 5.0, GameRules.DEFAULT_GOALIE_REACTION_DELAY_S, 0.07, 0.20)


# Normal is the middle tier: enough goalie to punish a lazy shot, soft enough
# that a well-picked corner or a quick release off the catch genuinely scores.
# Reads a beat slower than Hard (0.18 s legs ≈ the real elite cold-read floor,
# so the anticipation edge Hard keeps is gone), and arms that get most — not
# all — of the way to the corner.
static func normal() -> GoalieSkillProfile:
	return GoalieSkillProfile.new(3.8, 3.8, 0.18, 0.10, 0.25)


# Easy is the newcomer floor, tuned so any decently-aimed shot scores: the leg
# read and the slow drop leave the five-hole and low corners open from inside
# the slot, the arms crawl (top corners open), and the primed
# read barely beats the cold one (telegraphed beginner windups still score).
static func easy() -> GoalieSkillProfile:
	return GoalieSkillProfile.new(2.4, 2.4, 0.30, 0.16, 0.32)


static func for_difficulty(difficulty: int) -> GoalieSkillProfile:
	match difficulty:
		Difficulty.EASY:
			return easy()
		Difficulty.NORMAL:
			return normal()
		_:
			return hard()
