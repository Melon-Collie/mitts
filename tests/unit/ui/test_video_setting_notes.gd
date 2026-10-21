extends GutTest

# Every Image and Performance setting in Options → Video tells the player what
# it costs: its row ends in an impact rating, and hovering the rating explains
# the setting. A setting added without one is a knob the player has to guess
# about, which is what the ratings exist to end.


func _tab() -> OptionsVideoTab:
	var tab := OptionsVideoTab.new()
	tab.build()
	add_child_autofree(tab)
	return tab


func _rated_rows(tab: OptionsVideoTab) -> Array[HBoxContainer]:
	var rows: Array[HBoxContainer] = []
	var in_scope: bool = false
	for child: Node in tab.get_children():
		if child is Label and (child as Label).text in ["IMAGE", "PERFORMANCE"]:
			in_scope = true
		elif in_scope and child is HBoxContainer:
			rows.append(child as HBoxContainer)
	return rows


func _tag(row: HBoxContainer) -> Label:
	var last: Node = row.get_child(row.get_child_count() - 1)
	return last as Label if last.has_meta(&"impact") else null


func test_every_image_and_performance_row_ends_in_a_rating() -> void:
	var rows: Array[HBoxContainer] = _rated_rows(_tab())
	assert_gt(rows.size(), 15, "the Image and Performance sections were found")
	for row: HBoxContainer in rows:
		var label: String = (row.get_child(0) as Label).text
		var tag: Label = _tag(row)
		assert_not_null(tag, "%s has no impact rating" % label)
		if tag != null:
			assert_false(tag.tooltip_text.is_empty(), "%s's rating explains nothing" % label)
			assert_eq(tag.mouse_filter, Control.MOUSE_FILTER_STOP,
					"%s's rating never shows its tooltip" % label)


func test_ratings_and_explanations_are_translated() -> void:
	for row: HBoxContainer in _rated_rows(_tab()):
		var tag: Label = _tag(row)
		if tag == null:
			continue
		assert_false(tag.text.contains("OPTIONS_"), "%s renders a raw key" % tag.text)
		assert_false(tag.tooltip_text.contains("OPTIONS_"),
				"%s renders a raw key" % tag.tooltip_text)


func test_the_explanation_wraps() -> void:
	var tag: Label = _tag(_rated_rows(_tab())[0])
	var tip: Label = tag._make_custom_tooltip(tag.tooltip_text) as Label
	assert_not_null(tip, "the rating builds its own tooltip")
	if tip != null:
		assert_ne(tip.autowrap_mode, TextServer.AUTOWRAP_OFF, "a long note runs off the screen")
		assert_gt(tip.custom_minimum_size.x, 0.0, "a wrapping label needs a width to wrap at")
		tip.free()
