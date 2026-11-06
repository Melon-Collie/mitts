extends GutTest

# Host-only RPC handlers on NetworkManager refuse what reaches them on the wrong
# peer or at the wrong time. Called directly, outside an RPC, so the sender id
# reads 0 — no handler here may act on it.

var _was_host: bool = false


func before_each() -> void:
	_was_host = NetworkManager.is_host
	watch_signals(NetworkManager)


func after_each() -> void:
	NetworkManager.is_host = _was_host


func _one_input_batch() -> PackedByteArray:
	var input := InputState.new()
	input.host_timestamp = 1.0
	var b := PackedByteArray()
	b.resize(NetworkManager.INPUT_BATCH_HEADER)
	b.fill(0)
	b.encode_u8(2, 1)
	b.append_array(input.to_bytes())
	return WirePacking.pack(b, WirePacking.INPUT_MODE)


func test_a_client_ignores_an_input_batch() -> void:
	# With server relay on, one client can RPC another; inputs are only ever the
	# host's to consume.
	NetworkManager.is_host = false
	NetworkManager.receive_input_batch(_one_input_batch())
	assert_signal_not_emitted(NetworkManager, "input_batch_received")


func test_the_host_decodes_an_input_batch() -> void:
	NetworkManager.is_host = true
	NetworkManager.receive_input_batch(_one_input_batch())
	assert_signal_emitted(NetworkManager, "input_batch_received",
			"the guard must not refuse the host its own inputs")


func test_a_rematch_vote_outside_game_over_is_not_counted() -> void:
	# No match is running here, so GameManager's gate refuses it before any
	# peer's pool sees it.
	NetworkManager.is_host = true
	NetworkManager.request_rematch_vote(RematchVoteRules.Choice.REMATCH)
	assert_signal_emitted(NetworkManager, "rematch_vote_requested")
	assert_signal_not_emitted(NetworkManager, "rematch_vote_changed")


func test_a_new_match_keeps_the_hosts_ping() -> void:
	# The ping is the link's, not the match's. Cleared, every reader of it saw
	# "no sample" for the first two seconds of a rematch.
	var peer: int = 424242
	NetworkManager._record_host_measured_rtt(peer, 40.0)
	NetworkManager.prepare_for_new_game()
	assert_eq(NetworkManager.get_peer_ping_ms(peer), 40)
	NetworkManager._peer_ping_ms.erase(peer)
	NetworkManager._peer_rtt_ema_ms.erase(peer)


func test_a_spectators_snapshot_ack_sets_its_baseline() -> void:
	# A spectator sends no input batches; without its own ack it got whole
	# snapshots every broadcast.
	NetworkManager.is_host = true
	NetworkManager._peer_snapshot_acks.erase(0)
	NetworkManager.receive_snapshot_ack(41)
	assert_eq(NetworkManager._peer_snapshot_acks.get(0, -1), 41)
	NetworkManager.receive_snapshot_ack(40)
	assert_eq(NetworkManager._peer_snapshot_acks.get(0, -1), 41, "an older ack never shrinks the baseline")
	NetworkManager._peer_snapshot_acks.erase(0)


func test_a_client_ignores_a_snapshot_ack() -> void:
	NetworkManager.is_host = false
	NetworkManager._peer_snapshot_acks.erase(0)
	NetworkManager.receive_snapshot_ack(41)
	assert_false(NetworkManager._peer_snapshot_acks.has(0))
