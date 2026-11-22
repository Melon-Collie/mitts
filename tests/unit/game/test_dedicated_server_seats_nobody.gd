extends GutTest

# A dedicated server is a host with no player on it
# (docs/dedicated-server-plan.md). The whole-match check is
# .claude/hooks/probe-headless-host.sh --server; these hold the flag it rides on.

var _saved: Dictionary = {}


func before_each() -> void:
	for field: String in ["is_host", "game_initiated", "is_offline_mode", "is_dedicated_server"]:
		_saved[field] = NetworkManager.get(field)


func after_each() -> void:
	for field: String in _saved:
		NetworkManager.set(field, _saved[field])


func test_a_server_is_a_host_with_nobody_seated() -> void:
	NetworkManager.start_server()
	assert_true(NetworkManager.is_host, "a server simulates")
	assert_true(NetworkManager.is_dedicated_server, "and seats nobody")
	assert_true(NetworkManager.is_offline_mode, "it has no transport until one is attached")


func test_a_server_casts_no_skip_vote() -> void:
	NetworkManager.is_dedicated_server = false
	var with_a_player: int = GameManager.call("_total_skip_voters")
	NetworkManager.is_dedicated_server = true
	var as_a_server: int = GameManager.call("_total_skip_voters")
	assert_eq(with_a_player - as_a_server, 1,
			"the host's own vote is the one a server does not have")
