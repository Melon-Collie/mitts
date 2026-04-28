class_name ColorVoteRules

# Pure rule layer: resolves per-player color votes into a final color pair for
# home and away teams. No engine APIs; deterministic given a seeded RNG so it
# is fully unit-testable.


# Counts how many times each color id appears in `votes`.
static func tally_votes(votes: Array[String]) -> Dictionary:
	var tally: Dictionary = {}
	for v: String in votes:
		tally[v] = int(tally.get(v, 0)) + 1
	return tally


# Picks the color with the most votes. Ties are broken uniformly at random
# via `rng`. Returns "" if the tally is empty so callers can substitute a
# default.
static func pick_winner(tally: Dictionary, rng: RandomNumberGenerator) -> String:
	if tally.is_empty():
		return ""
	var best: int = 0
	for v: int in tally.values():
		if v > best:
			best = v
	var leaders: Array[String] = []
	for k: String in tally.keys():
		if int(tally[k]) == best:
			leaders.append(k)
	if leaders.size() == 1:
		return leaders[0]
	return leaders[rng.randi_range(0, leaders.size() - 1)]


# Resolves both teams' colors from their vote pools. Returns [home_id, away_id].
#
# Rules:
#   • Tally each team's votes; the most-voted color wins. Ties broken randomly.
#   • Empty pool → fall back to the supplied default for that team.
#   • If home and away both resolve to the same color, the AWAY team re-rolls
#     by re-running pick_winner over its tally with the home pick excluded.
#     If no away votes remain after exclusion, away is picked uniformly from
#     `all_color_ids` minus home's pick.
static func resolve_team_colors(
		home_votes: Array[String],
		away_votes: Array[String],
		all_color_ids: Array[String],
		default_home_id: String,
		default_away_id: String,
		rng: RandomNumberGenerator) -> Array[String]:
	var home_tally: Dictionary = tally_votes(home_votes)
	var away_tally: Dictionary = tally_votes(away_votes)

	var home_id: String = pick_winner(home_tally, rng)
	if home_id.is_empty():
		home_id = default_home_id

	var away_id: String = pick_winner(away_tally, rng)
	if away_id.is_empty():
		away_id = default_away_id

	if away_id == home_id:
		var filtered: Dictionary = {}
		for k: String in away_tally.keys():
			if k != home_id:
				filtered[k] = away_tally[k]
		away_id = pick_winner(filtered, rng)
		if away_id.is_empty():
			var pool: Array[String] = []
			for c: String in all_color_ids:
				if c != home_id:
					pool.append(c)
			if pool.is_empty():
				away_id = home_id
			else:
				away_id = pool[rng.randi_range(0, pool.size() - 1)]

	var result: Array[String] = [home_id, away_id]
	return result
