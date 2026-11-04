class_name CosmeticUnlocks
## Which cosmetic options a player may pick (docs/game-pucks-plan.md, Phase 4).
## A colour slot offers the team's two colours, white and black for free, and
## the tape-coverage slot its six original spans; any other option is offered
## only as a reward row — one slot, one option and the banner that unlocks it —
## so a reward never reaches a slot it was not meant for. A pick the player may
## not wear is worn as the slot's default: the team colour, or heel-to-mid tape.
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

# { "slot", "option", "banner" } — a Banners id raises it. The two signature
# tape jobs are homages to two players' real ones, never named.
const REWARDS: Array[Dictionary] = [
	{"slot": TAPE_SPAN, "option": StickTapeConfig.Span.SPACED, "banner": "sniper"},
	{"slot": TAPE_SPAN, "option": StickTapeConfig.Span.BOTTOM_STRIP, "banner": "playmaker"},
]


static func is_free(slot: String, option: int) -> bool:
	if slot == TAPE_SPAN:
		return FREE_SPANS.has(option)
	return COLOR_SLOTS.has(slot) and FREE_COLORS.has(option)


# How many options a slot has: the palette's colours, or the spans.
static func option_count(slot: String) -> int:
	return StickTapeConfig.Span.size() if slot == TAPE_SPAN else TapeColorRegistry.count()


# The banner whose raising unlocks `option` in `slot`, "" when none does.
static func reward_banner(slot: String, option: int) -> String:
	for row: Dictionary in REWARDS:
		if String(row["slot"]) == slot and int(row["option"]) == option:
			return String(row["banner"])
	return ""


# Free, or a reward whose banner is among `raised`.
static func is_available(slot: String, option: int, raised: Array[String]) -> bool:
	if is_free(slot, option):
		return true
	var banner: String = reward_banner(slot, option)
	return not banner.is_empty() and raised.has(banner)


# The options a slot's picker lists for a player with `raised` banners, in
# palette order.
static func available(slot: String, raised: Array[String]) -> Array[int]:
	var out: Array[int] = []
	for option: int in option_count(slot):
		if is_available(slot, option, raised):
			out.append(option)
	return out


# The reward options of `slot` the player has not unlocked, for a picker that
# shows what is still to earn.
static func locked(slot: String, raised: Array[String]) -> Array[int]:
	var out: Array[int] = []
	for row: Dictionary in REWARDS:
		if String(row["slot"]) == slot and not raised.has(String(row["banner"])):
			out.append(int(row["option"]))
	return out


# The reward rows a banner unlocks.
static func rewards_of(banner: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row: Dictionary in REWARDS:
		if String(row["banner"]) == banner:
			out.append(row)
	return out


# Every banner, for a caller that should switch only what no reward could ever
# unlock (a prefs load before Steam has said what is raised).
static func every_banner() -> Array[String]:
	var out: Array[String] = []
	for banner: Dictionary in Banners.ALL:
		out.append(String(banner["id"]))
	return out


# A packed tape code as the local player may wear it.
static func worn_tape_code(code: int, raised: Array[String]) -> int:
	var tape: StickTapeConfig = StickTapeConfig.from_code(code)
	tape.blade_color = _worn(TAPE_BLADE, tape.blade_color, raised)
	tape.knob_color = _worn(TAPE_KNOB, tape.knob_color, raised)
	tape.toe_color = _worn(TAPE_TOE, tape.toe_color, raised)
	if not is_available(TAPE_SPAN, tape.span, raised):
		tape.span = StickTapeConfig.Span.HEEL_TO_MID
	if tape.paint_custom:
		var colors: Array[int] = []
		for zone: int in StickModelRegistry.ZONE_COUNT:
			colors.append(_worn(STICK_PAINT, tape.paint[zone], raised))
		tape.set_paint(colors)
	return tape.to_code()


# A packed gear-style code as the local player may wear it.
static func worn_gear_code(code: int, raised: Array[String]) -> int:
	var gear: GearStyleConfig = GearStyleConfig.from_code(code)
	gear.lace_color = _worn(LACES, gear.lace_color, raised)
	return gear.to_code()


static func _worn(slot: String, option: int, raised: Array[String]) -> int:
	return option if is_available(slot, option, raised) else TapeColorRegistry.TEAM_INDEX
