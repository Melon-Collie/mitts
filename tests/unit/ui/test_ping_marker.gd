extends GutTest

# PingMarker and PingCallout free and hide themselves: nothing owns them after
# the ping that spawned them, so one that outlives its time (or the skater it
# rides) stays on the ice for the rest of the match.

const HOLD_S: float = 2.0


func _anchor(pos: Vector3) -> Node3D:
	var node := Node3D.new()
	add_child_autofree(node)
	node.global_position = pos
	return node


func test_a_spot_marker_stands_for_its_hold_then_frees_itself() -> void:
	var marker: PingMarker = PingMarker.at_spot(Vector3(3.0, 0.0, -4.0), null, HOLD_S)
	add_child_autofree(marker)
	assert_almost_eq(marker.global_position, Vector3(3.0, 0.0, -4.0), Vector3.ONE * 1e-4)
	marker._process(HOLD_S)
	assert_false(marker.is_queued_for_deletion(), "still fading")
	marker._process(1.0)
	assert_true(marker.is_queued_for_deletion())


func test_a_marker_rides_what_it_names() -> void:
	var target: Node3D = _anchor(Vector3(1.0, 0.0, 1.0))
	var marker: PingMarker = PingMarker.on_node(target, _anchor(Vector3(-6.0, 0.0, 0.0)), HOLD_S)
	add_child_autofree(marker)
	target.global_position = Vector3(5.0, 0.9, -2.0)
	marker._process(0.1)
	assert_almost_eq(marker.global_position, Vector3(5.0, 0.0, -2.0), Vector3.ONE * 1e-4,
			"on the ice under him, wherever he has skated to")


func test_a_marker_goes_with_the_skater_it_rode() -> void:
	var target := Node3D.new()
	add_child(target)
	var marker: PingMarker = PingMarker.on_node(target, null, HOLD_S)
	add_child_autofree(marker)
	target.free()
	marker._process(0.1)
	assert_true(marker.is_queued_for_deletion())


func test_a_marker_outlives_the_pinger_who_called_it() -> void:
	var pinger := Node3D.new()
	add_child(pinger)
	var marker: PingMarker = PingMarker.at_spot(Vector3(8.0, 0.0, 0.0), pinger, HOLD_S)
	add_child_autofree(marker)
	pinger.free()
	marker._process(0.1)
	assert_false(marker.is_queued_for_deletion(), "only its line goes")


func test_a_callout_shows_for_a_beat_and_a_fresh_call_restarts_it() -> void:
	var callout := PingCallout.new()
	add_child_autofree(callout)
	assert_false(callout.is_live())
	callout.say("Shoot!")
	assert_true(callout.is_live())
	assert_true(callout.visible)
	callout._process(2.0)
	callout.say("Pass to me!")
	callout._process(2.0)
	assert_true(callout.is_live(), "the second call has its own time")
	callout._process(2.0)
	assert_false(callout.is_live())
	assert_false(callout.visible)
