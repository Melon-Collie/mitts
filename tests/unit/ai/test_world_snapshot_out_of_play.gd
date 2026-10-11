extends GutTest

# WorldSnapshot.is_out_of_play — the bots' one read of "can't legally play the
# puck": a ghost, or a skater owing an NHL delayed-offside tag-up.

var snap: WorldSnapshot


func before_each() -> void:
	snap = WorldSnapshot.new()
	snap.skater_states[1] = SkaterNetworkState.new()
	snap.skater_states[2] = SkaterNetworkState.new()


func test_an_ordinary_skater_is_in_play() -> void:
	assert_false(snap.is_out_of_play(1))


func test_a_ghost_is_out_of_play() -> void:
	snap.skater_states[1].is_ghost = true
	assert_true(snap.is_out_of_play(1))
	assert_false(snap.is_out_of_play(2))


func test_a_skater_owing_a_tag_up_is_out_of_play() -> void:
	snap.tag_up_peers[2] = true
	assert_true(snap.is_out_of_play(2))
	assert_false(snap.is_out_of_play(1))


func test_an_unknown_peer_is_in_play() -> void:
	assert_false(snap.is_out_of_play(99))
