class_name GamePucks
## The Game Puck catalogue (docs/game-pucks-plan.md). Pure data: GamePuckRules
## decides what is earned, TrophyService records it and mirrors the pucks
## flagged for Steam. A reward (a Titles row, a CosmeticUnlocks reward) names
## the puck that unlocks it by a requirement: a puck id ("hat_trick") or a
## ladder tier named by its target ("goals@50").
##
## A row's `id` is the puck's own id, stored in the ledger and keyed into the
## locale catalogue: PUCK_<ID> names it and PUCK_<ID>_DESC describes it (a
## ladder's description takes the tier's target as %d; a combo has none, its
## requirements are its description). `steam` is the
## Steamworks API Name of the achievement it mirrors; a ladder's `steam_tiers`
## maps a tier's target to one. A puck with neither stays in-game, which costs
## no Steamworks setup (steam/ACHIEVEMENTS.md lists every mirrored id).
##
## Condition kinds (`cond.kind`):
##   "count"   — a ladder: the lifetime counter `field` (a SteamStats key, or
##               "points") reaching each of `tiers`, ascending. Derived from the
##               Steam User Stats totals every time, never stored.
##   "game"    — one game's stat `field` (a GamePuckRules.game_dict key) reached
##               `min`.
##   "special" — a compound game-over condition named by `key`, decided in
##               GamePuckRules._special_met.
##   "event"   — a moment named by `key`, fired by a TrophyService hook; `min`,
##               when present, is its threshold.
##   "roster"  — a match whose lobby holds `steam_id`, never earned by that
##               player themselves.
##   "feat"    — a specific play, detected on the host when a goal is credited
##               (FeatRules, which names every one) and sent to the player who
##               made it.
##   "combo"   — every requirement in `needs` met: pucks, ladder tiers or other
##               combos, never itself through the chain. Derived, never stored.

const FREIGHT_TRAIN := "freight_train"
const STUDENT := "student"
const CUSTOM_BUILD := "custom_build"
const PLAY_WITH_BUUKIE := "play_with_buukie"
const COMBO := "combo"

const BUUKIE_STEAM_ID := 76561198027551159

const ALL: Array[Dictionary] = [
	# ── Ladders ──────────────────────────────────────────────────────────────
	{"id": "goals", "cond": {"kind": "count", "field": "goals"},
		"tiers": [10, 50, 250, 1000], "steam_tiers": {50: "ACH_GOALS_50"}},
	{"id": "assists", "cond": {"kind": "count", "field": "assists"},
		"tiers": [10, 50, 250, 1000], "steam_tiers": {50: "ACH_SETUP_ARTIST"}},
	{"id": "points", "cond": {"kind": "count", "field": "points"},
		"tiers": [25, 100, 500, 2000]},
	{"id": "hits", "cond": {"kind": "count", "field": "hits"},
		"tiers": [10, 50, 100, 500, 1000], "steam_tiers": {100: "ACH_ENFORCER"}},
	{"id": "interceptions", "cond": {"kind": "count", "field": "interceptions"},
		"tiers": [10, 50, 250, 1000]},
	{"id": "takeaways", "cond": {"kind": "count", "field": "takeaways"},
		"tiers": [10, 50, 250, 1000]},
	{"id": "shots_blocked", "cond": {"kind": "count", "field": "shots_blocked"},
		"tiers": [10, 50, 250, 1000]},
	{"id": "faceoff_wins", "cond": {"kind": "count", "field": "faceoff_wins"},
		"tiers": [25, 100, 500, 2000]},
	{"id": "wins", "cond": {"kind": "count", "field": "wins"},
		"tiers": [5, 25, 100, 250]},
	{"id": "games_played", "cond": {"kind": "count", "field": "games_played"},
		"tiers": [10, 25, 100, 250, 500], "steam_tiers": {25: "ACH_VETERAN"}},
	# ── One game ─────────────────────────────────────────────────────────────
	{"id": "first_goal", "steam": "ACH_FIRST_GOAL",
		"cond": {"kind": "game", "field": "goals", "min": 1}},
	{"id": "hat_trick", "steam": "ACH_HAT_TRICK",
		"cond": {"kind": "game", "field": "goals", "min": 3}},
	{"id": "three_helpers", "steam": "ACH_THREE_HELPERS",
		"cond": {"kind": "game", "field": "assists", "min": 3}},
	{"id": "big_night", "steam": "ACH_BIG_NIGHT",
		"cond": {"kind": "game", "field": "points", "min": 5}},
	# 3, not 5: a block is a crouch into a live puck with no auto-block, so five
	# in one game is a grind.
	{"id": "brick_wall", "steam": "ACH_BRICK_WALL",
		"cond": {"kind": "game", "field": "shots_blocked", "min": 3}},
	{"id": "one_timer", "steam": "ACH_ONE_TIMER",
		"cond": {"kind": "game", "field": "one_timer_goals", "min": 1}},
	{"id": "tip_in", "steam": "ACH_TIP_IN",
		"cond": {"kind": "game", "field": "tip_goals", "min": 1}},
	{"id": "overtime_hero", "steam": "ACH_OVERTIME_HERO",
		"cond": {"kind": "game", "field": "ot_goals", "min": 1}},
	{"id": "faceoff_boss", "steam": "ACH_FACEOFF_BOSS",
		"cond": {"kind": "game", "field": "faceoff_wins", "min": 5}},
	{"id": "pickpocket", "steam": "ACH_PICKPOCKET",
		"cond": {"kind": "game", "field": "takeaways", "min": 5}},
	{"id": "shutout", "steam": "ACH_SHUTOUT",
		"cond": {"kind": "special", "key": "shutout"}},
	{"id": "first_win", "steam": "ACH_FIRST_WIN",
		"cond": {"kind": "special", "key": "win"}},
	# ── Moments ──────────────────────────────────────────────────────────────
	# `min` is the impact force body_checked_player carries (weight × closing
	# speed), where 3.0 is a glancing bump and 14.0 a full-strength check
	# (SkaterVFX._CHECK_FORCE_*): 11.0 is a clearly hard hit, not an everyday one.
	{"id": FREIGHT_TRAIN, "steam": "ACH_FREIGHT_TRAIN",
		"cond": {"kind": "event", "key": "big_hit", "min": 11.0}},
	{"id": STUDENT, "steam": "ACH_STUDENT",
		"cond": {"kind": "event", "key": "tutorials_done"}},
	{"id": CUSTOM_BUILD, "steam": "ACH_CUSTOM_BUILD",
		"cond": {"kind": "event", "key": "build_edited"}},
	# ── Plays (FeatRules) ────────────────────────────────────────────────────
	{"id": "snipe", "cond": {"kind": "feat"}},
	{"id": "backhand_shelf", "cond": {"kind": "feat"}},
	{"id": "one_timer_feed", "cond": {"kind": "feat"}},
	{"id": "pick_and_finish", "cond": {"kind": "feat"}},
	{"id": "strip_and_finish", "cond": {"kind": "feat"}},
	{"id": "one_timer_dot", "cond": {"kind": "feat"}},
	# ── Who you played with ──────────────────────────────────────────────────
	{"id": PLAY_WITH_BUUKIE, "steam": "ACH_PLAY_WITH_BUUKIE", "hidden": true,
		"cond": {"kind": "roster", "steam_id": BUUKIE_STEAM_ID}},
	# ── Combos ───────────────────────────────────────────────────────────────
	# One that unlocks a title carries the title's name.
	{"id": "power_forward", "cond": {"kind": COMBO, "needs": ["goals@50", "hits@50"]}},
	{"id": "shutdown", "cond": {"kind": COMBO,
		"needs": ["interceptions@50", "takeaways@50", "shots_blocked@50"]}},
	{"id": "two_way", "cond": {"kind": COMBO,
		"needs": ["goals@50", "assists@50", "interceptions@50", "takeaways@50"]}},
	{"id": "iron_man", "cond": {"kind": COMBO, "needs": ["games_played@100"]}},
	{"id": "playmaker", "cond": {"kind": COMBO, "needs": ["assists@250", "one_timer_feed"]}},
	{"id": "sniper", "cond": {"kind": COMBO, "needs": ["goals@250", "snipe"]}},
	{"id": "breadman", "cond": {"kind": COMBO, "needs": ["assists@50", "three_helpers"]}},
]


static func find(id: String) -> Dictionary:
	for entry: Dictionary in ALL:
		if String(entry["id"]) == id:
			return entry
	return {}


# "" for an empty entry (GamePucks.find on an unknown id).
static func kind_of(entry: Dictionary) -> String:
	return String((entry.get("cond", {}) as Dictionary).get("kind", ""))


static func is_ladder(entry: Dictionary) -> bool:
	return kind_of(entry) == "count"


static func is_combo(entry: Dictionary) -> bool:
	return kind_of(entry) == COMBO


# A combo's requirements; empty for anything else.
static func needs_of(entry: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for req: Variant in (entry.get("cond", {}) as Dictionary).get("needs", []):
		out.append(String(req))
	return out


# The puck id a requirement names, and the ladder target it asks for (0 for a
# whole puck).
static func requirement_puck(req: String) -> String:
	return req.get_slice("@", 0)


static func requirement_target(req: String) -> int:
	return int(req.get_slice("@", 1)) if req.contains("@") else 0


static func tiers_of(entry: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for t: Variant in entry.get("tiers", []):
		out.append(int(t))
	return out


# The threshold of the event puck named `key`, or -1.0 when there is none, so a
# renamed entry fails closed rather than firing on every occurrence.
static func event_threshold(key: String) -> float:
	var entry: Dictionary = _event_entry(key)
	if entry.is_empty():
		return -1.0
	return float((entry["cond"] as Dictionary).get("min", -1.0))


static func event_puck(key: String) -> String:
	var entry: Dictionary = _event_entry(key)
	return String(entry["id"]) if not entry.is_empty() else ""


# Every Steamworks API Name the catalogue mirrors, single pucks and ladder tiers.
static func all_steam_ids() -> Array[String]:
	var out: Array[String] = []
	for entry: Dictionary in ALL:
		if entry.has("steam"):
			out.append(String(entry["steam"]))
		for target: Variant in (entry.get("steam_tiers", {}) as Dictionary):
			out.append(String(entry["steam_tiers"][target]))
	return out


static func name_key(id: String) -> StringName:
	return StringName("PUCK_" + id.to_upper())


static func desc_key(id: String) -> StringName:
	return StringName("PUCK_" + id.to_upper() + "_DESC")


static func _event_entry(key: String) -> Dictionary:
	for entry: Dictionary in ALL:
		var cond: Dictionary = entry["cond"]
		if cond.get("kind", "") == "event" and cond.get("key", "") == key:
			return entry
	return {}
