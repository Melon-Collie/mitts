extends GutTest

# WorldStateCodec — round-trip serialization tests.
# World-state encode/decode uses live controllers (CharacterBody3D etc.), so
# those aren't covered here. Stats are pure Array<->Dictionary conversions
# and fully testable.

var codec: WorldStateCodec
var registry: PlayerRegistry
var sm: GameStateMachine


func before_each() -> void:
	sm = GameStateMachine.new()
	registry = PlayerRegistry.new()
	codec = WorldStateCodec.new()
	# Puck / controller / goalie getters aren't needed for stats tests.
	codec.setup(registry, sm, Callable(), Callable(), Callable())


func _add_player(peer_id: int, team_id: int, g: int = 0, a: int = 0, sog: int = 0, hits: int = 0) -> PlayerRecord:
	var team := Team.new()
	team.team_id = team_id
	var record := PlayerRecord.new(peer_id, 0, false, team)
	record.stats = PlayerStats.new()
	record.stats.goals         = g
	record.stats.assists       = a
	record.stats.shots_on_goal = sog
	record.stats.hits          = hits
	registry._players[peer_id] = record
	return record


# ── Stats round-trip ─────────────────────────────────────────────────────────

func test_stats_round_trip_preserves_per_player_counters() -> void:
	_add_player(10, 0, 2, 1, 5, 3)
	_add_player(11, 1, 0, 0, 4, 1)
	sm.team_shots[0] = 5
	sm.team_shots[1] = 4
	sm.period_scores[0][0] = 2
	sm.period_scores[1][0] = 0

	var encoded: Array = codec.encode_stats()

	# Fresh registry + state machine, then decode into them
	sm.team_shots[0] = 0
	sm.team_shots[1] = 0
	registry._players[10].stats = PlayerStats.new()
	registry._players[11].stats = PlayerStats.new()
	sm.period_scores[0][0] = 0
	sm.period_scores[1][0] = 0

	codec.decode_stats(encoded)

	assert_eq(registry._players[10].stats.goals, 2)
	assert_eq(registry._players[10].stats.assists, 1)
	assert_eq(registry._players[10].stats.shots_on_goal, 5)
	assert_eq(registry._players[10].stats.hits, 3)
	assert_eq(registry._players[11].stats.shots_on_goal, 4)
	assert_eq(sm.team_shots[0], 5)
	assert_eq(sm.team_shots[1], 4)
	assert_eq(sm.period_scores[0][0], 2)
	assert_eq(sm.period_scores[1][0], 0)


func test_decode_stats_skips_unknown_peer_ids() -> void:
	_add_player(10, 0, 1, 0, 0, 0)
	var encoded: Array = codec.encode_stats()
	# Drop the known player; decode should no-op on missing peer_id but still
	# apply team_shots/period_scores afterwards.
	registry._players.erase(10)
	codec.decode_stats(encoded)
	# Team shots/period_scores are at the tail — they should land regardless.
	assert_eq(sm.team_shots[0], 0)
	assert_eq(sm.team_shots[1], 0)


func test_decode_stats_emits_shots_on_goal_signal() -> void:
	_add_player(10, 0)
	sm.team_shots[0] = 3
	sm.team_shots[1] = 1
	var encoded: Array = codec.encode_stats()
	watch_signals(codec)
	codec.decode_stats(encoded)
	assert_signal_emitted_with_parameters(codec, "shots_on_goal_changed", [3, 1])


# ── Wire-format tail sentinel ─────────────────────────────────────────────────

func test_encode_stats_ends_with_num_periods_sentinel() -> void:
	_add_player(10, 0)
	var encoded: Array = codec.encode_stats()
	assert_eq(encoded[-1], sm.period_scores[0].size(),
			"trailing sentinel encodes the period count")
