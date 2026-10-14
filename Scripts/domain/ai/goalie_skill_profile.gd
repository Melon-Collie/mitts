class_name GoalieSkillProfile
extends RefCounted

# Per-difficulty bundle of goalie tuning knobs — the goalie's counterpart to
# BotSkillProfile. GoalieController.setup() writes a profile onto its fields
# before building its cached rule configs; HARD is every value at the
# controller's authored default, so applying it is a no-op. Every lever must be
# a trait a real weaker goalie has (Scripts/domain/ai/CLAUDE.md → "The goalie
# is tiered, but only ever as a weaker goalie").
#
# AI MIRROR: the bots' shot/pass scoring predicts the live goalie with the same
# read model (leg/arm delays, drop time, lateral accel ramp, arm deploy), held as
# static vars on AIGoalieModel and synced from the match's profile by
# set_goalie_profile. Their defaults are the Hard baselines, so unwired contexts
# (unit tests) score against the Hard goalie.
#
# FIXED ACROSS TIERS: t_push_speed, the standing T-push TOP speed — no tier
# varies it, so the scorer keeps it as a const (GOALIE_MAX_LATERAL_SPEED_MPS).
# Add it here only together with a set_goalie_profile field for it. The
# butterfly slide push IS tiered (slide_push_speed_mps); the bots' shot model
# does not price the slide, so it has no mirror.
#
# To add a tier: add a Difficulty enum value, a factory, and a for_difficulty arm.
# To add a knob: add a field + _init param, set it in all three factories, and
# consume it in GoalieController._apply_skill_profile. If the bots' shot model
# reads the same quantity (see AI MIRROR), also sync it in
# AIGoalieModel.set_goalie_profile — otherwise the bots keep scoring against
# the Hard goalie's version of it.

enum Difficulty {
	EASY = 0,     # the floor — positionally deep, slow arms, fat rebounds, laggy reads
	NORMAL = 1,   # the middle — a fair fight, clearly softer than Hard
	HARD = 2,     # the ceiling — exactly the authored goalie
}

# Glove/blocker read latency (s) before the shot hand reach starts.
var arm_reaction_delay_s: float
# Back-door read latency (s) before the standing cross-crease drive engages.
var cross_crease_react_delay_s: float
# Stick-strip reach (m): the goalie pokes a carried puck within this radius.
var poke_radius_m: float
# Cap (s) on the grounded screen-occlusion pickup delay (worst-case time a body
# can hide the puck from the goalie before the read starts).
var screen_max_extra_delay_s: float
# Extra read latency (s) while scrambling — standing up out of a butterfly, or
# out of the play on a committed lunge. The only tiered caught-unset latency:
# merely travelling on his feet pays the small untiered
# GoalieController.move_read_speed_delay, because there his real cost is the
# momentum carried through the reaction freeze, which already tier-varies off
# lateral_accel_mps2 (worse edges take longer to kill, so he drifts further past
# the puck — GoalieController.unset_drift_decel_ratio).
var move_read_scramble_delay_s: float
# Challenge depth (m) at the doorstep / mid-range on the depth chart. Lower sits
# the goalie deeper in the net, giving up shooting angle.
var depth_aggressive_m: float
var depth_base_m: float
# Glove / blocker reach speed cap (m/s) during shot hand saves. Lower → can't
# pull the corner back.
var glove_react_max_speed_mps: float
var blocker_react_max_speed_mps: float
# Butterfly rebound-steering pad toe-out (deg). Lower → rebounds kick to the slot.
var pad_toe_out_butterfly_deg: float
# Lateral push ramp acceleration (m/s²) — NOT the top speed. Lower → slow to get
# moving side-to-side.
var lateral_accel_mps2: float
# GO margin (s) for the behind-net rim stop — INF means the goalie never plays
# the puck. Timid puck play is a real weaker-goalie trait, so only the top
# tier leaves the net; it also means the feature carries zero risk on the
# tiers most players face.
var puck_play_go_margin_s: float
# Reflexive leg-drop read latency (s) — gates the butterfly drop that seals the
# five-hole and low ice, so it is the single strongest "reacts, but slower"
# lever. AI-mirrored (AIGoalieModel.goalie_leg_delay_s).
var reaction_delay_s: float
# Primed (quiet-eye) read latency (s) after watching a visible windup — the
# floor BOTH reads shortcut to when the goalie is pre-armed. Tiering it matters
# most at the bottom: beginners telegraph every shot (long deliberate wrister
# coils), so an untiered prearm makes Easy sharpest against exactly the shots
# newcomers take.
var prearmed_reaction_delay_s: float
# Pads-to-floor time (s) once the butterfly commits. AI-mirrored
# (AIGoalieModel.goalie_butterfly_drop_s).
var butterfly_drop_s: float
# Standing five-hole pad gap (m of separation each side of center). Higher = a
# visibly leaky five-hole whenever the paddle is off-centre (tracking, active
# blade); the drop still seals it, just later.
var five_hole_base_m: float
# READ STALENESS (s) — how old the goalie's belief about WHERE the shot is going
# is when he commits to it. The other knobs set WHEN he starts moving and HOW
# FAST, assuming he knows the destination; this one prices being WRONG. A
# shooter whose aim is stable through the wind-up is read perfectly at any lag;
# one who swings late beats the read by exactly this much. It also sets how fast
# he converges onto the true line once the puck is in flight, so a long shot is
# read correctly and an in-tight one is not. No RNG.
#
# The height-deception sweep (tests/unit/ai/test_goalie_disguise_read.gd)
# responds over roughly 0–0.10 s and is flat above: past that the goalie is
# already fully committed to the wrong read, so more staleness buys the shooter
# nothing.
var read_lag_s: float
# READ RE-SOLVE TIME (s) — how long it takes him to correct a WRONG belief once
# the puck is in flight and he can watch it. A separate knob from `read_lag_s`
# (the age of a wind-up read) so the deception window can lengthen without
# making the pre-read staler. It decides whether LATERAL deception pays: the
# belief is wrong only this long, and the arms recover in what is left of the
# flight.
#
# Anchored, not tuned: each tier re-solves in its own `reaction_delay_s`.
# Reading a line you got wrong is a fresh cold read, not a refinement, so a
# slower goalie stays wrong longer.
var read_converge_s: float
# Butterfly push-off speed (m/s) — the slide to a post or across the crease. A
# weaker goalie's push is softer, so he loses the race to the post on a wrap.
var slide_push_speed_mps: float


func _init(p_arm_reaction_delay_s: float, p_cross_crease_react_delay_s: float,
		p_poke_radius_m: float, p_screen_max_extra_delay_s: float,
		p_move_read_scramble_delay_s: float, p_depth_aggressive_m: float,
		p_depth_base_m: float, p_glove_react_max_speed_mps: float,
		p_blocker_react_max_speed_mps: float, p_pad_toe_out_butterfly_deg: float,
		p_lateral_accel_mps2: float, p_puck_play_go_margin_s: float,
		p_reaction_delay_s: float, p_prearmed_reaction_delay_s: float,
		p_butterfly_drop_s: float, p_five_hole_base_m: float,
		p_read_lag_s: float = 0.13,
		p_read_converge_s: float = 0.13,
		p_slide_push_speed_mps: float = 2.8) -> void:
	arm_reaction_delay_s = p_arm_reaction_delay_s
	cross_crease_react_delay_s = p_cross_crease_react_delay_s
	poke_radius_m = p_poke_radius_m
	screen_max_extra_delay_s = p_screen_max_extra_delay_s
	move_read_scramble_delay_s = p_move_read_scramble_delay_s
	depth_aggressive_m = p_depth_aggressive_m
	depth_base_m = p_depth_base_m
	glove_react_max_speed_mps = p_glove_react_max_speed_mps
	blocker_react_max_speed_mps = p_blocker_react_max_speed_mps
	pad_toe_out_butterfly_deg = p_pad_toe_out_butterfly_deg
	lateral_accel_mps2 = p_lateral_accel_mps2
	read_lag_s = p_read_lag_s
	read_converge_s = p_read_converge_s
	puck_play_go_margin_s = p_puck_play_go_margin_s
	reaction_delay_s = p_reaction_delay_s
	prearmed_reaction_delay_s = p_prearmed_reaction_delay_s
	butterfly_drop_s = p_butterfly_drop_s
	five_hole_base_m = p_five_hole_base_m
	slide_push_speed_mps = p_slide_push_speed_mps


# Hard == the GoalieController defaults verbatim, so applying Hard is a no-op
# (tests/unit/rules/test_goalie_profile_mirrors.gd).
static func hard() -> GoalieSkillProfile:
	return GoalieSkillProfile.new(0.18, 0.12, 0.25, 0.30, 0.12,
			1.75, 1.30, 5.0, 5.0, 18.0, 14.0, 0.9,
			0.13, 0.07, 0.20, 0.02, 0.05, 0.13, 2.8)


# Normal is the middle tier: enough goalie to punish a lazy shot, soft enough
# that a well-picked corner, a quick release off the catch, or a cross-crease
# play genuinely scores — the tier where shooting AND playmaking are both live
# options. Sits roughly mid-ladder on every axis: reads a beat slower than Hard
# (0.18 s legs ≈ the real elite cold-read floor, so the anticipation edge Hard
# keeps is gone), a step deeper on the arc, and arms that get most — not all —
# of the way to the corner.
static func normal() -> GoalieSkillProfile:
	return GoalieSkillProfile.new(0.28, 0.22, 0.16, 0.45, 0.20,
			1.35, 0.95, 3.8, 3.8, 11.0, 10.0, INF,
			0.18, 0.10, 0.25, 0.035, 0.10, 0.18, 2.3)


# Easy is the newcomer floor, tuned so ANY decently-aimed shot scores: he sits
# nearly on his goal line (net open from everywhere), the leg-drop read + slow
# butterfly leave the five-hole and low corners open from inside the slot, the
# arms start late and crawl (top corners open), the primed read barely beats the
# cold one (telegraphed beginner windups still score), and he's slow to get
# moving across. Only a shot more or less AT him gets saved.
static func easy() -> GoalieSkillProfile:
	return GoalieSkillProfile.new(0.45, 0.40, 0.08, 0.70, 0.35,
			0.90, 0.60, 2.4, 2.4, 5.0, 6.0, INF,
			0.30, 0.16, 0.32, 0.06, 0.16, 0.30, 1.8)


static func for_difficulty(difficulty: int) -> GoalieSkillProfile:
	match difficulty:
		Difficulty.EASY:
			return easy()
		Difficulty.NORMAL:
			return normal()
		_:
			return hard()
