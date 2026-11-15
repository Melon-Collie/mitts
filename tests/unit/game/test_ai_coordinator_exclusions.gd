extends GutTest

# AICoordinator.is_excluded answers on the main thread as of the last request,
# without waiting for the worker's idle window to move the peer on its brain:
# the host elects a ping's obeyer in the same frame a bot is boxed.

func test_a_peer_is_out_from_the_request_until_it_is_asked_back() -> void:
	var coordinator := AICoordinator.new()
	assert_false(coordinator.is_excluded(10000))
	coordinator.queue_exclude_skater(0, 10000)
	assert_true(coordinator.is_excluded(10000))
	assert_false(coordinator.is_excluded(10001))
	coordinator.queue_include_skater(0, 10000)
	assert_false(coordinator.is_excluded(10000))
