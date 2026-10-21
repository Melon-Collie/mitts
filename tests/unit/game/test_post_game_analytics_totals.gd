extends GutTest

# PostGameAnalytics.history_totals: the tape's numbers for a past game, from its
# shot list and (for a local replay) the footer's box score.


func _shot(team: int, outcome: int, xg: float) -> ShotEvent:
	return ShotEvent.make(-1, team, Vector3.ZERO, xg, outcome, ShotEvent.ShotType.SHOT,
			outcome <= ShotEvent.Outcome.SAVED, 1, 100.0)


func test_a_blocked_attempt_is_a_block_for_the_defending_team() -> void:
	var events: Array[ShotEvent] = [
		_shot(0, ShotEvent.Outcome.BLOCKED, 0.1),
		_shot(0, ShotEvent.Outcome.BLOCKED, 0.1),
		_shot(1, ShotEvent.Outcome.BLOCKED, 0.1),
	]
	var totals: Array[Dictionary] = PostGameAnalytics.history_totals(events, [])
	assert_eq(int(totals[0]["blocks"]), 1, "home blocked the one away attempt")
	assert_eq(int(totals[1]["blocks"]), 2, "away blocked both home attempts")


func test_shot_conventions_match_the_live_counters() -> void:
	var events: Array[ShotEvent] = [
		_shot(0, ShotEvent.Outcome.GOAL, 0.3),
		_shot(0, ShotEvent.Outcome.SAVED, 0.1),
		_shot(0, ShotEvent.Outcome.MISSED, 0.05),
		_shot(0, ShotEvent.Outcome.BLOCKED, 0.2),
	]
	var home: Dictionary = PostGameAnalytics.history_totals(events, [])[0]
	assert_eq(int(home["corsi"]), 4, "Corsi counts every attempt")
	assert_eq(int(home["fenwick"]), 3, "Fenwick leaves the block out")
	assert_eq(int(home["sog"]), 2, "on goal is goals plus saves")
	assert_almost_eq(float(home["xg"]), 0.45, 1e-5, "a blocked shot carries no xG")


func test_box_score_sums_per_team() -> void:
	var box: Array = [
		{"team_id": 0, "hits": 3, "faceoff_wins": 5, "takeaways": 1, "giveaways": 2},
		{"team_id": 0, "hits": 2, "faceoff_wins": 0, "takeaways": 2, "giveaways": 0},
		{"team_id": 1, "hits": 4, "faceoff_wins": 7, "takeaways": 0, "giveaways": 3},
	]
	var totals: Array[Dictionary] = PostGameAnalytics.history_totals([], box)
	assert_true(bool(totals[0]["box"]) and bool(totals[1]["box"]))
	assert_eq(int(totals[0]["hits"]), 5)
	assert_eq(int(totals[0]["faceoff_wins"]), 5)
	assert_eq(int(totals[0]["takeaways"]), 3)
	assert_eq(int(totals[0]["giveaways"]), 2)
	assert_eq(int(totals[1]["hits"]), 4)
	assert_eq(int(totals[1]["faceoff_wins"]), 7)


func test_no_box_score_leaves_the_box_rows_off() -> void:
	var totals: Array[Dictionary] = PostGameAnalytics.history_totals(
			[_shot(0, ShotEvent.Outcome.SAVED, 0.1)], [])
	assert_false(bool(totals[0]["box"]) or bool(totals[1]["box"]))
