extends GutTest

# SteamStatRecorder.increments() — pure per-game deltas for the Steam User Stats
# mirror — plus a consistency check that every Game Puck ladder is backed by a
# mirrored stat (otherwise it could never climb without a reachable backend).

func _stats(goals: int, assists: int, sog: int, hits: int, blocks: int) -> PlayerStats:
	var s := PlayerStats.new()
	s.goals = goals
	s.assists = assists
	s.shots_on_goal = sog
	s.hits = hits
	s.shots_blocked = blocks
	return s


func test_increments_map_per_game_stat_fields() -> void:
	var d := SteamStatRecorder.increments(_stats(2, 1, 4, 3, 1), "win")
	assert_eq(d[SteamStats.GOALS], 2)
	assert_eq(d[SteamStats.ASSISTS], 1)
	assert_eq(d[SteamStats.SHOTS], 4)
	assert_eq(d[SteamStats.HITS], 3)
	assert_eq(d[SteamStats.BLOCKS], 1)


func test_increments_map_extended_stat_fields() -> void:
	var s := _stats(0, 0, 0, 0, 0)
	s.hits_taken = 5
	s.takeaways = 6
	s.giveaways = 7
	s.faceoff_wins = 8
	s.interceptions = 9
	var d := SteamStatRecorder.increments(s, "loss")
	assert_eq(d[SteamStats.HITS_TAKEN], 5)
	assert_eq(d[SteamStats.TAKEAWAYS], 6)
	assert_eq(d[SteamStats.GIVEAWAYS], 7)
	assert_eq(d[SteamStats.FACEOFF_WINS], 8)
	assert_eq(d[SteamStats.INTERCEPTIONS], 9)


func test_increments_map_the_penalty_stats() -> void:
	var s := _stats(0, 0, 0, 0, 0)
	s.pim = 4
	s.pp_goals = 2
	s.pp_assists = 3
	var d := SteamStatRecorder.increments(s, "win")
	assert_eq(d[SteamStats.PIM], 4)
	assert_eq(d[SteamStats.PP_GOALS], 2)
	assert_eq(d[SteamStats.PP_POINTS], 5, "his goals and his assists a man up")


func test_games_played_always_increments_by_one() -> void:
	assert_eq(SteamStatRecorder.increments(_stats(0, 0, 0, 0, 0), "loss")[SteamStats.GAMES], 1)
	assert_eq(SteamStatRecorder.increments(_stats(9, 9, 9, 9, 9), "win")[SteamStats.GAMES], 1)


func test_wins_increment_only_on_win() -> void:
	assert_eq(SteamStatRecorder.increments(_stats(0, 0, 0, 0, 0), "win")[SteamStats.WINS], 1)
	assert_eq(SteamStatRecorder.increments(_stats(0, 0, 0, 0, 0), "loss")[SteamStats.WINS], 0)
	assert_eq(SteamStatRecorder.increments(_stats(0, 0, 0, 0, 0), "draw")[SteamStats.WINS], 0)


func test_null_stats_yields_empty() -> void:
	assert_eq(SteamStatRecorder.increments(null, "win").size(), 0)


func test_stat_ids_are_unique() -> void:
	var seen: Dictionary = {}
	for entry in SteamStats.ALL:
		var id: String = entry["id"]
		assert_false(seen.has(id), "duplicate stat id: %s" % id)
		seen[id] = true


# Every ladder's counter must be backed by a mirrored stat (or derive from them,
# as points do), or it can never climb without a reachable backend.
func test_every_ladder_has_a_backing_stat() -> void:
	var stat_keys: Dictionary = {"points": true}
	for entry in SteamStats.ALL:
		stat_keys[String(entry["key"])] = true
	for puck: Dictionary in GamePucks.ALL:
		if not GamePucks.is_ladder(puck):
			continue
		var field: String = String((puck["cond"] as Dictionary)["field"])
		assert_true(stat_keys.has(field),
				"ladder %s counts '%s' with no backing Steam stat" % [puck["id"], field])
