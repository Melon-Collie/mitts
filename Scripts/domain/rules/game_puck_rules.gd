class_name GamePuckRules
## Pure evaluation of the Game Puck catalogue (GamePucks) and the banners
## (Banners). No engine, no Steam, no state: given a finished game's stats, the
## lifetime counters and the ledger, it says what is earned and how far along
## everything is. Earning is idempotent, so callers may evaluate every game-over
## without bookkeeping.
##
## `totals` throughout is the Steam User Stats totals keyed by SteamStats `key`
## (SteamStatRecorder.totals): empty without Steam, which simply reads as zero.


# One game's stats in the shape "game" conditions and SteamStats increments read.
static func game_dict(stats: PlayerStats) -> Dictionary:
	return {
		"goals": stats.goals,
		"assists": stats.assists,
		"points": stats.goals + stats.assists,
		"shots_on_goal": stats.shots_on_goal,
		"hits": stats.hits,
		"shots_blocked": stats.shots_blocked,
		"hits_taken": stats.hits_taken,
		"takeaways": stats.takeaways,
		"interceptions": stats.interceptions,
		"giveaways": stats.giveaways,
		"faceoff_wins": stats.faceoff_wins,
		"one_timer_goals": stats.one_timer_goals,
		"tip_goals": stats.tip_goals,
		"ot_goals": stats.ot_goals,
	}


# Puck ids earned by this one game. `ctx` carries the game-level fields the
# "special" conditions read: { "outcome": "win"/"loss"/"draw", "goals_for",
# "goals_against" }.
static func earned_game(game: Dictionary, ctx: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for entry: Dictionary in GamePucks.ALL:
		var cond: Dictionary = entry["cond"]
		match String(cond.get("kind", "")):
			"game":
				if int(game.get(cond["field"], 0)) >= int(cond["min"]):
					out.append(String(entry["id"]))
			"special":
				if _special_met(String(cond["key"]), ctx):
					out.append(String(entry["id"]))
	return out


# Puck ids earned by the match roster: a "roster" condition names a SteamID64
# that must be among `present_steam_ids`, and that player cannot earn it
# themselves. A zero local id (no Steam) earns nothing.
static func earned_roster(present_steam_ids: Array, local_steam_id: int) -> Array[String]:
	var out: Array[String] = []
	if local_steam_id == 0:
		return out
	for entry: Dictionary in GamePucks.ALL:
		var cond: Dictionary = entry["cond"]
		if cond.get("kind", "") != "roster":
			continue
		var target: int = int(cond.get("steam_id", 0))
		if target == 0 or local_steam_id == target:
			continue
		if present_steam_ids.has(target):
			out.append(String(entry["id"]))
	return out


# The lifetime counter a ladder reads. "points" is goals + assists when the
# totals do not carry it.
static func counter(totals: Dictionary, field: String) -> int:
	if field == "points" and not totals.has("points"):
		return int(totals.get("goals", 0)) + int(totals.get("assists", 0))
	return int(totals.get(field, 0))


# How many of a ladder's tiers `totals` has reached.
static func tiers_reached(entry: Dictionary, totals: Dictionary) -> int:
	var value: int = counter(totals, String((entry["cond"] as Dictionary)["field"]))
	var reached: int = 0
	for target: int in GamePucks.tiers_of(entry):
		if value >= target:
			reached += 1
	return reached


# Ladder tiers reached in `after` but not in `before`, oldest ladder row first,
# as { "id", "target" }.
static func crossed_tiers(before: Dictionary, after: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in GamePucks.ALL:
		if not GamePucks.is_ladder(entry):
			continue
		var field: String = String((entry["cond"] as Dictionary)["field"])
		var was: int = counter(before, field)
		var now: int = counter(after, field)
		for target: int in GamePucks.tiers_of(entry):
			if was < target and now >= target:
				out.append({"id": String(entry["id"]), "target": target})
	return out


# Every Steamworks id `totals` and `ledger` have earned: the single pucks the
# ledger holds and the ladder tiers reached, wherever a row is flagged.
static func earned_steam_ids(totals: Dictionary, ledger: TrophyLedger) -> Array[String]:
	var out: Array[String] = []
	for entry: Dictionary in GamePucks.ALL:
		if entry.has("steam") and ledger != null and ledger.has(String(entry["id"])):
			out.append(String(entry["steam"]))
		var steam_tiers: Dictionary = entry.get("steam_tiers", {})
		if steam_tiers.is_empty():
			continue
		var value: int = counter(totals, String((entry["cond"] as Dictionary)["field"]))
		for target: Variant in steam_tiers:
			if value >= int(target):
				out.append(String(steam_tiers[target]))
	return out


static func requirement_met(req: String, totals: Dictionary, ledger: TrophyLedger) -> bool:
	var puck: String = Banners.requirement_puck(req)
	var target: int = Banners.requirement_target(req)
	if target > 0:
		var entry: Dictionary = GamePucks.find(puck)
		if entry.is_empty():
			return false
		return counter(totals, String((entry["cond"] as Dictionary)["field"])) >= target
	return ledger != null and ledger.has(puck)


# How many of a banner's requirements are met.
static func banner_progress(banner: Dictionary, totals: Dictionary, ledger: TrophyLedger) -> int:
	var met: int = 0
	for req: String in Banners.needs_of(banner):
		if requirement_met(req, totals, ledger):
			met += 1
	return met


static func is_raised(banner: Dictionary, totals: Dictionary, ledger: TrophyLedger) -> bool:
	var needs: Array[String] = Banners.needs_of(banner)
	return not needs.is_empty() and banner_progress(banner, totals, ledger) == needs.size()


static func raised_banners(totals: Dictionary, ledger: TrophyLedger) -> Array[String]:
	var out: Array[String] = []
	for banner: Dictionary in Banners.ALL:
		if is_raised(banner, totals, ledger):
			out.append(String(banner["id"]))
	return out


static func _special_met(key: String, ctx: Dictionary) -> bool:
	match key:
		"win":
			return String(ctx.get("outcome", "")) == "win"
		"shutout":
			return String(ctx.get("outcome", "")) == "win" \
					and int(ctx.get("goals_against", 1)) == 0
	return false
