class_name TrophyCopy
## The words for Game Pucks and what they unlock, shared by the Trophy Case,
## the HUD toast and the player screen's locked options. Static, so it translates through TranslationServer rather than tr().

# What a colour reward is for, by CosmeticUnlocks slot; anything unlisted
# reads TROPHY_UNLOCKS_COLOR.
const _COLOR_SLOT_KEYS: Dictionary[String, StringName] = {
	CosmeticUnlocks.LACES: &"TROPHY_UNLOCKS_LACES",
}

# One key per tier numeral; the catalogue test holds every ladder to this many.
const TIER_KEYS: Array[StringName] = [
	&"TROPHY_TIER_1", &"TROPHY_TIER_2", &"TROPHY_TIER_3", &"TROPHY_TIER_4", &"TROPHY_TIER_5",
]


static func t(key: StringName) -> String:
	return String(TranslationServer.translate(key))


# A single puck's name, or a ladder tier's ("Goal Scorer II") when `target` > 0.
static func puck_name(id: String, target: int = 0) -> String:
	var base: String = t(GamePucks.name_key(id))
	var tier: int = tier_index(id, target)
	if tier < 0 or tier >= TIER_KEYS.size():
		return base
	return t(&"TROPHY_TIER_NAME") % [base, t(TIER_KEYS[tier])]


# What a puck asks for; a ladder's description takes the tier's target.
static func puck_desc(id: String, target: int = 0) -> String:
	var desc: String = t(GamePucks.desc_key(id))
	return desc % target if target > 0 else desc


# A requirement's name: a puck's, or a ladder tier's for "id@target".
static func requirement_name(req: String) -> String:
	return puck_name(GamePucks.requirement_puck(req), GamePucks.requirement_target(req))


# One line per thing `req` unlocks: its titles, then its cosmetics.
static func unlock_lines(req: String) -> Array[String]:
	var out: Array[String] = []
	for title: String in Titles.unlocked_by(req):
		out.append(t(&"TROPHY_UNLOCKS_TITLE") % title_name(title))
	for row: Dictionary in CosmeticUnlocks.unlocked_by(req):
		out.append(cosmetic_line(String(row["slot"]), int(row["option"])))
	return out


# A cosmetic reward as the Trophy Case names it.
static func cosmetic_line(slot: String, option: int) -> String:
	if slot == CosmeticUnlocks.TAPE_SPAN:
		return t(&"TROPHY_UNLOCKS_TAPE") % t(StickTapeConfig.SPAN_NAME_KEYS[option])
	return t(_COLOR_SLOT_KEYS.get(slot, &"TROPHY_UNLOCKS_COLOR")) \
			% t(TapeColorRegistry.NAME_KEYS[option])


# A title's name; "" reads as the "None" choice.
static func title_name(id: String) -> String:
	return t(Titles.name_key(id)) if Titles.is_known(id) else t(&"PLAYER_TITLE_NONE")


# The tier `target` is on its ladder, 0-based; -1 for a single puck or a target
# that is not one of the ladder's tiers.
static func tier_index(id: String, target: int) -> int:
	if target <= 0:
		return -1
	return GamePucks.tiers_of(GamePucks.find(id)).find(target)


static func puck_toast(id: String, target: int) -> String:
	return t(&"TOAST_GAME_PUCK") % puck_name(id, target).to_upper()


