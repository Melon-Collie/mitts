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
	b.resize(3)
	b.encode_u16(0, 0)
	b.encode_u8(2, 1)
	b.append_array(input.to_bytes())
	return b


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
