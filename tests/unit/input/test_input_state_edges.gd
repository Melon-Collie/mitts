extends GutTest

# The host reuses a client's last input through a queue gap (RemoteController's
# fallback) and folds a drained frame's presses into the next one. Both walk the
# one-tick edges, and both must walk every one of them: an edge the fallback
# keeps re-fires each tick of the gap (a quick pass the client never made), and
# one the drain drops eats a press. Every `*_pressed` field is an edge.


func _edge_names() -> PackedStringArray:
	var names := PackedStringArray()
	for prop: Dictionary in InputState.new().get_property_list():
		var n: String = prop["name"]
		if n.ends_with("_pressed"):
			names.append(n)
	return names


func test_edges_are_discovered() -> void:
	assert_gt(_edge_names().size(), 0, "no *_pressed field found — the guards below assert nothing")


func test_clear_edges_clears_every_press() -> void:
	for n: String in _edge_names():
		var s := InputState.new()
		s.set(n, true)
		s.clear_edges()
		assert_false(s.get(n) as bool, "clear_edges leaves %s set" % n)


func test_clear_edges_keeps_held_state() -> void:
	var s := InputState.new()
	s.shoot_held = true
	s.elevation_level = 2
	s.clear_edges()
	assert_true(s.shoot_held)
	assert_eq(s.elevation_level, 2)


func test_fold_carries_every_press() -> void:
	for n: String in _edge_names():
		var dropped := InputState.new()
		dropped.set(n, true)
		var next := InputState.new()
		next.fold_edges_from(dropped)
		assert_true(next.get(n) as bool, "fold_edges_from drops %s" % n)
