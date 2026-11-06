extends GutTest

# A carrier who ghosts loses the puck on the host. Puck.drop() alone sends only
# CARRIER_CHANGED(-1), and a client's notify_remote_carrier_changed(-1) never
# clears its own local pin — so a ghosted human carrier's client kept the puck
# on his stick while the host had it loose. The drop must go through
# _drop_puck_if_carried, which also sends the DROPPED event to that carrier.
#
# Reads source: reaching the ghost pass needs a live match on the host, and the
# claim is which drop the pass calls.

const _GM: String = "res://Scripts/game/game_manager.gd"


func _body(src: String, fn: String) -> String:
	var start: int = src.find("func %s(" % fn)
	assert_gt(start, -1, "%s exists" % fn)
	var end: int = src.find("\nfunc ", start + 1)
	return src.substr(start, end - start)


func test_the_ghost_pass_drops_through_the_carrier_notify() -> void:
	var body: String = _body(FileAccess.get_file_as_string(_GM), "_apply_ghost_state")
	assert_true(body.contains("_drop_puck_if_carried()"))
	assert_false(body.contains("puck.drop()"),
			"a bare drop leaves the carrier's own client pinned")


func test_the_drop_it_goes_through_notifies_the_carrier() -> void:
	var body: String = _body(FileAccess.get_file_as_string(_GM), "_drop_puck_if_carried")
	assert_true(body.contains("NetworkManager.notify_puck_dropped_to_carrier("))
