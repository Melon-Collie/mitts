class_name CosmeticUnlocks
## Which cosmetic options a player may pick (docs/game-pucks-plan.md, Phase 4).
## A colour slot offers the team's two colours, white and black for free; any
## other option is offered only as a reward row — one slot, one option and the
## banner that unlocks it — so a reward never reaches a slot it was not meant
## for. A pick the player may not wear is worn as the team colour.
##
## The palette keeps every colour it ever had, so old codes and bots still
## decode; this file decides only what the player screen offers and what the
## local player is sent out wearing. Peers are never checked (no anti-cheat).

const TAPE_BLADE := "tape_blade"
const TAPE_KNOB := "tape_knob"
const LACES := "laces"
const COLOR_SLOTS: Array[String] = [TAPE_BLADE, TAPE_KNOB, LACES]

const FREE_COLORS: Array[int] = [
	TapeColorRegistry.TEAM_INDEX, TapeColorRegistry.TEAM_SECOND_INDEX,
	TapeColorRegistry.WHITE_INDEX, TapeColorRegistry.BLACK_INDEX,
]

# { "slot", "option", "banner" } — a Banners id raises it.
const REWARDS: Array[Dictionary] = []


static func is_free(slot: String, option: int) -> bool:
	return COLOR_SLOTS.has(slot) and FREE_COLORS.has(option)


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
	for option: int in TapeColorRegistry.count():
		if is_available(slot, option, raised):
			out.append(option)
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
	return tape.to_code()


# A packed gear-style code as the local player may wear it.
static func worn_gear_code(code: int, raised: Array[String]) -> int:
	var gear: GearStyleConfig = GearStyleConfig.from_code(code)
	gear.lace_color = _worn(LACES, gear.lace_color, raised)
	return gear.to_code()


static func _worn(slot: String, option: int, raised: Array[String]) -> int:
	return option if is_available(slot, option, raised) else TapeColorRegistry.TEAM_INDEX
