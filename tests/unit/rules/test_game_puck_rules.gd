extends GutTest

# GamePuckRules — pure evaluation of the Achievements registry against a
# finished game's stats and a player's lifetime totals. Idempotent unlocking
# means callers may re-report earned ids, so these only assert membership.

func _stats(goals: int, assists: int, sog: int, hits: int, blocks: int) -> PlayerStats:
	var s := PlayerStats.new()
	s.goals = goals
	s.assists = assists
	s.shots_on_goal = sog
	s.hits = hits
	s.shots_blocked = blocks
	return s


func _ctx(outcome: String, gf: int, ga: int) -> Dictionary:
	return {"outcome": outcome, "goals_for": gf, "goals_against": ga}


# ── game_dict ────────────────────────────────────────────────────────────────
func test_game_dict_derives_points() -> void:
	var d := GamePuckRules.game_dict(_stats(2, 3, 5, 1, 0))
	assert_eq(d["points"], 5)
	assert_eq(d["goals"], 2)
	assert_eq(d["assists"], 3)


# ── single-game thresholds ───────────────────────────────────────────────────
func test_hat_trick_unlocks_at_three_goals() -> void:
	var ids := GamePuckRules.earned_game(
			GamePuckRules.game_dict(_stats(3, 0, 4, 0, 0)), _ctx("win", 4, 2))
	assert_has(ids, "hat_trick")


func test_two_goals_is_no_hat_trick() -> void:
	var ids := GamePuckRules.earned_game(
			GamePuckRules.game_dict(_stats(2, 0, 4, 0, 0)), _ctx("win", 4, 2))
	assert_does_not_have(ids, "hat_trick")


func test_three_helpers_unlocks_at_three_assists() -> void:
	var ids := GamePuckRules.earned_game(
			GamePuckRules.game_dict(_stats(0, 3, 0, 0, 0)), _ctx("draw", 3, 3))
	assert_has(ids, "three_helpers")


func test_big_night_counts_goals_plus_assists() -> void:
	# 3 + 2 = 5 points trips Big Night without tripping Hat Trick's 3-goal bar
	# only on goals — 3 goals here also trips Hat Trick, so assert both fire.
	var ids := GamePuckRules.earned_game(
			GamePuckRules.game_dict(_stats(3, 2, 6, 0, 0)), _ctx("win", 5, 1))
	assert_has(ids, "big_night")
	assert_has(ids, "hat_trick")


func test_big_night_from_mixed_line_without_hat_trick() -> void:
	var ids := GamePuckRules.earned_game(
			GamePuckRules.game_dict(_stats(2, 3, 4, 0, 0)), _ctx("win", 5, 1))
	assert_has(ids, "big_night")
	assert_does_not_have(ids, "hat_trick")


func test_brick_wall_unlocks_at_three_blocks() -> void:
	var ids := GamePuckRules.earned_game(
			GamePuckRules.game_dict(_stats(0, 0, 0, 0, 3)), _ctx("loss", 1, 3))
	assert_has(ids, "brick_wall")


func test_two_blocks_is_no_brick_wall() -> void:
	var ids := GamePuckRules.earned_game(
			GamePuckRules.game_dict(_stats(0, 0, 0, 0, 2)), _ctx("loss", 1, 3))
	assert_does_not_have(ids, "brick_wall")


func test_first_goal_unlocks_on_scoring_any_game() -> void:
	# Onboarding: single-game, so it fires the first game you score in (any mode).
	var ids := GamePuckRules.earned_game(
			GamePuckRules.game_dict(_stats(1, 0, 2, 0, 0)), _ctx("loss", 1, 3))
	assert_has(ids, "first_goal")


func test_first_goal_not_awarded_without_a_goal() -> void:
	var ids := GamePuckRules.earned_game(
			GamePuckRules.game_dict(_stats(0, 2, 3, 1, 1)), _ctx("loss", 0, 2))
	assert_does_not_have(ids, "first_goal")


# ── goal-flavor + defensive game stats ───────────────────────────────────────
func test_one_timer_goal_unlocks_on_a_one_timer_marker() -> void:
	var s := _stats(1, 0, 2, 0, 0)
	s.one_timer_goals = 1
	var ids := GamePuckRules.earned_game(
			GamePuckRules.game_dict(s), _ctx("win", 2, 1))
	assert_has(ids, "one_timer")


func test_plain_goal_is_no_one_timer() -> void:
	# A goal with no one_timer_goals marker must not grant the One-Timer.
	var ids := GamePuckRules.earned_game(
			GamePuckRules.game_dict(_stats(2, 0, 3, 0, 0)), _ctx("win", 2, 1))
	assert_does_not_have(ids, "one_timer")


func test_tip_in_goal_unlocks_on_a_tip_marker() -> void:
	var s := _stats(1, 0, 1, 0, 0)
	s.tip_goals = 1
	var ids := GamePuckRules.earned_game(
			GamePuckRules.game_dict(s), _ctx("win", 2, 0))
	assert_has(ids, "tip_in")


func test_faceoff_boss_unlocks_at_five_wins() -> void:
	var s := _stats(0, 0, 0, 0, 0)
	s.faceoff_wins = 5
	var ids := GamePuckRules.earned_game(
			GamePuckRules.game_dict(s), _ctx("win", 1, 0))
	assert_has(ids, "faceoff_boss")


func test_four_faceoff_wins_is_no_boss() -> void:
	var s := _stats(0, 0, 0, 0, 0)
	s.faceoff_wins = 4
	var ids := GamePuckRules.earned_game(
			GamePuckRules.game_dict(s), _ctx("win", 1, 0))
	assert_does_not_have(ids, "faceoff_boss")


func test_pickpocket_unlocks_at_five_takeaways() -> void:
	var s := _stats(0, 0, 0, 0, 0)
	s.takeaways = 5
	var ids := GamePuckRules.earned_game(
			GamePuckRules.game_dict(s), _ctx("draw", 2, 2))
	assert_has(ids, "pickpocket")


func test_overtime_hero_unlocks_on_an_ot_goal() -> void:
	var s := _stats(1, 0, 2, 0, 0)
	s.ot_goals = 1
	var ids := GamePuckRules.earned_game(
			GamePuckRules.game_dict(s), _ctx("win", 3, 2))
	assert_has(ids, "overtime_hero")


func test_regulation_goal_is_no_overtime_hero() -> void:
	var ids := GamePuckRules.earned_game(
			GamePuckRules.game_dict(_stats(2, 0, 4, 0, 0)), _ctx("win", 2, 0))
	assert_does_not_have(ids, "overtime_hero")


# ── roster ("play with X") ───────────────────────────────────────────────────
func test_play_with_buukie_unlocks_when_present() -> void:
	# A non-Buukie local playing a game whose roster includes Buukie earns it.
	var ids := GamePuckRules.earned_roster(
			[111, GamePucks.BUUKIE_STEAM_ID, 222], 111)
	assert_has(ids, GamePucks.PLAY_WITH_BUUKIE)


func test_buukie_cannot_earn_his_own_achievement() -> void:
	# Local player IS Buukie — the roster includes him but he can't self-award it.
	var ids := GamePuckRules.earned_roster(
			[GamePucks.BUUKIE_STEAM_ID, 222], GamePucks.BUUKIE_STEAM_ID)
	assert_does_not_have(ids, GamePucks.PLAY_WITH_BUUKIE)


func test_no_buukie_in_lobby_earns_nothing() -> void:
	var ids := GamePuckRules.earned_roster([111, 222, 333], 111)
	assert_does_not_have(ids, GamePucks.PLAY_WITH_BUUKIE)


func test_roster_with_no_local_steam_id_earns_nothing() -> void:
	# Steam unavailable (local id 0) must not false-unlock even if X is "present".
	var ids := GamePuckRules.earned_roster([GamePucks.BUUKIE_STEAM_ID], 0)
	assert_eq(ids.size(), 0)


# ── compound (special) ───────────────────────────────────────────────────────
func test_shutout_requires_win_and_zero_against() -> void:
	var ids := GamePuckRules.earned_game(
			GamePuckRules.game_dict(_stats(1, 0, 3, 0, 0)), _ctx("win", 2, 0))
	assert_has(ids, "shutout")


func test_first_win_unlocks_on_any_win() -> void:
	var ids := GamePuckRules.earned_game(
			GamePuckRules.game_dict(_stats(0, 0, 1, 0, 0)), _ctx("win", 1, 0))
	assert_has(ids, "first_win")


func test_first_win_not_awarded_on_loss_or_draw() -> void:
	var loss := GamePuckRules.earned_game(
			GamePuckRules.game_dict(_stats(0, 0, 1, 0, 0)), _ctx("loss", 0, 1))
	assert_does_not_have(loss, "first_win")
	var draw := GamePuckRules.earned_game(
			GamePuckRules.game_dict(_stats(0, 0, 1, 0, 0)), _ctx("draw", 1, 1))
	assert_does_not_have(draw, "first_win")


func test_shutout_not_awarded_on_a_win_that_conceded() -> void:
	var ids := GamePuckRules.earned_game(
			GamePuckRules.game_dict(_stats(1, 0, 3, 0, 0)), _ctx("win", 3, 1))
	assert_does_not_have(ids, "shutout")


func test_shutout_not_awarded_on_a_scoreless_draw() -> void:
	# 0-0 is a draw, not a win, so no shutout even with 0 against.
	var ids := GamePuckRules.earned_game(
			GamePuckRules.game_dict(_stats(0, 0, 2, 0, 0)), _ctx("draw", 0, 0))
	assert_does_not_have(ids, "shutout")


# ── nothing earned ───────────────────────────────────────────────────────────
func test_quiet_game_earns_nothing() -> void:
	# No goal, no win — so no Lamp Lighter / W either.
	var ids := GamePuckRules.earned_game(
			GamePuckRules.game_dict(_stats(0, 1, 2, 1, 1)), _ctx("loss", 1, 4))
	assert_eq(ids.size(), 0)


# ── ladders ──────────────────────────────────────────────────────────────────
func test_ladder_tiers_count_up_to_the_counter() -> void:
	var goals: Dictionary = GamePucks.find("goals")
	assert_eq(GamePuckRules.tiers_reached(goals, {}), 0)
	assert_eq(GamePuckRules.tiers_reached(goals, {"goals": 49}), 1)
	assert_eq(GamePuckRules.tiers_reached(goals, {"goals": 50}), 2)


func test_a_higher_counter_never_reaches_fewer_tiers() -> void:
	for entry: Dictionary in GamePucks.ALL:
		if not GamePucks.is_ladder(entry):
			continue
		var field: String = String((entry["cond"] as Dictionary)["field"])
		var last: int = 0
		for value: int in [0, 1, 9, 10, 49, 50, 99, 100, 499, 500, 5000]:
			var reached: int = GamePuckRules.tiers_reached(entry, {field: value})
			assert_true(reached >= last, "%s fell back at %d" % [entry["id"], value])
			last = reached


func test_points_derive_from_goals_and_assists() -> void:
	assert_eq(GamePuckRules.counter({"goals": 20, "assists": 6}, "points"), 26)


func test_crossed_tiers_names_only_the_new_ones() -> void:
	var crossed := GamePuckRules.crossed_tiers({"goals": 9}, {"goals": 52})
	var goal_tiers: Array[Dictionary] = []
	for c: Dictionary in crossed:
		if c["id"] == "goals":
			goal_tiers.append(c)
	assert_eq(goal_tiers, [{"id": "goals", "target": 10}, {"id": "goals", "target": 50}] as Array[Dictionary])
	assert_has(crossed, {"id": "points", "target": 25}, "points rise with the goals")
	assert_eq(GamePuckRules.crossed_tiers({"goals": 52}, {"goals": 52}).size(), 0)


func test_crossing_into_points_comes_from_its_parts() -> void:
	var crossed := GamePuckRules.crossed_tiers(
			{"goals": 20, "assists": 4}, {"goals": 21, "assists": 4})
	assert_has(crossed, {"id": "points", "target": 25})


func test_empty_totals_earn_no_tier() -> void:
	assert_eq(GamePuckRules.crossed_tiers({}, {}).size(), 0)


# ── Steam mirror ─────────────────────────────────────────────────────────────
func test_the_old_career_achievements_ride_their_ladder_tiers() -> void:
	var ids := GamePuckRules.earned_steam_ids(
			{"goals": 50, "assists": 50, "hits": 100, "games_played": 25}, TrophyLedger.new())
	for id: String in ["ACH_GOALS_50", "ACH_SETUP_ARTIST", "ACH_ENFORCER", "ACH_VETERAN"]:
		assert_has(ids, id)
	assert_eq(GamePuckRules.earned_steam_ids({"goals": 49}, TrophyLedger.new()).size(), 0)


func test_ledger_pucks_mirror_their_steam_id() -> void:
	var ledger := TrophyLedger.new()
	ledger.earn("hat_trick", 1)
	assert_eq(GamePuckRules.earned_steam_ids({}, ledger), ["ACH_HAT_TRICK"] as Array[String])


# ── combos ───────────────────────────────────────────────────────────────────
func test_power_forward_is_earned_on_its_last_requirement() -> void:
	var combo: Dictionary = GamePucks.find("power_forward")
	var ledger := TrophyLedger.new()
	assert_eq(GamePuckRules.combo_progress(combo, {"goals": 50, "hits": 49}, ledger), 1)
	assert_false(GamePuckRules.requirement_met("power_forward", {"goals": 50, "hits": 49}, ledger))
	assert_true(GamePuckRules.requirement_met("power_forward", {"goals": 50, "hits": 50}, ledger))
	assert_has(GamePuckRules.earned_combos({"goals": 50, "hits": 50}, ledger), "power_forward")


# Every combo in the catalogue is earned exactly when everything it names is,
# whatever those are — pucks, tiers or other combos.
func test_every_combo_is_earned_exactly_when_its_requirements_are() -> void:
	var ledger := TrophyLedger.new()
	var totals: Dictionary = {}
	for entry: Dictionary in GamePucks.ALL:
		if GamePucks.is_combo(entry):
			var id: String = entry["id"]
			assert_false(GamePuckRules.requirement_met(id, totals, ledger), "%s from nothing" % id)
			_meet_all(GamePucks.needs_of(entry), totals, ledger)
			assert_true(GamePuckRules.requirement_met(id, totals, ledger), "%s once met" % id)
			ledger = TrophyLedger.new()
			totals = {}


func test_a_single_puck_requirement_reads_the_ledger() -> void:
	var ledger := TrophyLedger.new()
	assert_false(GamePuckRules.requirement_met("hat_trick", {}, ledger))
	ledger.earn("hat_trick", 1)
	assert_true(GamePuckRules.requirement_met("hat_trick", {}, ledger))


func test_an_unknown_requirement_is_never_met() -> void:
	assert_false(GamePuckRules.requirement_met("nope@5", {"nope": 99}, TrophyLedger.new()))
	assert_false(GamePuckRules.requirement_met("hat_trick@3", {"hat_trick": 9},
			TrophyLedger.new()), "a tier on a single puck is not a requirement")


# A combo is derived, never stored: an id in the ledger does not earn it.
func test_a_stored_combo_id_earns_nothing() -> void:
	var ledger := TrophyLedger.new()
	ledger.earn("power_forward", 1)
	assert_false(GamePuckRules.requirement_met("power_forward", {}, ledger))


func test_an_earned_combo_earns_its_title() -> void:
	var ledger := TrophyLedger.new()
	assert_eq(GamePuckRules.earned_titles({"goals": 50, "hits": 49}, ledger).size(), 0)
	assert_eq(GamePuckRules.earned_titles({"goals": 50, "hits": 50}, ledger),
			["power_forward"] as Array[String])


func test_met_requirements_keeps_only_those_met() -> void:
	var ledger := TrophyLedger.new()
	ledger.earn("hat_trick", 1)
	var reqs: Array[String] = ["hat_trick", "goals@50", "power_forward"]
	assert_eq(GamePuckRules.met_requirements(reqs, {"goals": 50}, ledger),
			["hat_trick", "goals@50"] as Array[String])


func _meet_all(reqs: Array[String], totals: Dictionary, ledger: TrophyLedger) -> void:
	for req: String in reqs:
		var entry: Dictionary = GamePucks.find(GamePucks.requirement_puck(req))
		var target: int = GamePucks.requirement_target(req)
		if target > 0:
			var field: String = String((entry["cond"] as Dictionary)["field"])
			totals[field] = maxi(int(totals.get(field, 0)), target)
		elif GamePucks.is_combo(entry):
			_meet_all(GamePucks.needs_of(entry), totals, ledger)
		else:
			ledger.earn(req, 1)
