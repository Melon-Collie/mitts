extends GutTest

# A ping is resolved on the pinger's own machine, and what it says turns on who
# has the puck. PuckController.get_carrier_peer_id is written by the host's
# pickup callbacks alone, so read on a client it says "loose" for the whole
# match and no client can call for a shot, a pass or pressure on the carrier.
#
# It reads source because the line under test sits behind a spawned local
# player, a LocalController and a client-mode PuckController, and what is
# asserted is which getter is called.

const _PATH: String = "res://Scripts/game/game_manager.gd"


func _body_of(func_name: String) -> String:
	var src: String = FileAccess.get_file_as_string(_PATH)
	var start: int = src.find("\nfunc %s(" % func_name)
	assert_gt(start, -1, "%s should exist" % func_name)
	if start < 0:
		return ""
	var end: int = src.find("\nfunc ", start + 1)
	return src.substr(start, end - start if end > start else -1)


func test_the_send_path_resolves_against_the_carrier_this_machine_sees() -> void:
	var body: String = _body_of("try_send_smart_ping")
	assert_true(body.contains("get_puck_carrier_peer_id()"),
			"resolve through the peer-agnostic carrier")
	assert_false(body.contains(".get_carrier_peer_id()"),
			"the host-only carrier reads loose on a client")


func test_the_peer_agnostic_carrier_goes_through_the_client_view() -> void:
	assert_true(_body_of("get_puck_carrier_peer_id").contains("get_puck_carrier()"))
