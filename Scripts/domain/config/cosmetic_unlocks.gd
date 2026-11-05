class_name CosmeticUnlocks
## Which cosmetic options a player may pick (docs/game-pucks-plan.md, Phase 4).
## A colour slot offers the team's two colours, white and black for free, and
## the tape-coverage slot its six original spans; any other option is offered
## only as a reward row — one slot, one option and the Game Puck requirement
## that unlocks it (a puck id or a ladder tier, "goals@50") —
## so a reward never reaches a slot it was not meant for. A pick the player may
## not wear is worn as the slot's default: the team colour, or heel-to-mid tape.
## `earned` throughout is the reward requirements the player has met
## (GamePuckRules.met_requirements over reward_pucks()).
##
## The palette keeps every colour it ever had, so old codes and bots still
## decode; this file decides only what the player screen offers and what the
## local player is sent out wearing. Peers are never checked (no anti-cheat).

const TAPE_BLADE := "tape_blade"
const TAPE_KNOB := "tape_knob"
const TAPE_TOE := "tape_toe"
const LACES := "laces"
const STICK_PAINT := "stick_paint"
const TAPE_SPAN := "tape_span"
const COLOR_SLOTS: Array[String] = [TAPE_BLADE, TAPE_KNOB, TAPE_TOE, LACES, STICK_PAINT]
const SLOTS: Array[String] = [TAPE_BLADE, TAPE_KNOB, TAPE_TOE, LACES, STICK_PAINT, TAPE_SPAN]

const FREE_COLORS: Array[int] = [
	TapeColorRegistry.TEAM_INDEX, TapeColorRegistry.TEAM_SECOND_INDEX,
	TapeColorRegistry.WHITE_INDEX, TapeColorRegistry.BLACK_INDEX,
]

const FREE_SPANS: Array[int] = [
	StickTapeConfig.Span.HEEL_TO_MID, StickTapeConfig.Span.TOE, StickTapeConfig.Span.MID,
	StickTapeConfig.Span.FULL, StickTapeConfig.Span.NONE, StickTapeConfig.Span.MID_TO_TOE,
]

# { "slot", "option", "puck" }. The signature tape jobs and the yellow laces
# are homages to real players' looks, never named.
const REWARDS: Array[Dictionary] = [
	{"slot": TAPE_SPAN, "option": StickTapeConfig.Span.SPACED, "puck": "hat_trick"},
	{"slot": TAPE_SPAN, "option": StickTapeConfig.Span.BOTTOM_STRIP, "puck": "breadman"},
	{"slot": LACES, "option": TapeColorRegistry.YELLOW_INDEX, "puck": "one_timer_dot"},
]


static func is_free(slot: String, option: int) -> bool:
	if slot == TAPE_SPAN:
		return FREE_SPANS.has(option)
	return COLOR_SLOTS.has(slot) and FREE_COLORS.has(option)


# How many options a slot has: the palette's colours, or the spans.
static func option_count(slot: String) -> int:
	return StickTapeConfig.Span.size() if slot == TAPE_SPAN else TapeColorRegistry.count()


# The requirement that unlocks `option` in `slot`, "" when none does.
static func reward_puck(slot: String, option: int) -> String:
	for row: Dictionary in REWARDS:
		if String(row["slot"]) == slot and int(row["option"]) == option:
			return String(row["puck"])
	return ""


# Free, or a reward whose requirement is among `earned`.
static func is_available(slot: String, option: int, earned: Array[String]) -> bool:
	if is_free(slot, option):
		return true
	var req: String = reward_puck(slot, option)
	return not req.is_empty() and earned.has(req)


# The options a slot's picker lists for a player who has `earned`, in palette
# order.
static func available(slot: String, earned: Array[String]) -> Array[int]:
	var out: Array[int] = []
	for option: int in option_count(slot):
		if is_available(slot, option, earned):
			out.append(option)
	return out


# The reward rows a requirement unlocks.
static func unlocked_by(req: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row: Dictionary in REWARDS:
		if String(row["puck"]) == req:
			out.append(row)
	return out


# Every requirement a reward names: what to ask GamePuckRules about, and, taken
# as all earned, what switches only the options no reward could ever unlock (a
# prefs load before Steam has said what is earned).
static func reward_pucks() -> Array[String]:
	var out: Array[String] = []
	for row: Dictionary in REWARDS:
		if not out.has(String(row["puck"])):
			out.append(String(row["puck"]))
	return out


# A packed tape code as the local player may wear it.
static func worn_tape_code(code: int, earned: Array[String]) -> int:
	var tape: StickTapeConfig = StickTapeConfig.from_code(code)
	tape.blade_color = _worn(TAPE_BLADE, tape.blade_color, earned)
	tape.knob_color = _worn(TAPE_KNOB, tape.knob_color, earned)
	tape.toe_color = _worn(TAPE_TOE, tape.toe_color, earned)
	if not is_available(TAPE_SPAN, tape.span, earned):
		tape.span = StickTapeConfig.Span.HEEL_TO_MID
	if tape.paint_custom:
		var colors: Array[int] = []
		for zone: int in StickModelRegistry.ZONE_COUNT:
			colors.append(_worn(STICK_PAINT, tape.paint[zone], earned))
		tape.set_paint(colors)
	return tape.to_code()


# A packed gear-style code as the local player may wear it.
static func worn_gear_code(code: int, earned: Array[String]) -> int:
	var gear: GearStyleConfig = GearStyleConfig.from_code(code)
	gear.lace_color = _worn(LACES, gear.lace_color, earned)
	return gear.to_code()


static func _worn(slot: String, option: int, earned: Array[String]) -> int:
	return option if is_available(slot, option, earned) else TapeColorRegistry.TEAM_INDEX
