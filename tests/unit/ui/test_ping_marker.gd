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


# ── The preview of a ping not yet sent ───────────────────────────────────────

var _pending: PingRules.Resolution = null


func _resolution(type: int, at: Vector3) -> PingRules.Resolution:
	var res := PingRules.Resolution.new()
	res.type = type
	res.world_pos = at
	return res


func _preview(subject: Node3D) -> PingPreview:
	var preview := PingPreview.new()
	preview.setup(func() -> PingRules.Resolution: return _pending,
			func(_res: PingRules.Resolution) -> Node3D: return subject)
	add_child_autofree(preview)
	return preview


func test_a_preview_draws_only_while_it_is_open() -> void:
	_pending = _resolution(PingRules.Type.GO_THERE, Vector3(2.0, 0.0, 3.0))
	var preview: PingPreview = _preview(null)
	assert_false(preview.is_open())
	assert_false(preview._marker.visible, "nothing before the key is down")
	preview.open()
	assert_true(preview._marker.visible)
	assert_true(preview._callout.is_live())
	assert_almost_eq(preview._marker.global_position, Vector3(2.0, 0.0, 3.0),
			Vector3.ONE * 1e-4)
	preview.close()
	assert_false(preview._marker.visible)
	assert_false(preview._callout.is_live())


func test_a_preview_follows_the_call_as_the_play_changes_under_the_key() -> void:
	var skater: Node3D = _anchor(Vector3(-3.0, 0.0, 1.0))
	_pending = _resolution(PingRules.Type.COVER_HIM, Vector3.ZERO)
	var preview: PingPreview = _preview(skater)
	preview.open()
	assert_almost_eq(preview._marker.global_position, Vector3(-3.0, 0.0, 1.0),
			Vector3.ONE * 1e-4, "on the man it would name")
	_pending = null
	preview._process(0.016)
	assert_false(preview._marker.visible, "nothing to say: nothing drawn")
	assert_false(preview._callout.is_live())
	assert_true(preview.is_open(), "the key is still down")


func test_a_held_marker_never_frees_itself() -> void:
	var marker: PingMarker = PingMarker.held()
	add_child_autofree(marker)
	marker._process(60.0)
	assert_false(marker.is_queued_for_deletion())
