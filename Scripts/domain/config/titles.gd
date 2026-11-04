class_name Titles
## The titles a player can wear (docs/game-pucks-plan.md, Phase 2). Pure data:
## each is earned by raising the banner that names it as its `title`
## (Banners.ALL), and TITLE_<ID> in the locale catalogue names it. An id travels
## the wire with a player's look; "" is no title.

const ALL: Array[String] = ["power_forward", "shutdown", "two_way", "iron_man", "playmaker",
		"sniper"]


static func is_known(id: String) -> bool:
	return ALL.has(id)


# A wire or prefs value as a title this build knows; anything else wears none.
static func coerce(id: String) -> String:
	return id if is_known(id) else ""


static func name_key(id: String) -> StringName:
	return StringName("TITLE_" + id.to_upper())
