class_name TrophyCopy
## The words for Game Pucks and banners, shared by the Trophy Case and the HUD
## toast. Static, so it translates through TranslationServer rather than tr().

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


static func banner_name(id: String) -> String:
	return t(Banners.name_key(id))


# The tier `target` is on its ladder, 0-based; -1 for a single puck or a target
# that is not one of the ladder's tiers.
static func tier_index(id: String, target: int) -> int:
	if target <= 0:
		return -1
	return GamePucks.tiers_of(GamePucks.find(id)).find(target)


static func puck_toast(id: String, target: int) -> String:
	return t(&"TOAST_GAME_PUCK") % puck_name(id, target).to_upper()


static func banner_toast(id: String) -> String:
	return t(&"TOAST_BANNER_RAISED") % banner_name(id).to_upper()
