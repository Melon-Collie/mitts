extends GutTest

# A client's reconcile replays its unacked inputs against remote bodies sampled
# out of their buffers (contacts, the press). Run inline at the local skater's
# block, it would read every remote encoded AFTER that block one broadcast stale
# — which ones depending only on join order. So decode_world_state buffers every
# skater, the puck and the goalies first and reconciles once they are in.
#
# Reads source: the decode needs a live registry, NetworkManager and controllers
# to reach the line, and the claim is about ORDER, not a number.


func _decode_body() -> String:
	var src: String = FileAccess.get_file_as_string("res://Scripts/game/world_state_codec.gd")
	var start: int = src.find("func decode_world_state(")
	assert_gt(start, -1, "decode_world_state not found")
	var end: int = src.find("\nfunc ", start + 1)
	return src.substr(start, end - start)


func test_the_skater_loop_does_not_reconcile() -> void:
	var body: String = _decode_body()
	assert_false(body.contains(".reconcile("),
			"decode_world_state reconciles inline; defer it to _reconcile_local")


func test_reconcile_follows_every_actor_apply() -> void:
	var body: String = _decode_body()
	var last_apply: int = maxi(body.rfind("apply_network_state("),
			maxi(body.rfind("puck_controller.apply_state("),
					body.rfind("goalie_controllers[gi].apply_state(")))
	assert_gt(last_apply, -1)
	var reconcile_at: int = body.rfind("_reconcile_local()")
	assert_gt(reconcile_at, last_apply, "the local reconcile must run after the packet's actors are buffered")
