extends GutTest

# SkaterAgent — the InputState scratch buffer is reused across ticks, so
# zero_input must reset every field a state-machine handler can set. A missed
# field latches: the regression this guards is quick_pass_pressed staying true
# after a bot's first pass/quick pass (added in the dedicated-button split),
# which made every subsequent carry tick fire an instant quick pass.


func test_zero_input_resets_every_field_the_sm_can_set() -> void:
	# Every InputState field, not a hand-kept list: a field added later and
	# forgotten here would latch across ticks in the reused scratch buffer.
	var agent := SkaterAgent.new()
	var input: InputState = agent._scratch_input
	var fresh := InputState.new()
	var fields: Array[String] = []
	for prop: Dictionary in input.get_property_list():
		if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			fields.append(prop["name"])
	assert_gt(fields.size(), 15, "found the InputState fields")
	for f: String in fields:
		var v: Variant = fresh.get(f)
		match typeof(v):
			TYPE_BOOL:
				input.set(f, not v)
			TYPE_INT:
				input.set(f, int(v) + 1)
			TYPE_FLOAT:
				input.set(f, float(v) + 0.5)
			TYPE_VECTOR2:
				input.set(f, (v as Vector2) + Vector2.ONE)
			TYPE_VECTOR3:
				input.set(f, (v as Vector3) + Vector3.ONE)

	SkaterAgent.zero_input(input, 1.0 / 120.0, 12.5)

	assert_eq(input.delta, 1.0 / 120.0, "delta is stamped")
	assert_eq(input.host_timestamp, 12.5, "host_timestamp is stamped")
	for f: String in fields:
		if f == "delta" or f == "host_timestamp":
			continue
		assert_eq(input.get(f), fresh.get(f), "zero_input leaves %s latched" % f)