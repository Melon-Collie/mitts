extends GutTest

# ColorVoteRules — vote tallying and team-color resolution from per-player votes.

const _ALL_IDS: Array[String] = [
	"blueberry", "pomegranate", "lemon", "coconut",
	"papaya", "dragonfruit", "fig", "lime",
]

func _rng(seed: int = 1) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	return r


# ── tally_votes ──────────────────────────────────────────────────────────────

func test_tally_empty_votes_returns_empty_dict() -> void:
	var t: Dictionary = ColorVoteRules.tally_votes([] as Array[String])
	assert_true(t.is_empty())

func test_tally_counts_each_color() -> void:
	var votes: Array[String] = ["lemon", "lemon", "lime"]
	var t: Dictionary = ColorVoteRules.tally_votes(votes)
	assert_eq(int(t["lemon"]), 2)
	assert_eq(int(t["lime"]), 1)


# ── pick_winner ──────────────────────────────────────────────────────────────

func test_pick_winner_empty_tally_returns_empty_string() -> void:
	assert_eq(ColorVoteRules.pick_winner({}, _rng()), "")

func test_pick_winner_clear_majority() -> void:
	var t: Dictionary = ColorVoteRules.tally_votes(["lemon", "lemon", "lime"] as Array[String])
	assert_eq(ColorVoteRules.pick_winner(t, _rng()), "lemon")

func test_pick_winner_three_way_tie_picks_one_of_them() -> void:
	var t: Dictionary = ColorVoteRules.tally_votes(["lemon", "lime", "fig"] as Array[String])
	var winner: String = ColorVoteRules.pick_winner(t, _rng(42))
	assert_true(winner == "lemon" or winner == "lime" or winner == "fig",
			"random tiebreak must return one of the tied colors, got %s" % winner)


# ── resolve_team_colors ──────────────────────────────────────────────────────

func test_resolve_empty_votes_falls_back_to_defaults() -> void:
	var result: Array[String] = ColorVoteRules.resolve_team_colors(
			[] as Array[String], [] as Array[String], _ALL_IDS,
			"blueberry", "pomegranate", _rng())
	assert_eq(result[0], "blueberry")
	assert_eq(result[1], "pomegranate")

func test_resolve_majority_wins_per_team() -> void:
	var home: Array[String] = ["lemon", "lemon", "lime"]
	var away: Array[String] = ["fig", "papaya", "fig"]
	var result: Array[String] = ColorVoteRules.resolve_team_colors(
			home, away, _ALL_IDS, "blueberry", "pomegranate", _rng())
	assert_eq(result[0], "lemon")
	assert_eq(result[1], "fig")

func test_resolve_three_way_tie_picks_random_voted_color() -> void:
	var votes: Array[String] = ["lemon", "lime", "fig"]
	var result: Array[String] = ColorVoteRules.resolve_team_colors(
			votes, [] as Array[String], _ALL_IDS,
			"blueberry", "pomegranate", _rng(7))
	assert_true(result[0] == "lemon" or result[0] == "lime" or result[0] == "fig",
			"home should resolve to one of the three tied colors, got %s" % result[0])

func test_resolve_clash_away_rerolls_from_remaining_votes() -> void:
	# Home wins lemon (2v1). Away also wins lemon (2v1) but has fig as a
	# fallback in its tally, so away should land on fig.
	var home: Array[String] = ["lemon", "lemon", "lime"]
	var away: Array[String] = ["lemon", "lemon", "fig"]
	var result: Array[String] = ColorVoteRules.resolve_team_colors(
			home, away, _ALL_IDS, "blueberry", "pomegranate", _rng())
	assert_eq(result[0], "lemon")
	assert_eq(result[1], "fig", "away clash should re-roll to remaining vote")

func test_resolve_clash_with_no_alt_votes_picks_from_palette() -> void:
	# Both teams unanimously vote lemon. Away has no other voted color, so it
	# must pick uniformly from the palette excluding lemon.
	var home: Array[String] = ["lemon", "lemon", "lemon"]
	var away: Array[String] = ["lemon", "lemon", "lemon"]
	var result: Array[String] = ColorVoteRules.resolve_team_colors(
			home, away, _ALL_IDS, "blueberry", "pomegranate", _rng(3))
	assert_eq(result[0], "lemon")
	assert_ne(result[1], "lemon", "away must differ when forced to re-roll")
	assert_true(_ALL_IDS.has(result[1]), "away pick must be a valid palette id")

func test_resolve_default_clash_when_no_votes_uses_distinct_defaults() -> void:
	# No votes at all → defaults are used. Defaults are already distinct,
	# so no re-roll is needed.
	var result: Array[String] = ColorVoteRules.resolve_team_colors(
			[] as Array[String], [] as Array[String], _ALL_IDS,
			"blueberry", "pomegranate", _rng())
	assert_eq(result[0], "blueberry")
	assert_eq(result[1], "pomegranate")

func test_resolve_default_clash_forces_away_reroll() -> void:
	# Defaults are the same and no votes exist — away must re-roll from the
	# palette since no away tally exists at all.
	var result: Array[String] = ColorVoteRules.resolve_team_colors(
			[] as Array[String], [] as Array[String], _ALL_IDS,
			"blueberry", "blueberry", _rng(11))
	assert_eq(result[0], "blueberry")
	assert_ne(result[1], "blueberry")
