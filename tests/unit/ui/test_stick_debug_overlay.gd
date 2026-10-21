extends GutTest

# StickDebugOverlay keeps the last LOG_SIZE face changes, names their causes,
# and draws without a skater to watch.

func test_the_log_names_causes_and_keeps_the_newest() -> void:
	var overlay := StickDebugOverlay.new()
	add_child_autofree(overlay)
	for i: int in StickDebugOverlay.LOG_SIZE + 3:
		overlay.record(CarryStrokeState.Cause.RETURN if i % 2 == 0 else CarryStrokeState.Cause.RELEASE,
				1.0 + i, 0.05, 7.5, 120.0, float(i))
	var lines: PackedStringArray = overlay.log_text().split("\n")
	assert_eq(lines.size(), StickDebugOverlay.LOG_SIZE + 1, "a header and the newest LOG_SIZE")
	assert_true(lines[1].contains("RELEASE") or lines[1].contains("RETURN"))
	assert_true(lines[-1].ends_with("14"), "the newest is last: %s" % lines[-1])


func test_it_draws_with_no_skater() -> void:
	var overlay := StickDebugOverlay.new()
	add_child_autofree(overlay)
	assert_true(overlay._render().contains("no local skater"))


func test_it_draws_a_carrier() -> void:
	var skater: Skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(skater)
	skater.set_process(false)
	skater.set_physics_process(false)
	skater.is_local_skater = true
	skater.current_shot_state = SkaterStateMachine.State.SKATING_WITH_PUCK
	var overlay := StickDebugOverlay.new()
	add_child_autofree(overlay)
	overlay._watch(overlay._find_local_skater())
	overlay.record(CarryStrokeState.Cause.REPUSH, 2.4, 0.06, 8.0, 150.0, 2.0)
	var text: String = overlay._render()
	assert_true(text.contains("CARRYING"), text)
	assert_true(text.contains("REPUSH"), text)
	assert_true(text.contains("still"), "a mouse that barely moved is marked")
	assert_true(skater.carry_face_changed.is_connected(overlay._on_face_changed),
			"it listens to the skater it watches")
	overlay._watch(null)
	assert_false(skater.carry_face_changed.is_connected(overlay._on_face_changed),
			"and lets go of it")
