class_name Banners
## The banners (docs/game-pucks-plan.md): a named set of Game Pucks that, once
## every one is earned, raises the banner. Pure data; GamePuckRules decides.
##
## A requirement is a puck id ("hat_trick") or a ladder tier named by its target
## ("goals@50"). Banners are flat: one needs pucks, never other banners. BANNER_<ID>
## in the locale catalogue names it, and `title` is the Titles id raising it
## unlocks.

const ALL: Array[Dictionary] = [
	{"id": "power_forward", "needs": ["goals@50", "hits@50"], "title": "power_forward"},
	{"id": "shutdown", "needs": ["interceptions@50", "takeaways@50", "shots_blocked@50"],
		"title": "shutdown"},
	{"id": "two_way", "needs": ["goals@50", "assists@50", "interceptions@50", "takeaways@50"],
		"title": "two_way"},
	{"id": "iron_man", "needs": ["games_played@100"], "title": "iron_man"},
]


static func needs_of(banner: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for req: Variant in banner.get("needs", []):
		out.append(String(req))
	return out


# The puck id a requirement names, and the ladder target it asks for (0 for a
# single puck).
static func requirement_puck(req: String) -> String:
	return req.get_slice("@", 0)


static func requirement_target(req: String) -> int:
	return int(req.get_slice("@", 1)) if req.contains("@") else 0


static func title_of(banner: Dictionary) -> String:
	return String(banner.get("title", ""))


static func name_key(id: String) -> StringName:
	return StringName("BANNER_" + id.to_upper())
